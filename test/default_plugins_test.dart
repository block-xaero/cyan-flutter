// test/default_plugins_test.dart
//
// cyan-media is a DEFAULT plugin — the core media engine every group carries,
// provisioned from app-shipped bytes with no network and no clicks.
//
// Why this is a test and not a nicety: a brand-new group's Plugins workspace is
// created EMPTY, so every `@cyan-media` step a cloned template lands binds to a
// bundle that is not in the group, and the engine's bind refuses it. That makes
// the same clone runnable on macOS and unrunnable here. The storefront cannot
// substitute — cyan-media is the lens's colocated media host, not a browse card
// — and the engine's own clone-path auto-install needs a running lens.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Models/DefaultPlugins.swift

import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/models/default_plugins.dart';

/// Records every install the provisioner asks the engine for.
class _RecordingBackend extends FakeCyanBackend {
  final List<({String groupId, String pluginId, int bytes})> installs = [];
  bool refuse = false;

  @override
  Future<PluginInstallResult> installPluginBundle(
      String groupId, String pluginId, String bundleBytesB64) async {
    installs.add((
      groupId: groupId,
      pluginId: pluginId,
      bytes: bundleBytesB64.length,
    ));
    if (refuse) {
      return const PluginInstallResult(
          success: false, pluginId: 'cyan-media', error: 'group not synced');
    }
    // Answered directly rather than through the fake's own install, which
    // validates the group exists. The subject here is the PROVISIONER's
    // ensure/retry logic, not the fake's group bookkeeping.
    return PluginInstallResult(success: true, pluginId: pluginId);
  }
}

/// Stands in for the app-shipped asset, so this test needs no asset bundle.
Future<List<int>?> _bundledBytes(String pluginId) async =>
    List<int>.filled(64, 7);

Future<List<int>?> _noAsset(String pluginId) async => null;

void main() {
  setUp(DefaultPlugins.resetForTests);

  test('cyan-media is the default plugin set', () {
    expect(DefaultPlugins.ids, ['cyan-media']);
  });

  test('a group is provisioned with no network', () async {
    final backend = _RecordingBackend();
    await DefaultPlugins.ensure('g-new', backend, loadAsset: _bundledBytes);

    expect(backend.installs, hasLength(1));
    expect(backend.installs.single.groupId, 'g-new');
    expect(backend.installs.single.pluginId, 'cyan-media');
    expect(backend.installs.single.bytes, greaterThan(0),
        reason: 'the bundle bytes are what land, base64 encoded');
  });

  test('a second pass does not re-write the bundle', () async {
    final backend = _RecordingBackend();
    await DefaultPlugins.ensure('g-new', backend, loadAsset: _bundledBytes);
    await DefaultPlugins.ensure('g-new', backend, loadAsset: _bundledBytes);
    await DefaultPlugins.ensure('g-new', backend, loadAsset: _bundledBytes);

    expect(backend.installs, hasLength(1),
        reason: 'the engine install is idempotent, but re-sending 574KB on '
            'every tree reload is not free');
  });

  test('a group that did NOT land is retried on the next pass', () async {
    // A group row that has not synced yet is a timing problem, not a permanent
    // one — marking it ensured would strand it empty forever.
    final backend = _RecordingBackend()..refuse = true;
    await DefaultPlugins.ensure('g-slow', backend, loadAsset: _bundledBytes);
    expect(backend.installs, hasLength(1));

    backend.refuse = false;
    await DefaultPlugins.ensure('g-slow', backend, loadAsset: _bundledBytes);
    expect(backend.installs, hasLength(2),
        reason: 'the failure must be retried');

    await DefaultPlugins.ensure('g-slow', backend, loadAsset: _bundledBytes);
    expect(backend.installs, hasLength(2),
        reason: 'and once it lands, it stops');
  });

  test('an optimistic local group id is never installed into', () async {
    // `temp_` rows are the tree's optimistic locals with no engine group behind
    // them; installing into one would foreign-key-reject.
    final backend = _RecordingBackend();
    await DefaultPlugins.ensure('temp_abc', backend, loadAsset: _bundledBytes);
    await DefaultPlugins.ensure('', backend, loadAsset: _bundledBytes);

    expect(backend.installs, isEmpty);
  });

  test('a build with no bundled asset does not fail the group', () async {
    final backend = _RecordingBackend();
    await DefaultPlugins.ensure('g-new', backend, loadAsset: _noAsset);

    expect(backend.installs, isEmpty, reason: 'there is nothing to land');
  });
}
