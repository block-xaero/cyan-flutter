// widgets/parity/parity_home_shell.dart
//
// PARITY face_shell — the home shell the signed-in app lives in, mirroring the
// BEHAVIOUR of SwiftUI's ContentView -> WorkspaceViewNew:
//
//   ┌──────┬──────────────────────────────┐
//   │ rail │  the open door's surface     │
//   ├──────┴──────────────────────────────┤
//   │ status gutter  (mesh · identity)    │
//   └─────────────────────────────────────┘
//
// The rail's five doors each mount a REAL parity face — the same widgets their
// own faces gate on — so swapping doors here is the same navigation the macOS
// app ships. The gutter is the status/sync spine's `ParityStatusBar` plus the
// profile chip the SwiftUI `StatusBar` keeps at its far right.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/shell_provider.dart';
import '../../theme/monokai_theme.dart';
import 'parity_boards_grid.dart';
import 'parity_chat_view.dart';
import 'parity_explorer_tree.dart';
import 'parity_icon_rail.dart';
import 'parity_lens_view.dart';
import 'parity_marketplace.dart';
import 'parity_status_bar.dart';

class ParityHomeShell extends ConsumerWidget {
  const ParityHomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final door = ref.watch(shellDoorProvider);

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              const ParityIconRail(),
              Container(width: 1, color: MonokaiTheme.divider),
              Expanded(child: _surfaceFor(door)),
            ],
          ),
        ),
        Container(height: 1, color: MonokaiTheme.divider),
        Row(
          children: [
            Expanded(child: ParityStatusBar(breadcrumb: door.label)),
            const _IdentityChip(),
          ],
        ),
      ],
    );
  }

  /// The surface behind each door — every one a real face, never a stub.
  Widget _surfaceFor(ShellDoor door) => switch (door) {
        ShellDoor.explorer => const ParityExplorerTree(),
        ShellDoor.boards => const ParityBoardsGrid(),
        ShellDoor.chat => const ParityChatView(),
        ShellDoor.lens => const ParityLensView(),
        ShellDoor.market => const ParityMarketplace(),
      };
}

/// The signed-in identity at the gutter's far right — the SwiftUI status bar's
/// profile button: an initials disc plus the display name. A device with no
/// identity says so instead of showing a blank chip.
class _IdentityChip extends ConsumerWidget {
  const _IdentityChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(shellIdentityProvider);
    final profile = identity.valueOrNull;

    return Container(
      height: 24,
      color: MonokaiTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: profile == null
          ? Row(
              key: const ValueKey('shell-identity-signed-out'),
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_off_outlined,
                    size: 10, color: MonokaiTheme.textMuted),
                const SizedBox(width: 4),
                Text(
                  identity.isLoading ? '…' : 'Signed out',
                  style: MonokaiTheme.labelSmall
                      .copyWith(fontSize: 10, color: MonokaiTheme.textMuted),
                ),
              ],
            )
          : _SignedInChip(profile: profile),
    );
  }
}

class _SignedInChip extends StatelessWidget {
  final DeviceProfile profile;

  const _SignedInChip({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Signed in as ${profile.displayName.isEmpty ? profile.nodeId : profile.displayName}',
      child: Row(
        key: const ValueKey('shell-identity'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: MonokaiTheme.cyan.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              profile.initials,
              style: MonokaiTheme.labelSmall
                  .copyWith(fontSize: 7, color: MonokaiTheme.cyan),
            ),
          ),
          if (profile.displayName.isNotEmpty) ...[
            const SizedBox(width: 5),
            Text(
              profile.displayName,
              key: const ValueKey('shell-identity-name'),
              style: MonokaiTheme.codeSmall
                  .copyWith(fontSize: 10, color: MonokaiTheme.cyan),
            ),
          ],
        ],
      ),
    );
  }
}
