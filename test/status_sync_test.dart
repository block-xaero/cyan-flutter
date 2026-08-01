// test/status_sync_test.dart
//
// PARITY face `status_sync` — the shell's gutter as a LIVE surface: peers and
// mesh reachability, a sync that is visible while it runs and settles when it
// lands, a dropped link that degrades the bar instead of emptying it, and a
// reconnect that goes back to the engine instead of serving what it cached.
//
// Tier-1: `ParityStatusBar` over `FakeCyanBackend`, driven through
// `syncLifecycleProvider` — the same seam the live engine signals drive. The
// mesh is the one thing about a running engine that is never static, so the
// peer set MOVES under the bar here (`FakeCyanBackend.setLivePeers`) rather
// than being asserted once at rest.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/models/mesh_status.dart';
import 'package:cyan_flutter/providers/mesh_status_provider.dart';
import 'package:cyan_flutter/theme/monokai_theme.dart';
import 'package:cyan_flutter/widgets/parity/parity_status_bar.dart';

import 'support/parity_test_harness.dart';

/// The gutter on a surface its own 24px height — the strip it occupies at the
/// foot of the shell.
Future<void> pumpBar(WidgetTester tester, {required FakeCyanBackend backend}) =>
    pumpParity(
      tester,
      const ParityStatusBar(breadcrumb: 'Engineering › Render + Review'),
      backend: backend,
      size: const Size(900, 24),
    );

SyncLifecycle _lifecycle(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ParityStatusBar)))
        .read(syncLifecycleProvider);

Text _peerCountText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('statusbar-peer-count')));

/// What the gutter is reporting right now.
String _peers(WidgetTester tester) => _peerCountText(tester).data!;

String _meshState(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('statusbar-mesh-state')))
    .data!;

/// Record what the gutter reads at [step].
///
/// These tests assert a PATH through a state machine, not a single frame, and a
/// failure halfway along says nothing about how it got there. Logging each leg
/// leaves the whole path in the run output, so a red one is diagnosable from
/// the log rather than by re-deriving the transitions.
void _trace(WidgetTester tester, String step) {
  // ignore: avoid_print
  print('gutter @ $step — peers=${_peers(tester)} '
      'state="${_meshState(tester)}"');
}

void main() {
  testWidgets('the status bar reports peer count and mesh reachability',
      (tester) async {
    // The fake's seeded mesh: 3 + 2 + 1 live neighbours across three groups,
    // matching each group's own peer count.
    final backend = FakeCyanBackend();
    await pumpBar(tester, backend: backend);
    final lifecycle = _lifecycle(tester);
    _trace(tester, 'mounted');

    expect(_peers(tester), '6');
    expect(_meshState(tester), 'Synced');
    // Reachable ⇒ the presence dot and count go green, and there is a tier to
    // reach the mesh by.
    expect(_peerCountText(tester).style!.color, MonokaiTheme.green);
    expect(find.text(ConnectionTier.direct.label), findsOneWidget);

    // Every neighbour drops. The bar must report that honestly — 0 peers is
    // NOT "Synced", which is the whole reason the state machine exists.
    backend.setLivePeers(const {});
    await lifecycle.probe();
    await tester.pumpAndSettle();
    _trace(tester, 'mesh emptied');

    expect(_peers(tester), '0');
    expect(_meshState(tester), 'Local-only · no peers');
    expect(_peerCountText(tester).style!.color, MonokaiTheme.comment);
    // No peers ⇒ nothing to report a tier about.
    expect(find.byKey(const ValueKey('statusbar-tier')), findsNothing);

    // Neighbours come back and the count follows the live set, not a cache.
    backend.setLivePeers(const {
      'g-eng': ['node-priya', 'node-mara', 'node-ravi'],
    });
    await lifecycle.probe();
    await tester.pumpAndSettle();
    _trace(tester, 'mesh repopulated');

    expect(_peers(tester), '3');
    expect(_meshState(tester), 'Synced');
    expect(find.byKey(const ValueKey('statusbar-tier')), findsOneWidget);
  });

  testWidgets('a sync in progress is visible and resolves to a settled state',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpBar(tester, backend: backend);
    final lifecycle = _lifecycle(tester);

    expect(_meshState(tester), 'Synced');

    // A group snapshot lands on this device (joined via a grant): the gutter
    // says what is arriving while it arrives.
    lifecycle.beginSnapshot(detail: 'Engineering: receiving snapshot…');
    await tester.pump();
    _trace(tester, 'snapshot in flight');
    expect(_meshState(tester), 'Engineering: receiving snapshot…');

    // …and settles once it has landed.
    await lifecycle.endSnapshot();
    await tester.pumpAndSettle();
    _trace(tester, 'snapshot landed');
    expect(_meshState(tester), 'Synced');

    // The same for file transfers, which report a percentage while they run.
    await lifecycle.transfersChanged(3, progressText: '42%', progress: 0.42);
    await tester.pump();
    _trace(tester, 'transfers in flight');

    expect(_meshState(tester), 'Syncing 3 files · 42%');
    final progress = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('statusbar-progress')));
    expect(progress.value, closeTo(0.42, 0.001));

    // Last transfer finishes ⇒ settled, and the progress bar goes with it.
    await lifecycle.transfersChanged(0);
    await tester.pumpAndSettle();
    _trace(tester, 'transfers settled');

    expect(_meshState(tester), 'Synced');
    expect(find.byKey(const ValueKey('statusbar-progress')), findsNothing);
  });

  testWidgets('losing connectivity shows a degraded indicator not a blank bar',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpBar(tester, backend: backend);
    final lifecycle = _lifecycle(tester);

    expect(_meshState(tester), 'Synced');

    await lifecycle.connectivityChanged(false);
    await tester.pumpAndSettle();
    _trace(tester, 'link lost');

    // Degraded, and SAYS so — glyph plus the state's own words.
    expect(_meshState(tester), 'Reconnecting…');
    expect(find.byKey(const ValueKey('statusbar-degraded')), findsOneWidget);

    // …and the gutter is still a gutter: every badge it had is still there,
    // still reporting the last thing this node actually knew. A bar that
    // empties itself tells an operator less than one that admits it is stale.
    for (final badge in const [
      'statusbar-breadcrumb',
      'statusbar-objects',
      'statusbar-peers',
      'statusbar-mesh',
    ]) {
      expect(find.byKey(ValueKey(badge)), findsOneWidget, reason: badge);
    }
    expect(find.text('Engineering › Render + Review'), findsOneWidget);
    expect(_peers(tester), '6');
  });

  testWidgets(
      'reconnecting refetches authoritative state rather than staying stale',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpBar(tester, backend: backend);
    final lifecycle = _lifecycle(tester);

    expect(_peers(tester), '6');

    await lifecycle.connectivityChanged(false);
    await tester.pumpAndSettle();
    _trace(tester, 'link lost');
    expect(_meshState(tester), 'Reconnecting…');
    // While the link is down the gutter holds the last good read — that is the
    // stale number the reconnect must not keep.
    expect(_peers(tester), '6');

    // The mesh MOVED while this node was blind to it: four of the six
    // neighbours went away and a different one arrived.
    backend.setLivePeers(const {
      'g-eng': ['node-priya', 'node-jun'],
    });

    await lifecycle.connectivityChanged(true);
    await tester.pumpAndSettle();
    _trace(tester, 'link back');

    // The count on screen is the ENGINE's answer, re-read after the link came
    // back — not the one cached from before it dropped.
    expect(_peers(tester), '2');
    expect(_meshState(tester), 'Synced');
    expect(find.byKey(const ValueKey('statusbar-degraded')), findsNothing);
  });

  testWidgets('the polled beat keeps the peer count live without a reload',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpBar(tester, backend: backend);
    final lifecycle = _lifecycle(tester);
    addTearDown(lifecycle.stopPolling);

    expect(_peers(tester), '6');

    // The engine is polled, not subscribed: nothing tells the bar a neighbour
    // left, so the beat has to go and look.
    lifecycle.startPolling(every: const Duration(seconds: 2));
    backend.setLivePeers(const {
      'g-design': ['node-mara'],
    });
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    _trace(tester, 'after one beat');

    expect(_peers(tester), '1');

    lifecycle.stopPolling();
    backend.setLivePeers(const {});
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Beat stopped ⇒ no further reads.
    expect(_peers(tester), '1');
  });

  testWidgets('a backend that cannot answer degrades the bar rather than '
      'leaving a stale count standing', (tester) async {
    final backend = _DeadMeshBackend();
    await pumpBar(tester, backend: backend);
    final lifecycle = _lifecycle(tester);

    // The first read succeeds — the seeded mesh.
    expect(_peers(tester), '6');

    backend.dead = true;
    await lifecycle.probe();
    await tester.pumpAndSettle();
    _trace(tester, 'engine gone');

    expect(_peers(tester), '0');
    expect(_meshState(tester), 'Reconnecting…');
    expect(find.byKey(const ValueKey('statusbar-degraded')), findsOneWidget);
  });

  testWidgets('golden: status bar mid-sync', (tester) async {
    final backend = FakeCyanBackend();
    await pumpBar(tester, backend: backend);
    await _lifecycle(tester)
        .transfersChanged(3, progressText: '42%', progress: 0.42);
    await tester.pump();

    await expectLater(
      find.byType(ParityStatusBar),
      matchesGoldenFile('golden/status_bar_sync.png'),
    );
  }, tags: 'golden');
}

/// A backend whose mesh read fails once the engine goes away — the Tier-1
/// stand-in for a dylib that stopped answering.
class _DeadMeshBackend extends FakeCyanBackend {
  bool dead = false;

  @override
  Future<MeshPresence> meshPresence() {
    if (dead) throw StateError('engine is not running');
    return super.meshPresence();
  }
}
