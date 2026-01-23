// models/chat_message.dart
// Chat message model

class ChatMessage {
  final String id;
  final String boardId;
  final String senderId;
  final String senderName;
  final String? senderColor;
  final String text;
  final DateTime timestamp;
  final bool isMe;
  
  const ChatMessage({
    required this.id,
    required this.boardId,
    required this.senderId,
    required this.senderName,
    this.senderColor,
    required this.text,
    required this.timestamp,
    this.isMe = false,
  });
  
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      boardId: json['board_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      senderName: json['sender_name'] as String? ?? 'Unknown',
      senderColor: json['sender_color'] as String?,
      text: json['text'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      isMe: json['is_me'] as bool? ?? false,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'board_id': boardId,
      'sender_id': senderId,
      'sender_name': senderName,
      if (senderColor != null) 'sender_color': senderColor,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'is_me': isMe,
    };
  }
}
