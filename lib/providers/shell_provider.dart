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
final shellDoorProvider =
    StateProvider<ShellDoor>((ref) => ShellDoor.explorer);

/// The signed-in identity the status bar's profile chip shows. Null renders as
/// signed-out, never as a blank profile.
final shellIdentityProvider = FutureProvider<DeviceProfile?>((ref) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.myProfile();
});
