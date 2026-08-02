// services/sso_grant_broker.dart
//
// The BROKER leg of an organization sign-in, ported from the SwiftUI app's
// `SSOGrantBroker` / `LensSSOGrantBroker` (ViewModels/IdentitySessionViewModel
// .swift, `signInWithOrganization`).
//
// A sign-in is two legs and they live in two different places — the same split
// the marketplace install uses (see `PluginBundleFetcher`):
//
//   1. BROKER — drive the org's IdP and come back with a signed, expiring grant
//      that is BOUND to this device's XaeroID, plus the trust material the
//      grant must verify against. That is THIS file. It is deliberately NOT on
//      the `CyanBackend` seam: the engine never talks to an IdP, the client
//      does.
//   2. INSTALL — hand the grant + trust to the engine, which VERIFIES the
//      signature and the binding before any session exists. That is
//      `CyanBackend.ssoInstallGrant`.
//
// Keeping the network leg behind an interface is what makes the whole front
// door drivable in a widget test with no lens, no IdP and no dylib.

import 'dart:convert';
import 'dart:io';

/// What the broker hands back: the grant the engine installs, and the trust
/// material it is verified against.
///
/// The client NEVER inspects the grant — it cannot verify it, only the engine
/// can. It carries both halves across to `ssoInstallGrant` verbatim.
class BrokerGrant {
  /// The broker-minted, XaeroID-bound session grant.
  final String grantToken;

  /// `{"tenant":…,"org_did":…|null,"legacy_rsa_public_pem":…|null,
  /// "grace_secs":N}` — the engine's verification input, passed through
  /// verbatim.
  final String trustJson;

  const BrokerGrant({required this.grantToken, required this.trustJson});
}

/// Drives the organization's IdP and mints a grant bound to this device.
abstract class SsoGrantBroker {
  /// Sign in to [tenant] — an EMPTY tenant means "no hint": the broker resolves
  /// the organization from the IdP itself, exactly as the SwiftUI
  /// `signInWithOrganization(tenantHint: nil, …)` path does.
  ///
  /// [xaeroPublicKeyHex] is this device's identity; the grant is bound to it so
  /// a grant lifted off one device is worthless on another.
  ///
  /// Throws [SsoSignInUnavailable] when the sign-in cannot be completed — the
  /// caller turns that into a terminal login error, never a crash.
  Future<BrokerGrant> signIn({
    required String tenant,
    required String xaeroPublicKeyHex,
  });
}

/// The sign-in could not be completed. Carries the plain-language reason the
/// login surface shows.
class SsoSignInUnavailable implements Exception {
  final String message;
  const SsoSignInUnavailable(this.message);

  @override
  String toString() => message;
}

/// `POST {lens}/api/v1/sso/grant` — the broker half of the lens SSO endpoint.
///
/// Reaches the SAME lens the rest of the app does: `CYAN_LENS_URL` when the
/// launcher sets it, else `http://localhost:8080` (the macOS app's
/// `LensConfig.baseURL` default). Needs a reachable lens — offline it throws
/// [SsoSignInUnavailable] and the login surface reports that, which is the
/// point at which the SwiftUI app falls back to the sovereign XaeroID path.
class LensSsoGrantBroker implements SsoGrantBroker {
  static const String defaultBaseUrl = 'http://localhost:8080';

  final String baseUrl;
  final HttpClient Function() _newClient;

  LensSsoGrantBroker({String? baseUrl, HttpClient Function()? newClient})
      : baseUrl = baseUrl ?? _envBaseUrl(),
        _newClient = newClient ?? HttpClient.new;

  static String _envBaseUrl() {
    final v = Platform.environment['CYAN_LENS_URL']?.trim() ?? '';
    return v.isEmpty ? defaultBaseUrl : v;
  }

  @override
  Future<BrokerGrant> signIn({
    required String tenant,
    required String xaeroPublicKeyHex,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/sso/grant');
    final client = _newClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      // An empty tenant is sent as absent — "resolve it yourself" — rather than
      // as an empty string the broker would try to match a tenant against.
      request.write(jsonEncode({
        if (tenant.isNotEmpty) 'tenant': tenant,
        'xaero_public_key': xaeroPublicKeyHex,
      }));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        throw const SsoSignInUnavailable(
            'your organization did not authorize this device');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw SsoSignInUnavailable(
            'the broker answered HTTP ${response.statusCode}');
      }

      final Object? decoded;
      try {
        decoded = jsonDecode(body);
      } catch (_) {
        throw const SsoSignInUnavailable(
            'the broker returned a response that could not be read');
      }
      if (decoded is! Map<String, dynamic>) {
        throw const SsoSignInUnavailable(
            'the broker returned a response that could not be read');
      }

      final grantToken = decoded['grant_token'] as String? ?? '';
      if (grantToken.isEmpty) {
        throw const SsoSignInUnavailable('the broker returned no grant');
      }
      // The trust material rides through UNTOUCHED — re-encoding the engine's
      // verification input through a Dart model would be a place for it to
      // drift from what was actually signed.
      final trust = decoded['trust'];
      if (trust is! Map<String, dynamic>) {
        throw const SsoSignInUnavailable(
            'the broker returned no trust material');
      }
      return BrokerGrant(grantToken: grantToken, trustJson: jsonEncode(trust));
    } on SsoSignInUnavailable {
      rethrow;
    } on SocketException catch (e) {
      throw SsoSignInUnavailable('the broker is unreachable at $baseUrl '
          '(${e.osError?.message ?? e.message})');
    } on HttpException catch (e) {
      throw SsoSignInUnavailable(e.message);
    } finally {
      client.close(force: true);
    }
  }
}
