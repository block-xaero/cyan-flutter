// widgets/board_detail_view.dart
// Board detail view with face selector (Canvas, Notebook, Notes)
// Uses VSCodeNotesEditor for syntax highlighting

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/selection_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/monokai_theme.dart';
import '../ffi/ffi_helpers.dart';
import '../services/python_executor.dart';
import '../services/autocomplete_provider.dart';
import '../services/notebook_import_export.dart';
import '../services/model_registry.dart';
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
      case 'mermaid': return CellType.mermaid;
      case 'model': return CellType.model;
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
            label: 'Python',
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
          _AddCellButton(
            label: 'Mermaid',
            icon: Icons.account_tree,
            color: MonokaiTheme.green,
            onTap: () => _addCell(CellType.mermaid),
          ),
          _AddCellButton(
            label: 'Model',
            icon: Icons.smart_toy,
            color: MonokaiTheme.orange,
            onTap: () => _addCell(CellType.model),
          ),
          const Spacer(),
          // Import / Export
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 16, color: MonokaiTheme.textMuted),
            color: MonokaiTheme.surface,
            onSelected: _handleMenuAction,
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'import_ipynb', child: Row(children: [
                Icon(Icons.upload_file, size: 14, color: MonokaiTheme.cyan),
                const SizedBox(width: 6),
                Text('Import .ipynb', style: TextStyle(fontSize: 12, color: MonokaiTheme.textPrimary)),
              ])),
              PopupMenuItem(value: 'import_spreadsheet', child: Row(children: [
                Icon(Icons.table_chart, size: 14, color: MonokaiTheme.green),
                const SizedBox(width: 6),
                Text('Import Spreadsheet', style: TextStyle(fontSize: 12, color: MonokaiTheme.textPrimary)),
              ])),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'export_pdf', child: Row(children: [
                Icon(Icons.picture_as_pdf, size: 14, color: MonokaiTheme.red),
                const SizedBox(width: 6),
                Text('Export PDF', style: TextStyle(fontSize: 12, color: MonokaiTheme.textPrimary)),
              ])),
              PopupMenuItem(value: 'export_ipynb', child: Row(children: [
                Icon(Icons.download, size: 14, color: MonokaiTheme.purple),
                const SizedBox(width: 6),
                Text('Export .ipynb', style: TextStyle(fontSize: 12, color: MonokaiTheme.textPrimary)),
              ])),
            ],
          ),
        ],
      ),
    );
  }
  
  void _handleMenuAction(String action) async {
    switch (action) {
      case 'import_ipynb':
        _showImportIpynbDialog();
        break;
      case 'import_spreadsheet':
        _showImportSpreadsheetDialog();
        break;
      case 'export_pdf':
        _exportPdf();
        break;
      case 'export_ipynb':
        _exportIpynb();
        break;
    }
  }
  
  void _showImportIpynbDialog() {
    final pathController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MonokaiTheme.surface,
        title: Text('Import Jupyter Notebook', style: TextStyle(color: MonokaiTheme.textPrimary)),
        content: TextField(
          controller: pathController,
          style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFF8F8F2)),
          decoration: InputDecoration(
            hintText: '/path/to/notebook.ipynb',
            hintStyle: TextStyle(color: MonokaiTheme.textMuted),
            filled: true, fillColor: MonokaiTheme.background,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: MonokaiTheme.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: MonokaiTheme.cyan),
            onPressed: () async {
              Navigator.pop(ctx);
              final path = pathController.text.trim();
              if (path.isEmpty) return;
              final cells = await JupyterImporter.importFile(path);
              if (cells.isEmpty) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No cells found in notebook')));
                return;
              }
              setState(() {
                for (final cell in cells) {
                  final nc = _NotebookCell(id: cell.id, type: _parseCellType(cell.cellType), content: cell.content);
                  _cells.add(nc);
                  _saveCell(nc);
                }
              });
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported ${cells.length} cells')));
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }
  
  void _showImportSpreadsheetDialog() {
    final pathController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MonokaiTheme.surface,
        title: Text('Import Spreadsheet', style: TextStyle(color: MonokaiTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pathController,
              style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFF8F8F2)),
              decoration: InputDecoration(
                hintText: '/path/to/data.csv  (.csv, .xlsx, .parquet)',
                hintStyle: TextStyle(color: MonokaiTheme.textMuted),
                filled: true, fillColor: MonokaiTheme.background,
              ),
            ),
            const SizedBox(height: 6),
            Text('Creates a Python cell pre-loaded with your data as a DataFrame', style: TextStyle(fontSize: 10, color: MonokaiTheme.textMuted)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: MonokaiTheme.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: MonokaiTheme.green),
            onPressed: () async {
              Navigator.pop(ctx);
              final path = pathController.text.trim();
              if (path.isEmpty) return;
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Loading spreadsheet...')));
              final info = await SpreadsheetHandler.importSpreadsheet(path);
              if (info == null) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load spreadsheet')));
                return;
              }
              setState(() {
                // Add a markdown cell with preview
                final mdCell = _NotebookCell(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  type: CellType.markdown,
                  content: '## 📊 ${info.fileName}\n\n${info.rows} rows × ${info.cols} columns\n\nColumns: ${info.columns.join(", ")}',
                );
                _cells.add(mdCell);
                _saveCell(mdCell);
                
                // Add a code cell with boilerplate
                final codeCell = _NotebookCell(
                  id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
                  type: CellType.code,
                  content: info.boilerplateCode,
                );
                _cells.add(codeCell);
                _saveCell(codeCell);
              });
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${info.fileName} loaded (${info.rows} rows)')));
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }
  
  void _exportPdf() async {
    final cellData = _cells.map((c) => {'cell_type': c.type.name, 'content': c.content}).toList();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exporting PDF...')));
    final path = await NotebookPdfExporter.exportToPdf(cellData, title: 'Notebook');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(path != null ? 'PDF saved: $path' : 'PDF export failed - try: pip install fpdf2')),
      );
    }
  }
  
  void _exportIpynb() async {
    final cellData = _cells.map((c) => {'cell_type': c.type.name, 'content': c.content}).toList();
    final ipynb = JupyterExporter.exportToIpynb(cellData);
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/notebook_${DateTime.now().millisecondsSinceEpoch}.ipynb';
    await File(path).writeAsString(ipynb);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported: $path')));
    }
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
            _buildCellHeader(cell, idx, isSelected),
            // Cell content - different editor per type
            _buildCellContent(cell, idx),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCellHeader(_NotebookCell cell, int idx, bool isSelected) {
    return Container(
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
          if (cell.type == CellType.code) ...[
            const SizedBox(width: 8),
            // Run button for code cells
            _MiniButton(
              icon: Icons.play_arrow,
              label: 'Run',
              color: MonokaiTheme.green,
              onTap: () => _runCodeCell(idx),
            ),
          ],
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
    );
  }
  
  Widget _buildCellContent(_NotebookCell cell, int idx) {
    switch (cell.type) {
      case CellType.mermaid:
        return _MermaidCell(
          content: cell.content,
          onChanged: (v) => _updateCell(idx, v),
        );
      case CellType.code:
      case CellType.sql:
        return _CodeCell(
          content: cell.content,
          cellType: cell.type,
          onChanged: (v) => _updateCell(idx, v),
        );
      case CellType.model:
        return _ModelCell(
          content: cell.content,
          boardId: widget.boardId,
          cellId: cell.id,
          onChanged: (v) => _updateCell(idx, v),
        );
      case CellType.markdown:
      default:
        return _EditableCell(
          content: cell.content,
          cellType: cell.type,
          onChanged: (v) => _updateCell(idx, v),
        );
    }
  }
  
  void _runCodeCell(int idx) {
    // TODO: Implement Python execution
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Python execution coming soon!')),
    );
  }

  void _addCell(CellType type) {
    final cell = _NotebookCell(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      content: type.defaultContent,
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

class _EditableCell extends StatefulWidget {
  final String content;
  final CellType cellType;
  final ValueChanged<String> onChanged;

  const _EditableCell({
    required this.content,
    required this.cellType,
    required this.onChanged,
  });

  @override
  State<_EditableCell> createState() => _EditableCellState();
}

class _EditableCellState extends State<_EditableCell> {
  late TextEditingController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.content);
  }
  
  @override
  void didUpdateWidget(_EditableCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update if content changed externally (not from user typing)
    if (oldWidget.content != widget.content && 
        _controller.text != widget.content) {
      _controller.text = widget.content;
    }
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _hintText {
    switch (widget.cellType) {
      case CellType.markdown:
        return 'Write markdown...';
      case CellType.code:
        return '# Python code here\nimport pandas as pd\n';
      case CellType.sql:
        return 'SELECT * FROM table;';
      case CellType.mermaid:
        return 'graph TD\n    A --> B';
      case CellType.model:
        return '';
    }
  }
  
  Color get _accentColor => widget.cellType.color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.cellType == CellType.markdown 
            ? Colors.transparent 
            : const Color(0xFF1E1E1E),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(7),
          bottomRight: Radius.circular(7),
        ),
      ),
      child: TextField(
        controller: _controller,
        maxLines: null,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.5,
          color: MonokaiTheme.textPrimary,
        ),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.all(12),
          border: InputBorder.none,
          hintText: _hintText,
          hintStyle: TextStyle(color: MonokaiTheme.textMuted.withOpacity(0.5)),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

/// Code cell with VSCode-style editor, execution, output, and autocomplete
class _CodeCell extends StatefulWidget {
  final String content;
  final CellType cellType;
  final ValueChanged<String> onChanged;

  const _CodeCell({
    required this.content,
    required this.cellType,
    required this.onChanged,
  });

  @override
  State<_CodeCell> createState() => _CodeCellState();
}

class _CodeCellState extends State<_CodeCell> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  final _executor = PythonExecutor();
  final _sqlExecutor = SqlExecutor();
  
  ExecutionResult? _result;
  SqlResult? _sqlResult;
  bool _isRunning = false;
  List<AutocompleteSuggestion> _suggestions = [];
  bool _showSuggestions = false;
  String _currentWord = '';
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.content);
    _controller.addListener(_onTextChanged);
  }
  
  @override
  void didUpdateWidget(_CodeCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content && 
        _controller.text != widget.content) {
      _controller.text = widget.content;
    }
  }
  
  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _hideOverlay();
    super.dispose();
  }
  
  void _onTextChanged() {
    // Extract current word for autocomplete
    final text = _controller.text;
    final pos = _controller.selection.baseOffset;
    if (pos < 0 || pos > text.length) return;
    
    // Find word boundaries
    int start = pos;
    while (start > 0 && RegExp(r'[a-zA-Z_0-9.]').hasMatch(text[start - 1])) {
      start--;
    }
    
    final word = text.substring(start, pos);
    
    if (word.length >= 2) {
      final lang = widget.cellType == CellType.code ? 'python' : 'sql';
      final suggestions = AutocompleteProvider.getSuggestions(lang, word, fullText: text);
      setState(() {
        _suggestions = suggestions;
        _currentWord = word;
        _showSuggestions = suggestions.isNotEmpty;
      });
      if (_showSuggestions) _showOverlay();
    } else {
      _hideOverlay();
      setState(() => _showSuggestions = false);
    }
  }
  
  void _showOverlay() {
    _hideOverlay();
    _overlayEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        width: 250,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 24),
          child: Material(
            elevation: 8,
            color: const Color(0xFF252526),
            borderRadius: BorderRadius.circular(4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (ctx, i) {
                  final s = _suggestions[i];
                  return InkWell(
                    onTap: () => _applySuggestion(s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          Icon(s.icon, size: 14, color: s.color),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(s.label, style: const TextStyle(fontSize: 12, color: Color(0xFFF8F8F2))),
                          ),
                          Text(s.detail, style: TextStyle(fontSize: 10, color: MonokaiTheme.textMuted)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }
  
  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
  
  void _applySuggestion(AutocompleteSuggestion suggestion) {
    final text = _controller.text;
    final pos = _controller.selection.baseOffset;
    
    // Replace current word
    int start = pos;
    while (start > 0 && RegExp(r'[a-zA-Z_0-9.]').hasMatch(text[start - 1])) {
      start--;
    }
    
    final newText = text.substring(0, start) + suggestion.insertText + text.substring(pos);
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(offset: start + suggestion.insertText.length);
    widget.onChanged(newText);
    _hideOverlay();
  }
  
  Future<void> _runCode() async {
    setState(() { _isRunning = true; _result = null; _sqlResult = null; });
    
    if (widget.cellType == CellType.sql) {
      final result = await _sqlExecutor.execute(_controller.text);
      if (mounted) setState(() { _sqlResult = result; _isRunning = false; });
    } else {
      final result = await _executor.execute(_controller.text);
      if (mounted) setState(() { _result = result; _isRunning = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPython = widget.cellType == CellType.code;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Editor area
        Container(
          constraints: const BoxConstraints(minHeight: 120, maxHeight: 400),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Line numbers gutter
              Container(
                width: 40,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  border: Border(right: BorderSide(color: MonokaiTheme.border.withOpacity(0.3))),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(
                    (_controller.text.split('\n').length).clamp(1, 50),
                    (i) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text('${i + 1}',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: MonokaiTheme.textMuted.withOpacity(0.5))),
                    ),
                  ),
                ),
              ),
              // Code editor with autocomplete
              Expanded(
                child: CompositedTransformTarget(
                  link: _layerLink,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: null,
                    style: TextStyle(
                      fontFamily: 'monospace', fontSize: 13, height: 1.5,
                      color: isPython ? const Color(0xFF9CDCFE) : const Color(0xFF569CD6),
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.all(12),
                      border: InputBorder.none,
                      hintText: widget.cellType.defaultContent,
                      hintStyle: TextStyle(color: MonokaiTheme.textMuted.withOpacity(0.3)),
                    ),
                    onChanged: (text) {
                      widget.onChanged(text);
                      setState(() {}); // Refresh line numbers
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        // Run bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: const Color(0xFF252526),
          child: Row(
            children: [
              // Run button
              InkWell(
                onTap: _isRunning ? _executor.cancel : _runCode,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _isRunning ? MonokaiTheme.red.withOpacity(0.2) : MonokaiTheme.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isRunning ? Icons.stop : Icons.play_arrow,
                        size: 14,
                        color: _isRunning ? MonokaiTheme.red : MonokaiTheme.green,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isRunning ? 'Stop' : 'Run',
                        style: TextStyle(fontSize: 11, color: _isRunning ? MonokaiTheme.red : MonokaiTheme.green),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (isPython) ...[
                // Pip install button
                InkWell(
                  onTap: () => _showPipInstallDialog(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: MonokaiTheme.purple.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download, size: 12, color: MonokaiTheme.purple),
                        const SizedBox(width: 3),
                        Text('pip install', style: TextStyle(fontSize: 10, color: MonokaiTheme.purple)),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // DB connection button
                InkWell(
                  onTap: () => _showDbConnectionDialog(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: MonokaiTheme.yellow.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.storage, size: 12, color: MonokaiTheme.yellow),
                        const SizedBox(width: 3),
                        Text('Add DB', style: TextStyle(fontSize: 10, color: MonokaiTheme.yellow)),
                      ],
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (_result != null)
                Text(_result!.formattedTime, style: TextStyle(fontSize: 10, color: MonokaiTheme.textMuted)),
            ],
          ),
        ),
        // Output area
        if (_isRunning)
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF1A1A1A),
            child: Row(
              children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text('Running...', style: TextStyle(fontSize: 11, color: MonokaiTheme.textMuted)),
              ],
            ),
          ),
        if (_result != null && _result!.hasOutput) _buildPythonOutput(),
        if (_sqlResult != null) _buildSqlOutput(),
      ],
    );
  }
  
  Widget _buildPythonOutput() {
    final r = _result!;
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: r.success ? MonokaiTheme.green.withOpacity(0.3) : MonokaiTheme.red.withOpacity(0.3))),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r.cleanOutput.isNotEmpty)
              Text(
                r.cleanOutput,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFF8F8F2)),
              ),
            if (r.stderr.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: MonokaiTheme.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  r.stderr,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: MonokaiTheme.red),
                ),
              ),
            // Chart images
            for (final imgPath in r.imagePaths)
              Container(
                margin: const EdgeInsets.only(top: 8),
                child: Image.file(
                  File(imgPath),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Text('Failed to load chart', style: TextStyle(color: MonokaiTheme.red, fontSize: 11)),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSqlOutput() {
    final r = _sqlResult!;
    if (r.isError) {
      return Container(
        padding: const EdgeInsets.all(10),
        color: const Color(0xFF1A1A1A),
        child: Text(r.error!, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: MonokaiTheme.red)),
      );
    }
    if (r.message != null) {
      return Container(
        padding: const EdgeInsets.all(10),
        color: const Color(0xFF1A1A1A),
        child: Text(r.message!, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: MonokaiTheme.green)),
      );
    }
    if (r.hasTable) {
      return Container(
        constraints: const BoxConstraints(maxHeight: 250),
        color: const Color(0xFF1A1A1A),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowHeight: 30,
              dataRowMinHeight: 24,
              dataRowMaxHeight: 28,
              columnSpacing: 16,
              headingTextStyle: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF66D9EF)),
              dataTextStyle: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFFF8F8F2)),
              columns: r.columns!.map((c) => DataColumn(label: Text(c))).toList(),
              rows: r.rows!.take(100).map((row) {
                return DataRow(
                  cells: r.columns!.map((c) => DataCell(Text('${row[c] ?? ''}'))).toList(),
                );
              }).toList(),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
  
  void _showPipInstallDialog(BuildContext context) {
    final pkgController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MonokaiTheme.surface,
        title: Text('pip install', style: TextStyle(color: MonokaiTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pkgController,
              style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFF8F8F2)),
              decoration: InputDecoration(
                hintText: 'e.g. pandas matplotlib seaborn',
                hintStyle: TextStyle(color: MonokaiTheme.textMuted),
                filled: true,
                fillColor: MonokaiTheme.background,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Separate multiple packages with spaces',
              style: TextStyle(fontSize: 11, color: MonokaiTheme.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: MonokaiTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: MonokaiTheme.green),
            onPressed: () async {
              Navigator.pop(ctx);
              final packages = pkgController.text.trim().split(RegExp(r'\s+'));
              for (final pkg in packages) {
                if (pkg.isNotEmpty) {
                  final result = await PythonEnvironment.instance.installPackage(pkg);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(result.success ? '$pkg installed!' : 'Failed: ${result.stderr}')),
                    );
                  }
                }
              }
            },
            child: const Text('Install'),
          ),
        ],
      ),
    );
  }
  
  void _showDbConnectionDialog(BuildContext context) {
    final nameController = TextEditingController(text: 'local');
    final pathController = TextEditingController();
    String dbType = 'sqlite';
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: MonokaiTheme.surface,
          title: Text('Add Database', style: TextStyle(color: MonokaiTheme.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // DB type selector
              Row(
                children: [
                  for (final type in ['sqlite', 'postgres', 'mysql'])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(type),
                        selected: dbType == type,
                        onSelected: (s) => setDialogState(() => dbType = type),
                        selectedColor: MonokaiTheme.yellow.withOpacity(0.3),
                        labelStyle: TextStyle(fontSize: 11, color: MonokaiTheme.textPrimary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFF8F8F2)),
                decoration: InputDecoration(
                  labelText: 'Connection Name',
                  labelStyle: TextStyle(color: MonokaiTheme.textMuted),
                  filled: true, fillColor: MonokaiTheme.background,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pathController,
                style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFF8F8F2)),
                decoration: InputDecoration(
                  labelText: dbType == 'sqlite' ? 'Database File Path' : 'Connection String',
                  hintText: dbType == 'sqlite' ? '/path/to/db.sqlite' : 'host=localhost;port=5432;user=...',
                  hintStyle: TextStyle(color: MonokaiTheme.textMuted.withOpacity(0.5)),
                  labelStyle: TextStyle(color: MonokaiTheme.textMuted),
                  filled: true, fillColor: MonokaiTheme.background,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: MonokaiTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: MonokaiTheme.yellow),
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await _sqlExecutor.addConnection(
                  name: nameController.text, type: dbType, connectionString: pathController.text,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? 'Connection added!' : 'Failed to connect')),
                  );
                }
              },
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mermaid cell with split view: Editor | Live Preview
class _MermaidCell extends StatefulWidget {
  final String content;
  final ValueChanged<String> onChanged;

  const _MermaidCell({
    required this.content,
    required this.onChanged,
  });

  @override
  State<_MermaidCell> createState() => _MermaidCellState();
}

class _MermaidCellState extends State<_MermaidCell> {
  late TextEditingController _controller;
  bool _isDragOver = false;
  bool _isConverting = false;
  String? _conversionError;
  
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.content);
  }
  
  @override
  void didUpdateWidget(_MermaidCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content && 
        _controller.text != widget.content) {
      _controller.text = widget.content;
    }
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(7),
          bottomRight: Radius.circular(7),
        ),
      ),
      child: Row(
        children: [
          // Editor side
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Editor header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: const Color(0xFF252526),
                  child: Row(
                    children: [
                      const Icon(Icons.code, size: 12, color: Color(0xFF75715E)),
                      const SizedBox(width: 4),
                      Text(
                        'Mermaid Code',
                        style: TextStyle(fontSize: 10, color: MonokaiTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                // Editor
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                      color: Color(0xFFA6E22E),
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.all(8),
                      border: InputBorder.none,
                      hintText: CellType.mermaid.defaultContent,
                      hintStyle: TextStyle(color: MonokaiTheme.textMuted.withOpacity(0.3)),
                    ),
                    onChanged: (text) {
                      widget.onChanged(text);
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),
          // Divider
          Container(width: 1, color: MonokaiTheme.border),
          // Preview side
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Preview header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: const Color(0xFF252526),
                  child: Row(
                    children: [
                      const Icon(Icons.preview, size: 12, color: Color(0xFF75715E)),
                      const SizedBox(width: 4),
                      Text(
                        'Preview',
                        style: TextStyle(fontSize: 10, color: MonokaiTheme.textMuted),
                      ),
                      const Spacer(),
                      if (_isConverting)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1),
                        ),
                    ],
                  ),
                ),
                // Preview / Drop zone
                Expanded(
                  child: DragTarget<String>(
                    onWillAcceptWithDetails: (details) {
                      setState(() => _isDragOver = true);
                      return true;
                    },
                    onLeave: (_) => setState(() => _isDragOver = false),
                    onAcceptWithDetails: (details) {
                      setState(() => _isDragOver = false);
                      _handleImageDrop(details.data);
                    },
                    builder: (context, candidateData, rejectedData) {
                      return Container(
                        decoration: BoxDecoration(
                          color: _isDragOver 
                              ? MonokaiTheme.green.withOpacity(0.1) 
                              : const Color(0xFF2D2D2D),
                          border: _isDragOver 
                              ? Border.all(color: MonokaiTheme.green, width: 2)
                              : null,
                        ),
                        child: _buildPreview(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPreview() {
    final code = _controller.text.trim();
    
    if (code.isEmpty) {
      return _buildDropHint();
    }
    
    if (_conversionError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _conversionError!,
            style: TextStyle(color: MonokaiTheme.red, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    
    // Render mermaid via HTML string in a simple text preview
    // Full WebView requires webview_flutter package
    // For now: parse and render a structural preview
    return _MermaidRenderPreview(code: code);
  }
  
  Widget _buildDropHint() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 32,
            color: MonokaiTheme.textMuted.withOpacity(0.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Drop whiteboard screenshot\nto convert to Mermaid',
            style: TextStyle(
              fontSize: 10,
              color: MonokaiTheme.textMuted.withOpacity(0.5),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'or write code on the left',
            style: TextStyle(
              fontSize: 9,
              color: MonokaiTheme.textMuted.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _handleImageDrop(String imagePath) async {
    setState(() {
      _isConverting = true;
      _conversionError = null;
    });
    
    try {
      // TODO: Call Claude API to convert image to mermaid
      // For now, show placeholder
      await Future.delayed(const Duration(seconds: 1));
      
      final generatedCode = '''graph TD
    A[Whiteboard Image] --> B[Claude API]
    B --> C[Mermaid Code]
    C --> D[Preview]
    
    %% Generated from dropped image
    %% TODO: Implement Claude vision API''';
      
      _controller.text = generatedCode;
      widget.onChanged(generatedCode);
      
    } catch (e) {
      setState(() => _conversionError = 'Conversion failed: $e');
    } finally {
      setState(() => _isConverting = false);
    }
  }
}

/// Graphical mermaid preview - renders parsed nodes/edges as a visual diagram
class _MermaidRenderPreview extends StatelessWidget {
  final String code;
  
  const _MermaidRenderPreview({required this.code});
  
  @override
  Widget build(BuildContext context) {
    final parsed = _MermaidParser.parse(code);
    
    if (parsed.nodes.isEmpty && parsed.diagramType == null) {
      return Center(
        child: Text(
          'Type mermaid code to see preview',
          style: TextStyle(color: MonokaiTheme.textMuted, fontSize: 11),
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // Diagram type badge
          if (parsed.diagramType != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: MonokaiTheme.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                parsed.diagramType!,
                style: TextStyle(fontSize: 9, color: MonokaiTheme.green),
              ),
            ),
          // Render nodes with connections
          ...parsed.nodes.entries.map((entry) {
            final nodeId = entry.key;
            final label = entry.value;
            final isDecision = label.contains('?') || parsed.decisions.contains(nodeId);
            final outgoing = parsed.edges.where((e) => e.from == nodeId).toList();
            
            return Column(
              children: [
                // Node
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: isDecision 
                        ? MonokaiTheme.yellow.withOpacity(0.15)
                        : MonokaiTheme.cyan.withOpacity(0.15),
                    borderRadius: isDecision 
                        ? BorderRadius.circular(0) // Diamond shape hint
                        : BorderRadius.circular(6),
                    border: Border.all(
                      color: isDecision 
                          ? MonokaiTheme.yellow.withOpacity(0.5)
                          : MonokaiTheme.cyan.withOpacity(0.5),
                    ),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 10, color: Color(0xFFF8F8F2)),
                    textAlign: TextAlign.center,
                  ),
                ),
                // Edge arrows
                for (final edge in outgoing)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_downward, size: 12, color: MonokaiTheme.textMuted.withOpacity(0.5)),
                        if (edge.label.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D2D2D),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(edge.label, style: TextStyle(fontSize: 8, color: MonokaiTheme.textMuted)),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          }),
          // Stats
          const SizedBox(height: 8),
          Text(
            '${parsed.nodes.length} nodes • ${parsed.edges.length} edges',
            style: TextStyle(fontSize: 9, color: MonokaiTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

class _MermaidParser {
  static _ParsedMermaid parse(String code) {
    final lines = code.split('\n');
    final nodes = <String, String>{};
    final edges = <_MermaidEdge>[];
    final decisions = <String>{};
    String? diagramType;
    
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('%%')) continue;
      
      if (trimmed.startsWith('graph ') || trimmed.startsWith('flowchart ')) {
        diagramType = 'Flowchart';
        continue;
      }
      if (trimmed.startsWith('sequenceDiagram')) { diagramType = 'Sequence Diagram'; continue; }
      if (trimmed.startsWith('classDiagram')) { diagramType = 'Class Diagram'; continue; }
      if (trimmed.startsWith('stateDiagram')) { diagramType = 'State Diagram'; continue; }
      if (trimmed.startsWith('erDiagram')) { diagramType = 'ER Diagram'; continue; }
      if (trimmed.startsWith('gantt')) { diagramType = 'Gantt Chart'; continue; }
      if (trimmed.startsWith('pie')) { diagramType = 'Pie Chart'; continue; }
      if (trimmed.startsWith('mindmap')) { diagramType = 'Mind Map'; continue; }
      if (trimmed.startsWith('gitgraph')) { diagramType = 'Git Graph'; continue; }
      
      // Parse flowchart edges: A[Label] --> B[Label]
      final edgeMatch = RegExp(r'(\w+)(\[.*?\]|\{.*?\}|\(.*?\))?\s*(-->|---|\->|==>|-.->)\s*(\|.*?\|)?\s*(\w+)(\[.*?\]|\{.*?\}|\(.*?\))?').firstMatch(trimmed);
      if (edgeMatch != null) {
        final from = edgeMatch.group(1)!;
        final fromLabel = _extractLabel(edgeMatch.group(2)) ?? from;
        final edgeLabel = _extractLabel(edgeMatch.group(4)) ?? '';
        final to = edgeMatch.group(5)!;
        final toLabel = _extractLabel(edgeMatch.group(6)) ?? to;
        
        nodes[from] = fromLabel;
        nodes[to] = toLabel;
        edges.add(_MermaidEdge(from: from, to: to, label: edgeLabel));
        
        // Detect decision nodes (curly braces)
        if (edgeMatch.group(2)?.startsWith('{') == true) decisions.add(from);
        if (edgeMatch.group(6)?.startsWith('{') == true) decisions.add(to);
      }
    }
    
    return _ParsedMermaid(
      nodes: nodes,
      edges: edges,
      decisions: decisions,
      diagramType: diagramType,
    );
  }
  
  static String? _extractLabel(String? raw) {
    if (raw == null) return null;
    return raw.replaceAll(RegExp(r'[\[\]{}\(\)|]'), '').trim();
  }
}

class _ParsedMermaid {
  final Map<String, String> nodes;
  final List<_MermaidEdge> edges;
  final Set<String> decisions;
  final String? diagramType;
  
  _ParsedMermaid({
    required this.nodes,
    required this.edges,
    required this.decisions,
    this.diagramType,
  });
}

class _MermaidEdge {
  final String from;
  final String to;
  final String label;
  
  _MermaidEdge({required this.from, required this.to, this.label = ''});
}

/// Model cell - drag GGUF/ONNX/HF, run inference, peer-discoverable
class _ModelCell extends StatefulWidget {
  final String content;
  final String boardId;
  final String cellId;
  final ValueChanged<String> onChanged;
  
  const _ModelCell({
    required this.content,
    required this.boardId,
    required this.cellId,
    required this.onChanged,
  });

  @override
  State<_ModelCell> createState() => _ModelCellState();
}

class _ModelCellState extends State<_ModelCell> {
  ModelInfo? _model;
  final _inputController = TextEditingController();
  String _output = '';
  bool _isRunning = false;
  bool _isImporting = false;
  bool _isDragOver = false;
  
  @override
  void initState() {
    super.initState();
    // Try to restore from content (model ID stored in cell content)
    if (widget.content.isNotEmpty) {
      _model = ModelRegistry.instance.models
          .where((m) => m.id == widget.content)
          .firstOrNull;
    }
  }
  
  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        setState(() => _isDragOver = true);
        return true;
      },
      onLeave: (_) => setState(() => _isDragOver = false),
      onAcceptWithDetails: (details) {
        setState(() => _isDragOver = false);
        _handleFileDrop(details.data);
      },
      builder: (context, _, __) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            border: _isDragOver ? Border.all(color: MonokaiTheme.orange, width: 2) : null,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(7),
              bottomRight: Radius.circular(7),
            ),
          ),
          child: _model == null ? _buildEmptyState() : _buildLoadedState(),
        );
      },
    );
  }
  
  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.smart_toy_outlined, size: 36, color: MonokaiTheme.textMuted.withOpacity(0.5)),
          const SizedBox(height: 8),
          Text('Drop a model file here', style: TextStyle(fontSize: 12, color: MonokaiTheme.textMuted)),
          Text('.gguf  .onnx  or HuggingFace / Claude', style: TextStyle(fontSize: 10, color: MonokaiTheme.textMuted.withOpacity(0.5))),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MiniButton(icon: Icons.folder_open, label: 'Browse', color: MonokaiTheme.orange, onTap: _showFilePickerDialog),
              const SizedBox(width: 8),
              _MiniButton(icon: Icons.hub, label: 'HuggingFace', color: MonokaiTheme.yellow, onTap: _showHfDialog),
              const SizedBox(width: 8),
              _MiniButton(icon: Icons.auto_awesome, label: 'Claude', color: MonokaiTheme.cyan, onTap: _addClaudeModel),
            ],
          ),
          if (_isImporting) ...[
            const SizedBox(height: 12),
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(height: 4),
            Text('Importing...', style: TextStyle(fontSize: 10, color: MonokaiTheme.textMuted)),
          ],
        ],
      ),
    );
  }
  
  Widget _buildLoadedState() {
    final m = _model!;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Model header
          Row(
            children: [
              Icon(Icons.smart_toy, size: 16, color: MonokaiTheme.orange),
              const SizedBox(width: 6),
              Expanded(
                child: Text(m.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Color(0xFFF8F8F2))),
              ),
              // Kind badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _kindColor(m.kind).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(m.kind.badge, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _kindColor(m.kind))),
              ),
              const SizedBox(width: 6),
              if (m.fileSizeMB > 0)
                Text('${m.fileSizeMB}MB', style: TextStyle(fontSize: 9, color: MonokaiTheme.textMuted)),
            ],
          ),
          // Capabilities
          if (m.capabilities.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4, runSpacing: 2,
              children: m.capabilities.map((cap) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: MonokaiTheme.purple.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(cap, style: TextStyle(fontSize: 9, color: MonokaiTheme.purple)),
              )).toList(),
            ),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFF3E3E3E)),
          const SizedBox(height: 10),
          // Input
          Text('Input', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: MonokaiTheme.textMuted)),
          const SizedBox(height: 4),
          TextField(
            controller: _inputController,
            maxLines: 3,
            minLines: 2,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFF8F8F2)),
            decoration: InputDecoration(
              filled: true, fillColor: const Color(0xFF2D2D2D),
              hintText: 'Enter prompt...',
              hintStyle: TextStyle(color: MonokaiTheme.textMuted.withOpacity(0.4)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.all(8),
            ),
          ),
          const SizedBox(height: 8),
          // Run button
          Row(
            children: [
              InkWell(
                onTap: _isRunning ? null : _runInference,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isRunning ? Colors.grey : MonokaiTheme.orange,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isRunning)
                        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      else
                        const Icon(Icons.play_arrow, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(_isRunning ? 'Running...' : 'Run Inference', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  ModelRegistry.instance.removeModel(m.id);
                  setState(() => _model = null);
                  widget.onChanged('');
                },
                child: Icon(Icons.close, size: 14, color: MonokaiTheme.textMuted),
              ),
            ],
          ),
          // Output
          if (_output.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Output', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: MonokaiTheme.textMuted)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _output,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFF8F8F2)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Color _kindColor(ModelKind kind) {
    switch (kind) {
      case ModelKind.gguf: return MonokaiTheme.purple;
      case ModelKind.onnx: return MonokaiTheme.orange;
      case ModelKind.huggingface: return MonokaiTheme.yellow;
      case ModelKind.claude: return MonokaiTheme.cyan;
      case ModelKind.custom: return MonokaiTheme.textMuted;
    }
  }
  
  Future<void> _handleFileDrop(String path) async {
    final ext = path.split('.').last.toLowerCase();
    if (ext != 'gguf' && ext != 'onnx') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unsupported: .$ext - use .gguf or .onnx')));
      return;
    }
    setState(() => _isImporting = true);
    final model = await ModelRegistry.instance.importLocalModel(filePath: path, boardId: widget.boardId);
    if (mounted) {
      setState(() { _model = model; _isImporting = false; });
      if (model != null) widget.onChanged(model.id);
    }
  }
  
  void _showFilePickerDialog() {
    final pathCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MonokaiTheme.surface,
        title: Text('Import Model', style: TextStyle(color: MonokaiTheme.textPrimary)),
        content: TextField(
          controller: pathCtrl,
          style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFF8F8F2)),
          decoration: InputDecoration(hintText: '/path/to/model.gguf', hintStyle: TextStyle(color: MonokaiTheme.textMuted), filled: true, fillColor: MonokaiTheme.background),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: MonokaiTheme.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: MonokaiTheme.orange),
            onPressed: () { Navigator.pop(ctx); _handleFileDrop(pathCtrl.text.trim()); },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }
  
  void _showHfDialog() {
    final modelIdCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MonokaiTheme.surface,
        title: Text('HuggingFace Model', style: TextStyle(color: MonokaiTheme.textPrimary)),
        content: TextField(
          controller: modelIdCtrl,
          style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFF8F8F2)),
          decoration: InputDecoration(hintText: 'meta-llama/Llama-2-7b', hintStyle: TextStyle(color: MonokaiTheme.textMuted), filled: true, fillColor: MonokaiTheme.background),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: MonokaiTheme.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: MonokaiTheme.yellow),
            onPressed: () async {
              Navigator.pop(ctx);
              final model = await ModelRegistry.instance.registerHuggingFaceModel(modelId: modelIdCtrl.text.trim(), boardId: widget.boardId);
              if (mounted) setState(() => _model = model);
              widget.onChanged(model.id);
            },
            child: const Text('Register'),
          ),
        ],
      ),
    );
  }
  
  void _addClaudeModel() {
    final keyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MonokaiTheme.surface,
        title: Text('Claude API', style: TextStyle(color: MonokaiTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyCtrl,
              obscureText: true,
              style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFF8F8F2)),
              decoration: InputDecoration(hintText: 'sk-ant-...', hintStyle: TextStyle(color: MonokaiTheme.textMuted), filled: true, fillColor: MonokaiTheme.background, labelText: 'API Key', labelStyle: TextStyle(color: MonokaiTheme.textMuted)),
            ),
            const SizedBox(height: 4),
            Text('Uses Claude Sonnet 4', style: TextStyle(fontSize: 10, color: MonokaiTheme.textMuted)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: MonokaiTheme.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: MonokaiTheme.cyan),
            onPressed: () {
              Navigator.pop(ctx);
              final model = ModelRegistry.instance.registerClaudeModel(boardId: widget.boardId, apiKey: keyCtrl.text.trim());
              setState(() => _model = model);
              widget.onChanged(model.id);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _runInference() async {
    if (_model == null || _inputController.text.trim().isEmpty) return;
    setState(() { _isRunning = true; _output = ''; });
    
    final result = await ModelRegistry.instance.runInference(
      modelId: _model!.id,
      prompt: _inputController.text,
    );
    
    if (mounted) {
      setState(() {
        _isRunning = false;
        _output = result.success ? result.output : 'Error: ${result.error}';
        if (result.timingMs != null) _output += '\n\n⏱ ${result.timingMs}ms';
      });
    }
  }
}

/// Mini button for cell header
class _MiniButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  
  const _MiniButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

enum CellType {
  markdown('Markdown', Icons.text_fields, MonokaiTheme.cyan),
  code('Python', Icons.code, MonokaiTheme.purple),
  sql('SQL', Icons.storage, MonokaiTheme.yellow),
  mermaid('Mermaid', Icons.account_tree, MonokaiTheme.green),
  model('Model', Icons.smart_toy, MonokaiTheme.orange);

  final String label;
  final IconData icon;
  final Color color;
  const CellType(this.label, this.icon, this.color);
  
  String get defaultContent {
    switch (this) {
      case CellType.markdown:
        return '# New Section\n\nStart typing...';
      case CellType.code:
        return '# Python code\nimport pandas as pd\n\n';
      case CellType.sql:
        return 'SELECT * FROM table\nWHERE condition;';
      case CellType.mermaid:
        return 'graph TD\n    A[Start] --> B[Process]\n    B --> C[End]';
      case CellType.model:
        return '';
    }
  }
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
  
  // Debounce timer for auto-save
  DateTime? _lastChange;
  bool _pendingSave = false;
  
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
    debugPrint('_NotesView: loadNotebookCells returned: ${json?.substring(0, (json.length > 100 ? 100 : json.length))}...');
    
    if (json != null && json.isNotEmpty) {
      try {
        final list = jsonDecode(json) as List<dynamic>;
        debugPrint('_NotesView: Found ${list.length} cells');
        // Find first markdown cell
        for (final c in list) {
          final map = c as Map<String, dynamic>;
          if (map['cell_type'] == 'markdown') {
            _cellId = map['id'] as String?;
            _content = map['content'] as String? ?? '';
            debugPrint('_NotesView: Loaded content length: ${_content.length}');
            break;
          }
        }
      } catch (e) {
        debugPrint('Error loading notes: $e');
      }
    }
    
    // Create default cell if none exists
    if (_content.isEmpty && _cellId == null) {
      _content = _defaultContent;
      _cellId = DateTime.now().millisecondsSinceEpoch.toString();
      debugPrint('_NotesView: Creating default cell with id $_cellId');
      _saveContent();
    }
    
    setState(() => _loading = false);
  }
  
  void _saveContent() {
    if (_cellId == null) return;
    debugPrint('_NotesView: Saving content length ${_content.length} for cell $_cellId');
    final result = CyanFFI.saveNotebookCell(widget.boardId, {
      'id': _cellId,
      'cell_type': 'markdown',
      'content': _content,
    });
    debugPrint('_NotesView: Save result: $result');
    _pendingSave = false;
  }
  
  void _onContentChanged(String text) {
    _content = text;
    _lastChange = DateTime.now();
    _pendingSave = true;
    
    // Auto-save after 500ms of no changes
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_pendingSave && mounted) {
        final now = DateTime.now();
        if (_lastChange != null && now.difference(_lastChange!).inMilliseconds >= 450) {
          _saveContent();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return VSCodeNotesEditor(
      initialContent: _content,
      onChanged: _onContentChanged,
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
