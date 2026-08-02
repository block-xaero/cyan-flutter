// services/plugin_bundle_fetcher.dart
//
// The DOWNLOAD leg of a marketplace install, ported from the SwiftUI app's
// `PluginBundleFetching` / `CyanLensBundleFetcher` (ViewModels/
// MarketplaceViewModel.swift).
//
// An install is two legs and they live in two different places:
//   1. FETCH — pull the signed `.cyanplugin` bytes from the lens over HTTP.
//      That is THIS file. It is deliberately NOT on the `CyanBackend` seam:
//      the engine never downloads, the client does.
//   2. LAND — hand those bytes to the engine, which verifies the bundle layout
//      and signature before anything is written. That is
//      `CyanBackend.installPluginBundle`.
//
// The seam is an interface so the storefront's install flow is drivable in a
// widget test with no lens running — the same split the macOS app uses.

import 'dart:convert';
import 'dart:io';

/// Fetches the raw signed `.cyanplugin` bytes for a plugin, base64-encoded the
/// way `CyanBackend.installPluginBundle` wants them.
abstract class PluginBundleFetcher {
  /// The bundle bytes for [bundleId], base64. Throws
  /// [PluginBundleUnavailable] when the bytes cannot be had — the caller turns
  /// that into the install's terminal failure, never a crash.
  Future<String> fetchBundleB64(String bundleId);
}

/// The download could not be completed. Carries the plain-language reason the
/// install banner shows.
class PluginBundleUnavailable implements Exception {
  final String message;
  const PluginBundleUnavailable(this.message);

  @override
  String toString() => message;
}

/// `GET {lens}/api/v1/marketplace/bundle/{bundle_id}` — the download half of
/// the lens marketplace endpoint whose browse half feeds the storefront.
///
/// Reaches the SAME lens the rest of the app does: `CYAN_LENS_URL` when the
/// launcher sets it, else `http://localhost:8080` (the macOS app's
/// `LensConfig.baseURL` default, read there off the `cyan_lens_url` default).
/// Needs a running lens — offline it throws [PluginBundleUnavailable] and the
/// storefront reports that as the install's terminal result.
class LensPluginBundleFetcher implements PluginBundleFetcher {
  static const String defaultBaseUrl = 'http://localhost:8080';

  final String baseUrl;
  final HttpClient Function() _newClient;

  LensPluginBundleFetcher({String? baseUrl, HttpClient Function()? newClient})
      : baseUrl = baseUrl ?? _envBaseUrl(),
        _newClient = newClient ?? HttpClient.new;

  static String _envBaseUrl() {
    final v = Platform.environment['CYAN_LENS_URL']?.trim() ?? '';
    return v.isEmpty ? defaultBaseUrl : v;
  }

  @override
  Future<String> fetchBundleB64(String bundleId) async {
    // The bundle id is ONE path segment (the lens rejects `..` and `/`);
    // encode it so a namespaced id can neither traverse nor split the path.
    final uri = Uri.parse(
        '$baseUrl/api/v1/marketplace/bundle/${Uri.encodeComponent(bundleId)}');
    final client = _newClient();
    try {
      final response = await (await client.getUrl(uri)).close();
      if (response.statusCode != HttpStatus.ok) {
        throw PluginBundleUnavailable(
            'the lens answered HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      if (bytes.isEmpty) {
        throw const PluginBundleUnavailable(
            'the lens returned an empty bundle');
      }
      return base64.encode(bytes);
    } on PluginBundleUnavailable {
      rethrow;
    } on SocketException catch (e) {
      throw PluginBundleUnavailable('the lens is unreachable at $baseUrl '
          '(${e.osError?.message ?? e.message})');
    } on HttpException catch (e) {
      throw PluginBundleUnavailable(e.message);
    } finally {
      client.close(force: true);
    }
  }
}
