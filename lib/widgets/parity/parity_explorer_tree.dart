// widgets/parity/parity_explorer_tree.dart
//
// PARITY port of the SwiftUI `FileTreeView` — the Explorer / group tree
// (PARITY_TRACKER row 2). A Group -> Workspace -> Board sidebar tree with
// expand/collapse chevrons, type-colored icons, indentation, live search, and
// row selection, in the Monokai look.
//
// Driven ENTIRELY through the `CyanBackend` seam (via `groupsProvider`). This
// widget never touches `CyanFFI` directly — that is the parity rule.
//
// SwiftUI reference (read-only): cyan-iOS-ready/Cyan/Cyan/Views/FileTreeView.swift
//   - header "Files" + a cyan add (+) button
//   - a search field
//   - rows: chevron (if expandable) · type icon · name, indented by level*20+8
//   - selection tints the row cyan; tapping an expandable row also expands it

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';

/// The three kinds of node the Explorer tree renders.
enum _NodeKind { group, workspace, board }

/// A flattened, renderable tree row (computed from the group tree + the set of
/// expanded node ids + the current search filter).
@immutable
class _Row {
  final String id;
  final String name;
  final int level; // 0 group, 1 workspace, 2 board
  final _NodeKind kind;
  final bool hasChildren;
  final Color iconColor;
  final IconData icon;
  final CyanBoard? board; // non-null for board rows (for onOpenBoard)

  const _Row({
    required this.id,
    required this.name,
    required this.level,
    required this.kind,
    required this.hasChildren,
    required this.iconColor,
    required this.icon,
    this.board,
  });
}

class ParityExplorerTree extends ConsumerStatefulWidget {
  /// Tapping a board (leaf) row.
  final void Function(CyanBoard board)? onOpenBoard;

  /// Tapping the header (+) button. UI-only here; wiring lands with create flows.
  final VoidCallback? onAddGroup;

  const ParityExplorerTree({super.key, this.onOpenBoard, this.onAddGroup});

  @override
  ConsumerState<ParityExplorerTree> createState() => _ParityExplorerTreeState();
}

class _ParityExplorerTreeState extends ConsumerState<ParityExplorerTree> {
  // Expansion + selection are local UI state (the engine doesn't own them).
  final Set<String> _expanded = <String>{};
  String? _selectedId;
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
          _Header(onAdd: widget.onAddGroup),
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
                if (groups.isEmpty) return _EmptyTree(onAdd: widget.onAddGroup);
                if (rows.isEmpty) return const _NoMatches();
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _TreeRow(
                    row: rows[i],
                    isExpanded: _expanded.contains(rows[i].id),
                    isSelected: _selectedId == rows[i].id,
                    onTap: () => _onTap(rows[i]),
                    onToggle: () => _toggle(rows[i].id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _onTap(_Row row) {
    setState(() => _selectedId = row.id);
    if (row.kind == _NodeKind.board) {
      if (row.board != null) widget.onOpenBoard?.call(row.board!);
      return;
    }
    // Expanding/collapsing on tap mirrors the SwiftUI row behavior.
    _toggle(row.id);
  }

  void _toggle(String id) {
    setState(() {
      if (!_expanded.remove(id)) _expanded.add(id);
    });
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
            kind: _NodeKind.board,
            hasChildren: false,
            iconColor: _faceColor(b.activeFace),
            icon: _faceIcon(b.activeFace),
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
          kind: _NodeKind.workspace,
          hasChildren: w.boards.isNotEmpty,
          iconColor: MonokaiTheme.green,
          icon: _expanded.contains(w.id)
              ? Icons.folder_open
              : Icons.folder,
        ));
        // Show children when expanded, or always while searching.
        if (searching || _expanded.contains(w.id)) wsRows.addAll(boardRows);
      }

      final groupVisible =
          !searching || groupMatch || wsRows.isNotEmpty;
      if (!groupVisible) continue;

      rows.add(_Row(
        id: g.id,
        name: g.name,
        level: 0,
        kind: _NodeKind.group,
        hasChildren: g.workspaces.isNotEmpty,
        iconColor: _hexColor(g.colorHex),
        icon: _expanded.contains(g.id) ? Icons.folder_open : Icons.folder,
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
  final VoidCallback? onAdd;
  const _Header({this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Text('Files',
              style: MonokaiTheme.labelLarge
                  .copyWith(color: MonokaiTheme.comment)),
          const Spacer(),
          IconButton(
            onPressed: onAdd,
            visualDensity: VisualDensity.compact,
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            tooltip: 'New group',
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

  const _TreeRow({
    required this.row,
    required this.isExpanded,
    required this.isSelected,
    required this.onTap,
    required this.onToggle,
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
        child: Container(
          color: bg,
          padding: EdgeInsets.only(
              left: leadingPad, right: 8, top: 3, bottom: 3),
          child: Row(
            children: [
              // Chevron (or spacer to keep names aligned).
              SizedBox(
                width: 12,
                child: r.hasChildren
                    ? GestureDetector(
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
                    fontWeight: r.kind == _NodeKind.group
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

class _EmptyTree extends StatelessWidget {
  final VoidCallback? onAdd;
  const _EmptyTree({this.onAdd});

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
