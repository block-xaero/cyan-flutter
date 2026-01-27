// widgets/full_chat_view.dart
// Full-screen chat with markdown and file drop

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import 'file_tree_widget.dart';
import 'markdown_chat.dart';
import 'file_drop_target.dart';

class FullChatView extends ConsumerStatefulWidget {
  const FullChatView({super.key});
  
  @override
  ConsumerState<FullChatView> createState() => _FullChatViewState();
}

class _FullChatViewState extends ConsumerState<FullChatView> {
  final _scrollController = ScrollController();
  final _messages = <_ChatMsg>[];
  List<DroppedFile> _attachedFiles = [];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatContext = ref.watch(chatContextProvider);

    return FileDropTarget(
      onDrop: (files) => setState(() => _attachedFiles.addAll(files)),
      builder: (ctx, isDragging, _) => Container(
        color: const Color(0xFF1E1E1E),
        child: Stack(
          children: [
            Column(
              children: [
                _ChatHeader(
                  context: chatContext,
                  onClose: () => ref.read(viewModeProvider.notifier).showAllBoards(),
                ),
                Expanded(
                  child: _messages.isEmpty
                      ? _EmptyChat(context: chatContext)
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(20),
                          itemCount: _messages.length,
                          itemBuilder: (ctx, i) => ChatMessageWidget(
                            sender: _messages[i].sender,
                            content: _messages[i].content,
                            timestamp: _messages[i].timestamp,
                            isMe: _messages[i].isMe,
                            attachments: _messages[i].attachments.map((f) => f.name).toList(),
                          ),
                        ),
                ),
                if (_attachedFiles.isNotEmpty)
                  _AttachedFilesBar(
                    files: _attachedFiles,
                    onRemove: (f) => setState(() => _attachedFiles.remove(f)),
                  ),
                MarkdownChatInput(
                  onSend: _sendMessage,
                  attachments: _attachedFiles.map((f) => f.name).toList(),
                  onAttach: _pickFile,
                ),
              ],
            ),
            if (isDragging) _DropOverlay(),
          ],
        ),
      ),
      child: const SizedBox(),
    );
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty && _attachedFiles.isEmpty) return;
    setState(() {
      _messages.add(_ChatMsg(
        sender: 'You',
        content: text,
        timestamp: DateTime.now(),
        attachments: List.from(_attachedFiles),
        isMe: true,
      ));
      _attachedFiles.clear();
    });
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

  void _pickFile() {
    setState(() {
      _attachedFiles.add(DroppedFile(
        path: '/tmp/doc.pdf',
        name: 'document.pdf',
      ));
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════════════

class _ChatMsg {
  final String sender;
  final String content;
  final DateTime timestamp;
  final List<DroppedFile> attachments;
  final bool isMe;
  
  _ChatMsg({
    required this.sender,
    required this.content,
    required this.timestamp,
    this.attachments = const [],
    this.isMe = false,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// CHAT HEADER
// ═══════════════════════════════════════════════════════════════════════════

class _ChatHeader extends StatelessWidget {
  final ChatContextInfo? context;
  final VoidCallback onClose;
  
  const _ChatHeader({this.context, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final ctx = this.context;
    IconData icon;
    Color iconColor;
    String title;
    String subtitle;
    
    if (ctx != null) {
      title = ctx.title;
      switch (ctx.type) {
        case ChatContextType.group:
          icon = Icons.folder;
          iconColor = const Color(0xFF66D9EF);
          subtitle = 'Group Chat';
        case ChatContextType.workspace:
          icon = Icons.workspaces_outline;
          iconColor = const Color(0xFFA6E22E);
          subtitle = 'Workspace Chat';
        case ChatContextType.board:
          icon = Icons.dashboard;
          iconColor = const Color(0xFFF92672);
          subtitle = 'Board Chat';
        case ChatContextType.global:
          icon = Icons.public;
          iconColor = const Color(0xFFAE81FF);
          subtitle = 'Global Chat';
      }
    } else {
      icon = Icons.chat;
      iconColor = const Color(0xFF808080);
      title = 'Chat';
      subtitle = 'Select a context';
    }

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(bottom: BorderSide(color: Color(0xFF3E3D32))),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF8F8F2),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(subtitle, style: TextStyle(fontSize: 11, color: iconColor)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.people_outline, size: 18),
            color: const Color(0xFF808080),
            onPressed: () {},
            tooltip: 'Members',
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: const Color(0xFF808080),
            onPressed: onClose,
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EMPTY CHAT
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyChat extends StatelessWidget {
  final ChatContextInfo? context;
  const _EmptyChat({this.context});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            this.context != null ? Icons.chat_bubble_outline : Icons.forum_outlined,
            size: 48,
            color: const Color(0xFF606060),
          ),
          const SizedBox(height: 12),
          Text(
            this.context != null ? 'Start the conversation' : 'Select a chat',
            style: const TextStyle(fontSize: 16, color: Color(0xFF808080)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Type a message or drag files to attach',
            style: TextStyle(fontSize: 12, color: Color(0xFF606060)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ATTACHED FILES BAR
// ═══════════════════════════════════════════════════════════════════════════

class _AttachedFilesBar extends StatelessWidget {
  final List<DroppedFile> files;
  final ValueChanged<DroppedFile> onRemove;
  
  const _AttachedFilesBar({required this.files, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(top: BorderSide(color: Color(0xFF3E3D32))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.attach_file, size: 14, color: Color(0xFF808080)),
            const SizedBox(width: 8),
            ...files.map((f) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF3E3D32),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(f.icon, size: 14, color: f.iconColor),
                    const SizedBox(width: 6),
                    Text(f.name, style: const TextStyle(fontSize: 11, color: Color(0xFFF8F8F2))),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => onRemove(f),
                      child: const Icon(Icons.close, size: 14, color: Color(0xFF808080)),
                    ),
                  ],
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DROP OVERLAY
// ═══════════════════════════════════════════════════════════════════════════

class _DropOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: const Color(0xFF66D9EF).withOpacity(0.1),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF252525),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF66D9EF), width: 2),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_upload, size: 48, color: Color(0xFF66D9EF)),
                SizedBox(height: 16),
                Text('Drop files to attach', style: TextStyle(color: Color(0xFFF8F8F2), fontSize: 16)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
