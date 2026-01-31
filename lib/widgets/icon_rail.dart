// widgets/icon_rail.dart
// Icon rail navigation - matches Swift IconRail.swift exactly
// 56px wide (Swift: frame(width: 56)), dark background

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/monokai_theme.dart';
import '../providers/navigation_provider.dart';

class IconRail extends ConsumerWidget {
  const IconRail({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(viewModeProvider);
    final showConsole = ref.watch(showConsoleProvider);
    final showDMs = ref.watch(showDMsPanelProvider);
    
    return Container(
      width: 56,  // Match Swift: frame(width: 56)
      color: const Color(0xFF1E1E1E),  // Match Swift: Color(hex: "1E1E1E")
      child: Column(
        children: [
          const SizedBox(height: 12),  // Match Swift: padding(.top, 12)
          
          // Top section: Navigation modes
          _RailButton(
            icon: Icons.description_outlined,
            label: 'Explorer',
            isSelected: currentMode == ViewMode.explorer,
            shortcut: '⌘1',
            onTap: () => ref.read(viewModeProvider.notifier).showExplorer(),
          ),
          _RailButton(
            icon: Icons.dashboard_outlined,  // rectangle.on.rectangle.angled
            label: 'Boards',
            isSelected: currentMode == ViewMode.allBoards,
            shortcut: '⌘2',
            onTap: () => ref.read(viewModeProvider.notifier).showAllBoards(),
          ),
          _RailButton(
            icon: Icons.forum_outlined,  // bubble.left.and.bubble.right
            label: 'Chat',
            isSelected: currentMode == ViewMode.chat,
            shortcut: '⌘3',
            onTap: () => ref.read(viewModeProvider.notifier).showChat(),
          ),
          _RailButton(
            icon: Icons.auto_awesome_outlined,  // Lens AI / integrations
            label: 'Lens AI',
            isSelected: currentMode == ViewMode.events,
            shortcut: '⌘4',
            onTap: () => ref.read(viewModeProvider.notifier).showEvents(),
          ),
          
          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: const Color(0xFF2A2A2A),
            ),
          ),
          
          // Console toggle
          _RailButton(
            icon: Icons.terminal,
            label: 'Console',
            isSelected: showConsole,
            shortcut: '⌘5',
            accentColor: const Color(0xFF66D9EF),  // Cyan
            onTap: () => ref.read(showConsoleProvider.notifier).state = !showConsole,
          ),
          
          // DMs
          _RailButton(
            icon: Icons.mark_chat_unread_outlined,
            label: 'DMs',
            isSelected: showDMs,
            accentColor: const Color(0xFFF92672),  // Pink/red
            onTap: () => ref.read(showDMsPanelProvider.notifier).state = !showDMs,
          ),
          
          const Spacer(),
          
          // Bottom section: Actions
          _RailButton(
            icon: Icons.splitscreen,
            label: 'Split',
            isSelected: false,
            shortcut: '⌘\\',
            showLabel: true,
            onTap: () {},  // TODO: split view toggle
          ),
          
          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: const Color(0xFF2A2A2A),
            ),
          ),
          
          // New Board
          _RailButton(
            icon: Icons.add_box_outlined,
            label: 'New Board',
            isSelected: false,
            accentColor: const Color(0xFF66D9EF),
            showLabel: false,
            onTap: () {},  // TODO
          ),
          
          // New Chat
          _RailButton(
            icon: Icons.add_comment_outlined,
            label: 'New Chat',
            isSelected: false,
            accentColor: const Color(0xFFA6E22E),  // Green
            showLabel: false,
            onTap: () {},  // TODO
          ),
          
          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: const Color(0xFF2A2A2A),
            ),
          ),
          
          // Settings
          _RailButton(
            icon: Icons.settings_outlined,
            label: 'Settings',
            isSelected: false,
            showLabel: false,
            onTap: () => _showSettings(context),
          ),
          
          // Profile
          _RailButton(
            icon: Icons.account_circle_outlined,
            label: 'Profile',
            isSelected: false,
            showLabel: false,
            onTap: () => Navigator.of(context).pushNamed('/profile'),
          ),
          
          const SizedBox(height: 12),  // Match Swift: padding(.bottom, 12)
        ],
      ),
    );
  }
  
  void _showSettings(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings coming soon')),
    );
  }
}

/// Icon Rail Button - matches Swift IconRailButton exactly
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
    this.accentColor = const Color(0xFFA6E22E),  // Default green
    this.showLabel = true,
    required this.onTap,
  });
  
  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton> {
  bool _isHovered = false;
  
  Color get iconColor {
    if (widget.isSelected) return widget.accentColor;
    if (_isHovered) return const Color(0xFFF8F8F2);
    return const Color(0xFF808080);
  }
  
  Color get labelColor {
    if (widget.isSelected) return widget.accentColor;
    return const Color(0xFF808080);
  }
  
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.shortcut.isNotEmpty ? '${widget.label} (${widget.shortcut})' : widget.label,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 400),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon container - matches Swift: frame(width: 44, height: 28)
                Container(
                  width: 44,
                  height: 28,
                  decoration: BoxDecoration(
                    color: widget.isSelected 
                        ? widget.accentColor.withOpacity(0.15) 
                        : (_isHovered ? const Color(0xFF2A2A2A) : Colors.transparent),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 18,  // Match Swift: font(.system(size: 18))
                    color: iconColor,
                  ),
                ),
                
                // Label - matches Swift: font(.system(size: 9, weight: .medium))
                if (widget.showLabel) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: labelColor,
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

/// Keyboard shortcuts handler for the app shell
class IconRailShortcuts extends ConsumerWidget {
  final Widget child;
  
  const IconRailShortcuts({super.key, required this.child});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.digit1):
            const _ViewModeIntent(ViewMode.explorer),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.digit2):
            const _ViewModeIntent(ViewMode.allBoards),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.digit3):
            const _ViewModeIntent(ViewMode.chat),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.digit4):
            const _ViewModeIntent(ViewMode.events),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.backquote):
            const _ToggleConsoleIntent(),
      },
      child: Actions(
        actions: {
          _ViewModeIntent: CallbackAction<_ViewModeIntent>(
            onInvoke: (intent) {
              ref.read(viewModeProvider.notifier).setMode(intent.mode);
              return null;
            },
          ),
          _ToggleConsoleIntent: CallbackAction<_ToggleConsoleIntent>(
            onInvoke: (intent) {
              ref.read(showConsoleProvider.notifier).update((s) => !s);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: child,
        ),
      ),
    );
  }
}

class _ViewModeIntent extends Intent {
  final ViewMode mode;
  const _ViewModeIntent(this.mode);
}

class _ToggleConsoleIntent extends Intent {
  const _ToggleConsoleIntent();
}
