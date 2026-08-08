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
import '../../providers/cyan_backend_provider.dart';
import '../../providers/onboarding_session_provider.dart';
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

    // Choosing a rail door LEAVES the open board. Without this the cube keeps
    // the surface no matter which door is lit, so the rail goes decorative the
    // moment a board is open — the opposite of the "one click away" property
    // keeping the chrome around the container is supposed to buy.
    ref.listen<ShellDoor>(shellDoorProvider, (_, __) {
      ref.read(selectedBoardProvider.notifier).state = null;
    });

    // Every group carries the default plugins, provisioned from app-shipped
    // bytes with no network and no clicks. Watched here because the shell is
    // the one surface guaranteed to be mounted for a signed-in operator; the
    // result is never rendered (see `defaultPluginsProvider`).
    ref.watch(defaultPluginsProvider);

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
    void standIn(String? groupId) =>
        ref.read(selectedGroupProvider.notifier).state = groupId;

    return switch (door) {
      ShellDoor.explorer => ParityExplorerTree(
          onOpenBoard: (board) => open(board.id),
          // Where the operator is standing follows the tree's selection, which
          // is what decides the group an install would land in.
          onSelectionChanged: (selection) => standIn(selection?.groupId),
        ),
      ShellDoor.boards => ParityBoardsGrid(onOpenBoard: (entry) {
          standIn(entry.group.id);
          open(entry.board.id);
        }),
      ShellDoor.chat => const ParityChatView(),
      ShellDoor.lens => const ParityLensView(),
      // The storefront needs BOTH: the group an install lands in, and the role
      // that decides whether the forge entry is offered. Constructed bare, it
      // evaluated `forgeEntryGate(null)` and hard-locked "Build a custom tool"
      // for EVERYONE — owners included — while Install could never run at all
      // for want of a group.
      ShellDoor.market => ParityMarketplace(
          groupId: ref.watch(selectedGroupProvider),
          sessionRole: _sessionRole(ref),
        ),
    };
  }

  /// The membership role of the verified session, or null when there is no
  /// session at all. Null and empty are the same fact here — no session means
  /// no role — and the gate locks on both, which is the honest reading.
  static String? _sessionRole(WidgetRef ref) {
    final role = ref.watch(onboardingSessionProvider).role;
    return role.isEmpty ? null : role;
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
      message:
          'Signed in as ${profile.displayName.isEmpty ? profile.nodeId : profile.displayName}',
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
