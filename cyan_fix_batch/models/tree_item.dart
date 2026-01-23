// models/tree_item.dart
// Tree models matching Rust's TreeSnapshotDTO structure

import 'dart:convert';

/// Group - matches Rust Group struct
class TreeGroup {
  final String id;
  final String name;
  final String icon;
  final String color;
  final int createdAt;
  final List<TreeWorkspace> workspaces;
  final int peerCount;
  
  const TreeGroup({
    required this.id,
    required this.name,
    this.icon = 'folder.fill',
    this.color = '#FD971F',
    this.createdAt = 0,
    this.workspaces = const [],
    this.peerCount = 0,
  });
  
  factory TreeGroup.fromJson(Map<String, dynamic> json) {
    return TreeGroup(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String? ?? 'folder.fill',
      color: json['color'] as String? ?? '#FD971F',
      createdAt: json['created_at'] as int? ?? 0,
      workspaces: [], // Populated separately
      peerCount: json['peer_count'] as int? ?? 0,
    );
  }
  
  TreeGroup copyWith({
    String? id,
    String? name,
    String? icon,
    String? color,
    int? createdAt,
    List<TreeWorkspace>? workspaces,
    int? peerCount,
  }) {
    return TreeGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      workspaces: workspaces ?? this.workspaces,
      peerCount: peerCount ?? this.peerCount,
    );
  }
}

/// Workspace - matches Rust Workspace struct
class TreeWorkspace {
  final String id;
  final String groupId;
  final String name;
  final int createdAt;
  final List<TreeBoard> boards;
  
  const TreeWorkspace({
    required this.id,
    required this.groupId,
    required this.name,
    this.createdAt = 0,
    this.boards = const [],
  });
  
  factory TreeWorkspace.fromJson(Map<String, dynamic> json) {
    return TreeWorkspace(
      id: json['id'] as String? ?? '',
      groupId: json['group_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      createdAt: json['created_at'] as int? ?? 0,
      boards: [], // Populated separately
    );
  }
  
  TreeWorkspace copyWith({
    String? id,
    String? groupId,
    String? name,
    int? createdAt,
    List<TreeBoard>? boards,
  }) {
    return TreeWorkspace(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      boards: boards ?? this.boards,
    );
  }
}

/// Board (Whiteboard) - matches Rust WhiteboardDTO
class TreeBoard {
  final String id;
  final String workspaceId;
  final String name;
  final int createdAt;
  final String? boardType;
  final bool hasUnread;
  final bool isPinned;
  final int rating;
  final DateTime? lastModified;
  
  const TreeBoard({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.createdAt = 0,
    this.boardType,
    this.hasUnread = false,
    this.isPinned = false,
    this.rating = 0,
    this.lastModified,
  });
  
  factory TreeBoard.fromJson(Map<String, dynamic> json) {
    final lastAccessed = json['last_accessed'] as int?;
    return TreeBoard(
      id: json['id'] as String? ?? '',
      workspaceId: json['workspace_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      createdAt: json['created_at'] as int? ?? 0,
      boardType: json['board_type'] as String?,
      hasUnread: json['has_unread'] as bool? ?? false,
      isPinned: json['is_pinned'] as bool? ?? false,
      rating: json['rating'] as int? ?? 0,
      lastModified: lastAccessed != null && lastAccessed > 0 
          ? DateTime.fromMillisecondsSinceEpoch(lastAccessed * 1000)
          : null,
    );
  }
}

/// Tree snapshot - matches Rust TreeSnapshotDTO
class TreeSnapshot {
  final List<TreeGroup> groups;
  final List<TreeWorkspace> workspaces;
  final List<TreeBoard> whiteboards;
  
  const TreeSnapshot({
    this.groups = const [],
    this.workspaces = const [],
    this.whiteboards = const [],
  });
  
  factory TreeSnapshot.fromJson(String jsonStr) {
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      
      final groupsList = (json['groups'] as List<dynamic>?)
          ?.map((g) => TreeGroup.fromJson(g as Map<String, dynamic>))
          .toList() ?? [];
      
      final workspacesList = (json['workspaces'] as List<dynamic>?)
          ?.map((w) => TreeWorkspace.fromJson(w as Map<String, dynamic>))
          .toList() ?? [];
      
      final boardsList = (json['whiteboards'] as List<dynamic>?)
          ?.map((b) => TreeBoard.fromJson(b as Map<String, dynamic>))
          .toList() ?? [];
      
      return TreeSnapshot(
        groups: groupsList,
        workspaces: workspacesList,
        whiteboards: boardsList,
      );
    } catch (e) {
      print('⚠️ TreeSnapshot.fromJson error: $e');
      return const TreeSnapshot();
    }
  }
  
  /// Build hierarchical tree from flat lists
  List<TreeGroup> buildTree() {
    // Build boards by workspace
    final boardsByWorkspace = <String, List<TreeBoard>>{};
    for (final board in whiteboards) {
      boardsByWorkspace.putIfAbsent(board.workspaceId, () => []);
      boardsByWorkspace[board.workspaceId]!.add(board);
    }
    
    // Build workspaces by group
    final workspacesByGroup = <String, List<TreeWorkspace>>{};
    for (final ws in workspaces) {
      final wsWithBoards = ws.copyWith(
        boards: boardsByWorkspace[ws.id] ?? [],
      );
      workspacesByGroup.putIfAbsent(ws.groupId, () => []);
      workspacesByGroup[ws.groupId]!.add(wsWithBoards);
    }
    
    // Build groups with workspaces
    return groups.map((g) => g.copyWith(
      workspaces: workspacesByGroup[g.id] ?? [],
    )).toList();
  }
}
