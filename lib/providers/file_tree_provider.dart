// providers/file_tree_provider.dart
// File tree state - groups, workspaces, boards from FFI
// Matches Swift's FileTreeViewModel pattern

import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ffi/component_bridge.dart';
import '../models/tree_item.dart';

class FileTreeState {
  final List<TreeGroup> groups;
  final Set<String> expandedGroups;
  final Set<String> expandedWorkspaces;
  final bool isLoading;
  final String? error;
  
  // Inline editing state
  final String? editingItemId;
  final String editingText;

  const FileTreeState({
    this.groups = const [],
    this.expandedGroups = const {},
    this.expandedWorkspaces = const {},
    this.isLoading = false,
    this.error,
    this.editingItemId,
    this.editingText = '',
  });

  FileTreeState copyWith({
    List<TreeGroup>? groups,
    Set<String>? expandedGroups,
    Set<String>? expandedWorkspaces,
    bool? isLoading,
    String? error,
    String? editingItemId,
    String? editingText,
    bool clearEditing = false,
  }) {
    return FileTreeState(
      groups: groups ?? this.groups,
      expandedGroups: expandedGroups ?? this.expandedGroups,
      expandedWorkspaces: expandedWorkspaces ?? this.expandedWorkspaces,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      editingItemId: clearEditing ? null : (editingItemId ?? this.editingItemId),
      editingText: clearEditing ? '' : (editingText ?? this.editingText),
    );
  }
}

final fileTreeProvider = StateNotifierProvider<FileTreeNotifier, FileTreeState>((ref) {
  return FileTreeNotifier();
});

class FileTreeNotifier extends StateNotifier<FileTreeState> {
  final _bridge = FileTreeBridge();
  StreamSubscription<FileTreeEvent>? _subscription;

  FileTreeNotifier() : super(const FileTreeState(isLoading: true)) {
    _init();
  }

  void _init() async {
    _bridge.start();
    _subscription = _bridge.events.listen(_handleEvent);

    // Wait a bit then request initial data
    await Future.delayed(const Duration(milliseconds: 300));
    _bridge.send(FileTreeCommand.seedDemoIfEmpty());
    await Future.delayed(const Duration(milliseconds: 200));
    _bridge.send(FileTreeCommand.snapshot());
  }

  void _handleEvent(FileTreeEvent event) {
    print('🌲 FileTreeEvent: ${event.type}');
    
    if (event.isTreeLoaded) {
      _handleTreeLoaded(event);
    } else if (event.isGroupCreated) {
      _handleGroupCreated(event);
    } else if (event.isGroupRenamed) {
      _handleGroupRenamed(event);
    } else if (event.isGroupDeleted) {
      _removeGroup(event.id ?? '');
    } else if (event.isWorkspaceCreated) {
      _handleWorkspaceCreated(event);
    } else if (event.isBoardCreated) {
      _handleBoardCreated(event);
    } else if (event.isError) {
      state = state.copyWith(error: event.errorMessage, isLoading: false);
    } else if (event.type == 'Network') {
      _handleNetworkEvent(event.data);
    }
  }

  void _handleTreeLoaded(FileTreeEvent event) {
    // TreeLoaded event has 'data' field which is a JSON string
    final treeJson = event.data['data'] as String? ?? '{}';
    final snapshot = TreeSnapshot.fromJson(treeJson);
    final tree = snapshot.buildTree();
    
    print('🌲 Tree loaded: ${tree.length} groups');
    state = state.copyWith(groups: tree, isLoading: false, error: null);
  }

  void _handleNetworkEvent(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    print('🌐 Network event: $type');
    
    switch (type) {
      case 'GroupCreated':
        final group = TreeGroup.fromJson(data);
        state = state.copyWith(groups: [...state.groups, group]);
        break;
        
      case 'GroupRenamed':
        final id = data['id'] as String?;
        final name = data['name'] as String?;
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
        final id = data['id'] as String?;
        if (id != null) _removeGroup(id);
        break;
        
      case 'WorkspaceCreated':
        final ws = TreeWorkspace.fromJson(data);
        state = state.copyWith(
          groups: state.groups.map((g) {
            if (g.id == ws.groupId) {
              return g.copyWith(workspaces: [...g.workspaces, ws]);
            }
            return g;
          }).toList(),
        );
        break;
        
      case 'WorkspaceDeleted':
      case 'WorkspaceDissolved':
        final id = data['id'] as String?;
        if (id != null) _removeWorkspace(id);
        break;
        
      case 'BoardCreated':
        final board = TreeBoard.fromJson(data);
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
        
      case 'BoardDeleted':
      case 'BoardDissolved':
        final id = data['id'] as String?;
        if (id != null) _removeBoard(id);
        break;
    }
  }

  void _handleGroupCreated(FileTreeEvent event) {
    final group = TreeGroup(
      id: event.data['id'] as String? ?? '',
      name: event.data['name'] as String? ?? 'New Group',
      icon: event.data['icon'] as String? ?? 'folder.fill',
      color: event.data['color'] as String? ?? '#66D9EF',
      createdAt: event.data['created_at'] as int? ?? 0,
      workspaces: [],
      peerCount: 0,
    );
    print('🌲 Group created: ${group.name}');
    state = state.copyWith(groups: [...state.groups, group]);
  }

  void _handleGroupRenamed(FileTreeEvent event) {
    final id = event.data['id'] as String?;
    final name = event.data['name'] as String?;
    if (id == null || name == null) return;

    state = state.copyWith(
      groups: state.groups.map((g) {
        if (g.id == id) return g.copyWith(name: name);
        return g;
      }).toList(),
    );
  }

  void _handleWorkspaceCreated(FileTreeEvent event) {
    final groupId = event.data['group_id'] as String?;
    if (groupId == null) return;

    final ws = TreeWorkspace(
      id: event.data['id'] as String? ?? '',
      groupId: groupId,
      name: event.data['name'] as String? ?? 'New Workspace',
      createdAt: event.data['created_at'] as int? ?? 0,
      boards: [],
    );

    state = state.copyWith(
      groups: state.groups.map((g) {
        if (g.id == groupId) {
          return g.copyWith(workspaces: [...g.workspaces, ws]);
        }
        return g;
      }).toList(),
    );
  }

  void _handleBoardCreated(FileTreeEvent event) {
    final workspaceId = event.data['workspace_id'] as String?;
    if (workspaceId == null) return;

    final board = TreeBoard(
      id: event.data['id'] as String? ?? '',
      workspaceId: workspaceId,
      name: event.data['name'] as String? ?? 'New Board',
      createdAt: event.data['created_at'] as int? ?? 0,
      boardType: event.data['board_type'] as String? ?? 'canvas',
      hasUnread: false,
      isPinned: false,
      rating: 0,
    );

    state = state.copyWith(
      groups: state.groups.map((g) {
        return g.copyWith(
          workspaces: g.workspaces.map((ws) {
            if (ws.id == workspaceId) {
              return ws.copyWith(boards: [...ws.boards, board]);
            }
            return ws;
          }).toList(),
        );
      }).toList(),
    );
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

  // CRUD - Groups
  void createGroup(String name) {
    print('🌲 Creating group: $name');
    _bridge.send(FileTreeCommand.createGroup(name: name));
  }

  void renameGroup(String id, String name) {
    // Optimistic update
    state = state.copyWith(
      groups: state.groups.map((g) {
        if (g.id == id) return g.copyWith(name: name);
        return g;
      }).toList(),
      clearEditing: true,
    );
    _bridge.send(FileTreeCommand.renameGroup(id: id, name: name));
  }

  void deleteGroup(String id) {
    _bridge.send(FileTreeCommand.deleteGroup(id: id));
    _removeGroup(id); // Optimistic
  }

  void leaveGroup(String id) {
    _bridge.send(FileTreeCommand.leaveGroup(id: id));
    _removeGroup(id); // Optimistic
  }

  // CRUD - Workspaces
  void createWorkspace(String groupId, String name) {
    print('🌲 Creating workspace in $groupId: $name');
    _bridge.send(FileTreeCommand.createWorkspace(groupId: groupId, name: name));
  }

  void renameWorkspaceById(String id, String name) {
    // Optimistic update
    state = state.copyWith(
      groups: state.groups.map((g) {
        return g.copyWith(
          workspaces: g.workspaces.map((ws) {
            if (ws.id == id) return ws.copyWith(name: name);
            return ws;
          }).toList(),
        );
      }).toList(),
      clearEditing: true,
    );
    _bridge.send(FileTreeCommand.renameWorkspace(id: id, name: name));
  }

  void deleteWorkspace(String id) {
    _bridge.send(FileTreeCommand.deleteWorkspace(id: id));
    _removeWorkspace(id); // Optimistic
  }

  void leaveWorkspace(String id) {
    _bridge.send(FileTreeCommand.leaveWorkspace(id: id));
    _removeWorkspace(id); // Optimistic
  }

  // CRUD - Boards
  void createBoard(String workspaceId, String name) {
    print('🌲 Creating board in $workspaceId: $name');
    _bridge.send(FileTreeCommand.createBoard(workspaceId: workspaceId, name: name));
  }

  void renameBoardById(String id, String name) {
    // Optimistic update
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
      clearEditing: true,
    );
    _bridge.send(FileTreeCommand.renameBoard(id: id, name: name));
  }

  void deleteBoard(String id) {
    _bridge.send(FileTreeCommand.deleteBoard(id: id));
    _removeBoard(id); // Optimistic
  }

  void leaveBoard(String id) {
    _bridge.send(FileTreeCommand.leaveBoard(id: id));
    _removeBoard(id); // Optimistic
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INLINE EDITING
  // ═══════════════════════════════════════════════════════════════════════════

  void startEditing(String itemId, String currentName) {
    state = state.copyWith(
      editingItemId: itemId,
      editingText: currentName,
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
        renameWorkspaceById(id, name);
        break;
      case 'board':
        renameBoardById(id, name);
        break;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _bridge.dispose();
    super.dispose();
  }
}
