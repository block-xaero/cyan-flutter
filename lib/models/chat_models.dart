// models/chat_models.dart
// Enhanced chat models with DMs, markdown, code blocks, peers

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PEER INFO
// ═══════════════════════════════════════════════════════════════════════════

class PeerInfo {
  final String id; // Public key
  final String displayName;
  final bool isOnline;
  final int unreadCount;

  const PeerInfo({
    required this.id,
    required this.displayName,
    this.isOnline = false,
    this.unreadCount = 0,
  });

  /// Create from public key with shortened display name
  factory PeerInfo.fromPublicKey(String publicKey, {bool isOnline = false}) {
    final displayName = publicKey.length > 12
        ? '${publicKey.substring(0, 6)}...${publicKey.substring(publicKey.length - 4)}'
        : publicKey;
    return PeerInfo(id: publicKey, displayName: displayName, isOnline: isOnline);
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
}

// ═══════════════════════════════════════════════════════════════════════════
// CHAT CONTEXT
// ═══════════════════════════════════════════════════════════════════════════

enum ChatContextType { global, group, workspace, board, directMessage }

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

  static ChatContext group({required String id, required String name}) =>
      ChatContext(
        id: 'g:$id',
        type: ChatContextType.group,
        groupId: id,
        displayName: name,
      );

  static ChatContext workspace({
    required String id,
    required String groupId,
    required String name,
  }) =>
      ChatContext(
        id: 'ws:$id',
        type: ChatContextType.workspace,
        workspaceId: id,
        groupId: groupId,
        displayName: name,
      );

  static ChatContext board({
    required String id,
    required String workspaceId,
    required String groupId,
    required String name,
  }) =>
      ChatContext(
        id: 'b:$id',
        type: ChatContextType.board,
        workspaceId: workspaceId,
        groupId: groupId,
        displayName: name,
      );

  static ChatContext directMessage({
    required String peerId,
    required String peerName,
  }) =>
      ChatContext(
        id: 'dm:$peerId',
        type: ChatContextType.directMessage,
        displayName: peerName,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// CHAT MODE
// ═══════════════════════════════════════════════════════════════════════════

sealed class ChatMode {
  const ChatMode();
}

class GroupChatMode extends ChatMode {
  const GroupChatMode();
}

class DirectChatMode extends ChatMode {
  final PeerInfo peer;
  const DirectChatMode(this.peer);
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

  String get id => peerId;

  String get displayTime {
    if (lastMessageTime == null) return '';
    final now = DateTime.now();
    final diff = now.difference(lastMessageTime!);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
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
      peerId: peerId,
      peerName: peerName ?? this.peerName,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ENHANCED CHAT MESSAGE
// ═══════════════════════════════════════════════════════════════════════════

/// Content block in a message (text, code, file, etc.)
sealed class MessageContent {
  const MessageContent();
}

class TextContent extends MessageContent {
  final String text;
  const TextContent(this.text);
}

class CodeContent extends MessageContent {
  final String code;
  final String? language;
  const CodeContent(this.code, {this.language});
}

class FileContent extends MessageContent {
  final String fileId;
  final String fileName;
  final int fileSize;
  final String? mimeType;
  final String? localPath;
  const FileContent({
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    this.mimeType,
    this.localPath,
  });
}

class EnhancedChatMessage {
  final String id;
  final String workspaceId;
  final String authorId; // Public key
  final String authorName;
  final DateTime timestamp;
  final bool isOwn;
  final List<MessageContent> content;
  final List<String> mentions;
  final bool isBroadcast;
  final bool mentionsMe;
  final String? parentId;

  const EnhancedChatMessage({
    required this.id,
    required this.workspaceId,
    required this.authorId,
    required this.authorName,
    required this.timestamp,
    required this.isOwn,
    required this.content,
    this.mentions = const [],
    this.isBroadcast = false,
    this.mentionsMe = false,
    this.parentId,
  });

  /// Parse raw text into content blocks (handles code blocks)
  static List<MessageContent> parseContent(String rawText) {
    final blocks = <MessageContent>[];
    final codeBlockPattern = RegExp(r'```(\w+)?\n?([\s\S]*?)```');

    int lastEnd = 0;
    for (final match in codeBlockPattern.allMatches(rawText)) {
      // Add text before code block
      if (match.start > lastEnd) {
        final text = rawText.substring(lastEnd, match.start).trim();
        if (text.isNotEmpty) {
          blocks.add(TextContent(text));
        }
      }

      // Add code block
      final language = match.group(1);
      final code = match.group(2)?.trim() ?? '';
      blocks.add(CodeContent(code, language: language));

      lastEnd = match.end;
    }

    // Add remaining text
    if (lastEnd < rawText.length) {
      final text = rawText.substring(lastEnd).trim();
      if (text.isNotEmpty) {
        blocks.add(TextContent(text));
      }
    }

    // If no blocks, treat entire text as plain text
    if (blocks.isEmpty) {
      blocks.add(TextContent(rawText));
    }

    return blocks;
  }

  /// Get all file attachments
  List<FileContent> get files =>
      content.whereType<FileContent>().toList();

  /// Check if message has any files
  bool get hasFiles => files.isNotEmpty;

  /// Get plain text representation
  String get plainText {
    return content.map((c) {
      if (c is TextContent) return c.text;
      if (c is CodeContent) return '```${c.language ?? ''}\n${c.code}\n```';
      if (c is FileContent) return '[File: ${c.fileName}]';
      return '';
    }).join('\n');
  }

  /// Shortened author ID for display
  String get shortAuthorId {
    if (authorId.length > 12) {
      return '${authorId.substring(0, 6)}...${authorId.substring(authorId.length - 4)}';
    }
    return authorId;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FILE ATTACHMENT INFO
// ═══════════════════════════════════════════════════════════════════════════

class ChatFileAttachment {
  final String messageId;
  final String fileId;
  final String fileName;
  final int fileSize;
  final String? mimeType;
  final String authorName;
  final DateTime timestamp;

  const ChatFileAttachment({
    required this.messageId,
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    this.mimeType,
    required this.authorName,
    required this.timestamp,
  });

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData get icon {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
        return Icons.image;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
      case 'aac':
        return Icons.audio_file;
      case 'zip':
      case 'tar':
      case 'gz':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }
}
