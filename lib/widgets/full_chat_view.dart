// widgets/full_chat_view.dart
// Full-screen chat view with proper group/workspace/board scoping

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../providers/selection_provider.dart';
import '../providers/file_tree_provider.dart';
import 'scoped_chat_panel.dart';

class FullChatView extends ConsumerWidget {
  const FullChatView({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionProvider);
    final fileTreeState = ref.watch(fileTreeProvider);
    
    // Build context
    final chatContext = _buildChatContext(selection, fileTreeState);
    
    return ScopedChatPanel(
      key: ValueKey(chatContext.id),
      context: chatContext,
    );
  }
  
  ChatContextInfo _buildChatContext(SelectionState selection, FileTreeState treeState) {
    // Board context
    if (selection.boardId != null && selection.workspaceId != null) {
      return ChatContextInfo.board(
        id: selection.boardId!,
        workspaceId: selection.workspaceId!,
        groupId: selection.groupId ?? '',
        name: selection.boardName ?? 'Board',
      );
    }
    
    // Workspace context
    if (selection.workspaceId != null) {
      return ChatContextInfo.workspace(
        id: selection.workspaceId!,
        groupId: selection.groupId ?? '',
        name: selection.workspaceName ?? 'Workspace',
      );
    }
    
    // Group context
    if (selection.groupId != null) {
      return ChatContextInfo.group(
        id: selection.groupId!,
        name: selection.groupName ?? 'Group',
      );
    }
    
    // Global fallback
    return ChatContextInfo.global();
  }
}
