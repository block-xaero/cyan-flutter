// models/peer_info.dart
// Peer information for chat panels and DMs

class PeerInfo {
  final String id;           // Public key string
  final String displayName;  // Shortened display name or resolved name
  final bool isOnline;
  final int unreadCount;     // For DM badge
  
  const PeerInfo({
    required this.id,
    required this.displayName,
    this.isOnline = false,
    this.unreadCount = 0,
  });
  
  factory PeerInfo.fromPublicKey(String publicKey, {bool isOnline = false, String? name}) {
    final displayName = name ?? _shortenKey(publicKey);
    return PeerInfo(
      id: publicKey,
      displayName: displayName,
      isOnline: isOnline,
    );
  }
  
  static String _shortenKey(String key) {
    if (key.length > 12) {
      return '${key.substring(0, 6)}...${key.substring(key.length - 4)}';
    }
    return key;
  }
  
  PeerInfo copyWith({
    String? displayName,
    bool? isOnline,
    int? unreadCount,
  }) {
    return PeerInfo(
      id: id,
      displayName: displayName ?? this.displayName,
      isOnline: isOnline ?? this.isOnline,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PeerInfo && runtimeType == other.runtimeType && id == other.id;
  
  @override
  int get hashCode => id.hashCode;
}

/// Direct message conversation summary
class DMConversation {
  final String id;           // peer node_id
  final String peerId;
  final String peerName;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isOnline;
  
  const DMConversation({
    required this.id,
    required this.peerId,
    required this.peerName,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isOnline = false,
  });
  
  String get displayTime {
    if (lastMessageTime == null) return '';
    
    final now = DateTime.now();
    final diff = now.difference(lastMessageTime!);
    
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${lastMessageTime!.month}/${lastMessageTime!.day}';
  }
  
  DMConversation copyWith({
    String? peerName,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isOnline,
  }) {
    return DMConversation(
      id: id,
      peerId: peerId,
      peerName: peerName ?? this.peerName,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

/// Chat context - what scope is the chat for
enum ChatContextType {
  global,
  group,
  workspace,
  board,
  directMessage,
}

class ChatContext {
  final String id;
  final ChatContextType type;
  final String? workspaceId;
  final String? groupId;
  final String displayName;
  
  const ChatContext({
    required this.id,
    required this.type,
    this.workspaceId,
    this.groupId,
    required this.displayName,
  });
  
  String get title {
    switch (type) {
      case ChatContextType.global:
        return 'Global Chat';
      case ChatContextType.group:
        return 'Group: $displayName';
      case ChatContextType.workspace:
        return displayName;
      case ChatContextType.board:
        return 'Board: $displayName';
      case ChatContextType.directMessage:
        return 'DM: $displayName';
    }
  }
  
  // Factory methods
  static ChatContext global() => const ChatContext(
    id: 'global',
    type: ChatContextType.global,
    displayName: 'Global',
  );
  
  static ChatContext workspace({
    required String id,
    required String groupId,
    required String name,
  }) => ChatContext(
    id: 'ws:$id',
    type: ChatContextType.workspace,
    workspaceId: id,
    groupId: groupId,
    displayName: name,
  );
  
  static ChatContext group({
    required String id,
    required String name,
  }) => ChatContext(
    id: 'g:$id',
    type: ChatContextType.group,
    groupId: id,
    displayName: name,
  );
  
  static ChatContext board({
    required String id,
    required String workspaceId,
    required String groupId,
    required String name,
  }) => ChatContext(
    id: 'b:$id',
    type: ChatContextType.board,
    workspaceId: workspaceId,
    groupId: groupId,
    displayName: name,
  );
  
  static ChatContext directMessage({
    required String peerId,
    required String peerName,
  }) => ChatContext(
    id: 'dm:$peerId',
    type: ChatContextType.directMessage,
    displayName: peerName,
  );
}
