// widgets/board_detail_view.dart
// Board detail view with face selector (Canvas, Notebook, Notes)
// Uses VSCodeNotesEditor for syntax highlighting

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/selection_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/monokai_theme.dart';
import '../ffi/ffi_helpers.dart';
import 'vscode_markdown.dart' show VSCodeBlock;
import 'vscode_notes_editor.dart';

enum BoardFace {
  canvas('canvas', Icons.brush, 'Canvas'),
  notebook('notebook', Icons.article, 'Notebook'),
  notes('notes', Icons.description, 'Notes');

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
  BoardFace _activeFace = BoardFace.notes;
  bool _showChat = false;
  bool _faceLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadActiveFace();
  }
  
  @override
  void didUpdateWidget(BoardDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.boardId != widget.boardId) {
      _faceLoaded = false;
      _loadActiveFace();
    }
  }
  
  void _loadActiveFace() {
    if (_faceLoaded) return;
    _faceLoaded = true;
    
    // Load saved face from FFI
    final mode = CyanFFI.getBoardMode(widget.boardId);
    if (mode != null && mode.isNotEmpty) {
      setState(() {
        _activeFace = BoardFace.values.firstWhere(
          (f) => f.value == mode,
          orElse: () => BoardFace.notes,
        );
      });
    }
  }
  
  void _setActiveFace(BoardFace face) {
    if (_activeFace == face) return;
    
    // Save to FFI
    CyanFFI.setBoardMode(widget.boardId, face.value);
    
    setState(() => _activeFace = face);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        const Divider(height: 1, color: MonokaiTheme.divider),
        Expanded(
          child: _showChat
              ? _buildWithChat()
              : _buildContent(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: MonokaiTheme.surface,
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 18),
            color: MonokaiTheme.cyan,
            onPressed: () => ref.read(selectionProvider.notifier).clearBoard(),
            tooltip: 'Back',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 4),
          
          // Board name
          Flexible(
            child: Text(
              widget.boardName,
              style: MonokaiTheme.titleSmall.copyWith(color: MonokaiTheme.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          
          // Face selector
          _buildFaceSelector(),
          
          const Spacer(),
          
          // Chat toggle
          _ChatToggle(
            isActive: _showChat,
            onToggle: () => setState(() => _showChat = !_showChat),
          ),
          
          // More menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: MonokaiTheme.textMuted, size: 18),
            padding: EdgeInsets.zero,
            color: MonokaiTheme.surface,
            onSelected: _handleMenuAction,
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename', style: TextStyle(color: MonokaiTheme.textPrimary))),
              const PopupMenuItem(value: 'duplicate', child: Text('Duplicate', style: TextStyle(color: MonokaiTheme.textPrimary))),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: MonokaiTheme.red))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFaceSelector() {
    return Container(
      decoration: BoxDecoration(
        color: MonokaiTheme.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: BoardFace.values.map((face) => _FaceButton(
          face: face,
          isActive: _activeFace == face,
          onTap: () => _setActiveFace(face),
        )).toList(),
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

  Widget _buildWithChat() {
    return Row(
      children: [
        Expanded(child: _buildContent()),
        Container(width: 1, color: MonokaiTheme.divider),
        SizedBox(
          width: 320,
          child: _BoardChatPanel(
            boardId: widget.boardId,
            boardName: widget.boardName,
            onClose: () => setState(() => _showChat = false),
          ),
        ),
      ],
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'delete':
        // TODO: Implement delete
        break;
      case 'rename':
        // TODO: Implement rename
        break;
      case 'duplicate':
        // TODO: Implement duplicate
        break;
    }
  }
}

// ============================================================================
// FACE BUTTON
// ============================================================================

class _FaceButton extends StatelessWidget {
  final BoardFace face;
  final bool isActive;
  final VoidCallback onTap;

  const _FaceButton({required this.face, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: face.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? MonokaiTheme.cyan.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            face.icon,
            size: 16,
            color: isActive ? MonokaiTheme.cyan : MonokaiTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// CHAT TOGGLE
// ============================================================================

class _ChatToggle extends StatelessWidget {
  final bool isActive;
  final VoidCallback onToggle;

  const _ChatToggle({required this.isActive, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isActive ? 'Hide Chat' : 'Show Chat',
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? MonokaiTheme.cyan.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? MonokaiTheme.cyan : MonokaiTheme.border,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 14,
                color: isActive ? MonokaiTheme.cyan : MonokaiTheme.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                'Chat',
                style: TextStyle(
                  fontSize: 12,
                  color: isActive ? MonokaiTheme.cyan : MonokaiTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// CANVAS VIEW (Whiteboard placeholder)
// ============================================================================

class _CanvasView extends StatelessWidget {
  final String boardId;
  const _CanvasView({required this.boardId});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MonokaiTheme.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: MonokaiTheme.surfaceLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.brush, size: 40, color: MonokaiTheme.purple),
            ),
            const SizedBox(height: 16),
            Text('Canvas', style: MonokaiTheme.titleMedium.copyWith(color: MonokaiTheme.textSecondary)),
            const SizedBox(height: 8),
            Text('Whiteboard coming soon', style: MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.textMuted)),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// NOTEBOOK VIEW (Cells)
// ============================================================================

class _NotebookView extends StatefulWidget {
  final String boardId;
  const _NotebookView({required this.boardId});

  @override
  State<_NotebookView> createState() => _NotebookViewState();
}

class _NotebookViewState extends State<_NotebookView> {
  List<_NotebookCell> _cells = [];
  int? _selectedIdx;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCells();
  }
  
  void _loadCells() {
    final json = CyanFFI.loadNotebookCells(widget.boardId);
    if (json != null && json.isNotEmpty) {
      try {
        final list = jsonDecode(json) as List<dynamic>;
        _cells = list.map((c) {
          final map = c as Map<String, dynamic>;
          return _NotebookCell(
            id: map['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
            type: _parseCellType(map['cell_type'] as String? ?? 'markdown'),
            content: map['content'] as String? ?? '',
          );
        }).toList();
      } catch (e) {
        debugPrint('Error loading cells: $e');
      }
    }
    
    // Add default cell if empty
    if (_cells.isEmpty) {
      _cells.add(_NotebookCell(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: CellType.markdown,
        content: '# Welcome\n\nStart writing markdown here...',
      ));
      _saveCell(_cells.first);
    }
    
    setState(() => _loading = false);
  }
  
  CellType _parseCellType(String type) {
    switch (type) {
      case 'code': return CellType.code;
      case 'sql': return CellType.sql;
      default: return CellType.markdown;
    }
  }
  
  void _saveCell(_NotebookCell cell) {
    CyanFFI.saveNotebookCell(widget.boardId, {
      'id': cell.id,
      'cell_type': cell.type.name,
      'content': cell.content,
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    
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
      decoration: const BoxDecoration(
        color: MonokaiTheme.surface,
        border: Border(bottom: BorderSide(color: MonokaiTheme.divider)),
      ),
      child: Row(
        children: [
          Text('Add:', style: MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.textMuted)),
          const SizedBox(width: 8),
          _AddCellButton(
            label: 'Markdown',
            icon: Icons.text_fields,
            color: MonokaiTheme.cyan,
            onTap: () => _addCell(CellType.markdown),
          ),
          _AddCellButton(
            label: 'Code',
            icon: Icons.code,
            color: MonokaiTheme.purple,
            onTap: () => _addCell(CellType.code),
          ),
          _AddCellButton(
            label: 'SQL',
            icon: Icons.storage,
            color: MonokaiTheme.yellow,
            onTap: () => _addCell(CellType.sql),
          ),
        ],
      ),
    );
  }

  Widget _buildCell(int idx) {
    final cell = _cells[idx];
    final isSelected = _selectedIdx == idx;

    return GestureDetector(
      onTap: () => setState(() => _selectedIdx = idx),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? MonokaiTheme.cyan : MonokaiTheme.border,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cell header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: MonokaiTheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(7),
                  topRight: Radius.circular(7),
                ),
              ),
              child: Row(
                children: [
                  Icon(cell.type.icon, size: 14, color: cell.type.color),
                  const SizedBox(width: 6),
                  Text(
                    cell.type.label,
                    style: MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.textMuted),
                  ),
                  const Spacer(),
                  if (isSelected) ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_upward, size: 14),
                      color: MonokaiTheme.textMuted,
                      onPressed: idx > 0 ? () => _moveCell(idx, -1) : null,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_downward, size: 14),
                      color: MonokaiTheme.textMuted,
                      onPressed: idx < _cells.length - 1 ? () => _moveCell(idx, 1) : null,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 14),
                      color: MonokaiTheme.red,
                      onPressed: () => _deleteCell(idx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    ),
                  ],
                ],
              ),
            ),
            // Cell content
            Container(
              constraints: const BoxConstraints(minHeight: 100),
              child: cell.type == CellType.markdown
                  ? _MarkdownCell(
                      content: cell.content,
                      onChanged: (v) => _updateCell(idx, v),
                    )
                  : VSCodeBlock(
                      code: cell.content.isEmpty ? '// Enter code here' : cell.content,
                      language: cell.type == CellType.sql ? 'sql' : null,
                      showLineNumbers: true,
                      maxHeight: 300,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _addCell(CellType type) {
    final cell = _NotebookCell(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      content: '',
    );
    setState(() {
      _cells.add(cell);
      _selectedIdx = _cells.length - 1;
    });
    _saveCell(cell);
  }

  void _updateCell(int idx, String content) {
    final cell = _NotebookCell(
      id: _cells[idx].id,
      type: _cells[idx].type,
      content: content,
    );
    setState(() {
      _cells[idx] = cell;
    });
    _saveCell(cell);
  }

  void _moveCell(int idx, int delta) {
    setState(() {
      final cell = _cells.removeAt(idx);
      _cells.insert(idx + delta, cell);
      _selectedIdx = idx + delta;
    });
    // Save new order
    CyanFFI.reorderNotebookCells(widget.boardId, _cells.map((c) => c.id).toList());
  }

  void _deleteCell(int idx) {
    final cellId = _cells[idx].id;
    setState(() {
      _cells.removeAt(idx);
      _selectedIdx = null;
    });
    CyanFFI.deleteNotebookCell(widget.boardId, cellId);
  }
}

class _AddCellButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _AddCellButton({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: MonokaiTheme.background,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkdownCell extends StatelessWidget {
  final String content;
  final ValueChanged<String> onChanged;

  const _MarkdownCell({required this.content, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: TextEditingController(text: content),
      maxLines: null,
      style: MonokaiTheme.bodyMedium.copyWith(
        fontFamily: 'monospace',
        color: MonokaiTheme.textPrimary,
      ),
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.all(12),
        border: InputBorder.none,
        hintText: 'Write markdown...',
        hintStyle: TextStyle(color: MonokaiTheme.textMuted),
      ),
      onChanged: onChanged,
    );
  }
}

enum CellType {
  markdown('Markdown', Icons.text_fields, MonokaiTheme.cyan),
  code('Code', Icons.code, MonokaiTheme.purple),
  sql('SQL', Icons.storage, MonokaiTheme.yellow);

  final String label;
  final IconData icon;
  final Color color;
  const CellType(this.label, this.icon, this.color);
}

class _NotebookCell {
  final String id;
  final CellType type;
  final String content;
  _NotebookCell({
    String? id,
    required this.type,
    required this.content,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();
}

// ============================================================================
// NOTES VIEW (VSCode-style editor)
// ============================================================================

class _NotesView extends StatefulWidget {
  final String boardId;
  const _NotesView({required this.boardId});

  @override
  State<_NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<_NotesView> {
  String _content = '';
  String? _cellId;
  bool _loading = true;
  
  static const _defaultContent = '''# Notes

Welcome to VSCode-style notes!

Start writing here...
''';

  @override
  void initState() {
    super.initState();
    _loadContent();
  }
  
  void _loadContent() {
    // Notes view uses a single markdown cell
    final json = CyanFFI.loadNotebookCells(widget.boardId);
    if (json != null && json.isNotEmpty) {
      try {
        final list = jsonDecode(json) as List<dynamic>;
        // Find first markdown cell
        for (final c in list) {
          final map = c as Map<String, dynamic>;
          if (map['cell_type'] == 'markdown') {
            _cellId = map['id'] as String?;
            _content = map['content'] as String? ?? '';
            break;
          }
        }
      } catch (e) {
        debugPrint('Error loading notes: $e');
      }
    }
    
    // Create default cell if none exists
    if (_content.isEmpty) {
      _content = _defaultContent;
      _cellId = DateTime.now().millisecondsSinceEpoch.toString();
      _saveContent();
    }
    
    setState(() => _loading = false);
  }
  
  void _saveContent() {
    if (_cellId == null) return;
    CyanFFI.saveNotebookCell(widget.boardId, {
      'id': _cellId,
      'cell_type': 'markdown',
      'content': _content,
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return VSCodeNotesEditor(
      initialContent: _content,
      onChanged: (text) {
        setState(() => _content = text);
      },
      onSave: _saveContent,
    );
  }
}

// ============================================================================
// BOARD CHAT PANEL (Inline chat for board)
// ============================================================================

class _BoardChatPanel extends ConsumerWidget {
  final String boardId;
  final String boardName;
  final VoidCallback onClose;

  const _BoardChatPanel({
    required this.boardId,
    required this.boardName,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: MonokaiTheme.background,
      child: Column(
        children: [
          // Header
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: MonokaiTheme.surface,
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline, size: 14, color: MonokaiTheme.cyan),
                const SizedBox(width: 8),
                Text('Board Chat', style: MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.textPrimary)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  color: MonokaiTheme.textMuted,
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: MonokaiTheme.divider),
          
          // Chat placeholder
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 32, color: MonokaiTheme.textMuted),
                  const SizedBox(height: 8),
                  Text('Board chat', style: MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.textMuted)),
                  const SizedBox(height: 4),
                  Text('Coming soon', style: MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.textMuted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
