// providers/file_tree_provider.dart
// File tree state - groups, workspaces, boards
// Uses ComponentBridge for events, direct FFI for CRUD (matches Swift pattern)

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ffi/component_bridge.dart';
import '../ffi/ffi_helpers.dart';
import '../models/tree_item.dart';

// ═══════════════════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════════════════

class FileTreeState {
  final List<TreeGroup> groups;
  final Set<String> expandedGroups;
  final Set<String> expandedWorkspaces;
  final bool isLoading;
  final String? error;
  
  const FileTreeState({
    this.groups = const [],
    this.expandedGroups = const {},
    this.expandedWorkspaces = const {},
    this.isLoading = false,
    this.error,
  });
  
  FileTreeState copyWith({
    List<TreeGroup>? groups,
    Set<String>? expandedGroups,
    Set<String>? expandedWorkspaces,
    bool? isLoading,
    String? error,
  }) {
    return FileTreeState(
      groups: groups ?? this.groups,
      expandedGroups: expandedGroups ?? this.expandedGroups,
      expandedWorkspaces: expandedWorkspaces ?? this.expandedWorkspaces,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

final fileTreeProvider = StateNotifierProvider<FileTreeNotifier, FileTreeState>((ref) {
  return FileTreeNotifier();
});

// ═══════════════════════════════════════════════════════════════════════════
// NOTIFIER - Uses ComponentBridge pattern
// ═══════════════════════════════════════════════════════════════════════════

class FileTreeNotifier extends StateNotifier<FileTreeState> {
  final _bridge = FileTreeBridge();
  StreamSubscription<FileTreeEvent>? _subscription;
  
  FileTreeNotifier() : super(const FileTreeState(isLoading: true)) {
    _init();
  }
  
  void _init() {
    // Start bridge and listen for events
    _bridge.start();
    _subscription = _bridge.events.listen(_handleEvent);
    
    // Request initial data
    print('🌳 FileTreeNotifier: Requesting SeedDemoIfEmpty + Snapshot');
    _bridge.send(FileTreeCommand.seedDemoIfEmpty());
    
    // Small delay then request snapshot
    Future.delayed(const Duration(milliseconds: 200), () {
      _bridge.send(FileTreeCommand.snapshot());
    });
  }
  
  void _handleEvent(FileTreeEvent event) {
    print('📥 FileTree event: ${event.type}');
    
    switch (event.type) {
      case 'TreeLoaded':
        _handleTreeLoaded(event);
        break;
        
      case 'Network':
        final networkData = event.data['data'] as Map<String, dynamic>?;
        if (networkData != null) {
          _handleNetworkEvent(networkData);
        }
        break;
        
      case 'GroupDeleted':
      case 'GroupLeft':
        final id = event.data['id'] as String?;
        if (id != null) _removeGroup(id);
        break;
        
      case 'WorkspaceDeleted':
      case 'WorkspaceLeft':
        final id = event.data['id'] as String?;
        if (id != null) _removeWorkspace(id);
        break;
        
      case 'BoardDeleted':
      case 'BoardLeft':
        final id = event.data['id'] as String?;
        if (id != null) _removeBoard(id);
        break;
        
      case 'Error':
        state = state.copyWith(
          error: event.data['message'] as String?,
          isLoading: false,
        );
        break;
    }
  }
  
  void _handleTreeLoaded(FileTreeEvent event) {
    try {
      // TreeLoaded comes with data as JSON string
      final treeJson = event.data['data'] as String? ?? '{}';
      print('🌳 TreeLoaded data length: ${treeJson.length}');
      
      final snapshot = TreeSnapshot.fromJson(treeJson);
      final tree = snapshot.buildTree();
      
      print('🌳 Parsed ${tree.length} groups');
      
      state = state.copyWith(
        groups: tree,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      print('⚠️ TreeLoaded parse error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to parse tree: $e',
      );
    }
  }
  
  void _handleNetworkEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    print('🔔 NetworkEvent: $type');
    
    switch (type) {
      case 'GroupCreated':
        print('➕ GroupCreated: ${event['name']}');
        final group = TreeGroup.fromJson(event);
        state = state.copyWith(
          groups: [...state.groups, group],
        );
        break;
        
      case 'GroupRenamed':
        final id = event['id'] as String?;
        final name = event['name'] as String?;
        if (id != null && name != null) {
          state = state.copyWith(
            groups: state.groups.map((g) {
              if (g.id == id) return g.copyWith(name: name);
              return g;
            }).toList(),
          );
        }
        break;
        
      case 'GroupDeleted':
      case 'GroupDissolved':
        final id = event['id'] as String?;
        if (id != null) _removeGroup(id);
        break;
        
      case 'WorkspaceCreated':
        print('➕ WorkspaceCreated: ${event['name']} in group ${event['group_id']}');
        final ws = TreeWorkspace.fromJson(event);
        state = state.copyWith(
          groups: state.groups.map((g) {
            if (g.id == ws.groupId) {
              return g.copyWith(workspaces: [...g.workspaces, ws]);
            }
            return g;
          }).toList(),
        );
        break;
        
      case 'WorkspaceRenamed':
        final id = event['id'] as String?;
        final name = event['name'] as String?;
        if (id != null && name != null) _renameWorkspace(id, name);
        break;
        
      case 'WorkspaceDeleted':
      case 'WorkspaceDissolved':
        final id = event['id'] as String?;
        if (id != null) _removeWorkspace(id);
        break;
        
      case 'BoardCreated':
        print('➕ BoardCreated: ${event['name']} in workspace ${event['workspace_id']}');
        final board = TreeBoard.fromJson(event);
        state = state.copyWith(
          groups: state.groups.map((g) {
            return g.copyWith(
              workspaces: g.workspaces.map((ws) {
                if (ws.id == board.workspaceId) {
                  return ws.copyWith(boards: [...ws.boards, board]);
                }
                return ws;
              }).toList(),
            );
          }).toList(),
        );
        break;
        
      case 'BoardRenamed':
        final id = event['id'] as String?;
        final name = event['name'] as String?;
        if (id != null && name != null) _renameBoard(id, name);
        break;
        
      case 'BoardDeleted':
      case 'BoardDissolved':
        final id = event['id'] as String?;
        if (id != null) _removeBoard(id);
        break;
    }
  }
  
  void _removeGroup(String id) {
    state = state.copyWith(
      groups: state.groups.where((g) => g.id != id).toList(),
      expandedGroups: Set.from(state.expandedGroups)..remove(id),
    );
  }
  
  void _removeWorkspace(String id) {
    state = state.copyWith(
      groups: state.groups.map((g) {
        return g.copyWith(
          workspaces: g.workspaces.where((ws) => ws.id != id).toList(),
        );
      }).toList(),
      expandedWorkspaces: Set.from(state.expandedWorkspaces)..remove(id),
    );
  }
  
  void _removeBoard(String id) {
    state = state.copyWith(
      groups: state.groups.map((g) {
        return g.copyWith(
          workspaces: g.workspaces.map((ws) {
            return ws.copyWith(
              boards: ws.boards.where((b) => b.id != id).toList(),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
  
  void _renameWorkspace(String id, String name) {
    state = state.copyWith(
      groups: state.groups.map((g) {
        return g.copyWith(
          workspaces: g.workspaces.map((ws) {
            if (ws.id == id) return ws.copyWith(name: name);
            return ws;
          }).toList(),
        );
      }).toList(),
    );
  }
  
  void _renameBoard(String id, String name) {
    state = state.copyWith(
      groups: state.groups.map((g) {
        return g.copyWith(
          workspaces: g.workspaces.map((ws) {
            return ws.copyWith(
              boards: ws.boards.map((b) {
                if (b.id == id) {
                  return TreeBoard(
                    id: b.id,
                    workspaceId: b.workspaceId,
                    name: name,
                    createdAt: b.createdAt,
                    boardType: b.boardType,
                    hasUnread: b.hasUnread,
                    isPinned: b.isPinned,
                    rating: b.rating,
                    lastModified: b.lastModified,
                  );
                }
                return b;
              }).toList(),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API - Send commands via bridge
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
  
  /// Refresh tree from backend
  void refresh() {
    print('🔄 FileTree: Refresh requested');
    state = state.copyWith(isLoading: true);
    _bridge.send(FileTreeCommand.snapshot());
  }
  
  /// Create a new group
  void createGroup(String name) {
    print('📤 FileTree: CreateGroup "$name"');
    _bridge.send(FileTreeCommand.createGroup(name: name));
  }
  
  /// Create a new workspace in a group
  void createWorkspace(String groupId, String name) {
    print('📤 FileTree: CreateWorkspace "$name" in group $groupId');
    _bridge.send(FileTreeCommand.createWorkspace(groupId: groupId, name: name));
  }
  
  /// Create a new board in a workspace
  void createBoard(String workspaceId, String name) {
    print('📤 FileTree: CreateBoard "$name" in workspace $workspaceId');
    _bridge.send(FileTreeCommand.createBoard(workspaceId: workspaceId, name: name));
  }
  
  /// Rename a group
  void renameGroup(String id, String name) {
    print('📤 FileTree: RenameGroup $id to "$name"');
    _bridge.send(FileTreeCommand.renameGroup(id: id, name: name));
  }
  
  /// Rename a workspace
  void renameWorkspaceById(String id, String name) {
    print('📤 FileTree: RenameWorkspace $id to "$name"');
    _bridge.send(FileTreeCommand.renameWorkspace(id: id, name: name));
  }
  
  /// Rename a board
  void renameBoardById(String id, String name) {
    print('📤 FileTree: RenameBoard $id to "$name"');
    _bridge.send(FileTreeCommand.renameBoard(id: id, name: name));
  }
  
  /// Delete a group
  void deleteGroup(String id) {
    print('📤 FileTree: DeleteGroup $id');
    _bridge.send(FileTreeCommand.deleteGroup(id: id));
  }
  
  /// Delete a workspace
  void deleteWorkspace(String id) {
    print('📤 FileTree: DeleteWorkspace $id');
    _bridge.send(FileTreeCommand.deleteWorkspace(id: id));
  }
  
  /// Delete a board
  void deleteBoard(String id) {
    print('📤 FileTree: DeleteBoard $id');
    _bridge.send(FileTreeCommand.deleteBoard(id: id));
  }
  
  /// Leave a group (non-owner)
  void leaveGroup(String id) {
    print('📤 FileTree: LeaveGroup $id');
    _bridge.send(FileTreeCommand.leaveGroup(id: id));
  }
  
  /// Leave a workspace (non-owner)
  void leaveWorkspace(String id) {
    print('📤 FileTree: LeaveWorkspace $id');
    _bridge.send(FileTreeCommand.leaveWorkspace(id: id));
  }
  
  /// Leave a board (non-owner)
  void leaveBoard(String id) {
    print('📤 FileTree: LeaveBoard $id');
    _bridge.send(FileTreeCommand.leaveBoard(id: id));
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    _bridge.dispose();
    super.dispose();
  }
}
