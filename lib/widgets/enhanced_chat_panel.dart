// widgets/enhanced_chat_panel.dart
// Enhanced chat panel with:
// - Markdown rendering
// - Code block formatting (```)
// - Peer panel (online peers in context)
// - File attachments panel
// - DM support (click peer → open DM)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_models.dart';
import '../providers/dm_provider.dart';
import '../theme/monokai_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ENHANCED CHAT PANEL
// ═══════════════════════════════════════════════════════════════════════════

class EnhancedChatPanel extends ConsumerStatefulWidget {
  final ChatContext context;
  final VoidCallback? onClose;

  const EnhancedChatPanel({
    super.key,
    required this.context,
    this.onClose,
  });

  @override
  ConsumerState<EnhancedChatPanel> createState() => _EnhancedChatPanelState();
}

class _EnhancedChatPanelState extends ConsumerState<EnhancedChatPanel> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  bool _showPeerPanel = true;
  bool _showFilesPanel = false;
  bool _isInCodeBlock = false;

  // Mock data for now - would come from provider
  final List<EnhancedChatMessage> _messages = [];
  final List<PeerInfo> _peers = [
    PeerInfo.fromPublicKey('mock_alice_abc123def456ghi789', isOnline: true),
    PeerInfo.fromPublicKey('mock_bob_xyz789ghi012jkl345', isOnline: true),
    PeerInfo.fromPublicKey('mock_charlie_mno345pqr678stu', isOnline: false),
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleTextChange(String text) {
    // Detect code block start
    final hasOpenCodeBlock = '```'.allMatches(text).length % 2 == 1;
    if (hasOpenCodeBlock != _isInCodeBlock) {
      setState(() => _isInCodeBlock = hasOpenCodeBlock);
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    // Create message
    final message = EnhancedChatMessage(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      workspaceId: widget.context.workspaceId ?? '',
      authorId: 'me',
      authorName: 'Me',
      timestamp: DateTime.now(),
      isOwn: true,
      content: EnhancedChatMessage.parseContent(text),
    );

    setState(() {
      _messages.add(message);
      _isInCodeBlock = false;
    });

    _messageController.clear();
    _focusNode.requestFocus();

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

    // TODO: Send via ComponentBridge
  }

  void _openDM(PeerInfo peer) {
    ref.read(dmProvider.notifier).openConversation(peer);
    // TODO: Switch to DMs view
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MonokaiTheme.background,
      child: Column(
        children: [
          // Header
          _ChatHeader(
            title: widget.context.title,
            showPeerPanel: _showPeerPanel,
            showFilesPanel: _showFilesPanel,
            onTogglePeerPanel: () => setState(() => _showPeerPanel = !_showPeerPanel),
            onToggleFilesPanel: () => setState(() => _showFilesPanel = !_showFilesPanel),
            onClose: widget.onClose,
          ),

          // Content area
          Expanded(
            child: Row(
              children: [
                // Messages
                Expanded(
                  child: Column(
                    children: [
                      // Messages list
                      Expanded(
                        child: _messages.isEmpty
                            ? const _EmptyMessages()
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(12),
                                itemCount: _messages.length,
                                itemBuilder: (ctx, i) {
                                  final msg = _messages[i];
                                  final showAvatar = i == 0 ||
                                      _messages[i - 1].authorId != msg.authorId;
                                  return _MessageBubble(
                                    message: msg,
                                    showAvatar: showAvatar,
                                    onPeerTap: (peerId) {
                                      final peer = _peers.firstWhere(
                                        (p) => p.id == peerId,
                                        orElse: () => PeerInfo.fromPublicKey(peerId),
                                      );
                                      _openDM(peer);
                                    },
                                  );
                                },
                              ),
                      ),

                      // Files panel (collapsible)
                      if (_showFilesPanel) _FilesPanel(messages: _messages),

                      // Input area
                      _ChatInput(
                        controller: _messageController,
                        focusNode: _focusNode,
                        isInCodeBlock: _isInCodeBlock,
                        onChanged: _handleTextChange,
                        onSend: _sendMessage,
                        onAttachFile: () {
                          // TODO: File picker
                        },
                      ),
                    ],
                  ),
                ),

                // Peer panel (collapsible)
                if (_showPeerPanel)
                  _PeerPanel(
                    peers: _peers,
                    contextType: widget.context.type,
                    onPeerTap: _openDM,
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
  final String title;
  final bool showPeerPanel;
  final bool showFilesPanel;
  final VoidCallback onTogglePeerPanel;
  final VoidCallback onToggleFilesPanel;
  final VoidCallback? onClose;

  const _ChatHeader({
    required this.title,
    required this.showPeerPanel,
    required this.showFilesPanel,
    required this.onTogglePeerPanel,
    required this.onToggleFilesPanel,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface,
        border: Border(bottom: BorderSide(color: MonokaiTheme.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.forum, size: 16, color: MonokaiTheme.cyan),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: MonokaiTheme.foreground,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Toggle buttons
          _HeaderToggle(
            icon: Icons.people_outline,
            isActive: showPeerPanel,
            tooltip: 'Toggle peers panel',
            onTap: onTogglePeerPanel,
          ),
          const SizedBox(width: 4),
          _HeaderToggle(
            icon: Icons.attach_file,
            isActive: showFilesPanel,
            tooltip: 'Toggle files panel',
            onTap: onToggleFilesPanel,
          ),

          if (onClose != null) ...[
            const SizedBox(width: 8),
            _HeaderToggle(
              icon: Icons.close,
              isActive: false,
              tooltip: 'Close chat',
              onTap: onClose!,
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderToggle extends StatefulWidget {
  final IconData icon;
  final bool isActive;
  final String tooltip;
  final VoidCallback onTap;

  const _HeaderToggle({
    required this.icon,
    required this.isActive,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_HeaderToggle> createState() => _HeaderToggleState();
}

class _HeaderToggleState extends State<_HeaderToggle> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: widget.isActive
                  ? MonokaiTheme.cyan.withOpacity(0.2)
                  : (_isHovered ? MonokaiTheme.surface : Colors.transparent),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: widget.isActive
                  ? MonokaiTheme.cyan
                  : (_isHovered ? MonokaiTheme.foreground : MonokaiTheme.comment),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PEER PANEL
// ═══════════════════════════════════════════════════════════════════════════

class _PeerPanel extends StatelessWidget {
  final List<PeerInfo> peers;
  final ChatContextType contextType;
  final void Function(PeerInfo) onPeerTap;

  const _PeerPanel({
    required this.peers,
    required this.contextType,
    required this.onPeerTap,
  });

  @override
  Widget build(BuildContext context) {
    final onlinePeers = peers.where((p) => p.isOnline).toList();
    final offlinePeers = peers.where((p) => !p.isOnline).toList();

    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: MonokaiTheme.surface,
        border: Border(left: BorderSide(color: MonokaiTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text(
                  'PEERS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: MonokaiTheme.comment,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: MonokaiTheme.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${onlinePeers.length}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: MonokaiTheme.green,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Online peers
          if (onlinePeers.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                'Online',
                style: TextStyle(fontSize: 10, color: MonokaiTheme.comment),
              ),
            ),
            ...onlinePeers.map((p) => _PeerItem(
                  peer: p,
                  onTap: () => onPeerTap(p),
                )),
          ],

          // Offline peers
          if (offlinePeers.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text(
                'Offline',
                style: TextStyle(fontSize: 10, color: MonokaiTheme.comment),
              ),
            ),
            ...offlinePeers.map((p) => _PeerItem(
                  peer: p,
                  onTap: () => onPeerTap(p),
                )),
          ],

          const Spacer(),
        ],
      ),
    );
  }
}

class _PeerItem extends StatefulWidget {
  final PeerInfo peer;
  final VoidCallback onTap;

  const _PeerItem({required this.peer, required this.onTap});

  @override
  State<_PeerItem> createState() => _PeerItemState();
}

class _PeerItemState extends State<_PeerItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: _isHovered ? MonokaiTheme.cyan.withOpacity(0.1) : Colors.transparent,
          child: Row(
            children: [
              // Online indicator
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.peer.isOnline
                      ? MonokaiTheme.green
                      : MonokaiTheme.comment.withOpacity(0.5),
                ),
              ),
              const SizedBox(width: 8),

              // Name
              Expanded(
                child: Text(
                  widget.peer.displayName,
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.peer.isOnline
                        ? MonokaiTheme.foreground
                        : MonokaiTheme.comment,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Unread badge
              if (widget.peer.unreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: MonokaiTheme.pink,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${widget.peer.unreadCount}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),

              // DM icon on hover
              if (_isHovered)
                Icon(
                  Icons.chat_bubble_outline,
                  size: 14,
                  color: MonokaiTheme.cyan,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FILES PANEL
// ═══════════════════════════════════════════════════════════════════════════

class _FilesPanel extends StatelessWidget {
  final List<EnhancedChatMessage> messages;

  const _FilesPanel({required this.messages});

  List<ChatFileAttachment> get _files {
    final files = <ChatFileAttachment>[];
    for (final msg in messages) {
      for (final content in msg.content) {
        if (content is FileContent) {
          files.add(ChatFileAttachment(
            messageId: msg.id,
            fileId: content.fileId,
            fileName: content.fileName,
            fileSize: content.fileSize,
            mimeType: content.mimeType,
            authorName: msg.authorName,
            timestamp: msg.timestamp,
          ));
        }
      }
    }
    return files.reversed.toList(); // Most recent first
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;

    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: MonokaiTheme.surface,
        border: Border(top: BorderSide(color: MonokaiTheme.border)),
      ),
      child: files.isEmpty
          ? Center(
              child: Text(
                'No files shared',
                style: TextStyle(fontSize: 12, color: MonokaiTheme.comment),
              ),
            )
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(8),
              itemCount: files.length,
              itemBuilder: (ctx, i) => _FileCard(file: files[i]),
            ),
    );
  }
}

class _FileCard extends StatelessWidget {
  final ChatFileAttachment file;

  const _FileCard({required this.file});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: MonokaiTheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MonokaiTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(file.icon, size: 24, color: MonokaiTheme.cyan),
          const SizedBox(height: 4),
          Expanded(
            child: Text(
              file.fileName,
              style: TextStyle(fontSize: 11, color: MonokaiTheme.foreground),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            file.formattedSize,
            style: TextStyle(fontSize: 10, color: MonokaiTheme.comment),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MESSAGE BUBBLE
// ═══════════════════════════════════════════════════════════════════════════

class _MessageBubble extends StatelessWidget {
  final EnhancedChatMessage message;
  final bool showAvatar;
  final void Function(String peerId)? onPeerTap;

  const _MessageBubble({
    required this.message,
    required this.showAvatar,
    this.onPeerTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: showAvatar ? 12 : 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          if (showAvatar)
            GestureDetector(
              onTap: message.isOwn ? null : () => onPeerTap?.call(message.authorId),
              child: _Avatar(
                name: message.authorName,
                isOnline: true, // TODO: Get from peer status
              ),
            )
          else
            const SizedBox(width: 36),

          const SizedBox(width: 8),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header (name, pubkey, time)
                if (showAvatar)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: message.isOwn ? null : () => onPeerTap?.call(message.authorId),
                          child: Text(
                            message.authorName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: message.isOwn ? MonokaiTheme.cyan : MonokaiTheme.purple,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          message.shortAuthorId,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: MonokaiTheme.comment,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatTime(message.timestamp),
                          style: TextStyle(
                            fontSize: 10,
                            color: MonokaiTheme.comment,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Content blocks
                ...message.content.map((block) => _ContentBlock(content: block)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final bool isOnline;

  const _Avatar({required this.name, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: MonokaiTheme.purple.withOpacity(0.3),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: MonokaiTheme.purple,
              ),
            ),
          ),
        ),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: MonokaiTheme.green,
                shape: BoxShape.circle,
                border: Border.all(color: MonokaiTheme.background, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONTENT BLOCKS
// ═══════════════════════════════════════════════════════════════════════════

class _ContentBlock extends StatelessWidget {
  final MessageContent content;

  const _ContentBlock({required this.content});

  @override
  Widget build(BuildContext context) {
    return switch (content) {
      TextContent(text: var text) => _TextBlock(text: text),
      CodeContent(code: var code, language: var lang) =>
        _CodeBlock(code: code, language: lang),
      FileContent() => _FileBlock(file: content as FileContent),
    };
  }
}

class _TextBlock extends StatelessWidget {
  final String text;

  const _TextBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    // Simple markdown-like rendering
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SelectableText(
        text,
        style: TextStyle(
          fontSize: 14,
          color: MonokaiTheme.foreground,
          height: 1.4,
        ),
      ),
    );
  }
}

class _CodeBlock extends StatefulWidget {
  final String code;
  final String? language;

  const _CodeBlock({required this.code, this.language});

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MonokaiTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: MonokaiTheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                if (widget.language != null)
                  Text(
                    widget.language!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: MonokaiTheme.cyan,
                    ),
                  ),
                const Spacer(),
                GestureDetector(
                  onTap: _copy,
                  child: Row(
                    children: [
                      Icon(
                        _copied ? Icons.check : Icons.copy,
                        size: 14,
                        color: _copied ? MonokaiTheme.green : MonokaiTheme.comment,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _copied ? 'Copied!' : 'Copy',
                        style: TextStyle(
                          fontSize: 11,
                          color: _copied ? MonokaiTheme.green : MonokaiTheme.comment,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Code
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              widget.code,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: MonokaiTheme.foreground,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileBlock extends StatelessWidget {
  final FileContent file;

  const _FileBlock({required this.file});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MonokaiTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file, size: 24, color: MonokaiTheme.cyan),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                file.fileName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: MonokaiTheme.foreground,
                ),
              ),
              Text(
                '${(file.fileSize / 1024).toStringAsFixed(1)} KB',
                style: TextStyle(fontSize: 11, color: MonokaiTheme.comment),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Icon(Icons.download, size: 20, color: MonokaiTheme.comment),
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
  final bool isInCodeBlock;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback onAttachFile;

  const _ChatInput({
    required this.controller,
    required this.focusNode,
    required this.isInCodeBlock,
    required this.onChanged,
    required this.onSend,
    required this.onAttachFile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface,
        border: Border(top: BorderSide(color: MonokaiTheme.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Attach file
          IconButton(
            icon: Icon(Icons.attach_file, color: MonokaiTheme.comment),
            iconSize: 20,
            onPressed: onAttachFile,
            tooltip: 'Attach file',
          ),

          // Input field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 150),
              decoration: BoxDecoration(
                color: MonokaiTheme.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isInCodeBlock ? MonokaiTheme.cyan : MonokaiTheme.border,
                ),
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: null,
                style: TextStyle(
                  fontSize: 14,
                  color: MonokaiTheme.foreground,
                  fontFamily: isInCodeBlock ? 'monospace' : null,
                ),
                decoration: InputDecoration(
                  hintText: isInCodeBlock ? 'Type code... (close with ```)' : 'Type a message...',
                  hintStyle: TextStyle(color: MonokaiTheme.comment),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: onChanged,
                onSubmitted: (_) {
                  if (!isInCodeBlock) onSend();
                },
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Send button
          IconButton(
            icon: Icon(Icons.send, color: MonokaiTheme.cyan),
            iconSize: 20,
            onPressed: onSend,
            tooltip: 'Send',
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 48, color: MonokaiTheme.comment),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(fontSize: 14, color: MonokaiTheme.comment),
          ),
          const SizedBox(height: 4),
          Text(
            'Start the conversation!',
            style: TextStyle(fontSize: 12, color: MonokaiTheme.comment.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }
}
