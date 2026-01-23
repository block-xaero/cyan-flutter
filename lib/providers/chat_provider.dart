// providers/chat_provider.dart
// Chat state - messages for a workspace
// Uses ComponentBridge pattern matching Swift's ChatViewModel

import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ffi/component_bridge.dart';
import '../models/chat_message.dart';

// ═══════════════════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════════════════

class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;
  final String? currentWorkspaceId;
  
  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.currentWorkspaceId,
  });
  
  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? error,
    String? currentWorkspaceId,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentWorkspaceId: currentWorkspaceId ?? this.currentWorkspaceId,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER - Per workspace (family)
// ═══════════════════════════════════════════════════════════════════════════

final chatProvider = StateNotifierProvider.family<ChatNotifier, ChatState, String>((ref, workspaceId) {
  return ChatNotifier(workspaceId);
});

// ═══════════════════════════════════════════════════════════════════════════
// NOTIFIER - Uses ComponentBridge pattern
// ═══════════════════════════════════════════════════════════════════════════

class ChatNotifier extends StateNotifier<ChatState> {
  final String workspaceId;
  final _bridge = ChatBridge();
  StreamSubscription<ChatEvent>? _subscription;
  
  ChatNotifier(this.workspaceId) : super(const ChatState()) {
    _init();
  }
  
  void _init() {
    print('💬 ChatNotifier: Starting for workspace $workspaceId');
    _bridge.start();
    _subscription = _bridge.events.listen(_handleEvent);
    
    // Load chat history for this workspace
    loadHistory();
  }
  
  void _handleEvent(ChatEvent event) {
    print('📥 Chat event: ${event.type}');
    
    switch (event.type) {
      case 'ChatSent':
        _handleChatSent(event);
        break;
        
      case 'ChatDeleted':
        final id = event.data['id'] as String?;
        if (id != null) {
          state = state.copyWith(
            messages: state.messages.where((m) => m.id != id).toList(),
          );
        }
        break;
        
      case 'ChatHistory':
        _handleChatHistory(event);
        break;
        
      case 'DirectMessageReceived':
        _handleDirectMessage(event);
        break;
        
      case 'ChatStreamReady':
        print('✅ Chat stream ready with peer: ${event.data['peer_id']}');
        break;
        
      case 'ChatStreamClosed':
        print('❌ Chat stream closed with peer: ${event.data['peer_id']}');
        break;
        
      case 'Error':
        state = state.copyWith(
          error: event.data['message'] as String?,
          isLoading: false,
        );
        break;
    }
  }
  
  void _handleChatSent(ChatEvent event) {
    // Only add if it's for our workspace
    final eventWorkspaceId = event.data['workspace_id'] as String?;
    if (eventWorkspaceId != workspaceId) return;
    
    final message = ChatMessage(
      id: event.data['id'] as String? ?? '',
      boardId: workspaceId,
      senderId: event.data['author'] as String? ?? '',
      senderName: event.data['author_name'] as String? ?? 'Unknown',
      senderColor: event.data['author_color'] as String?,
      text: event.data['message'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (event.data['timestamp'] as int? ?? 0) * 1000,
      ),
      isMe: event.data['is_me'] as bool? ?? false,
    );
    
    // Avoid duplicates (optimistic add)
    if (!state.messages.any((m) => m.id == message.id)) {
      state = state.copyWith(
        messages: [...state.messages, message],
      );
    }
  }
  
  void _handleChatHistory(ChatEvent event) {
    final messagesData = event.data['messages'] as List<dynamic>? ?? [];
    final messages = messagesData.map((m) {
      final msg = m as Map<String, dynamic>;
      return ChatMessage(
        id: msg['id'] as String? ?? '',
        boardId: workspaceId,
        senderId: msg['author'] as String? ?? '',
        senderName: msg['author_name'] as String? ?? 'Unknown',
        senderColor: msg['author_color'] as String?,
        text: msg['message'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (msg['timestamp'] as int? ?? 0) * 1000,
        ),
        isMe: msg['is_me'] as bool? ?? false,
      );
    }).toList();
    
    state = state.copyWith(
      messages: messages,
      isLoading: false,
    );
  }
  
  void _handleDirectMessage(ChatEvent event) {
    final message = ChatMessage(
      id: event.data['id'] as String? ?? '',
      boardId: workspaceId,
      senderId: event.data['peer_id'] as String? ?? '',
      senderName: event.data['peer_name'] as String? ?? 'Peer',
      text: event.data['message'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (event.data['timestamp'] as int? ?? 0) * 1000,
      ),
      isMe: (event.data['is_incoming'] as bool?) == false,
    );
    
    state = state.copyWith(
      messages: [...state.messages, message],
    );
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API - Send commands via bridge
  // ═══════════════════════════════════════════════════════════════════════════
  
  void loadHistory() {
    print('📤 Chat: LoadChatHistory for workspace $workspaceId');
    state = state.copyWith(isLoading: true);
    _bridge.send(ChatCommand.loadChatHistory(workspaceId: workspaceId));
  }
  
  void sendMessage(String text) {
    print('📤 Chat: SendChat "$text" to workspace $workspaceId');
    _bridge.send(ChatCommand.sendMessage(
      workspaceId: workspaceId,
      message: text,
    ));
    
    // Optimistically add message
    final optimisticMessage = ChatMessage(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      boardId: workspaceId,
      senderId: 'me',
      senderName: 'Me',
      text: text,
      timestamp: DateTime.now(),
      isMe: true,
    );
    
    state = state.copyWith(
      messages: [...state.messages, optimisticMessage],
    );
  }
  
  void deleteMessage(String id) {
    print('📤 Chat: DeleteChat $id');
    _bridge.send(ChatCommand.deleteMessage(id: id));
  }
  
  void startDirectChat(String peerId) {
    print('📤 Chat: StartDirectChat with peer $peerId in workspace $workspaceId');
    _bridge.send(ChatCommand.startDirectChat(
      peerId: peerId,
      workspaceId: workspaceId,
    ));
  }
  
  void sendDirectMessage(String peerId, String text) {
    print('📤 Chat: SendDirectMessage to peer $peerId');
    _bridge.send(ChatCommand.sendDirectMessage(
      peerId: peerId,
      workspaceId: workspaceId,
      message: text,
    ));
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    _bridge.dispose();
    super.dispose();
  }
}
