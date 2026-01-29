// models/tree_item.dart
// Tree structure models for groups, workspaces, boards

import 'package:flutter/foundation.dart';

/// A group in the file tree (top level)
@immutable
class TreeGroup {
  final String id;
  final String name;
  final String color;
  final List<TreeWorkspace> workspaces;
  final int peerCount;
  
  const TreeGroup({
    required this.id,
    required this.name,
    required this.color,
    required this.workspaces,
    this.peerCount = 0,
  });
  
  factory TreeGroup.empty() => const TreeGroup(
    id: '',
    name: '',
    color: '#66D9EF',
    workspaces: [],
    peerCount: 0,
  );
  
  TreeGroup copyWith({
    String? id,
    String? name,
    String? color,
    List<TreeWorkspace>? workspaces,
    int? peerCount,
  }) {
    return TreeGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      workspaces: workspaces ?? this.workspaces,
      peerCount: peerCount ?? this.peerCount,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'workspaces': workspaces.map((w) => w.toJson()).toList(),
  };
  
  factory TreeGroup.fromJson(Map<String, dynamic> json) => TreeGroup(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    color: json['color'] as String? ?? '#66D9EF',
    workspaces: (json['workspaces'] as List<dynamic>?)
        ?.map((w) => TreeWorkspace.fromJson(w as Map<String, dynamic>))
        .toList() ?? [],
  );
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TreeGroup &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A workspace in a group
@immutable
class TreeWorkspace {
  final String id;
  final String groupId;
  final String name;
  final List<TreeBoard> boards;
  
  const TreeWorkspace({
    required this.id,
    required this.groupId,
    required this.name,
    required this.boards,
  });
  
  TreeWorkspace copyWith({
    String? id,
    String? groupId,
    String? name,
    List<TreeBoard>? boards,
  }) {
    return TreeWorkspace(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      name: name ?? this.name,
      boards: boards ?? this.boards,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'group_id': groupId,
    'name': name,
    'boards': boards.map((b) => b.toJson()).toList(),
  };
  
  factory TreeWorkspace.fromJson(Map<String, dynamic> json) => TreeWorkspace(
    id: json['id'] as String? ?? '',
    groupId: json['group_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    boards: (json['boards'] as List<dynamic>?)
        ?.map((b) => TreeBoard.fromJson(b as Map<String, dynamic>))
        .toList() ?? [],
  );
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TreeWorkspace &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A board in a workspace
@immutable
class TreeBoard {
  final String id;
  final String workspaceId;
  final String name;
  final DateTime createdAt;
  final String boardType; // 'canvas', 'notebook', 'notes'
  final bool isPinned;
  final int rating; // 0-5 stars
  final List<String> labels;
  final bool hasUnread;
  final DateTime? lastModified;
  final DateTime? lastAccessed;
  final String? containsModel; // GGUF model name if present
  final List<String> containsSkills;
  
  const TreeBoard({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.createdAt,
    this.boardType = 'canvas',
    this.isPinned = false,
    this.rating = 0,
    this.labels = const [],
    this.hasUnread = false,
    this.lastModified,
    this.lastAccessed,
    this.containsModel,
    this.containsSkills = const [],
  });
  
  TreeBoard copyWith({
    String? id,
    String? workspaceId,
    String? name,
    DateTime? createdAt,
    String? boardType,
    bool? isPinned,
    int? rating,
    List<String>? labels,
    bool? hasUnread,
    DateTime? lastModified,
    DateTime? lastAccessed,
    String? containsModel,
    List<String>? containsSkills,
  }) {
    return TreeBoard(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      boardType: boardType ?? this.boardType,
      isPinned: isPinned ?? this.isPinned,
      rating: rating ?? this.rating,
      labels: labels ?? this.labels,
      hasUnread: hasUnread ?? this.hasUnread,
      lastModified: lastModified ?? this.lastModified,
      lastAccessed: lastAccessed ?? this.lastAccessed,
      containsModel: containsModel ?? this.containsModel,
      containsSkills: containsSkills ?? this.containsSkills,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'workspace_id': workspaceId,
    'name': name,
    'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
    'board_type': boardType,
    'is_pinned': isPinned,
    'rating': rating,
    'labels': labels,
    'has_unread': hasUnread,
    if (lastModified != null) 'last_modified': lastModified!.millisecondsSinceEpoch ~/ 1000,
    if (lastAccessed != null) 'last_accessed': lastAccessed!.millisecondsSinceEpoch ~/ 1000,
    if (containsModel != null) 'contains_model': containsModel,
    'contains_skills': containsSkills,
  };
  
  factory TreeBoard.fromJson(Map<String, dynamic> json) => TreeBoard(
    id: json['id'] as String? ?? '',
    workspaceId: json['workspace_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      ((json['created_at'] as int?) ?? 0) * 1000,
    ),
    boardType: json['board_type'] as String? ?? 'canvas',
    isPinned: json['is_pinned'] as bool? ?? false,
    rating: json['rating'] as int? ?? 0,
    labels: (json['labels'] as List<dynamic>?)?.cast<String>() ?? [],
    hasUnread: json['has_unread'] as bool? ?? false,
    lastModified: json['last_modified'] != null
        ? DateTime.fromMillisecondsSinceEpoch((json['last_modified'] as int) * 1000)
        : null,
    lastAccessed: json['last_accessed'] != null
        ? DateTime.fromMillisecondsSinceEpoch((json['last_accessed'] as int) * 1000)
        : null,
    containsModel: json['contains_model'] as String?,
    containsSkills: (json['contains_skills'] as List<dynamic>?)?.cast<String>() ?? [],
  );
  
  /// Get board face type for display
  BoardFace get face {
    switch (boardType.toLowerCase()) {
      case 'notebook':
        return BoardFace.notebook;
      case 'notes':
        return BoardFace.notes;
      default:
        return BoardFace.canvas;
    }
  }
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TreeBoard &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Board face type (how it's displayed)
enum BoardFace {
  canvas,
  notebook,
  notes;
  
  String get displayName {
    switch (this) {
      case BoardFace.canvas:
        return 'Canvas';
      case BoardFace.notebook:
        return 'Notebook';
      case BoardFace.notes:
        return 'Notes';
    }
  }
  
  String get icon {
    switch (this) {
      case BoardFace.canvas:
        return '🎨';
      case BoardFace.notebook:
        return '📓';
      case BoardFace.notes:
        return '📝';
    }
  }
}

/// A file attached to a scope (group, workspace, or board)
@immutable
class TreeFile {
  final String id;
  final String name;
  final String? groupId;
  final String? workspaceId;
  final String? boardId;
  final String hash;
  final int size;
  final String? mimeType;
  final DateTime createdAt;
  final String? localPath;
  final FileStatus status;
  
  const TreeFile({
    required this.id,
    required this.name,
    this.groupId,
    this.workspaceId,
    this.boardId,
    required this.hash,
    required this.size,
    this.mimeType,
    required this.createdAt,
    this.localPath,
    this.status = FileStatus.remote,
  });
  
  TreeFile copyWith({
    String? id,
    String? name,
    String? groupId,
    String? workspaceId,
    String? boardId,
    String? hash,
    int? size,
    String? mimeType,
    DateTime? createdAt,
    String? localPath,
    FileStatus? status,
  }) {
    return TreeFile(
      id: id ?? this.id,
      name: name ?? this.name,
      groupId: groupId ?? this.groupId,
      workspaceId: workspaceId ?? this.workspaceId,
      boardId: boardId ?? this.boardId,
      hash: hash ?? this.hash,
      size: size ?? this.size,
      mimeType: mimeType ?? this.mimeType,
      createdAt: createdAt ?? this.createdAt,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
    );
  }
  
  factory TreeFile.fromJson(Map<String, dynamic> json) => TreeFile(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    groupId: json['group_id'] as String?,
    workspaceId: json['workspace_id'] as String?,
    boardId: json['board_id'] as String?,
    hash: json['hash'] as String? ?? '',
    size: json['size'] as int? ?? 0,
    mimeType: json['mime_type'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      ((json['created_at'] as int?) ?? 0) * 1000,
    ),
    localPath: json['local_path'] as String?,
    status: FileStatus.fromString(json['status'] as String?),
  );
  
  /// Human readable file size
  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(size / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
  
  /// File extension from name
  String get extension {
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }
  
  /// Is this file available locally?
  bool get isLocal => localPath != null && status == FileStatus.local;
}

/// File availability status
enum FileStatus {
  remote,     // Only on peers, needs download
  downloading,
  local,      // Available locally
  uploading,
  error;
  
  static FileStatus fromString(String? s) {
    switch (s?.toLowerCase()) {
      case 'downloading':
        return FileStatus.downloading;
      case 'local':
        return FileStatus.local;
      case 'uploading':
        return FileStatus.uploading;
      case 'error':
        return FileStatus.error;
      default:
        return FileStatus.remote;
    }
  }
}
