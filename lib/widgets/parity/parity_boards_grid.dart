// widgets/parity/parity_boards_grid.dart
//
// PARITY port of the SwiftUI `BoardGridView` — the All-Boards living wall
// (PARITY_TRACKER row 1). Masonry-style Monokai cards, grouped by workspace,
// with the "living wall" treatment: deployed boards show a running pill, idle
// boards show their step/notes summary.
//
// Driven ENTIRELY through the `CyanBackend` seam (via `allBoardsProvider`).
// This widget never touches `CyanFFI` directly — that is the parity rule.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';

class ParityBoardsGrid extends ConsumerWidget {
  /// Tapping a board card.
  final void Function(BoardWithContext)? onOpenBoard;

  const ParityBoardsGrid({super.key, this.onOpenBoard});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardsAsync = ref.watch(allBoardsProvider);

    return Material(
      color: MonokaiTheme.background,
      child: Column(
        children: [
          const _GridHeader(),
          const Divider(height: 1, color: MonokaiTheme.divider),
          Expanded(
            child: boardsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: MonokaiTheme.cyan),
              ),
              error: (e, _) => Center(
                child: Text('Failed to load boards: $e',
                    style: MonokaiTheme.bodyMedium
                        .copyWith(color: MonokaiTheme.red)),
              ),
              data: (boards) => boards.isEmpty
                  ? const _EmptyState()
                  : _GroupedMasonry(boards: boards, onOpenBoard: onOpenBoard),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridHeader extends StatelessWidget {
  const _GridHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.dashboard, size: 24, color: MonokaiTheme.cyan),
          const SizedBox(width: 12),
          Text('All Boards', style: MonokaiTheme.titleLarge),
          const Spacer(),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.dashboard_outlined,
              size: 64, color: MonokaiTheme.textDisabled),
          const SizedBox(height: 16),
          Text('No boards yet',
              style: MonokaiTheme.titleMedium
                  .copyWith(color: MonokaiTheme.textMuted)),
        ],
      ),
    );
  }
}

/// Workspace-grouped masonry, matching the SwiftUI grouped grid.
class _GroupedMasonry extends StatelessWidget {
  final List<BoardWithContext> boards;
  final void Function(BoardWithContext)? onOpenBoard;

  const _GroupedMasonry({required this.boards, required this.onOpenBoard});

  @override
  Widget build(BuildContext context) {
    // Stable group order by appearance.
    final grouped = <String, List<BoardWithContext>>{};
    for (final b in boards) {
      grouped.putIfAbsent('${b.group.id}:${b.workspace.id}', () => []).add(b);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const minCardWidth = 260.0;
        const spacing = 16.0;
        const padding = 20.0;
        final available = constraints.maxWidth - (padding * 2);
        final columns = ((available + spacing) / (minCardWidth + spacing))
            .floor()
            .clamp(1, 5);
        final cardWidth = (available - (spacing * (columns - 1))) / columns;

        final children = <Widget>[];
        var idx = 0;
        for (final entry in grouped.entries) {
          final items = entry.value;
          final first = items.first;
          children.add(Padding(
            padding: EdgeInsets.only(
                bottom: 12, top: idx > 0 ? 24 : 0, left: padding, right: padding),
            child: Row(
              children: [
                Icon(Icons.folder, size: 16, color: _color(first.group.colorHex)),
                const SizedBox(width: 8),
                Text(first.group.name, style: MonokaiTheme.titleSmall),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right,
                    size: 14, color: MonokaiTheme.textMuted),
                const SizedBox(width: 6),
                Text(first.workspace.name,
                    style: MonokaiTheme.titleSmall
                        .copyWith(color: MonokaiTheme.green)),
                const SizedBox(width: 8),
                Text('(${items.length})', style: MonokaiTheme.labelMedium),
              ],
            ),
          ));
          children.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: padding),
            child: Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: items
                  .map((b) => SizedBox(
                        width: cardWidth,
                        child: ParityBoardCard(
                          board: b,
                          onTap: () => onOpenBoard?.call(b),
                        ),
                      ))
                  .toList(),
            ),
          ));
          idx++;
        }

        return ListView(
          padding: const EdgeInsets.only(top: 16, bottom: 16),
          children: children,
        );
      },
    );
  }

  static Color _color(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return MonokaiTheme.cyan;
    }
  }
}

/// A single board card — the living-wall tile.
class ParityBoardCard extends StatefulWidget {
  final BoardWithContext board;
  final VoidCallback? onTap;

  const ParityBoardCard({super.key, required this.board, this.onTap});

  @override
  State<ParityBoardCard> createState() => _ParityBoardCardState();
}

class _ParityBoardCardState extends State<ParityBoardCard> {
  bool _hovered = false;

  CyanBoard get _b => widget.board.board;

  Color get _faceColor => switch (_b.activeFace) {
        BoardFaceKind.workflow => MonokaiTheme.cyan,
        BoardFaceKind.notes => MonokaiTheme.green,
        BoardFaceKind.dashboard => MonokaiTheme.orange,
        BoardFaceKind.canvas => MonokaiTheme.purple,
      };

  IconData get _faceIcon => switch (_b.activeFace) {
        BoardFaceKind.workflow => Icons.article,
        BoardFaceKind.notes => Icons.description,
        BoardFaceKind.dashboard => Icons.play_circle,
        BoardFaceKind.canvas => Icons.brush,
      };

  @override
  Widget build(BuildContext context) {
    final previewHeight = _previewHeight(_b.id);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: MonokaiTheme.surfaceLighter,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered
                  ? MonokaiTheme.cyan.withValues(alpha: 0.6)
                  : MonokaiTheme.border.withValues(alpha: 0.4),
              width: _hovered ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: previewHeight,
                child: Stack(
                  children: [
                    Positioned.fill(child: _preview()),
                    if (_b.isPinned)
                      const Positioned(
                        top: 8,
                        right: 8,
                        child: Icon(Icons.push_pin,
                            size: 14, color: MonokaiTheme.orange),
                      ),
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: _faceColor.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_faceIcon, size: 10, color: Colors.white),
                            const SizedBox(width: 3),
                            Text(_b.activeFace.label,
                                style: MonokaiTheme.labelSmall
                                    .copyWith(color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(_b.name,
                              style: MonokaiTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (_b.rating > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              _b.rating.clamp(0, 5),
                              (_) => const Icon(Icons.star,
                                  size: 8, color: MonokaiTheme.yellow),
                            ),
                          ),
                      ],
                    ),
                    if (_b.labels.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: _b.labels
                            .map((l) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: MonokaiTheme.selection,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(l,
                                      style: MonokaiTheme.labelSmall),
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Living-wall preview: a deployed/running board shows a "running" treatment;
  /// an idle board shows a step/notes summary.
  Widget _preview() {
    final base = Container(
      decoration: const BoxDecoration(
        color: MonokaiTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
      ),
    );
    if (_b.isDeployed) {
      return Stack(
        children: [
          Positioned.fill(child: base),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_circle, size: 32, color: _faceColor),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: MonokaiTheme.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('Running · ${_b.stepCount} steps',
                      style: MonokaiTheme.labelSmall
                          .copyWith(color: MonokaiTheme.green)),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: base),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_faceIcon,
                  size: 28, color: _faceColor.withValues(alpha: 0.5)),
              const SizedBox(height: 6),
              Text(
                _b.activeFace == BoardFaceKind.notes
                    ? 'Notes'
                    : '${_b.stepCount} step${_b.stepCount == 1 ? '' : 's'}',
                style: MonokaiTheme.labelSmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Deterministic masonry height from the board id (stable for goldens).
  static double _previewHeight(String boardId) {
    const heights = [120.0, 140.0, 160.0, 180.0];
    return heights[boardId.hashCode.abs() % heights.length];
  }
}
