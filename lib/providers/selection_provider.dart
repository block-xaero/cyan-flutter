// providers/selection_provider.dart
// Selection state - selected group, workspace, board

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'file_tree_provider.dart';

class SelectionState {
  final String? selectedGroupId;
  final String? selectedGroupName;
  final String? selectedWorkspaceId;
  final String? selectedWorkspaceName;
  final String? selectedBoardId;
  final String? selectedBoardName;
  
  const SelectionState({
    this.selectedGroupId,
    this.selectedGroupName,
    this.selectedWorkspaceId,
    this.selectedWorkspaceName,
    this.selectedBoardId,
    this.selectedBoardName,
  });
  
  SelectionState copyWith({
    String? selectedGroupId,
    String? selectedGroupName,
    String? selectedWorkspaceId,
    String? selectedWorkspaceName,
    String? selectedBoardId,
    String? selectedBoardName,
    bool clearWorkspace = false,
    bool clearBoard = false,
  }) {
    return SelectionState(
      selectedGroupId: selectedGroupId ?? this.selectedGroupId,
      selectedGroupName: selectedGroupName ?? this.selectedGroupName,
      selectedWorkspaceId: clearWorkspace ? null : (selectedWorkspaceId ?? this.selectedWorkspaceId),
      selectedWorkspaceName: clearWorkspace ? null : (selectedWorkspaceName ?? this.selectedWorkspaceName),
      selectedBoardId: clearBoard || clearWorkspace ? null : (selectedBoardId ?? this.selectedBoardId),
      selectedBoardName: clearBoard || clearWorkspace ? null : (selectedBoardName ?? this.selectedBoardName),
    );
  }
}

final selectionProvider = StateNotifierProvider<SelectionNotifier, SelectionState>((ref) {
  return SelectionNotifier(ref);
});

class SelectionNotifier extends StateNotifier<SelectionState> {
  final Ref _ref;
  
  SelectionNotifier(this._ref) : super(const SelectionState());
  
  void selectGroup(String id, String name) {
    state = SelectionState(
      selectedGroupId: id,
      selectedGroupName: name,
    );
  }
  
  void selectWorkspace({
    required String groupId,
    required String workspaceId,
    required String workspaceName,
  }) {
    state = state.copyWith(
      selectedGroupId: groupId,
      selectedWorkspaceId: workspaceId,
      selectedWorkspaceName: workspaceName,
      clearBoard: true,
    );
  }
  
  void selectBoard({
    required String groupId,
    required String workspaceId,
    required String workspaceName,
    required String boardId,
    required String boardName,
  }) {
    state = SelectionState(
      selectedGroupId: groupId,
      selectedGroupName: state.selectedGroupName,
      selectedWorkspaceId: workspaceId,
      selectedWorkspaceName: workspaceName,
      selectedBoardId: boardId,
      selectedBoardName: boardName,
    );
  }
  
  void clearBoard() {
    state = state.copyWith(clearBoard: true);
  }
  
  void clearSelection() {
    state = const SelectionState();
  }
  
  /// Create a new group via file_tree_provider
  void createGroup(String name) {
    _ref.read(fileTreeProvider.notifier).createGroup(name);
  }
  
  /// Create a new workspace in current group
  void createWorkspace(String name) {
    if (state.selectedGroupId == null) return;
    _ref.read(fileTreeProvider.notifier).createWorkspace(state.selectedGroupId!, name);
  }
  
  /// Create a new board in current workspace
  void createBoard(String name) {
    if (state.selectedWorkspaceId == null) return;
    _ref.read(fileTreeProvider.notifier).createBoard(state.selectedWorkspaceId!, name);
  }
}
