// services/review_video_surface.dart
//
// PARITY face_review_player — the video seam.
//
// SwiftUI reference (READ-ONLY):
//   Media/VideoSurface.swift          — the protocol: frames, fps, isPlaying,
//                                       load/seek/play/pause, `isCaptureGrade`
//   Media/AVFoundationVideoSurface    — the production implementation
//
// The player's controller NEVER touches a decoder: it sees frame indices and a
// play flag, and that is the whole surface contract. Production mounts
// [VideoPlayerReviewSurface] (AVFoundation, through `video_player`); a test
// mounts its own double and drives the same API.
//
// FRAMES ARE THE TRUTH. Every anchor this face writes is a frame index, so the
// two rules the seam has to hold are:
//
//   1. a seek lands on EXACTLY the requested frame (zero tolerance — the
//      AVFoundation implementation behind `video_player` seeks with zero
//      tolerance either side, which is what makes ±1 frame stepping honest);
//   2. the RATE that converts a position to a frame is the one the review lane
//      published, not one guessed from the container. It rides in on [load] so
//      a proxy whose fps the registry does not carry falls back to the engine's
//      own 24, exactly as the engine's comment anchoring does.
//
// [isCaptureGrade] is a CORRECTNESS gate, not a nicety: a surface that cannot
// report the frame it is showing writes silently wrong anchors that no later
// pass can identify, so region capture refuses rather than guess. Refusal is
// only ever on POSITIVE detection of a reason.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// The engine's own fallback rate for a proxy whose fps the asset registry does
/// not carry. Same number as the review lane's comment anchoring.
const double kReviewFallbackFps = 24;

/// What the player mounts media on. A [ChangeNotifier] rather than Swift's two
/// Combine publishers — one notification covers both the playhead and the play
/// flag, and Flutter's listeners are the idiom the rest of this app uses.
abstract class ReviewVideoSurface extends ChangeNotifier {
  /// The media currently mounted, or null before the first load.
  String? get mountedPath;

  /// The playhead, in frames at [fps] (0-based).
  int get currentFrame;

  /// Total length in frames. 0 until a load completes.
  int get durationFrames;

  /// The rate frames are counted at.
  double get fps;

  bool get isPlaying;

  /// Whether anchors captured against this surface may be trusted.
  bool get isCaptureGrade;

  /// The raster the picture is drawn on — the shape a region is normalized
  /// against. Null until a load reports one.
  Size? get raster;

  Future<void> load(String path, {double fps});

  /// Frame-accurate seek. The implementation must land on EXACTLY [frame].
  void seek(int frame);

  void play();
  void pause();

  /// Clamp-and-step, for the transport's ± one-frame buttons.
  void step(int frames) {
    final upper = durationFrames > 0 ? durationFrames - 1 : currentFrame + frames;
    final target = currentFrame + frames;
    seek(target < 0 ? 0 : (target > upper ? (upper < 0 ? 0 : upper) : target));
  }

  /// The picture. The view asks the surface for it rather than knowing which
  /// decoder is underneath.
  Widget buildPicture(BuildContext context);
}

/// The production surface: AVFoundation through `video_player`.
///
/// A file that does not exist, or a container the platform cannot decode, is an
/// ANSWER — [failure] carries it and the face says so — never a crash and never
/// a spinner that spins forever.
class VideoPlayerReviewSurface extends ReviewVideoSurface {
  VideoPlayerController? _controller;
  String? _path;
  double _fps = kReviewFallbackFps;
  String? _failure;

  /// Why the last load did not mount. Null when the picture is up.
  String? get failure => _failure;

  @override
  String? get mountedPath => _path;

  @override
  double get fps => _fps;

  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;

  @override
  int get currentFrame {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return 0;
    return (c.value.position.inMicroseconds * _fps / 1000000).round();
  }

  @override
  int get durationFrames {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return 0;
    return (c.value.duration.inMicroseconds * _fps / 1000000).round();
  }

  /// Nothing has been positively detected as untrustworthy: a zero-tolerance
  /// seek at a published rate is frame-exact. A load that failed has no picture
  /// to capture against at all, which IS a positive reason to refuse.
  @override
  bool get isCaptureGrade => _failure == null;

  @override
  Size? get raster {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return null;
    final s = c.value.size;
    return (s.width > 0 && s.height > 0) ? s : null;
  }

  @override
  Future<void> load(String path, {double fps = kReviewFallbackFps}) async {
    final previous = _controller;
    _controller = null;
    previous?.removeListener(_onTick);
    await previous?.dispose();

    _path = path;
    _fps = fps > 0 ? fps : kReviewFallbackFps;
    _failure = null;
    notifyListeners();

    final controller = path.startsWith('http')
        ? VideoPlayerController.networkUrl(Uri.parse(path))
        : VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
    } catch (e) {
      await controller.dispose();
      // The media did not open. Say why — a face that cannot show the picture
      // must not pretend it is loading forever.
      _failure = e.toString();
      notifyListeners();
      return;
    }
    controller.addListener(_onTick);
    _controller = controller;
    notifyListeners();
  }

  void _onTick() => notifyListeners();

  @override
  void seek(int frame) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final clamped = frame < 0 ? 0 : frame;
    c.seekTo(Duration(microseconds: (clamped / _fps * 1000000).round()));
  }

  @override
  void play() => _controller?.play();

  @override
  void pause() => _controller?.pause();

  @override
  Widget buildPicture(BuildContext context) {
    final c = _controller;
    if (c != null && c.value.isInitialized) {
      return AspectRatio(
        aspectRatio: c.value.aspectRatio,
        child: VideoPlayer(c),
      );
    }
    return _UnmountedPicture(path: _path, failure: _failure);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }
}

/// What the hero shows when there is no picture: the media it was asked for and
/// the engine's own reason, never a spinner with nothing behind it.
class _UnmountedPicture extends StatelessWidget {
  final String? path;
  final String? failure;

  const _UnmountedPicture({this.path, this.failure});

  @override
  Widget build(BuildContext context) {
    final name = path == null ? '—' : path!.split('/').last;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(failure == null ? Icons.movie_outlined : Icons.error_outline,
              size: 34, color: Colors.white24),
          const SizedBox(height: 6),
          Text(name,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 11, color: Colors.white54)),
          if (failure != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(failure!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 10, color: Colors.white38)),
            ),
        ],
      ),
    );
  }
}
