// test/frame_accuracy_test.dart
//
// FRAME ACCURACY — the property the review player is judged on.
//
// The decoder cannot be exercised in Tier-1 (no native libs, no media), so the
// part that CAN be proved is isolated here as pure arithmetic: given a frame,
// which instant do we ask for, and given an instant, which frame is on screen.
// Get that pair wrong and every timecode, every anchored comment and every
// one-frame step is off by one — on a review station, that is the difference
// between a note landing on the shot and landing on the cut.
//
// The rule: SEEK TO THE CENTRE of a frame, READ BACK WITH FLOOR.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/ViewModels/ReviewPlayerViewModel.swift  (frames are the
//   truth; the surface's fps is adopted, never assumed)

import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/services/review_video_surface.dart';

/// The rates a post house actually hands us, including the two NTSC pulldowns
/// whose non-integer fps is where off-by-one bugs live.
const List<double> _rates = [
  23.976023976023978, // 24000/1001
  24,
  25,
  29.97002997002997, // 30000/1001
  30,
  48,
  50,
  59.94005994005994, // 60000/1001
  60,
];

void main() {
  test('a seek lands on the frame it was asked for, at every rate', () {
    // The round trip IS the property. If seeking to frame N and reading the
    // position back does not give N, the playhead lies.
    for (final fps in _rates) {
      for (final frame in const [0, 1, 2, 23, 24, 100, 1439, 86399, 300000]) {
        final landed = positionToFrame(frameToPosition(frame, fps), fps);
        expect(landed, frame,
            reason: 'frame $frame at ${fps}fps came back as $landed');
      }
    }
  });

  test('the aim point is the CENTRE of the frame, not its boundary', () {
    // Boundary seeking is the bug this exists to prevent: the instant where
    // frame 9 ends and frame 10 begins belongs to both by rounding, and which
    // one the decoder returns is its own business.
    const fps = 24.0;
    final boundary = Duration(microseconds: (10 / fps * 1000000).round());
    final aimed = frameToPosition(10, fps);

    expect(aimed, greaterThan(boundary));
    final halfFrame = Duration(microseconds: (0.5 / fps * 1000000).round());
    expect((aimed - boundary - halfFrame).inMicroseconds.abs(),
        lessThanOrEqualTo(1),
        reason: 'the aim point is half a frame past the boundary');
  });

  test('a decoder that lands anywhere INSIDE the frame still reads back right',
      () {
    // Real decoders do not land on the microsecond you asked for. Centre-aiming
    // buys half a frame of tolerance in both directions, which is the whole
    // reason to do it.
    for (final fps in _rates) {
      final frameMicros = 1000000 / fps;
      for (final frame in const [0, 7, 480, 12345]) {
        final aimed = frameToPosition(frame, fps).inMicroseconds;
        // Just inside each edge of the frame's display interval.
        final early = aimed - (frameMicros / 2).floor() + 1;
        final late = aimed + (frameMicros / 2).floor() - 1;
        expect(positionToFrame(Duration(microseconds: early), fps), frame,
            reason: 'landing early within frame $frame at ${fps}fps');
        expect(positionToFrame(Duration(microseconds: late), fps), frame,
            reason: 'landing late within frame $frame at ${fps}fps');
      }
    }
  });

  test('consecutive frames are distinct instants — a step really steps', () {
    // If two frames resolved to the same instant, +1 frame would be a no-op and
    // the transport's step buttons would do nothing at the high rates.
    for (final fps in _rates) {
      for (var frame = 0; frame < 200; frame++) {
        final a = frameToPosition(frame, fps);
        final b = frameToPosition(frame + 1, fps);
        expect(b, greaterThan(a),
            reason:
                'frame ${frame + 1} must be later than $frame at ${fps}fps');
        expect(positionToFrame(b, fps) - positionToFrame(a, fps), 1);
      }
    }
  });

  test('a negative frame is clamped rather than seeking backwards past zero',
      () {
    expect(frameToPosition(-5, 24).inMicroseconds,
        frameToPosition(0, 24).inMicroseconds);
    expect(positionToFrame(const Duration(microseconds: -1000), 24), 0);
  });

  test('a rate of zero falls back rather than dividing by it', () {
    // The asset registry does not always carry an fps; the engine's own
    // fallback is what the review lane anchors comments at.
    expect(frameToPosition(10, 0), frameToPosition(10, kReviewFallbackFps));
    expect(positionToFrame(const Duration(seconds: 1), 0),
        positionToFrame(const Duration(seconds: 1), kReviewFallbackFps));
    expect(frameToPosition(10, -30), frameToPosition(10, kReviewFallbackFps));
  });

  test('duration counts frames, and the last frame index is count-1', () {
    expect(durationToFrameCount(const Duration(seconds: 1), 24), 24);
    expect(durationToFrameCount(const Duration(seconds: 10), 25), 250);
    expect(durationToFrameCount(Duration.zero, 24), 0);

    // A one-second 24fps clip holds frames 0..23, and frame 23 is inside it.
    final count = durationToFrameCount(const Duration(seconds: 1), 24);
    expect(
        frameToPosition(count - 1, 24), lessThan(const Duration(seconds: 1)));
  });
}
