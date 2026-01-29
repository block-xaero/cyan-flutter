// widgets/icon_rail.dart
// Icon rail navigation - matches Swift IconRail.swift
// 52px wide, dark background, keyboard shortcuts

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
      width: 52,
      color: MonokaiTheme.background,
      child: Column(
        children: [
          const SizedBox(height: 8),
          
          // Logo/brand
          _LogoBadge(),
          
          const SizedBox(height: 16),
          const Divider(height: 1, indent: 8, endIndent: 8),
          const SizedBox(height: 12),
          
          // Main navigation
          _NavButton(
            icon: Icons.folder_outlined,
            activeIcon: Icons.folder,
            tooltip: 'Explorer (⌘1)',
            isActive: currentMode == ViewMode.explorer,
            onTap: () => ref.read(viewModeProvider.notifier).showExplorer(),
          ),
          _NavButton(
            icon: Icons.grid_view_outlined,
            activeIcon: Icons.grid_view,
            tooltip: 'Boards (⌘2)',
            isActive: currentMode == ViewMode.allBoards,
            onTap: () => ref.read(viewModeProvider.notifier).showAllBoards(),
          ),
          _NavButton(
            icon: Icons.chat_bubble_outline,
            activeIcon: Icons.chat_bubble,
            tooltip: 'Chat (⌘3)',
            isActive: currentMode == ViewMode.chat,
            onTap: () => ref.read(viewModeProvider.notifier).showChat(),
          ),
          _NavButton(
            icon: Icons.notifications_outlined,
            activeIcon: Icons.notifications,
            tooltip: 'Events (⌘4)',
            isActive: currentMode == ViewMode.events,
            onTap: () => ref.read(viewModeProvider.notifier).showEvents(),
          ),
          
          const SizedBox(height: 12),
          const Divider(height: 1, indent: 8, endIndent: 8),
          const SizedBox(height: 12),
          
          // Secondary tools
          _NavButton(
            icon: Icons.terminal_outlined,
            activeIcon: Icons.terminal,
            tooltip: 'Console (⌘`)',
            isActive: showConsole,
            onTap: () => ref.read(showConsoleProvider.notifier).state = !showConsole,
          ),
          _NavButton(
            icon: Icons.mail_outline,
            activeIcon: Icons.mail,
            tooltip: 'Direct Messages',
            isActive: showDMs,
            badgeCount: 0,
            onTap: () => ref.read(showDMsPanelProvider.notifier).state = !showDMs,
          ),
          
          const Spacer(),
          
          // Bottom actions
          _NavButton(
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings,
            tooltip: 'Settings',
            isActive: false,
            onTap: () => _showSettings(context),
          ),
          _NavButton(
            icon: Icons.account_circle_outlined,
            activeIcon: Icons.account_circle,
            tooltip: 'Profile',
            isActive: false,
            onTap: () => _showProfile(context, ref),
          ),
          
          const SizedBox(height: 8),
        ],
      ),
    );
  }
  
  void _showSettings(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings coming soon')),
    );
  }
  
  void _showProfile(BuildContext context, WidgetRef ref) {
    Navigator.of(context).pushNamed('/profile');
  }
}

class _LogoBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [MonokaiTheme.cyan, MonokaiTheme.purple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Text(
          'C',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: MonokaiTheme.fontFamilyMono,
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;
  final int badgeCount;
  
  const _NavButton({
    required this.icon,
    required this.activeIcon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
    this.badgeCount = 0,
  });
  
  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _isHovered = false;
  
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 300),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: widget.isActive
                    ? MonokaiTheme.cyan.withOpacity(0.15)
                    : _isHovered
                        ? MonokaiTheme.hover
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: widget.isActive
                    ? Border.all(color: MonokaiTheme.cyan.withOpacity(0.3))
                    : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    widget.isActive ? widget.activeIcon : widget.icon,
                    size: 20,
                    color: widget.isActive
                        ? MonokaiTheme.cyan
                        : _isHovered
                            ? MonokaiTheme.textSecondary
                            : MonokaiTheme.textMuted,
                  ),
                  if (widget.badgeCount > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: MonokaiTheme.red,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            widget.badgeCount > 9 ? '9+' : '${widget.badgeCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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
