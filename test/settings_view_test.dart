// test/settings_view_test.dart
//
// PARITY face `settings_identity` — Settings. Tier-1: drives `ParitySettingsView`
// through the `CyanBackend` seam (FakeCyanBackend) and asserts the shell, the
// preference round trip (craft role + anonymous mode written through the seam
// and READ BACK off the engine), the group transfer tab and the identity tab.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/widgets/parity/parity_settings_view.dart';

import 'support/parity_test_harness.dart';

const Size _panel = Size(880, 760);

void main() {
  testWidgets('settings renders and persists user preferences',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParitySettingsView(scopeId: 'b-eng-1'),
        backend: backend, size: _panel);

    // The shell: header + the sidebar tabs.
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('Identity'), findsOneWidget);

    // The craft-role vocabulary is the ENGINE's — the screen carries no copy.
    expect(find.byKey(const ValueKey('settings-role-editor')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('settings-role-colorist')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('settings-role-current')))
          .data,
      'unset',
    );

    // Pick a role: it is WRITTEN through the seam…
    await tester.tap(find.byKey(const ValueKey('settings-role-editor')));
    await tester.pumpAndSettle();
    expect(await backend.getProductionRole(), 'editor');

    // …and read BACK off the engine onto the screen.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('settings-role-current')))
          .data,
      'editor',
    );
    expect(find.byKey(const ValueKey('settings-pref-notice')), findsOneWidget);

    // A fresh mount reads the PERSISTED pref, not leftover widget state.
    await pumpParity(tester, const ParitySettingsView(scopeId: 'b-eng-1'),
        backend: backend, size: _panel);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('settings-role-current')))
          .data,
      'editor',
    );
  });

  testWidgets('anonymous mode is per scope and reveals one way',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParitySettingsView(scopeId: 'b-eng-1'),
        backend: backend, size: _panel);

    // Visible by default — this device's own profile label.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('settings-anon-status')))
          .data,
      'Visible as Ada Byron',
    );

    // Mask: the engine mints the session and the handle comes back from it.
    await tester.tap(find.byKey(const ValueKey('settings-anon-toggle')));
    await tester.pumpAndSettle();
    final masked = tester
        .widget<Text>(find.byKey(const ValueKey('settings-anon-status')))
        .data!;
    expect(masked, startsWith('Masked as '));
    expect((await backend.getAnonymousStatus('b-eng-1')).anonymous, isTrue);

    // Revealing binds the handle to this device — and is one-way.
    await tester.tap(find.byKey(const ValueKey('settings-anon-reveal')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Revealed'), findsOneWidget);
    expect((await backend.getAnonymousStatus('b-eng-1')).revealed, isTrue);
  });

  testWidgets('the groups tab exports a bundle and imports it back',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParitySettingsView(),
        backend: backend, size: _panel);

    await tester.tap(find.byKey(const ValueKey('settings-tab-groups')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-export-g-eng')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-export-run')));
    await tester.pumpAndSettle();

    // The engine drops its own copy of the signed bundle.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('settings-export-status')))
          .data,
      startsWith('Saved to '),
    );

    // The exported body round-trips back in — signature + scope verify.
    await tester.tap(find.byKey(const ValueKey('settings-import-run')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('settings-import-status')))
          .data,
      'Imported g-eng',
    );
  });

  testWidgets('the identity tab shows this device and can wipe it',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParitySettingsView(),
        backend: backend, size: _panel);

    await tester.tap(find.byKey(const ValueKey('settings-tab-identity')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('settings-identity-node')))
          .data,
      'node-fake-local',
    );

    // Destructive, so it is confirmed first — and then it really wipes.
    await tester.tap(find.byKey(const ValueKey('settings-identity-delete')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('settings-identity-delete-confirm')));
    await tester.pumpAndSettle();

    expect(await backend.myProfile(), isNull);
    expect(
        find.byKey(const ValueKey('settings-identity-none')), findsOneWidget);
  });
}
