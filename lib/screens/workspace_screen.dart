// screens/workspace_screen.dart
// Main workspace view with FileTree, BoardGrid, and Chat panel

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/selection_provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/file_tree_widget.dart';
import '../widgets/board_grid_widget.dart';
import '../widgets/chat_panel_widget.dart';

class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  bool _showChat = false;
  
  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(selectionProvider);
    final hasBoard = selection.selectedBoardId != null;
    
    return Row(
      children: [
        // FileTree panel (left)
        SizedBox(
          width: 260,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.folder, color: Color(0xFF66D9EF), size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Workspaces',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF8F8F2),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add, size: 20),
                      color: const Color(0xFF75715E),
                      onPressed: _showCreateGroupDialog,
                      tooltip: 'Create group',
                    ),
                  ],
                ),
              ),
              
              // FileTree
              const Expanded(
                child: FileTreeWidget(),
              ),
            ],
          ),
        ),
        
        // Vertical divider
        Container(width: 1, color: const Color(0xFF3E3D32)),
        
        // Content area (BoardGrid or Board detail)
        Expanded(
          child: Column(
            children: [
              // Toolbar
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF3E3D32)),
                  ),
                ),
                child: Row(
                  children: [
                    // Breadcrumb
                    Expanded(
                      child: _buildBreadcrumb(selection),
                    ),
                    
                    // Actions
                    if (hasBoard) ...[
                      IconButton(
                        icon: Icon(
                          _showChat ? Icons.chat_bubble : Icons.chat_bubble_outline,
                          size: 20,
                        ),
                        color: _showChat ? const Color(0xFF66D9EF) : const Color(0xFF75715E),
                        onPressed: () => setState(() => _showChat = !_showChat),
                        tooltip: 'Toggle chat',
                      ),
                    ],
                    IconButton(
                      icon: const Icon(Icons.add, size: 20),
                      color: const Color(0xFF75715E),
                      onPressed: _showCreateBoardDialog,
                      tooltip: 'Create board',
                    ),
                  ],
                ),
              ),
              
              // Main content
              Expanded(
                child: Row(
                  children: [
                    // BoardGrid or detail
                    Expanded(
                      child: hasBoard
                          ? _BoardDetailView(boardId: selection.selectedBoardId!)
                          : const BoardGridWidget(),
                    ),
                    
                    // Chat panel (conditionally shown)
                    if (_showChat && hasBoard) ...[
                      Container(width: 1, color: const Color(0xFF3E3D32)),
                      SizedBox(
                        width: 320,
                        child: ChatPanelWidget(boardId: selection.selectedBoardId!),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildBreadcrumb(SelectionState selection) {
    final parts = <String>[];
    if (selection.selectedGroupName != null) {
      parts.add(selection.selectedGroupName!);
    }
    if (selection.selectedWorkspaceName != null) {
      parts.add(selection.selectedWorkspaceName!);
    }
    if (selection.selectedBoardName != null) {
      parts.add(selection.selectedBoardName!);
    }
    
    if (parts.isEmpty) {
      return const Text(
        'Select a workspace',
        style: TextStyle(color: Color(0xFF75715E)),
      );
    }
    
    return Row(
      children: [
        for (int i = 0; i < parts.length; i++) ...[
          if (i > 0) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.chevron_right, size: 16, color: Color(0xFF75715E)),
            ),
          ],
          Text(
            parts[i],
            style: TextStyle(
              color: i == parts.length - 1
                  ? const Color(0xFFF8F8F2)
                  : const Color(0xFF75715E),
              fontWeight: i == parts.length - 1 ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ],
      ],
    );
  }
  
  void _showCreateGroupDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF3E3D32),
        title: const Text('Create Group', style: TextStyle(color: Color(0xFFF8F8F2))),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFF8F8F2)),
          decoration: const InputDecoration(
            hintText: 'Group name',
            hintStyle: TextStyle(color: Color(0xFF75715E)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref.read(selectionProvider.notifier).createGroup(controller.text.trim());
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFA6E22E),
              foregroundColor: const Color(0xFF272822),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
  
  void _showCreateBoardDialog() {
    final selection = ref.read(selectionProvider);
    if (selection.selectedWorkspaceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a workspace first')),
      );
      return;
    }
    
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF3E3D32),
        title: const Text('Create Board', style: TextStyle(color: Color(0xFFF8F8F2))),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFF8F8F2)),
          decoration: const InputDecoration(
            hintText: 'Board name',
            hintStyle: TextStyle(color: Color(0xFF75715E)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
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
              foregroundColor: const Color(0xFF272822),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

/// Board detail view with face tabs (Notes, Canvas, Chat, Files)
class _BoardDetailView extends ConsumerStatefulWidget {
  final String boardId;
  
  const _BoardDetailView({required this.boardId});

  @override
  ConsumerState<_BoardDetailView> createState() => _BoardDetailViewState();
}

class _BoardDetailViewState extends ConsumerState<_BoardDetailView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Face tabs
        Container(
          color: const Color(0xFF3E3D32),
          child: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF66D9EF),
            labelColor: const Color(0xFF66D9EF),
            unselectedLabelColor: const Color(0xFF75715E),
            tabs: const [
              Tab(icon: Icon(Icons.notes, size: 18), text: 'Notes'),
              Tab(icon: Icon(Icons.brush, size: 18), text: 'Canvas'),
              Tab(icon: Icon(Icons.chat, size: 18), text: 'Chat'),
              Tab(icon: Icon(Icons.folder, size: 18), text: 'Files'),
            ],
          ),
        ),
        
        // Face content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _NotesPlaceholder(boardId: widget.boardId),
              _CanvasPlaceholder(boardId: widget.boardId),
              ChatPanelWidget(boardId: widget.boardId),
              _FilesPlaceholder(boardId: widget.boardId),
            ],
          ),
        ),
      ],
    );
  }
}

class _NotesPlaceholder extends StatelessWidget {
  final String boardId;
  const _NotesPlaceholder({required this.boardId});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notes, size: 48, color: Color(0xFF75715E)),
          SizedBox(height: 16),
          Text('Notes', style: TextStyle(color: Color(0xFF75715E))),
          Text('Batch 6: Notebook', style: TextStyle(color: Color(0xFF75715E), fontSize: 12)),
        ],
      ),
    );
  }
}

class _CanvasPlaceholder extends StatelessWidget {
  final String boardId;
  const _CanvasPlaceholder({required this.boardId});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.brush, size: 48, color: Color(0xFF75715E)),
          SizedBox(height: 16),
          Text('Canvas', style: TextStyle(color: Color(0xFF75715E))),
          Text('Batch 5: Whiteboard', style: TextStyle(color: Color(0xFF75715E), fontSize: 12)),
        ],
      ),
    );
  }
}

class _FilesPlaceholder extends StatelessWidget {
  final String boardId;
  const _FilesPlaceholder({required this.boardId});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder, size: 48, color: Color(0xFF75715E)),
          SizedBox(height: 16),
          Text('Files', style: TextStyle(color: Color(0xFF75715E))),
          Text('Coming later', style: TextStyle(color: Color(0xFF75715E), fontSize: 12)),
        ],
      ),
    );
  }
}
