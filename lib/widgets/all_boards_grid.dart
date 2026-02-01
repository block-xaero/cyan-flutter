// widgets/all_boards_grid.dart
// Pinterest-style masonry grid showing ALL boards from all groups/workspaces
// With grouping headers, search, filter, sort

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/file_tree_provider.dart';
import '../providers/selection_provider.dart';
import '../models/tree_item.dart';
import '../ffi/ffi_helpers.dart';

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

  List<BoardWithContext> _getAllBoards(FileTreeState state, SelectionState selection) {
    final boards = <BoardWithContext>[];
    
    for (final group in state.groups) {
      // If group is selected, only show boards from that group
      if (selection.groupId != null && group.id != selection.groupId) {
        continue;
      }
      
      for (final workspace in group.workspaces) {
        // If workspace is selected, only show boards from that workspace
        if (selection.workspaceId != null && workspace.id != selection.workspaceId) {
          continue;
        }
        
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
          final aTime = a.board.lastModified?.millisecondsSinceEpoch ?? a.board.createdAt.millisecondsSinceEpoch;
          final bTime = b.board.lastModified?.millisecondsSinceEpoch ?? b.board.createdAt.millisecondsSinceEpoch;
          return bTime.compareTo(aTime);
      }
    });

    return filtered;
  }
  
  String _getScopeLabel(SelectionState selection) {
    if (selection.workspaceId != null) {
      return selection.workspaceName ?? 'Workspace';
    }
    if (selection.groupId != null) {
      return selection.groupName ?? 'Group';
    }
    return 'All Boards';
  }

  @override
  Widget build(BuildContext context) {
    final treeState = ref.watch(fileTreeProvider);
    final selection = ref.watch(selectionProvider);
    final allBoards = _getAllBoards(treeState, selection);
    final filteredBoards = _filterAndSort(allBoards);
    final scopeLabel = _getScopeLabel(selection);

    return Material(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          // Header with scope indicator
          _Header(
            scopeLabel: scopeLabel,
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
                    ? _EmptyView(hasBoards: allBoards.isNotEmpty, scopeLabel: scopeLabel)
                    : _groupByWorkspace
                        ? _GroupedGrid(boards: filteredBoards, onBoardTap: _onBoardTap)
                        : _FlatGrid(boards: filteredBoards, onBoardTap: _onBoardTap),
          ),
        ],
      ),
    );
  }

  void _onBoardTap(BoardWithContext board) {
    ref.read(selectionProvider.notifier).selectBoardNamed(
      groupId: board.group.id,
      workspaceId: board.workspace.id,
      workspaceName: board.workspace.name,
      boardId: board.board.id,
      boardName: board.board.name,
    );
  }
}

class _Header extends StatelessWidget {
  final String scopeLabel;
  final int totalBoards;
  final int filteredBoards;
  final VoidCallback onRefresh;

  const _Header({required this.scopeLabel, required this.totalBoards, required this.filteredBoards, required this.onRefresh});

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
              Text(
                scopeLabel,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFFF8F8F2)),
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
  final String scopeLabel;
  const _EmptyView({required this.hasBoards, required this.scopeLabel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(hasBoards ? Icons.search_off : Icons.dashboard_outlined, size: 64, color: const Color(0xFF606060)),
          const SizedBox(height: 16),
          Text(
            hasBoards ? 'No boards match your search' : 'No boards in $scopeLabel',
            style: const TextStyle(fontSize: 18, color: Color(0xFF808080)),
          ),
          const SizedBox(height: 8),
          Text(
            hasBoards ? 'Try a different search term' : 'Create a board to get started',
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate card width
        const minCardWidth = 280.0;
        const spacing = 16.0;
        const padding = 20.0;
        
        final availableWidth = constraints.maxWidth - (padding * 2);
        final columnCount = ((availableWidth + spacing) / (minCardWidth + spacing)).floor().clamp(1, 5);
        final cardWidth = (availableWidth - (spacing * (columnCount - 1))) / columnCount;

        // Build flat list of widgets (headers + board rows)
        final widgets = <Widget>[];
        
        for (int i = 0; i < grouped.length; i++) {
          final key = grouped.keys.elementAt(i);
          final items = grouped[key]!;
          final first = items.first;

          // Section header
          widgets.add(
            Padding(
              padding: EdgeInsets.only(bottom: 12, top: i > 0 ? 24 : 0, left: padding, right: padding),
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

          // Board cards as Wrap (no fixed aspect ratio)
          widgets.add(
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: items.map((board) => SizedBox(
                  width: cardWidth,
                  child: _BoardCard(
                    board: board,
                    onTap: () => onBoardTap(board),
                  ),
                )).toList(),
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.only(top: 16, bottom: 16),
          children: widgets,
        );
      },
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

/// Flat masonry grid (no grouping) - using Wrap for natural sizing
class _FlatGrid extends StatelessWidget {
  final List<BoardWithContext> boards;
  final ValueChanged<BoardWithContext> onBoardTap;

  const _FlatGrid({required this.boards, required this.onBoardTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate card width based on available space
        const minCardWidth = 280.0;
        const spacing = 16.0;
        const padding = 20.0;
        
        final availableWidth = constraints.maxWidth - (padding * 2);
        final columnCount = ((availableWidth + spacing) / (minCardWidth + spacing)).floor().clamp(1, 5);
        final cardWidth = (availableWidth - (spacing * (columnCount - 1))) / columnCount;
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(padding),
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: boards.map((board) => SizedBox(
              width: cardWidth,
              child: _BoardCard(
                board: board,
                onTap: () => onBoardTap(board),
                showContext: true,
              ),
            )).toList(),
          ),
        );
      },
    );
  }
  
  // Preview height only (not total card height)
  static double _getPreviewHeight(String boardId) {
    final hash = boardId.hashCode.abs();
    const heights = [120.0, 140.0, 160.0, 180.0, 200.0];
    return heights[hash % heights.length];
  }
}

class _BoardCard extends ConsumerStatefulWidget {
  final BoardWithContext board;
  final VoidCallback onTap;
  final bool showContext;

  const _BoardCard({required this.board, required this.onTap, this.showContext = false});

  @override
  ConsumerState<_BoardCard> createState() => _BoardCardState();
}

class _BoardCardState extends ConsumerState<_BoardCard> {
  bool _hovered = false;
  
  // Loaded from FFI
  bool _isPinned = false;
  String _activeFace = 'canvas';
  List<String> _labels = [];
  int _rating = 0;
  bool _metadataLoaded = false;
  
  @override
  void initState() {
    super.initState();
    // Always load metadata on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMetadataAsync();
    });
  }
  
  @override
  void didUpdateWidget(_BoardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.board.board.id != widget.board.board.id) {
      _resetAndReload();
    }
  }
  
  // Force reload when we navigate back to the grid
  void _resetAndReload() {
    _metadataLoaded = false;
    _notesPreview = '';
    _notebookCells = [];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMetadataAsync();
    });
  }
  
  Future<void> _loadMetadataAsync() async {
    // Allow reload by not checking _metadataLoaded at the start
    final boardId = widget.board.board.id;
    
    // Use Future.delayed to ensure this doesn't block initial render
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    
    // Load metadata from FFI
    try {
      _isPinned = CyanFFI.isBoardPinned(boardId);
      
      final mode = CyanFFI.getBoardMode(boardId);
      if (mode != null && mode.isNotEmpty) {
        _activeFace = mode;
        debugPrint('BoardCard[$boardId]: mode=$_activeFace');
      }
      
      final metadataJson = CyanFFI.getBoardMetadata(boardId);
      if (metadataJson != null && metadataJson.isNotEmpty) {
        final metadata = json.decode(metadataJson) as Map<String, dynamic>;
        _labels = (metadata['labels'] as List<dynamic>?)?.cast<String>() ?? [];
        _rating = metadata['rating'] as int? ?? 0;
      }
      
      // Load notebook cells for all face types (they share the same storage)
      final cellsJson = CyanFFI.loadNotebookCells(boardId);
      debugPrint('BoardCard[$boardId]: loadNotebookCells returned ${cellsJson?.length ?? 0} bytes');
      
      if (cellsJson != null && cellsJson.isNotEmpty) {
        try {
          final cells = json.decode(cellsJson) as List<dynamic>;
          debugPrint('BoardCard[$boardId]: Found ${cells.length} cells');
          
          _notebookCells = cells.map((cell) {
            final cellMap = cell as Map<String, dynamic>;
            final cellType = cellMap['cell_type'] as String? ?? 'markdown';
            final content = cellMap['content'] as String? ?? '';
            
            // Extract preview text (first line, strip headers)
            String preview = '';
            if (content.isNotEmpty) {
              final firstLine = content.split('\n').first;
              preview = firstLine
                  .replaceAll(RegExp(r'^#+\s*'), '') // Strip markdown headers
                  .trim();
              if (preview.length > 50) {
                preview = '${preview.substring(0, 50)}...';
              }
            }
            
            return _CellPreview(type: cellType, preview: preview, fullContent: content);
          }).toList();
          
          // Always extract notes preview from first markdown cell (for notes face display)
          if (_notebookCells.isNotEmpty) {
            final markdownCell = _notebookCells.firstWhere(
              (c) => c.type == 'markdown' && c.fullContent.isNotEmpty,
              orElse: () => _notebookCells.first,
            );
            final content = markdownCell.fullContent;
            if (content.isNotEmpty) {
              _notesPreview = content.length > 300 
                  ? '${content.substring(0, 300)}...' 
                  : content;
              debugPrint('BoardCard[$boardId]: notesPreview length=${_notesPreview.length}');
            }
          }
        } catch (e) {
          debugPrint('Error parsing cells for $boardId: $e');
        }
      } else {
        debugPrint('BoardCard[$boardId]: No cells found');
      }
    } catch (e) {
      debugPrint('Board metadata load error for $boardId: $e');
    }
    
    _metadataLoaded = true;
    if (mounted) setState(() {});
  }
  
  // Content previews
  String _notesPreview = '';

  IconData get _icon => switch (_activeFace) {
    'canvas' => Icons.brush,
    'notebook' => Icons.article,
    'notes' => Icons.description,
    _ => Icons.dashboard,
  };

  String get _faceLabel => switch (_activeFace) {
    'canvas' => 'Canvas',
    'notebook' => 'Notebook',
    'notes' => 'Notes',
    _ => 'Board',
  };

  Color get _color => switch (_activeFace) {
    'canvas' => const Color(0xFFFD971F),
    'notebook' => const Color(0xFF66D9EF),
    'notes' => const Color(0xFFA6E22E),
    _ => const Color(0xFF808080),
  };
  
  Widget _buildFacePreview() {
    switch (_activeFace) {
      case 'notes':
        return _buildNotesPreview();
      case 'canvas':
        return _buildCanvasPreview();
      case 'notebook':
        return _buildNotebookPreview();
      default:
        return _buildDefaultPreview();
    }
  }
  
  Widget _buildNotesPreview() {
    if (_notesPreview.isEmpty) {
      // Empty notes
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description, size: 28, color: const Color(0xFF75715E).withOpacity(0.4)),
            const SizedBox(height: 6),
            Text(
              'Empty Note',
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
                color: const Color(0xFF75715E).withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }
    
    // Show simple formatted markdown preview
    return Padding(
      padding: const EdgeInsets.all(10),
      child: _SimpleMarkdownPreview(content: _notesPreview),
    );
  }
  
  Widget _buildCanvasPreview() {
    if (_notebookCells.isEmpty) {
      // Empty canvas - show dot grid pattern
      return Stack(
        children: [
          // Dot grid
          CustomPaint(
            painter: _DotGridPainter(),
            size: Size.infinite,
          ),
          // Empty state
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.gesture, size: 28, color: const Color(0xFF75715E).withOpacity(0.4)),
                const SizedBox(height: 6),
                Text(
                  'Empty Canvas',
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF75715E).withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    
    // Show canvas with elements indicator
    return Stack(
      children: [
        // Grid background
        CustomPaint(painter: _GridPainter(), size: Size.infinite),
        // Sample shapes representing content
        Positioned(left: 15, top: 12, child: Container(width: 28, height: 18, decoration: BoxDecoration(color: const Color(0xFF66D9EF).withOpacity(0.3), border: Border.all(color: const Color(0xFF66D9EF), width: 1.5), borderRadius: BorderRadius.circular(2)))),
        Positioned(right: 20, top: 25, child: Container(width: 22, height: 22, decoration: BoxDecoration(color: const Color(0xFFA6E22E).withOpacity(0.3), shape: BoxShape.circle, border: Border.all(color: const Color(0xFFA6E22E), width: 1.5)))),
        Positioned(left: 30, bottom: 18, child: Container(width: 35, height: 14, decoration: BoxDecoration(color: const Color(0xFFFD971F).withOpacity(0.3), borderRadius: BorderRadius.circular(3), border: Border.all(color: const Color(0xFFFD971F), width: 1.5)))),
        // Connection lines
        CustomPaint(painter: _ConnectionPainter(), size: Size.infinite),
        // Element count badge
        if (_notebookCells.isNotEmpty)
          Positioned(
            bottom: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E).withOpacity(0.8),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.category, size: 9, color: Color(0xFF75715E)),
                  const SizedBox(width: 3),
                  Text(
                    '${_notebookCells.length} elements',
                    style: const TextStyle(fontSize: 8, fontFamily: 'monospace', fontWeight: FontWeight.w500, color: Color(0xFF75715E)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
  
  Widget _buildNotebookPreview() {
    if (_notebookCells.isEmpty) {
      // Empty notebook
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article, size: 28, color: const Color(0xFF75715E).withOpacity(0.4)),
            const SizedBox(height: 6),
            Text(
              'Empty Notebook',
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
                color: const Color(0xFF75715E).withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }
    
    // Show notebook cells preview - clip to prevent overflow
    return ClipRect(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Show first 2 cells only to prevent overflow
            ..._notebookCells.take(2).map((cell) => _buildMiniCellPreview(cell)),
            
            const Spacer(),
            
            // Cell count footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E).withOpacity(0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.view_agenda, size: 9, color: Color(0xFF75715E)),
                  const SizedBox(width: 3),
                  Text(
                    '${_notebookCells.length} cell${_notebookCells.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 8, fontFamily: 'monospace', fontWeight: FontWeight.w500, color: Color(0xFF75715E)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMiniCellPreview(_CellPreview cell) {
    final color = _getCellColor(cell.type);
    final icon = _getCellIcon(cell.type);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E).withOpacity(0.4),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          // Cell type icon
          Container(
            width: 14, height: 14,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Icon(icon, size: 8, color: color),
          ),
          const SizedBox(width: 5),
          // Content preview
          Expanded(
            child: Text(
              cell.preview.isNotEmpty ? cell.preview : cell.type,
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'monospace',
                color: cell.preview.isNotEmpty ? const Color(0xFFA6A6A6) : const Color(0xFF75715E),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
  
  Color _getCellColor(String type) {
    switch (type) {
      case 'markdown': return const Color(0xFF66D9EF);
      case 'code': return const Color(0xFFAE81FF);
      case 'mermaid': return const Color(0xFFA6E22E);
      case 'canvas': return const Color(0xFFFD971F);
      case 'image': return const Color(0xFFF92672);
      default: return const Color(0xFF75715E);
    }
  }
  
  IconData _getCellIcon(String type) {
    switch (type) {
      case 'markdown': return Icons.text_fields;
      case 'code': return Icons.code;
      case 'mermaid': return Icons.account_tree;
      case 'canvas': return Icons.gesture;
      case 'image': return Icons.image;
      default: return Icons.square;
    }
  }
  
  Widget _buildDefaultPreview() {
    return Center(
      child: Icon(_icon, size: 36, color: _color.withOpacity(0.5)),
    );
  }
  
  // Notebook cells loaded from FFI
  List<_CellPreview> _notebookCells = [];

  void _togglePin() {
    final boardId = widget.board.board.id;
    final newPinned = !_isPinned;
    
    // Optimistic update
    setState(() => _isPinned = newPinned);
    
    // Call FFI
    final success = newPinned 
        ? CyanFFI.pinBoard(boardId)
        : CyanFFI.unpinBoard(boardId);
    
    if (!success) {
      // Revert on failure
      setState(() => _isPinned = !newPinned);
    }
  }
  
  void _addLabel(String label) {
    if (label.isEmpty || _labels.contains(label)) return;
    
    final newLabels = [..._labels, label];
    final success = CyanFFI.setBoardLabels(widget.board.board.id, newLabels);
    
    if (success) {
      setState(() => _labels = newLabels);
    }
  }
  
  void _removeLabel(String label) {
    final newLabels = _labels.where((l) => l != label).toList();
    final success = CyanFFI.setBoardLabels(widget.board.board.id, newLabels);
    
    if (success) {
      setState(() => _labels = newLabels);
    }
  }
  
  void _showLabelEditor(BuildContext context) {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252525),
        title: const Text('Edit Labels', style: TextStyle(color: Color(0xFFF8F8F2))),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current labels
              if (_labels.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _labels.map((label) => Chip(
                    label: Text(label, style: TextStyle(fontSize: 12, color: _getLabelColor(label))),
                    backgroundColor: _getLabelColor(label).withOpacity(0.2),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    deleteIconColor: _getLabelColor(label),
                    onDeleted: () {
                      _removeLabel(label);
                      Navigator.pop(ctx);
                      _showLabelEditor(context);
                    },
                  )).toList(),
                ),
                const SizedBox(height: 16),
              ],
              
              // Add new label
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      style: const TextStyle(color: Color(0xFFF8F8F2)),
                      decoration: const InputDecoration(
                        hintText: 'Add label...',
                        hintStyle: TextStyle(color: Color(0xFF808080)),
                        filled: true,
                        fillColor: Color(0xFF1E1E1E),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                      ),
                      onSubmitted: (value) {
                        if (value.trim().isNotEmpty) {
                          _addLabel(value.trim());
                          Navigator.pop(ctx);
                          _showLabelEditor(context);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add, color: Color(0xFF66D9EF)),
                    onPressed: () {
                      if (controller.text.trim().isNotEmpty) {
                        _addLabel(controller.text.trim());
                        Navigator.pop(ctx);
                        _showLabelEditor(context);
                      }
                    },
                  ),
                ],
              ),
              
              // Suggested labels
              const SizedBox(height: 12),
              const Text('Suggestions:', style: TextStyle(fontSize: 11, color: Color(0xFF808080))),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ['important', 'work', 'personal', 'ideas', 'todo', 'archive']
                    .where((l) => !_labels.contains(l))
                    .map((label) => ActionChip(
                      label: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFFF8F8F2))),
                      backgroundColor: const Color(0xFF3E3D32),
                      onPressed: () {
                        _addLabel(label);
                        Navigator.pop(ctx);
                        _showLabelEditor(context);
                      },
                    )).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done', style: TextStyle(color: Color(0xFF66D9EF))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Variable preview height based on board ID (masonry effect)
    final previewHeight = _FlatGrid._getPreviewHeight(widget.board.board.id);
    
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: _hovered ? (Matrix4.identity()..scale(1.02)) : Matrix4.identity(),
          decoration: BoxDecoration(
            color: const Color(0xFF252525),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered ? const Color(0xFF66D9EF).withOpacity(0.6) : const Color(0xFF3E3D32).withOpacity(0.3),
              width: _hovered ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_hovered ? 0.35 : 0.2),
                blurRadius: _hovered ? 16 : 8,
                offset: Offset(0, _hovered ? 8 : 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Preview area - FIXED HEIGHT based on hash
              SizedBox(
                height: previewHeight,
                child: Stack(
                  children: [
                    // Face-specific preview
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                          child: _buildFacePreview(),
                        ),
                      ),
                    ),
                    
                    // Pin button (top right)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: _hovered || _isPinned ? 1.0 : 0.0,
                        child: GestureDetector(
                          onTap: _togglePin,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _isPinned 
                                  ? const Color(0xFFFD971F)
                                  : Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    // Rating stars (top left)
                    if (_rating > 0)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              _rating.clamp(0, 5),
                              (_) => const Icon(Icons.star, size: 9, color: Color(0xFFE6DB74)),
                            ),
                          ),
                        ),
                      ),
                    
                    // Face badge (bottom left)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: _color.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_icon, size: 10, color: Colors.white),
                            const SizedBox(width: 3),
                            Text(
                              _faceLabel,
                              style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Hover overlay
                    if (_hovered)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.2),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                          ),
                          child: const Center(
                            child: Icon(Icons.open_in_new, size: 28, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Info footer (matches Swift infoFooter)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF252525).withOpacity(0.6),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row with rating
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.board.board.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'monospace',
                              color: Color(0xFFF8F8F2),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_rating > 0) ...[
                          const SizedBox(width: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              _rating.clamp(0, 5),
                              (_) => const Icon(Icons.star, size: 8, color: Color(0xFFE6DB74)),
                            ),
                          ),
                        ],
                      ],
                    ),
                    
                    // Labels row (horizontal scroll)
                    if (_labels.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 18,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: _labels.map((label) => Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getLabelColor(label).withOpacity(0.85),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              label,
                              style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w500),
                            ),
                          )).toList(),
                        ),
                      ),
                    ],
                    
                    // Bottom info row
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Element count
                        Icon(Icons.grid_view, size: 10, color: const Color(0xFF75715E)),
                        const SizedBox(width: 3),
                        Text(
                          '${_notebookCells.length}',
                          style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFF75715E)),
                        ),
                        
                        const Spacer(),
                        
                        // Date
                        Text(
                          _formatDate(widget.board.board.lastModified ?? widget.board.board.createdAt),
                          style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: const Color(0xFF75715E).withOpacity(0.6)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _showContextMenu(BuildContext ctx, Offset position) {
    final RenderBox overlay = Overlay.of(ctx).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: ctx,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      color: const Color(0xFF252525),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'open',
          child: Row(
            children: const [
              Icon(Icons.open_in_new, size: 16, color: Color(0xFF66D9EF)),
              SizedBox(width: 8),
              Text('Open', style: TextStyle(color: Color(0xFFF8F8F2))),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'pin',
          child: Row(
            children: [
              Icon(_isPinned ? Icons.push_pin_outlined : Icons.push_pin, size: 16, color: const Color(0xFFFD971F)),
              const SizedBox(width: 8),
              Text(_isPinned ? 'Unpin' : 'Pin', style: const TextStyle(color: Color(0xFFF8F8F2))),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'labels',
          child: Row(
            children: const [
              Icon(Icons.label_outline, size: 16, color: Color(0xFFAE81FF)),
              SizedBox(width: 8),
              Text('Edit Labels', style: TextStyle(color: Color(0xFFF8F8F2))),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'chat',
          child: Row(
            children: const [
              Icon(Icons.chat_bubble_outline, size: 16, color: Color(0xFFA6E22E)),
              SizedBox(width: 8),
              Text('Open Chat', style: TextStyle(color: Color(0xFFF8F8F2))),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: const [
              Icon(Icons.edit, size: 16, color: Color(0xFF808080)),
              SizedBox(width: 8),
              Text('Rename', style: TextStyle(color: Color(0xFFF8F8F2))),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: const [
              Icon(Icons.delete_outline, size: 16, color: Color(0xFFF92672)),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Color(0xFFF92672))),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'open') widget.onTap();
      if (value == 'pin') _togglePin();
      if (value == 'labels') _showLabelEditor(ctx);
      if (value == 'chat') {
        // TODO: Open chat for this board
      }
      if (value == 'rename') {
        // TODO: Rename board
      }
      if (value == 'delete') {
        // TODO: Delete board
      }
    });
  }

  Color _getLabelColor(String label) {
    final hash = label.hashCode;
    final colors = [
      const Color(0xFF66D9EF),
      const Color(0xFFA6E22E),
      const Color(0xFFFD971F),
      const Color(0xFFF92672),
      const Color(0xFFAE81FF),
      const Color(0xFFE6DB74),
    ];
    return colors[hash.abs() % colors.length];
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

// Cell preview data
class _CellPreview {
  final String type;
  final String preview;
  final String fullContent;
  
  _CellPreview({required this.type, required this.preview, required this.fullContent});
}

// Canvas grid painter
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF3E3D32).withOpacity(0.3)
      ..strokeWidth = 0.5;
    
    const spacing = 10.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Dot grid painter (for empty canvas)
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF3E3D32).withOpacity(0.4);
    
    const spacing = 20.0;
    const dotSize = 2.0;
    
    for (double x = spacing; x < size.width; x += spacing) {
      for (double y = spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), dotSize / 2, paint);
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Canvas connection lines painter
class _ConnectionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF66D9EF).withOpacity(0.4)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    
    final path = Path()
      ..moveTo(43, 21)
      ..quadraticBezierTo(55, 35, size.width - 30, 36);
    
    canvas.drawPath(path, paint);
    
    final paint2 = Paint()
      ..color = const Color(0xFFA6E22E).withOpacity(0.4)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    
    final path2 = Path()
      ..moveTo(size.width - 30, 47)
      ..quadraticBezierTo(45, 55, 48, size.height - 22);
    
    canvas.drawPath(path2, paint2);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Simple markdown preview renderer for board cards
class _SimpleMarkdownPreview extends StatelessWidget {
  final String content;
  
  const _SimpleMarkdownPreview({required this.content});
  
  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    final widgets = <Widget>[];
    
    for (int i = 0; i < lines.length && widgets.length < 10; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 4));
        continue;
      }
      
      // Parse line
      Widget lineWidget;
      
      if (line.startsWith('# ')) {
        // H1
        lineWidget = Text(
          line.substring(2),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFFF8F8F2),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      } else if (line.startsWith('## ')) {
        // H2
        lineWidget = Text(
          line.substring(3),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF66D9EF),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      } else if (line.startsWith('### ')) {
        // H3
        lineWidget = Text(
          line.substring(4),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Color(0xFFA6E22E),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        // List item
        lineWidget = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• ', style: TextStyle(fontSize: 9, color: Color(0xFF75715E))),
            Expanded(
              child: Text(
                line.substring(2),
                style: TextStyle(fontSize: 9, color: const Color(0xFFF8F8F2).withOpacity(0.8)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      } else if (line.startsWith('```')) {
        // Code block start/end - show indicator
        lineWidget = Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            line.length > 3 ? line.substring(3) : 'code',
            style: const TextStyle(fontSize: 8, color: Color(0xFFAE81FF), fontFamily: 'monospace'),
          ),
        );
      } else if (line.startsWith('>')) {
        // Blockquote
        lineWidget = Container(
          padding: const EdgeInsets.only(left: 6),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Color(0xFF75715E), width: 2)),
          ),
          child: Text(
            line.substring(1).trim(),
            style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: const Color(0xFFF8F8F2).withOpacity(0.6)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      } else {
        // Regular text
        lineWidget = Text(
          _parseInlineFormatting(line),
          style: TextStyle(fontSize: 9, color: const Color(0xFFF8F8F2).withOpacity(0.8)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      }
      
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: lineWidget,
      ));
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }
  
  String _parseInlineFormatting(String text) {
    // Simple cleanup - remove markdown syntax for preview
    return text
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'\1')  // Bold
        .replaceAll(RegExp(r'\*(.+?)\*'), r'\1')      // Italic
        .replaceAll(RegExp(r'`(.+?)`'), r'\1')        // Inline code
        .replaceAll(RegExp(r'\[(.+?)\]\(.+?\)'), r'\1'); // Links
  }
}
