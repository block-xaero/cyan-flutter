// widgets/dms_panel.dart
// Direct Messages panel - replaces standalone "Chat" icon
// Shows all DM conversations, click peer in chat → opens DM here

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dm_provider.dart';
import '../models/chat_models.dart';

class DMsPanel extends ConsumerStatefulWidget {
  const DMsPanel({super.key});

  @override
  ConsumerState<DMsPanel> createState() => _DMsPanelState();
}

class _DMsPanelState extends ConsumerState<DMsPanel> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dmState = ref.watch(dmProvider);

    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          // Header
          _buildHeader(dmState),

          // Content
          Expanded(
            child: dmState.activePeerId != null
                ? _buildConversationView(dmState)
                : _buildConversationsList(dmState),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(DMState state) {
    final hasActive = state.activePeerId != null;
    final activeConvo = state.activeConversation;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(bottom: BorderSide(color: Color(0xFF3E3D32))),
      ),
      child: Row(
        children: [
          if (hasActive) ...[
            // Back button
            GestureDetector(
              onTap: () => ref.read(dmProvider.notifier).closeConversation(),
              child: const MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.arrow_back,
                    size: 18,
                    color: Color(0xFF808080),
                  ),
                ),
              ),
            ),
            // Peer name
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: activeConvo?.isOnline == true
                          ? const Color(0xFFA6E22E)
                          : const Color(0xFF606060),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    activeConvo?.peerName ?? 'Unknown',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFF8F8F2),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const Icon(
              Icons.mark_chat_unread,
              size: 16,
              color: Color(0xFFF92672),
            ),
            const SizedBox(width: 8),
            const Text(
              'DIRECT MESSAGES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: Color(0xFF808080),
              ),
            ),
            const Spacer(),
            if (state.totalUnreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF92672),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${state.totalUnreadCount}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildConversationsList(DMState state) {
    if (state.conversations.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: state.conversations.length,
      itemBuilder: (context, index) {
        final convo = state.conversations[index];
        return _ConversationTile(
          conversation: convo,
          onTap: () {
            ref.read(dmProvider.notifier).openConversation(
                  PeerInfo(
                    id: convo.peerId,
                    displayName: convo.peerName,
                    isOnline: convo.isOnline,
                  ),
                );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: Color(0xFF606060),
          ),
          const SizedBox(height: 16),
          const Text(
            'No conversations yet',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF808080),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Click on a peer in any chat\nto start a direct message',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationView(DMState state) {
    final messages = state.activeMessages;

    return Column(
      children: [
        // Messages
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Text(
                    'Start the conversation!',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return _DMMessageBubble(message: msg);
                  },
                ),
        ),

        // Input
        _buildInputArea(),
      ],
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(top: BorderSide(color: Color(0xFF3E3D32))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Color(0xFFF8F8F2), fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: const TextStyle(color: Color(0xFF606060)),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            icon: const Icon(Icons.send),
            color: const Color(0xFF66D9EF),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    ref.read(dmProvider.notifier).sendMessage(text);
    _messageController.clear();

    // Scroll to bottom
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
}

// ═══════════════════════════════════════════════════════════════════════════
// CONVERSATION TILE
// ═══════════════════════════════════════════════════════════════════════════

class _ConversationTile extends StatefulWidget {
  final DMConversation conversation;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.onTap,
  });

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final convo = widget.conversation;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: _isHovered ? const Color(0xFF2A2A2A) : Colors.transparent,
          child: Row(
            children: [
              // Avatar with online indicator
              Stack(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFF66D9EF),
                    child: Text(
                      convo.peerName.isNotEmpty
                          ? convo.peerName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Color(0xFF272822),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: convo.isOnline
                            ? const Color(0xFFA6E22E)
                            : const Color(0xFF606060),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF1E1E1E),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),

              // Name and last message
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            convo.peerName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: convo.unreadCount > 0
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: const Color(0xFFF8F8F2),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (convo.lastMessageTime != null)
                          Text(
                            convo.displayTime,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF808080),
                            ),
                          ),
                      ],
                    ),
                    if (convo.lastMessage != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        convo.lastMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: convo.unreadCount > 0
                              ? const Color(0xFFCCCCCC)
                              : const Color(0xFF808080),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // Unread badge
              if (convo.unreadCount > 0)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF92672),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${convo.unreadCount}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DM MESSAGE BUBBLE
// ═══════════════════════════════════════════════════════════════════════════

class _DMMessageBubble extends StatelessWidget {
  final EnhancedChatMessage message;

  const _DMMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isOwn = message.isOwn;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isOwn
                  ? const Color(0xFF66D9EF).withOpacity(0.2)
                  : const Color(0xFF3E3D32),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isOwn ? 12 : 4),
                bottomRight: Radius.circular(isOwn ? 4 : 12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Render content blocks
                ...message.content.map((content) {
                  if (content.type == MessagePartType.text) {
                    return Text(
                      content.text,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFFF8F8F2),
                      ),
                    );
                  } else if (content.type == MessagePartType.code || content.type == MessagePartType.codeBlock) {
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF272822),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        content.text,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: Color(0xFFF8F8F2),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }),

                // Timestamp
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF606060),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
