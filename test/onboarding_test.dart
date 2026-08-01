// test/onboarding_test.dart
//
// PARITY — Onboarding: the front door driven end to end. Tier-1, fakes only:
// no native library, no lens, no IdP, no network.
//
// `login_view_test.dart` is the oracle for the login SURFACE (what it renders,
// which callbacks it fires). This file is the oracle for the front-door SPINE:
// what actually happens when those callbacks are taken — a grant is brokered,
// the ENGINE verifies and installs it, the session captures what the engine
// resolved, and signing out puts the login surface back.
//
// Ported from the SwiftUI reference (read-only):
//   Cyan/Cyan/Views/Auth/LoginView.swift          — the two-mode front door
//   Cyan/Cyan/Views/Auth/SSOLoginView.swift       — the SSO sign-in surface
//   Cyan/Cyan/Views/ProfileView.swift             — the signed-in panel + Sign Out
//   Cyan/Cyan/ViewModels/IdentitySessionViewModel.swift — login / logout

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/providers/onboarding_session_provider.dart';
import 'package:cyan_flutter/services/sso_grant_broker.dart';
import 'package:cyan_flutter/widgets/parity/parity_onboarding_gate.dart';

import 'support/parity_test_harness.dart';

// ---------------------------------------------------------------------------
// The broker leg, faked
// ---------------------------------------------------------------------------

/// Mints grants the way the lens broker would, with no network. The trust
/// material it hands back is the real shape `CyanBackend.ssoInstallGrant`
/// verifies against, so the ENGINE half of the flow is exercised for real.
class FakeSsoGrantBroker implements SsoGrantBroker {
  /// The organization the broker RESOLVES. Null ⇒ it resolves whatever tenant
  /// was asked for (and `_defaultTenant` when nothing was).
  String? resolvedTenant;

  /// When set, every sign-in fails with this reason instead of minting.
  String? failWith;

  /// Drop the trust material, so the engine has nothing to verify the grant
  /// against and must refuse it.
  bool omitTrustMaterial = false;

  /// The last binding the broker was asked to mint against.
  String? lastXaeroPublicKeyHex;
  String? lastTenantHint;

  static const String _defaultTenant = 'cyan';

  @override
  Future<BrokerGrant> signIn({
    required String tenant,
    required String xaeroPublicKeyHex,
  }) async {
    lastTenantHint = tenant;
    lastXaeroPublicKeyHex = xaeroPublicKeyHex;
    final failure = failWith;
    if (failure != null) throw SsoSignInUnavailable(failure);

    final resolved =
        resolvedTenant ?? (tenant.isEmpty ? _defaultTenant : tenant);
    return BrokerGrant(
      grantToken: 'grant-for-$resolved',
      trustJson: jsonEncode({
        'tenant': resolved,
        if (!omitTrustMaterial) 'org_did': 'did:cyan:$resolved',
        'grace_secs': 604800,
      }),
    );
  }
}

/// Pump the gate with both seams faked.
Future<void> pumpGate(
  WidgetTester tester, {
  FakeCyanBackend? backend,
  FakeSsoGrantBroker? broker,
}) {
  return pumpParity(
    tester,
    const ParityOnboardingGate(),
    backend: backend ?? FakeCyanBackend(),
    size: const Size(600, 800),
    overrides: [
      ssoGrantBrokerProvider
          .overrideWithValue(broker ?? FakeSsoGrantBroker()),
    ],
  );
}

/// Drive the organization half of the front door: switch modes, type the
/// tenant, take the sign-in.
Future<void> signInWithOrganization(WidgetTester tester, String tenant) async {
  await tester.tap(find.byKey(const ValueKey('login-mode-organization')));
  await tester.pumpAndSettle();
  if (tenant.isNotEmpty) {
    await tester.enterText(find.byKey(const ValueKey('login-org-field')), tenant);
  }
  await tester.tap(find.byKey(const ValueKey('login-sso-signin')));
  await tester.pumpAndSettle();
}

void main() {
  // -------------------------------------------------------------------------
  // Behaviour 1 — the two entry paths
  // -------------------------------------------------------------------------

  testWidgets('the login surface offers sign in and anonymous entry',
      (tester) async {
    await pumpGate(tester);

    // The front door opens signed OUT, on the login surface.
    expect(find.byKey(const ValueKey('onboarding-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-profile')), findsNothing);

    // ANONYMOUS ENTRY — the sovereign default: no account, no organization.
    expect(find.byKey(const ValueKey('login-create-identity')), findsOneWidget);
    expect(find.textContaining('no account'), findsWidgets);

    // SIGN IN — the organization half is one mode switch away.
    expect(
      find.byKey(const ValueKey('login-mode-organization')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('login-mode-organization')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-sso-signin')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-org-field')), findsOneWidget);
  });

  testWidgets('anonymous entry opens the app behind an engine-minted handle',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpGate(tester, backend: backend);

    await tester.tap(find.byKey(const ValueKey('login-create-identity')));
    await tester.pumpAndSettle();

    // We are in — and the login surface is gone.
    expect(find.byKey(const ValueKey('session-profile')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-login')), findsNothing);

    // The ENGINE minted the handle; the client never invents one. Assert
    // against what the engine actually holds for the shell scope.
    final status = await backend.getAnonymousStatus(kAnonymousEntryScope);
    expect(status.anonymous, isTrue);
    expect(status.handle, isNotNull);
    expect(find.byKey(const ValueKey('session-anonymous-handle')), findsOneWidget);
    // The handle is what the panel puts on screen — as the session's name at
    // the top, and again in the Handle row.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('session-anonymous-handle')),
        matching: find.text(status.handle!),
      ),
      findsOneWidget,
    );

    // Anonymous entry has NO organization — so no tenant row at all.
    expect(find.byKey(const ValueKey('session-tenant')), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Behaviour 2 — what a sign-in captures
  // -------------------------------------------------------------------------

  testWidgets('a successful sign in captures tenant and profile',
      (tester) async {
    final backend = FakeCyanBackend();
    final broker = FakeSsoGrantBroker();
    await pumpGate(tester, backend: backend, broker: broker);

    await signInWithOrganization(tester, 'acme');

    // Signed in: the login surface is replaced by the identity panel.
    expect(find.byKey(const ValueKey('onboarding-login')), findsNothing);
    expect(find.byKey(const ValueKey('session-profile')), findsOneWidget);

    // TENANT — the organization the ENGINE resolved out of the verified grant.
    expect(find.byKey(const ValueKey('session-tenant')), findsOneWidget);
    expect(find.text('acme'), findsOneWidget);

    // PROFILE — the device identity, straight from `myProfile`.
    final profile = await backend.myProfile();
    expect(profile, isNotNull);
    expect(find.text(profile!.label), findsOneWidget);
    expect(find.byKey(const ValueKey('session-node')), findsOneWidget);
    expect(find.text(profile.nodeId), findsOneWidget);

    // The grant was BOUND to that identity — a grant lifted onto another
    // device would not verify.
    expect(broker.lastXaeroPublicKeyHex, profile.nodeId);

    // And the engine stamped a role on the session.
    expect(find.byKey(const ValueKey('session-role')), findsOneWidget);
  });

  testWidgets('an empty organization lets the broker resolve the tenant',
      (tester) async {
    final broker = FakeSsoGrantBroker();
    await pumpGate(tester, broker: broker);

    // No hint typed — the SwiftUI `tenantHint: nil` path.
    await signInWithOrganization(tester, '');

    expect(broker.lastTenantHint, '');
    expect(find.byKey(const ValueKey('session-tenant')), findsOneWidget);
    expect(find.text('cyan'), findsOneWidget);
  });

  testWidgets('a grant for a different organization is refused', (tester) async {
    final backend = FakeCyanBackend();
    // The broker resolves globex while the user asked for acme.
    final broker = FakeSsoGrantBroker()..resolvedTenant = 'globex';
    await pumpGate(tester, backend: backend, broker: broker);

    await signInWithOrganization(tester, 'acme');

    // Tenant isolation: we stay OUT rather than opening on someone else's org.
    expect(find.byKey(const ValueKey('session-profile')), findsNothing);
    expect(find.byKey(const ValueKey('login-error')), findsOneWidget);
    expect(find.textContaining('different organization'), findsOneWidget);

    // And the foreign session was dropped from the engine, not left installed.
    final reinstalled = await backend.ssoInstallGrant(
        'grant-for-globex', jsonEncode({'tenant': 'globex', 'org_did': 'x'}));
    expect(reinstalled.active, isTrue,
        reason: 'a fresh install proves nothing was left behind');
  });

  testWidgets('a grant the engine cannot verify leaves the device signed out',
      (tester) async {
    // No trust material — the engine has nothing to check the grant against.
    final broker = FakeSsoGrantBroker()..omitTrustMaterial = true;
    await pumpGate(tester, broker: broker);

    await signInWithOrganization(tester, 'acme');

    expect(find.byKey(const ValueKey('session-profile')), findsNothing);
    expect(find.byKey(const ValueKey('login-error')), findsOneWidget);
    // The ENGINE's own reason is what the user is shown.
    expect(find.textContaining('no trust material'), findsOneWidget);
  });

  testWidgets('an unreachable broker is reported, not crashed on',
      (tester) async {
    final broker = FakeSsoGrantBroker()
      ..failWith = 'the broker is unreachable at http://localhost:8080';
    await pumpGate(tester, broker: broker);

    await signInWithOrganization(tester, 'acme');

    expect(find.byKey(const ValueKey('session-profile')), findsNothing);
    expect(find.byKey(const ValueKey('login-error')), findsOneWidget);
    expect(find.textContaining('unreachable'), findsOneWidget);
  });

  testWidgets('a device with no identity cannot bind an organization grant',
      (tester) async {
    // A fresh install / post-wipe device: nothing for the grant to bind to.
    final backend = FakeCyanBackend()..profile = null;
    final broker = FakeSsoGrantBroker();
    await pumpGate(tester, backend: backend, broker: broker);

    await signInWithOrganization(tester, 'acme');

    expect(find.byKey(const ValueKey('session-profile')), findsNothing);
    expect(find.byKey(const ValueKey('login-error')), findsOneWidget);
    expect(find.textContaining('no identity'), findsOneWidget);
    // The broker was never even asked — there was nothing to bind.
    expect(broker.lastXaeroPublicKeyHex, isNull);
  });

  // -------------------------------------------------------------------------
  // Behaviour 3 — sign-out
  // -------------------------------------------------------------------------

  testWidgets('signing out returns to the login surface', (tester) async {
    final backend = FakeCyanBackend();
    await pumpGate(tester, backend: backend);

    await signInWithOrganization(tester, 'acme');
    expect(find.byKey(const ValueKey('session-profile')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('session-sign-out')));
    await tester.pumpAndSettle();

    // Back at the front door, with both entry paths on offer again.
    expect(find.byKey(const ValueKey('onboarding-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-profile')), findsNothing);
    expect(find.byKey(const ValueKey('login-create-identity')), findsOneWidget);

    // A stale error from before the session does not follow us back out.
    expect(find.byKey(const ValueKey('login-error')), findsNothing);
  });

  testWidgets('signing out of an anonymous entry drops the engine session',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpGate(tester, backend: backend);

    await tester.tap(find.byKey(const ValueKey('login-create-identity')));
    await tester.pumpAndSettle();
    expect((await backend.getAnonymousStatus(kAnonymousEntryScope)).anonymous,
        isTrue);

    await tester.tap(find.byKey(const ValueKey('session-sign-out')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('onboarding-login')), findsOneWidget);
    // The mask was dropped in the engine too — not just hidden client-side.
    expect((await backend.getAnonymousStatus(kAnonymousEntryScope)).anonymous,
        isFalse);
  });

  testWidgets('signing out does not wipe the identity from the vault',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpGate(tester, backend: backend);

    await signInWithOrganization(tester, 'acme');
    await tester.tap(find.byKey(const ValueKey('session-sign-out')));
    await tester.pumpAndSettle();

    // Sign-out is not a wipe: the XaeroID stays. `deleteIdentity` is the
    // destructive action, and it lives in Settings, not here.
    expect(await backend.myProfile(), isNotNull);
  });

  testWidgets('signing back in after a sign-out works', (tester) async {
    await pumpGate(tester);

    await signInWithOrganization(tester, 'acme');
    await tester.tap(find.byKey(const ValueKey('session-sign-out')));
    await tester.pumpAndSettle();

    await signInWithOrganization(tester, 'acme');
    expect(find.byKey(const ValueKey('session-profile')), findsOneWidget);
    expect(find.text('acme'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // The gate's other half: it hands the app over once there is a session.
  // -------------------------------------------------------------------------

  testWidgets('the gate shows the app once a session exists', (tester) async {
    await pumpParity(
      tester,
      const ParityOnboardingGate(
        child: Text('the app', key: ValueKey('app-body')),
      ),
      backend: FakeCyanBackend(),
      size: const Size(600, 800),
      overrides: [
        ssoGrantBrokerProvider.overrideWithValue(FakeSsoGrantBroker()),
      ],
    );

    // Signed out, the child is withheld — the front door comes first.
    expect(find.byKey(const ValueKey('app-body')), findsNothing);
    expect(find.byKey(const ValueKey('onboarding-login')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('login-create-identity')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-body')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-login')), findsNothing);
  });
}
