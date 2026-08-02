// providers/onboarding_session_provider.dart
//
// The ONBOARDING spine — the state behind the front door, ported from the
// SwiftUI `IdentitySessionViewModel` (login / logout) plus the two entry paths
// `LoginView.swift` offers:
//
//   • Organization sign-in — the broker mints a signed, XaeroID-bound grant;
//     the ENGINE verifies and installs it (`cyan_sso_install_grant`). What lands
//     on screen is the tenant + role the engine resolved, never a hint the
//     client typed.
//   • Anonymous entry — the sovereign path. No account, no org, no tenant: the
//     ENGINE mints an ephemeral handle (`cyan_create_anonymous_session`) and the
//     device enters behind it.
//
// Both reads and writes go through the ONE `CyanBackend` seam, so the whole
// face drives off `FakeCyanBackend` in a widget test with no dylib. The network
// leg — talking to the org's IdP — is the separate `SsoGrantBroker` seam, for
// the same reason the marketplace's download leg is separate from its install.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Views/Auth/LoginView.swift
//   cyan-iOS/Cyan/Cyan/Views/Auth/SSOLoginView.swift
//   cyan-iOS/Cyan/Cyan/Views/ProfileView.swift
//   cyan-iOS/Cyan/Cyan/ViewModels/IdentitySessionViewModel.swift

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/cyan_backend.dart';
import '../ffi/parity_models.dart';
import '../services/sso_grant_broker.dart';
import 'cyan_backend_provider.dart';

/// The broker leg. Overridden in tests with a broker that mints grants offline.
final ssoGrantBrokerProvider =
    Provider<SsoGrantBroker>((ref) => LensSsoGrantBroker());

/// Where the front door's anonymous entry is scoped.
///
/// The engine's anonymity is per SCOPE (a board / workspace id) — a device can
/// be masked on one board and visible on another. Entering the APP anonymously
/// is the shell-wide scope, so it gets one named id rather than a scope
/// invented per screen. Boards that mask separately keep their own.
const String kAnonymousEntryScope = 'cyan-shell';

/// Which of the three states the front door is in.
enum OnboardingPhase {
  /// No session — the login surface is what the user sees.
  signedOut,

  /// A sign-in or an anonymous entry is in flight.
  signingIn,

  /// A session exists; the app is open.
  signedIn,
}

/// Everything the front door knows, read in ONE object so a tenant from before
/// a sign-out can never sit next to a profile from after it.
@immutable
class OnboardingSession {
  final OnboardingPhase phase;

  /// The installed organization grant. Null for an anonymous entry — that path
  /// has no org and therefore no tenant.
  final SsoSession? sso;

  /// The device identity the sign-in captured, straight from the engine
  /// (`myProfile`). Null for an anonymous entry: the whole point of the mask is
  /// that the real profile is not what is presented.
  final DeviceProfile? profile;

  /// The ephemeral session behind an anonymous entry, carrying the handle the
  /// ENGINE minted. Null for an organization sign-in.
  final AnonymousSession? anonymous;

  /// The last attempt's plain-language failure, shown in the login notice box.
  final String? error;

  const OnboardingSession({
    this.phase = OnboardingPhase.signedOut,
    this.sso,
    this.profile,
    this.anonymous,
    this.error,
  });

  bool get isSignedIn => phase == OnboardingPhase.signedIn;
  bool get isBusy => phase == OnboardingPhase.signingIn;

  /// True when the session in hand is the masked one.
  bool get isAnonymous => anonymous != null;

  /// The organization this device is signed in to, as the ENGINE resolved it.
  /// Empty when signed out or entered anonymously.
  String get tenant => sso?.active == true ? sso!.tenant : '';

  /// The role the grant confers, in the engine's own vocabulary. Empty when
  /// there is no organization session.
  String get role => sso?.active == true ? sso!.role : '';

  /// The one name to put on screen for this session: the engine's profile
  /// label when signed in for real, the minted handle when masked.
  String get displayLabel {
    if (anonymous != null) return anonymous!.handle;
    return profile?.label ?? '';
  }
}

final onboardingSessionProvider =
    StateNotifierProvider<OnboardingSessionController, OnboardingSession>((ref) {
  return OnboardingSessionController(
    backend: ref.watch(cyanBackendProvider),
    broker: ref.watch(ssoGrantBrokerProvider),
  );
});

class OnboardingSessionController extends StateNotifier<OnboardingSession> {
  final CyanBackend _backend;
  final SsoGrantBroker _broker;

  OnboardingSessionController({
    required CyanBackend backend,
    required SsoGrantBroker broker,
  })  : _backend = backend,
        _broker = broker,
        super(const OnboardingSession());

  /// "Sign in with your organization." Broker → engine → session.
  ///
  /// [tenant] is a HINT and may be empty, in which case the broker resolves the
  /// organization itself. The tenant that ends up on screen is always the one
  /// the ENGINE read out of the verified grant.
  ///
  /// No-throw: every failure lands as [OnboardingSession.error] with the phase
  /// back at [OnboardingPhase.signedOut], never as a crash.
  Future<void> signInWithOrganization(String tenant) async {
    if (state.isBusy) return;
    state = OnboardingSession(phase: OnboardingPhase.signingIn);

    final hint = tenant.trim();
    try {
      await _backend.initialize();

      // The grant BINDS to this device's identity, so there must be one to bind
      // to. A device with no identity is refused plainly rather than signed in
      // against an identity we invented here.
      final identity = await _backend.myProfile();
      if (identity == null) {
        _fail('This device has no identity yet — create one before signing in '
            'with an organization.');
        return;
      }

      final BrokerGrant grant;
      try {
        grant = await _broker.signIn(
          tenant: hint,
          xaeroPublicKeyHex: identity.nodeId,
        );
      } on SsoSignInUnavailable catch (e) {
        _fail('Sign-in failed — ${e.message}.');
        return;
      }

      // The ENGINE verifies the signature and the binding. A refusal carries
      // its own reason and leaves any previous session untouched.
      final session =
          await _backend.ssoInstallGrant(grant.grantToken, grant.trustJson);
      if (!session.active) {
        _fail('Sign-in failed — ${session.reason ?? 'the grant was refused'}.');
        return;
      }

      // Tenant isolation: a grant that resolved a DIFFERENT organization than
      // the one asked for is not this user's session. Drop it rather than open
      // the app on someone else's tenant.
      if (hint.isNotEmpty && session.tenant != hint) {
        await _backend.ssoSignOut();
        _fail('Sign-in failed — this account belongs to a different '
            'organization.');
        return;
      }

      // Re-read the profile AFTER the install: the engine is the source of
      // truth for what the session captured, not the copy we read a moment ago
      // to bind the grant.
      final profile = await _backend.myProfile();
      if (!mounted) return;
      state = OnboardingSession(
        phase: OnboardingPhase.signedIn,
        sso: session,
        profile: profile ?? identity,
      );
    } catch (e) {
      _fail('Sign-in failed — $e.');
    }
  }

  /// The sovereign path: enter with no account and no organization. The ENGINE
  /// mints the handle the device is seen behind — callers never invent one.
  Future<void> enterAnonymously() async {
    if (state.isBusy) return;
    state = OnboardingSession(phase: OnboardingPhase.signingIn);

    try {
      await _backend.initialize();
      final session = await _backend.createAnonymousSession(kAnonymousEntryScope);
      if (session == null) {
        _fail('Could not enter anonymously — this device has already been '
            'revealed here.');
        return;
      }
      if (!mounted) return;
      state = OnboardingSession(
        phase: OnboardingPhase.signedIn,
        anonymous: session,
      );
    } catch (e) {
      _fail('Could not enter anonymously — $e.');
    }
  }

  /// Sign out: clear whichever session is installed and return the front door
  /// to its signed-out state.
  ///
  /// This is NOT a wipe. The device's XaeroID stays in the vault — signing out
  /// drops the org grant / the mask, exactly as the SwiftUI `logout()` does.
  /// Wiping the identity is `deleteIdentity`, a separate destructive action
  /// that lives in Settings.
  Future<void> signOut() async {
    if (state.sso?.active == true) {
      await _backend.ssoSignOut();
    }
    if (state.anonymous != null) {
      await _backend.exitAnonymousMode(state.anonymous!.scopeId);
    }
    if (!mounted) return;
    state = const OnboardingSession();
  }

  void _fail(String message) {
    if (!mounted) return;
    state = OnboardingSession(
      phase: OnboardingPhase.signedOut,
      error: message,
    );
  }
}
