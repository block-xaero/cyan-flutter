// widgets/parity/parity_status_bar.dart
//
// PARITY port of the SwiftUI `StatusBar` (Views/StatusBar.swift) — the 24pt
// bottom gutter: a breadcrumb on the left, then the live mesh readout on the
// right as divider-separated badges:
//
//   objects │ peers ● │ mesh state │ tier
//
// The rule the Swift file was written to enforce is kept: a static green
// "Synced" is a LIE. Every badge is a projection of `meshStatusProvider`, which
// is a pure fold of live inputs over the `CyanBackend` seam — so 0 peers reads
// "Local-only · no peers", a dropped link degrades the bar rather than blanking
// it, and a regained one shows a REFETCHED count, never the one from before the
// drop.
//
// Driven ENTIRELY through the seam (`meshPresenceProvider` / `allBoardsProvider`
// via `syncLifecycleProvider`). This widget never touches `CyanFFI` — that is
// the parity rule.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/mesh_status.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../providers/mesh_status_provider.dart';
import '../../theme/monokai_theme.dart';

class ParityStatusBar extends ConsumerWidget {
  /// What the left of the bar names — the open door, plus the board in scope.
  final String breadcrumb;

  const ParityStatusBar({super.key, this.breadcrumb = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mesh = ref.watch(meshStatusProvider);
    final boards = ref.watch(allBoardsProvider);

    return Container(
      height: 24,
      color: MonokaiTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            breadcrumb.isEmpty ? Icons.circle_outlined : Icons.description,
            size: 10,
            color: MonokaiTheme.cyan,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              breadcrumb.isEmpty ? 'No selection' : breadcrumb,
              key: const ValueKey('statusbar-breadcrumb'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MonokaiTheme.labelSmall.copyWith(
                fontSize: 11,
                color: breadcrumb.isEmpty
                    ? MonokaiTheme.textMuted
                    : MonokaiTheme.foreground,
              ),
            ),
          ),
          _ObjectCountBadge(count: boards.valueOrNull?.length),
          const _Divider(),
          _PeerCountBadge(peerCount: mesh.peerCount),
          const _Divider(),
          _MeshStateBadge(mesh: mesh),
          if (mesh.tier != ConnectionTier.none) ...[
            const _Divider(),
            _ConnectionTierBadge(tier: mesh.tier),
          ],
        ],
      ),
    );
  }
}

/// Total boards the engine can see — the SwiftUI `objectCountBadge`.
class _ObjectCountBadge extends StatelessWidget {
  final int? count;

  const _ObjectCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Objects in the local store',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.storage_outlined,
              size: 10, color: MonokaiTheme.comment),
          const SizedBox(width: 4),
          Text(
            count == null ? '—' : '$count',
            key: const ValueKey('statusbar-objects'),
            style: MonokaiTheme.codeSmall
                .copyWith(fontSize: 10, color: MonokaiTheme.comment),
          ),
        ],
      ),
    );
  }
}

/// The live peer count, with the presence dot the SwiftUI bar shows: green the
/// moment this node can see a neighbour, grey when it is alone.
class _PeerCountBadge extends StatelessWidget {
  final int peerCount;

  const _PeerCountBadge({required this.peerCount});

  @override
  Widget build(BuildContext context) {
    final reachable = peerCount > 0;
    final color = reachable ? MonokaiTheme.green : MonokaiTheme.comment;

    return Tooltip(
      message:
          peerCount == 1 ? '1 peer connected' : '$peerCount peers connected',
      child: Row(
        key: const ValueKey('statusbar-peers'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: reachable
                  ? MonokaiTheme.green
                  : MonokaiTheme.comment.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.people_outline, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            '$peerCount',
            key: const ValueKey('statusbar-peer-count'),
            style: MonokaiTheme.codeSmall.copyWith(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }
}

/// How this node is reaching its peers — only shown once there is a tier.
class _ConnectionTierBadge extends StatelessWidget {
  final ConnectionTier tier;

  const _ConnectionTierBadge({required this.tier});

  IconData get _icon => switch (tier) {
        ConnectionTier.none => Icons.flash_off,
        ConnectionTier.direct => Icons.bolt,
        ConnectionTier.relayed => Icons.swap_horiz,
        ConnectionTier.websocket => Icons.public,
      };

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Connection tier: ${tier.label}',
      child: Row(
        key: const ValueKey('statusbar-tier'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 10, color: MonokaiTheme.cyan),
          const SizedBox(width: 4),
          Text(
            tier.label,
            style: MonokaiTheme.labelSmall
                .copyWith(fontSize: 10, color: MonokaiTheme.cyan),
          ),
        ],
      ),
    );
  }
}

/// Whether the mesh is reachable, and how — the honest state, never a static
/// "Synced". An impaired link also gets a warning glyph, so a degraded gutter
/// can never be mistaken for a quiet one.
class _MeshStateBadge extends StatelessWidget {
  final MeshStatus mesh;

  const _MeshStateBadge({required this.mesh});

  IconData get _icon => switch (mesh.kind) {
        MeshStateKind.offline => Icons.wifi_off,
        MeshStateKind.localOnly => Icons.person_off_outlined,
        MeshStateKind.connecting => Icons.settings_input_antenna,
        MeshStateKind.syncing => Icons.sync,
        MeshStateKind.synced => Icons.check_circle,
        MeshStateKind.degraded => Icons.warning_amber_rounded,
      };

  Color get _color => switch (mesh.kind) {
        MeshStateKind.offline => MonokaiTheme.comment,
        MeshStateKind.localOnly => MonokaiTheme.yellow,
        MeshStateKind.connecting => MonokaiTheme.cyan,
        MeshStateKind.syncing => MonokaiTheme.cyan,
        MeshStateKind.synced => MonokaiTheme.green,
        MeshStateKind.degraded => MonokaiTheme.orange,
      };

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: mesh.displayText,
      child: Row(
        key: const ValueKey('statusbar-mesh'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon,
              key: mesh.isImpaired
                  ? const ValueKey('statusbar-degraded')
                  : null,
              size: 10,
              color: _color),
          const SizedBox(width: 4),
          if (mesh.progress != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 50,
                height: 3,
                child: LinearProgressIndicator(
                  key: const ValueKey('statusbar-progress'),
                  value: mesh.progress,
                  backgroundColor: MonokaiTheme.selection,
                  valueColor: AlwaysStoppedAnimation<Color>(_color),
                ),
              ),
            ),
          // Swift: .frame(minWidth: 60, maxWidth: 170) — a long "Syncing…"
          // detail is clipped rather than pushing the gutter around.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              mesh.displayText,
              key: const ValueKey('statusbar-mesh-state'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  MonokaiTheme.labelSmall.copyWith(fontSize: 10, color: _color),
            ),
          ),
        ],
      ),
    );
  }
}

/// The 1x12 hairline between badges.
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: MonokaiTheme.comment.withValues(alpha: 0.3),
    );
  }
}
