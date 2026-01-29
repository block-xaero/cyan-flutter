// widgets/full_chat_view.dart
// Full-screen chat view with proper group/workspace/board scoping

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../providers/selection_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/file_tree_provider.dart';
import '../theme/monokai_theme.dart';

class FullChatView extends ConsumerWidget {
  const FullChatView({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionProvider);
    final fileTreeState = ref.watch(fileTreeProvider);
    
    // Build context and get workspace IDs for group chat
    final result = _buildChatContext(selection, fileTreeState);
    
    return _ChatViewContent(
      key: ValueKey(result.context.id),
      chatContext: result.context,
      workspaceIdsForGroup: result.workspaceIds,
    );
  }
  
  _ChatContextResult _buildChatContext(SelectionState selection, FileTreeState treeState) {
    // Board context
    if (selection.boardId != null && selection.workspaceId != null) {
      return _ChatContextResult(
        context: ChatContextInfo.board(
          id: selection.boardId!,
          workspaceId: selection.workspaceId!,
          groupId: selection.groupId ?? '',
          name: selection.boardName ?? 'Board',
        ),
        workspaceIds: [],
      );
    }
    
    // Workspace context
    if (selection.workspaceId != null) {
      return _ChatContextResult(
        context: ChatContextInfo.workspace(
          id: selection.workspaceId!,
          groupId: selection.groupId ?? '',
          name: selection.workspaceName ?? 'Workspace',
        ),
        workspaceIds: [],
      );
    }
    
    // Group context - collect all workspace IDs in the group
    if (selection.groupId != null) {
      final group = treeState.groups.where((g) => g.id == selection.groupId).firstOrNull;
      final workspaceIds = group?.workspaces.map((w) => w.id).toList() ?? [];
      
      return _ChatContextResult(
        context: ChatContextInfo.group(
          id: selection.groupId!,
          name: selection.groupName ?? 'Group',
        ),
        workspaceIds: workspaceIds,
      );
    }
    
    // Global - collect ALL workspace IDs
    final allWorkspaceIds = <String>[];
    for (final group in treeState.groups) {
      for (final ws in group.workspaces) {
        allWorkspaceIds.add(ws.id);
      }
    }
    
    return _ChatContextResult(
      context: ChatContextInfo.global(),
      workspaceIds: allWorkspaceIds,
    );
  }
}

class _ChatContextResult {
  final ChatContextInfo context;
  final List<String> workspaceIds;
  
  _ChatContextResult({required this.context, required this.workspaceIds});
}

// ============================================================================
// CHAT VIEW CONTENT
// ============================================================================

class _ChatViewContent extends ConsumerStatefulWidget {
  final ChatContextInfo chatContext;
  final List<String> workspaceIdsForGroup;
  
  const _ChatViewContent({
    super.key,
    required this.chatContext,
    required this.workspaceIdsForGroup,
  });
  
  @override
  ConsumerState<_ChatViewContent> createState() => _ChatViewContentState();
}

class _ChatViewContentState extends ConsumerState<_ChatViewContent> {
  final _scrollController = ScrollController();
  final _messageController = TextEditingController();
  final _focusNode = FocusNode();
  
  @override
  void dispose() {
    _scrollController.dispose();
    _messageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    // Use the provider with workspace IDs for proper group chat loading
    final params = ChatWithWorkspacesParams(
      context: widget.chatContext,
      workspaceIds: widget.workspaceIdsForGroup,
    );
    final chatState = ref.watch(chatWithWorkspacesProvider(params));
    
    return Container(
      color: MonokaiTheme.background,
      child: Column(
        children: [
          _ChatHeader(
            context: widget.chatContext,
            isLoading: chatState.isLoadingHistory,
            messageCount: chatState.messages.length,
            onClose: () => ref.read(viewModeProvider.notifier).showExplorer(),
          ),
          
          const Divider(height: 1, color: MonokaiTheme.divider),
          
          Expanded(
            child: chatState.messages.isEmpty
                ? _EmptyChat(context: widget.chatContext, isLoading: chatState.isLoadingHistory)
                : _MessagesList(
                    messages: chatState.messages,
                    scrollController: _scrollController,
                  ),
          ),
          
          const Divider(height: 1, color: MonokaiTheme.divider),
          
          _ChatInput(
            controller: _messageController,
            focusNode: _focusNode,
            onSend: _sendMessage,
            canSend: _canSend(),
          ),
        ],
      ),
    );
  }
  
  bool _canSend() {
    // Can send if we have workspace context or workspaces in group
    return widget.chatContext.workspaceId != null || 
           widget.workspaceIdsForGroup.isNotEmpty;
  }
  
  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    final params = ChatWithWorkspacesParams(
      context: widget.chatContext,
      workspaceIds: widget.workspaceIdsForGroup,
    );
    ref.read(chatWithWorkspacesProvider(params).notifier).sendMessage(text);
    _messageController.clear();
    _focusNode.requestFocus();
    
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

// ============================================================================
// HEADER
// ============================================================================

class _ChatHeader extends StatelessWidget {
  final ChatContextInfo context;
  final bool isLoading;
  final int messageCount;
  final VoidCallback onClose;
  
  const _ChatHeader({
    required this.context,
    required this.isLoading,
    required this.messageCount,
    required this.onClose,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: MonokaiTheme.surface,
      child: Row(
        children: [
          Icon(_iconForType(this.context.type), size: 18, color: MonokaiTheme.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  this.context.title,
                  style: MonokaiTheme.titleSmall.copyWith(color: MonokaiTheme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$messageCount messages',
                  style: MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.textMuted),
                ),
              ],
            ),
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: MonokaiTheme.cyan),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: MonokaiTheme.textMuted,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
  
  IconData _iconForType(ChatContextType type) {
    switch (type) {
      case ChatContextType.global: return Icons.public;
      case ChatContextType.group: return Icons.folder;
      case ChatContextType.workspace: return Icons.workspaces_outline;
      case ChatContextType.board: return Icons.dashboard;
      case ChatContextType.directMessage: return Icons.person;
    }
  }
}

// ============================================================================
// MESSAGES LIST
// ============================================================================

class _MessagesList extends StatelessWidget {
  final List<ChatMessage> messages;
  final ScrollController scrollController;
  
  const _MessagesList({required this.messages, required this.scrollController});
  
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
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
    final isOwn = message.isOwn;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isOwn) ...[
            _Avatar(name: message.displayAuthor),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isOwn ? MonokaiTheme.cyan.withOpacity(0.2) : MonokaiTheme.surfaceLight,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(isOwn ? 12 : 4),
                  bottomRight: Radius.circular(isOwn ? 4 : 12),
                ),
                border: message.mentionsMe ? Border.all(color: MonokaiTheme.yellow, width: 1) : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isOwn)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        message.displayAuthor,
                        style: MonokaiTheme.labelSmall.copyWith(
                          color: MonokaiTheme.cyan,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Text(message.message, style: MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                    message.displayTime,
                    style: MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.textMuted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
          if (isOwn) ...[
            const SizedBox(width: 8),
            _Avatar(name: 'Me', isOwn: true),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final bool isOwn;
  
  const _Avatar({required this.name, this.isOwn = false});
  
  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    
    return Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: isOwn ? MonokaiTheme.cyan : MonokaiTheme.purple,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(initial, style: MonokaiTheme.labelSmall.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ============================================================================
// INPUT
// ============================================================================

class _ChatInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final bool canSend;
  
  const _ChatInput({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.canSend,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: MonokaiTheme.surface,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: canSend,
              style: MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.textPrimary),
              decoration: InputDecoration(
                hintText: canSend ? 'Type a message...' : 'Select a workspace to chat',
                hintStyle: MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.textMuted),
                filled: true,
                fillColor: MonokaiTheme.background,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: MonokaiTheme.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: MonokaiTheme.cyan)),
                disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: MonokaiTheme.border.withOpacity(0.5))),
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: canSend ? (_) => onSend() : null,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            color: canSend ? MonokaiTheme.cyan : MonokaiTheme.textMuted,
            onPressed: canSend ? onSend : null,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// EMPTY STATE
// ============================================================================

class _EmptyChat extends StatelessWidget {
  final ChatContextInfo context;
  final bool isLoading;
  
  const _EmptyChat({required this.context, this.isLoading = false});
  
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLoading ? Icons.hourglass_empty : Icons.chat_bubble_outline,
            size: 48,
            color: MonokaiTheme.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            isLoading ? 'Loading messages...' : 'No messages yet',
            style: MonokaiTheme.titleMedium.copyWith(color: MonokaiTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            isLoading ? 'Please wait...' : 'Be the first to send a message',
            style: MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.textMuted),
          ),
        ],
      ),
    );
  }
}
