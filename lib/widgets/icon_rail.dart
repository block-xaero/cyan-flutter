// widgets/icon_rail.dart
// RustRover-style vertical icon rail - FIXED overflow issue

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';

/// Navigation modes matching Swift IconRail
enum NavigationMode {
  explorer('Explorer', Icons.description_outlined, '⌘1'),
  boards('Boards', Icons.dashboard_outlined, '⌘2'),
  chat('Chat', Icons.forum_outlined, '⌘3'),
  events('Events', Icons.hub_outlined, '⌘4');

  final String label;
  final IconData icon;
  final String shortcut;
  const NavigationMode(this.label, this.icon, this.shortcut);
}

class IconRail extends ConsumerStatefulWidget {
  const IconRail({super.key});

  @override
  ConsumerState<IconRail> createState() => _IconRailState();
}

class _IconRailState extends ConsumerState<IconRail> {
  bool _showConsole = false;
  
  @override
  Widget build(BuildContext context) {
    final currentMode = ref.watch(navigationModeProvider);
    
    return Container(
      width: 56,
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          const SizedBox(height: 8),
          
          // Navigation modes (top section) - wrapped in Flexible
          ...NavigationMode.values.map((mode) => _IconRailButton(
            icon: mode.icon,
            label: mode.label,
            isSelected: currentMode == mode,
            shortcut: mode.shortcut,
            showLabel: true,
            onTap: () => ref.read(navigationModeProvider.notifier).setMode(mode),
          )),
          
          // Divider
          _buildDivider(),
          
          // Console toggle
          _IconRailButton(
            icon: Icons.terminal,
            label: 'Console',
            isSelected: _showConsole,
            shortcut: '⌘5',
            accentColor: const Color(0xFF66D9EF),
            showLabel: true,
            onTap: () => setState(() => _showConsole = !_showConsole),
          ),
          
          // DMs button
          _IconRailButton(
            icon: Icons.mark_chat_unread,
            label: 'DMs',
            isSelected: false,
            shortcut: '⌘D',
            accentColor: const Color(0xFFF92672),
            showLabel: true,
            onTap: () {
              // Show DMs
            },
          ),
          
          // Spacer takes remaining space
          const Spacer(),
          
          // Bottom section - Settings only (simplified to prevent overflow)
          _buildDivider(),
          
          _IconRailButton(
            icon: Icons.settings_outlined,
            label: 'Settings',
            isSelected: false,
            shortcut: '⌘,',
            showLabel: false,
            onTap: () {
              // Show settings
            },
          ),
          
          const SizedBox(height: 8),
        ],
      ),
    );
  }
  
  Widget _buildDivider() {
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

class _IconRailButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final String shortcut;
  final Color accentColor;
  final bool showLabel;
  final VoidCallback onTap;

  const _IconRailButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    this.shortcut = '',
    this.accentColor = const Color(0xFFA6E22E),
    this.showLabel = true,
    required this.onTap,
  });

  @override
  State<_IconRailButton> createState() => _IconRailButtonState();
}

class _IconRailButtonState extends State<_IconRailButton> {
  bool _isHovered = false;

  Color get _iconColor {
    if (widget.isSelected) return widget.accentColor;
    if (_isHovered) return const Color(0xFFCCCCCC);
    return const Color(0xFF808080);
  }

  Color get _labelColor {
    if (widget.isSelected) return widget.accentColor;
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
                        ? widget.accentColor.withValues(alpha: 0.15)
                        : (_isHovered ? const Color(0xFF2A2A2A) : Colors.transparent),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 16,
                    color: _iconColor,
                  ),
                ),
                if (widget.showLabel) ...[
                  const SizedBox(height: 1),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w500,
                      color: _labelColor,
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
