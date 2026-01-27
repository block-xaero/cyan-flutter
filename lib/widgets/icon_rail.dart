// widgets/icon_rail.dart
// Simplified icon rail - AllBoards, Explorer, Chat, DMs, Events

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import 'file_tree_widget.dart';

class IconRail extends ConsumerWidget {
  const IconRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(viewModeProvider);
    final showDMs = ref.watch(showDMsPanelProvider);
    final showConsole = ref.watch(showConsoleProvider);

    return Container(
      width: 56,
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // All Boards (default view)
          _RailButton(
            icon: Icons.dashboard_outlined,
            label: 'Boards',
            isSelected: viewMode == ViewMode.allBoards,
            shortcut: '⌘1',
            onTap: () => ref.read(viewModeProvider.notifier).showAllBoards(),
          ),

          // Explorer (file tree + filtered boards)
          _RailButton(
            icon: Icons.folder_outlined,
            label: 'Explorer',
            isSelected: viewMode == ViewMode.explorer,
            shortcut: '⌘2',
            onTap: () => ref.read(viewModeProvider.notifier).showExplorer(),
          ),

          // Chat (full screen)
          _RailButton(
            icon: Icons.chat_bubble_outline,
            label: 'Chat',
            isSelected: viewMode == ViewMode.chat,
            shortcut: '⌘3',
            accentColor: const Color(0xFF66D9EF),
            onTap: () => ref.read(viewModeProvider.notifier).showChat(),
          ),

          // Events
          _RailButton(
            icon: Icons.hub_outlined,
            label: 'Events',
            isSelected: viewMode == ViewMode.events,
            shortcut: '⌘4',
            onTap: () => ref.read(viewModeProvider.notifier).showEvents(),
          ),

          _divider(),

          // DMs (toggleable panel)
          _RailButton(
            icon: showDMs ? Icons.mark_chat_read : Icons.mark_chat_unread_outlined,
            label: 'DMs',
            isSelected: showDMs,
            shortcut: '⌘D',
            accentColor: const Color(0xFFF92672),
            onTap: () => ref.read(showDMsPanelProvider.notifier).state = !showDMs,
          ),

          // Console toggle
          _RailButton(
            icon: Icons.terminal,
            label: 'Console',
            isSelected: showConsole,
            shortcut: '⌘5',
            accentColor: const Color(0xFFAE81FF),
            onTap: () => ref.read(showConsoleProvider.notifier).state = !showConsole,
          ),

          const Spacer(),

          _divider(),

          // Settings
          _RailButton(
            icon: Icons.settings_outlined,
            label: 'Settings',
            isSelected: false,
            shortcut: '⌘,',
            showLabel: false,
            onTap: () {
              // TODO: Show settings
            },
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: const Color(0xFF2A2A2A),
      ),
    );
  }
}

class _RailButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final String shortcut;
  final Color accentColor;
  final bool showLabel;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    this.shortcut = '',
    this.accentColor = const Color(0xFFA6E22E),
    this.showLabel = true,
    required this.onTap,
  });

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton> {
  bool _isHovered = false;

  Color get _iconColor {
    if (widget.isSelected) return widget.accentColor;
    if (_isHovered) return const Color(0xFFCCCCCC);
    return const Color(0xFF808080);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${widget.label} (${widget.shortcut})',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 26,
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? widget.accentColor.withOpacity(0.15)
                        : (_isHovered ? const Color(0xFF2A2A2A) : Colors.transparent),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(widget.icon, size: 16, color: _iconColor),
                ),
                if (widget.showLabel) ...[
                  const SizedBox(height: 1),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w500,
                      color: widget.isSelected ? widget.accentColor : const Color(0xFF808080),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
