// widgets/file_tree_widget.dart
// VS Code style file explorer with search, context menus, and drag-drop

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/file_tree_provider.dart';
import '../providers/selection_provider.dart';
import '../models/tree_item.dart';

class FileTreeWidget extends ConsumerStatefulWidget {
  const FileTreeWidget({super.key});

  @override
  ConsumerState<FileTreeWidget> createState() => _FileTreeWidgetState();
}

class _FileTreeWidgetState extends ConsumerState<FileTreeWidget> {
  final _searchController = TextEditingController();
  bool _isDropTargeted = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final treeState = ref.watch(fileTreeProvider);
    
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with title and add button
          _TreeHeader(
            onAddGroup: () => _showCreateGroupDialog(context),
          ),
          
          // Search bar
          _TreeSearch(
            controller: _searchController,
            onChanged: (value) {
              // TODO: Filter tree
            },
          ),
          
          // Tree content
          Expanded(
            child: treeState.isLoading
                ? const _LoadingView()
                : treeState.groups.isEmpty
                    ? _EmptyView(onCreateGroup: () => _showCreateGroupDialog(context))
                    : _TreeList(
                        groups: treeState.groups,
                        expandedGroups: treeState.expandedGroups,
                        expandedWorkspaces: treeState.expandedWorkspaces,
                      ),
          ),
          
          // Drop zone indicator
          if (_isDropTargeted)
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF66D9EF).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: const Color(0xFF66D9EF),
                  style: BorderStyle.solid,
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.file_download, size: 14, color: Color(0xFF66D9EF)),
                  SizedBox(width: 8),
                  Text(
                    'Drop files to upload',
                    style: TextStyle(fontSize: 12, color: Color(0xFF66D9EF)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showCreateGroupDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252525),
        title: const Text('New Group', style: TextStyle(color: Color(0xFFF8F8F2))),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFF8F8F2)),
          decoration: InputDecoration(
            hintText: 'Group name',
            hintStyle: const TextStyle(color: Color(0xFF808080)),
            filled: true,
            fillColor: const Color(0xFF1E1E1E),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF3E3D32)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF66D9EF)),
            ),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              ref.read(selectionProvider.notifier).createGroup(value.trim());
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF808080))),
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
              foregroundColor: const Color(0xFF1E1E1E),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _TreeHeader extends StatelessWidget {
  final VoidCallback onAddGroup;

  const _TreeHeader({required this.onAddGroup});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(bottom: BorderSide(color: Color(0xFF1E1E1E))),
      ),
      child: Row(
        children: [
          const Text(
            'EXPLORER',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: Color(0xFF808080),
            ),
          ),
          const Spacer(),
          _HeaderButton(
            icon: Icons.add,
            tooltip: 'New Group',
            onTap: onAddGroup,
          ),
          _HeaderButton(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onTap: () {
              // Refresh tree
            },
          ),
          _HeaderButton(
            icon: Icons.more_horiz,
            tooltip: 'More Actions',
            onTap: () {
              // Show more actions
            },
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_HeaderButton> createState() => _HeaderButtonState();
}

class _HeaderButtonState extends State<_HeaderButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: _isHovered ? const Color(0xFF3E3D32) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: _isHovered ? const Color(0xFFF8F8F2) : const Color(0xFF808080),
            ),
          ),
        ),
      ),
    );
  }
}

class _TreeSearch extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _TreeSearch({
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 12, color: Color(0xFFF8F8F2)),
        decoration: InputDecoration(
          hintText: 'Search',
          hintStyle: const TextStyle(color: Color(0xFF808080)),
          prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFF808080)),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFF252525),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFF66D9EF), width: 1),
          ),
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF66D9EF)),
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Loading tree...',
            style: TextStyle(fontSize: 12, color: Color(0xFF808080)),
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onCreateGroup;

  const _EmptyView({required this.onCreateGroup});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.folder_open, size: 48, color: Color(0xFF606060)),
          const SizedBox(height: 16),
          const Text(
            'No groups yet',
            style: TextStyle(fontSize: 14, color: Color(0xFF808080)),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onCreateGroup,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Create your first group'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF66D9EF),
            ),
          ),
        ],
      ),
    );
  }
}

class _TreeList extends ConsumerWidget {
  final List<TreeGroup> groups;
  final Set<String> expandedGroups;
  final Set<String> expandedWorkspaces;

  const _TreeList({
    required this.groups,
    required this.expandedGroups,
    required this.expandedWorkspaces,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return _GroupItem(
          group: group,
          isExpanded: expandedGroups.contains(group.id),
          expandedWorkspaces: expandedWorkspaces,
        );
      },
    );
  }
}

class _GroupItem extends ConsumerStatefulWidget {
  final TreeGroup group;
  final bool isExpanded;
  final Set<String> expandedWorkspaces;

  const _GroupItem({
    required this.group,
    required this.isExpanded,
    required this.expandedWorkspaces,
  });

  @override
  ConsumerState<_GroupItem> createState() => _GroupItemState();
}

class _GroupItemState extends ConsumerState<_GroupItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(selectionProvider);
    final isSelected = selection.selectedGroupId == widget.group.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Group row
        MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: () {
              ref.read(fileTreeProvider.notifier).toggleGroupExpanded(widget.group.id);
              ref.read(selectionProvider.notifier).selectGroup(widget.group.id, widget.group.name);
            },
            onSecondaryTap: () => _showContextMenu(context),
            child: Container(
              height: 24,
              padding: const EdgeInsets.only(left: 8, right: 8),
              color: isSelected
                  ? const Color(0xFF66D9EF).withValues(alpha: 0.15)
                  : (_isHovered ? const Color(0xFF2A2A2A) : Colors.transparent),
              child: Row(
                children: [
                  Icon(
                    widget.isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: const Color(0xFF808080),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.folder,
                    size: 16,
                    color: _parseColor(widget.group.color) ?? const Color(0xFFFD971F),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.group.name,
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected ? const Color(0xFF66D9EF) : const Color(0xFFF8F8F2),
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.group.peerCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFA6E22E).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${widget.group.peerCount}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFA6E22E),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        
        // Workspaces (when expanded)
        if (widget.isExpanded)
          ...widget.group.workspaces.map((ws) => _WorkspaceItem(
            workspace: ws,
            groupId: widget.group.id,
            isExpanded: widget.expandedWorkspaces.contains(ws.id),
          )),
      ],
    );
  }

  void _showContextMenu(BuildContext context) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(100, 100, 100, 100),
      color: const Color(0xFF252525),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'rename',
          child: const Text('Rename', style: TextStyle(color: Color(0xFFF8F8F2))),
        ),
        PopupMenuItem<String>(
          value: 'new_workspace',
          child: const Text('New Workspace', style: TextStyle(color: Color(0xFFF8F8F2))),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'open_chat',
          child: const Text('Open Group Chat', style: TextStyle(color: Color(0xFFF8F8F2))),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          child: const Text('Delete', style: TextStyle(color: Color(0xFFF92672))),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'rename':
          // Rename group
          break;
        case 'new_workspace':
          ref.read(selectionProvider.notifier).createWorkspace('New Workspace');
          break;
        case 'open_chat':
          // Open chat
          break;
        case 'delete':
          // Delete group
          break;
      }
    });
  }

  Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      final cleanHex = hex.replaceAll('#', '');
      return Color(int.parse('FF$cleanHex', radix: 16));
    } catch (_) {
      return null;
    }
  }
}

class _WorkspaceItem extends ConsumerStatefulWidget {
  final TreeWorkspace workspace;
  final String groupId;
  final bool isExpanded;

  const _WorkspaceItem({
    required this.workspace,
    required this.groupId,
    required this.isExpanded,
  });

  @override
  ConsumerState<_WorkspaceItem> createState() => _WorkspaceItemState();
}

class _WorkspaceItemState extends ConsumerState<_WorkspaceItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(selectionProvider);
    final isSelected = selection.selectedWorkspaceId == widget.workspace.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Workspace row
        MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: () {
              ref.read(fileTreeProvider.notifier).toggleWorkspaceExpanded(widget.workspace.id);
              ref.read(selectionProvider.notifier).selectWorkspace(
                groupId: widget.groupId,
                workspaceId: widget.workspace.id,
                workspaceName: widget.workspace.name,
              );
            },
            child: Container(
              height: 24,
              padding: const EdgeInsets.only(left: 24, right: 8),
              color: isSelected
                  ? const Color(0xFF66D9EF).withValues(alpha: 0.15)
                  : (_isHovered ? const Color(0xFF2A2A2A) : Colors.transparent),
              child: Row(
                children: [
                  Icon(
                    widget.isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 14,
                    color: const Color(0xFF808080),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.workspaces_outline,
                    size: 14,
                    color: Color(0xFF66D9EF),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.workspace.name,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? const Color(0xFF66D9EF) : const Color(0xFFF8F8F2),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // Boards (when expanded)
        if (widget.isExpanded)
          ...widget.workspace.boards.map((board) => _BoardItem(
            board: board,
            groupId: widget.groupId,
            workspaceId: widget.workspace.id,
            workspaceName: widget.workspace.name,
          )),
      ],
    );
  }
}

class _BoardItem extends ConsumerStatefulWidget {
  final TreeBoard board;
  final String groupId;
  final String workspaceId;
  final String workspaceName;

  const _BoardItem({
    required this.board,
    required this.groupId,
    required this.workspaceId,
    required this.workspaceName,
  });

  @override
  ConsumerState<_BoardItem> createState() => _BoardItemState();
}

class _BoardItemState extends ConsumerState<_BoardItem> {
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

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(selectionProvider);
    final isSelected = selection.selectedBoardId == widget.board.id;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          ref.read(selectionProvider.notifier).selectBoard(
            groupId: widget.groupId,
            workspaceId: widget.workspaceId,
            workspaceName: widget.workspaceName,
            boardId: widget.board.id,
            boardName: widget.board.name,
          );
        },
        child: Container(
          height: 24,
          padding: const EdgeInsets.only(left: 48, right: 8),
          color: isSelected
              ? const Color(0xFF66D9EF).withValues(alpha: 0.2)
              : (_isHovered ? const Color(0xFF2A2A2A) : Colors.transparent),
          child: Row(
            children: [
              Icon(
                _boardIcon,
                size: 12,
                color: isSelected ? const Color(0xFF66D9EF) : const Color(0xFF808080),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.board.name,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? const Color(0xFF66D9EF) : const Color(0xFFF8F8F2),
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
        ),
      ),
    );
  }
}
