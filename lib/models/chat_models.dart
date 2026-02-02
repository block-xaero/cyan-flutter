// models/chat_models.dart
// Chat models matching Swift ChatTypes.swift

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CHAT MESSAGE
// ═══════════════════════════════════════════════════════════════════════════

class ChatMessage {
  final String id;
  final String workspaceId;
  final String message;
  final String authorId;
  final String? authorName;
  final String? parentId;
  final DateTime timestamp;
  final List<String> mentions;
  final bool isBroadcast;
  final bool mentionsMe;
  final bool isOwn;

  const ChatMessage({
    required this.id,
    required this.workspaceId,
    required this.message,
    required this.authorId,
    this.authorName,
    this.parentId,
    required this.timestamp,
    this.mentions = const [],
    this.isBroadcast = false,
    this.mentionsMe = false,
    this.isOwn = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, {String? currentUserId}) {
    final authorId = json['author'] as String? ?? json['author_id'] as String? ?? '';
    return ChatMessage(
      id: json['id'] as String? ?? '',
      workspaceId: json['workspace_id'] as String? ?? '',
      message: json['message'] as String? ?? '',
      authorId: authorId,
      authorName: json['author_name'] as String?,
      parentId: json['parent_id'] as String?,
      timestamp: _parseTimestamp(json['timestamp']),
      mentions: (json['mentions'] as List<dynamic>?)?.cast<String>() ?? [],
      isBroadcast: json['is_broadcast'] as bool? ?? false,
      mentionsMe: json['mentions_me'] as bool? ?? false,
      isOwn: currentUserId != null && authorId == currentUserId,
    );
  }

  static DateTime _parseTimestamp(dynamic ts) {
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    if (ts is double) return DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt());
    return DateTime.now();
  }

  String get displayAuthor {
    if (authorName != null && authorName!.isNotEmpty) return authorName!;
    if (authorId.length > 12) {
      return '${authorId.substring(0, 6)}...${authorId.substring(authorId.length - 4)}';
    }
    return authorId;
  }

  String get displayTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ENHANCED MESSAGE WITH PARSED CONTENT
// ═══════════════════════════════════════════════════════════════════════════

class EnhancedChatMessage {
  final String id;
  final String workspaceId;
  final String authorId;
  final String authorName;
  final DateTime timestamp;
  final bool isOwn;
  final List<MessagePart> content;
  final List<String> attachments;
  final String? replyToId;

  const EnhancedChatMessage({
    required this.id,
    required this.workspaceId,
    required this.authorId,
    required this.authorName,
    required this.timestamp,
    this.isOwn = false,
    this.content = const [],
    this.attachments = const [],
    this.replyToId,
  });

  String get displayTime => '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  String get plainText => content.map((p) => p.text).join();

  static List<MessagePart> parseContent(String text) {
    final parts = <MessagePart>[];
    if (text.isEmpty) return parts;

    // Simple parsing - just return as text for now
    // Full markdown is rendered by MarkdownRenderer widget
    parts.add(MessagePart.text(text));
    return parts;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MESSAGE PART (for rich content)
// ═══════════════════════════════════════════════════════════════════════════

enum MessagePartType { text, code, codeBlock, mention, link, bold, italic }

class MessagePart {
  final MessagePartType type;
  final String text;
  final String? language; // for code blocks
  final String? url; // for links

  const MessagePart({required this.type, required this.text, this.language, this.url});

  factory MessagePart.text(String t) => MessagePart(type: MessagePartType.text, text: t);
  factory MessagePart.code(String t) => MessagePart(type: MessagePartType.code, text: t);
  factory MessagePart.codeBlock(String t, String? lang) => MessagePart(type: MessagePartType.codeBlock, text: t, language: lang);
  factory MessagePart.mention(String t) => MessagePart(type: MessagePartType.mention, text: t);
  factory MessagePart.link(String t, String u) => MessagePart(type: MessagePartType.link, text: t, url: u);
}

// ═══════════════════════════════════════════════════════════════════════════
// PEER INFO
// ═══════════════════════════════════════════════════════════════════════════

class PeerInfo {
  final String id; // Public key
  final String displayName;
  final bool isOnline;
  final int unreadCount;
  final String? avatarUrl;

  const PeerInfo({
    required this.id,
    required this.displayName,
    this.isOnline = false,
    this.unreadCount = 0,
    this.avatarUrl,
  });

  factory PeerInfo.fromPublicKey(String publicKey, {bool isOnline = true}) {
    String name;
    if (publicKey.length > 12) {
      name = '${publicKey.substring(0, 6)}...${publicKey.substring(publicKey.length - 4)}';
    } else {
      name = publicKey;
    }
    return PeerInfo(id: publicKey, displayName: name, isOnline: isOnline);
  }

  PeerInfo copyWith({String? displayName, bool? isOnline, int? unreadCount}) {
    return PeerInfo(
      id: id,
      displayName: displayName ?? this.displayName,
      isOnline: isOnline ?? this.isOnline,
      unreadCount: unreadCount ?? this.unreadCount,
      avatarUrl: avatarUrl,
    );
  }

  /// Color based on peer ID hash (for avatar background)
  Color get avatarColor {
    final hash = id.hashCode;
    final colors = [
      const Color(0xFF66D9EF), // cyan
      const Color(0xFFA6E22E), // green
      const Color(0xFFF92672), // pink
      const Color(0xFFAE81FF), // purple
      const Color(0xFFFD971F), // orange
      const Color(0xFFE6DB74), // yellow
    ];
    return colors[hash.abs() % colors.length];
  }

  /// Initial for avatar
  String get initial => displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
}

// ═══════════════════════════════════════════════════════════════════════════
// DM CONVERSATION
// ═══════════════════════════════════════════════════════════════════════════

class DMConversation {
  final String peerId;
  final String peerName;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isOnline;

  const DMConversation({
    required this.peerId,
    required this.peerName,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isOnline = false,
  });

  DMConversation copyWith({
    String? peerName,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isOnline,
  }) {
    return DMConversation(
      peerId: peerId,
      peerName: peerName ?? this.peerName,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  String get displayTime {
    if (lastMessageTime == null) return '';
    final diff = DateTime.now().difference(lastMessageTime!);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHAT CONTEXT
// ═══════════════════════════════════════════════════════════════════════════

enum ChatContextType { global, group, workspace, board, directMessage }

class ChatContextInfo {
  final String id;
  final ChatContextType type;
  final String? workspaceId;
  final String? groupId;
  final String displayName;

  const ChatContextInfo({
    required this.id,
    required this.type,
    this.workspaceId,
    this.groupId,
    required this.displayName,
  });
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatContextInfo && other.id == id;
  }
  
  @override
  int get hashCode => id.hashCode;

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

  IconData get icon {
    switch (type) {
      case ChatContextType.global:
        return Icons.public;
      case ChatContextType.group:
        return Icons.folder;
      case ChatContextType.workspace:
        return Icons.workspaces_outline;
      case ChatContextType.board:
        return Icons.dashboard;
      case ChatContextType.directMessage:
        return Icons.person;
    }
  }

  Color get color {
    switch (type) {
      case ChatContextType.global:
        return const Color(0xFFAE81FF);
      case ChatContextType.group:
        return const Color(0xFF66D9EF);
      case ChatContextType.workspace:
        return const Color(0xFFA6E22E);
      case ChatContextType.board:
        return const Color(0xFFF92672);
      case ChatContextType.directMessage:
        return const Color(0xFFFD971F);
    }
  }
  
  /// Scope string for FFI (group/workspace/board)
  String get scope {
    switch (type) {
      case ChatContextType.global:
        return 'global';
      case ChatContextType.group:
        return 'group';
      case ChatContextType.workspace:
        return 'workspace';
      case ChatContextType.board:
        return 'board';
      case ChatContextType.directMessage:
        return 'dm';
    }
  }
  
  /// Display name
  String get name => displayName;
  
  /// Raw ID without prefix (for FFI)
  String get rawId {
    if (id.startsWith('ws:')) return id.substring(3);
    if (id.startsWith('g:')) return id.substring(2);
    if (id.startsWith('b:')) return id.substring(2);
    if (id.startsWith('dm:')) return id.substring(3);
    return id;
  }

  // Factory methods
  static ChatContextInfo global() => const ChatContextInfo(
        id: 'global',
        type: ChatContextType.global,
        displayName: 'Global',
      );

  static ChatContextInfo workspace({
    required String id,
    required String groupId,
    required String name,
  }) =>
      ChatContextInfo(
        id: 'ws:$id',
        type: ChatContextType.workspace,
        workspaceId: id,
        groupId: groupId,
        displayName: name,
      );

  static ChatContextInfo group({required String id, required String name}) => ChatContextInfo(
        id: 'g:$id',
        type: ChatContextType.group,
        groupId: id,
        displayName: name,
      );

  static ChatContextInfo board({
    required String id,
    required String workspaceId,
    required String groupId,
    required String name,
  }) =>
      ChatContextInfo(
        id: 'b:$id',
        type: ChatContextType.board,
        workspaceId: workspaceId,
        groupId: groupId,
        displayName: name,
      );

  static ChatContextInfo directMessage({
    required String peerId,
    required String peerName,
  }) =>
      ChatContextInfo(
        id: 'dm:$peerId',
        type: ChatContextType.directMessage,
        displayName: peerName,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// CHAT MODE
// ═══════════════════════════════════════════════════════════════════════════

enum ChatMode { group, direct }

// XaeroIdentity has been moved to models/xaero_identity.dart
