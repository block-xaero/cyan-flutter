// widgets/file_drop_target.dart
// Reusable file drop target
// For real OS file drops, add: desktop_drop: ^0.4.4 to pubspec.yaml

import 'package:flutter/material.dart';

class FileDropTarget extends StatefulWidget {
  final Widget child;
  final void Function(List<DroppedFile> files)? onDrop;
  final VoidCallback? onDragEnter;
  final VoidCallback? onDragExit;
  final Widget Function(BuildContext, bool isDragging, Widget child)? builder;

  const FileDropTarget({super.key, required this.child, this.onDrop, this.onDragEnter, this.onDragExit, this.builder});

  @override
  State<FileDropTarget> createState() => _FileDropTargetState();
}

class _FileDropTargetState extends State<FileDropTarget> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final child = widget.builder != null
        ? widget.builder!(context, _isDragging, widget.child)
        : Stack(children: [widget.child, if (_isDragging) _DefaultDropOverlay()]);

    return DragTarget<Object>(
      onWillAcceptWithDetails: (_) { _onEnter(); return true; },
      onLeave: (_) => _onExit(),
      onAcceptWithDetails: (details) {
        _onExit();
        final files = <DroppedFile>[];
        if (details.data is String) {
          files.add(DroppedFile(path: details.data as String, name: (details.data as String).split('/').last));
        } else {
          files.add(DroppedFile(path: '/tmp/file_${DateTime.now().millisecondsSinceEpoch}', name: 'dropped_file.txt'));
        }
        widget.onDrop?.call(files);
      },
      builder: (context, candidateData, rejectedData) => child,
    );
  }

  void _onEnter() { if (!_isDragging) { setState(() => _isDragging = true); widget.onDragEnter?.call(); } }
  void _onExit() { if (_isDragging) { setState(() => _isDragging = false); widget.onDragExit?.call(); } }
}

class DroppedFile {
  final String path;
  final String name;
  final String? mimeType;
  final int? size;

  DroppedFile({required this.path, required this.name, this.mimeType, this.size});

  String get extension => name.contains('.') ? name.split('.').last.toLowerCase() : '';
  bool get isImage => ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'].contains(extension);
  bool get isPdf => extension == 'pdf';
  bool get isCode => ['dart', 'py', 'js', 'ts', 'rs', 'go', 'java', 'swift'].contains(extension);

  IconData get icon {
    if (isImage) return Icons.image;
    if (isPdf) return Icons.picture_as_pdf;
    if (isCode) return Icons.code;
    return Icons.insert_drive_file;
  }

  Color get iconColor {
    if (isImage) return const Color(0xFFF92672);
    if (isPdf) return const Color(0xFFE74C3C);
    if (isCode) return const Color(0xFFA6E22E);
    return const Color(0xFF808080);
  }
}

class _DefaultDropOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: const Color(0xFF66D9EF).withOpacity(0.1),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF252525),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF66D9EF), width: 2),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_upload_outlined, size: 48, color: Color(0xFF66D9EF)),
                SizedBox(height: 16),
                Text('Drop files here', style: TextStyle(color: Color(0xFFF8F8F2), fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DraggableFileChip extends StatelessWidget {
  final String fileName;
  final String filePath;
  final VoidCallback? onTap;

  const DraggableFileChip({super.key, required this.fileName, required this.filePath, this.onTap});

  @override
  Widget build(BuildContext context) {
    final file = DroppedFile(path: filePath, name: fileName);
    return Draggable<String>(
      data: filePath,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFF252525), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF66D9EF))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(file.icon, size: 16, color: file.iconColor),
            const SizedBox(width: 8),
            Text(fileName, style: const TextStyle(color: Color(0xFFF8F8F2), fontSize: 12, decoration: TextDecoration.none)),
          ]),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: _chip(file)),
      child: GestureDetector(onTap: onTap, child: _chip(file)),
    );
  }

  Widget _chip(DroppedFile f) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: const Color(0xFF3E3D32), borderRadius: BorderRadius.circular(6)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(f.icon, size: 14, color: f.iconColor),
      const SizedBox(width: 6),
      Text(fileName, style: const TextStyle(color: Color(0xFFF8F8F2), fontSize: 12)),
    ]),
  );
}
