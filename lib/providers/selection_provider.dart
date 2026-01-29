// providers/selection_provider.dart
// Tracks current selection state across the app

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tree_item.dart';

/// Current selection state
class SelectionState {
  final String? groupId;
  final String? groupName;
  final String? workspaceId;
  final String? workspaceName;
  final String? boardId;
  final String? boardName;
  final BoardFace? boardFace;
  
  const SelectionState({
    this.groupId,
    this.groupName,
    this.workspaceId,
    this.workspaceName,
    this.boardId,
    this.boardName,
    this.boardFace,
  });
  
  static const empty = SelectionState();
  
  SelectionState copyWith({
    String? groupId,
    String? groupName,
    String? workspaceId,
    String? workspaceName,
    String? boardId,
    String? boardName,
    BoardFace? boardFace,
    bool clearGroup = false,
    bool clearWorkspace = false,
    bool clearBoard = false,
  }) {
    return SelectionState(
      groupId: clearGroup ? null : (groupId ?? this.groupId),
      groupName: clearGroup ? null : (groupName ?? this.groupName),
      workspaceId: clearWorkspace ? null : (workspaceId ?? this.workspaceId),
      workspaceName: clearWorkspace ? null : (workspaceName ?? this.workspaceName),
      boardId: clearBoard ? null : (boardId ?? this.boardId),
      boardName: clearBoard ? null : (boardName ?? this.boardName),
      boardFace: clearBoard ? null : (boardFace ?? this.boardFace),
    );
  }
  
  /// Breadcrumb for status bar
  String get breadcrumb {
    final parts = <String>[];
    if (groupName != null) parts.add(groupName!);
    if (workspaceName != null) parts.add(workspaceName!);
    if (boardName != null) parts.add(boardName!);
    return parts.join(' › ');
  }
  
  bool get isEmpty => groupId == null && workspaceId == null && boardId == null;
  bool get hasGroup => groupId != null;
  bool get hasWorkspace => workspaceId != null;
  bool get hasBoard => boardId != null;
  
  // Aliases for compatibility with file_tree_widget
  String? get selectedGroupId => groupId;
  String? get selectedWorkspaceId => workspaceId;
  String? get selectedBoardId => boardId;
  
  /// Can open chat (requires workspace)
  bool get canOpenChat => workspaceId != null;
  
  /// Chat scope ID (board > workspace > group)
  String? get chatScopeId => boardId ?? workspaceId ?? groupId;
}

/// Provider for selection state
final selectionProvider = StateNotifierProvider<SelectionNotifier, SelectionState>((ref) {
  return SelectionNotifier();
});

class SelectionNotifier extends StateNotifier<SelectionState> {
  SelectionNotifier() : super(SelectionState.empty);
  
  void selectGroup(String id, String name) {
    state = SelectionState(
      groupId: id,
      groupName: name,
    );
  }
  
  void selectWorkspace(String id, String name, String groupId, String groupName) {
    state = SelectionState(
      groupId: groupId,
      groupName: groupName,
      workspaceId: id,
      workspaceName: name,
    );
  }
  
  // Named parameter version for compatibility
  void selectWorkspaceNamed({
    required String workspaceId,
    required String workspaceName,
    required String groupId,
    String? groupName,
  }) {
    state = SelectionState(
      groupId: groupId,
      groupName: groupName,
      workspaceId: workspaceId,
      workspaceName: workspaceName,
    );
  }
  
  void selectBoard(TreeBoard board, String workspaceName, String groupId, String groupName) {
    state = SelectionState(
      groupId: groupId,
      groupName: groupName,
      workspaceId: board.workspaceId,
      workspaceName: workspaceName,
      boardId: board.id,
      boardName: board.name,
      boardFace: board.face,
    );
  }
  
  // Named parameter version for compatibility
  void selectBoardNamed({
    required String boardId,
    required String boardName,
    required String workspaceId,
    required String groupId,
    String? workspaceName,
    String? groupName,
  }) {
    state = SelectionState(
      groupId: groupId,
      groupName: groupName,
      workspaceId: workspaceId,
      workspaceName: workspaceName,
      boardId: boardId,
      boardName: boardName,
    );
  }
  
  void clearSelection() {
    state = SelectionState.empty;
  }
  
  void clearBoard() {
    state = state.copyWith(clearBoard: true);
  }
  
  void clearWorkspace() {
    state = state.copyWith(clearWorkspace: true, clearBoard: true);
  }
}

/// Convenience provider for just the selected board ID
final selectedBoardIdProvider = Provider<String?>((ref) {
  return ref.watch(selectionProvider).boardId;
});

/// Convenience provider for just the selected workspace ID
final selectedWorkspaceIdProvider = Provider<String?>((ref) {
  return ref.watch(selectionProvider).workspaceId;
});

/// Convenience provider for just the selected group ID
final selectedGroupIdProvider = Provider<String?>((ref) {
  return ref.watch(selectionProvider).groupId;
});
