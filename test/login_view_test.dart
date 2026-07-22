// test/login_view_test.dart
//
// PARITY — Login / landing (the front door). Tier-1, fakes only: no native
// library, no network, no engine.
//
// This is the ACCEPTANCE ORACLE for the login parity area, authored from the
// SwiftUI reference at cyan-iOS `Cyan/Cyan/Views/Auth/LoginView.swift` (read
// only). That screen is the "two-mode front door":
//
//   • Personal / sovereign — create a XaeroID on this device (works fully
//     offline, no account, no network), or restore an existing one.
//   • Organization (SSO)   — an optional tenant, then sign in via the org's
//     IdP; the broker returns a signed, XaeroID-bound grant.
//
// The widget under test is presentational and pre-session by design: login
// happens BEFORE there is a backend session, so it takes callbacks rather than
// going through the `CyanBackend` seam. That keeps the whole area testable at
// Tier-1 with zero infrastructure.
//
// The supervisor runs this file itself; a worker agent makes it pass by writing
// `lib/widgets/parity/parity_login_view.dart`. Contract the widget must honour:
//
//   ParityLoginView({
//     Key? key,
//     String? errorMessage,          // renders in a notice box when non-null
//     bool isLoading = false,        // renders a progress indicator when true
//     VoidCallback? onCreateIdentity,
//     VoidCallback? onRestore,
//     void Function(String tenant)? onSsoSignIn,
//   })
//
// Required ValueKeys (the SwiftUI console disambiguates by
// accessibilityIdentifier for exactly the same reason):
//   login-mode-personal · login-mode-organization · login-create-identity
//   login-restore · login-org-field · login-sso-signin · login-error

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/widgets/parity/parity_login_view.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('renders the brand, the tagline and the two-mode picker',
      (tester) async {
    await pumpParity(tester, const ParityLoginView(),
        size: const Size(600, 800));

    // Brand block (the reference renders the brand mark + wordmark + tagline).
    expect(find.text('Cyan'), findsOneWidget);
    expect(find.text('Decentralized Collaboration'), findsOneWidget);

    // Both modes are offered.
    expect(find.byKey(const ValueKey('login-mode-personal')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('login-mode-organization')),
      findsOneWidget,
    );
  });

  testWidgets('personal mode is the default and offers create + restore',
      (tester) async {
    await pumpParity(tester, const ParityLoginView(),
        size: const Size(600, 800));

    // Sovereign identity is the default front door.
    expect(
      find.byKey(const ValueKey('login-create-identity')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('login-restore')), findsOneWidget);

    // The offline promise is the whole point of this mode — it must be stated.
    expect(find.textContaining('offline'), findsWidgets);

    // The organization field belongs to the OTHER mode.
    expect(find.byKey(const ValueKey('login-org-field')), findsNothing);
  });

  testWidgets('creating an identity fires its callback', (tester) async {
    var created = 0;
    await pumpParity(
      tester,
      ParityLoginView(onCreateIdentity: () => created++),
      size: const Size(600, 800),
    );

    await tester.tap(find.byKey(const ValueKey('login-create-identity')));
    await tester.pumpAndSettle();
    expect(created, 1);
  });

  testWidgets('switching to organization reveals the tenant field + SSO',
      (tester) async {
    await pumpParity(tester, const ParityLoginView(),
        size: const Size(600, 800));

    await tester.tap(find.byKey(const ValueKey('login-mode-organization')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('login-org-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-sso-signin')), findsOneWidget);

    // Personal-mode actions are gone in this mode.
    expect(find.byKey(const ValueKey('login-create-identity')), findsNothing);
  });

  testWidgets('SSO sign-in reports the organization that was typed',
      (tester) async {
    String? tenant;
    await pumpParity(
      tester,
      ParityLoginView(onSsoSignIn: (t) => tenant = t),
      size: const Size(600, 800),
    );

    await tester.tap(find.byKey(const ValueKey('login-mode-organization')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('login-org-field')),
      'acme',
    );
    await tester.tap(find.byKey(const ValueKey('login-sso-signin')));
    await tester.pumpAndSettle();

    expect(tenant, 'acme');
  });

  testWidgets('an error is surfaced in a notice box', (tester) async {
    await pumpParity(
      tester,
      const ParityLoginView(errorMessage: 'could not reach the broker'),
      size: const Size(600, 800),
    );

    expect(find.byKey(const ValueKey('login-error')), findsOneWidget);
    expect(find.text('could not reach the broker'), findsOneWidget);
  });

  testWidgets('no error box when there is no error', (tester) async {
    await pumpParity(tester, const ParityLoginView(),
        size: const Size(600, 800));
    expect(find.byKey(const ValueKey('login-error')), findsNothing);
  });

  testWidgets('the loading state shows progress', (tester) async {
    await pumpParity(
      tester,
      const ParityLoginView(isLoading: true),
      size: const Size(600, 800),
    );
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });
}
