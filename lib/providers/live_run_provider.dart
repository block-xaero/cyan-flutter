// providers/live_run_provider.dart
//
// Riverpod wiring for the live-run pump (see live_run_controller.dart).
//
// autoDispose + family, and that is not incidental: `pollEvents` is POP-FRONT,
// so a frame handed to one pump is gone for every other. Exactly ONE live pump
// per board may exist, and it must die with the surface that owns it —
// otherwise two views on the same board would each see half the run.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cyan_backend_provider.dart';
import 'live_run_controller.dart';

/// The live run for a board: authoritative read first, then the event pump.
final liveRunProvider = StateNotifierProvider.autoDispose
    .family<LiveRunController, LiveRunState, String>((ref, boardId) {
  final controller = LiveRunController(
    backend: ref.watch(cyanBackendProvider),
    boardId: boardId,
  );
  ref.onDispose(controller.stopPump);
  // Hydrate BEFORE pumping: events refine an authoritative read, they never
  // bootstrap one. A failed hydrate still starts the pump — the first
  // successful poll is what heals the surface.
  controller.hydrate().whenComplete(controller.start);
  return controller;
});
