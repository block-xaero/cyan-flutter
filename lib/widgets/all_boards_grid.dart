// widgets/all_boards_grid.dart
// Pinterest-style masonry grid showing ALL boards from all groups/workspaces
// With grouping headers, search, filter, sort

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/file_tree_provider.dart';
import '../providers/selection_provider.dart';
import '../models/tree_item.dart';

/// Board with context (which group/workspace it belongs to)
class BoardWithContext {
  final TreeBoard board;
  final TreeGroup group;
  final TreeWorkspace workspace;

  BoardWithContext({required this.board, required this.group, required this.workspace});
}

enum BoardSortOption {
  lastModified('Last Modified', Icons.access_time),
  name('Name', Icons.sort_by_alpha),
  created('Created', Icons.calendar_today),
  group('Group', Icons.folder);

  final String label;
  final IconData icon;
  const BoardSortOption(this.label, this.icon);
}

class AllBoardsGrid extends ConsumerStatefulWidget {
  const AllBoardsGrid({super.key});

  @override
  ConsumerState<AllBoardsGrid> createState() => _AllBoardsGridState();
}

class _AllBoardsGridState extends ConsumerState<AllBoardsGrid> {
  final _searchController = TextEditingController();
  String _searchText = '';
  BoardSortOption _sortOption = BoardSortOption.lastModified;
  bool _groupByWorkspace = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BoardWithContext> _getAllBoards(FileTreeState state) {
    final boards = <BoardWithContext>[];
    for (final group in state.groups) {
      for (final workspace in group.workspaces) {
        for (final board in workspace.boards) {
          boards.add(BoardWithContext(board: board, group: group, workspace: workspace));
        }
      }
    }
    return boards;
  }

  List<BoardWithContext> _filterAndSort(List<BoardWithContext> boards) {
    var filtered = boards.where((b) {
      if (_searchText.isEmpty) return true;
      final search = _searchText.toLowerCase();
      return b.board.name.toLowerCase().contains(search) ||
          b.group.name.toLowerCase().contains(search) ||
          b.workspace.name.toLowerCase().contains(search);
    }).toList();

    filtered.sort((a, b) {
      switch (_sortOption) {
        case BoardSortOption.name:
          return a.board.name.compareTo(b.board.name);
        case BoardSortOption.created:
          return b.board.createdAt.compareTo(a.board.createdAt);
        case BoardSortOption.group:
          final groupCmp = a.group.name.compareTo(b.group.name);
          if (groupCmp != 0) return groupCmp;
          return a.workspace.name.compareTo(b.workspace.name);
        case BoardSortOption.lastModified:
        default:
          final aTime = a.board.lastModified?.millisecondsSinceEpoch ?? a.board.createdAt;
          final bTime = b.board.lastModified?.millisecondsSinceEpoch ?? b.board.createdAt;
          return bTime.compareTo(aTime);
      }
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final treeState = ref.watch(fileTreeProvider);
    final allBoards = _getAllBoards(treeState);
    final filteredBoards = _filterAndSort(allBoards);

    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          // Header
          _Header(
            totalBoards: allBoards.length,
            filteredBoards: filteredBoards.length,
            onRefresh: () => ref.read(fileTreeProvider.notifier).refresh(),
          ),
          const Divider(height: 1, color: Color(0xFF3E3D32)),

          // Search & Filter bar
          _SearchBar(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchText = v),
            sortOption: _sortOption,
            onSortChanged: (v) => setState(() => _sortOption = v),
            groupByWorkspace: _groupByWorkspace,
            onGroupToggle: () => setState(() => _groupByWorkspace = !_groupByWorkspace),
          ),

          // Grid
          Expanded(
            child: treeState.isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF66D9EF)))
                : filteredBoards.isEmpty
                    ? _EmptyView(hasBoards: allBoards.isNotEmpty)
                    : _groupByWorkspace
                        ? _GroupedGrid(boards: filteredBoards, onBoardTap: _onBoardTap)
                        : _FlatGrid(boards: filteredBoards, onBoardTap: _onBoardTap),
          ),
        ],
      ),
    );
  }

  void _onBoardTap(BoardWithContext board) {
    ref.read(selectionProvider.notifier).selectBoard(
      groupId: board.group.id,
      workspaceId: board.workspace.id,
      workspaceName: board.workspace.name,
      boardId: board.board.id,
      boardName: board.board.name,
    );
  }
}

class _Header extends StatelessWidget {
  final int totalBoards;
  final int filteredBoards;
  final VoidCallback onRefresh;

  const _Header({required this.totalBoards, required this.filteredBoards, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.dashboard, size: 24, color: Color(0xFF66D9EF)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'All Boards',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFFF8F8F2)),
              ),
              Text(
                filteredBoards == totalBoards
                    ? '$totalBoards boards'
                    : '$filteredBoards of $totalBoards boards',
                style: const TextStyle(fontSize: 11, color: Color(0xFF808080)),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 18),
            color: const Color(0xFF66D9EF),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final BoardSortOption sortOption;
  final ValueChanged<BoardSortOption> onSortChanged;
  final bool groupByWorkspace;
  final VoidCallback onGroupToggle;

  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.sortOption,
    required this.onSortChanged,
    required this.groupByWorkspace,
    required this.onGroupToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          // Search
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 14, color: Color(0xFF808080)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      onChanged: onChanged,
                      style: const TextStyle(fontSize: 12, color: Color(0xFFF8F8F2)),
                      decoration: const InputDecoration(
                        hintText: 'Search all boards...',
                        hintStyle: TextStyle(color: Color(0xFF808080)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  if (controller.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        controller.clear();
                        onChanged('');
                      },
                      child: const Icon(Icons.close, size: 14, color: Color(0xFF808080)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Group toggle
          _ToggleButton(
            icon: Icons.folder_outlined,
            label: 'Group',
            isActive: groupByWorkspace,
            onTap: onGroupToggle,
          ),
          const SizedBox(width: 8),

          // Sort
          PopupMenuButton<BoardSortOption>(
            onSelected: onSortChanged,
            color: const Color(0xFF252525),
            itemBuilder: (ctx) => BoardSortOption.values.map((opt) {
              return PopupMenuItem(
                value: opt,
                child: Row(
                  children: [
                    Icon(opt.icon, size: 14, color: sortOption == opt ? const Color(0xFF66D9EF) : const Color(0xFF808080)),
                    const SizedBox(width: 8),
                    Text(opt.label, style: TextStyle(color: sortOption == opt ? const Color(0xFF66D9EF) : const Color(0xFFF8F8F2))),
                  ],
                ),
              );
            }).toList(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF252525), borderRadius: BorderRadius.circular(6)),
              child: Icon(sortOption.icon, size: 14, color: const Color(0xFF808080)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ToggleButton({required this.icon, required this.label, required this.isActive, required this.onTap});

  @override
  State<_ToggleButton> createState() => _ToggleButtonState();
}

class _ToggleButtonState extends State<_ToggleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isActive ? const Color(0xFF66D9EF).withOpacity(0.15) : (_hovered ? const Color(0xFF3E3D32) : const Color(0xFF252525)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 14, color: widget.isActive ? const Color(0xFF66D9EF) : const Color(0xFF808080)),
              const SizedBox(width: 6),
              Text(widget.label, style: TextStyle(fontSize: 11, color: widget.isActive ? const Color(0xFF66D9EF) : const Color(0xFF808080))),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final bool hasBoards;
  const _EmptyView({required this.hasBoards});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(hasBoards ? Icons.search_off : Icons.dashboard_outlined, size: 64, color: const Color(0xFF606060)),
          const SizedBox(height: 16),
          Text(
            hasBoards ? 'No boards match your search' : 'No boards yet',
            style: const TextStyle(fontSize: 18, color: Color(0xFF808080)),
          ),
          const SizedBox(height: 8),
          Text(
            hasBoards ? 'Try a different search term' : 'Create a group and workspace to get started',
            style: const TextStyle(fontSize: 13, color: Color(0xFF606060)),
          ),
        ],
      ),
    );
  }
}

/// Grouped by workspace with section headers
class _GroupedGrid extends StatelessWidget {
  final List<BoardWithContext> boards;
  final ValueChanged<BoardWithContext> onBoardTap;

  const _GroupedGrid({required this.boards, required this.onBoardTap});

  @override
  Widget build(BuildContext context) {
    // Group by workspace
    final grouped = <String, List<BoardWithContext>>{};
    for (final b in boards) {
      final key = '${b.group.id}:${b.workspace.id}';
      grouped.putIfAbsent(key, () => []).add(b);
    }

    // Build flat list of widgets (headers + board rows)
    final widgets = <Widget>[];
    
    for (int i = 0; i < grouped.length; i++) {
      final key = grouped.keys.elementAt(i);
      final items = grouped[key]!;
      final first = items.first;

      // Section header
      widgets.add(
        Padding(
          padding: EdgeInsets.only(bottom: 12, top: i > 0 ? 24 : 0, left: 16, right: 16),
          child: Row(
            children: [
              Icon(Icons.folder, size: 16, color: _parseColor(first.group.color)),
              const SizedBox(width: 8),
              Text(first.group.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFF8F8F2))),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 14, color: Color(0xFF808080)),
              const SizedBox(width: 6),
              const Icon(Icons.workspaces_outline, size: 14, color: Color(0xFFA6E22E)),
              const SizedBox(width: 6),
              Text(first.workspace.name, style: const TextStyle(fontSize: 13, color: Color(0xFFA6E22E))),
              const SizedBox(width: 8),
              Text('(${items.length})', style: const TextStyle(fontSize: 11, color: Color(0xFF808080))),
            ],
          ),
        ),
      );

      // Board cards as GridView
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 250,
              childAspectRatio: 1.3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (ctx, idx) => _BoardCard(
              board: items[idx],
              onTap: () => onBoardTap(items[idx]),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      children: widgets,
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return const Color(0xFF66D9EF);
    }
  }
}

/// Flat masonry grid (no grouping)
class _FlatGrid extends StatelessWidget {
  final List<BoardWithContext> boards;
  final ValueChanged<BoardWithContext> onBoardTap;

  const _FlatGrid({required this.boards, required this.onBoardTap});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 250,
        childAspectRatio: 0.85,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: boards.length,
      itemBuilder: (ctx, i) => _BoardCard(
        board: boards[i],
        onTap: () => onBoardTap(boards[i]),
        showContext: true,
      ),
    );
  }
}

class _BoardCard extends StatefulWidget {
  final BoardWithContext board;
  final VoidCallback onTap;
  final bool showContext;

  const _BoardCard({required this.board, required this.onTap, this.showContext = false});

  @override
  State<_BoardCard> createState() => _BoardCardState();
}

class _BoardCardState extends State<_BoardCard> {
  bool _hovered = false;

  IconData get _icon => switch (widget.board.board.boardType) {
    'canvas' => Icons.brush,
    'notebook' => Icons.book,
    'notes' => Icons.article,
    _ => Icons.dashboard,
  };

  Color get _color => switch (widget.board.board.boardType) {
    'canvas' => const Color(0xFFFD971F),
    'notebook' => const Color(0xFF66D9EF),
    'notes' => const Color(0xFFA6E22E),
    _ => const Color(0xFF808080),
  };

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: const Color(0xFF252525),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered ? const Color(0xFF66D9EF) : const Color(0xFF3E3D32),
              width: _hovered ? 2 : 1,
            ),
            boxShadow: _hovered ? [BoxShadow(color: const Color(0xFF66D9EF).withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))] : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Preview
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
                  ),
                  child: Center(child: Icon(_icon, size: 40, color: _color.withOpacity(0.3))),
                ),
              ),

              // Info
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_icon, size: 14, color: _color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.board.board.name,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFF8F8F2)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.board.board.hasUnread)
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFA6E22E), shape: BoxShape.circle)),
                      ],
                    ),
                    if (widget.showContext) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${widget.board.group.name} / ${widget.board.workspace.name}',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF808080)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (widget.board.board.lastModified != null) ...[
                      const SizedBox(height: 4),
                      Text(_formatDate(widget.board.board.lastModified!), style: const TextStyle(fontSize: 10, color: Color(0xFF808080))),
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

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}';
  }
}
