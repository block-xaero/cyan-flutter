// widgets/parity/parity_explorer_tree.dart
//
// PARITY port of the SwiftUI `FileTreeView` — the Explorer / group tree
// (PARITY_TRACKER row 2). A Group -> Workspace -> Board sidebar tree with
// disclosure chevrons, type-colored icons, indentation, live search, row
// SELECTION, and create / rename / delete of boards, in the Monokai look.
//
// Driven ENTIRELY through the `CyanBackend` seam (via `groupsProvider`). This
// widget never touches `CyanFFI` directly — that is the parity rule.
//
// SwiftUI reference (read-only):
//   Views/FileTreeView.swift, ViewModels/FileTreeViewModel.swift
//   - header "Files" + a cyan add button
//   - a search field
//   - rows: chevron (if expandable) · type icon · name, indented by level*20+8
//   - `FileTreeRow.onTapGesture` -> `toggleSelection(item)`, and then expands
//     the row IF it is collapsed. Tapping never COLLAPSES — that is the
//     chevron's own `onToggleExpand`. Selection is the point of the tap.
//   - `.contextMenu` -> Rename / Delete / New Board
//   - the New Board target comes from `defaultWorkspaceIdForNewBoard()`, which
//     resolves the CURRENT SELECTION most-specific-first — never "whichever
//     workspace sorted first", which silently filed boards into the wrong group.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';

/// The three kinds of node the Explorer tree renders.
enum ExplorerNodeKind { group, workspace, board }

/// What the operator currently stands on in the Explorer — the Flutter
/// equivalent of `FileTreeViewModel.selectedItem` plus the scope chain it
/// posts on `.fileTreeSelectionDidChange`. Surfaced so the shell (and the
/// Marketplace's install target) can read the scope, not guess it.
@immutable
class ExplorerSelection {
  final ExplorerNodeKind kind;
  final String id;
  final String name;

  /// The owning group — the node itself for a group row.
  final String groupId;

  /// The owning workspace: the node itself for a workspace row, the parent for
  /// a board row, null for a group row.
  final String? workspaceId;

  /// The board, for board rows only.
  final CyanBoard? board;

  const ExplorerSelection({
    required this.kind,
    required this.id,
    required this.name,
    required this.groupId,
    this.workspaceId,
    this.board,
  });
}

/// A flattened, renderable tree row (computed from the group tree + the set of
/// expanded node ids + the current search filter).
@immutable
class _Row {
  final String id;
  final String name;
  final int level; // 0 group, 1 workspace, 2 board
  final ExplorerNodeKind kind;
  final bool hasChildren;
  final Color iconColor;
  final IconData icon;
  final String groupId;
  final String? workspaceId;
  final CyanBoard? board; // non-null for board rows (for onOpenBoard)

  const _Row({
    required this.id,
    required this.name,
    required this.level,
    required this.kind,
    required this.hasChildren,
    required this.iconColor,
    required this.icon,
    required this.groupId,
    this.workspaceId,
    this.board,
  });

  ExplorerSelection get selection => ExplorerSelection(
        kind: kind,
        id: id,
        name: name,
        groupId: groupId,
        workspaceId: workspaceId,
        board: board,
      );
}

class ParityExplorerTree extends ConsumerStatefulWidget {
  /// Tapping a board (leaf) row.
  final void Function(CyanBoard board)? onOpenBoard;

  /// The selection changed — null when the operator deselected. Mirrors the
  /// `.fileTreeSelectionDidChange` notification.
  final void Function(ExplorerSelection? selection)? onSelectionChanged;

  /// Overrides the header / empty-state group button. Left null, the button
  /// creates the group here, through the seam — `FileTreeView` puts that
  /// affordance in the tree itself (`filetree.createGroup.empty`), and a host
  /// only takes it over when it wants its own flow.
  final VoidCallback? onAddGroup;

  const ParityExplorerTree({
    super.key,
    this.onOpenBoard,
    this.onSelectionChanged,
    this.onAddGroup,
  });

  @override
  ConsumerState<ParityExplorerTree> createState() => _ParityExplorerTreeState();
}

class _ParityExplorerTreeState extends ConsumerState<ParityExplorerTree> {
  /// `TreeItem.pluginsWorkspaceName` — the system workspace, never where a
  /// board belongs.
  static const String _pluginsWorkspaceName = 'Plugins';

  // Expansion + selection are local UI state (the engine doesn't own them).
  final Set<String> _expanded = <String>{};
  ExplorerSelection? _selection;
  String _search = '';
  bool _seededExpansion = false;

  // On first data load, expand every group + workspace so the full hierarchy is
  // visible (and goldens are deterministic). Done once; user toggles persist.
  void _seedExpansion(List<CyanGroup> groups) {
    if (_seededExpansion) return;
    for (final g in groups) {
      _expanded.add(g.id);
      for (final w in g.workspaces) {
        _expanded.add(w.id);
      }
    }
    _seededExpansion = true;
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsProvider);

    return Material(
      color: MonokaiTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            onAddGroup: widget.onAddGroup ?? _promptNewGroup,
            onNewBoard: () => _promptNewBoard(),
          ),
          _SearchField(
            value: _search,
            onChanged: (v) => setState(() => _search = v),
          ),
          const Divider(height: 1, color: MonokaiTheme.divider),
          Expanded(
            child: groupsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: MonokaiTheme.cyan),
              ),
              error: (e, _) => Center(
                child: Text('Failed to load tree: $e',
                    style: MonokaiTheme.bodyMedium
                        .copyWith(color: MonokaiTheme.red)),
              ),
              data: (groups) {
                _seedExpansion(groups);
                final rows = _flatten(groups);
                if (groups.isEmpty) {
                  return _EmptyTree(
                      onAdd: widget.onAddGroup ?? _promptNewGroup);
                }
                if (rows.isEmpty) return const _NoMatches();
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _TreeRow(
                    key: ValueKey('explorer.row.${rows[i].id}'),
                    row: rows[i],
                    isExpanded: _expanded.contains(rows[i].id),
                    isSelected: _selection?.id == rows[i].id,
                    onTap: () => _onTap(rows[i]),
                    onToggle: () => _toggle(rows[i].id),
                    onMenu: (position) => _showRowMenu(rows[i], position),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---- selection ------------------------------------------------------------

  /// `FileTreeRow.onTapGesture`: select (toggling off if it was already the
  /// selection), then expand IF collapsed. A tap never collapses.
  void _onTap(_Row row) {
    if (row.kind == ExplorerNodeKind.board) {
      // A board row is a door: it always selects, and opens.
      _setSelection(row.selection);
      if (row.board != null) widget.onOpenBoard?.call(row.board!);
      return;
    }
    _setSelection(_selection?.id == row.id ? null : row.selection);
    if (row.hasChildren && !_expanded.contains(row.id)) _toggle(row.id);
  }

  void _setSelection(ExplorerSelection? selection) {
    setState(() => _selection = selection);
    widget.onSelectionChanged?.call(selection);
  }

  void _toggle(String id) {
    setState(() {
      if (!_expanded.remove(id)) _expanded.add(id);
    });
  }

  // ---- board create / rename / delete ---------------------------------------

  List<CyanGroup> get _groups => ref.read(groupsProvider).value ?? const [];

  /// Port of `FileTreeViewModel.defaultWorkspaceIdForNewBoard()`. Resolution,
  /// most-specific first: a selected workspace IS the answer; a selected board
  /// means its parent workspace; a selected group means that group's workspace,
  /// preferring the conventional "General" over the system "Plugins" one. With
  /// nothing selected, fall back to the first workspace — with no selection
  /// there is nothing better to infer.
  ///
  /// What it must NOT do is remember the last target: filing a board where the
  /// previous one went is exactly the papercut this replaces.
  String? _defaultWorkspaceIdForNewBoard(List<CyanGroup> groups) {
    final workspaces = [for (final g in groups) ...g.workspaces];
    if (workspaces.isEmpty) return null;

    CyanWorkspace? inGroup(String groupId) =>
        _preferredWorkspace(workspaces.where((w) => w.groupId == groupId));

    final sel = _selection;
    if (sel != null) {
      switch (sel.kind) {
        case ExplorerNodeKind.workspace:
          return sel.id;
        case ExplorerNodeKind.group:
          return inGroup(sel.id)?.id ?? workspaces.first.id;
        case ExplorerNodeKind.board:
          final parent = sel.workspaceId;
          if (parent != null && workspaces.any((w) => w.id == parent)) {
            return parent;
          }
      }
    }
    return workspaces.first.id;
  }

  /// The workspace an operator means when they name only a group: the
  /// conventional `General`, never the system `Plugins` one if anything else is
  /// on offer. Shared by the New Board target resolver and the landing spot
  /// after a group is created, so both agree on what "the group's workspace"
  /// means.
  static CyanWorkspace? _preferredWorkspace(Iterable<CyanWorkspace> within) {
    if (within.isEmpty) return null;
    for (final w in within) {
      if (w.name == 'General') return w;
    }
    for (final w in within) {
      if (w.name != _pluginsWorkspaceName) return w;
    }
    return within.first;
  }

  /// `FileTreeView`'s add-group affordance (header (+), and
  /// `filetree.createGroup.empty` in the empty state).
  ///
  /// The ENGINE seeds the new group's General + Plugins workspaces — Swift
  /// receives them as `WorkspaceCreated` events behind `GroupCreated` and
  /// auto-expands the group so they are on screen with no reload. This does the
  /// same through the seam: create, re-read the tree, and LAND on the seeded
  /// General workspace — expanded and selected, so it is also the target the
  /// next New Board resolves to.
  ///
  /// The group that appeared is found by diffing ids, not by matching the name
  /// the operator typed: the engine mints the id, and two groups may share a
  /// name.
  Future<void> _promptNewGroup() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(
        title: 'New Group',
        label: 'Group name',
        initial: 'New Group',
        action: 'Create',
        fieldKey: ValueKey('explorer.newGroup.name'),
      ),
    );
    if (name == null || !mounted) return;

    final backend = ref.read(cyanBackendProvider);
    final before = {for (final g in _groups) g.id};
    await backend.createGroup(name);
    final after = await backend.loadGroups();
    if (!mounted) return;
    ref.invalidate(groupsProvider);

    CyanGroup? created;
    for (final g in after) {
      if (!before.contains(g.id)) {
        created = g;
        break;
      }
    }
    if (created == null) return;

    final landing = _preferredWorkspace(created.workspaces);
    setState(() {
      _expanded.add(created!.id);
      if (landing != null) _expanded.add(landing.id);
    });
    _setSelection(landing == null
        ? ExplorerSelection(
            kind: ExplorerNodeKind.group,
            id: created.id,
            name: created.name,
            groupId: created.id,
          )
        : ExplorerSelection(
            kind: ExplorerNodeKind.workspace,
            id: landing.id,
            name: landing.name,
            groupId: created.id,
            workspaceId: landing.id,
          ));
  }

  /// `FileTreeViewModel.addWorkspaceToGroup(groupId:)` — a second workspace
  /// inside an existing group, from the group row's context menu.
  Future<void> _promptNewWorkspace(String groupId) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(
        title: 'New Workspace',
        label: 'Workspace name',
        initial: 'New Workspace',
        action: 'Create',
        fieldKey: ValueKey('explorer.newWorkspace.name'),
      ),
    );
    if (name == null || !mounted) return;
    await ref.read(cyanBackendProvider).createWorkspace(groupId, name);
    if (!mounted) return;
    // `createWorkspace(in:)` expands the parent so the new row is on screen.
    setState(() => _expanded.add(groupId));
    ref.invalidate(groupsProvider);
  }

  /// The New Board sheet: a workspace picker seeded from the selection, and a
  /// name. [workspaceId] pins the target (the row context menu); the header
  /// button leaves it null so the selection decides.
  Future<void> _promptNewBoard({String? workspaceId}) async {
    final groups = _groups;
    final workspaces = [for (final g in groups) ...g.workspaces];
    if (workspaces.isEmpty) return;

    final seeded = workspaceId ?? _defaultWorkspaceIdForNewBoard(groups);
    if (seeded == null) return;

    final result = await showDialog<_NewBoard>(
      context: context,
      builder: (_) => _NewBoardDialog(groups: groups, workspaceId: seeded),
    );
    if (result == null || !mounted) return;

    await ref
        .read(cyanBackendProvider)
        .createBoard(result.workspaceId, result.name);
    if (!mounted) return;
    // Reveal it where it actually landed.
    setState(() => _expanded.add(result.workspaceId));
    ref.invalidate(groupsProvider);
  }

  Future<void> _promptRename(_Row row) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: 'Rename Board',
        label: 'Name',
        initial: row.name,
        action: 'Rename',
        fieldKey: const ValueKey('explorer.rename.field'),
      ),
    );
    if (name == null || !mounted) return;
    await ref.read(cyanBackendProvider).renameBoard(row.id, name);
    if (!mounted) return;
    ref.invalidate(groupsProvider);
  }

  /// `FileTreeRow`'s destructive delete routes through a confirm — it
  /// tombstones and syncs to peers.
  Future<void> _promptDelete(_Row row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteBoardDialog(name: row.name),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(cyanBackendProvider).deleteBoard(row.id);
    if (!mounted) return;
    if (_selection?.id == row.id) _setSelection(null);
    ref.invalidate(groupsProvider);
  }

  /// `FileTreeRow.contextMenu`. Rename/Delete are board-only here: the seam
  /// binds board mutation, not group/workspace mutation, and an affordance
  /// that cannot act is worse than no affordance.
  Future<void> _showRowMenu(_Row row, Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final size = overlay?.size ?? const Size(400, 800);
    final action = await showMenu<String>(
      context: context,
      color: MonokaiTheme.surface,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        size.width - position.dx,
        size.height - position.dy,
      ),
      items: [
        if (row.kind == ExplorerNodeKind.board) ...[
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ] else ...[
          const PopupMenuItem(value: 'newBoard', child: Text('New Board')),
          if (row.kind == ExplorerNodeKind.group)
            const PopupMenuItem(
                value: 'newWorkspace', child: Text('New Workspace')),
        ],
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'rename':
        await _promptRename(row);
      case 'delete':
        await _promptDelete(row);
      case 'newBoard':
        // A workspace row IS the target; a group row resolves through its OWN
        // General/Plugins preference — the row the operator right-clicked, not
        // whatever happens to be selected elsewhere in the tree.
        await _promptNewBoard(
          workspaceId: switch (row.kind) {
            ExplorerNodeKind.workspace => row.id,
            ExplorerNodeKind.group => _preferredWorkspace([
                for (final g in _groups)
                  if (g.id == row.groupId) ...g.workspaces,
              ])?.id,
            ExplorerNodeKind.board => null,
          },
        );
      case 'newWorkspace':
        await _promptNewWorkspace(row.groupId);
    }
  }

  // ---- tree -> visible rows ------------------------------------------------

  bool _matches(String name) =>
      _search.isEmpty || name.toLowerCase().contains(_search.toLowerCase());

  /// Flatten the group tree into the visible row list, honoring expansion and
  /// the search filter. A parent stays visible if it (or any descendant)
  /// matches; when searching, parents are force-shown so matches have context.
  List<_Row> _flatten(List<CyanGroup> groups) {
    final searching = _search.isNotEmpty;
    final rows = <_Row>[];

    for (final g in groups) {
      final groupMatch = _matches(g.name);
      final wsRows = <_Row>[];

      for (final w in g.workspaces) {
        final wsMatch = _matches(w.name);
        final boardRows = <_Row>[];

        for (final b in w.boards) {
          if (searching && !_matches(b.name) && !wsMatch && !groupMatch) {
            continue;
          }
          boardRows.add(_Row(
            id: b.id,
            name: b.name,
            level: 2,
            kind: ExplorerNodeKind.board,
            hasChildren: false,
            iconColor: _faceColor(b.activeFace),
            icon: _faceIcon(b.activeFace),
            groupId: g.id,
            workspaceId: w.id,
            board: b,
          ));
        }

        final wsVisible =
            !searching || wsMatch || groupMatch || boardRows.isNotEmpty;
        if (!wsVisible) continue;

        wsRows.add(_Row(
          id: w.id,
          name: w.name,
          level: 1,
          kind: ExplorerNodeKind.workspace,
          hasChildren: w.boards.isNotEmpty,
          iconColor: MonokaiTheme.green,
          icon: _expanded.contains(w.id) ? Icons.folder_open : Icons.folder,
          groupId: g.id,
          workspaceId: w.id,
        ));
        // Show children when expanded, or always while searching.
        if (searching || _expanded.contains(w.id)) wsRows.addAll(boardRows);
      }

      final groupVisible = !searching || groupMatch || wsRows.isNotEmpty;
      if (!groupVisible) continue;

      rows.add(_Row(
        id: g.id,
        name: g.name,
        level: 0,
        kind: ExplorerNodeKind.group,
        hasChildren: g.workspaces.isNotEmpty,
        iconColor: _hexColor(g.colorHex),
        icon: _expanded.contains(g.id) ? Icons.folder_open : Icons.folder,
        groupId: g.id,
      ));
      if (searching || _expanded.contains(g.id)) rows.addAll(wsRows);
    }
    return rows;
  }

  static Color _faceColor(BoardFaceKind f) => switch (f) {
        BoardFaceKind.workflow => MonokaiTheme.cyan,
        BoardFaceKind.notes => MonokaiTheme.green,
        BoardFaceKind.dashboard => MonokaiTheme.orange,
        BoardFaceKind.canvas => MonokaiTheme.purple,
      };

  static IconData _faceIcon(BoardFaceKind f) => switch (f) {
        BoardFaceKind.workflow => Icons.article,
        BoardFaceKind.notes => Icons.description,
        BoardFaceKind.dashboard => Icons.play_circle,
        BoardFaceKind.canvas => Icons.brush,
      };

  static Color _hexColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return MonokaiTheme.cyan;
    }
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final VoidCallback onAddGroup;
  final VoidCallback onNewBoard;
  const _Header({required this.onNewBoard, required this.onAddGroup});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Text('Files',
              style:
                  MonokaiTheme.labelLarge.copyWith(color: MonokaiTheme.comment)),
          const Spacer(),
          IconButton(
            key: const ValueKey('explorer.newGroup'),
            onPressed: onAddGroup,
            visualDensity: VisualDensity.compact,
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            tooltip: 'New group',
            icon: const Icon(Icons.create_new_folder_outlined,
                color: MonokaiTheme.comment),
          ),
          IconButton(
            key: const ValueKey('explorer.newBoard'),
            onPressed: onNewBoard,
            visualDensity: VisualDensity.compact,
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            tooltip: 'New board',
            icon: const Icon(Icons.add, color: MonokaiTheme.cyan),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: MonokaiTheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 12, color: MonokaiTheme.comment),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                key: const ValueKey('explorer.search'),
                onChanged: onChanged,
                style: MonokaiTheme.labelMedium
                    .copyWith(color: MonokaiTheme.foreground),
                cursorColor: MonokaiTheme.cyan,
                cursorWidth: 1,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Search',
                  hintStyle: MonokaiTheme.labelMedium
                      .copyWith(color: MonokaiTheme.comment),
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TreeRow extends StatefulWidget {
  final _Row row;
  final bool isExpanded;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final void Function(Offset globalPosition) onMenu;

  const _TreeRow({
    super.key,
    required this.row,
    required this.isExpanded,
    required this.isSelected,
    required this.onTap,
    required this.onToggle,
    required this.onMenu,
  });

  @override
  State<_TreeRow> createState() => _TreeRowState();
}

class _TreeRowState extends State<_TreeRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final double leadingPad = r.level * 20.0 + 8.0;

    final Color bg = widget.isSelected
        ? MonokaiTheme.cyan.withValues(alpha: 0.2)
        : _hovered
            ? MonokaiTheme.cyan.withValues(alpha: 0.08)
            : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapUp: (d) => widget.onMenu(d.globalPosition),
        onLongPressStart: (d) => widget.onMenu(d.globalPosition),
        child: Container(
          color: bg,
          padding:
              EdgeInsets.only(left: leadingPad, right: 8, top: 3, bottom: 3),
          child: Row(
            children: [
              // Chevron (or spacer to keep names aligned). Collapsing is the
              // chevron's job alone — `FileTreeRow` wires `onToggleExpand`
              // here, and only here.
              SizedBox(
                width: 12,
                child: r.hasChildren
                    ? GestureDetector(
                        key: ValueKey('explorer.chevron.${r.id}'),
                        onTap: widget.onToggle,
                        child: Icon(
                          widget.isExpanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                          size: 14,
                          color: MonokaiTheme.comment,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 4),
              Icon(r.icon, size: 13, color: r.iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MonokaiTheme.labelMedium.copyWith(
                    color: MonokaiTheme.foreground,
                    fontWeight: r.kind == ExplorerNodeKind.group
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The (workspace, name) the New Board sheet resolved to.
@immutable
class _NewBoard {
  final String workspaceId;
  final String name;
  const _NewBoard(this.workspaceId, this.name);
}

class _NewBoardDialog extends StatefulWidget {
  final List<CyanGroup> groups;
  final String workspaceId;
  const _NewBoardDialog({required this.groups, required this.workspaceId});

  @override
  State<_NewBoardDialog> createState() => _NewBoardDialogState();
}

class _NewBoardDialogState extends State<_NewBoardDialog> {
  late String _workspaceId = widget.workspaceId;
  final TextEditingController _name = TextEditingController(text: 'New Board');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(_NewBoard(_workspaceId, name));
  }

  @override
  Widget build(BuildContext context) {
    final entries = <DropdownMenuItem<String>>[
      for (final g in widget.groups)
        for (final w in g.workspaces)
          DropdownMenuItem(
            value: w.id,
            child: Text('${g.name} / ${w.name}',
                style: MonokaiTheme.labelMedium
                    .copyWith(color: MonokaiTheme.foreground)),
          ),
    ];

    return AlertDialog(
      backgroundColor: MonokaiTheme.surface,
      title: Text('New Board',
          style: MonokaiTheme.bodyMedium
              .copyWith(color: MonokaiTheme.foreground)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButton<String>(
            key: const ValueKey('explorer.newBoard.workspace'),
            value: _workspaceId,
            isExpanded: true,
            dropdownColor: MonokaiTheme.surface,
            items: entries,
            onChanged: (v) => setState(() => _workspaceId = v ?? _workspaceId),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('explorer.newBoard.name'),
            controller: _name,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            style: MonokaiTheme.labelMedium
                .copyWith(color: MonokaiTheme.foreground),
            cursorColor: MonokaiTheme.cyan,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Board name',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: MonokaiTheme.labelMedium
                  .copyWith(color: MonokaiTheme.comment)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text('Create',
              style:
                  MonokaiTheme.labelMedium.copyWith(color: MonokaiTheme.cyan)),
        ),
      ],
    );
  }
}

/// One name prompt for every node the Explorer names — rename a board, name a
/// new group, name a new workspace. `commitRename()` is the shared behaviour
/// underneath: an empty name is dropped on the floor rather than committing a
/// nameless node, and Return commits.
class _NameDialog extends StatefulWidget {
  final String title;
  final String label;
  final String initial;
  final String action;
  final Key fieldKey;

  const _NameDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.action,
    required this.fieldKey,
  });

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _c.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: MonokaiTheme.surface,
      title: Text(widget.title,
          style: MonokaiTheme.bodyMedium
              .copyWith(color: MonokaiTheme.foreground)),
      content: TextField(
        key: widget.fieldKey,
        controller: _c,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        style:
            MonokaiTheme.labelMedium.copyWith(color: MonokaiTheme.foreground),
        cursorColor: MonokaiTheme.cyan,
        decoration:
            InputDecoration(isDense: true, labelText: widget.label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: MonokaiTheme.labelMedium
                  .copyWith(color: MonokaiTheme.comment)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(widget.action,
              style:
                  MonokaiTheme.labelMedium.copyWith(color: MonokaiTheme.cyan)),
        ),
      ],
    );
  }
}

class _DeleteBoardDialog extends StatelessWidget {
  final String name;
  const _DeleteBoardDialog({required this.name});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: MonokaiTheme.surface,
      title: Text('Delete “$name”?',
          style: MonokaiTheme.bodyMedium
              .copyWith(color: MonokaiTheme.foreground)),
      content: Text(
        'This removes the board for everyone in the group. '
        'You can’t undo this.',
        style: MonokaiTheme.bodySmall
            .copyWith(color: MonokaiTheme.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel',
              style: MonokaiTheme.labelMedium
                  .copyWith(color: MonokaiTheme.comment)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('Delete',
              style:
                  MonokaiTheme.labelMedium.copyWith(color: MonokaiTheme.red)),
        ),
      ],
    );
  }
}

class _EmptyTree extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyTree({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.create_new_folder_outlined,
              size: 28, color: MonokaiTheme.comment),
          const SizedBox(height: 12),
          Text('No groups yet',
              style: MonokaiTheme.bodySmall
                  .copyWith(color: MonokaiTheme.textSecondary)),
          const SizedBox(height: 8),
          TextButton.icon(
            // `filetree.createGroup.empty` — the first-run front door.
            key: const ValueKey('explorer.newGroup.empty'),
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 14, color: MonokaiTheme.cyan),
            label: Text('Create group',
                style: MonokaiTheme.labelMedium
                    .copyWith(color: MonokaiTheme.cyan)),
          ),
        ],
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('No matches',
          style: MonokaiTheme.bodySmall
              .copyWith(color: MonokaiTheme.textMuted)),
    );
  }
}
