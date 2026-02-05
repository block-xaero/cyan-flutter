// services/board_preview_loader.dart
// Face-aware preview loader for board cards - matches Swift's BoardPreviewLoader
// Loads canvas elements, notebook cells, or notes content based on active face

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../ffi/ffi_helpers.dart';

// ============================================================================
// BOARD FACE ENUM
// ============================================================================

enum BoardFace { canvas, notebook, notes }

extension BoardFaceExtension on BoardFace {
  String get name => switch (this) {
    BoardFace.canvas => 'canvas',
    BoardFace.notebook => 'notebook',
    BoardFace.notes => 'notes',
  };
  
  static BoardFace fromString(String? s) => switch (s?.toLowerCase()) {
    'notebook' => BoardFace.notebook,
    'notes' => BoardFace.notes,
    _ => BoardFace.canvas,
  };
}

// ============================================================================
// NOTEBOOK CELL PREVIEW
// ============================================================================

class NotebookCellPreview {
  final String id;
  final String cellType;
  final String? contentPreview;
  final int order;
  
  NotebookCellPreview({
    required this.id,
    required this.cellType,
    this.contentPreview,
    required this.order,
  });
  
  factory NotebookCellPreview.fromJson(Map<String, dynamic> json, int index) {
    final content = json['content'] as String?;
    String? preview;
    
    if (content != null && content.isNotEmpty) {
      // Extract first line, strip markdown headers
      final firstLine = content.split('\n').first.trim();
      final cleaned = firstLine.replaceAll(RegExp(r'^#+\s*'), '');
      preview = cleaned.isEmpty ? null : (cleaned.length > 50 ? '${cleaned.substring(0, 50)}...' : cleaned);
    }
    
    return NotebookCellPreview(
      id: json['id'] as String? ?? '',
      cellType: json['cell_type'] as String? ?? 'markdown',
      contentPreview: preview,
      order: index,
    );
  }
}

// ============================================================================
// WHITEBOARD ELEMENT (minimal for preview)
// ============================================================================

class WhiteboardElementPreview {
  final String id;
  final String elementType;
  final double x, y, width, height;
  final String? content;
  final int? color;
  final List<Map<String, double>>? points;
  
  WhiteboardElementPreview({
    required this.id,
    required this.elementType,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.content,
    this.color,
    this.points,
  });
  
  factory WhiteboardElementPreview.fromJson(Map<String, dynamic> json) {
    List<Map<String, double>>? points;
    if (json['points'] != null) {
      points = (json['points'] as List).map((p) => {
        'x': (p['x'] as num?)?.toDouble() ?? 0,
        'y': (p['y'] as num?)?.toDouble() ?? 0,
      }).toList();
    }
    
    return WhiteboardElementPreview(
      id: json['id'] as String? ?? '',
      elementType: json['element_type'] as String? ?? json['type'] as String? ?? 'shape',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 100,
      height: (json['height'] as num?)?.toDouble() ?? 100,
      content: json['content'] as String?,
      color: json['color'] as int?,
      points: points,
    );
  }
}

// ============================================================================
// BOARD PREVIEW DATA
// ============================================================================

class BoardPreviewData {
  final String boardId;
  final BoardFace activeFace;
  final List<WhiteboardElementPreview> canvasElements;
  final List<NotebookCellPreview> notebookCells;
  final String? notesContent;
  
  BoardPreviewData({
    required this.boardId,
    required this.activeFace,
    this.canvasElements = const [],
    this.notebookCells = const [],
    this.notesContent,
  });
  
  bool get isEmpty => switch (activeFace) {
    BoardFace.canvas => canvasElements.isEmpty,
    BoardFace.notebook => notebookCells.isEmpty,
    BoardFace.notes => notesContent?.isEmpty ?? true,
  };
}

// ============================================================================
// BOARD PREVIEW LOADER
// ============================================================================

class BoardPreviewLoader extends ChangeNotifier {
  static final BoardPreviewLoader instance = BoardPreviewLoader._();
  BoardPreviewLoader._();
  
  final Map<String, BoardPreviewData> _cache = {};
  
  /// Load preview for a board (face-aware)
  BoardPreviewData loadPreview(String boardId) {
    // Check cache
    if (_cache.containsKey(boardId)) {
      return _cache[boardId]!;
    }
    
    // Get active face
    final face = _getActiveFace(boardId);
    
    // Load content based on face
    BoardPreviewData data;
    switch (face) {
      case BoardFace.canvas:
        final elements = _loadCanvasElements(boardId);
        data = BoardPreviewData(
          boardId: boardId,
          activeFace: face,
          canvasElements: elements,
        );
        
      case BoardFace.notebook:
        final cells = _loadNotebookCells(boardId);
        data = BoardPreviewData(
          boardId: boardId,
          activeFace: face,
          notebookCells: cells,
        );
        
      case BoardFace.notes:
        final cells = _loadNotebookCells(boardId);
        String? notesContent;
        // Get full content from first markdown cell
        final markdownCell = cells.where((c) => c.cellType == 'markdown').firstOrNull;
        if (markdownCell != null) {
          notesContent = _loadFullCellContent(boardId, markdownCell.id);
        }
        data = BoardPreviewData(
          boardId: boardId,
          activeFace: face,
          notebookCells: cells,
          notesContent: notesContent,
        );
    }
    
    // Cache it
    _cache[boardId] = data;
    return data;
  }
  
  /// Invalidate cache for a board
  void invalidate(String boardId) {
    _cache.remove(boardId);
    notifyListeners();
  }
  
  /// Clear all cached previews
  void clearCache() {
    _cache.clear();
    notifyListeners();
  }
  
  // MARK: - Private Loading
  
  BoardFace _getActiveFace(String boardId) {
    final modeStr = CyanFFI.getBoardMode(boardId);
    return BoardFaceExtension.fromString(modeStr);
  }
  
  List<WhiteboardElementPreview> _loadCanvasElements(String boardId) {
    final json = CyanFFI.loadWhiteboardElements(boardId);
    if (json == null || json.isEmpty) return [];
    
    try {
      final list = jsonDecode(json) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map((e) => WhiteboardElementPreview.fromJson(e))
          .toList();
    } catch (e) {
      debugPrint('BoardPreviewLoader: Error parsing canvas elements: $e');
      return [];
    }
  }
  
  List<NotebookCellPreview> _loadNotebookCells(String boardId) {
    final json = CyanFFI.loadNotebookCells(boardId);
    if (json == null || json.isEmpty) return [];
    
    try {
      final list = jsonDecode(json) as List;
      final cells = <NotebookCellPreview>[];
      for (int i = 0; i < list.length; i++) {
        if (list[i] is Map<String, dynamic>) {
          cells.add(NotebookCellPreview.fromJson(list[i], i));
        }
      }
      cells.sort((a, b) => a.order.compareTo(b.order));
      return cells;
    } catch (e) {
      debugPrint('BoardPreviewLoader: Error parsing notebook cells: $e');
      return [];
    }
  }
  
  String? _loadFullCellContent(String boardId, String cellId) {
    final json = CyanFFI.loadNotebookCells(boardId);
    if (json == null) return null;
    
    try {
      final list = jsonDecode(json) as List;
      for (final item in list) {
        if (item is Map<String, dynamic> && item['id'] == cellId) {
          final content = item['content'] as String?;
          if (content != null && content.isNotEmpty) {
            // Strip markdown headers, limit to 500 chars
            final cleaned = content
                .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
                .trim();
            return cleaned.length > 500 ? cleaned.substring(0, 500) : cleaned;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
