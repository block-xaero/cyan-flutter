// providers/review_player_provider.dart
//
// PARITY face_review_player — the wiring.
//
// One player per board (the face is board-scoped, exactly as the ledger read
// is), and one video surface per player. The surface is behind a provider so a
// test mounts its own double on the same seam the app mounts AVFoundation on —
// the view is identical either way.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/media_kit_review_surface.dart';

import '../services/review_video_surface.dart';
import 'cyan_backend_provider.dart';
import 'review_player_controller.dart';

/// How the face gets a surface to mount media on. Overridden in tests.
///
/// PLATFORM-SELECTED, and it has to be: `video_player` ships no Windows
/// implementation at all, so the AVFoundation surface throws on this platform
/// and the review station had a door, a scrubber and no picture. Windows and
/// Linux mount libmpv through media_kit — which is also the only one of the two
/// that decodes the ProRes/DNx masters this station exists to review.
///
/// macOS keeps AVFoundation: it is the reference implementation, it is what the
/// Mac app ships, and replacing a working decoder to share code would be a
/// regression dressed as symmetry.
final reviewVideoSurfaceFactoryProvider =
    Provider<ReviewVideoSurface Function()>((ref) {
  if (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux) {
    return MediaKitReviewSurface.new;
  }
  return VideoPlayerReviewSurface.new;
});

/// The player for one board. Autodisposed with the face: the ledger read is
/// cheap and a stale lane is worse than a re-read.
final reviewPlayerProvider = StateNotifierProvider.autoDispose
    .family<ReviewPlayerController, ReviewPlayerState, String>((ref, boardId) {
  return ReviewPlayerController(
    backend: ref.watch(cyanBackendProvider),
    boardId: boardId,
  );
});
