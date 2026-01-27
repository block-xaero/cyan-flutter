// widgets/board_detail_view.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/selection_provider.dart';
import '../providers/navigation_provider.dart';
import 'file_tree_widget.dart';

enum BoardFace {
  canvas('canvas', Icons.brush, 'Canvas'),
  notebook('notebook', Icons.book, 'Notebook'),
  notes('notes', Icons.article, 'Notes');

  final String value;
  final IconData icon;
  final String label;
  const BoardFace(this.value, this.icon, this.label);
}

class BoardDetailView extends ConsumerStatefulWidget {
  final String boardId;
  final String boardName;

  const BoardDetailView({super.key, required this.boardId, required this.boardName});

  @override
  ConsumerState<BoardDetailView> createState() => _BoardDetailViewState();
}

class _BoardDetailViewState extends ConsumerState<BoardDetailView> {
  BoardFace _activeFace = BoardFace.canvas;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        const Divider(height: 1, color: Color(0xFF3E3D32)),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFF252525),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 18),
            color: const Color(0xFF66D9EF),
            onPressed: () => ref.read(selectionProvider.notifier).clearBoard(),
            tooltip: 'Back',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              widget.boardName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFFF8F8F2)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _buildFaceSelector(),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline, size: 16),
            color: const Color(0xFF808080),
            onPressed: _openChat,
            tooltip: 'Chat',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: Color(0xFF808080), size: 16),
            padding: EdgeInsets.zero,
            color: const Color(0xFF252525),
            itemBuilder: (ctx) => [
              _menuItem('rename', Icons.edit, 'Rename'),
              _menuItem('duplicate', Icons.copy, 'Duplicate'),
              const PopupMenuDivider(),
              _menuItem('delete', Icons.delete, 'Delete', destructive: true),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String v, IconData i, String l, {bool destructive = false}) {
    final c = destructive ? const Color(0xFFF92672) : const Color(0xFFF8F8F2);
    return PopupMenuItem(value: v, child: Row(children: [Icon(i, size: 14, color: c), const SizedBox(width: 8), Text(l, style: TextStyle(color: c, fontSize: 12))]));
  }

  Widget _buildFaceSelector() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: BoardFace.values.map((f) {
          final active = f == _activeFace;
          return Tooltip(
            message: f.label,
            child: GestureDetector(
              onTap: () => setState(() => _activeFace = f),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF3D3D3D) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(f.icon, size: 14, color: active ? Colors.white : const Color(0xFF808080)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildContent() {
    switch (_activeFace) {
      case BoardFace.canvas:
        return _CanvasView(boardId: widget.boardId);
      case BoardFace.notebook:
        return _NotebookView(boardId: widget.boardId);
      case BoardFace.notes:
        return _NotesView(boardId: widget.boardId);
    }
  }

  void _openChat() {
    final sel = ref.read(selectionProvider);
    ref.read(chatContextProvider.notifier).state = ChatContextInfo.board(
      id: widget.boardId,
      workspaceId: sel.selectedWorkspaceId ?? '',
      groupId: sel.selectedGroupId ?? '',
      name: widget.boardName,
    );
    ref.read(viewModeProvider.notifier).showChat();
  }
}

class _CanvasView extends StatelessWidget {
  final String boardId;
  const _CanvasView({required this.boardId});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.brush, size: 48, color: Color(0xFF606060)),
          SizedBox(height: 12),
          Text('Canvas', style: TextStyle(fontSize: 16, color: Color(0xFF808080))),
        ]),
      ),
    );
  }
}

class _NotebookView extends StatefulWidget {
  final String boardId;
  const _NotebookView({required this.boardId});

  @override
  State<_NotebookView> createState() => _NotebookViewState();
}

class _NotebookViewState extends State<_NotebookView> {
  final _cells = <_Cell>[_Cell(type: 'markdown', content: '# Welcome\n\nStart writing...')];
  int? _selectedIdx;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _cells.length,
            itemBuilder: (ctx, i) => _buildCell(i),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(color: Color(0xFF252525), border: Border(bottom: BorderSide(color: Color(0xFF3E3D32)))),
      child: Row(
        children: [
          const Text('Add:', style: TextStyle(fontSize: 11, color: Color(0xFF808080))),
          const SizedBox(width: 8),
          _addBtn('Markdown', Icons.text_fields, const Color(0xFF66D9EF), () => _addCell('markdown')),
          _addBtn('Code', Icons.code, const Color(0xFFAE81FF), () => _addCell('code')),
        ],
      ),
    );
  }

  Widget _addBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(4)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ]),
        ),
      ),
    );
  }

  void _addCell(String type) {
    setState(() {
      _cells.add(_Cell(type: type, content: type == 'code' ? '# code' : ''));
      _selectedIdx = _cells.length - 1;
    });
  }

  Widget _buildCell(int i) {
    final cell = _cells[i];
    final selected = _selectedIdx == i;
    return GestureDetector(
      onTap: () => setState(() => _selectedIdx = i),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? const Color(0xFF66D9EF) : const Color(0xFF3E3D32), width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(7))),
              child: Row(children: [
                Icon(cell.type == 'code' ? Icons.code : Icons.text_fields, size: 12, color: cell.type == 'code' ? const Color(0xFFAE81FF) : const Color(0xFF66D9EF)),
                const SizedBox(width: 6),
                Text(cell.type == 'code' ? 'Code' : 'Markdown', style: TextStyle(fontSize: 11, color: cell.type == 'code' ? const Color(0xFFAE81FF) : const Color(0xFF66D9EF))),
                const Spacer(),
                if (selected) GestureDetector(onTap: () => setState(() => _cells.removeAt(i)), child: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFF92672))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: TextEditingController(text: cell.content),
                maxLines: null,
                style: TextStyle(fontSize: 13, fontFamily: cell.type == 'code' ? 'monospace' : null, color: const Color(0xFFF8F8F2)),
                decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                onChanged: (v) => _cells[i] = _Cell(type: cell.type, content: v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell {
  final String type;
  final String content;
  _Cell({required this.type, required this.content});
}

class _NotesView extends StatefulWidget {
  final String boardId;
  const _NotesView({required this.boardId});

  @override
  State<_NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<_NotesView> {
  final _controller = TextEditingController(text: '# Notes\n\n');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = _controller.text.split('\n');
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            padding: const EdgeInsets.only(top: 12, right: 8),
            color: const Color(0xFF252525),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(lines.length.clamp(1, 999), (i) => SizedBox(
                height: 20,
                child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Color(0xFF808080))),
              )),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: Color(0xFFF8F8F2), height: 1.54),
              decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.all(12)),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }
}
