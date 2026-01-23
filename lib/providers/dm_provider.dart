// providers/dm_provider.dart
// Direct Messages state management

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ffi/component_bridge.dart';
import '../models/chat_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════════════════

class DMState {
  final List<DMConversation> conversations;
  final Map<String, List<EnhancedChatMessage>> messagesByPeer;
  final String? activePeerId;
  final bool isLoading;
  final int totalUnreadCount;

  const DMState({
    this.conversations = const [],
    this.messagesByPeer = const {},
    this.activePeerId,
    this.isLoading = false,
    this.totalUnreadCount = 0,
  });

  DMConversation? get activeConversation {
    if (activePeerId == null) return null;
    return conversations.cast<DMConversation?>().firstWhere(
          (c) => c?.peerId == activePeerId,
          orElse: () => null,
        );
  }

  List<EnhancedChatMessage> get activeMessages {
    if (activePeerId == null) return [];
    return messagesByPeer[activePeerId] ?? [];
  }

  DMState copyWith({
    List<DMConversation>? conversations,
    Map<String, List<EnhancedChatMessage>>? messagesByPeer,
    String? activePeerId,
    bool clearActivePeer = false,
    bool? isLoading,
    int? totalUnreadCount,
  }) {
    return DMState(
      conversations: conversations ?? this.conversations,
      messagesByPeer: messagesByPeer ?? this.messagesByPeer,
      activePeerId: clearActivePeer ? null : (activePeerId ?? this.activePeerId),
      isLoading: isLoading ?? this.isLoading,
      totalUnreadCount: totalUnreadCount ?? this.totalUnreadCount,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

final dmProvider = StateNotifierProvider<DMNotifier, DMState>((ref) {
  return DMNotifier();
});

// ═══════════════════════════════════════════════════════════════════════════
// NOTIFIER
// ═══════════════════════════════════════════════════════════════════════════

class DMNotifier extends StateNotifier<DMState> {
  final _bridge = ChatBridge();
  StreamSubscription<ChatEvent>? _subscription;

  DMNotifier() : super(const DMState()) {
    _init();
  }

  void _init() {
    _bridge.start();
    _subscription = _bridge.events.listen(_handleEvent);
  }

  void _handleEvent(ChatEvent event) {
    if (event.isDirectMessage) {
      _handleDirectMessage(event.data);
    } else if (event.isChatStreamReady) {
      final peerId = event.data['peer_id'] as String?;
      if (peerId != null) {
        print('📱 DM: Stream ready with $peerId');
      }
    } else if (event.type == 'ChatStreamClosed') {
      final peerId = event.data['peer_id'] as String?;
      if (peerId != null) {
        print('📱 DM: Stream closed with $peerId');
        _updatePeerOnlineStatus(peerId, false);
      }
    }
  }

  void _handleDirectMessage(Map<String, dynamic> data) {
    final id = data['id'] as String?;
    final peerId = data['peer_id'] as String?;
    final message = data['message'] as String?;
    final timestamp = data['timestamp'] as int? ?? 0;
    final isIncoming = data['is_incoming'] as bool? ?? true;

    if (id == null || peerId == null || message == null) return;

    print('📩 DM received from $peerId: $message');

    // Create message
    final msg = EnhancedChatMessage(
      id: id,
      workspaceId: 'dm:$peerId',
      authorId: isIncoming ? peerId : 'me',
      authorName: isIncoming ? _getPeerName(peerId) : 'Me',
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
      isOwn: !isIncoming,
      content: EnhancedChatMessage.parseContent(message),
    );

    // Update messages
    final messages = Map<String, List<EnhancedChatMessage>>.from(state.messagesByPeer);
    messages[peerId] = [...(messages[peerId] ?? []), msg];

    // Update conversation
    final conversations = List<DMConversation>.from(state.conversations);
    final existingIndex = conversations.indexWhere((c) => c.peerId == peerId);

    if (existingIndex >= 0) {
      final existing = conversations[existingIndex];
      conversations[existingIndex] = existing.copyWith(
        lastMessage: message,
        lastMessageTime: msg.timestamp,
        unreadCount: isIncoming && state.activePeerId != peerId
            ? existing.unreadCount + 1
            : existing.unreadCount,
      );
    } else {
      conversations.add(DMConversation(
        peerId: peerId,
        peerName: _getPeerName(peerId),
        lastMessage: message,
        lastMessageTime: msg.timestamp,
        unreadCount: isIncoming ? 1 : 0,
        isOnline: true,
      ));
    }

    // Sort by most recent
    conversations.sort((a, b) {
      final aTime = a.lastMessageTime ?? DateTime(1970);
      final bTime = b.lastMessageTime ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });

    // Calculate total unread
    final totalUnread = conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);

    state = state.copyWith(
      conversations: conversations,
      messagesByPeer: messages,
      totalUnreadCount: totalUnread,
    );
  }

  void _updatePeerOnlineStatus(String peerId, bool isOnline) {
    final conversations = state.conversations.map((c) {
      if (c.peerId == peerId) {
        return c.copyWith(isOnline: isOnline);
      }
      return c;
    }).toList();
    state = state.copyWith(conversations: conversations);
  }

  String _getPeerName(String peerId) {
    // Check if we have a conversation with this peer
    final existing = state.conversations.cast<DMConversation?>().firstWhere(
          (c) => c?.peerId == peerId,
          orElse: () => null,
        );
    if (existing != null) return existing.peerName;

    // Generate short name from public key
    if (peerId.length > 12) {
      return '${peerId.substring(0, 6)}...${peerId.substring(peerId.length - 4)}';
    }
    return peerId;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start or open a DM conversation with a peer
  void openConversation(PeerInfo peer) {
    print('📱 Opening DM with ${peer.displayName}');

    // Add conversation if not exists
    final conversations = List<DMConversation>.from(state.conversations);
    final existingIndex = conversations.indexWhere((c) => c.peerId == peer.id);

    if (existingIndex < 0) {
      conversations.insert(
          0,
          DMConversation(
            peerId: peer.id,
            peerName: peer.displayName,
            isOnline: peer.isOnline,
          ));
    }

    // Mark as read
    if (existingIndex >= 0) {
      final existing = conversations[existingIndex];
      if (existing.unreadCount > 0) {
        conversations[existingIndex] = existing.copyWith(unreadCount: 0);
      }
    }

    final totalUnread = conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);

    state = state.copyWith(
      conversations: conversations,
      activePeerId: peer.id,
      totalUnreadCount: totalUnread,
    );

    // Start QUIC connection
    _bridge.send(ChatCommand.startDirectChat(peerId: peer.id, workspaceId: 'direct'));

    // Load history
    _bridge.send(ChatCommand.loadDirectMessageHistory(peerId: peer.id));
  }

  /// Send a DM to the active peer
  void sendMessage(String text) {
    if (state.activePeerId == null) return;
    final peerId = state.activePeerId!;

    print('📤 Sending DM to $peerId: $text');

    // Optimistic update
    final localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final msg = EnhancedChatMessage(
      id: localId,
      workspaceId: 'dm:$peerId',
      authorId: 'me',
      authorName: 'Me',
      timestamp: DateTime.now(),
      isOwn: true,
      content: EnhancedChatMessage.parseContent(text),
    );

    final messages = Map<String, List<EnhancedChatMessage>>.from(state.messagesByPeer);
    messages[peerId] = [...(messages[peerId] ?? []), msg];

    // Update conversation
    final conversations = state.conversations.map((c) {
      if (c.peerId == peerId) {
        return c.copyWith(
          lastMessage: text,
          lastMessageTime: msg.timestamp,
        );
      }
      return c;
    }).toList();

    state = state.copyWith(
      conversations: conversations,
      messagesByPeer: messages,
    );

    // Send via bridge
    _bridge.send(ChatCommand.sendDirectMessage(
      peerId: peerId,
      workspaceId: 'direct',
      message: text,
    ));
  }

  /// Close the active conversation
  void closeConversation() {
    state = state.copyWith(clearActivePeer: true);
  }

  /// Mark conversation as read
  void markAsRead(String peerId) {
    final conversations = state.conversations.map((c) {
      if (c.peerId == peerId) {
        return c.copyWith(unreadCount: 0);
      }
      return c;
    }).toList();

    final totalUnread = conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);

    state = state.copyWith(
      conversations: conversations,
      totalUnreadCount: totalUnread,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _bridge.dispose();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHAT BRIDGE (for DM commands) - uses existing ChatBridge from component_bridge.dart
// ═══════════════════════════════════════════════════════════════════════════

// Note: ChatBridge, ChatCommand, and ChatEvent are defined in component_bridge.dart
// This file just uses them for DM functionality
