// widgets/board_card.dart
// Enhanced board card with face-aware previews, labels, ratings - matches Swift's BoardCardEnhanced
// Shows Canvas/Notebook/Notes preview based on board's active face

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/tree_item.dart';
import '../services/board_preview_loader.dart';
import '../ffi/component_bridge.dart';
import '../ffi/ffi_helpers.dart' show CyanFFI;

// ============================================================================
// PREDEFINED LABELS
// ============================================================================

class PredefinedLabels {
  static const List<String> all = [
    'urgent', 'review', 'draft', 'approved', 'blocked',
    'in-progress', 'research', 'design', 'development', 'testing',
  ];

  static Color colorFor(String label) => switch (label.toLowerCase()) {
    'urgent' => const Color(0xFFF92672),
    'review' => const Color(0xFF66D9EF),
    'draft' => const Color(0xFF75715E),
    'approved' => const Color(0xFFA6E22E),
    'blocked' => const Color(0xFFF92672),
    'in-progress' => const Color(0xFFFD971F),
    'research' => const Color(0xFFAE81FF),
    'design' => const Color(0xFFE91E63),
    'development' => const Color(0xFF66D9EF),
    'testing' => const Color(0xFFA6E22E),
    _ => const Color(0xFF757575),
  };
}

// ============================================================================
// ENHANCED BOARD CARD
// ============================================================================

class EnhancedBoardCard extends StatefulWidget {
  final TreeBoard board;
  final String groupName;
  final String workspaceName;
  final VoidCallback onTap;
  final VoidCallback? onChat;
  final VoidCallback? onDelete;
  final bool showContext;
  // Use BoardGridItem data if available
  final BoardGridItem? gridItem;

  const EnhancedBoardCard({
    super.key,
    required this.board,
    required this.groupName,
    required this.workspaceName,
    required this.onTap,
    this.onChat,
    this.onDelete,
    this.showContext = false,
    this.gridItem,
  });

  @override
  State<EnhancedBoardCard> createState() => _EnhancedBoardCardState();
}

class _EnhancedBoardCardState extends State<EnhancedBoardCard> {
  bool _hovered = false;
  bool _pressed = false;
  BoardPreviewData? _previewData;
  
  // Use gridItem data or board data
  List<String> get _labels => widget.gridItem?.labels ?? [];
  bool get _isPinned => widget.gridItem?.isPinned ?? false;
  int get _rating => widget.gridItem?.rating ?? 0;
  
  BoardFace get _activeFace => _previewData?.activeFace ?? BoardFace.canvas;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }
  
  @override
  void didUpdateWidget(EnhancedBoardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.board.id != widget.board.id) {
      _loadPreview();
    }
  }
  
  void _loadPreview() {
    // Load preview asynchronously
    Future.microtask(() {
      if (!mounted) return;
      final data = BoardPreviewLoader.instance.loadPreview(widget.board.id);
      if (mounted) {
        setState(() => _previewData = data);
      }
    });
  }

  double get _cardHeight {
    final hash = widget.board.id.hashCode.abs();
    const heights = [140.0, 160.0, 180.0, 200.0, 220.0];
    return heights[hash % heights.length];
  }

  IconData get _faceIcon => switch (_activeFace) {
    BoardFace.canvas => Icons.brush,
    BoardFace.notebook => Icons.book,
    BoardFace.notes => Icons.article,
  };

  Color get _faceColor => switch (_activeFace) {
    BoardFace.canvas => const Color(0xFFFD971F),
    BoardFace.notebook => const Color(0xFF66D9EF),
    BoardFace.notes => const Color(0xFFA6E22E),
  };
  
  List<Color> get _gradientColors => switch (_activeFace) {
    BoardFace.notebook => [const Color(0xFF2D2D2D), const Color(0xFF1E1E1E).withOpacity(0.8)],
    BoardFace.notes => [const Color(0xFF2A2D2E), const Color(0xFF1E1E1E).withOpacity(0.9)],
    BoardFace.canvas => [const Color(0xFF272822).withOpacity(0.8), const Color(0xFF1E1E1E).withOpacity(0.6)],
  };

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
        onTapCancel: () => setState(() => _pressed = false),
        onSecondaryTapUp: (d) => _showContextMenu(context, d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.identity()..scale(_pressed ? 0.97 : (_hovered ? 1.02 : 1.0)),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF252525),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered ? const Color(0xFF66D9EF).withOpacity(0.6) : const Color(0xFF3E3D32).withOpacity(0.15),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: _cardHeight, child: _buildPreviewArea()),
              _buildInfoFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // PREVIEW AREA
  // ============================================================================

  Widget _buildPreviewArea() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
      child: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          
          // Face-specific preview content
          _buildFacePreview(),
          
          // Face type badge (top-left)
          Positioned(
            top: 8,
            left: 8,
            child: _buildFaceBadge(),
          ),
          
          // Pin indicator (top-right)
          if (_isPinned)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFD971F).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.push_pin, size: 12, color: Color(0xFFFD971F)),
              ),
            ),
          
          // Hover overlay
          if (_hovered)
            Container(
              color: Colors.black.withOpacity(0.25),
              child: const Center(
                child: Icon(Icons.open_in_new, size: 32, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildFaceBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E).withOpacity(0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_faceIcon, size: 10, color: _faceColor),
          const SizedBox(width: 4),
          Text(
            _activeFace.name[0].toUpperCase() + _activeFace.name.substring(1),
            style: TextStyle(fontSize: 9, color: _faceColor, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // FACE-SPECIFIC PREVIEWS
  // ============================================================================

  Widget _buildFacePreview() {
    switch (_activeFace) {
      case BoardFace.canvas:
        return _buildCanvasPreview();
      case BoardFace.notebook:
        return _buildNotebookPreview();
      case BoardFace.notes:
        return _buildNotesPreview();
    }
  }

  Widget _buildCanvasPreview() {
    final elements = _previewData?.canvasElements ?? [];
    
    if (elements.isEmpty) {
      return _buildEmptyCanvasPreview();
    }
    
    // Render mini canvas preview
    return Padding(
      padding: const EdgeInsets.all(8),
      child: CustomPaint(
        painter: _CanvasPreviewPainter(elements),
        size: Size.infinite,
      ),
    );
  }
  
  Widget _buildEmptyCanvasPreview() {
    return Stack(
      children: [
        // Dot grid pattern
        CustomPaint(
          painter: _DotGridPainter(),
          size: Size.infinite,
        ),
        // Empty state
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.gesture, size: 32, color: const Color(0xFF75715E).withOpacity(0.4)),
              const SizedBox(height: 8),
              Text(
                'Empty Canvas',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                  color: const Color(0xFF75715E).withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotebookPreview() {
    final cells = _previewData?.notebookCells ?? [];
    
    if (cells.isEmpty) {
      return _buildEmptyNotebookPreview();
    }
    
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Show first 3 cells as mini previews
          ...cells.take(3).map((cell) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _NotebookCellMiniPreview(cell: cell),
          )),
          
          const Spacer(),
          
          // Cell count footer
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E).withOpacity(0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.view_agenda_outlined, size: 9, color: Color(0xFF75715E)),
                  const SizedBox(width: 4),
                  Text(
                    '${cells.length} cell${cells.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'monospace',
                      color: Color(0xFF75715E),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyNotebookPreview() {
    return Column(
      children: [
        const SizedBox(height: 16),
        // Notebook lines illustration
        ...List.generate(4, (i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF3E3D32).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3E3D32).withOpacity((4 - i) * 0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        )),
        const Spacer(),
        Text(
          'Empty Notebook',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            fontFamily: 'monospace',
            color: const Color(0xFF75715E).withOpacity(0.5),
          ),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildNotesPreview() {
    final content = _previewData?.notesContent;
    
    if (content == null || content.isEmpty) {
      return _buildEmptyNotesPreview();
    }
    
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        content,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          color: const Color(0xFFF8F8F2).withOpacity(0.7),
          height: 1.4,
        ),
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
  
  Widget _buildEmptyNotesPreview() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.article_outlined, size: 28, color: const Color(0xFF75715E).withOpacity(0.4)),
          const SizedBox(height: 8),
          Text(
            'Empty Note',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
              color: const Color(0xFF75715E).withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // INFO FOOTER
  // ============================================================================

  Widget _buildInfoFooter() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
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
          
          // Labels
          if (_labels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: _labels.take(3).map((l) => _LabelChip(label: l)).toList(),
            ),
          ],
          
          const SizedBox(height: 8),
          
          // Bottom row: rating + context/date
          Row(
            children: [
              if (_rating > 0) ...[
                _StarRating(rating: _rating, size: 10),
                const SizedBox(width: 8),
              ],
              if (widget.showContext)
                Expanded(
                  child: Text(
                    '${widget.groupName} / ${widget.workspaceName}',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF808080)),
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else if (widget.board.lastModified != null)
                Text(
                  _formatDate(widget.board.lastModified!),
                  style: const TextStyle(fontSize: 10, color: Color(0xFF808080)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // CONTEXT MENU
  // ============================================================================

  void _showContextMenu(BuildContext context, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: const Color(0xFF252525),
      items: [
        _menuItem('open', Icons.open_in_new, 'Open'),
        _menuItem('chat', Icons.chat_bubble_outline, 'Chat'),
        const PopupMenuDivider(),
        _menuItem('pin', _isPinned ? Icons.push_pin : Icons.push_pin_outlined, _isPinned ? 'Unpin' : 'Pin'),
        _menuItem('labels', Icons.label_outline, 'Labels'),
        _menuItem('rate', Icons.star_outline, 'Rate'),
        const PopupMenuDivider(),
        // Switch face menu
        PopupMenuItem(
          value: 'face_canvas',
          child: Row(children: [
            Icon(Icons.brush, size: 16, color: _activeFace == BoardFace.canvas ? const Color(0xFFFD971F) : const Color(0xFFF8F8F2)),
            const SizedBox(width: 12),
            Text('Canvas', style: TextStyle(color: _activeFace == BoardFace.canvas ? const Color(0xFFFD971F) : const Color(0xFFF8F8F2), fontSize: 13)),
          ]),
        ),
        PopupMenuItem(
          value: 'face_notebook',
          child: Row(children: [
            Icon(Icons.book, size: 16, color: _activeFace == BoardFace.notebook ? const Color(0xFF66D9EF) : const Color(0xFFF8F8F2)),
            const SizedBox(width: 12),
            Text('Notebook', style: TextStyle(color: _activeFace == BoardFace.notebook ? const Color(0xFF66D9EF) : const Color(0xFFF8F8F2), fontSize: 13)),
          ]),
        ),
        PopupMenuItem(
          value: 'face_notes',
          child: Row(children: [
            Icon(Icons.article, size: 16, color: _activeFace == BoardFace.notes ? const Color(0xFFA6E22E) : const Color(0xFFF8F8F2)),
            const SizedBox(width: 12),
            Text('Notes', style: TextStyle(color: _activeFace == BoardFace.notes ? const Color(0xFFA6E22E) : const Color(0xFFF8F8F2), fontSize: 13)),
          ]),
        ),
        const PopupMenuDivider(),
        _menuItem('copy_link', Icons.link, 'Copy Link'),
        const PopupMenuDivider(),
        _menuItem('delete', Icons.delete_outline, 'Delete', isDestructive: true),
      ],
    ).then((v) => _handleMenuAction(v));
  }

  PopupMenuItem<String> _menuItem(String v, IconData i, String l, {bool isDestructive = false}) {
    final c = isDestructive ? const Color(0xFFF92672) : const Color(0xFFF8F8F2);
    return PopupMenuItem(value: v, child: Row(children: [Icon(i, size: 16, color: c), const SizedBox(width: 12), Text(l, style: TextStyle(color: c, fontSize: 13))]));
  }

  void _handleMenuAction(String? action) {
    if (action == null) return;
    
    switch (action) {
      case 'open':
        widget.onTap();
      case 'chat':
        widget.onChat?.call();
      case 'pin':
        // TODO: Toggle pin via provider
        break;
      case 'labels':
        _showLabelEditor();
      case 'rate':
        _showRatingDialog();
      case 'face_canvas':
        _switchFace(BoardFace.canvas);
      case 'face_notebook':
        _switchFace(BoardFace.notebook);
      case 'face_notes':
        _switchFace(BoardFace.notes);
      case 'copy_link':
        Clipboard.setData(ClipboardData(text: 'cyan://board/${widget.board.id}'));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied!')));
      case 'delete':
        widget.onDelete?.call();
    }
  }
  
  void _switchFace(BoardFace face) {
    CyanFFI.setBoardMode(widget.board.id, face.name);
    BoardPreviewLoader.instance.invalidate(widget.board.id);
    _loadPreview();
  }

  void _showLabelEditor() {
    showDialog(
      context: context,
      builder: (ctx) => _LabelEditorDialog(
        boardId: widget.board.id,
        currentLabels: _labels,
        onSave: (labels) {
          // TODO: Save labels via provider
        },
      ),
    );
  }

  void _showRatingDialog() {
    int tempRating = _rating;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252525),
        title: const Text('Rate Board', style: TextStyle(color: Color(0xFFF8F8F2))),
        content: StatefulBuilder(
          builder: (ctx, ss) => _StarRating(
            rating: tempRating,
            size: 32,
            interactive: true,
            onRate: (r) {
              ss(() => tempRating = r);
              // TODO: Save rating via provider
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
      ),
    );
  }

  String _formatDate(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.month}/${d.day}';
  }
}

// ============================================================================
// CANVAS PREVIEW PAINTER
// ============================================================================

class _CanvasPreviewPainter extends CustomPainter {
  final List<WhiteboardElementPreview> elements;
  
  _CanvasPreviewPainter(this.elements);
  
  @override
  void paint(Canvas canvas, Size size) {
    if (elements.isEmpty) return;
    
    // Calculate bounds
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    
    for (final e in elements) {
      minX = minX < e.x ? minX : e.x;
      minY = minY < e.y ? minY : e.y;
      maxX = maxX > (e.x + e.width) ? maxX : (e.x + e.width);
      maxY = maxY > (e.y + e.height) ? maxY : (e.y + e.height);
    }
    
    final contentWidth = maxX - minX;
    final contentHeight = maxY - minY;
    if (contentWidth <= 0 || contentHeight <= 0) return;
    
    // Scale to fit
    final scale = (size.width / contentWidth).clamp(0.0, size.height / contentHeight) * 0.9;
    final offsetX = (size.width - contentWidth * scale) / 2 - minX * scale;
    final offsetY = (size.height - contentHeight * scale) / 2 - minY * scale;
    
    for (final e in elements) {
      final rect = Rect.fromLTWH(
        e.x * scale + offsetX,
        e.y * scale + offsetY,
        e.width * scale,
        e.height * scale,
      );
      
      final paint = Paint()
        ..color = Color(e.color ?? 0xFF66D9EF).withOpacity(0.7)
        ..style = PaintingStyle.fill;
      
      switch (e.elementType) {
        case 'rect':
        case 'shape':
          canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);
        case 'ellipse':
          canvas.drawOval(rect, paint);
        case 'text':
        case 'sticky':
          paint.color = const Color(0xFFE6DB74).withOpacity(0.8);
          canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
        case 'path':
        case 'pen':
          if (e.points != null && e.points!.length >= 2) {
            final path = Path();
            path.moveTo(e.points![0]['x']! * scale + offsetX, e.points![0]['y']! * scale + offsetY);
            for (int i = 1; i < e.points!.length; i++) {
              path.lineTo(e.points![i]['x']! * scale + offsetX, e.points![i]['y']! * scale + offsetY);
            }
            paint.style = PaintingStyle.stroke;
            paint.strokeWidth = 2;
            canvas.drawPath(path, paint);
          }
        default:
          canvas.drawRect(rect, paint);
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant _CanvasPreviewPainter oldDelegate) {
    return elements != oldDelegate.elements;
  }
}

// ============================================================================
// DOT GRID PAINTER
// ============================================================================

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 20.0;
    const dotSize = 2.0;
    final paint = Paint()..color = const Color(0xFF3E3D32).withOpacity(0.4);
    
    for (double x = spacing; x < size.width; x += spacing) {
      for (double y = spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), dotSize / 2, paint);
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================================
// NOTEBOOK CELL MINI PREVIEW
// ============================================================================

class _NotebookCellMiniPreview extends StatelessWidget {
  final NotebookCellPreview cell;
  
  const _NotebookCellMiniPreview({required this.cell});
  
  IconData get _icon => switch (cell.cellType) {
    'markdown' => Icons.text_fields,
    'mermaid' => Icons.account_tree,
    'canvas' => Icons.gesture,
    'image' => Icons.image,
    'code' => Icons.code,
    _ => Icons.square,
  };
  
  Color get _color => switch (cell.cellType) {
    'markdown' => const Color(0xFF66D9EF),
    'mermaid' => const Color(0xFFA6E22E),
    'canvas' => const Color(0xFFFD971F),
    'image' => const Color(0xFFF92672),
    'code' => const Color(0xFFAE81FF),
    _ => const Color(0xFF75715E),
  };
  
  String get _typeName => switch (cell.cellType) {
    'markdown' => 'Markdown',
    'mermaid' => 'Diagram',
    'canvas' => 'Drawing',
    'image' => 'Image',
    'code' => 'Code',
    _ => cell.cellType,
  };
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E).withOpacity(0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: _color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(_icon, size: 9, color: _color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              cell.contentPreview ?? _typeName,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: cell.contentPreview != null ? const Color(0xFFA6A6A6) : const Color(0xFF75715E),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// LABEL CHIP
// ============================================================================

class _LabelChip extends StatelessWidget {
  final String label;
  final VoidCallback? onRemove;
  
  const _LabelChip({required this.label, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: PredefinedLabels.colorFor(label).withOpacity(0.85),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close, size: 10, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// STAR RATING
// ============================================================================

class _StarRating extends StatelessWidget {
  final int rating;
  final double size;
  final bool interactive;
  final ValueChanged<int>? onRate;
  
  const _StarRating({
    required this.rating,
    this.size = 14,
    this.interactive = false,
    this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating;
        return GestureDetector(
          onTap: interactive ? () => onRate?.call(i + 1 == rating ? 0 : i + 1) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Icon(
              filled ? Icons.star : Icons.star_border,
              size: size,
              color: filled ? const Color(0xFFE6DB74) : const Color(0xFF808080).withOpacity(0.4),
            ),
          ),
        );
      }),
    );
  }
}

// ============================================================================
// LABEL EDITOR DIALOG
// ============================================================================

class _LabelEditorDialog extends StatefulWidget {
  final String boardId;
  final List<String> currentLabels;
  final ValueChanged<List<String>> onSave;
  
  const _LabelEditorDialog({
    required this.boardId,
    required this.currentLabels,
    required this.onSave,
  });

  @override
  State<_LabelEditorDialog> createState() => _LabelEditorDialogState();
}

class _LabelEditorDialogState extends State<_LabelEditorDialog> {
  late List<String> _labels;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _labels = List.from(widget.currentLabels);
  }
  
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF252525),
      title: const Text('Edit Labels', style: TextStyle(color: Color(0xFFF8F8F2))),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_labels.isNotEmpty) ...[
              const Text('Current', style: TextStyle(fontSize: 12, color: Color(0xFF808080))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _labels.map((l) => _LabelChip(
                  label: l,
                  onRemove: () => setState(() => _labels.remove(l)),
                )).toList(),
              ),
              const SizedBox(height: 16),
            ],
            const Text('Add', style: TextStyle(fontSize: 12, color: Color(0xFF808080))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: PredefinedLabels.all
                  .where((l) => !_labels.contains(l))
                  .map((l) => GestureDetector(
                    onTap: () => setState(() => _labels.add(l)),
                    child: _LabelChip(label: l),
                  ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    style: const TextStyle(color: Color(0xFFF8F8F2), fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Custom...',
                      hintStyle: TextStyle(color: Color(0xFF808080)),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      filled: true,
                      fillColor: Color(0xFF1E1E1E),
                      border: OutlineInputBorder(borderSide: BorderSide.none),
                    ),
                    onSubmitted: _addCustom,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _addCustom(_ctrl.text),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF66D9EF)),
                  child: const Text('Add'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF808080))),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSave(_labels);
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA6E22E)),
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _addCustom(String v) {
    final t = v.trim().toLowerCase();
    if (t.isNotEmpty && !_labels.contains(t)) {
      setState(() {
        _labels.add(t);
        _ctrl.clear();
      });
    }
  }
}
