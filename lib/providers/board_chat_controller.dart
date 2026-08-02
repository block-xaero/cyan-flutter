// providers/board_chat_controller.dart
//
// The board's CHAT LANE, ported from `ChatPanelViewModel`
// (ViewModels/ChatPanelViewModel.swift). Every read and write goes through the
// `CyanBackend` seam (`loadChat` / `sendChat` / `deleteChat`), so the whole lane
// is Tier-1 drivable against FakeCyanBackend with no dylib.
//
// Two invariants carried over from the Swift view-model:
//
//   • BOARD SCOPE is the whole address. Chat is board-scoped on the wire —
//     there is no group or workspace transcript — so a lane with no board id
//     has nothing to read and refuses to send rather than guessing a target.
//     The Swift VM guards the same way (`guard let targetScopeId = chatScopeId`).
//   • The engine is the truth. Every write is followed by a re-read of the
//     transcript, so what the lane renders is what was persisted rather than a
//     shadow copy of the composer's draft.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/cyan_backend.dart';
import '../ffi/parity_models.dart';
import 'cyan_backend_provider.dart';

@immutable
class BoardChatState {
  final bool loading;

  /// The transcript could not be read — the lane says so rather than showing an
  /// empty thread, which would read as "nobody has said anything".
  final String? error;

  /// The board's messages, oldest first (the order the transcript scrolls).
  final List<ChatMessage> messages;

  const BoardChatState({
    this.loading = true,
    this.error,
    this.messages = const [],
  });

  BoardChatState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    List<ChatMessage>? messages,
  }) {
    return BoardChatState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      messages: messages ?? this.messages,
    );
  }

  bool get isEmpty => messages.isEmpty;

  ChatMessage? byId(String id) {
    for (final m in messages) {
      if (m.id == id) return m;
    }
    return null;
  }
}

/// The chat lane for one board. Keyed by board id because a message is anchored
/// on its board — another board's lane is a different transcript.
final boardChatControllerProvider = StateNotifierProvider.autoDispose
    .family<BoardChatController, BoardChatState, String>((ref, boardId) {
  final controller = BoardChatController(
    backend: ref.watch(cyanBackendProvider),
    boardId: boardId,
  );
  controller.load();
  return controller;
});

class BoardChatController extends StateNotifier<BoardChatState> {
  final CyanBackend _backend;
  final String boardId;

  BoardChatController({
    required CyanBackend backend,
    required this.boardId,
  })  : _backend = backend,
        super(const BoardChatState());

  /// True when this lane has a board to talk to. A lane without one cannot
  /// send: the board id IS the chat scope, so there is no fallback target.
  bool get hasScope => boardId.trim().isNotEmpty;

  /// Read the board's transcript off the engine. This is also the RELOAD every
  /// write ends with, so a message only survives it because the engine kept it,
  /// never because this object remembered it.
  Future<void> load() async {
    if (!hasScope) {
      if (mounted) {
        state = state.copyWith(
            loading: false, messages: const [], clearError: true);
      }
      return;
    }
    try {
      final messages = await _backend.loadChat(boardId);
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        clearError: true,
        messages: messages,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        error: "Could not read this board's chat: $e",
      );
    }
  }

  /// Send [text] to THIS board. Returns whether anything was sent.
  ///
  /// Whitespace-only is not a message and never reaches the mesh. A lane with
  /// no board scope refuses outright rather than sending to a guessed target —
  /// the same guard the Swift composer makes.
  Future<bool> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !hasScope) return false;
    try {
      final sent = await _backend.sendChat(boardId, trimmed);
      // The seam refuses what it will not file and says so by answering null;
      // a refusal is not an error, but it is also not a send.
      if (sent == null) return false;
    } catch (e) {
      if (mounted) state = state.copyWith(error: 'Failed to send: $e');
      return false;
    }
    await load();
    return true;
  }

  /// Delete one message. The engine soft-deletes and gossips a tombstone, so
  /// the lane is re-read rather than having the row spliced out locally.
  Future<bool> delete(String messageId) async {
    if (messageId.isEmpty) return false;
    try {
      await _backend.deleteChat(messageId);
    } catch (e) {
      if (mounted) state = state.copyWith(error: 'Failed to delete: $e');
      return false;
    }
    await load();
    return true;
  }
}
