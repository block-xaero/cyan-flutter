// widgets/chat_panel.dart
// Enhanced chat panel with peers sidebar, markdown, and DMs

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../providers/dm_provider.dart';
import '../models/chat_models.dart';
import 'markdown_chat.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CHAT PANEL (main widget)
// ═══════════════════════════════════════════════════════════════════════════

class ChatPanel extends ConsumerStatefulWidget {
  final ChatContextInfo? context;
  final VoidCallback? onClose;
  final double? width;

  const ChatPanel({
    super.key,
    this.context,
    this.onClose,
    this.width,
  });

  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  bool _showPreview = false;
  bool _showPeers = true;

  @override
  void initState() {
    super.initState();
    if (widget.context != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(chatProvider.notifier).setContext(widget.context!);
      });
    }
  }

  @override
  void didUpdateWidget(ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.context != oldWidget.context && widget.context != null) {
      ref.read(chatProvider.notifier).setContext(widget.context!);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    
    ref.read(chatProvider.notifier).sendMessage(text);
    _inputController.clear();
    _showPreview = false;
    setState(() {});
    
    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final ctx = widget.context ?? chatState.context;

    return Container(
      width: widget.width,
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          // Header
          _ChatHeader(
            context: ctx,
            onClose: widget.onClose,
            showPeers: _showPeers,
            onTogglePeers: () => setState(() => _showPeers = !_showPeers),
          ),
          
          // Main content
          Expanded(
            child: Row(
              children: [
                // Messages
                Expanded(
                  child: Column(
                    children: [
                      // Message list
                      Expanded(
                        child: chatState.isLoading
                            ? const Center(child: CircularProgressIndicator(color: Color(0xFF66D9EF)))
                            : chatState.messages.isEmpty
                                ? _EmptyMessages(context: ctx)
                                : _MessageList(
                                    messages: chatState.messages,
                                    controller: _scrollController,
                                  ),
                      ),
                      
                      // Input
                      _ChatInput(
                        controller: _inputController,
                        focusNode: _inputFocusNode,
                        showPreview: _showPreview,
                        onTogglePreview: () => setState(() => _showPreview = !_showPreview),
                        onSend: _sendMessage,
                        isSending: chatState.isSending,
                      ),
                    ],
                  ),
                ),
                
                // Peers sidebar
                if (_showPeers)
                  _PeersSidebar(
                    peers: chatState.onlinePeers,
                    onPeerTap: (peer) {
                      ref.read(chatProvider.notifier).startDirectMessage(peer);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHAT HEADER
// ═══════════════════════════════════════════════════════════════════════════

class _ChatHeader extends StatelessWidget {
  final ChatContextInfo? context;
  final VoidCallback? onClose;
  final bool showPeers;
  final VoidCallback onTogglePeers;

  const _ChatHeader({
    this.context,
    this.onClose,
    required this.showPeers,
    required this.onTogglePeers,
  });

  @override
  Widget build(BuildContext context) {
    final ctx = this.context;
    
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(bottom: BorderSide(color: Color(0xFF3E3D32))),
      ),
      child: Row(
        children: [
          // Context icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: (ctx?.color ?? const Color(0xFF808080)).withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              ctx?.icon ?? Icons.chat,
              size: 16,
              color: ctx?.color ?? const Color(0xFF808080),
            ),
          ),
          const SizedBox(width: 10),
          
          // Title
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ctx?.title ?? 'Chat',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF8F8F2),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (ctx != null)
                  Text(
                    ctx.type.name,
                    style: TextStyle(
                      fontSize: 10,
                      color: ctx.color,
                    ),
                  ),
              ],
            ),
          ),
          
          // Peers toggle
          IconButton(
            icon: Icon(
              showPeers ? Icons.people : Icons.people_outline,
              size: 18,
            ),
            color: showPeers ? const Color(0xFF66D9EF) : const Color(0xFF808080),
            onPressed: onTogglePeers,
            tooltip: showPeers ? 'Hide peers' : 'Show peers',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          
          // Close
          if (onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: const Color(0xFF808080),
              onPressed: onClose,
              tooltip: 'Close',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MESSAGE LIST
// ═══════════════════════════════════════════════════════════════════════════

class _MessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final ScrollController controller;

  const _MessageList({required this.messages, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.all(12),
      itemCount: messages.length,
      itemBuilder: (ctx, i) => _MessageBubble(message: messages[i]),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: message.isOwn
                  ? const Color(0xFF66D9EF).withOpacity(0.2)
                  : const Color(0xFFA6E22E).withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                message.displayAuthor[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: message.isOwn ? const Color(0xFF66D9EF) : const Color(0xFFA6E22E),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author + time
                Row(
                  children: [
                    Text(
                      message.displayAuthor,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: message.isOwn ? const Color(0xFF66D9EF) : const Color(0xFFA6E22E),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      message.displayTime,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF808080)),
                    ),
                    if (message.mentionsMe) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF92672).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          '@mention',
                          style: TextStyle(fontSize: 9, color: Color(0xFFF92672)),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                
                // Markdown rendered content
                MarkdownRenderer(markdown: message.message, fontSize: 13),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EMPTY MESSAGES
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyMessages extends StatelessWidget {
  final ChatContextInfo? context;
  
  const _EmptyMessages({this.context});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            this.context?.icon ?? Icons.chat_bubble_outline,
            size: 48,
            color: const Color(0xFF606060),
          ),
          const SizedBox(height: 12),
          Text(
            this.context != null ? 'Start the conversation' : 'Select a chat',
            style: const TextStyle(fontSize: 14, color: Color(0xFF808080)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Messages support **markdown** and `code`',
            style: TextStyle(fontSize: 11, color: Color(0xFF606060)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHAT INPUT
// ═══════════════════════════════════════════════════════════════════════════

class _ChatInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool showPreview;
  final VoidCallback onTogglePreview;
  final VoidCallback onSend;
  final bool isSending;

  const _ChatInput({
    required this.controller,
    required this.focusNode,
    required this.showPreview,
    required this.onTogglePreview,
    required this.onSend,
    this.isSending = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(top: BorderSide(color: Color(0xFF3E3D32))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Preview
          if (showPreview && controller.text.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF3E3D32)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Preview',
                    style: TextStyle(fontSize: 10, color: Color(0xFF808080)),
                  ),
                  const SizedBox(height: 6),
                  MarkdownRenderer(markdown: controller.text, fontSize: 13),
                ],
              ),
            ),
          ],
          
          // Input row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Text field
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF3E3D32)),
                  ),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    maxLines: null,
                    style: const TextStyle(color: Color(0xFFF8F8F2), fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Type a message... (**bold**, `code`, ```block```)',
                      hintStyle: TextStyle(color: Color(0xFF808080), fontSize: 12),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
              ),
              
              const SizedBox(width: 8),
              
              // Preview toggle
              IconButton(
                icon: Icon(
                  showPreview ? Icons.visibility : Icons.visibility_outlined,
                  size: 18,
                ),
                color: showPreview ? const Color(0xFF66D9EF) : const Color(0xFF808080),
                onPressed: onTogglePreview,
                tooltip: 'Preview markdown',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              
              // Send button
              Container(
                decoration: BoxDecoration(
                  color: controller.text.trim().isNotEmpty
                      ? const Color(0xFF66D9EF)
                      : const Color(0xFF3E3D32),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF1E1E1E),
                          ),
                        )
                      : const Icon(Icons.send, size: 18),
                  color: controller.text.trim().isNotEmpty
                      ? const Color(0xFF1E1E1E)
                      : const Color(0xFF606060),
                  onPressed: controller.text.trim().isNotEmpty && !isSending ? onSend : null,
                  padding: const EdgeInsets.all(10),
                  constraints: const BoxConstraints(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PEERS SIDEBAR
// ═══════════════════════════════════════════════════════════════════════════

class _PeersSidebar extends StatelessWidget {
  final List<PeerInfo> peers;
  final ValueChanged<PeerInfo> onPeerTap;

  const _PeersSidebar({required this.peers, required this.onPeerTap});

  @override
  Widget build(BuildContext context) {
    final onlinePeers = peers.where((p) => p.isOnline).toList();
    final offlinePeers = peers.where((p) => !p.isOnline).toList();

    return Container(
      width: 180,
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(left: BorderSide(color: Color(0xFF3E3D32))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.people, size: 14, color: Color(0xFF808080)),
                const SizedBox(width: 6),
                Text(
                  'Peers (${onlinePeers.length})',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF808080),
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1, color: Color(0xFF3E3D32)),
          
          // Online peers
          if (onlinePeers.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                'ONLINE',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFFA6E22E)),
              ),
            ),
            ...onlinePeers.map((p) => _PeerTile(peer: p, onTap: () => onPeerTap(p))),
          ],
          
          // Offline peers
          if (offlinePeers.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text(
                'OFFLINE',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF808080)),
              ),
            ),
            ...offlinePeers.map((p) => _PeerTile(peer: p, onTap: () => onPeerTap(p))),
          ],
          
          const Spacer(),
          
          // Tip
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Click to start DM',
              style: TextStyle(fontSize: 10, color: Color(0xFF606060)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  final PeerInfo peer;
  final VoidCallback onTap;

  const _PeerTile({required this.peer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: peer.avatarColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Text(
                      peer.initial,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: peer.avatarColor,
                      ),
                    ),
                  ),
                  // Online indicator
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: peer.isOnline ? const Color(0xFFA6E22E) : const Color(0xFF808080),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF252525), width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            
            // Name
            Expanded(
              child: Text(
                peer.displayName,
                style: TextStyle(
                  fontSize: 11,
                  color: peer.isOnline ? const Color(0xFFF8F8F2) : const Color(0xFF808080),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            
            // Unread badge
            if (peer.unreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF92672),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${peer.unreadCount}',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
