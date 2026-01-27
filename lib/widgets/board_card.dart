// widgets/board_card.dart
// Enhanced board card with labels, pins, ratings

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/tree_item.dart';

class PredefinedLabels {
  static const List<String> all = ['design', 'api', 'ml', 'data', 'planning', 'research', 'notes', 'demo', 'wip', 'archived'];

  static Color colorFor(String label) {
    switch (label.toLowerCase()) {
      case 'design': return const Color(0xFFE91E63);
      case 'api': return const Color(0xFF2196F3);
      case 'ml': return const Color(0xFF9C27B0);
      case 'data': return const Color(0xFFFF9800);
      case 'planning': return const Color(0xFF4CAF50);
      case 'research': return const Color(0xFF00BCD4);
      case 'notes': return const Color(0xFFFFEB3B);
      case 'demo': return const Color(0xFF00E676);
      case 'wip': return const Color(0xFFF44336);
      case 'archived': return const Color(0xFF9E9E9E);
      default: return const Color(0xFF757575);
    }
  }
}

class BoardMetadata {
  List<String> labels;
  int rating;
  bool isPinned;
  int viewCount;

  BoardMetadata({this.labels = const [], this.rating = 0, this.isPinned = false, this.viewCount = 0});
}

class EnhancedBoardCard extends StatefulWidget {
  final TreeBoard board;
  final String groupName;
  final String workspaceName;
  final VoidCallback onTap;
  final VoidCallback? onChat;
  final VoidCallback? onDelete;
  final bool showContext;

  const EnhancedBoardCard({
    super.key,
    required this.board,
    required this.groupName,
    required this.workspaceName,
    required this.onTap,
    this.onChat,
    this.onDelete,
    this.showContext = false,
  });

  @override
  State<EnhancedBoardCard> createState() => _EnhancedBoardCardState();
}

class _EnhancedBoardCardState extends State<EnhancedBoardCard> {
  bool _hovered = false;
  bool _pressed = false;
  late BoardMetadata _metadata;

  @override
  void initState() {
    super.initState();
    final hash = widget.board.name.hashCode;
    _metadata = BoardMetadata(
      labels: hash % 3 == 0 ? ['design', 'wip'] : (hash % 3 == 1 ? ['api'] : []),
      rating: hash % 6,
      isPinned: hash % 5 == 0,
    );
  }

  IconData get _faceIcon => switch (widget.board.boardType) {
    'canvas' => Icons.brush,
    'notebook' => Icons.book,
    'notes' => Icons.article,
    _ => Icons.dashboard,
  };

  Color get _faceColor => switch (widget.board.boardType) {
    'canvas' => const Color(0xFFFD971F),
    'notebook' => const Color(0xFF66D9EF),
    'notes' => const Color(0xFFA6E22E),
    _ => const Color(0xFF808080),
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
          decoration: BoxDecoration(
            color: const Color(0xFF252525),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _hovered ? const Color(0xFF66D9EF).withOpacity(0.6) : const Color(0xFF3E3D32), width: _hovered ? 2 : 1),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(_hovered ? 0.35 : 0.2), blurRadius: _hovered ? 16 : 8, offset: Offset(0, _hovered ? 8 : 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildPreview()),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [const Color(0xFF2D2D2D), const Color(0xFF1E1E1E).withOpacity(0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
          ),
          child: Center(child: Icon(_faceIcon, size: 40, color: _faceColor.withOpacity(0.3))),
        ),
        Positioned(top: 8, left: 8, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: const Color(0xFF1E1E1E).withOpacity(0.8), borderRadius: BorderRadius.circular(4)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_faceIcon, size: 10, color: _faceColor),
            const SizedBox(width: 4),
            Text(widget.board.boardType.isEmpty ? 'Canvas' : widget.board.boardType[0].toUpperCase() + widget.board.boardType.substring(1), style: TextStyle(fontSize: 9, color: _faceColor, fontWeight: FontWeight.w500)),
          ]),
        )),
        if (_metadata.isPinned) Positioned(top: 8, right: 8, child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: const Color(0xFFFD971F).withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
          child: const Icon(Icons.push_pin, size: 12, color: Color(0xFFFD971F)),
        )),
        if (_hovered) Container(
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.25), borderRadius: const BorderRadius.vertical(top: Radius.circular(11))),
          child: const Center(child: Icon(Icons.open_in_new, size: 32, color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(widget.board.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFF8F8F2)), overflow: TextOverflow.ellipsis)),
            if (widget.board.hasUnread) Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFA6E22E), shape: BoxShape.circle)),
          ]),
          if (_metadata.labels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 4, runSpacing: 4, children: _metadata.labels.take(3).map((l) => _LabelChip(label: l)).toList()),
          ],
          const SizedBox(height: 8),
          Row(children: [
            if (_metadata.rating > 0) ...[_StarRating(rating: _metadata.rating, size: 10), const SizedBox(width: 8)],
            if (widget.showContext) Expanded(child: Text('${widget.groupName} / ${widget.workspaceName}', style: const TextStyle(fontSize: 10, color: Color(0xFF808080)), overflow: TextOverflow.ellipsis))
            else if (widget.board.lastModified != null) Text(_formatDate(widget.board.lastModified!), style: const TextStyle(fontSize: 10, color: Color(0xFF808080))),
          ]),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: const Color(0xFF252525),
      items: [
        _menuItem('open', Icons.open_in_new, 'Open'),
        _menuItem('chat', Icons.chat_bubble_outline, 'Chat'),
        const PopupMenuDivider(),
        _menuItem('pin', _metadata.isPinned ? Icons.push_pin : Icons.push_pin_outlined, _metadata.isPinned ? 'Unpin' : 'Pin'),
        _menuItem('labels', Icons.label_outline, 'Labels'),
        _menuItem('rate', Icons.star_outline, 'Rate'),
        const PopupMenuDivider(),
        _menuItem('copy_link', Icons.link, 'Copy Link'),
        const PopupMenuDivider(),
        _menuItem('delete', Icons.delete_outline, 'Delete', isDestructive: true),
      ],
    ).then((v) {
      if (v == 'open') widget.onTap();
      else if (v == 'chat') widget.onChat?.call();
      else if (v == 'pin') setState(() => _metadata.isPinned = !_metadata.isPinned);
      else if (v == 'labels') _showLabelEditor();
      else if (v == 'rate') _showRatingDialog();
      else if (v == 'copy_link') { Clipboard.setData(ClipboardData(text: 'cyan://board/${widget.board.id}')); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied!'))); }
      else if (v == 'delete') widget.onDelete?.call();
    });
  }

  PopupMenuItem<String> _menuItem(String v, IconData i, String l, {bool isDestructive = false}) {
    final c = isDestructive ? const Color(0xFFF92672) : const Color(0xFFF8F8F2);
    return PopupMenuItem(value: v, child: Row(children: [Icon(i, size: 16, color: c), const SizedBox(width: 12), Text(l, style: TextStyle(color: c, fontSize: 13))]));
  }

  void _showLabelEditor() {
    showDialog(context: context, builder: (ctx) => _LabelEditorDialog(currentLabels: _metadata.labels, onSave: (l) => setState(() => _metadata.labels = l)));
  }

  void _showRatingDialog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF252525),
      title: const Text('Rate Board', style: TextStyle(color: Color(0xFFF8F8F2))),
      content: StatefulBuilder(builder: (ctx, ss) => _StarRating(rating: _metadata.rating, size: 32, interactive: true, onRate: (r) { ss(() {}); setState(() => _metadata.rating = r); })),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
    ));
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

class _LabelChip extends StatelessWidget {
  final String label;
  final VoidCallback? onRemove;
  const _LabelChip({required this.label, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: PredefinedLabels.colorFor(label).withOpacity(0.85), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white)),
        if (onRemove != null) ...[const SizedBox(width: 4), GestureDetector(onTap: onRemove, child: const Icon(Icons.close, size: 10, color: Colors.white))],
      ]),
    );
  }
}

class _StarRating extends StatelessWidget {
  final int rating;
  final double size;
  final bool interactive;
  final ValueChanged<int>? onRate;
  const _StarRating({required this.rating, this.size = 14, this.interactive = false, this.onRate});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (i) {
      final filled = i < rating;
      return GestureDetector(
        onTap: interactive ? () => onRate?.call(i + 1 == rating ? 0 : i + 1) : null,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: Icon(filled ? Icons.star : Icons.star_border, size: size, color: filled ? const Color(0xFFE6DB74) : const Color(0xFF808080).withOpacity(0.4))),
      );
    }));
  }
}

class _LabelEditorDialog extends StatefulWidget {
  final List<String> currentLabels;
  final ValueChanged<List<String>> onSave;
  const _LabelEditorDialog({required this.currentLabels, required this.onSave});

  @override
  State<_LabelEditorDialog> createState() => _LabelEditorDialogState();
}

class _LabelEditorDialogState extends State<_LabelEditorDialog> {
  late List<String> _labels;
  final _ctrl = TextEditingController();

  @override
  void initState() { super.initState(); _labels = List.from(widget.currentLabels); }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF252525),
      title: const Text('Edit Labels', style: TextStyle(color: Color(0xFFF8F8F2))),
      content: SizedBox(width: 300, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_labels.isNotEmpty) ...[
          const Text('Current', style: TextStyle(fontSize: 12, color: Color(0xFF808080))),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: _labels.map((l) => _LabelChip(label: l, onRemove: () => setState(() => _labels.remove(l)))).toList()),
          const SizedBox(height: 16),
        ],
        const Text('Add', style: TextStyle(fontSize: 12, color: Color(0xFF808080))),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: PredefinedLabels.all.where((l) => !_labels.contains(l)).map((l) => GestureDetector(onTap: () => setState(() => _labels.add(l)), child: _LabelChip(label: l))).toList()),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: TextField(controller: _ctrl, style: const TextStyle(color: Color(0xFFF8F8F2), fontSize: 13), decoration: const InputDecoration(hintText: 'Custom...', hintStyle: TextStyle(color: Color(0xFF808080)), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10), filled: true, fillColor: Color(0xFF1E1E1E), border: OutlineInputBorder(borderSide: BorderSide.none)), onSubmitted: _addCustom)),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: () => _addCustom(_ctrl.text), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF66D9EF)), child: const Text('Add')),
        ]),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Color(0xFF808080)))),
        ElevatedButton(onPressed: () { widget.onSave(_labels); Navigator.pop(context); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA6E22E)), child: const Text('Save')),
      ],
    );
  }

  void _addCustom(String v) {
    final t = v.trim().toLowerCase();
    if (t.isNotEmpty && !_labels.contains(t)) setState(() { _labels.add(t); _ctrl.clear(); });
  }
}
