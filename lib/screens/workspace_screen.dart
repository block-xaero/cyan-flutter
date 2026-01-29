// screens/workspace_screen.dart
// Main workspace screen with IconRail + content + StatusBar

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/monokai_theme.dart';
import '../widgets/icon_rail.dart';
import '../widgets/status_bar.dart';
import '../widgets/file_tree_widget.dart';
import '../widgets/all_boards_grid.dart';
import '../widgets/full_chat_view.dart';
import '../widgets/dms_panel.dart';
import '../widgets/board_detail_view.dart';
import '../providers/selection_provider.dart';
import '../providers/navigation_provider.dart';

class WorkspaceScreen extends ConsumerWidget {
  const WorkspaceScreen({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconRailShortcuts(
      child: Scaffold(
        body: Column(
          children: [
            // Main content area
            Expanded(
              child: Row(
                children: [
                  // Icon rail
                  const IconRail(),
                  
                  // Vertical divider
                  Container(
                    width: 1,
                    color: MonokaiTheme.divider,
                  ),
                  
                  // Content based on view mode
                  Expanded(
                    child: _MainContent(),
                  ),
                ],
              ),
            ),
            
            // Status bar
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: MonokaiTheme.divider),
                ),
              ),
              child: const StatusBar(),
            ),
          ],
        ),
      ),
    );
  }
}

class _MainContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(viewModeProvider);
    final showDMs = ref.watch(showDMsPanelProvider);
    
    Widget content;
    
    switch (viewMode) {
      case ViewMode.explorer:
        content = const _ExplorerLayout();
        break;
      case ViewMode.allBoards:
        content = const AllBoardsGrid();
        break;
      case ViewMode.chat:
        content = const FullChatView();
        break;
      case ViewMode.events:
        content = const _EventsView();
        break;
    }
    
    // Wrap with optional panels
    return Row(
      children: [
        // Main content
        Expanded(child: content),
        
        // DMs panel (if shown)
        if (showDMs) ...[
          Container(width: 1, color: MonokaiTheme.divider),
          const SizedBox(
            width: 320,
            child: DMsPanel(),
          ),
        ],
      ],
    );
  }
}

class _ExplorerLayout extends ConsumerWidget {
  const _ExplorerLayout();
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionProvider);
    final hasBoard = selection.hasBoard;
    final hasGroupOrWorkspace = selection.groupId != null || selection.workspaceId != null;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive tree width: 280 on wide screens, 200 on narrow
        final treeWidth = constraints.maxWidth > 600 ? 280.0 : 200.0;
        
        return Row(
          children: [
            // File tree (responsive sidebar)
            SizedBox(
              width: treeWidth,
              child: const FileTreeWidget(),
            ),
            
            Container(width: 1, color: MonokaiTheme.divider),
            
            // Content: Board detail, Board grid, or empty state
            Expanded(
              child: hasBoard
                  ? BoardDetailView(
                      boardId: selection.boardId!,
                      boardName: selection.boardName ?? 'Board',
                    )
                  : hasGroupOrWorkspace
                      ? const AllBoardsGrid() // Shows boards filtered by selection
                      : const _EmptyBoardState(),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyBoardState extends StatelessWidget {
  const _EmptyBoardState();
  
  @override
  Widget build(BuildContext context) {
    return Container(
      color: MonokaiTheme.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: MonokaiTheme.surfaceLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.dashboard_outlined,
                size: 40,
                color: MonokaiTheme.textMuted,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Select a board',
              style: MonokaiTheme.titleMedium.copyWith(
                color: MonokaiTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a board from the sidebar to view its contents',
              style: MonokaiTheme.bodySmall.copyWith(
                color: MonokaiTheme.textMuted,
              ),
            ),
            const SizedBox(height: 24),
            // Wrap in Flexible to prevent overflow on narrow screens
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _KeyHint('⌘1'),
                    const SizedBox(width: 4),
                    Text(
                      'Explorer',
                      style: MonokaiTheme.labelSmall.copyWith(
                        color: MonokaiTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _KeyHint('⌘2'),
                    const SizedBox(width: 4),
                    Text(
                      'All Boards',
                      style: MonokaiTheme.labelSmall.copyWith(
                        color: MonokaiTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  final String keys;
  
  const _KeyHint(this.keys);
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: MonokaiTheme.surfaceLight,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: MonokaiTheme.border),
      ),
      child: Text(
        keys,
        style: MonokaiTheme.codeSmall.copyWith(
          color: MonokaiTheme.textMuted,
        ),
      ),
    );
  }
}

class _EventsView extends StatelessWidget {
  const _EventsView();
  
  @override
  Widget build(BuildContext context) {
    return Container(
      color: MonokaiTheme.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.notifications_outlined,
              size: 48,
              color: MonokaiTheme.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'Events & Activity',
              style: MonokaiTheme.titleMedium.copyWith(
                color: MonokaiTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Coming soon',
              style: MonokaiTheme.bodySmall.copyWith(
                color: MonokaiTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
