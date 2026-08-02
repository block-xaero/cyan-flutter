// models/region_gesture.dart
//
// PARITY face_review_player — the drawing surface's PURE half.
//
// SwiftUI reference (READ-ONLY):
//   Media/RegionGestureGeometry.swift — the whole reduction, verbatim
//
// Everything about turning a drag into a `region` that needs no widget, no
// surface and no frame. It lives apart from the overlay for one reason: the
// gesture→region path is a CORRECTNESS path — a skewed or off-by-one
// normalization writes a permanently wrong anchor — and correctness paths must
// be testable without a running app.
//
// THE TRAP THIS FILE EXISTS TO AVOID: normalizing against the WIDGET bounds.
// The picture is aspect-fit inside its box, so on any window whose shape is not
// the media's, the box and the picture differ — and a region normalized against
// the box is stretched and offset relative to the frame the human drew on.
// Every coordinate here is normalized against the PICTURE rect, then clamped.

import 'dart:math' as math;
import 'dart:ui';

/// A drag shorter than this (in logical pixels) is a CLICK, not a drag: it
/// seeds a `point` region rather than a degenerate 0×0 rect, which is a
/// validation error waiting to happen and never what the human meant.
const double kClickSlop = 3.0;

/// The modifier held during the drag chooses the shape: plain → rect,
/// ⌥ → ellipse, ⇧ → freeform path. Shift wins over option — freeform is the
/// more specific intent, and a human holding both is drawing, not ellipsing.
class RegionModifiers {
  final bool option;
  final bool shift;
  const RegionModifiers({this.option = false, this.shift = false});
  static const RegionModifiers none = RegionModifiers();

  String get draggedShape =>
      shift ? 'path' : (option ? 'ellipse' : 'rect');
}

/// A reduced drag: the shape the format stores and its normalized points.
class ReducedRegionGesture {
  final String kind;
  final List<Offset> points;
  const ReducedRegionGesture(this.kind, this.points);
}

/// The rect the PICTURE actually occupies inside [bounds], aspect-fit. The hero
/// enforces 16:9 on its box, but a box is not a picture: callers pass the
/// aspect they are actually displaying so this stays honest once the surface
/// reports a real natural size.
Rect pictureRect(Size bounds, double aspect) {
  if (bounds.width <= 0 || bounds.height <= 0 || aspect <= 0) return Rect.zero;
  final boundsAspect = bounds.width / bounds.height;
  if (boundsAspect > aspect) {
    // Pillarboxed — height fills, width is inset.
    final w = bounds.height * aspect;
    return Rect.fromLTWH((bounds.width - w) / 2, 0, w, bounds.height);
  }
  // Letterboxed — width fills, height is inset.
  final h = bounds.width / aspect;
  return Rect.fromLTWH(0, (bounds.height - h) / 2, bounds.width, h);
}

/// A widget-space point → normalized picture coordinates in [0, 1].
///
/// Clamped, not rejected: a drag that leaves the picture is a human overshooting
/// the edge of the frame, and the region they meant is the one bounded by the
/// frame. Refusing it would lose the note.
Offset normalizeToPicture(Offset point, Rect picture) {
  if (picture.width <= 0 || picture.height <= 0) return Offset.zero;
  final x = (point.dx - picture.left) / picture.width;
  final y = (point.dy - picture.top) / picture.height;
  return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
}

/// The draft box's strength while the playhead is off its anchor frame.
/// Deliberately well above zero — an invisible draft is the bug this prevents.
const double kDraftDimmedEmphasis = 0.35;

/// Full strength on the frame it was drawn on; dimmed (never hidden) elsewhere,
/// because a region is a tracker seed exact at its key frame and a full-strength
/// box on other frames would claim tracking the format does not have.
double draftEmphasis({required int anchorFrame, required int playhead}) =>
    anchorFrame == playhead ? 1.0 : kDraftDimmedEmphasis;

/// The whole reduction: a raw drag in widget space → (shape kind, normalized
/// points) ready for the composer.
///
/// `rect` and `ellipse` normalize to TWO points — origin then opposite corner,
/// ordered min-then-max on both axes. A drag up-and-left is the same region as
/// a drag down-and-right, and the stored form must not remember which way the
/// wrist moved, or two identical regions would hash differently.
ReducedRegionGesture? reduceRegionGesture({
  required List<Offset> dragPoints,
  required RegionModifiers modifiers,
  required Size bounds,
  required double aspect,
}) {
  if (dragPoints.isEmpty) return null;
  final first = dragPoints.first;
  final last = dragPoints.last;
  final picture = pictureRect(bounds, aspect);
  if (picture.width <= 0) return null;

  final travel =
      math.sqrt(math.pow(last.dx - first.dx, 2) + math.pow(last.dy - first.dy, 2));
  if (travel < kClickSlop) {
    return ReducedRegionGesture('point', [normalizeToPicture(first, picture)]);
  }

  if (modifiers.draggedShape == 'path') {
    // Freeform keeps the sampled polyline, deduplicated — a stutter of
    // identical samples is noise, not shape.
    final pts = <Offset>[];
    for (final p in dragPoints) {
      final n = normalizeToPicture(p, picture);
      if (pts.isNotEmpty && pts.last == n) continue;
      pts.add(n);
    }
    // A path needs ≥2 points; collapse to a point if the dedup ate it.
    return pts.length >= 2
        ? ReducedRegionGesture('path', pts)
        : ReducedRegionGesture('point', [pts.isEmpty ? Offset.zero : pts.first]);
  }

  final a = normalizeToPicture(first, picture);
  final b = normalizeToPicture(last, picture);
  return ReducedRegionGesture(modifiers.draggedShape, [
    Offset(math.min(a.dx, b.dx), math.min(a.dy, b.dy)),
    Offset(math.max(a.dx, b.dx), math.max(a.dy, b.dy)),
  ]);
}
