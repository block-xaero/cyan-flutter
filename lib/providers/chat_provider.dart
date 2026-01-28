// providers/chat_provider.dart
// Chat state management with actual FFI bridge

import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ffi/component_bridge.dart';
import '../models/chat_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CHAT STATE
// ═══════════════════════════════════════════════════════════════════════════

class ChatState {
  final ChatContextInfo? context;
  final List<ChatMessage> messages;
  final List<PeerInfo> onlinePeers;
  final bool isLoading;
  final bool isSending;
  final String? error;

  const ChatState({
    this.context,
    this.messages = const [],
    this.onlinePeers = const [],
    this.isLoading = false,
    this.isSending = false,
    this.error,
  });

  ChatState copyWith({
    ChatContextInfo? context,
    List<ChatMessage>? messages,
    List<PeerInfo>? onlinePeers,
    bool? isLoading,
    bool? isSending,
    String? error,
    bool clearContext = false,
    bool clearError = false,
  }) {
    return ChatState(
      context: clearContext ? null : (context ?? this.context),
      messages: messages ?? this.messages,
      onlinePeers: onlinePeers ?? this.onlinePeers,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHAT PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier();
});

class ChatNotifier extends StateNotifier<ChatState> {
  late final ComponentBridge _bridge;
  StreamSubscription? _subscription;
  String? _currentUserId;

  ChatNotifier() : super(const ChatState()) {
    _init();
  }

  void _init() {
    // Create bridge for chat_panel component
    _bridge = ComponentBridge(
      componentName: 'chat_panel',
      onEvent: _handleEvent,
    );
    _bridge.start();
    
    // Get current user ID from FFI
    _loadCurrentUserId();
  }

  void _loadCurrentUserId() {
    // TODO: Get from FFI - cyan_get_node_id_hex()
    // For now, use placeholder
    _currentUserId = 'current_user';
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    print('📥 Chat event: $type');
    
    switch (type) {
      case 'ChatSent':
        _handleChatMessage(event['data'] as Map<String, dynamic>? ?? event);
        break;
        
      case 'ChatDeleted':
        _handleChatDeleted(event['data'] as Map<String, dynamic>? ?? event);
        break;
        
      case 'ChatHistory':
        _handleChatHistory(event['data'] as Map<String, dynamic>? ?? event);
        break;
        
      case 'PeerJoined':
        _handlePeerJoined(event['data'] as Map<String, dynamic>? ?? event);
        break;
        
      case 'PeerLeft':
        _handlePeerLeft(event['data'] as Map<String, dynamic>? ?? event);
        break;
        
      case 'Error':
        state = state.copyWith(
          error: event['message'] as String?,
          isLoading: false,
          isSending: false,
        );
        break;
    }
  }

  void _handleChatMessage(Map<String, dynamic> data) {
    // Only add if it's for the current context
    final wsId = data['workspace_id'] as String?;
    if (state.context == null) return;
    if (wsId != state.context!.workspaceId && wsId != state.context!.id) return;
    
    final msg = ChatMessage.fromJson(data, currentUserId: _currentUserId);
    
    // Avoid duplicates (from optimistic add)
    if (state.messages.any((m) => m.id == msg.id)) return;
    // Also check temp IDs
    if (msg.id.startsWith('temp_')) return;
    
    final messages = [...state.messages, msg];
    // Sort by timestamp
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    
    state = state.copyWith(messages: messages, isSending: false);
  }

  void _handleChatDeleted(Map<String, dynamic> data) {
    final id = data['id'] as String?;
    if (id != null) {
      final messages = state.messages.where((m) => m.id != id).toList();
      state = state.copyWith(messages: messages);
    }
  }

  void _handleChatHistory(Map<String, dynamic> data) {
    final messagesData = data['messages'] as List<dynamic>? ?? [];
    final messages = messagesData.map((m) {
      return ChatMessage.fromJson(m as Map<String, dynamic>, currentUserId: _currentUserId);
    }).toList();
    
    // Sort by timestamp
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    
    state = state.copyWith(
      messages: messages,
      isLoading: false,
    );
  }

  void _handlePeerJoined(Map<String, dynamic> data) {
    final peerId = data['peer_id'] as String?;
    if (peerId == null) return;
    
    final peers = List<PeerInfo>.from(state.onlinePeers);
    final existingIndex = peers.indexWhere((p) => p.id == peerId);
    
    if (existingIndex >= 0) {
      peers[existingIndex] = peers[existingIndex].copyWith(isOnline: true);
    } else {
      peers.add(PeerInfo.fromPublicKey(peerId, isOnline: true));
    }
    
    state = state.copyWith(onlinePeers: peers);
  }

  void _handlePeerLeft(Map<String, dynamic> data) {
    final peerId = data['peer_id'] as String?;
    if (peerId == null) return;
    
    final peers = state.onlinePeers.map((p) {
      if (p.id == peerId) return p.copyWith(isOnline: false);
      return p;
    }).toList();
    
    state = state.copyWith(onlinePeers: peers);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set chat context (workspace, group, etc.)
  void setContext(ChatContextInfo context) {
    print('💬 Setting chat context: ${context.title}');
    state = state.copyWith(context: context, messages: [], isLoading: true);
    _loadHistory();
  }

  /// Clear chat context
  void clearContext() {
    state = state.copyWith(clearContext: true, messages: []);
  }

  /// Load chat history for current context
  void _loadHistory() {
    if (state.context == null) return;
    
    final workspaceId = state.context!.workspaceId ?? state.context!.id;
    print('📤 Loading chat history for $workspaceId');
    
    _bridge.send(jsonEncode({
      'type': 'LoadChatHistory',
      'workspace_id': workspaceId,
    }));
  }

  /// Send a message
  void sendMessage(String text, {List<String>? attachments}) {
    if (text.trim().isEmpty || state.context == null) return;
    
    final workspaceId = state.context!.workspaceId ?? state.context!.id;
    print('📤 Sending message to $workspaceId: $text');
    
    state = state.copyWith(isSending: true);
    
    // Optimistic update
    final localId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final msg = ChatMessage(
      id: localId,
      workspaceId: workspaceId,
      message: text,
      authorId: _currentUserId ?? 'me',
      authorName: 'Me',
      timestamp: DateTime.now(),
      isOwn: true,
    );
    
    final messages = [...state.messages, msg];
    state = state.copyWith(messages: messages);
    
    // Send via FFI bridge
    _bridge.send(jsonEncode({
      'type': 'SendChat',
      'workspace_id': workspaceId,
      'message': text,
    }));
  }

  /// Delete a message
  void deleteMessage(String id) {
    print('📤 Deleting message $id');
    
    // Optimistic update
    final messages = state.messages.where((m) => m.id != id).toList();
    state = state.copyWith(messages: messages);
    
    _bridge.send(jsonEncode({
      'type': 'DeleteChat',
      'id': id,
    }));
  }

  /// Start DM with a peer
  void startDirectMessage(PeerInfo peer) {
    print('📤 Starting DM with ${peer.displayName}');
    
    final context = ChatContextInfo.directMessage(
      peerId: peer.id,
      peerName: peer.displayName,
    );
    setContext(context);
    
    // Start QUIC stream
    _bridge.send(jsonEncode({
      'type': 'StartDirectChat',
      'peer_id': peer.id,
      'workspace_id': 'direct',
    }));
  }

  /// Refresh peer list
  void refreshPeers() {
    _bridge.send(jsonEncode({
      'type': 'GetOnlinePeers',
    }));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _bridge.dispose();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONVENIENCE PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

final onlinePeersProvider = Provider<List<PeerInfo>>((ref) {
  return ref.watch(chatProvider).onlinePeers;
});

final onlinePeerCountProvider = Provider<int>((ref) {
  return ref.watch(onlinePeersProvider).where((p) => p.isOnline).length;
});

final chatContextProvider = StateProvider<ChatContextInfo?>((ref) {
  return ref.watch(chatProvider).context;
});
