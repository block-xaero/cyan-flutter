// providers/chat_provider.dart
// Chat provider matching Swift ChatPanelViewModel pattern
// Properly handles group, workspace, and board chat scopes

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ffi/component_bridge.dart';
import '../models/chat_models.dart';
import '../services/cyan_service.dart';

// Re-export for convenience
export '../models/chat_models.dart' show ChatContextInfo, ChatContextType, ChatMessage, PeerInfo;

// ============================================================================
// CHAT STATE
// ============================================================================

class ChatState {
  final List<ChatMessage> messages;
  final List<PeerInfo> peers;
  final bool isLoadingHistory;
  final String? error;
  final ChatContextInfo? context;
  
  const ChatState({
    this.messages = const [],
    this.peers = const [],
    this.isLoadingHistory = false,
    this.error,
    this.context,
  });
  
  ChatState copyWith({
    List<ChatMessage>? messages,
    List<PeerInfo>? peers,
    bool? isLoadingHistory,
    String? error,
    ChatContextInfo? context,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      peers: peers ?? this.peers,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      error: error,
      context: context ?? this.context,
    );
  }
}

// ============================================================================
// CHAT NOTIFIER - matches Swift ChatPanelViewModel
// ============================================================================

class ChatNotifier extends StateNotifier<ChatState> {
  final ChatBridge _bridge;
  final List<String> _workspaceIdsForGroup;
  StreamSubscription? _subscription;
  Timer? _peerRefreshTimer;
  
  // Deduplication
  final Set<String> _seenMessageIds = {};
  final Map<String, String> _pendingLocalMessages = {};
  
  String get _myNodeId => CyanService.instance.nodeId ?? 'unknown';
  
  ChatNotifier(ChatContextInfo context, {List<String> workspaceIdsForGroup = const []}) 
      : _bridge = ChatBridge(),
        _workspaceIdsForGroup = workspaceIdsForGroup,
        super(ChatState(context: context)) {
    _setup();
  }
  
  void _setup() {
    _bridge.start();
    _subscription = _bridge.events.listen(_handleEvent);
    
    // Load history after a brief delay
    Future.delayed(const Duration(milliseconds: 100), () {
      _loadHistory();
    });
    
    _startPeerRefresh();
  }
  
  void _startPeerRefresh() {
    _peerRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // Could poll peers here
    });
  }
  
  void _loadHistory() {
    final ctx = state.context;
    if (ctx == null) return;
    
    state = state.copyWith(isLoadingHistory: true);
    
    switch (ctx.type) {
      case ChatContextType.global:
        // Load from all known workspaces
        break;
        
      case ChatContextType.group:
        // Load from ALL workspaces in the group
        _loadChatsForGroup();
        break;
        
      case ChatContextType.workspace:
      case ChatContextType.board:
        if (ctx.workspaceId != null) {
          _bridge.send(ChatCommand.loadHistory(workspaceId: ctx.workspaceId!));
        }
        break;
        
      case ChatContextType.directMessage:
        // DM history handled separately
        break;
    }
    
    // Clear loading after timeout
    Future.delayed(const Duration(seconds: 3), () {
      if (state.isLoadingHistory) {
        state = state.copyWith(isLoadingHistory: false);
      }
    });
  }
  
  void _loadChatsForGroup() {
    // Load chat history for ALL workspaces in the group
    for (final wsId in _workspaceIdsForGroup) {
      _bridge.send(ChatCommand.loadHistory(workspaceId: wsId));
      // Small delay between requests
      Future.delayed(const Duration(milliseconds: 100));
    }
  }
  
  void _handleEvent(ChatEvent event) {
    print('📨 Chat event: ${event.type}');
    
    if (event.isMessage) {
      _handleMessage(event);
    } else if (event.isMessageDeleted) {
      _handleMessageDeleted(event);
    } else if (event.isPeerJoined) {
      _handlePeerJoined(event);
    } else if (event.isPeerLeft) {
      _handlePeerLeft(event);
    } else if (event.isHistory) {
      _handleHistory(event);
      state = state.copyWith(isLoadingHistory: false);
    }
  }
  
  void _handleMessage(ChatEvent event) {
    final data = event.data;
    final id = data['id'] as String? ?? '';
    final workspaceId = data['workspace_id'] as String? ?? '';
    final message = data['message'] as String? ?? '';
    final author = data['author'] as String? ?? '';
    final timestamp = _parseTimestamp(data['timestamp']);
    final mentions = (data['mentions'] as List?)?.cast<String>() ?? [];
    final isBroadcast = data['is_broadcast'] as bool? ?? false;
    final mentionsMe = data['mentions_me'] as bool? ?? false;
    
    // Check if this workspace is relevant to our context
    if (!_shouldIncludeMessage(workspaceId)) {
      return;
    }
    
    // Check for echo of our own message
    final contentHash = _makeContentHash(message, author);
    if (_pendingLocalMessages.containsKey(contentHash)) {
      final localId = _pendingLocalMessages.remove(contentHash)!;
      final messages = state.messages.map((m) {
        if (m.id == localId) {
          return ChatMessage(
            id: id,
            workspaceId: m.workspaceId,
            message: m.message,
            authorId: m.authorId,
            authorName: m.authorName,
            timestamp: m.timestamp,
            isOwn: m.isOwn,
            mentions: mentions,
            isBroadcast: isBroadcast,
            mentionsMe: mentionsMe,
          );
        }
        return m;
      }).toList();
      state = state.copyWith(messages: messages);
      return;
    }
    
    // Dedupe
    if (_seenMessageIds.contains(id)) return;
    _seenMessageIds.add(id);
    
    final isOwn = author == _myNodeId;
    final newMessage = ChatMessage(
      id: id,
      workspaceId: workspaceId,
      message: message,
      authorId: author,
      authorName: isOwn ? 'Me' : _shortName(author),
      timestamp: timestamp,
      isOwn: isOwn,
      mentions: mentions,
      isBroadcast: isBroadcast,
      mentionsMe: mentionsMe,
    );
    
    final messages = [...state.messages, newMessage];
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    state = state.copyWith(messages: messages);
  }
  
  void _handleMessageDeleted(ChatEvent event) {
    final id = event.data['id'] as String?;
    if (id == null) return;
    
    final messages = state.messages.where((m) => m.id != id).toList();
    state = state.copyWith(messages: messages);
    _seenMessageIds.remove(id);
  }
  
  void _handlePeerJoined(ChatEvent event) {
    final peerId = event.data['peer_id'] as String?;
    if (peerId == null) return;
    
    if (!state.peers.any((p) => p.id == peerId)) {
      final peer = PeerInfo(
        id: peerId,
        displayName: _shortName(peerId),
        isOnline: true,
      );
      state = state.copyWith(peers: [...state.peers, peer]);
    } else {
      final peers = state.peers.map((p) {
        if (p.id == peerId) return p.copyWith(isOnline: true);
        return p;
      }).toList();
      state = state.copyWith(peers: peers);
    }
  }
  
  void _handlePeerLeft(ChatEvent event) {
    final peerId = event.data['peer_id'] as String?;
    if (peerId == null) return;
    
    final peers = state.peers.map((p) {
      if (p.id == peerId) return p.copyWith(isOnline: false);
      return p;
    }).toList();
    state = state.copyWith(peers: peers);
  }
  
  void _handleHistory(ChatEvent event) {
    final messagesData = event.data['messages'] as List? ?? [];
    
    for (final msgData in messagesData) {
      if (msgData is Map<String, dynamic>) {
        final id = msgData['id'] as String? ?? '';
        if (_seenMessageIds.contains(id)) continue;
        _seenMessageIds.add(id);
        
        final author = msgData['author'] as String? ?? '';
        final isOwn = author == _myNodeId;
        
        final msg = ChatMessage(
          id: id,
          workspaceId: msgData['workspace_id'] as String? ?? '',
          message: msgData['message'] as String? ?? '',
          authorId: author,
          authorName: isOwn ? 'Me' : _shortName(author),
          timestamp: _parseTimestamp(msgData['timestamp']),
          isOwn: isOwn,
          mentions: (msgData['mentions'] as List?)?.cast<String>() ?? [],
          isBroadcast: msgData['is_broadcast'] as bool? ?? false,
          mentionsMe: msgData['mentions_me'] as bool? ?? false,
        );
        
        state = state.copyWith(messages: [...state.messages, msg]);
      }
    }
    
    // Sort by timestamp
    final messages = [...state.messages];
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    state = state.copyWith(messages: messages);
  }
  
  bool _shouldIncludeMessage(String workspaceId) {
    final ctx = state.context;
    if (ctx == null) return true;
    
    switch (ctx.type) {
      case ChatContextType.global:
        return true;
      case ChatContextType.workspace:
      case ChatContextType.board:
        return ctx.workspaceId == workspaceId;
      case ChatContextType.group:
        // For group chat, include messages from ANY workspace in the group
        return _workspaceIdsForGroup.contains(workspaceId);
      case ChatContextType.directMessage:
        return false;
    }
  }
  
  String _makeContentHash(String content, String author) {
    return '$author:$content';
  }
  
  String _shortName(String nodeId) {
    if (nodeId.length > 12) {
      return '${nodeId.substring(0, 6)}...${nodeId.substring(nodeId.length - 4)}';
    }
    return nodeId;
  }
  
  DateTime _parseTimestamp(dynamic ts) {
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    if (ts is double) return DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt());
    return DateTime.now();
  }
  
  // ============================================================================
  // PUBLIC ACTIONS
  // ============================================================================
  
  void sendMessage(String text, {String? parentId, String? targetWorkspaceId}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    
    final ctx = state.context;
    if (ctx == null) {
      print('⚠️ Cannot send message: no context');
      return;
    }
    
    // Determine target workspace
    String? workspaceId = targetWorkspaceId ?? ctx.workspaceId;
    
    // For group context, use first workspace in group
    if (workspaceId == null && ctx.type == ChatContextType.group) {
      if (_workspaceIdsForGroup.isNotEmpty) {
        workspaceId = _workspaceIdsForGroup.first;
      }
    }
    
    if (workspaceId == null) {
      print('⚠️ Cannot send message: no workspace available');
      return;
    }
    
    // Create local message
    final localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    _seenMessageIds.add(localId);
    
    final contentHash = _makeContentHash(trimmed, _myNodeId);
    _pendingLocalMessages[contentHash] = localId;
    
    final localMessage = ChatMessage(
      id: localId,
      workspaceId: workspaceId,
      message: trimmed,
      authorId: _myNodeId,
      authorName: 'Me',
      timestamp: DateTime.now(),
      isOwn: true,
    );
    
    state = state.copyWith(messages: [...state.messages, localMessage]);
    
    // Send via bridge
    _bridge.send(ChatCommand.sendMessage(
      workspaceId: workspaceId,
      message: trimmed,
      parentId: parentId,
    ));
    
    // Cleanup stale pending after 30s
    Future.delayed(const Duration(seconds: 30), () {
      _pendingLocalMessages.remove(contentHash);
    });
  }
  
  void deleteMessage(String id) {
    _bridge.send(ChatCommand.deleteMessage(id: id));
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    _peerRefreshTimer?.cancel();
    _bridge.dispose();
    super.dispose();
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

/// Chat provider - creates notifier with proper workspace IDs for group
final chatProvider = StateNotifierProvider.family<ChatNotifier, ChatState, ChatContextInfo>(
  (ref, context) {
    // For group context, we need to pass workspace IDs
    // This is handled by the widget that creates the context
    return ChatNotifier(context);
  },
);

/// Parameters for chat with workspace IDs (for group chat)
class ChatWithWorkspacesParams {
  final ChatContextInfo context;
  final List<String> workspaceIds;
  
  const ChatWithWorkspacesParams({required this.context, required this.workspaceIds});
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatWithWorkspacesParams && 
           other.context == context &&
           _listEquals(other.workspaceIds, workspaceIds);
  }
  
  @override
  int get hashCode => Object.hash(context, Object.hashAll(workspaceIds));
  
  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Chat provider with workspace IDs for group chat
final chatWithWorkspacesProvider = StateNotifierProvider.family<ChatNotifier, ChatState, ChatWithWorkspacesParams>(
  (ref, params) {
    return ChatNotifier(params.context, workspaceIdsForGroup: params.workspaceIds);
  },
);
