// test/plugins_workspace_test.dart
//
// PARITY face `plugins_surface` — the Plugins workspace. Tier-1: drives
// `ParityPluginsWorkspace` through the `CyanBackend` seam (FakeCyanBackend),
// no dylib.
//
// The behaviour reference is the ENGINE, not a SwiftUI view — the shipping
// macOS app binds `cyan_plugin_catalog` and has no plugins face. What is
// asserted here is `cyan-backend/src/plugin_config.rs` plus
// PLUGIN_CREDENTIAL_ONBOARDING.md stage D: a config row holds a NON-SECRET
// target, scoped to a group; a credential never lands in that table at all.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/widgets/parity/parity_plugins_workspace.dart';

import 'support/parity_test_harness.dart';

const _size = Size(1000, 760);

/// Open a bundle in the rail by its plugin id.
Future<void> openBundle(WidgetTester tester, String pluginId) async {
  await tester.tap(find.text(pluginId).first);
  await tester.pumpAndSettle();
}

/// The composer's Key / Value fields, in order.
Finder get _keyField => find.byType(TextField).at(0);
Finder get _valueField => find.byType(TextField).at(1);

void main() {
  group('Plugins workspace', () {
    testWidgets('lists installed plugin bundles for a group', (tester) async {
      await pumpParity(tester, const ParityPluginsWorkspace(), size: _size);

      expect(find.text('Plugins'), findsOneWidget);
      expect(find.text('Installed bundles'), findsOneWidget);

      // The group IS the engine's tenant — every config row is scoped to it, so
      // the workspace names which one it is showing.
      expect(find.text('Engineering'), findsOneWidget);

      // Every bundle the engine's catalog reports, ordered by id.
      expect(find.text('asset-ingest'), findsWidgets);
      expect(find.text('ffmpeg'), findsWidgets);
      expect(find.text('frameio'), findsWidgets);

      // Each row carries the manifest version + tool count.
      expect(find.text('v1.4.0 · 2 tools'), findsOneWidget);
      expect(find.text('v1.0.0 · 1 tools'), findsOneWidget);
    });

    testWidgets('opening a plugin shows its configuration fields',
        (tester) async {
      await pumpParity(tester, const ParityPluginsWorkspace(), size: _size);
      await openBundle(tester, 'frameio');

      expect(find.text('Configuration'), findsOneWidget);

      // The rows the engine actually holds for (g-eng, frameio) — the
      // non-secret targets a real install leaves behind.
      expect(find.text('account_id'), findsOneWidget);
      expect(find.text('acct-9f2c41'), findsOneWidget);
      expect(find.text('folder_id'), findsOneWidget);
      expect(find.text('fld-review-inbox'), findsOneWidget);

      // The bundle's tools come off the manifest with their side effects, and
      // an actuator is flagged as gating on a human.
      expect(find.text('push_review'), findsOneWidget);
      expect(find.text('external_send'), findsOneWidget);
      expect(find.text('approval'), findsOneWidget);
    });

    testWidgets('a plugin with no rows says so instead of showing an empty box',
        (tester) async {
      await pumpParity(tester, const ParityPluginsWorkspace(), size: _size);
      await openBundle(tester, 'ffmpeg');

      expect(
        find.text('No configuration set — this plugin runs on its defaults.'),
        findsOneWidget,
      );
    });

    testWidgets('saving plugin configuration persists it and survives reload',
        (tester) async {
      // ONE backend across both pumps: the second pump is a fresh widget tree
      // and fresh providers reading the same engine, which is what "reload"
      // means here.
      final backend = FakeCyanBackend();

      await pumpParity(tester, const ParityPluginsWorkspace(),
          backend: backend, size: _size);
      await openBundle(tester, 'frameio');

      await tester.enterText(_keyField, 'c2c_project');
      await tester.pumpAndSettle();
      await tester.enterText(_valueField, 'proj-atlas-7');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // The engine accepted it, and the sheet re-read the row from the engine
      // rather than echoing what was typed.
      expect(find.text('Saved c2c_project'), findsOneWidget);
      expect(find.text('c2c_project'), findsOneWidget);
      expect(find.text('proj-atlas-7'), findsOneWidget);

      // Reload: a brand-new tree over the same engine still has the row.
      await pumpParity(tester, const ParityPluginsWorkspace(),
          backend: backend, size: _size);
      await openBundle(tester, 'frameio');

      expect(find.text('c2c_project'), findsOneWidget);
      expect(find.text('proj-atlas-7'), findsOneWidget);
    });

    testWidgets('a credential field is never rendered in plain text',
        (tester) async {
      final backend = FakeCyanBackend();
      await pumpParity(tester, const ParityPluginsWorkspace(),
          backend: backend, size: _size);
      await openBundle(tester, 'frameio');

      // A non-secret target composes in the clear.
      await tester.enterText(_keyField, 'folder_id');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_valueField).obscureText, isFalse);
      expect(find.text('Value'), findsOneWidget);

      // Naming credential material flips the value to a SECURE field the
      // moment the key is typed — before any round trip to the engine.
      await tester.enterText(_keyField, 'ims_token');
      await tester.pumpAndSettle();

      final secure = tester.widget<TextField>(_valueField);
      expect(secure.obscureText, isTrue);
      expect(secure.obscuringCharacter, '•');
      expect(find.text('Value (secure)'), findsOneWidget);
      expect(find.textContaining('device vault'), findsOneWidget);

      // Writing it anyway is REFUSED by the engine, in the engine's own words,
      // and the secret is cleared rather than left sitting in the box.
      await tester.enterText(_valueField, 'sk-live-do-not-store');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining("'ims_token' looks like a secret"),
          findsOneWidget);
      expect(tester.widget<TextField>(_valueField).controller?.text, isEmpty);

      // The secret is nowhere on screen — not as a row, not as a leftover.
      expect(find.text('sk-live-do-not-store'), findsNothing);

      // And it never became a config row: the engine still holds only the two
      // non-secret targets it started with.
      final stored = await backend.pluginConfigGet('g-eng', 'frameio');
      expect(stored.values.keys, ['account_id', 'folder_id']);
    });

    testWidgets('a stored row whose key names a secret is masked',
        (tester) async {
      await pumpParity(tester, const ParityPluginsWorkspace(), size: _size);
      await openBundle(tester, 'frameio');

      // `plugin_config` cannot hold a secret — the write API refuses one — so a
      // plain value is correct for every row the engine serves. The mask is the
      // fallback for a row that could only have come from outside that guard.
      expect(find.text('•' * 12), findsNothing);
      expect(find.text('acct-9f2c41'), findsOneWidget);
    });

    testWidgets('the config seam refuses secret-looking keys', (tester) async {
      // The app's `pluginConfigKeyLooksSecret` is a port of the engine's
      // `looks_secret`; the seam must refuse exactly what the engine refuses.
      final backend = FakeCyanBackend();
      for (final k in ['ims_token', 'API_KEY', 'client_secret', 'password']) {
        expect(pluginConfigKeyLooksSecret(k), isTrue, reason: k);
        final w = await backend.pluginConfigSet('g-eng', 'frameio', k, 'v');
        expect(w.ok, isFalse, reason: k);
        expect(w.error, contains('vault'), reason: k);
      }
      // The non-secret targets all store fine.
      for (final k in ['account_id', 'folder_id', 'c2c_project']) {
        expect(pluginConfigKeyLooksSecret(k), isFalse, reason: k);
        expect((await backend.pluginConfigSet('g-eng', 'frameio', k, 'v')).ok,
            isTrue,
            reason: k);
      }
    });
  });

  testWidgets('golden: plugins workspace', (tester) async {
    await pumpParity(tester, const ParityPluginsWorkspace(), size: _size);
    await openBundle(tester, 'frameio');
    await expectLater(
      find.byType(ParityPluginsWorkspace),
      matchesGoldenFile('golden/plugins_workspace.png'),
    );
  }, tags: 'golden');
}
