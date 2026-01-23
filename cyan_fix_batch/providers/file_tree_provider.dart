// providers/file_tree_provider.dart
// File tree state - groups, workspaces, boards from FFI
// Matches Swift's FileTreeViewModel pattern

import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ffi/cyan_ffi.dart';
import '../models/tree_item.dart';

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

final fileTreeProvider = StateNotifierProvider<FileTreeNotifier, FileTreeState>((ref) {
  return FileTreeNotifier();
});

class FileTreeNotifier extends StateNotifier<FileTreeState> {
  Timer? _pollTimer;
  final _ffi = CyanFFI.instance;
  
  FileTreeNotifier() : super(const FileTreeState(isLoading: true)) {
    _init();
  }
  
  void _init() async {
    // Wait for backend to be ready (max 5 seconds)
    var attempts = 0;
    while (!_ffi.isReady && attempts < 50) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }
    
    if (!_ffi.isReady) {
      state = state.copyWith(
        isLoading: false,
        error: 'Backend not ready',
      );
      return;
    }
    
    // Seed demo data if empty, then request snapshot
    _ffi.seedDemoIfEmpty();
    await Future.delayed(const Duration(milliseconds: 200));
    _ffi.requestSnapshot();
    
    // Start polling for events
    _startPolling();
  }
  
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _pollEvents();
    });
  }
  
  void _pollEvents() {
    final json = _ffi.pollEvents('file_tree');
    if (json == null || json.isEmpty) return;
    
    _handleEvent(json);
  }
  
  void _handleEvent(String json) {
    try {
      final event = jsonDecode(json) as Map<String, dynamic>;
      final type = event['type'] as String?;
      
      switch (type) {
        case 'TreeLoaded':
          final treeJson = event['data'] as String? ?? '{}';
          _handleTreeLoaded(treeJson);
          break;
          
        case 'Network':
          final data = event['data'] as Map<String, dynamic>?;
          if (data != null) {
            _handleNetworkEvent(data);
          }
          break;
          
        case 'GroupDeleted':
        case 'GroupLeft':
          final id = event['id'] as String?;
          if (id != null) _removeGroup(id);
          break;
          
        case 'WorkspaceDeleted':
        case 'WorkspaceLeft':
          final id = event['id'] as String?;
          if (id != null) _removeWorkspace(id);
          break;
          
        case 'BoardDeleted':
        case 'BoardLeft':
          final id = event['id'] as String?;
          if (id != null) _removeBoard(id);
          break;
          
        case 'Error':
          final message = event['message'] as String?;
          state = state.copyWith(error: message);
          break;
      }
    } catch (e) {
      print('⚠️ FileTreeNotifier._handleEvent error: $e');
    }
  }
  
  void _handleTreeLoaded(String treeJson) {
    final snapshot = TreeSnapshot.fromJson(treeJson);
    final tree = snapshot.buildTree();
    
    state = state.copyWith(
      groups: tree,
      isLoading: false,
      error: null,
    );
  }
  
  void _handleNetworkEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    
    switch (type) {
      case 'GroupCreated':
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
  // PUBLIC METHODS (called by UI)
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
    state = state.copyWith(isLoading: true);
    _ffi.requestSnapshot();
  }
  
  /// Create a new group
  void createGroup(String name) {
    _ffi.createGroup(name);
  }
  
  /// Create a new workspace in a group
  void createWorkspace(String groupId, String name) {
    _ffi.createWorkspace(groupId, name);
  }
  
  /// Create a new board in a workspace
  void createBoard(String workspaceId, String name) {
    _ffi.createBoard(workspaceId, name);
  }
  
  /// Rename a group
  void renameGroup(String id, String name) {
    _ffi.renameGroup(id, name);
  }
  
  /// Rename a workspace
  void renameWorkspaceById(String id, String name) {
    _ffi.renameWorkspace(id, name);
  }
  
  /// Rename a board
  void renameBoardById(String id, String name) {
    _ffi.renameBoard(id, name);
  }
  
  /// Delete a group
  void deleteGroup(String id) {
    _ffi.deleteGroup(id);
  }
  
  /// Delete a workspace
  void deleteWorkspace(String id) {
    _ffi.deleteWorkspace(id);
  }
  
  /// Delete a board
  void deleteBoard(String id) {
    _ffi.deleteBoard(id);
  }
  
  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
