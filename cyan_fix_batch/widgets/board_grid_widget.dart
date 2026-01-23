// widgets/board_grid_widget.dart
// Pinterest-style masonry grid with search, filter, sort, and pin support

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/selection_provider.dart';
import '../providers/file_tree_provider.dart';
import '../models/tree_item.dart';

/// Sort options for board grid
enum BoardSortOption {
  lastModified('Last Modified', Icons.access_time),
  name('Name', Icons.sort_by_alpha),
  created('Created', Icons.calendar_today),
  rating('Rating', Icons.star);

  final String label;
  final IconData icon;
  const BoardSortOption(this.label, this.icon);
}

class BoardGridWidget extends ConsumerStatefulWidget {
  const BoardGridWidget({super.key});

  @override
  ConsumerState<BoardGridWidget> createState() => _BoardGridWidgetState();
}

class _BoardGridWidgetState extends ConsumerState<BoardGridWidget> {
  final _searchController = TextEditingController();
  String _searchText = '';
  BoardSortOption _sortOption = BoardSortOption.lastModified;
  bool _showPinnedOnly = false;
  final Set<String> _selectedLabels = {};
  final bool _isDropTargeted = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(selectionProvider);
    final treeState = ref.watch(fileTreeProvider);
    
    // Get boards for selected workspace
    List<TreeBoard> boards = [];
    String contextTitle = 'All Boards';
    
    if (selection.selectedWorkspaceId != null) {
      for (final group in treeState.groups) {
        for (final workspace in group.workspaces) {
          if (workspace.id == selection.selectedWorkspaceId) {
            boards = workspace.boards;
            contextTitle = workspace.name;
            break;
          }
        }
      }
    }
    
    // Filter boards
    var filteredBoards = boards.where((b) {
      if (_searchText.isNotEmpty) {
        return b.name.toLowerCase().contains(_searchText.toLowerCase());
      }
      return true;
    }).toList();

    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _GridHeader(
            title: contextTitle,
            boardCount: filteredBoards.length,
            pinnedCount: 0, // TODO: Get from metadata
            onRefresh: () {
              ref.read(fileTreeProvider.notifier).refresh();
            },
          ),
          
          const Divider(height: 1, color: Color(0xFF3E3D32)),
          
          // Search and filter bar
          _SearchFilterBar(
            searchController: _searchController,
            onSearchChanged: (value) => setState(() => _searchText = value),
            sortOption: _sortOption,
            onSortChanged: (option) => setState(() => _sortOption = option),
            showPinnedOnly: _showPinnedOnly,
            onPinnedToggle: () => setState(() => _showPinnedOnly = !_showPinnedOnly),
            selectedLabels: _selectedLabels,
            onLabelToggle: (label) {
              setState(() {
                if (_selectedLabels.contains(label)) {
                  _selectedLabels.remove(label);
                } else {
                  _selectedLabels.add(label);
                }
              });
            },
          ),
          
          // Grid content
          Expanded(
            child: selection.selectedWorkspaceId == null
                ? const _SelectWorkspaceView()
                : filteredBoards.isEmpty
                    ? _EmptyBoardsView(onCreateBoard: () => _showCreateBoardDialog(context))
                    : _MasonryGrid(
                        boards: filteredBoards,
                        onBoardTap: (board) {
                          ref.read(selectionProvider.notifier).selectBoard(
                            groupId: selection.selectedGroupId!,
                            workspaceId: selection.selectedWorkspaceId!,
                            workspaceName: selection.selectedWorkspaceName!,
                            boardId: board.id,
                            boardName: board.name,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _showCreateBoardDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252525),
        title: const Text('New Board', style: TextStyle(color: Color(0xFFF8F8F2))),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFF8F8F2)),
          decoration: InputDecoration(
            hintText: 'Board name',
            hintStyle: const TextStyle(color: Color(0xFF808080)),
            filled: true,
            fillColor: const Color(0xFF1E1E1E),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF3E3D32)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF808080))),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref.read(selectionProvider.notifier).createBoard(controller.text.trim());
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFA6E22E),
              foregroundColor: const Color(0xFF1E1E1E),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _GridHeader extends StatelessWidget {
  final String title;
  final int boardCount;
  final int pinnedCount;
  final VoidCallback onRefresh;

  const _GridHeader({
    required this.title,
    required this.boardCount,
    required this.pinnedCount,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: Color(0xFFF8F8F2),
                    ),
                  ),
                  if (pinnedCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFD971F).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.push_pin, size: 10, color: Color(0xFFFD971F)),
                          const SizedBox(width: 3),
                          Text(
                            '$pinnedCount',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFD971F),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '$boardCount board${boardCount == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Color(0xFF808080),
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 18),
            color: const Color(0xFF66D9EF),
            tooltip: 'Refresh boards',
          ),
        ],
      ),
    );
  }
}

class _SearchFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final BoardSortOption sortOption;
  final ValueChanged<BoardSortOption> onSortChanged;
  final bool showPinnedOnly;
  final VoidCallback onPinnedToggle;
  final Set<String> selectedLabels;
  final ValueChanged<String> onLabelToggle;

  const _SearchFilterBar({
    required this.searchController,
    required this.onSearchChanged,
    required this.sortOption,
    required this.onSortChanged,
    required this.showPinnedOnly,
    required this.onPinnedToggle,
    required this.selectedLabels,
    required this.onLabelToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          // Search field
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF252525).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 14, color: Color(0xFF808080)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      onChanged: onSearchChanged,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Color(0xFFF8F8F2),
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Search boards...',
                        hintStyle: TextStyle(color: Color(0xFF808080)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  if (searchController.text.isNotEmpty)
                    IconButton(
                      onPressed: () {
                        searchController.clear();
                        onSearchChanged('');
                      },
                      icon: const Icon(Icons.close, size: 14),
                      color: const Color(0xFF808080),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(width: 10),
          
          // Filter button
          _FilterButton(
            selectedCount: selectedLabels.length,
            onTap: () {
              // Show filter popover
            },
          ),
          
          const SizedBox(width: 8),
          
          // Sort button
          _SortButton(
            currentSort: sortOption,
            onSortChanged: onSortChanged,
          ),
          
          const SizedBox(width: 8),
          
          // Pinned only toggle
          _PinnedToggle(
            isActive: showPinnedOnly,
            onToggle: onPinnedToggle,
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatefulWidget {
  final int selectedCount;
  final VoidCallback onTap;

  const _FilterButton({
    required this.selectedCount,
    required this.onTap,
  });

  @override
  State<_FilterButton> createState() => _FilterButtonState();
}

class _FilterButtonState extends State<_FilterButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _isHovered
                ? const Color(0xFF3E3D32)
                : const Color(0xFF252525).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.filter_list,
                size: 14,
                color: widget.selectedCount > 0
                    ? const Color(0xFF66D9EF)
                    : const Color(0xFF808080),
              ),
              if (widget.selectedCount > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '${widget.selectedCount}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF66D9EF),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SortButton extends StatefulWidget {
  final BoardSortOption currentSort;
  final ValueChanged<BoardSortOption> onSortChanged;

  const _SortButton({
    required this.currentSort,
    required this.onSortChanged,
  });

  @override
  State<_SortButton> createState() => _SortButtonState();
}

class _SortButtonState extends State<_SortButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: PopupMenuButton<BoardSortOption>(
        onSelected: widget.onSortChanged,
        color: const Color(0xFF252525),
        itemBuilder: (context) => BoardSortOption.values.map((option) {
          return PopupMenuItem<BoardSortOption>(
            value: option,
            child: Row(
              children: [
                Icon(
                  option.icon,
                  size: 14,
                  color: widget.currentSort == option
                      ? const Color(0xFF66D9EF)
                      : const Color(0xFF808080),
                ),
                const SizedBox(width: 8),
                Text(
                  option.label,
                  style: TextStyle(
                    color: widget.currentSort == option
                        ? const Color(0xFF66D9EF)
                        : const Color(0xFFF8F8F2),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _isHovered
                ? const Color(0xFF3E3D32)
                : const Color(0xFF252525).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            widget.currentSort.icon,
            size: 14,
            color: const Color(0xFF808080),
          ),
        ),
      ),
    );
  }
}

class _PinnedToggle extends StatefulWidget {
  final bool isActive;
  final VoidCallback onToggle;

  const _PinnedToggle({
    required this.isActive,
    required this.onToggle,
  });

  @override
  State<_PinnedToggle> createState() => _PinnedToggleState();
}

class _PinnedToggleState extends State<_PinnedToggle> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onToggle,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: widget.isActive
                ? const Color(0xFFFD971F).withValues(alpha: 0.15)
                : (_isHovered
                    ? const Color(0xFF3E3D32)
                    : const Color(0xFF252525).withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            widget.isActive ? Icons.push_pin : Icons.push_pin_outlined,
            size: 14,
            color: widget.isActive ? const Color(0xFFFD971F) : const Color(0xFF808080),
          ),
        ),
      ),
    );
  }
}

class _SelectWorkspaceView extends StatelessWidget {
  const _SelectWorkspaceView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 64, color: Color(0xFF606060)),
          SizedBox(height: 16),
          Text(
            'Select a workspace',
            style: TextStyle(fontSize: 18, color: Color(0xFF808080)),
          ),
          SizedBox(height: 8),
          Text(
            'Choose a workspace from the explorer to see boards',
            style: TextStyle(fontSize: 13, color: Color(0xFF606060)),
          ),
        ],
      ),
    );
  }
}

class _EmptyBoardsView extends StatelessWidget {
  final VoidCallback onCreateBoard;

  const _EmptyBoardsView({required this.onCreateBoard});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.dashboard_outlined, size: 64, color: Color(0xFF606060)),
          const SizedBox(height: 16),
          const Text(
            'No boards yet',
            style: TextStyle(fontSize: 18, color: Color(0xFF808080)),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onCreateBoard,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Create your first board'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF66D9EF),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinterest-style masonry grid
class _MasonryGrid extends StatelessWidget {
  final List<TreeBoard> boards;
  final ValueChanged<TreeBoard> onBoardTap;

  const _MasonryGrid({
    required this.boards,
    required this.onBoardTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate column count based on width
        const minCardWidth = 220.0;
        const spacing = 16.0;
        final columnCount = max(2, (constraints.maxWidth / minCardWidth).floor());
        final cardWidth = (constraints.maxWidth - (columnCount + 1) * spacing) / columnCount;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: boards.map((board) {
              // Vary height for masonry effect
              final heightVariation = (board.name.hashCode % 3) * 30.0;
              final cardHeight = 140.0 + heightVariation;

              return SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: _BoardCard(
                  board: board,
                  onTap: () => onBoardTap(board),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _BoardCard extends StatefulWidget {
  final TreeBoard board;
  final VoidCallback onTap;

  const _BoardCard({
    required this.board,
    required this.onTap,
  });

  @override
  State<_BoardCard> createState() => _BoardCardState();
}

class _BoardCardState extends State<_BoardCard> {
  bool _isHovered = false;

  IconData get _boardIcon {
    switch (widget.board.boardType) {
      case 'canvas':
        return Icons.brush;
      case 'notebook':
        return Icons.book;
      case 'notes':
        return Icons.article;
      default:
        return Icons.dashboard;
    }
  }

  Color get _boardColor {
    switch (widget.board.boardType) {
      case 'canvas':
        return const Color(0xFFFD971F);
      case 'notebook':
        return const Color(0xFF66D9EF);
      case 'notes':
        return const Color(0xFFA6E22E);
      default:
        return const Color(0xFF808080);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: const Color(0xFF252525),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered ? const Color(0xFF66D9EF) : const Color(0xFF3E3D32),
              width: _isHovered ? 2 : 1,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: const Color(0xFF66D9EF).withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Preview area
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
                  ),
                  child: Center(
                    child: Icon(
                      _boardIcon,
                      size: 40,
                      color: _boardColor.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
              
              // Info section
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_boardIcon, size: 14, color: _boardColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.board.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFF8F8F2),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.board.hasUnread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFA6E22E),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (widget.board.lastModified != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(widget.board.lastModified!),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF808080),
                        ),
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    
    return '${date.month}/${date.day}/${date.year}';
  }
}
