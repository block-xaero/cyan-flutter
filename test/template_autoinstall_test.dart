// test/template_autoinstall_test.dart
//
// CLONE-TIME PLUGIN AUTO-INSTALL — "auto install plugins from marketplace when
// we use templates to create workflows", which is a stated product requirement
// and an engine-verified divergence rather than a theoretical one.
//
// The engine's own clone-path auto-install covers only a template's declared
// `auto_install_set`, and its DTO explicitly EXCLUDES step `@mentions`. That
// set is empty on the builtins whose steps bind @cyan-media / @ae / @frameio,
// and on every user-saved template. The bind then refuses any mention whose
// bundle is not in the group — so the same clone lands runnable on macOS and
// unrunnable here, reporting an empty install.
//
// The Mac installs the UNION of every plugin the steps bind
// (TemplatesViewModel.swift:286-306). These tests pin that Dart does too.

import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/models/default_plugins.dart';
import 'package:cyan_flutter/providers/templates_provider.dart';
import 'package:cyan_flutter/services/plugin_bundle_fetcher.dart';

/// The builtin whose steps bind three plugins the group ALREADY holds
/// (`asset-ingest` / `ffmpeg` / `frameio` are the fake's installed catalog).
const _dailies = 'tpl-dailies';

/// The builtin with a step bound to `loudness`, which the group does NOT hold —
/// the case the whole feature exists for.
const _finishing = 'tpl-finishing';
const _board = 'b-eng-2';
const _tenant = 'g-eng';

class _RecordingBackend extends FakeCyanBackend {
  final List<({String groupId, String pluginId})> installs = [];

  @override
  Future<PluginInstallResult> installPluginBundle(
      String groupId, String pluginId, String bundleBytesB64) async {
    installs.add((groupId: groupId, pluginId: pluginId));
    return PluginInstallResult(success: true, pluginId: pluginId);
  }
}

/// Hands back bytes for anything asked for — the subject here is WHICH plugins
/// are asked for, not how the bytes arrive.
class _FakeFetcher implements PluginBundleFetcher {
  final List<String> asked = [];
  bool unavailable = false;

  @override
  Future<String> fetchBundleB64(String bundleId) async {
    asked.add(bundleId);
    if (unavailable) {
      throw const PluginBundleUnavailable('no bundle host reachable');
    }
    return 'YnVuZGxl';
  }
}

Future<TemplatesController> _controller(
  _RecordingBackend backend,
  _FakeFetcher fetcher,
) async {
  final c = TemplatesController(
    backend: backend,
    fetcher: fetcher,
    boardId: _board,
    tenantId: _tenant,
  );
  addTearDown(c.dispose);
  await c.load();
  return c;
}

void main() {
  setUp(DefaultPlugins.resetForTests);

  test('cloning installs the step-bound plugin the group does not hold',
      () async {
    final backend = _RecordingBackend();
    final fetcher = _FakeFetcher();
    final controller = await _controller(backend, fetcher);

    final template = controller.state.byId(_finishing);
    expect(template, isNotNull, reason: 'the fixture must carry the builtin');
    final bound = {
      for (final s in template!.steps)
        if (s.plugin != null) s.plugin!,
    };
    expect(bound, contains('loudness'),
        reason: 'this template binds loudness on a STEP');

    await controller.clone(_finishing, attempts: 3, interval: Duration.zero);

    // The step-bound plugin the group did not hold was installed, into the
    // TENANT the picker is scoped to. Without this the clone lands and every
    // `@loudness` step compiles to a mention the engine refuses to bind.
    expect(backend.installs.map((i) => i.pluginId), ['loudness']);
    expect(backend.installs.single.groupId, _tenant,
        reason: 'an install lands in the picker\'s own group, never a guess');
  });

  test('plugins the group ALREADY holds are not re-fetched', () async {
    // asset-ingest / ffmpeg / frameio are the fake's installed catalog, and
    // re-sending bundle bytes for a tool that is already there is pure waste.
    final backend = _RecordingBackend();
    final fetcher = _FakeFetcher();
    final controller = await _controller(backend, fetcher);

    await controller.clone(_dailies, attempts: 3, interval: Duration.zero);

    expect(fetcher.asked, isEmpty,
        reason: 'every plugin this template binds is already in the group');
    expect(backend.installs, isEmpty);
  });

  test('the defaults every group already carries are never fetched', () async {
    // `DefaultPlugins.ensure` provisions these from app-shipped bytes. Pulling
    // them over the network would undo the point of shipping them, and would
    // fail offline — which is exactly when they matter.
    final backend = _RecordingBackend();
    final fetcher = _FakeFetcher();
    final controller = await _controller(backend, fetcher);

    await controller.clone(_finishing, attempts: 3, interval: Duration.zero);

    for (final id in DefaultPlugins.ids) {
      expect(fetcher.asked, isNot(contains(id)),
          reason: '$id ships with the app and is already in the group');
    }
  });

  test('a clone still lands when the bundle host is unreachable', () async {
    // Best effort by design: the operator can install a tool afterwards, but
    // they cannot re-run a clone that refused.
    final backend = _RecordingBackend();
    final fetcher = _FakeFetcher()..unavailable = true;
    final controller = await _controller(backend, fetcher);

    final ok = await controller.clone(_finishing,
        attempts: 3, interval: Duration.zero);

    expect(fetcher.asked, isNotEmpty, reason: 'it tried');
    expect(backend.installs, isEmpty, reason: 'and nothing could land');
    expect(ok, isTrue,
        reason: 'the steps must still be on the board — a clone that refuses '
            'because a plugin was unreachable is not recoverable');
  });
}
