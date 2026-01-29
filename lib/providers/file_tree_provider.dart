// providers/file_tree_provider.dart
// File tree state management - mirrors Swift's FileTreeViewModel
// Uses ComponentBridge pattern for command/event flow

import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ffi/component_bridge.dart';
import '../models/tree_item.dart';
import '../services/cyan_service.dart';

// ============================================================================
// STATE
// ============================================================================

class FileTreeState {
  final List<TreeGroup> groups;
  final Set<String> expandedGroups;
  final Set<String> expandedWorkspaces;
  final bool isLoading;
  final bool isLoaded;
  final String? error;
  
  // Inline editing
  final String? editingItemId;
  final String editingText;
  
  // Sync state
  final String? syncingGroupId;
  final String? syncingGroupName;
  final Set<String> syncingBoards;
  
  const FileTreeState({
    this.groups = const [],
    this.expandedGroups = const {},
    this.expandedWorkspaces = const {},
    this.isLoading = false,
    this.isLoaded = false,
    this.error,
    this.editingItemId,
    this.editingText = '',
    this.syncingGroupId,
    this.syncingGroupName,
    this.syncingBoards = const {},
  });
  
  FileTreeState copyWith({
    List<TreeGroup>? groups,
    Set<String>? expandedGroups,
    Set<String>? expandedWorkspaces,
    bool? isLoading,
    bool? isLoaded,
    String? error,
    String? editingItemId,
    String? editingText,
    String? syncingGroupId,
    String? syncingGroupName,
    Set<String>? syncingBoards,
    bool clearError = false,
    bool clearEditing = false,
    bool clearSyncing = false,
  }) {
    return FileTreeState(
      groups: groups ?? this.groups,
      expandedGroups: expandedGroups ?? this.expandedGroups,
      expandedWorkspaces: expandedWorkspaces ?? this.expandedWorkspaces,
      isLoading: isLoading ?? this.isLoading,
      isLoaded: isLoaded ?? this.isLoaded,
      error: clearError ? null : (error ?? this.error),
      editingItemId: clearEditing ? null : (editingItemId ?? this.editingItemId),
      editingText: clearEditing ? '' : (editingText ?? this.editingText),
      syncingGroupId: clearSyncing ? null : (syncingGroupId ?? this.syncingGroupId),
      syncingGroupName: clearSyncing ? null : (syncingGroupName ?? this.syncingGroupName),
      syncingBoards: clearSyncing ? const {} : (syncingBoards ?? this.syncingBoards),
    );
  }
  
  /// Get all boards across all groups and workspaces
  List<TreeBoard> get allBoards {
    final boards = <TreeBoard>[];
    for (final group in groups) {
      for (final workspace in group.workspaces) {
        boards.addAll(workspace.boards);
      }
    }
    return boards;
  }
  
  /// Get boards filtered by group
  List<TreeBoard> boardsForGroup(String groupId) {
    final group = groups.firstWhere((g) => g.id == groupId, orElse: () => TreeGroup.empty());
    final boards = <TreeBoard>[];
    for (final workspace in group.workspaces) {
      boards.addAll(workspace.boards);
    }
    return boards;
  }
  
  /// Get boards for a specific workspace
  List<TreeBoard> boardsForWorkspace(String workspaceId) {
    for (final group in groups) {
      for (final workspace in group.workspaces) {
        if (workspace.id == workspaceId) {
          return workspace.boards;
        }
      }
    }
    return [];
  }
  
  /// Find group by ID
  TreeGroup? findGroup(String id) {
    try {
      return groups.firstWhere((g) => g.id == id);
    } catch (_) {
      return null;
    }
  }
  
  /// Find workspace by ID
  TreeWorkspace? findWorkspace(String id) {
    for (final group in groups) {
      try {
        return group.workspaces.firstWhere((w) => w.id == id);
      } catch (_) {
        continue;
      }
    }
    return null;
  }
  
  /// Find board by ID
  TreeBoard? findBoard(String id) {
    for (final group in groups) {
      for (final workspace in group.workspaces) {
        try {
          return workspace.boards.firstWhere((b) => b.id == id);
        } catch (_) {
          continue;
        }
      }
    }
    return null;
  }
}

// ============================================================================
// PROVIDER
// ============================================================================

final fileTreeProvider = StateNotifierProvider<FileTreeNotifier, FileTreeState>((ref) {
  return FileTreeNotifier(ref);
});

// ============================================================================
// NOTIFIER
// ============================================================================

class FileTreeNotifier extends StateNotifier<FileTreeState> {
  final Ref _ref;
  final _bridge = FileTreeBridge();
  StreamSubscription<FileTreeEvent>? _subscription;
  
  FileTreeNotifier(this._ref) : super(const FileTreeState(isLoading: true)) {
    _init();
  }
  
  void _init() async {
    _bridge.start();
    _subscription = _bridge.events.listen(_handleEvent);
    
    // Wait for backend
    final service = CyanService.instance;
    var attempts = 0;
    while (!service.isReady && attempts < 50) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }
    
    if (!service.isReady) {
      print('⚠️ FileTree: Backend not ready, loading demo data');
      _loadDemoData();
      return;
    }
    
    print('✅ FileTree: Backend ready, requesting snapshot');
    _bridge.send(FileTreeCommand.seedDemoIfEmpty());
    await Future.delayed(const Duration(milliseconds: 200));
    _bridge.send(FileTreeCommand.snapshot());
    
    // Timeout fallback
    await Future.delayed(const Duration(seconds: 2));
    if (!state.isLoaded) {
      print('⚠️ FileTree: Snapshot timeout, loading demo data');
      _loadDemoData();
    }
  }
  
  void _handleEvent(FileTreeEvent event) {
    print('📥 FileTree event: ${event.type}');
    
    if (event.isTreeLoaded) {
      _handleTreeLoaded(event);
    } else if (event.isNetwork) {
      _handleNetworkEvent(event.data['data'] as Map<String, dynamic>?);
    } else if (event.isGroupCreated) {
      _handleGroupCreated(event.data);
    } else if (event.isGroupRenamed) {
      _handleGroupRenamed(event.data['id'] as String?, event.data['name'] as String?);
    } else if (event.isGroupDeleted) {
      _removeGroup(event.data['id'] as String?);
    } else if (event.isWorkspaceCreated) {
      _handleWorkspaceCreated(event.data);
    } else if (event.isWorkspaceDeleted) {
      _removeWorkspace(event.data['id'] as String?);
    } else if (event.isBoardCreated) {
      _handleBoardCreated(event.data);
    } else if (event.isBoardDeleted) {
      _removeBoard(event.data['id'] as String?);
    } else if (event.isError) {
      state = state.copyWith(
        error: event.errorMessage ?? 'Unknown error',
        isLoading: false,
      );
    }
  }
  
  void _handleTreeLoaded(FileTreeEvent event) {
    try {
      final dataStr = event.data['data'];
      if (dataStr == null) {
        print('⚠️ TreeLoaded: No data');
        _loadDemoData();
        return;
      }
      
      final Map<String, dynamic> snapshot;
      if (dataStr is String) {
        snapshot = jsonDecode(dataStr) as Map<String, dynamic>;
      } else {
        snapshot = dataStr as Map<String, dynamic>;
      }
      
      final groups = _parseGroups(snapshot);
      
      print('🌳 TreeLoaded: ${groups.length} groups');
      
      state = state.copyWith(
        groups: groups,
        isLoading: false,
        isLoaded: true,
        clearError: true,
      );
    } catch (e) {
      print('⚠️ TreeLoaded parse error: $e');
      _loadDemoData();
    }
  }
  
  List<TreeGroup> _parseGroups(Map<String, dynamic> snapshot) {
    final groupsData = snapshot['groups'] as List<dynamic>? ?? [];
    final workspacesData = snapshot['workspaces'] as List<dynamic>? ?? [];
    // NOTE: Rust returns "whiteboards" not "boards" - matches Swift TreeSnapshot
    final boardsData = snapshot['whiteboards'] as List<dynamic>? ?? snapshot['boards'] as List<dynamic>? ?? [];
    final filesData = snapshot['files'] as List<dynamic>? ?? [];
    
    print('🔍 Parsing: ${groupsData.length} groups, ${workspacesData.length} workspaces, ${boardsData.length} boards');
    
    // Build lookup maps
    final workspacesByGroup = <String, List<Map<String, dynamic>>>{};
    for (final ws in workspacesData) {
      final wsMap = ws as Map<String, dynamic>;
      final groupId = wsMap['group_id'] as String?;
      if (groupId != null) {
        workspacesByGroup.putIfAbsent(groupId, () => []).add(wsMap);
      }
    }
    
    final boardsByWorkspace = <String, List<Map<String, dynamic>>>{};
    for (final b in boardsData) {
      final bMap = b as Map<String, dynamic>;
      final wsId = bMap['workspace_id'] as String?;
      if (wsId != null) {
        boardsByWorkspace.putIfAbsent(wsId, () => []).add(bMap);
      }
    }
    
    // Build tree
    final groups = <TreeGroup>[];
    for (final g in groupsData) {
      final gMap = g as Map<String, dynamic>;
      final groupId = gMap['id'] as String;
      
      final workspaces = <TreeWorkspace>[];
      for (final wsMap in (workspacesByGroup[groupId] ?? [])) {
        final wsId = wsMap['id'] as String;
        
        final boards = <TreeBoard>[];
        for (final bMap in (boardsByWorkspace[wsId] ?? [])) {
          boards.add(TreeBoard(
            id: bMap['id'] as String,
            workspaceId: wsId,
            name: bMap['name'] as String? ?? 'Untitled',
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              ((bMap['created_at'] as int?) ?? 0) * 1000,
            ),
            boardType: bMap['board_type'] as String? ?? 'canvas',
            isPinned: bMap['is_pinned'] as bool? ?? false,
            rating: bMap['rating'] as int? ?? 0,
            labels: (bMap['labels'] as List<dynamic>?)?.cast<String>() ?? [],
          ));
        }
        
        workspaces.add(TreeWorkspace(
          id: wsId,
          groupId: groupId,
          name: wsMap['name'] as String? ?? 'Untitled',
          boards: boards,
        ));
      }
      
      groups.add(TreeGroup(
        id: groupId,
        name: gMap['name'] as String? ?? 'Untitled',
        color: gMap['color'] as String? ?? '#66D9EF',
        workspaces: workspaces,
      ));
    }
    
    return groups;
  }
  
  void _handleNetworkEvent(Map<String, dynamic>? event) {
    if (event == null) return;
    final type = event['type'] as String?;
    print('🔔 Network event: $type');
    
    switch (type) {
      case 'GroupCreated':
        _handleGroupCreated(event);
        break;
      case 'GroupRenamed':
        _handleGroupRenamed(event['id'] as String?, event['name'] as String?);
        break;
      case 'GroupDeleted':
      case 'GroupDissolved':
        _removeGroup(event['id'] as String?);
        break;
      case 'WorkspaceCreated':
        _handleWorkspaceCreated(event);
        break;
      case 'WorkspaceDeleted':
      case 'WorkspaceDissolved':
        _removeWorkspace(event['id'] as String?);
        break;
      case 'BoardCreated':
        _handleBoardCreated(event);
        break;
      case 'BoardDeleted':
      case 'BoardDissolved':
        _removeBoard(event['id'] as String?);
        break;
    }
  }
  
  void _handleGroupCreated(Map<String, dynamic> data) {
    final group = TreeGroup(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? 'New Group',
      color: data['color'] as String? ?? '#66D9EF',
      workspaces: [],
    );
    
    // Check for temp item to replace
    final tempIndex = state.groups.indexWhere(
      (g) => g.id.startsWith('temp_') && g.name == group.name,
    );
    
    if (tempIndex >= 0) {
      final updated = List<TreeGroup>.from(state.groups);
      updated[tempIndex] = group;
      state = state.copyWith(groups: updated);
    } else {
      state = state.copyWith(groups: [...state.groups, group]);
    }
  }
  
  void _handleGroupRenamed(String? id, String? name) {
    if (id == null || name == null) return;
    final updated = state.groups.map((g) {
      if (g.id == id) return g.copyWith(name: name);
      return g;
    }).toList();
    state = state.copyWith(groups: updated);
  }
  
  void _handleWorkspaceCreated(Map<String, dynamic> data) {
    final groupId = data['group_id'] as String?;
    if (groupId == null) return;
    
    final ws = TreeWorkspace(
      id: data['id'] as String? ?? '',
      groupId: groupId,
      name: data['name'] as String? ?? 'New Workspace',
      boards: [],
    );
    
    final updated = state.groups.map((g) {
      if (g.id == groupId) {
        return g.copyWith(workspaces: [...g.workspaces, ws]);
      }
      return g;
    }).toList();
    
    state = state.copyWith(groups: updated);
  }
  
  void _handleBoardCreated(Map<String, dynamic> data) {
    final workspaceId = data['workspace_id'] as String?;
    if (workspaceId == null) return;
    
    final board = TreeBoard(
      id: data['id'] as String? ?? '',
      workspaceId: workspaceId,
      name: data['name'] as String? ?? 'New Board',
      createdAt: DateTime.now(),
      boardType: data['board_type'] as String? ?? 'canvas',
    );
    
    final updated = state.groups.map((g) {
      return g.copyWith(
        workspaces: g.workspaces.map((ws) {
          if (ws.id == workspaceId) {
            return ws.copyWith(boards: [...ws.boards, board]);
          }
          return ws;
        }).toList(),
      );
    }).toList();
    
    state = state.copyWith(groups: updated);
  }
  
  void _removeGroup(String? id) {
    if (id == null) return;
    state = state.copyWith(
      groups: state.groups.where((g) => g.id != id).toList(),
      expandedGroups: Set.from(state.expandedGroups)..remove(id),
    );
  }
  
  void _removeWorkspace(String? id) {
    if (id == null) return;
    final updated = state.groups.map((g) {
      return g.copyWith(
        workspaces: g.workspaces.where((ws) => ws.id != id).toList(),
      );
    }).toList();
    state = state.copyWith(
      groups: updated,
      expandedWorkspaces: Set.from(state.expandedWorkspaces)..remove(id),
    );
  }
  
  void _removeBoard(String? id) {
    if (id == null) return;
    final updated = state.groups.map((g) {
      return g.copyWith(
        workspaces: g.workspaces.map((ws) {
          return ws.copyWith(
            boards: ws.boards.where((b) => b.id != id).toList(),
          );
        }).toList(),
      );
    }).toList();
    state = state.copyWith(groups: updated);
  }
  
  void _loadDemoData() {
    final demoGroups = <TreeGroup>[
      TreeGroup(
        id: 'demo-group-1',
        name: 'Personal',
        color: '#66D9EF',
        workspaces: [
          TreeWorkspace(
            id: 'demo-ws-1',
            groupId: 'demo-group-1',
            name: 'Projects',
            boards: [
              TreeBoard(id: 'demo-board-1', workspaceId: 'demo-ws-1', name: 'Welcome Board', createdAt: DateTime.now(), boardType: 'canvas'),
              TreeBoard(id: 'demo-board-2', workspaceId: 'demo-ws-1', name: 'Ideas', createdAt: DateTime.now(), boardType: 'notebook'),
            ],
          ),
          TreeWorkspace(
            id: 'demo-ws-2',
            groupId: 'demo-group-1',
            name: 'Notes',
            boards: [
              TreeBoard(id: 'demo-board-3', workspaceId: 'demo-ws-2', name: 'Daily Log', createdAt: DateTime.now(), boardType: 'notes'),
            ],
          ),
        ],
      ),
      TreeGroup(
        id: 'demo-group-2',
        name: 'Work',
        color: '#A6E22E',
        workspaces: [
          TreeWorkspace(
            id: 'demo-ws-3',
            groupId: 'demo-group-2',
            name: 'Team Alpha',
            boards: [
              TreeBoard(id: 'demo-board-4', workspaceId: 'demo-ws-3', name: 'Sprint Planning', createdAt: DateTime.now(), boardType: 'canvas', isPinned: true),
              TreeBoard(id: 'demo-board-5', workspaceId: 'demo-ws-3', name: 'Retrospective', createdAt: DateTime.now(), boardType: 'notebook', rating: 5),
            ],
          ),
        ],
      ),
    ];
    
    state = state.copyWith(
      groups: demoGroups,
      isLoading: false,
      isLoaded: true,
      clearError: true,
    );
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════
  
  void toggleGroupExpanded(String groupId) {
    final expanded = Set<String>.from(state.expandedGroups);
    if (expanded.contains(groupId)) {
      expanded.remove(groupId);
    } else {
      expanded.add(groupId);
    }
    state = state.copyWith(expandedGroups: expanded);
  }
  
  void toggleWorkspaceExpanded(String workspaceId) {
    final expanded = Set<String>.from(state.expandedWorkspaces);
    if (expanded.contains(workspaceId)) {
      expanded.remove(workspaceId);
    } else {
      expanded.add(workspaceId);
    }
    state = state.copyWith(expandedWorkspaces: expanded);
  }
  
  void refresh() {
    state = state.copyWith(isLoading: true);
    _bridge.send(FileTreeCommand.snapshot());
  }
  
  void createGroup(String name) {
    _bridge.send(FileTreeCommand.createGroup(name: name));
  }
  
  void createWorkspace(String groupId, String name) {
    _bridge.send(FileTreeCommand.createWorkspace(groupId: groupId, name: name));
  }
  
  void createBoard(String workspaceId, String name) {
    _bridge.send(FileTreeCommand.createBoard(workspaceId: workspaceId, name: name));
  }
  
  void renameGroup(String id, String name) {
    _bridge.send(FileTreeCommand.renameGroup(id: id, name: name));
  }
  
  void renameWorkspace(String id, String name) {
    _bridge.send(FileTreeCommand.renameWorkspace(id: id, name: name));
  }
  
  // Alias for compatibility
  void renameWorkspaceById(String id, String name) => renameWorkspace(id, name);
  
  void renameBoard(String id, String name) {
    _bridge.send(FileTreeCommand.renameBoard(id: id, name: name));
  }
  
  // Alias for compatibility
  void renameBoardById(String id, String name) => renameBoard(id, name);
  
  void deleteGroup(String id) {
    _bridge.send(FileTreeCommand.deleteGroup(id: id));
  }
  
  void deleteWorkspace(String id) {
    _bridge.send(FileTreeCommand.deleteWorkspace(id: id));
  }
  
  void deleteBoard(String id) {
    _bridge.send(FileTreeCommand.deleteBoard(id: id));
  }
  
  void leaveGroup(String id) {
    _bridge.send(FileTreeCommand.leaveGroup(id: id));
  }
  
  void leaveWorkspace(String id) {
    _bridge.send(FileTreeCommand.leaveWorkspace(id: id));
  }
  
  void leaveBoard(String id) {
    _bridge.send(FileTreeCommand.leaveBoard(id: id));
  }
  
  // Inline editing
  void startEditing(String itemId, String currentText) {
    state = state.copyWith(
      editingItemId: itemId,
      editingText: currentText,
    );
  }
  
  void updateEditingText(String text) {
    state = state.copyWith(editingText: text);
  }
  
  void cancelEditing() {
    state = state.copyWith(clearEditing: true);
  }
  
  void commitEditing(String itemType) {
    final id = state.editingItemId;
    final name = state.editingText.trim();
    
    if (id == null || name.isEmpty) {
      cancelEditing();
      return;
    }
    
    switch (itemType) {
      case 'group':
        renameGroup(id, name);
        break;
      case 'workspace':
        renameWorkspace(id, name);
        break;
      case 'board':
        renameBoard(id, name);
        break;
    }
    
    cancelEditing();
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    _bridge.dispose();
    super.dispose();
  }
}
