// widgets/file_drop_zone.dart
// Cross-platform file drag & drop support for macOS/Windows/Linux
// Uses desktop_drop package for native file drops
//
// Usage:
//   1. Add to pubspec.yaml: desktop_drop: ^0.4.4
//   2. Wrap FileTreeWidget rows with FileDropZone
//   3. Wrap ChatPanel input area with FileDropZone

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:path_provider/path_provider.dart';
import '../ffi/ffi_helpers.dart';
import '../theme/monokai_theme.dart';

// ============================================================================
// FILE SCOPE (matches Swift FileScope)
// ============================================================================

enum FileScopeType { group, workspace, board }

class FileScope {
  final FileScopeType type;
  final String id;
  
  const FileScope.group(this.id) : type = FileScopeType.group;
  const FileScope.workspace(this.id) : type = FileScopeType.workspace;
  const FileScope.board(this.id) : type = FileScopeType.board;
  
  String toJson() {
    switch (type) {
      case FileScopeType.group:
        return '{"type":"group","group_id":"$id"}';
      case FileScopeType.workspace:
        return '{"type":"workspace","workspace_id":"$id"}';
      case FileScopeType.board:
        return '{"type":"board","board_id":"$id"}';
    }
  }
}

// ============================================================================
// FILE DROP RESULT
// ============================================================================

class FileDropResult {
  final bool success;
  final String? fileId;
  final String? error;
  
  const FileDropResult({required this.success, this.fileId, this.error});
}

// ============================================================================
// FILE DROP ZONE WIDGET
// ============================================================================

/// Wraps a child widget with drag & drop file support.
/// Shows visual feedback when dragging over and calls onFilesDropped with paths.
class FileDropZone extends StatefulWidget {
  final Widget child;
  final FileScope? scope;
  final void Function(List<String> paths)? onFilesDropped;
  final void Function(List<String> paths)? onFilesAttached; // For chat attachments
  final bool enabled;
  final String dropLabel;
  
  const FileDropZone({
    super.key,
    required this.child,
    this.scope,
    this.onFilesDropped,
    this.onFilesAttached,
    this.enabled = true,
    this.dropLabel = 'Drop files to upload',
  });
  
  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _isDragging = false;
  
  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    
    return DropTarget(
      onDragEntered: (_) {
        setState(() => _isDragging = true);
        debugPrint('📥 Drag entered');
      },
      onDragExited: (_) {
        setState(() => _isDragging = false);
        debugPrint('📤 Drag exited');
      },
      onDragDone: (details) {
        setState(() => _isDragging = false);
        _handleDrop(details.files);
      },
      child: Stack(
        children: [
          widget.child,
          if (_isDragging) _buildDropOverlay(),
        ],
      ),
    );
  }
  
  Widget _buildDropOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: MonokaiTheme.cyan.withOpacity(0.15),
            border: Border.all(color: MonokaiTheme.cyan, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_upload, size: 32, color: MonokaiTheme.cyan),
                const SizedBox(height: 8),
                Text(
                  widget.dropLabel,
                  style: TextStyle(
                    color: MonokaiTheme.cyan,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Future<void> _handleDrop(List<XFile> files) async {
    debugPrint('📦 Dropped ${files.length} files');
    
    final paths = <String>[];
    
    for (final file in files) {
      final path = file.path;
      debugPrint('  📁 ${file.name} -> $path');
      
      // Copy to app's uploads directory (like Swift does)
      final copiedPath = await _copyToUploadsDir(path, file.name);
      if (copiedPath != null) {
        paths.add(copiedPath);
      }
    }
    
    if (paths.isEmpty) return;
    
    // If scope is provided, upload to backend
    if (widget.scope != null && widget.onFilesDropped != null) {
      for (final path in paths) {
        final result = _uploadFile(path, widget.scope!);
        if (result.success) {
          debugPrint('✅ Uploaded: ${result.fileId}');
        } else {
          debugPrint('❌ Upload failed: ${result.error}');
        }
      }
      widget.onFilesDropped?.call(paths);
    }
    
    // If attachment callback provided (for chat)
    widget.onFilesAttached?.call(paths);
  }
  
  Future<String?> _copyToUploadsDir(String sourcePath, String filename) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final uploadsDir = Directory('${docsDir.path}/uploads');
      if (!await uploadsDir.exists()) {
        await uploadsDir.create(recursive: true);
      }
      
      final destPath = '${uploadsDir.path}/$filename';
      final sourceFile = File(sourcePath);
      
      // Remove existing file
      final destFile = File(destPath);
      if (await destFile.exists()) {
        await destFile.delete();
      }
      
      await sourceFile.copy(destPath);
      debugPrint('✅ Copied to: $destPath');
      
      return destPath;
    } catch (e) {
      debugPrint('❌ Copy failed: $e');
      return null;
    }
  }
  
  FileDropResult _uploadFile(String path, FileScope scope) {
    try {
      final scopeMap = _scopeToMap(scope);
      final result = CyanFFI.uploadFile(path, scopeMap);
      if (result != null) {
        // Parse result JSON
        // Expected: {"success": true, "file_id": "..."} or {"success": false, "error": "..."}
        return FileDropResult(success: true, fileId: result);
      }
      return const FileDropResult(success: false, error: 'FFI returned null');
    } catch (e) {
      return FileDropResult(success: false, error: e.toString());
    }
  }
  
  Map<String, dynamic> _scopeToMap(FileScope scope) {
    // Backend expects capitalized type: "Group", "Workspace", "Board"
    switch (scope.type) {
      case FileScopeType.group:
        return {'type': 'Group', 'group_id': scope.id};
      case FileScopeType.workspace:
        return {'type': 'Workspace', 'workspace_id': scope.id};
      case FileScopeType.board:
        return {'type': 'Board', 'board_id': scope.id};
    }
  }
}

// ============================================================================
// FILE TREE ROW WITH DROP SUPPORT
// ============================================================================

/// Wrapper for file tree rows that accepts file drops
class DroppableTreeRow extends StatefulWidget {
  final Widget child;
  final String itemId;
  final String itemType; // 'group', 'workspace', 'board'
  final void Function()? onRefresh;
  
  const DroppableTreeRow({
    super.key,
    required this.child,
    required this.itemId,
    required this.itemType,
    this.onRefresh,
  });
  
  @override
  State<DroppableTreeRow> createState() => _DroppableTreeRowState();
}

class _DroppableTreeRowState extends State<DroppableTreeRow> {
  bool _isDropTarget = false;
  
  FileScope? get _scope {
    switch (widget.itemType) {
      case 'group': return FileScope.group(widget.itemId);
      case 'workspace': return FileScope.workspace(widget.itemId);
      case 'board': return FileScope.board(widget.itemId);
      default: return null;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDropTarget = true),
      onDragExited: (_) => setState(() => _isDropTarget = false),
      onDragDone: (details) {
        setState(() => _isDropTarget = false);
        _handleFileDrop(details.files);
      },
      child: Container(
        decoration: BoxDecoration(
          border: _isDropTarget
              ? Border.all(color: MonokaiTheme.cyan, width: 2)
              : null,
          borderRadius: BorderRadius.circular(4),
          color: _isDropTarget ? MonokaiTheme.cyan.withOpacity(0.1) : null,
        ),
        child: widget.child,
      ),
    );
  }
  
  Future<void> _handleFileDrop(List<XFile> files) async {
    final scope = _scope;
    if (scope == null) {
      debugPrint('⚠️ Cannot drop on this item type: ${widget.itemType}');
      return;
    }
    
    debugPrint('📥 Dropped ${files.length} files on ${widget.itemType}: ${widget.itemId}');
    
    final scopeMap = _scopeToMap(scope);
    
    for (final file in files) {
      // Copy to uploads dir first
      final docsDir = await getApplicationDocumentsDirectory();
      final uploadsDir = Directory('${docsDir.path}/uploads');
      if (!await uploadsDir.exists()) {
        await uploadsDir.create(recursive: true);
      }
      
      final destPath = '${uploadsDir.path}/${file.name}';
      try {
        final sourceFile = File(file.path);
        await sourceFile.copy(destPath);
        
        // Upload via FFI
        final result = CyanFFI.uploadFile(destPath, scopeMap);
        debugPrint('📤 Upload result: $result');
      } catch (e) {
        debugPrint('❌ File drop failed: $e');
      }
    }
    
    widget.onRefresh?.call();
  }
  
  Map<String, dynamic> _scopeToMap(FileScope scope) {
    // Backend expects capitalized type: "Group", "Workspace", "Board"
    switch (scope.type) {
      case FileScopeType.group:
        return {'type': 'Group', 'group_id': scope.id};
      case FileScopeType.workspace:
        return {'type': 'Workspace', 'workspace_id': scope.id};
      case FileScopeType.board:
        return {'type': 'Board', 'board_id': scope.id};
    }
  }
}

// ============================================================================
// CHAT ATTACHMENT DROP ZONE
// ============================================================================

/// Drop zone specifically for chat input - attaches files to pending message
class ChatAttachmentDropZone extends StatefulWidget {
  final Widget child;
  final void Function(List<String> paths) onFilesAttached;
  
  const ChatAttachmentDropZone({
    super.key,
    required this.child,
    required this.onFilesAttached,
  });
  
  @override
  State<ChatAttachmentDropZone> createState() => _ChatAttachmentDropZoneState();
}

class _ChatAttachmentDropZoneState extends State<ChatAttachmentDropZone> {
  bool _isDragging = false;
  
  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        _handleDrop(details.files);
      },
      child: Stack(
        children: [
          widget.child,
          if (_isDragging) _buildDropOverlay(),
        ],
      ),
    );
  }
  
  Widget _buildDropOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: MonokaiTheme.green.withOpacity(0.15),
            border: Border.all(color: MonokaiTheme.green, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.attach_file, size: 32, color: MonokaiTheme.green),
                const SizedBox(height: 8),
                Text(
                  'Drop to attach',
                  style: TextStyle(
                    color: MonokaiTheme.green,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Future<void> _handleDrop(List<XFile> files) async {
    final paths = <String>[];
    
    final docsDir = await getApplicationDocumentsDirectory();
    final uploadsDir = Directory('${docsDir.path}/uploads');
    if (!await uploadsDir.exists()) {
      await uploadsDir.create(recursive: true);
    }
    
    for (final file in files) {
      try {
        final destPath = '${uploadsDir.path}/${file.name}';
        final destFile = File(destPath);
        if (await destFile.exists()) {
          await destFile.delete();
        }
        await File(file.path).copy(destPath);
        paths.add(destPath);
        debugPrint('📎 Attached: ${file.name}');
      } catch (e) {
        debugPrint('❌ Attach failed: $e');
      }
    }
    
    if (paths.isNotEmpty) {
      widget.onFilesAttached(paths);
    }
  }
}

// ============================================================================
// ATTACHMENT CHIP WIDGET
// ============================================================================

/// Visual chip showing an attached file with remove button
class AttachmentChip extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;
  
  const AttachmentChip({
    super.key,
    required this.path,
    required this.onRemove,
  });
  
  String get filename => path.split('/').last;
  
  IconData get icon {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'png': case 'jpg': case 'jpeg': case 'gif': case 'webp': return Icons.image;
      case 'mp4': case 'mov': case 'avi': case 'mkv': return Icons.videocam;
      case 'mp3': case 'wav': case 'm4a': return Icons.audiotrack;
      case 'zip': case 'tar': case 'gz': case 'rar': return Icons.folder_zip;
      case 'doc': case 'docx': return Icons.description;
      case 'xls': case 'xlsx': return Icons.table_chart;
      case 'ppt': case 'pptx': return Icons.slideshow;
      case 'txt': case 'md': return Icons.article;
      case 'py': case 'js': case 'ts': case 'dart': case 'rs': return Icons.code;
      default: return Icons.insert_drive_file;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: MonokaiTheme.comment.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: MonokaiTheme.cyan),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              filename,
              style: TextStyle(fontSize: 12, color: MonokaiTheme.foreground),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close, size: 14, color: MonokaiTheme.comment),
          ),
        ],
      ),
    );
  }
}
