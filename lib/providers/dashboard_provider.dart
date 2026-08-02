// providers/dashboard_provider.dart
//
// Riverpod wiring for the board Dashboard (see dashboard_controller.dart).
//
// autoDispose + family, and that is not incidental: `pollEvents` is POP-FRONT,
// so a frame handed to one drain is gone for every other. Exactly ONE dashboard
// pump per board may exist, and it must die with the surface that owns it.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cyan_backend_provider.dart';
import 'dashboard_controller.dart';

/// The Dashboard read-model for a board: the authoritative `pipelineStatus`
/// read first, then the event pump on top of it.
final dashboardProvider = StateNotifierProvider.autoDispose
    .family<DashboardController, DashboardState, String>((ref, boardId) {
  final controller = DashboardController(
    backend: ref.watch(cyanBackendProvider),
    boardId: boardId,
  );
  ref.onDispose(controller.stop);
  // Hydrate BEFORE pumping: events refine an authoritative read, they never
  // bootstrap one. A failed hydrate still starts the pump — the next successful
  // read is what heals the surface.
  controller.hydrate().whenComplete(controller.start);
  return controller;
});
