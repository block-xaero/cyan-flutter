// providers/review_player_provider.dart
//
// PARITY face_review_player — the wiring.
//
// One player per board (the face is board-scoped, exactly as the ledger read
// is), and one video surface per player. The surface is behind a provider so a
// test mounts its own double on the same seam the app mounts AVFoundation on —
// the view is identical either way.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/review_video_surface.dart';
import 'cyan_backend_provider.dart';
import 'review_player_controller.dart';

/// How the face gets a surface to mount media on. Overridden in tests.
final reviewVideoSurfaceFactoryProvider =
    Provider<ReviewVideoSurface Function()>((ref) => VideoPlayerReviewSurface.new);

/// The player for one board. Autodisposed with the face: the ledger read is
/// cheap and a stale lane is worse than a re-read.
final reviewPlayerProvider = StateNotifierProvider.autoDispose
    .family<ReviewPlayerController, ReviewPlayerState, String>((ref, boardId) {
  return ReviewPlayerController(
    backend: ref.watch(cyanBackendProvider),
    boardId: boardId,
  );
});
