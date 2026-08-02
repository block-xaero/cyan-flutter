// widgets/parity/parity_icon_rail.dart
//
// PARITY face_shell — the icon rail: the five doors on the left edge of the
// home shell. Mirrors the BEHAVIOUR of the SwiftUI workspace rail
// (WorkspaceViewNew.swift): every door is always visible, the open door is
// highlighted, and clicking a door swaps the home surface (see
// `ParityHomeShell`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/shell_provider.dart';
import '../../theme/monokai_theme.dart';

class ParityIconRail extends ConsumerWidget {
  const ParityIconRail({super.key});

  static const _icons = <ShellDoor, IconData>{
    ShellDoor.explorer: Icons.description_outlined,
    ShellDoor.boards: Icons.dashboard_outlined,
    ShellDoor.chat: Icons.forum_outlined,
    ShellDoor.lens: Icons.auto_awesome_outlined,
    ShellDoor.market: Icons.storefront_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(shellDoorProvider);

    return Container(
      width: 64,
      color: MonokaiTheme.surfaceLighter,
      child: Column(
        children: [
          const SizedBox(height: 12),
          for (final door in ShellDoor.values)
            _RailDoor(
              icon: _icons[door]!,
              label: door.label,
              isOpen: door == open,
              onTap: () =>
                  ref.read(shellDoorProvider.notifier).state = door,
            ),
        ],
      ),
    );
  }
}

class _RailDoor extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isOpen;
  final VoidCallback onTap;

  const _RailDoor({
    required this.icon,
    required this.label,
    required this.isOpen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isOpen ? MonokaiTheme.cyan : MonokaiTheme.textMuted;

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 2,
                color: isOpen ? MonokaiTheme.cyan : Colors.transparent,
              ),
            ),
            color: isOpen ? MonokaiTheme.selection : Colors.transparent,
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: MonokaiTheme.labelSmall.copyWith(
                  fontSize: 9,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
