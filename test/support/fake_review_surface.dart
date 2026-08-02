// test/support/fake_review_surface.dart
//
// Tier-1 video surface: the review player's `ReviewVideoSurface` seam with no
// decoder behind it. Swift's `FakeVideoSurface` plays exactly this role for the
// XCUITest harness — the VIEW is identical either way, because the face only
// ever asks the surface for frames, a play flag and a picture.
//
// It is frame-exact BY CONSTRUCTION (a seek sets an integer), which is what
// makes it a legitimate stand-in for the capture gate: `isCaptureGrade` is true
// because nothing has been positively detected as untrustworthy, not because
// the flag was faked on.

import 'package:flutter/material.dart';

import 'package:cyan_flutter/services/review_video_surface.dart';

class FakeReviewVideoSurface extends ReviewVideoSurface {
  FakeReviewVideoSurface({int durationFrames = 2880}) : _duration = durationFrames;

  String? _path;
  int _frame = 0;
  bool _playing = false;
  double _fps = kReviewFallbackFps;
  final int _duration;

  /// Every path this surface has been asked to mount, in order — the checkout
  /// trail a version flip leaves.
  final List<String> mounted = [];

  @override
  String? get mountedPath => _path;

  @override
  int get currentFrame => _frame;

  @override
  int get durationFrames => _duration;

  @override
  double get fps => _fps;

  @override
  bool get isPlaying => _playing;

  @override
  bool get isCaptureGrade => true;

  @override
  Size? get raster => const Size(1920, 1080);

  @override
  Future<void> load(String path, {double fps = kReviewFallbackFps}) async {
    _path = path;
    _fps = fps > 0 ? fps : kReviewFallbackFps;
    mounted.add(path);
    notifyListeners();
  }

  @override
  void seek(int frame) {
    final clamped = frame < 0 ? 0 : (frame >= _duration ? _duration - 1 : frame);
    if (clamped == _frame) return;
    _frame = clamped;
    notifyListeners();
  }

  @override
  void play() {
    if (_playing) return;
    _playing = true;
    notifyListeners();
  }

  @override
  void pause() {
    if (!_playing) return;
    _playing = false;
    notifyListeners();
  }

  @override
  Widget buildPicture(BuildContext context) => ColoredBox(
        color: const Color(0xFF14140F),
        child: Center(
          child: Text(
            _path == null ? '—' : _path!.split('/').last,
            key: const ValueKey('review.fake.picture'),
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 11, color: Colors.white54),
          ),
        ),
      );
}
