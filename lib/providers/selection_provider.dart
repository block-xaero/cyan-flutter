// providers/selection_provider.dart
// Tracks current selection in the file tree (group, workspace, board)

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selection state - tracks what's currently selected in the tree
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

  /// Breadcrumb path string (e.g., "Group › Workspace › Board")
  String get breadcrumb {
    final parts = <String>[];
    if (selectedGroupName != null) parts.add(selectedGroupName!);
    if (selectedWorkspaceName != null) parts.add(selectedWorkspaceName!);
    if (selectedBoardName != null) parts.add(selectedBoardName!);
    return parts.isEmpty ? 'No selection' : parts.join(' › ');
  }

  /// Whether anything is selected
  bool get isEmpty => selectedGroupId == null && selectedWorkspaceId == null && selectedBoardId == null;

  /// Whether chat can be opened (need at least workspace level)
  bool get canOpenChat => selectedWorkspaceId != null || selectedGroupId != null;

  /// Copy with new values
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
      selectedBoardId: clearBoard ? null : (selectedBoardId ?? this.selectedBoardId),
      selectedBoardName: clearBoard ? null : (selectedBoardName ?? this.selectedBoardName),
    );
  }

  /// Clear all selection
  static const empty = SelectionState();
}

/// Selection provider
final selectionProvider = StateNotifierProvider<SelectionNotifier, SelectionState>((ref) {
  return SelectionNotifier();
});

class SelectionNotifier extends StateNotifier<SelectionState> {
  SelectionNotifier() : super(const SelectionState());

  /// Select a group (positional: id, name)
  void selectGroup(String id, String name) {
    state = SelectionState(selectedGroupId: id, selectedGroupName: name);
  }

  /// Select a workspace - all named parameters
  void selectWorkspace({
    required String workspaceId,
    required String workspaceName,
    String? groupId,
    String? groupName,
  }) {
    state = SelectionState(
      selectedGroupId: groupId ?? state.selectedGroupId,
      selectedGroupName: groupName ?? state.selectedGroupName,
      selectedWorkspaceId: workspaceId,
      selectedWorkspaceName: workspaceName,
    );
  }

  /// Select a board - all named parameters
  void selectBoard({
    required String boardId,
    required String boardName,
    String? workspaceId,
    String? workspaceName,
    String? groupId,
    String? groupName,
  }) {
    state = SelectionState(
      selectedGroupId: groupId ?? state.selectedGroupId,
      selectedGroupName: groupName ?? state.selectedGroupName,
      selectedWorkspaceId: workspaceId ?? state.selectedWorkspaceId,
      selectedWorkspaceName: workspaceName ?? state.selectedWorkspaceName,
      selectedBoardId: boardId,
      selectedBoardName: boardName,
    );
  }

  /// Create a board in the selected workspace (just name, generates ID)
  void createBoard(String name) {
    final boardId = 'board_${DateTime.now().millisecondsSinceEpoch}';
    state = state.copyWith(
      selectedBoardId: boardId,
      selectedBoardName: name,
    );
  }

  /// Clear board selection (keep workspace)
  void clearBoard() {
    state = SelectionState(
      selectedGroupId: state.selectedGroupId,
      selectedGroupName: state.selectedGroupName,
      selectedWorkspaceId: state.selectedWorkspaceId,
      selectedWorkspaceName: state.selectedWorkspaceName,
    );
  }

  /// Clear workspace selection (keep group)
  void clearWorkspace() {
    state = SelectionState(
      selectedGroupId: state.selectedGroupId,
      selectedGroupName: state.selectedGroupName,
    );
  }

  /// Clear all selection
  void clearAll() {
    state = const SelectionState();
  }

  /// Set full selection at once
  void setSelection({
    String? groupId,
    String? groupName,
    String? workspaceId,
    String? workspaceName,
    String? boardId,
    String? boardName,
  }) {
    state = SelectionState(
      selectedGroupId: groupId,
      selectedGroupName: groupName,
      selectedWorkspaceId: workspaceId,
      selectedWorkspaceName: workspaceName,
      selectedBoardId: boardId,
      selectedBoardName: boardName,
    );
  }
}
