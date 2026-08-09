// services/media_kit_review_surface.dart
//
// The WINDOWS review surface — libmpv through media_kit.
//
// WHY THIS EXISTS: `video_player` has no Windows implementation. Its pub cache
// carries android / avfoundation / web and nothing else, so on this platform
// `VideoPlayerController.file()` throws and the review station had a door, a
// scrubber, a timecode rail and no picture. This is the decoder half.
//
// WHY libmpv AND NOT MEDIA FOUNDATION, both of which are requirements:
//
//   • FRAME ACCURACY. mpv's `hr-seek=yes` makes every seek exact rather than
//     keyframe-biased. Frame-exactness is the whole contract of
//     `ReviewVideoSurface.seek`, and a keyframe seek on a long-GOP proxy can
//     miss by a second — which on a review station means a note landing on the
//     wrong shot.
//   • THE PLATES. libmpv is ffmpeg-backed and decodes ProRes 422/4444 and
//     DNxHD/HR. Media Foundation cannot open ProRes at all, so the "drop-in"
//     Windows implementation of the video_player API would have played proxies
//     and failed on the masters this station exists to review.
//
// BRAW is out of scope by design: it is Blackmagic-SDK-only and this surface
// sees conform outputs (ProRes / H.264 proxies), never camera negative.
//
// FRAMES ARE THE TRUTH, exactly as in the macOS surface and in Swift's
// `ReviewPlayerViewModel`. The frame<->instant arithmetic is shared with the
// macOS surface (`frameToPosition` / `positionToFrame` in
// review_video_surface.dart), so both platforms land on a frame the same way
// and the property is proved once, in test/frame_accuracy_test.dart.

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'review_video_surface.dart';

/// Whether [MediaKitReviewSurface] may be constructed yet.
///
/// `MediaKit.ensureInitialized()` is process-wide and must run before the first
/// player. Tracked here rather than left to the caller so a second surface
/// (the graphics-strip preview mounts its own) cannot double-initialise.
bool _mediaKitReady = false;

void _ensureMediaKit() {
  if (_mediaKitReady) return;
  MediaKit.ensureInitialized();
  _mediaKitReady = true;
}

/// The production surface on Windows (and any other libmpv target).
class MediaKitReviewSurface extends ReviewVideoSurface {
  MediaKitReviewSurface() {
    _ensureMediaKit();
    _player = Player();
    _controller = VideoController(_player);

    // EXACT SEEKING. Without this mpv seeks to the nearest keyframe, which is
    // fast and wrong: on a long-GOP proxy the picture can land a second away
    // from the frame the timecode claims. `hr-seek=yes` costs decode time
    // between the keyframe and the target and buys the only property this
    // surface is judged on.
    final native = _player.platform;
    if (native is NativePlayer) {
      native.setProperty('hr-seek', 'yes');
      // Seek to the exact instant even when it means demuxing forward, and do
      // not drop frames to keep the clock — a review station wants the right
      // picture, not a smooth wall clock.
      native.setProperty('hr-seek-framedrop', 'no');
    }

    _subs = [
      _player.stream.position.listen((p) {
        _position = p;
        notifyListeners();
      }),
      _player.stream.duration.listen((d) {
        _duration = d;
        notifyListeners();
      }),
      _player.stream.playing.listen((p) {
        _playing = p;
        notifyListeners();
      }),
      _player.stream.width.listen((w) {
        _width = w;
        notifyListeners();
      }),
      _player.stream.height.listen((h) {
        _height = h;
        notifyListeners();
      }),
      // The decoder's own refusal, verbatim. A face that cannot show the
      // picture must say why rather than spin forever.
      _player.stream.error.listen((e) {
        _failure = e;
        notifyListeners();
      }),
    ];
  }

  late final Player _player;
  late final VideoController _controller;
  late final List<dynamic> _subs;

  String? _path;
  double _fps = kReviewFallbackFps;
  String? _failure;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  int? _width;
  int? _height;

  /// The playhead we ASKED for, held until the decoder's own position catches
  /// up past it.
  ///
  /// A seek is not instantaneous, and an exact seek least of all. Reporting the
  /// decoder's stale position in the meantime would make the timecode jump
  /// backwards under the operator's cursor while they scrub, and would anchor a
  /// comment at a frame they had already left.
  int? _requestedFrame;

  /// Why the last load did not mount. Null when the picture is up.
  String? get failure => _failure;

  @override
  String? get mountedPath => _path;

  @override
  double get fps => _fps;

  @override
  bool get isPlaying => _playing;

  @override
  int get currentFrame {
    final observed = positionToFrame(_position, _fps);
    final requested = _requestedFrame;
    if (requested == null) return observed;
    // Once the decoder reports the frame we asked for, the request has landed
    // and the observed position takes over again.
    if (observed == requested) {
      _requestedFrame = null;
      return observed;
    }
    return requested;
  }

  @override
  int get durationFrames => durationToFrameCount(_duration, _fps);

  /// A seek in flight is a POSITIVE reason to refuse capture: the picture on
  /// screen is not yet the frame the playhead claims, so a region captured now
  /// would be anchored to a frame nobody looked at.
  @override
  bool get isCaptureGrade => _failure == null && _requestedFrame == null;

  @override
  Size? get raster {
    final w = _width, h = _height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return Size(w.toDouble(), h.toDouble());
  }

  @override
  Future<void> load(String path, {double fps = kReviewFallbackFps}) async {
    _path = path;
    _fps = fps > 0 ? fps : kReviewFallbackFps;
    _failure = null;
    _requestedFrame = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();

    try {
      // Opened PAUSED: a review station that starts playing the moment media
      // mounts has already moved the playhead away from where the operator was
      // sent.
      await _player.open(Media(path), play: false);
    } catch (e) {
      _failure = e.toString();
      notifyListeners();
    }
  }

  @override
  void seek(int frame) {
    if (_path == null) return;
    final upper = durationFrames > 0 ? durationFrames - 1 : frame;
    final target = frame < 0 ? 0 : (frame > upper ? upper : frame);
    _requestedFrame = target;
    notifyListeners();
    // Fire and forget: the position stream is what confirms the landing, and
    // awaiting here would serialise a scrub into a queue of stale seeks.
    _player.seek(frameToPosition(target, _fps));
  }

  @override
  void play() => _player.play();

  @override
  void pause() => _player.pause();

  @override
  Widget buildPicture(BuildContext context) {
    if (_failure != null || _path == null) {
      return UnmountedPicture(path: _path, failure: _failure);
    }
    return Video(
      controller: _controller,
      // The review station draws its own transport; mpv's would be a second,
      // disagreeing one.
      controls: NoVideoControls,
      fill: Colors.black,
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
