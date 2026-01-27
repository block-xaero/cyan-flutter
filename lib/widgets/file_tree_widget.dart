// widgets/file_tree_widget.dart
// VS Code style file explorer with inline editing, context menus, and chat

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/file_tree_provider.dart';
import '../providers/selection_provider.dart';
import '../providers/navigation_provider.dart';
import '../models/tree_item.dart';

// Chat context types
enum ChatContextType { global, group, workspace, board }

class ChatContextInfo {
  final ChatContextType type;
  final String? id;
  final String? groupId;
  final String? workspaceId;
  final String title;

  const ChatContextInfo({required this.type, this.id, this.groupId, this.workspaceId, required this.title});

  factory ChatContextInfo.group({required String id, required String name}) =>
      ChatContextInfo(type: ChatContextType.group, id: id, groupId: id, title: name);

  factory ChatContextInfo.workspace({required String id, required String groupId, required String name}) =>
      ChatContextInfo(type: ChatContextType.workspace, id: id, groupId: groupId, workspaceId: id, title: name);

  factory ChatContextInfo.board({required String id, required String workspaceId, required String groupId, required String name}) =>
      ChatContextInfo(type: ChatContextType.board, id: id, groupId: groupId, workspaceId: workspaceId, title: name);
}

final chatContextProvider = StateProvider<ChatContextInfo?>((ref) => null);
final showChatPanelProvider = StateProvider<bool>((ref) => false);

class FileTreeWidget extends ConsumerStatefulWidget {
  const FileTreeWidget({super.key});
  @override
  ConsumerState<FileTreeWidget> createState() => _FileTreeWidgetState();
}

class _FileTreeWidgetState extends ConsumerState<FileTreeWidget> {
  final _searchController = TextEditingController();

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
          _buildHeader(),
          _buildSearch(),
          Expanded(
            child: GestureDetector(
              onTap: () => ref.read(fileTreeProvider.notifier).cancelEditing(),
              child: treeState.isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF66D9EF)))
                  : treeState.groups.isEmpty
                      ? _buildEmptyView()
                      : _buildTreeList(treeState),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(bottom: BorderSide(color: Color(0xFF1E1E1E))),
      ),
      child: Row(
        children: [
          const Text('EXPLORER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: Color(0xFF808080))),
          const Spacer(),
          _HeaderBtn(icon: Icons.add, tooltip: 'New Group', onTap: () => _showCreateDialog('Group', (n) => ref.read(fileTreeProvider.notifier).createGroup(n))),
          _HeaderBtn(icon: Icons.refresh, tooltip: 'Refresh', onTap: () => ref.read(fileTreeProvider.notifier).refresh()),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 12, color: Color(0xFFF8F8F2)),
        decoration: InputDecoration(
          hintText: 'Search', hintStyle: const TextStyle(color: Color(0xFF808080)),
          prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFF808080)),
          filled: true, fillColor: const Color(0xFF272822),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.folder_open, size: 48, color: Color(0xFF808080)),
          const SizedBox(height: 16),
          const Text('No groups yet', style: TextStyle(color: Color(0xFF808080))),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _showCreateDialog('Group', (n) => ref.read(fileTreeProvider.notifier).createGroup(n)),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Create Group'),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF66D9EF)),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeList(FileTreeState state) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: state.groups.length,
      itemBuilder: (ctx, i) => _GroupItem(
        group: state.groups[i],
        isExpanded: state.expandedGroups.contains(state.groups[i].id),
        expandedWorkspaces: state.expandedWorkspaces,
        editingItemId: state.editingItemId,
      ),
    );
  }

  void _showCreateDialog(String type, void Function(String) onCreate) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252525),
        title: Text('New $type', style: const TextStyle(color: Color(0xFFF8F8F2))),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(color: Color(0xFFF8F8F2)),
          decoration: InputDecoration(hintText: '$type name', hintStyle: const TextStyle(color: Color(0xFF808080)), filled: true, fillColor: const Color(0xFF1E1E1E)),
          onSubmitted: (v) { if (v.trim().isNotEmpty) { onCreate(v.trim()); Navigator.pop(ctx); } },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF808080)))),
          ElevatedButton(
            onPressed: () { if (ctrl.text.trim().isNotEmpty) { onCreate(ctrl.text.trim()); Navigator.pop(ctx); } },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF66D9EF)),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _HeaderBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _HeaderBtn({required this.icon, required this.tooltip, required this.onTap});
  @override
  State<_HeaderBtn> createState() => _HeaderBtnState();
}

class _HeaderBtnState extends State<_HeaderBtn> {
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
            width: 22, height: 22, margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(color: _hovered ? const Color(0xFF3E3D32) : Colors.transparent, borderRadius: BorderRadius.circular(4)),
            child: Icon(widget.icon, size: 14, color: _hovered ? const Color(0xFFF8F8F2) : const Color(0xFF808080)),
          ),
        ),
      ),
    );
  }
}

class _GroupItem extends ConsumerStatefulWidget {
  final TreeGroup group;
  final bool isExpanded;
  final Set<String> expandedWorkspaces;
  final String? editingItemId;
  const _GroupItem({required this.group, required this.isExpanded, required this.expandedWorkspaces, this.editingItemId});
  @override
  ConsumerState<_GroupItem> createState() => _GroupItemState();
}

class _GroupItemState extends ConsumerState<_GroupItem> {
  bool _hovered = false;
  final _editCtrl = TextEditingController();
  final _focusNode = FocusNode();

  bool get _isEditing => widget.editingItemId == widget.group.id;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        final t = _editCtrl.text.trim();
        if (t.isNotEmpty && t != widget.group.name) {
          ref.read(fileTreeProvider.notifier).renameGroup(widget.group.id, t);
        } else {
          ref.read(fileTreeProvider.notifier).cancelEditing();
        }
      }
    });
  }

  @override
  void didUpdateWidget(_GroupItem old) {
    super.didUpdateWidget(old);
    if (_isEditing && old.editingItemId != widget.group.id) {
      _editCtrl.text = widget.group.name;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
        _editCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _editCtrl.text.length);
      });
    }
  }

  @override
  void dispose() { _editCtrl.dispose(); _focusNode.dispose(); super.dispose(); }

  Color get _groupColor {
    final hex = widget.group.color.replaceAll('#', '');
    try { return Color(int.parse('FF$hex', radix: 16)); } catch (_) { return const Color(0xFF66D9EF); }
  }

  @override
  Widget build(BuildContext context) {
    final sel = ref.watch(selectionProvider);
    final isSelected = sel.selectedGroupId == widget.group.id && sel.selectedWorkspaceId == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: _isEditing ? null : _onTap,
            onDoubleTap: _startEdit,
            onSecondaryTapUp: (d) => _showMenu(context, d.globalPosition),
            child: Container(
              height: 28, padding: const EdgeInsets.symmetric(horizontal: 8),
              color: isSelected ? _groupColor.withOpacity(0.15) : (_hovered ? const Color(0xFF2A2A2A) : Colors.transparent),
              child: Row(
                children: [
                  Icon(widget.isExpanded ? Icons.expand_more : Icons.chevron_right, size: 16, color: const Color(0xFF808080)),
                  const SizedBox(width: 4),
                  Icon(Icons.folder, size: 16, color: _groupColor),
                  const SizedBox(width: 6),
                  Expanded(child: _isEditing ? _buildEdit() : Text(widget.group.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isSelected ? _groupColor : const Color(0xFFF8F8F2)), overflow: TextOverflow.ellipsis)),
                  if (widget.group.peerCount > 0 && !_isEditing)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFA6E22E).withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                      child: Text('${widget.group.peerCount}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFFA6E22E))),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (widget.isExpanded) ...widget.group.workspaces.map((ws) => _WorkspaceItem(workspace: ws, groupId: widget.group.id, isExpanded: widget.expandedWorkspaces.contains(ws.id), editingItemId: widget.editingItemId)),
      ],
    );
  }

  Widget _buildEdit() => TextField(
    controller: _editCtrl, focusNode: _focusNode,
    style: const TextStyle(fontSize: 13, color: Color(0xFFF8F8F2)),
    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4), border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF66D9EF))), filled: true, fillColor: Color(0xFF1E1E1E)),
    onSubmitted: (v) { if (v.trim().isNotEmpty) ref.read(fileTreeProvider.notifier).renameGroup(widget.group.id, v.trim()); else ref.read(fileTreeProvider.notifier).cancelEditing(); },
  );

  void _startEdit() { _editCtrl.text = widget.group.name; ref.read(fileTreeProvider.notifier).startEditing(widget.group.id, widget.group.name); }
  void _onTap() { ref.read(fileTreeProvider.notifier).toggleGroupExpanded(widget.group.id); ref.read(selectionProvider.notifier).selectGroup(widget.group.id, widget.group.name); }

  void _showMenu(BuildContext ctx, Offset pos) {
    final overlay = Overlay.of(ctx).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: ctx, position: RelativeRect.fromRect(Rect.fromLTWH(pos.dx, pos.dy, 0, 0), Offset.zero & overlay.size),
      color: const Color(0xFF252525), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        _mi('rename', Icons.edit, 'Rename'),
        _mi('new_ws', Icons.create_new_folder, 'New Workspace'),
        const PopupMenuDivider(),
        _mi('chat', Icons.chat_bubble_outline, 'Open Group Chat'),
        const PopupMenuDivider(),
        _mi('leave', Icons.logout, 'Leave'),
        _mi('delete', Icons.delete_outline, 'Delete', destructive: true),
      ],
    ).then((v) {
      if (v == 'rename') _startEdit();
      else if (v == 'new_ws') _showCreate('Workspace', (n) => ref.read(fileTreeProvider.notifier).createWorkspace(widget.group.id, n));
      else if (v == 'chat') { ref.read(chatContextProvider.notifier).state = ChatContextInfo.group(id: widget.group.id, name: widget.group.name); ref.read(viewModeProvider.notifier).showChat(); }
      else if (v == 'leave') ref.read(fileTreeProvider.notifier).leaveGroup(widget.group.id);
      else if (v == 'delete') ref.read(fileTreeProvider.notifier).deleteGroup(widget.group.id);
    });
  }

  void _showCreate(String type, void Function(String) fn) {
    final c = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF252525), title: Text('New $type', style: const TextStyle(color: Color(0xFFF8F8F2))),
      content: TextField(controller: c, autofocus: true, style: const TextStyle(color: Color(0xFFF8F8F2)), decoration: InputDecoration(hintText: '$type name', hintStyle: const TextStyle(color: Color(0xFF808080)), filled: true, fillColor: const Color(0xFF1E1E1E)), onSubmitted: (v) { if (v.trim().isNotEmpty) { fn(v.trim()); Navigator.pop(ctx); } }),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF808080)))), ElevatedButton(onPressed: () { if (c.text.trim().isNotEmpty) { fn(c.text.trim()); Navigator.pop(ctx); } }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF66D9EF)), child: const Text('Create'))],
    ));
  }
}

class _WorkspaceItem extends ConsumerStatefulWidget {
  final TreeWorkspace workspace;
  final String groupId;
  final bool isExpanded;
  final String? editingItemId;
  const _WorkspaceItem({required this.workspace, required this.groupId, required this.isExpanded, this.editingItemId});
  @override
  ConsumerState<_WorkspaceItem> createState() => _WorkspaceItemState();
}

class _WorkspaceItemState extends ConsumerState<_WorkspaceItem> {
  bool _hovered = false;
  final _editCtrl = TextEditingController();
  final _focusNode = FocusNode();
  bool get _isEditing => widget.editingItemId == widget.workspace.id;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        final t = _editCtrl.text.trim();
        if (t.isNotEmpty && t != widget.workspace.name) ref.read(fileTreeProvider.notifier).renameWorkspaceById(widget.workspace.id, t);
        else ref.read(fileTreeProvider.notifier).cancelEditing();
      }
    });
  }

  @override
  void didUpdateWidget(_WorkspaceItem old) {
    super.didUpdateWidget(old);
    if (_isEditing && old.editingItemId != widget.workspace.id) {
      _editCtrl.text = widget.workspace.name;
      WidgetsBinding.instance.addPostFrameCallback((_) { _focusNode.requestFocus(); _editCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _editCtrl.text.length); });
    }
  }

  @override
  void dispose() { _editCtrl.dispose(); _focusNode.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final sel = ref.watch(selectionProvider);
    final isSelected = sel.selectedWorkspaceId == widget.workspace.id && sel.selectedBoardId == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: _isEditing ? null : _onTap,
            onDoubleTap: _startEdit,
            onSecondaryTapUp: (d) => _showMenu(context, d.globalPosition),
            child: Container(
              height: 26, padding: const EdgeInsets.only(left: 24, right: 8),
              color: isSelected ? const Color(0xFFA6E22E).withOpacity(0.15) : (_hovered ? const Color(0xFF2A2A2A) : Colors.transparent),
              child: Row(
                children: [
                  Icon(widget.isExpanded ? Icons.expand_more : Icons.chevron_right, size: 14, color: const Color(0xFF808080)),
                  const SizedBox(width: 4),
                  const Icon(Icons.workspaces_outline, size: 14, color: Color(0xFFA6E22E)),
                  const SizedBox(width: 6),
                  Expanded(child: _isEditing ? _buildEdit() : Text(widget.workspace.name, style: TextStyle(fontSize: 12, color: isSelected ? const Color(0xFFA6E22E) : const Color(0xFFF8F8F2)), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
        ),
        if (widget.isExpanded) ...widget.workspace.boards.map((b) => _BoardItem(board: b, groupId: widget.groupId, workspaceId: widget.workspace.id, editingItemId: widget.editingItemId)),
      ],
    );
  }

  Widget _buildEdit() => TextField(controller: _editCtrl, focusNode: _focusNode, style: const TextStyle(fontSize: 12, color: Color(0xFFF8F8F2)), decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4), border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFA6E22E))), filled: true, fillColor: Color(0xFF1E1E1E)), onSubmitted: (v) { if (v.trim().isNotEmpty) ref.read(fileTreeProvider.notifier).renameWorkspaceById(widget.workspace.id, v.trim()); else ref.read(fileTreeProvider.notifier).cancelEditing(); });

  void _startEdit() { _editCtrl.text = widget.workspace.name; ref.read(fileTreeProvider.notifier).startEditing(widget.workspace.id, widget.workspace.name); }
  void _onTap() { ref.read(fileTreeProvider.notifier).toggleWorkspaceExpanded(widget.workspace.id); ref.read(selectionProvider.notifier).selectWorkspace(groupId: widget.groupId, workspaceId: widget.workspace.id, workspaceName: widget.workspace.name); }

  void _showMenu(BuildContext ctx, Offset pos) {
    final overlay = Overlay.of(ctx).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: ctx, position: RelativeRect.fromRect(Rect.fromLTWH(pos.dx, pos.dy, 0, 0), Offset.zero & overlay.size),
      color: const Color(0xFF252525), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [_mi('rename', Icons.edit, 'Rename'), _mi('new_board', Icons.add_box_outlined, 'New Board'), const PopupMenuDivider(), _mi('chat', Icons.chat_bubble_outline, 'Open Workspace Chat'), const PopupMenuDivider(), _mi('leave', Icons.logout, 'Leave'), _mi('delete', Icons.delete_outline, 'Delete', destructive: true)],
    ).then((v) {
      if (v == 'rename') _startEdit();
      else if (v == 'new_board') _showCreate('Board', (n) => ref.read(fileTreeProvider.notifier).createBoard(widget.workspace.id, n));
      else if (v == 'chat') { ref.read(chatContextProvider.notifier).state = ChatContextInfo.workspace(id: widget.workspace.id, groupId: widget.groupId, name: widget.workspace.name); ref.read(viewModeProvider.notifier).showChat(); }
      else if (v == 'leave') ref.read(fileTreeProvider.notifier).leaveWorkspace(widget.workspace.id);
      else if (v == 'delete') ref.read(fileTreeProvider.notifier).deleteWorkspace(widget.workspace.id);
    });
  }

  void _showCreate(String type, void Function(String) fn) {
    final c = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF252525), title: Text('New $type', style: const TextStyle(color: Color(0xFFF8F8F2))), content: TextField(controller: c, autofocus: true, style: const TextStyle(color: Color(0xFFF8F8F2)), decoration: InputDecoration(hintText: '$type name', hintStyle: const TextStyle(color: Color(0xFF808080)), filled: true, fillColor: const Color(0xFF1E1E1E)), onSubmitted: (v) { if (v.trim().isNotEmpty) { fn(v.trim()); Navigator.pop(ctx); } }), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF808080)))), ElevatedButton(onPressed: () { if (c.text.trim().isNotEmpty) { fn(c.text.trim()); Navigator.pop(ctx); } }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF66D9EF)), child: const Text('Create'))]));
  }
}

class _BoardItem extends ConsumerStatefulWidget {
  final TreeBoard board;
  final String groupId;
  final String workspaceId;
  final String? editingItemId;
  const _BoardItem({required this.board, required this.groupId, required this.workspaceId, this.editingItemId});
  @override
  ConsumerState<_BoardItem> createState() => _BoardItemState();
}

class _BoardItemState extends ConsumerState<_BoardItem> {
  bool _hovered = false;
  final _editCtrl = TextEditingController();
  final _focusNode = FocusNode();
  bool get _isEditing => widget.editingItemId == widget.board.id;

  IconData get _icon => switch (widget.board.boardType) { 'canvas' => Icons.brush, 'notebook' => Icons.book, 'notes' => Icons.article, _ => Icons.dashboard };

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        final t = _editCtrl.text.trim();
        if (t.isNotEmpty && t != widget.board.name) ref.read(fileTreeProvider.notifier).renameBoardById(widget.board.id, t);
        else ref.read(fileTreeProvider.notifier).cancelEditing();
      }
    });
  }

  @override
  void didUpdateWidget(_BoardItem old) {
    super.didUpdateWidget(old);
    if (_isEditing && old.editingItemId != widget.board.id) {
      _editCtrl.text = widget.board.name;
      WidgetsBinding.instance.addPostFrameCallback((_) { _focusNode.requestFocus(); _editCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _editCtrl.text.length); });
    }
  }

  @override
  void dispose() { _editCtrl.dispose(); _focusNode.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final sel = ref.watch(selectionProvider);
    final isSelected = sel.selectedBoardId == widget.board.id;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _isEditing ? null : _onTap,
        onDoubleTap: _startEdit,
        onSecondaryTapUp: (d) => _showMenu(context, d.globalPosition),
        child: Container(
          height: 24, padding: const EdgeInsets.only(left: 48, right: 8),
          color: isSelected ? const Color(0xFF66D9EF).withOpacity(0.2) : (_hovered ? const Color(0xFF2A2A2A) : Colors.transparent),
          child: Row(
            children: [
              Icon(_icon, size: 12, color: isSelected ? const Color(0xFF66D9EF) : const Color(0xFF808080)),
              const SizedBox(width: 6),
              Expanded(child: _isEditing ? _buildEdit() : Text(widget.board.name, style: TextStyle(fontSize: 11, color: isSelected ? const Color(0xFF66D9EF) : const Color(0xFFF8F8F2)), overflow: TextOverflow.ellipsis)),
              if (widget.board.hasUnread && !_isEditing) Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFA6E22E), shape: BoxShape.circle)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEdit() => TextField(controller: _editCtrl, focusNode: _focusNode, style: const TextStyle(fontSize: 11, color: Color(0xFFF8F8F2)), decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4), border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF66D9EF))), filled: true, fillColor: Color(0xFF1E1E1E)), onSubmitted: (v) { if (v.trim().isNotEmpty) ref.read(fileTreeProvider.notifier).renameBoardById(widget.board.id, v.trim()); else ref.read(fileTreeProvider.notifier).cancelEditing(); });

  void _startEdit() { _editCtrl.text = widget.board.name; ref.read(fileTreeProvider.notifier).startEditing(widget.board.id, widget.board.name); }
  void _onTap() { ref.read(selectionProvider.notifier).selectBoard(groupId: widget.groupId, workspaceId: widget.workspaceId, workspaceName: '', boardId: widget.board.id, boardName: widget.board.name); }

  void _showMenu(BuildContext ctx, Offset pos) {
    final overlay = Overlay.of(ctx).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: ctx, position: RelativeRect.fromRect(Rect.fromLTWH(pos.dx, pos.dy, 0, 0), Offset.zero & overlay.size),
      color: const Color(0xFF252525), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [_mi('open', Icons.open_in_new, 'Open'), _mi('rename', Icons.edit, 'Rename'), const PopupMenuDivider(), _mi('chat', Icons.chat_bubble_outline, 'Open Board Chat'), const PopupMenuDivider(), _mi('leave', Icons.logout, 'Leave'), _mi('delete', Icons.delete_outline, 'Delete', destructive: true)],
    ).then((v) {
      if (v == 'open') _onTap();
      else if (v == 'rename') _startEdit();
      else if (v == 'chat') { ref.read(chatContextProvider.notifier).state = ChatContextInfo.board(id: widget.board.id, workspaceId: widget.workspaceId, groupId: widget.groupId, name: widget.board.name); ref.read(viewModeProvider.notifier).showChat(); }
      else if (v == 'leave') ref.read(fileTreeProvider.notifier).leaveBoard(widget.board.id);
      else if (v == 'delete') ref.read(fileTreeProvider.notifier).deleteBoard(widget.board.id);
    });
  }
}

PopupMenuItem<String> _mi(String v, IconData i, String l, {bool destructive = false}) {
  final c = destructive ? const Color(0xFFF92672) : const Color(0xFFF8F8F2);
  return PopupMenuItem(value: v, child: Row(children: [Icon(i, size: 16, color: c), const SizedBox(width: 12), Text(l, style: TextStyle(color: c, fontSize: 13))]));
}
