// providers/mesh_status_provider.dart
//
// PARITY port of the live half of the SwiftUI `StatusBarViewModel`
// (ViewModels/StatusBarViewModel.swift) — the status/sync spine the shell's
// gutter renders.
//
// Division of labour, kept from the Swift:
//   * `MeshStatusMachine` (models/mesh_status.dart) is the PURE fold — inputs
//     in, one honest state out.
//   * [MeshStatusNotifier] holds the OBSERVED inputs and RECOMPUTES the state
//     from them. The state is never assigned directly, so the bar can never
//     show a state its inputs do not support.
//   * [SyncLifecycle] is the policy on top: which transitions have to go back
//     to the engine and re-read the authoritative numbers.
//
// The rule this file exists to enforce: a peer count read before the link
// dropped is not evidence about the link that came back. Every path that
// reconnects or settles ends in a [SyncLifecycle.probe].

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mesh_status.dart';
import 'cyan_backend_provider.dart';

/// The engine's live peer reading. Read once per mount; [SyncLifecycle.probe]
/// invalidates it whenever the bar needs a fresh one.
final meshPresenceProvider = FutureProvider<MeshPresence>((ref) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.meshPresence();
});

/// The honest mesh status: [MeshStatusMachine] over live inputs, with the peer
/// count folded in from the engine as [meshPresenceProvider] resolves.
final meshStatusProvider =
    StateNotifierProvider<MeshStatusNotifier, MeshStatus>((ref) {
  final notifier = MeshStatusNotifier();
  ref.listen<AsyncValue<MeshPresence>>(
    meshPresenceProvider,
    (_, next) {
      final presence = next.valueOrNull;
      if (presence != null) notifier.updatePeerCount(presence.totalPeers);
    },
    fireImmediately: true,
  );
  return notifier;
});

/// Drives [MeshStatus] the way `StatusBarViewModel` drives `SyncState`.
class MeshStatusNotifier extends StateNotifier<MeshStatus> {
  MeshStatusNotifier([MeshInputs inputs = const MeshInputs()])
      : _inputs = inputs,
        super(MeshStatusMachine.state(inputs));

  MeshInputs _inputs;

  /// The inputs the current state is a pure function of.
  MeshInputs get inputs => _inputs;

  /// The live peer count (from the engine's peer map / presence events).
  ///
  /// The tier follows the peer set the way the SwiftUI view-model moves it: the
  /// first peer puts this node on `direct` unless a real tier was already
  /// observed, and losing the last peer drops it back to `none`.
  void updatePeerCount(int count) {
    var tier = _inputs.connectionTier;
    if (count > 0 && tier == ConnectionTier.none) tier = ConnectionTier.direct;
    if (count == 0) tier = ConnectionTier.none;
    _apply(_inputs.copyWith(peerCount: count, connectionTier: tier));
  }

  /// Internet reachability changed. With no peers this is what separates
  /// "Offline" from "Local-only".
  void setReachable(bool online) =>
      _apply(_inputs.copyWith(hasInternet: online));

  /// Peer discovery is in progress (dialing, no peers yet).
  void setDiscovering(bool discovering) =>
      _apply(_inputs.copyWith(isDiscovering: discovering));

  /// The mesh is partitioned / on a relay fallback / reconnecting — or healed.
  void setDegraded(bool degraded) =>
      _apply(_inputs.copyWith(degraded: degraded));

  void setConnectionTier(ConnectionTier tier) =>
      _apply(_inputs.copyWith(connectionTier: tier));

  /// File transfers in flight. Passing 0 clears the progress fragment too —
  /// nothing is transferring, so there is no percentage to keep showing.
  void setTransfers(int pending, {String? progressText, double? progress}) {
    _apply(MeshInputs(
      hasInternet: _inputs.hasInternet,
      peerCount: _inputs.peerCount,
      isDiscovering: _inputs.isDiscovering,
      pendingTransfers: pending,
      transferProgressText: pending > 0 ? progressText : null,
      transferProgress: pending > 0 ? progress : null,
      snapshotInFlight: _inputs.snapshotInFlight,
      snapshotDetail: _inputs.snapshotDetail,
      degraded: _inputs.degraded,
      connectionTier: _inputs.connectionTier,
    ));
  }

  /// A group snapshot is arriving (e.g. this device just joined via a grant).
  void setSnapshotInFlight(bool inFlight, {String? detail}) {
    _apply(MeshInputs(
      hasInternet: _inputs.hasInternet,
      peerCount: _inputs.peerCount,
      isDiscovering: _inputs.isDiscovering,
      pendingTransfers: _inputs.pendingTransfers,
      transferProgressText: _inputs.transferProgressText,
      transferProgress: _inputs.transferProgress,
      snapshotInFlight: inFlight,
      snapshotDetail: inFlight ? detail : null,
      degraded: _inputs.degraded,
      connectionTier: _inputs.connectionTier,
    ));
  }

  void _apply(MeshInputs next) {
    _inputs = next;
    state = MeshStatusMachine.state(next);
  }
}

/// The sync lifecycle driver behind the status bar. Live engine signals call
/// these; Tier-1 tests script the same seam.
final syncLifecycleProvider = Provider<SyncLifecycle>((ref) {
  final lifecycle = SyncLifecycle(ref);
  ref.onDispose(lifecycle.stopPolling);
  return lifecycle;
});

class SyncLifecycle {
  SyncLifecycle(this._ref);

  final Ref _ref;

  MeshStatusNotifier get _mesh => _ref.read(meshStatusProvider.notifier);

  /// True while a [probe] is in flight. The Swift VM coalesces its poll the
  /// same way: a read that arrives while one is running is DROPPED, never
  /// stacked behind it — the counts are an FFI hop through the engine's DB
  /// mutex, and a blocked read must not queue more of itself.
  bool _probeInFlight = false;
  bool get isProbing => _probeInFlight;

  // ---- the authoritative read ----------------------------------------------

  /// Throw away the cached presence read and ask the ENGINE what the mesh is
  /// right now, folding the answer back into the status bar.
  ///
  /// A read that FAILS is not hidden: a backend that cannot answer is a mesh
  /// this node cannot see, so it degrades the bar rather than leaving the last
  /// good number standing as if it were current.
  Future<void> probe() async {
    if (_probeInFlight) return;
    _probeInFlight = true;
    try {
      _ref.invalidate(meshPresenceProvider);
      final presence = await _ref.read(meshPresenceProvider.future);
      _mesh.updatePeerCount(presence.totalPeers);
    } catch (_) {
      _mesh.updatePeerCount(0);
      _mesh.setDegraded(true);
    } finally {
      _probeInFlight = false;
    }
  }

  // ---- the beat ------------------------------------------------------------

  Timer? _poll;

  /// Start the polled refresh the SwiftUI view-model runs on a 2s beat.
  ///
  /// The engine has no presence STREAM — `cyan_get_total_peer_count` /
  /// `cyan_get_all_peers` are reads — so a live peer count is a POLLED one, and
  /// a status bar that never re-reads is one showing whatever was true when it
  /// mounted. The host starts this when the shell mounts; widget tests drive
  /// [probe] directly, so no test carries a timer it did not ask for.
  /// Idempotent.
  void startPolling({Duration every = const Duration(seconds: 2)}) {
    if (_poll != null) return;
    _poll = Timer.periodic(every, (_) => probe());
  }

  /// End the beat. Called for the host when the provider is disposed.
  void stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  // ---- connectivity --------------------------------------------------------

  /// Reachability changed (the OS path monitor in the macOS app).
  ///
  /// Losing it marks the mesh degraded — the bar keeps every badge it had and
  /// says "Reconnecting…", because a gutter that empties itself tells an
  /// operator less than one that admits what it no longer knows. Regaining it
  /// [probe]s BEFORE it settles, so the count that returns is the engine's,
  /// not the one from before the drop.
  Future<void> connectivityChanged(bool online) async {
    if (!online) {
      _mesh.setReachable(false);
      _mesh.setDegraded(true);
      return;
    }
    _mesh.setReachable(true);
    await probe();
    // Only stand the mesh back up once the fresh read has landed.
    _mesh.setDegraded(false);
  }

  // ---- sync lifecycle ------------------------------------------------------

  /// A group snapshot is arriving (this device just joined via a grant).
  void beginSnapshot({String detail = 'Receiving snapshot…'}) =>
      _mesh.setSnapshotInFlight(true, detail: detail);

  /// The snapshot landed. What arrived CHANGED what this node holds, so
  /// settling re-reads rather than trusting the pre-sync numbers.
  Future<void> endSnapshot() async {
    _mesh.setSnapshotInFlight(false);
    await probe();
  }

  /// Reflect the in-flight transfer set — count, plus the pre-formatted
  /// progress fragment the bar shows ("42%").
  ///
  /// Dropping to zero SETTLES the bar, and a settle is authoritative: the
  /// transfers that just finished moved objects between this node and the
  /// mesh, so the counts get re-read.
  Future<void> transfersChanged(
    int pending, {
    String? progressText,
    double? progress,
  }) async {
    final settled = pending == 0 && _mesh.inputs.pendingTransfers > 0;
    _mesh.setTransfers(pending, progressText: progressText, progress: progress);
    if (settled) await probe();
  }

  /// Peer discovery is running (dialing, no peers yet).
  void setDiscovering(bool discovering) => _mesh.setDiscovering(discovering);

  /// The live connection tier, when the engine reports a real one.
  void setConnectionTier(ConnectionTier tier) => _mesh.setConnectionTier(tier);
}
