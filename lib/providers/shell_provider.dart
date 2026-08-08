// providers/shell_provider.dart
//
// Riverpod wiring for the home SHELL — the frame every parity face mounts
// inside: the icon rail's five doors and the status bar's signed-in identity.
// The mesh half of the gutter is owned by `mesh_status_provider.dart` (the
// status/sync spine); this file deliberately does not duplicate it.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Views/ContentView.swift        (authenticated -> shell)
//   cyan-iOS/Cyan/Cyan/Views/WorkspaceViewNew.swift   (rail | surface | bar)
//   cyan-iOS/Cyan/Cyan/Views/StatusBar.swift          (profile button, far right)
//
// Every read goes through the ONE `CyanBackend` seam, so the whole shell
// drives off `FakeCyanBackend` in a widget test with no dylib.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/parity_models.dart';
import 'cyan_backend_provider.dart';

/// The five doors the rail advertises — the surfaces behind the SwiftUI
/// workspace's navigation modes.
enum ShellDoor {
  explorer,
  boards,
  chat,
  lens,
  market;

  String get label => switch (this) {
        ShellDoor.explorer => 'Explorer',
        ShellDoor.boards => 'Boards',
        ShellDoor.chat => 'Chat',
        ShellDoor.lens => 'Lens',
        ShellDoor.market => 'Market',
      };
}

/// Which door is open. The shell swaps its home surface off this alone, so a
/// test (or a keyboard shortcut) drives navigation exactly like a rail click.
final shellDoorProvider = StateProvider<ShellDoor>((ref) => ShellDoor.explorer);

/// The board the operator has OPENED, or null when the shell is showing the
/// open door's own surface.
///
/// This is what makes the rail's surfaces navigable rather than terminal: the
/// Explorer tree and the Boards wall both answer a tap by setting it, and the
/// shell swaps in the board CUBE (`ParityBoardContainer`) over the door's
/// surface — the same move `WorkspaceViewNew` makes when it mounts
/// `BoardContainerViewNew` beside the rail. Going back clears it, which returns
/// the operator to the door they were on rather than to a default one.
///
/// It holds an id, not a board: the cube re-reads the board through the seam,
/// so a board renamed or re-faced elsewhere is not stale here.
final selectedBoardProvider = StateProvider<String?>((ref) => null);

/// The GROUP the operator is currently standing in.
///
/// Set by the Explorer's selection and by opening a board from the wall, so it
/// tracks wherever the operator actually is rather than a remembered default.
///
/// It matters because a plugin install LANDS in a group's Plugins workspace:
/// `ParityMarketplace` refuses the install when this is null rather than
/// guessing a group the engine would foreign-key-reject. Guessing here would
/// install a tool into someone else's tenant.
final selectedGroupProvider = StateProvider<String?>((ref) => null);

/// The signed-in identity the status bar's profile chip shows. Null renders as
/// signed-out, never as a blank profile.
final shellIdentityProvider = FutureProvider<DeviceProfile?>((ref) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.myProfile();
});
