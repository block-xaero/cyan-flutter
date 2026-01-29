// providers/board_grid_provider.dart
// Board grid provider - loads boards with full metadata via BoardGridBridge
// Matches Swift's BoardGridViewModel pattern

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ffi/component_bridge.dart';

// ============================================================================
// STATE
// ============================================================================

class BoardGridState {
  final List<BoardGridItem> boards;
  final bool isLoading;
  final String? error;
  final String? scopeGroupId;
  final String? scopeWorkspaceId;
  
  const BoardGridState({
    this.boards = const [],
    this.isLoading = false,
    this.error,
    this.scopeGroupId,
    this.scopeWorkspaceId,
  });
  
  BoardGridState copyWith({
    List<BoardGridItem>? boards,
    bool? isLoading,
    String? error,
    String? scopeGroupId,
    String? scopeWorkspaceId,
    bool clearError = false,
  }) {
    return BoardGridState(
      boards: boards ?? this.boards,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      scopeGroupId: scopeGroupId ?? this.scopeGroupId,
      scopeWorkspaceId: scopeWorkspaceId ?? this.scopeWorkspaceId,
    );
  }
  
  /// Get boards filtered/sorted for display
  List<BoardGridItem> get sortedBoards {
    final sorted = [...boards];
    // Pinned first, then by last accessed
    sorted.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final aTime = a.lastAccessed ?? a.createdAt;
      final bTime = b.lastAccessed ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    return sorted;
  }
  
  List<BoardGridItem> get pinnedBoards => boards.where((b) => b.isPinned).toList();
  List<BoardGridItem> get recentBoards {
    final sorted = [...boards];
    sorted.sort((a, b) {
      final aTime = a.lastAccessed ?? a.createdAt;
      final bTime = b.lastAccessed ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    return sorted.take(10).toList();
  }
}

// ============================================================================
// NOTIFIER
// ============================================================================

class BoardGridNotifier extends StateNotifier<BoardGridState> {
  final BoardGridBridge _bridge;
  StreamSubscription? _subscription;
  
  BoardGridNotifier() : _bridge = BoardGridBridge(), super(const BoardGridState()) {
    _setup();
  }
  
  void _setup() {
    _bridge.start();
    _subscription = _bridge.events.listen(_handleEvent);
  }
  
  void _handleEvent(BoardGridEvent event) {
    print('📊 BoardGrid event: ${event.type}');
    
    if (event.isBoardsLoaded) {
      state = state.copyWith(
        boards: event.boards,
        isLoading: false,
        clearError: true,
      );
    } else if (event.isBoardCreated) {
      final newBoards = [...state.boards];
      final board = event.boards.isNotEmpty ? event.boards.first : null;
      if (board != null) {
        newBoards.add(board);
        state = state.copyWith(boards: newBoards);
      }
    } else if (event.isBoardDeleted) {
      final id = event.data['id'] as String?;
      if (id != null) {
        state = state.copyWith(
          boards: state.boards.where((b) => b.id != id).toList(),
        );
      }
    } else if (event.isBoardRenamed) {
      final id = event.data['id'] as String?;
      final name = event.data['name'] as String?;
      if (id != null && name != null) {
        state = state.copyWith(
          boards: state.boards.map((b) {
            if (b.id == id) {
              return BoardGridItem(
                id: b.id,
                workspaceId: b.workspaceId,
                groupId: b.groupId,
                name: name,
                createdAt: b.createdAt,
                elementCount: b.elementCount,
                isPinned: b.isPinned,
                labels: b.labels,
                rating: b.rating,
                lastAccessed: b.lastAccessed,
              );
            }
            return b;
          }).toList(),
        );
      }
    } else if (event.isBoardPinChanged) {
      _updateBoardField(event.data['board_id'] as String?, (b) => BoardGridItem(
        id: b.id,
        workspaceId: b.workspaceId,
        groupId: b.groupId,
        name: b.name,
        createdAt: b.createdAt,
        elementCount: b.elementCount,
        isPinned: event.data['is_pinned'] as bool? ?? b.isPinned,
        labels: b.labels,
        rating: b.rating,
        lastAccessed: b.lastAccessed,
      ));
    } else if (event.isBoardRatingChanged) {
      _updateBoardField(event.data['board_id'] as String?, (b) => BoardGridItem(
        id: b.id,
        workspaceId: b.workspaceId,
        groupId: b.groupId,
        name: b.name,
        createdAt: b.createdAt,
        elementCount: b.elementCount,
        isPinned: b.isPinned,
        labels: b.labels,
        rating: event.data['rating'] as int? ?? b.rating,
        lastAccessed: b.lastAccessed,
      ));
    } else if (event.isBoardLabelsChanged) {
      _updateBoardField(event.data['board_id'] as String?, (b) => BoardGridItem(
        id: b.id,
        workspaceId: b.workspaceId,
        groupId: b.groupId,
        name: b.name,
        createdAt: b.createdAt,
        elementCount: b.elementCount,
        isPinned: b.isPinned,
        labels: (event.data['labels'] as List?)?.cast<String>() ?? b.labels,
        rating: b.rating,
        lastAccessed: b.lastAccessed,
      ));
    }
  }
  
  void _updateBoardField(String? id, BoardGridItem Function(BoardGridItem) updater) {
    if (id == null) return;
    state = state.copyWith(
      boards: state.boards.map((b) => b.id == id ? updater(b) : b).toList(),
    );
  }
  
  // ============================================================================
  // PUBLIC ACTIONS
  // ============================================================================
  
  /// Load all boards
  void loadAllBoards() {
    state = state.copyWith(isLoading: true, scopeGroupId: null, scopeWorkspaceId: null);
    _bridge.send(BoardGridCommand.loadAll());
  }
  
  /// Load boards for a specific group
  void loadBoardsForGroup(String groupId) {
    state = state.copyWith(isLoading: true, scopeGroupId: groupId, scopeWorkspaceId: null);
    _bridge.send(BoardGridCommand.loadForGroup(groupId));
  }
  
  /// Load boards for a specific workspace
  void loadBoardsForWorkspace(String workspaceId) {
    state = state.copyWith(isLoading: true, scopeWorkspaceId: workspaceId);
    _bridge.send(BoardGridCommand.loadForWorkspace(workspaceId));
  }
  
  /// Toggle pin status
  void togglePin(String boardId) {
    final board = state.boards.firstWhere((b) => b.id == boardId, orElse: () => throw Exception('Board not found'));
    _bridge.send(BoardGridCommand.setPin(boardId, !board.isPinned));
    // Optimistic update
    _updateBoardField(boardId, (b) => BoardGridItem(
      id: b.id,
      workspaceId: b.workspaceId,
      groupId: b.groupId,
      name: b.name,
      createdAt: b.createdAt,
      elementCount: b.elementCount,
      isPinned: !b.isPinned,
      labels: b.labels,
      rating: b.rating,
      lastAccessed: b.lastAccessed,
    ));
  }
  
  /// Set rating (0-5)
  void setRating(String boardId, int rating) {
    _bridge.send(BoardGridCommand.setRating(boardId, rating.clamp(0, 5)));
    // Optimistic update
    _updateBoardField(boardId, (b) => BoardGridItem(
      id: b.id,
      workspaceId: b.workspaceId,
      groupId: b.groupId,
      name: b.name,
      createdAt: b.createdAt,
      elementCount: b.elementCount,
      isPinned: b.isPinned,
      labels: b.labels,
      rating: rating.clamp(0, 5),
      lastAccessed: b.lastAccessed,
    ));
  }
  
  /// Set labels
  void setLabels(String boardId, List<String> labels) {
    _bridge.send(BoardGridCommand.setLabels(boardId, labels));
    // Optimistic update
    _updateBoardField(boardId, (b) => BoardGridItem(
      id: b.id,
      workspaceId: b.workspaceId,
      groupId: b.groupId,
      name: b.name,
      createdAt: b.createdAt,
      elementCount: b.elementCount,
      isPinned: b.isPinned,
      labels: labels,
      rating: b.rating,
      lastAccessed: b.lastAccessed,
    ));
  }
  
  /// Add a label
  void addLabel(String boardId, String label) {
    final board = state.boards.firstWhere((b) => b.id == boardId, orElse: () => throw Exception('Board not found'));
    if (!board.labels.contains(label)) {
      setLabels(boardId, [...board.labels, label]);
    }
  }
  
  /// Remove a label
  void removeLabel(String boardId, String label) {
    final board = state.boards.firstWhere((b) => b.id == boardId, orElse: () => throw Exception('Board not found'));
    setLabels(boardId, board.labels.where((l) => l != label).toList());
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    _bridge.dispose();
    super.dispose();
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

/// Main board grid provider
final boardGridProvider = StateNotifierProvider<BoardGridNotifier, BoardGridState>((ref) {
  return BoardGridNotifier();
});

/// Convenience provider for sorted boards
final sortedBoardsProvider = Provider<List<BoardGridItem>>((ref) {
  return ref.watch(boardGridProvider).sortedBoards;
});

/// Convenience provider for pinned boards
final pinnedBoardsProvider = Provider<List<BoardGridItem>>((ref) {
  return ref.watch(boardGridProvider).pinnedBoards;
});
