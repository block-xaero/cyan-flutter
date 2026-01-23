// widgets/chat_panel_widget.dart
// Chat panel with messages for a board

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../models/chat_message.dart';

class ChatPanelWidget extends ConsumerStatefulWidget {
  final String boardId;
  
  const ChatPanelWidget({super.key, required this.boardId});

  @override
  ConsumerState<ChatPanelWidget> createState() => _ChatPanelWidgetState();
}

class _ChatPanelWidgetState extends ConsumerState<ChatPanelWidget> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  
  @override
  void initState() {
    super.initState();
    // Load chat history when panel opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatProvider(widget.boardId).notifier).loadHistory();
    });
  }
  
  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  
  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    ref.read(chatProvider(widget.boardId).notifier).sendMessage(text);
    _messageController.clear();
    
    // Scroll to bottom after sending
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider(widget.boardId));
    
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF3E3D32),
            border: Border(
              bottom: BorderSide(color: Color(0xFF272822)),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.chat_bubble, size: 18, color: Color(0xFF66D9EF)),
              const SizedBox(width: 8),
              const Text(
                'Chat',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFF8F8F2),
                ),
              ),
              const Spacer(),
              if (chatState.isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF66D9EF)),
                  ),
                ),
            ],
          ),
        ),
        
        // Messages list
        Expanded(
          child: chatState.messages.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 48, color: Color(0xFF75715E)),
                      SizedBox(height: 16),
                      Text(
                        'No messages yet',
                        style: TextStyle(color: Color(0xFF75715E)),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Start the conversation!',
                        style: TextStyle(fontSize: 12, color: Color(0xFF75715E)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: chatState.messages.length,
                  itemBuilder: (context, index) {
                    final message = chatState.messages[index];
                    final showAvatar = index == 0 ||
                        chatState.messages[index - 1].senderId != message.senderId;
                    
                    return _MessageBubble(
                      message: message,
                      showAvatar: showAvatar,
                    );
                  },
                ),
        ),
        
        // Input area
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Color(0xFF3E3D32),
            border: Border(
              top: BorderSide(color: Color(0xFF272822)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(color: Color(0xFFF8F8F2), fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: const TextStyle(color: Color(0xFF75715E)),
                    filled: true,
                    fillColor: const Color(0xFF272822),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _sendMessage,
                icon: const Icon(Icons.send),
                color: const Color(0xFF66D9EF),
                tooltip: 'Send',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool showAvatar;
  
  const _MessageBubble({
    required this.message,
    required this.showAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    
    return Padding(
      padding: EdgeInsets.only(
        top: showAvatar ? 12 : 2,
        bottom: 2,
      ),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar (for others' messages)
          if (!isMe) ...[
            if (showAvatar)
              _Avatar(
                name: message.senderName,
                color: message.senderColor,
              )
            else
              const SizedBox(width: 32),
            const SizedBox(width: 8),
          ],
          
          // Message content
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 240),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMe
                    ? const Color(0xFF66D9EF).withValues(alpha: 0.2)
                    : const Color(0xFF3E3D32),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender name (for others' messages)
                  if (!isMe && showAvatar)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        message.senderName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _parseColor(message.senderColor) ?? const Color(0xFF66D9EF),
                        ),
                      ),
                    ),
                  
                  // Message text
                  Text(
                    message.text,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFFF8F8F2),
                    ),
                  ),
                  
                  // Timestamp
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _formatTime(message.timestamp),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF75715E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Spacer for my messages
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }
  
  Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      final cleanHex = hex.replaceAll('#', '');
      return Color(int.parse('FF$cleanHex', radix: 16));
    } catch (_) {
      return null;
    }
  }
  
  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final String? color;
  
  const _Avatar({
    required this.name,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = _parseColor(color) ?? const Color(0xFF66D9EF);
    
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF272822),
          ),
        ),
      ),
    );
  }
  
  Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      final cleanHex = hex.replaceAll('#', '');
      return Color(int.parse('FF$cleanHex', radix: 16));
    } catch (_) {
      return null;
    }
  }
}
