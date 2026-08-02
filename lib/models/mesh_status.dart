// models/mesh_status.dart
//
// PARITY port of the SwiftUI `SyncStatusMachine` (ViewModels/
// SyncStatusMachine.swift) — the honest live mesh status the shell's status bar
// reports.
//
// The rule that file was written to enforce, kept verbatim here: a near-static
// green "Synced" with 0 live peers is a LIE. The state is a PURE function of
// live inputs (internet reachability, peer count, in-flight snapshot /
// transfers, connection tier, mesh degradation). The shell feeds it observed
// inputs; the status bar renders the result. Pure and input-driven, so Tier-1
// can script every transition with no engine.
//
// Presentation (glyph + colour) belongs to the widget, not here — this layer
// stays free of Flutter so the machine can be unit-tested on its own.

import 'package:flutter/foundation.dart';

/// The engine's live peer reading: `cyan_get_total_peer_count` with the
/// per-group ids behind it (`cyan_get_all_peers`).
///
/// Lives beside the machine that consumes it rather than in `parity_models`
/// because it is not a screen's view model — it is the one input the status
/// bar's whole state is derived from.
@immutable
class MeshPresence {
  /// Total live peers across every group.
  final int totalPeers;

  /// Live peer ids keyed by group id. A group with no live neighbours is
  /// ABSENT rather than empty, exactly as the engine answers it.
  final Map<String, List<String>> peersByGroup;

  const MeshPresence({this.totalPeers = 0, this.peersByGroup = const {}});

  /// Engine not running — no peers, no groups. Honestly zero, not unknown.
  const MeshPresence.none()
      : totalPeers = 0,
        peersByGroup = const {};

  /// `{"group_id":["peer",…],…}` — the shape `cyan_get_all_peers` answers.
  /// The total is the sum unless a caller passes the engine's own count, which
  /// is authoritative when the two disagree.
  factory MeshPresence.fromJson(Map<String, dynamic> json, {int? totalPeers}) {
    final byGroup = <String, List<String>>{};
    for (final entry in json.entries) {
      final peers = entry.value;
      if (peers is! List) continue;
      byGroup[entry.key] = [for (final p in peers) '$p'];
    }
    return MeshPresence(
      totalPeers: totalPeers ??
          byGroup.values.fold<int>(0, (sum, peers) => sum + peers.length),
      peersByGroup: byGroup,
    );
  }

  /// Live peers in one group — 0 for a group with none.
  int peersIn(String groupId) => peersByGroup[groupId]?.length ?? 0;
}

/// How this node is reaching its peers.
enum ConnectionTier {
  none,
  direct,
  relayed,
  websocket;

  String get label => switch (this) {
        ConnectionTier.none => '—',
        ConnectionTier.direct => 'Direct',
        ConnectionTier.relayed => 'Relayed',
        ConnectionTier.websocket => 'WebSocket',
      };
}

/// The six honest states, mirroring the Swift enum's cases.
enum MeshStateKind {
  /// No internet AND no peers — cloud features are greyed out.
  offline,

  /// 0 peers. NOT "Synced".
  localOnly,

  /// Discovering / dialing peers.
  connecting,

  /// Snapshot on join / delta / file transfer in flight.
  syncing,

  /// ≥1 peer AND nothing pending.
  synced,

  /// Partition / relay fallback / reconnecting.
  degraded,
}

/// Everything the state depends on.
@immutable
class MeshInputs {
  final bool hasInternet;
  final int peerCount;
  final bool isDiscovering;

  /// In-flight file transfers (download or upload).
  final int pendingTransfers;

  /// A pre-formatted transfer progress fragment, e.g. "42%".
  final String? transferProgressText;
  final double? transferProgress;

  /// A group snapshot is arriving (e.g. this device just joined via a grant).
  final bool snapshotInFlight;
  final String? snapshotDetail;

  /// Mesh is partitioned / relay-fallback / reconnecting.
  final bool degraded;
  final ConnectionTier connectionTier;

  const MeshInputs({
    this.hasInternet = true,
    this.peerCount = 0,
    this.isDiscovering = false,
    this.pendingTransfers = 0,
    this.transferProgressText,
    this.transferProgress,
    this.snapshotInFlight = false,
    this.snapshotDetail,
    this.degraded = false,
    this.connectionTier = ConnectionTier.none,
  });

  /// Note: nullable fields CANNOT be cleared through this — `??` keeps the old
  /// value. Clearing a transfer / snapshot builds a fresh [MeshInputs].
  MeshInputs copyWith({
    bool? hasInternet,
    int? peerCount,
    bool? isDiscovering,
    bool? degraded,
    ConnectionTier? connectionTier,
  }) =>
      MeshInputs(
        hasInternet: hasInternet ?? this.hasInternet,
        peerCount: peerCount ?? this.peerCount,
        isDiscovering: isDiscovering ?? this.isDiscovering,
        pendingTransfers: pendingTransfers,
        transferProgressText: transferProgressText,
        transferProgress: transferProgress,
        snapshotInFlight: snapshotInFlight,
        snapshotDetail: snapshotDetail,
        degraded: degraded ?? this.degraded,
        connectionTier: connectionTier ?? this.connectionTier,
      );
}

/// The derived state: what the mesh IS right now, plus the peer count and tier
/// the status bar reports alongside it.
@immutable
class MeshStatus {
  final MeshStateKind kind;
  final int peerCount;
  final ConnectionTier tier;

  /// The "Syncing…" line, composed by the machine. Null for every other state.
  final String? detail;

  /// Transfer progress 0..1 while syncing, when the transfer reports one.
  final double? progress;

  const MeshStatus({
    required this.kind,
    this.peerCount = 0,
    this.tier = ConnectionTier.none,
    this.detail,
    this.progress,
  });

  bool get isSynced => kind == MeshStateKind.synced;
  bool get isSyncing => kind == MeshStateKind.syncing;

  /// True when this node can see at least one peer — the mesh is REACHABLE.
  bool get isMeshReachable => peerCount > 0;

  /// The link is not carrying. The bar owes the operator a warning in these
  /// states, not a blank space.
  bool get isImpaired =>
      kind == MeshStateKind.offline || kind == MeshStateKind.degraded;

  /// Cloud-only features (compile, cloud workflow steps, plugin registry,
  /// nudges) are unavailable when offline — surfaces grey out.
  bool get cloudFeaturesAvailable => kind != MeshStateKind.offline;

  /// The single line the status bar shows, verbatim from the Swift.
  String get displayText => switch (kind) {
        MeshStateKind.offline => 'Offline',
        MeshStateKind.localOnly => 'Local-only · no peers',
        MeshStateKind.connecting => 'Connecting…',
        MeshStateKind.syncing => detail ?? 'Syncing…',
        MeshStateKind.synced => 'Synced',
        MeshStateKind.degraded => 'Reconnecting…',
      };
}

/// The pure transition function.
abstract final class MeshStatusMachine {
  /// Derive the single honest state from the current inputs. Priority is
  /// deliberate: active work (degraded → syncing) wins; otherwise the
  /// peer/internet situation decides.
  static MeshStatus state(MeshInputs i) {
    MeshStatus at(MeshStateKind kind, {String? detail, double? progress}) =>
        MeshStatus(
          kind: kind,
          peerCount: i.peerCount,
          tier: i.connectionTier,
          detail: detail,
          progress: progress,
        );

    if (i.degraded) return at(MeshStateKind.degraded);

    if (i.snapshotInFlight || i.pendingTransfers > 0) {
      return at(MeshStateKind.syncing,
          detail: _syncingDetail(i), progress: i.transferProgress);
    }

    if (i.peerCount == 0) {
      if (!i.hasInternet) return at(MeshStateKind.offline);
      return at(i.isDiscovering
          ? MeshStateKind.connecting
          : MeshStateKind.localOnly);
    }

    // ≥1 peer and nothing pending — the ONLY time this is truly "Synced".
    return at(MeshStateKind.synced);
  }

  /// Compose the "Syncing…" detail line, scaling sanely to many
  /// peers/transfers.
  static String _syncingDetail(MeshInputs i) {
    if (i.snapshotInFlight) return i.snapshotDetail ?? 'Receiving snapshot…';

    final n = i.pendingTransfers;
    final base = n == 1 ? 'Syncing 1 file' : 'Syncing $n files';
    final pct = i.transferProgressText;
    if (pct != null) return '$base · $pct';
    if (i.peerCount > 1) {
      return 'Syncing with ${i.peerCount} peers · $n '
          'transfer${n == 1 ? '' : 's'}';
    }
    return base;
  }
}
