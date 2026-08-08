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
import 'parity_board_container.dart';
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

    final openBoard = ref.watch(selectedBoardProvider);

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              const ParityIconRail(),
              Container(width: 1, color: MonokaiTheme.divider),
              Expanded(
                child: openBoard == null
                    ? _surfaceFor(door, ref)
                    // The board CUBE replaces the door's surface but NOT the
                    // rail — Swift keeps the workspace chrome around
                    // `BoardContainerViewNew`, so switching doors is still one
                    // click away from inside a board. Keying on the board id
                    // makes opening a second board a fresh cube rather than the
                    // previous board's state re-pointed.
                    : ParityBoardContainer(
                        key: ValueKey(openBoard),
                        boardId: openBoard,
                        onBack: () => ref
                            .read(selectedBoardProvider.notifier)
                            .state = null,
                      ),
              ),
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
  ///
  /// The two surfaces that LIST boards are handed `onOpenBoard`, because a
  /// board row that does nothing when tapped is the difference between a face
  /// that renders and a shell an operator can work in. Both list the same
  /// boards through the same seam and differ only in shape, so both open the
  /// cube the same way.
  Widget _surfaceFor(ShellDoor door, WidgetRef ref) {
    void open(String boardId) =>
        ref.read(selectedBoardProvider.notifier).state = boardId;

    return switch (door) {
      ShellDoor.explorer =>
        ParityExplorerTree(onOpenBoard: (board) => open(board.id)),
      ShellDoor.boards =>
        ParityBoardsGrid(onOpenBoard: (entry) => open(entry.board.id)),
      ShellDoor.chat => const ParityChatView(),
      ShellDoor.lens => const ParityLensView(),
      ShellDoor.market => const ParityMarketplace(),
    };
  }
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
