// widgets/icon_rail.dart
// VS Code style icon rail - matches Swift app exactly

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';

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
          
          // Main navigation items (fixed at top)
          _RailItem(
            icon: Icons.folder_outlined,
            label: 'Explorer',
            isActive: viewMode == ViewMode.explorer,
            onTap: () => ref.read(viewModeProvider.notifier).setMode(ViewMode.explorer),
            shortcut: '⌘1',
          ),
          _RailItem(
            icon: Icons.dashboard_outlined,
            label: 'Boards',
            isActive: viewMode == ViewMode.allBoards,
            onTap: () => ref.read(viewModeProvider.notifier).setMode(ViewMode.allBoards),
            shortcut: '⌘2',
          ),
          _RailItem(
            icon: Icons.chat_bubble_outline,
            label: 'Chat',
            isActive: viewMode == ViewMode.chat,
            onTap: () => ref.read(viewModeProvider.notifier).setMode(ViewMode.chat),
            shortcut: '⌘3',
          ),
          _RailItem(
            icon: Icons.device_hub,
            label: 'Events',
            isActive: viewMode == ViewMode.events,
            onTap: () => ref.read(viewModeProvider.notifier).setMode(ViewMode.events),
            shortcut: '⌘4',
          ),
          
          const _RailDivider(),
          
          _RailItem(
            icon: Icons.terminal,
            label: 'Console',
            isActive: showConsole,
            onTap: () => ref.read(showConsoleProvider.notifier).state = !showConsole,
          ),
          _RailItem(
            icon: Icons.mark_chat_unread_outlined,
            label: 'DMs',
            isActive: showDMs,
            onTap: () => ref.read(showDMsPanelProvider.notifier).state = !showDMs,
          ),
          
          const Spacer(),
          
          // Bottom items (fixed at bottom)
          const _RailDivider(),
          
          _RailItem(
            icon: Icons.settings_outlined,
            label: 'Settings',
            isActive: false,
            onTap: () {},
          ),
          _RailItem(
            icon: Icons.person_outline,
            label: 'Profile',
            isActive: false,
            onTap: () {},
          ),
          
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final String? shortcut;
  final int? badge;
  final bool hasNotification;

  const _RailItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.shortcut,
    this.badge,
    this.hasNotification = false,
  });

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.shortcut != null ? '${widget.label} (${widget.shortcut})' : widget.label,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 56,
            height: 48,
            decoration: BoxDecoration(
              color: widget.isActive
                  ? const Color(0xFF66D9EF).withOpacity(0.15)
                  : _isHovered
                      ? const Color(0xFF3E3D32)
                      : Colors.transparent,
              border: Border(
                left: BorderSide(
                  color: widget.isActive ? const Color(0xFF66D9EF) : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.icon,
                      size: 22,
                      color: widget.isActive
                          ? const Color(0xFF66D9EF)
                          : _isHovered
                              ? const Color(0xFFF8F8F2)
                              : const Color(0xFF808080),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 9,
                        color: widget.isActive
                            ? const Color(0xFF66D9EF)
                            : _isHovered
                                ? const Color(0xFFF8F8F2)
                                : const Color(0xFF808080),
                      ),
                    ),
                  ],
                ),
                // Badge
                if (widget.badge != null && widget.badge! > 0)
                  Positioned(
                    top: 6,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF92672),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${widget.badge}',
                        style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                // Notification dot
                if (widget.hasNotification)
                  Positioned(
                    top: 8,
                    right: 12,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFD971F),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailDivider extends StatelessWidget {
  const _RailDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      height: 1,
      color: const Color(0xFF3E3D32),
    );
  }
}

/// Keyboard shortcut handler - wrap your app with this
class KeyboardShortcuts extends ConsumerWidget {
  final Widget child;

  const KeyboardShortcuts({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () {
          ref.read(viewModeProvider.notifier).setMode(ViewMode.explorer);
        },
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () {
          ref.read(viewModeProvider.notifier).setMode(ViewMode.allBoards);
        },
        const SingleActivator(LogicalKeyboardKey.digit3, meta: true): () {
          ref.read(viewModeProvider.notifier).setMode(ViewMode.chat);
        },
        const SingleActivator(LogicalKeyboardKey.digit4, meta: true): () {
          ref.read(viewModeProvider.notifier).setMode(ViewMode.events);
        },
        const SingleActivator(LogicalKeyboardKey.backquote, meta: true): () {
          ref.read(showConsoleProvider.notifier).update((s) => !s);
        },
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true, shift: true): () {
          ref.read(showDMsPanelProvider.notifier).update((s) => !s);
        },
      },
      child: Focus(
        autofocus: true,
        child: child,
      ),
    );
  }
}
