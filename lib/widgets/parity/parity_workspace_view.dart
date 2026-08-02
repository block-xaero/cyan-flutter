// widgets/parity/parity_workspace_view.dart
//
// PARITY face_workspaces — ONE workspace: the boards filed in it, what each of
// them is doing, and the shortcuts that jump to them.
//
// SwiftUI reference (read-only):
//   Views/WorkspaceViewNew.swift          — the workspace shell + `closeBoard`
//   Views/WorkspaceShortcuts.swift        — the shortcut REGISTRY + pure reducer
//   Views/BoardGridView.swift             — the card face (preview + run pill)
//   ViewModels/BoardGridViewModel.swift   — `loadBoardsForWorkspace(_:)`
//   Models/LensConsole.swift              — BoardRunState, the lane counts
//
// The All-Boards living wall (`ParityBoardsGrid`) answers "everything, grouped";
// this answers "this workspace, and what is holding". They render different
// cards on purpose: the wall's tile is a thumbnail, this one is an operations
// row that has to say whether a board is waiting on a person.
//
// Everything reads through the ONE `CyanBackend` seam via
// `workspaceSurfaceProvider` — this widget never touches `CyanFFI`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../models/workspace_surface.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../theme/monokai_theme.dart';

/// The digit chords the shortcut strip binds, in order. CONTROL, not command:
/// ⌘1–⌘5 already belong to the icon rail's five doors (SwiftUI
/// `WorkspaceShortcut.explorer…lens`), and a workspace shortcut that stole ⌘2
/// would be a second binding for one chord — the exact drift the Swift registry
/// exists to make impossible.
const List<LogicalKeyboardKey> _shortcutDigits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

class ParityWorkspaceView extends ConsumerStatefulWidget {
  /// The workspace this surface is standing in.
  final String workspaceId;

  /// Navigating to a board. The board SURFACE is the board container's job
  /// (SwiftUI hands off to `BoardContainerViewNew` the same way); this face
  /// owns getting you there and remembering where you are.
  final void Function(CyanBoard)? onOpenBoard;

  const ParityWorkspaceView({
    super.key,
    required this.workspaceId,
    this.onOpenBoard,
  });

  @override
  ConsumerState<ParityWorkspaceView> createState() =>
      _ParityWorkspaceViewState();
}

class _ParityWorkspaceViewState extends ConsumerState<ParityWorkspaceView> {
  /// The board navigated to, if any. SwiftUI keeps the same `selectedBoard`
  /// beside the grid, and `WorkspaceShortcut.closeBoard` (esc) clears it.
  String? _openBoardId;

  void _open(CyanBoard board) {
    setState(() => _openBoardId = board.id);
    widget.onOpenBoard?.call(board);
  }

  /// `WorkspaceShortcut.closeBoard.apply` — esc returns to the board list.
  void _closeBoard() {
    if (_openBoardId == null) return;
    setState(() => _openBoardId = null);
  }

  /// The board navigated to, resolved against the workspace. Null once esc has
  /// closed it, or when the open board has since left the workspace.
  CyanBoard? _openBoard(WorkspaceSurface surface) {
    for (final b in surface.boards) {
      if (b.id == _openBoardId) return b;
    }
    return null;
  }

  /// Jump to the nth shortcut board. Out of range is a no-op, never a crash:
  /// the chord stays bound while the workspace holds fewer boards than digits.
  void _jumpTo(WorkspaceSurface surface, int index) {
    final boards = surface.shortcutBoards;
    if (index < 0 || index >= boards.length) return;
    _open(boards[index]);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(workspaceSurfaceProvider(widget.workspaceId));

    return Material(
      color: MonokaiTheme.background,
      child: async.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MonokaiTheme.cyan),
        ),
        error: (e, _) => Center(
          child: Text('Failed to load workspace: $e',
              style: MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.red)),
        ),
        data: (surface) =>
            surface == null ? const _NoSuchWorkspace() : _body(surface),
      ),
    );
  }

  Widget _body(WorkspaceSurface surface) {
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.escape): _closeBoard,
      for (var i = 0; i < _shortcutDigits.length; i++)
        SingleActivator(_shortcutDigits[i], control: true): () =>
            _jumpTo(surface, i),
    };

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WorkspaceHeader(
              surface: surface,
              openBoard: _openBoard(surface),
              onCloseBoard: _closeBoard,
              onCreateBoard:
                  surface.isSystem ? null : () => _promptNewBoard(surface),
            ),
            const Divider(height: 1, color: MonokaiTheme.divider),
            _PipelineStrip(pipeline: surface.pipeline),
            const Divider(height: 1, color: MonokaiTheme.divider),
            _ShortcutsStrip(
              boards: surface.shortcutBoards,
              openBoardId: _openBoardId,
              onJump: _open,
            ),
            const Divider(height: 1, color: MonokaiTheme.divider),
            Expanded(
              child: surface.boards.isEmpty
                  ? _EmptyWorkspace(surface: surface)
                  : ListView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      children: [
                        for (final board in surface.boards)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _WorkspaceBoardCard(
                              board: board,
                              runState: surface.runState(board.id),
                              isOpen: board.id == _openBoardId,
                              onTap: () => _open(board),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Create a board IN this workspace. Only reachable from a workspace that
  /// accepts boards — the system `Plugins` workspace never renders the button,
  /// and the resolver below refuses it a second time so the guard does not
  /// depend on a button being hidden.
  Future<void> _promptNewBoard(WorkspaceSurface surface) async {
    final target = boardTargetIn([surface.workspace]);
    if (target == null) return;

    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewBoardDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;

    await ref.read(cyanBackendProvider).createBoard(target.id, name.trim());
    if (!mounted) return;
    ref.invalidate(workspaceSurfaceProvider(widget.workspaceId));
  }
}

// ---------------------------------------------------------------------------
// Header — where you are, and how much is here
// ---------------------------------------------------------------------------

class _WorkspaceHeader extends StatelessWidget {
  final WorkspaceSurface surface;

  /// The board navigated to, if any — the third breadcrumb segment. SwiftUI
  /// mounts `BoardContainerViewNew` here; the container is its own face, so
  /// what this surface owns is saying WHERE you went and how to come back.
  final CyanBoard? openBoard;
  final VoidCallback onCloseBoard;
  final VoidCallback? onCreateBoard;

  const _WorkspaceHeader({
    required this.surface,
    required this.openBoard,
    required this.onCloseBoard,
    this.onCreateBoard,
  });

  @override
  Widget build(BuildContext context) {
    final w = surface.workspace;
    final count = surface.boards.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                surface.isSystem ? Icons.inventory_2 : Icons.layers,
                size: 20,
                color:
                    surface.isSystem ? MonokaiTheme.purple : MonokaiTheme.green,
              ),
              const SizedBox(width: 10),
              Text(surface.group.name,
                  key: const ValueKey('workspace.group'),
                  style: MonokaiTheme.titleSmall
                      .copyWith(color: MonokaiTheme.textMuted)),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right,
                  size: 14, color: MonokaiTheme.textMuted),
              const SizedBox(width: 6),
              Text(w.name,
                  key: const ValueKey('workspace.name'),
                  style: MonokaiTheme.titleLarge),
              if (openBoard != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right,
                    size: 14, color: MonokaiTheme.textMuted),
                const SizedBox(width: 6),
                _OpenBoardCrumb(board: openBoard!, onClose: onCloseBoard),
              ],
              const SizedBox(width: 10),
              Text('$count ${count == 1 ? 'board' : 'boards'}',
                  key: const ValueKey('workspace.boardCount'),
                  style: MonokaiTheme.labelMedium),
              if (surface.isSystem) ...[
                const SizedBox(width: 10),
                Container(
                  key: const ValueKey('workspace.systemBadge'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: MonokaiTheme.purple.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: MonokaiTheme.purple.withValues(alpha: 0.5)),
                  ),
                  child: Text('System workspace',
                      style: MonokaiTheme.labelSmall
                          .copyWith(color: MonokaiTheme.purple)),
                ),
              ],
              const Spacer(),
              if (onCreateBoard != null)
                TextButton.icon(
                  key: const ValueKey('workspace.newBoard'),
                  onPressed: onCreateBoard,
                  icon: const Icon(Icons.add, size: 15),
                  label: const Text('New Board'),
                  style: TextButton.styleFrom(
                      foregroundColor: MonokaiTheme.cyan,
                      textStyle: MonokaiTheme.labelMedium),
                ),
            ],
          ),
          // A system workspace says what it IS for, so its missing New Board
          // button reads as a rule rather than as something broken.
          if (surface.isSystem) ...[
            const SizedBox(height: 6),
            Text(
              '${surface.workspace.systemPurpose} — boards are never filed here.',
              key: const ValueKey('workspace.systemPurpose'),
              style: MonokaiTheme.labelMedium
                  .copyWith(color: MonokaiTheme.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Where the shortcut took you, and the way back out. Never a dead end: the
/// chord that got you here has a visible inverse.
class _OpenBoardCrumb extends StatelessWidget {
  final CyanBoard board;
  final VoidCallback onClose;

  const _OpenBoardCrumb({required this.board, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('workspace.openBoard'),
      padding: const EdgeInsets.only(left: 8, right: 4, top: 3, bottom: 3),
      decoration: BoxDecoration(
        color: MonokaiTheme.cyan.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: MonokaiTheme.cyan.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(board.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    MonokaiTheme.titleSmall.copyWith(color: MonokaiTheme.cyan)),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            key: const ValueKey('workspace.closeBoard'),
            onTap: onClose,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('esc',
                    style: MonokaiTheme.codeSmall
                        .copyWith(fontSize: 9, color: MonokaiTheme.textMuted)),
                const SizedBox(width: 3),
                const Icon(Icons.close,
                    size: 12, color: MonokaiTheme.textMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pipeline status strip — the five lanes, rolled up over the workspace
// ---------------------------------------------------------------------------

class _PipelineStrip extends StatelessWidget {
  final WorkspacePipeline pipeline;

  const _PipelineStrip({required this.pipeline});

  static Color _laneColor(BoardRunLane lane) => switch (lane) {
        BoardRunLane.incoming => MonokaiTheme.textMuted,
        BoardRunLane.inFlight => MonokaiTheme.cyan,
        BoardRunLane.approval => MonokaiTheme.orange,
        BoardRunLane.done => MonokaiTheme.green,
        BoardRunLane.failed => MonokaiTheme.red,
      };

  @override
  Widget build(BuildContext context) {
    // The feed never arrived. Say that — five confident zeroes would read as
    // "this workspace is quiet", which is a claim we have not earned.
    if (!pipeline.isKnown) {
      return Container(
        key: const ValueKey('workspace.pipeline.unavailable'),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.cloud_off,
                size: 14, color: MonokaiTheme.textMuted),
            const SizedBox(width: 8),
            Text('Pipeline status unavailable',
                style: MonokaiTheme.labelMedium
                    .copyWith(color: MonokaiTheme.textMuted)),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('workspace.pipeline'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Text('Pipeline',
              style: MonokaiTheme.labelMedium
                  .copyWith(color: MonokaiTheme.textMuted)),
          const SizedBox(width: 14),
          for (final lane in BoardRunLane.values) ...[
            _LaneChip(
              lane: lane,
              count: pipeline.count(lane),
              color: _laneColor(lane),
            ),
            const SizedBox(width: 8),
          ],
          const Spacer(),
          if (pipeline.actionNeeded > 0)
            Container(
              key: const ValueKey('workspace.pipeline.actionNeeded'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: MonokaiTheme.orange.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${pipeline.actionNeeded} need action',
                  style: MonokaiTheme.labelSmall
                      .copyWith(color: MonokaiTheme.orange)),
            ),
        ],
      ),
    );
  }
}

class _LaneChip extends StatelessWidget {
  final BoardRunLane lane;
  final int count;
  final Color color;

  const _LaneChip(
      {required this.lane, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    // A zero lane stays on screen at half weight: the strip is a fixed layout
    // an operator reads by position, so lanes must never reshuffle.
    final live = count > 0;
    return Container(
      key: ValueKey('workspace.lane.${lane.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: live ? 0.14 : 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(lane.title,
              style: MonokaiTheme.labelSmall
                  .copyWith(color: live ? color : MonokaiTheme.textDisabled)),
          const SizedBox(width: 6),
          Text('$count',
              style: MonokaiTheme.labelSmall.copyWith(
                color: live ? color : MonokaiTheme.textDisabled,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shortcuts strip — ⌃1…⌃9 jump to a board
// ---------------------------------------------------------------------------

class _ShortcutsStrip extends StatelessWidget {
  final List<CyanBoard> boards;
  final String? openBoardId;
  final void Function(CyanBoard) onJump;

  const _ShortcutsStrip({
    required this.boards,
    required this.openBoardId,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    final shown = boards.take(_shortcutDigits.length).toList();
    if (shown.isEmpty) return const SizedBox.shrink();

    return Container(
      key: const ValueKey('workspace.shortcuts'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Shortcuts',
                style: MonokaiTheme.labelMedium
                    .copyWith(color: MonokaiTheme.textMuted)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < shown.length; i++)
                  _ShortcutChip(
                    chord: '⌃${i + 1}',
                    board: shown[i],
                    isOpen: shown[i].id == openBoardId,
                    onTap: () => onJump(shown[i]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutChip extends StatelessWidget {
  final String chord;
  final CyanBoard board;
  final bool isOpen;
  final VoidCallback onTap;

  const _ShortcutChip({
    required this.chord,
    required this.board,
    required this.isOpen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey('workspace.shortcut.${board.id}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isOpen
              ? MonokaiTheme.cyan.withValues(alpha: 0.14)
              : MonokaiTheme.surface,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isOpen
                ? MonokaiTheme.cyan.withValues(alpha: 0.7)
                : MonokaiTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (board.isPinned) ...[
              const Icon(Icons.push_pin, size: 10, color: MonokaiTheme.orange),
              const SizedBox(width: 4),
            ],
            Text(chord,
                style: MonokaiTheme.codeSmall
                    .copyWith(fontSize: 10, color: MonokaiTheme.textMuted)),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(board.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MonokaiTheme.labelMedium.copyWith(
                      color: isOpen
                          ? MonokaiTheme.cyan
                          : MonokaiTheme.foreground)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Board card — preview, metadata, last run state
// ---------------------------------------------------------------------------

class _WorkspaceBoardCard extends StatefulWidget {
  final CyanBoard board;
  final BoardRunState runState;
  final bool isOpen;
  final VoidCallback onTap;

  const _WorkspaceBoardCard({
    required this.board,
    required this.runState,
    required this.isOpen,
    required this.onTap,
  });

  @override
  State<_WorkspaceBoardCard> createState() => _WorkspaceBoardCardState();
}

class _WorkspaceBoardCardState extends State<_WorkspaceBoardCard> {
  /// Pointer over the card. SwiftUI's `isHovered` gates the same strip, and for
  /// the same reason: the asset-class counts cost an engine call per board, so
  /// they are fetched when a card is asked about rather than for the whole wall
  /// on open.
  bool _hovered = false;

  CyanBoard get board => widget.board;
  BoardRunState get runState => widget.runState;

  Color get _faceColor => switch (board.activeFace) {
        BoardFaceKind.workflow => MonokaiTheme.cyan,
        BoardFaceKind.notes => MonokaiTheme.green,
        BoardFaceKind.dashboard => MonokaiTheme.orange,
        BoardFaceKind.canvas => MonokaiTheme.purple,
      };

  IconData get _faceIcon => switch (board.activeFace) {
        BoardFaceKind.workflow => Icons.article,
        BoardFaceKind.notes => Icons.description,
        BoardFaceKind.dashboard => Icons.play_circle,
        BoardFaceKind.canvas => Icons.brush,
      };

  /// The card's run badge colour, by what the run is doing.
  Color get _runColor => switch (runState.phase) {
        BoardRunPhase.unknown => MonokaiTheme.textDisabled,
        BoardRunPhase.noRuns => MonokaiTheme.textMuted,
        BoardRunPhase.active => switch (runState.status!) {
            RunStatus.queued => MonokaiTheme.textMuted,
            RunStatus.running => MonokaiTheme.cyan,
            RunStatus.awaitingApproval => MonokaiTheme.orange,
            RunStatus.stuck => MonokaiTheme.orange,
            RunStatus.done => MonokaiTheme.green,
            RunStatus.failed => MonokaiTheme.red,
          },
      };

  static String _date(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final runLabel = runState.label;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        key: ValueKey('workspace.board.${board.id}'),
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: MonokaiTheme.surfaceLighter,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isOpen
                  ? MonokaiTheme.cyan.withValues(alpha: 0.7)
                  : MonokaiTheme.border.withValues(alpha: 0.4),
              width: widget.isOpen ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _preview(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (board.isPinned) ...[
                          const Icon(Icons.push_pin,
                              size: 12, color: MonokaiTheme.orange),
                          const SizedBox(width: 5),
                        ],
                        Flexible(
                          child: Text(board.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MonokaiTheme.titleSmall),
                        ),
                        if (board.rating > 0) ...[
                          const SizedBox(width: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              board.rating.clamp(0, 5),
                              (_) => const Icon(Icons.star,
                                  size: 9, color: MonokaiTheme.yellow),
                            ),
                          ),
                        ],
                        const Spacer(),
                        // The LAST RUN STATE. A board whose feed never arrived
                        // shows no badge at all rather than a guess.
                        if (runLabel != null)
                          Container(
                            key: ValueKey('workspace.runState.${board.id}'),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _runColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (runState.needsAction) ...[
                                  Icon(Icons.error_outline,
                                      size: 10, color: _runColor),
                                  const SizedBox(width: 4),
                                ],
                                Text(runLabel,
                                    style: MonokaiTheme.labelSmall
                                        .copyWith(color: _runColor)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        // Metadata: the face it opens on, its size, and when it
                        // last moved. Dates are absolute, not "3h ago" — a
                        // relative label re-renders differently every second and
                        // no golden can pin it.
                        Expanded(
                          child: Text(
                            '${board.activeFace.label} · '
                            '${board.stepCount} ${board.stepCount == 1 ? 'step' : 'steps'} · '
                            'updated ${_date(board.lastModified ?? board.createdAt)}',
                            key: ValueKey('workspace.meta.${board.id}'),
                            style: MonokaiTheme.labelSmall,
                          ),
                        ),
                        // The ASSET-CLASS strip, on hover — the board's own
                        // compiled steps, which the run badge beside the title
                        // cannot describe: a board mid-workflow with no lens run
                        // in flight still has step progress to report.
                        if (_hovered) ...[
                          const SizedBox(width: 10),
                          _AssetClassStrip(boardId: board.id),
                        ],
                      ],
                    ),
                    if (board.labels.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final l in board.labels)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: MonokaiTheme.selection,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(l, style: MonokaiTheme.labelSmall),
                            ),
                        ],
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

  /// The card PREVIEW — SwiftUI's board-card thumbnail, minus the canvas store:
  /// a deployed board wears its running treatment, an idle one shows the face it
  /// opens on and how much is in it.
  Widget _preview() {
    return Container(
      key: ValueKey('workspace.preview.${board.id}'),
      width: 72,
      height: 56,
      decoration: BoxDecoration(
        color: MonokaiTheme.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _faceColor.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            board.isDeployed ? Icons.play_circle : _faceIcon,
            size: 20,
            color: board.isDeployed
                ? _faceColor
                : _faceColor.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 4),
          Text(
            board.isDeployed
                ? 'Deployed'
                : board.activeFace == BoardFaceKind.notes
                    ? 'Notes'
                    : '${board.stepCount} ${board.stepCount == 1 ? 'step' : 'steps'}',
            style: MonokaiTheme.labelSmall.copyWith(
                fontSize: 9,
                color: board.isDeployed
                    ? MonokaiTheme.green
                    : MonokaiTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The asset-class strip — the board's own compiled steps
// ---------------------------------------------------------------------------

/// `● 1 pending · ● 1 in-flight · ● 2 done` (+ `● n failed` only when real),
/// straight off `cyan_pipeline_status` — SwiftUI's `BoardPipelineStatusStrip`.
///
/// Renders NOTHING in three cases, all of them deliberate: while the read is in
/// flight, when the read did not land, and when the board has no compiled steps
/// at all. Each of those is "we cannot say", and a strip of zeroes says the
/// opposite — that the board is authored and idle.
class _AssetClassStrip extends ConsumerWidget {
  final String boardId;

  const _AssetClassStrip({required this.boardId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(boardPipelineCountsProvider(boardId)).valueOrNull;
    if (counts == null || counts.isEmpty) return const SizedBox.shrink();

    return Container(
      key: ValueKey('workspace.assetClass.$boardId'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: MonokaiTheme.background.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip(boardId, 'pending', counts.pending, MonokaiTheme.textMuted),
          const SizedBox(width: 8),
          _chip(boardId, 'in-flight', counts.inFlight, MonokaiTheme.cyan),
          const SizedBox(width: 8),
          _chip(boardId, 'done', counts.done, MonokaiTheme.green),
          // A failed chip appears only when something actually failed — but
          // once it does it is never suppressed.
          if (counts.failed > 0) ...[
            const SizedBox(width: 8),
            _chip(boardId, 'failed', counts.failed, MonokaiTheme.red),
          ],
        ],
      ),
    );
  }

  static Widget _chip(String boardId, String label, int count, Color color) {
    return Row(
      key: ValueKey('workspace.assetClass.$boardId.$label'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text('$count $label',
            style: MonokaiTheme.codeSmall.copyWith(fontSize: 9, color: color)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty / missing states
// ---------------------------------------------------------------------------

class _EmptyWorkspace extends StatelessWidget {
  final WorkspaceSurface surface;

  const _EmptyWorkspace({required this.surface});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
              surface.isSystem
                  ? Icons.inventory_2_outlined
                  : Icons.layers_clear,
              size: 44,
              color: MonokaiTheme.textDisabled),
          const SizedBox(height: 12),
          Text(
            surface.isSystem
                ? 'This is a system workspace — it holds plugin bundles, not boards.'
                : 'No boards in this workspace yet',
            key: const ValueKey('workspace.empty'),
            style:
                MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

class _NoSuchWorkspace extends StatelessWidget {
  const _NoSuchWorkspace();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('No such workspace',
          key: const ValueKey('workspace.missing'),
          style: MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.red)),
    );
  }
}

// ---------------------------------------------------------------------------
// New Board
// ---------------------------------------------------------------------------

class _NewBoardDialog extends StatefulWidget {
  const _NewBoardDialog();

  @override
  State<_NewBoardDialog> createState() => _NewBoardDialogState();
}

class _NewBoardDialogState extends State<_NewBoardDialog> {
  final _name = TextEditingController(text: 'New Board');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: MonokaiTheme.surface,
      title: Text('New Board', style: MonokaiTheme.titleMedium),
      content: TextField(
        key: const ValueKey('workspace.newBoard.name'),
        controller: _name,
        autofocus: true,
        style: MonokaiTheme.bodyMedium,
        decoration: const InputDecoration(labelText: 'Board name'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_name.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
