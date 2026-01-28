// screens/workspace_screen.dart
// Main workspace - switches between AllBoards, Explorer, Chat based on ViewMode
// Everything is collapsible, Chat takes over full screen

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import '../providers/selection_provider.dart';
import '../providers/file_tree_provider.dart';
import '../widgets/file_tree_widget.dart';
import '../widgets/all_boards_grid.dart';
import '../widgets/full_chat_view.dart';
import '../widgets/board_detail_view.dart';
import '../widgets/board_grid_widget.dart';

class WorkspaceScreen extends ConsumerWidget {
  const WorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(viewModeProvider);

    // Chat mode takes over everything
    if (viewMode == ViewMode.chat) {
      return const FullChatView();
    }

    // Events mode
    if (viewMode == ViewMode.events) {
      return const _EventsView();
    }

    // AllBoards or Explorer mode
    return _MainLayout(viewMode: viewMode);
  }
}

class _MainLayout extends ConsumerStatefulWidget {
  final ViewMode viewMode;

  const _MainLayout({required this.viewMode});

  @override
  ConsumerState<_MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<_MainLayout> {
  double _explorerWidth = 260;
  bool _isResizing = false;

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(selectionProvider);
    final showExplorer = widget.viewMode == ViewMode.explorer;
    final hasBoard = selection.selectedBoardId != null;

    return Row(
      children: [
        // Explorer panel (only in explorer mode)
        if (showExplorer) ...[
          _ResizablePanel(
            width: _explorerWidth,
            minWidth: 200,
            maxWidth: 400,
            onResize: (w) => setState(() => _explorerWidth = w),
            child: const _ExplorerPanel(),
          ),
          const _VerticalDivider(),
        ],

        // Main content
        Expanded(
          child: Column(
            children: [
              // Toolbar
              _Toolbar(
                selection: selection,
                showExplorer: showExplorer,
                hasBoard: hasBoard,
              ),

              // Content
              Expanded(
                child: showExplorer
                    ? _ExplorerContent(selection: selection, hasBoard: hasBoard)
                    : const AllBoardsGrid(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExplorerPanel extends StatelessWidget {
  const _ExplorerPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: const Column(
        children: [
          // File tree takes full height
          Expanded(child: FileTreeWidget()),
        ],
      ),
    );
  }
}

class _ExplorerContent extends ConsumerWidget {
  final SelectionState selection;
  final bool hasBoard;

  const _ExplorerContent({required this.selection, required this.hasBoard});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (hasBoard) {
      return BoardDetailView(
        boardId: selection.selectedBoardId!,
        boardName: selection.selectedBoardName ?? 'Board',
      );
    }

    if (selection.selectedWorkspaceId != null) {
      return const BoardGridWidget();
    }

    return const _SelectWorkspacePrompt();
  }
}

class _Toolbar extends ConsumerWidget {
  final SelectionState selection;
  final bool showExplorer;
  final bool hasBoard;

  const _Toolbar({
    required this.selection,
    required this.showExplorer,
    required this.hasBoard,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(bottom: BorderSide(color: Color(0xFF3E3D32))),
      ),
      child: Row(
        children: [
          // Breadcrumb / Title
          Expanded(
            child: showExplorer
                ? _Breadcrumb(selection: selection)
                : Row(
                    children: [
                      const Icon(Icons.dashboard, size: 16, color: Color(0xFF66D9EF)),
                      const SizedBox(width: 8),
                      const Text(
                        'All Boards',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF8F8F2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Pinned badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFD971F),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.push_pin, size: 10, color: Colors.white),
                            SizedBox(width: 2),
                            Text('5', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),

          // Actions
          if (showExplorer && hasBoard) ...[
            _ToolbarButton(
              icon: Icons.chat_bubble_outline,
              tooltip: 'Open Chat',
              onTap: () {
                final sel = ref.read(selectionProvider);
                ref.read(chatContextProvider.notifier).state = ChatContextInfo.board(
                  id: sel.selectedBoardId!,
                  workspaceId: sel.selectedWorkspaceId!,
                  groupId: sel.selectedGroupId!,
                  name: sel.selectedBoardName ?? 'Board',
                );
                ref.read(viewModeProvider.notifier).showChat();
              },
            ),
          ],

          _ToolbarButton(
            icon: Icons.add,
            tooltip: 'Create',
            onTap: () => _showCreateMenu(context, ref),
          ),
        ],
      ),
    );
  }

  void _showCreateMenu(BuildContext context, WidgetRef ref) {
    final selection = ref.read(selectionProvider);
    
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(100, 48, 0, 0),
      color: const Color(0xFF252525),
      items: [
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.folder, size: 16, color: Color(0xFF66D9EF)),
              SizedBox(width: 12),
              Text('New Group', style: TextStyle(color: Color(0xFFF8F8F2))),
            ],
          ),
          onTap: () => _showCreateDialog(context, ref, 'Group', (n) => ref.read(fileTreeProvider.notifier).createGroup(n)),
        ),
        if (selection.selectedGroupId != null)
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.workspaces_outline, size: 16, color: Color(0xFFA6E22E)),
                SizedBox(width: 12),
                Text('New Workspace', style: TextStyle(color: Color(0xFFF8F8F2))),
              ],
            ),
            onTap: () => _showCreateDialog(context, ref, 'Workspace', (n) => ref.read(fileTreeProvider.notifier).createWorkspace(selection.selectedGroupId!, n)),
          ),
        if (selection.selectedWorkspaceId != null)
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.dashboard, size: 16, color: Color(0xFFF92672)),
                SizedBox(width: 12),
                Text('New Board', style: TextStyle(color: Color(0xFFF8F8F2))),
              ],
            ),
            onTap: () => _showCreateDialog(context, ref, 'Board', (n) => ref.read(fileTreeProvider.notifier).createBoard(selection.selectedWorkspaceId!, n)),
          ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref, String type, void Function(String) onCreate) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252525),
        title: Text('New $type', style: const TextStyle(color: Color(0xFFF8F8F2))),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFF8F8F2)),
          decoration: InputDecoration(
            hintText: '$type name',
            hintStyle: const TextStyle(color: Color(0xFF808080)),
            filled: true,
            fillColor: const Color(0xFF1E1E1E),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) {
              onCreate(v.trim());
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF808080)))),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                onCreate(ctrl.text.trim());
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF66D9EF)),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolbarButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: _hovered ? const Color(0xFF3E3D32) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(widget.icon, size: 18, color: _hovered ? const Color(0xFFF8F8F2) : const Color(0xFF808080)),
          ),
        ),
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  final SelectionState selection;

  const _Breadcrumb({required this.selection});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (selection.selectedGroupName != null) parts.add(selection.selectedGroupName!);
    if (selection.selectedWorkspaceName != null) parts.add(selection.selectedWorkspaceName!);
    if (selection.selectedBoardName != null) parts.add(selection.selectedBoardName!);

    if (parts.isEmpty) {
      return const Text('Select a workspace', style: TextStyle(color: Color(0xFF75715E)));
    }

    return Row(
      children: [
        for (int i = 0; i < parts.length; i++) ...[
          if (i > 0) const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.chevron_right, size: 16, color: Color(0xFF75715E)),
          ),
          Text(
            parts[i],
            style: TextStyle(
              color: i == parts.length - 1 ? const Color(0xFFF8F8F2) : const Color(0xFF75715E),
              fontWeight: i == parts.length - 1 ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ],
      ],
    );
  }
}

class _SelectWorkspacePrompt extends StatelessWidget {
  const _SelectWorkspacePrompt();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 64, color: Color(0xFF606060)),
          SizedBox(height: 16),
          Text('Select a workspace', style: TextStyle(fontSize: 18, color: Color(0xFF808080))),
          SizedBox(height: 8),
          Text('Choose from the explorer to see boards', style: TextStyle(fontSize: 13, color: Color(0xFF606060))),
        ],
      ),
    );
  }
}

class _EventsView extends StatelessWidget {
  const _EventsView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hub_outlined, size: 64, color: Color(0xFF606060)),
          SizedBox(height: 16),
          Text('Network Events', style: TextStyle(fontSize: 18, color: Color(0xFF808080))),
          SizedBox(height: 8),
          Text('Event stream coming soon', style: TextStyle(fontSize: 13, color: Color(0xFF606060))),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, color: const Color(0xFF3E3D32));
  }
}

class _ResizablePanel extends StatefulWidget {
  final double width;
  final double minWidth;
  final double maxWidth;
  final ValueChanged<double> onResize;
  final Widget child;

  const _ResizablePanel({
    required this.width,
    required this.minWidth,
    required this.maxWidth,
    required this.onResize,
    required this.child,
  });

  @override
  State<_ResizablePanel> createState() => _ResizablePanelState();
}

class _ResizablePanelState extends State<_ResizablePanel> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Stack(
        children: [
          widget.child,
          // Resize handle
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              onEnter: (_) => setState(() => _isHovered = true),
              onExit: (_) => setState(() => _isHovered = false),
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  final newWidth = widget.width + details.delta.dx;
                  if (newWidth >= widget.minWidth && newWidth <= widget.maxWidth) {
                    widget.onResize(newWidth);
                  }
                },
                child: Container(
                  width: 4,
                  color: _isHovered ? const Color(0xFF66D9EF) : Colors.transparent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
