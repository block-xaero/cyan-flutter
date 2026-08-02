// models/spatial_note.dart
//
// PARITY face_review_player — the `ref` / `region` / `intent_struct` field
// groups a captured note carries.
//
// SwiftUI reference (READ-ONLY):
//   Review/SpatialNotes.swift  — the field-for-field mirror of the engine's
//                                `spatial.rs`, which is the format itself.
//
// This file invents NOTHING. Every name, key, closed vocabulary and optionality
// rule is the engine's.
//
// THE LAW THIS FILE MUST NOT BREAK: absent = OMITTED ENTIRELY, null is
// forbidden. An entry carrying none of these groups must serialize exactly as
// it did before they existed, or every `entry_hash` on every shipped device
// silently moves.
//
// Coordinates are fixed-point integers, never doubles: double formatting is not
// reproducible across writers, and two peers capturing the same note have to
// dedup to one row.

import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

/// Normalized coordinates are scaled by 1e6 and stored as integers.
const int kFixedScale = 1000000;

/// Normalized double → the hashed fixed-point form. API boundary only.
int toFixed(double v) => (v * kFixedScale).round();

/// The inverse, for RENDERING only — never for hashing.
double fromFixed(int v) => v / kFixedScale;

/// Referent classes (WAIST §1).
const List<String> kRefClassVocab = ['source', 'junction', 'entry', 'version'];

/// Region shape types (§2).
const List<String> kShapeVocab = ['point', 'rect', 'ellipse', 'path'];

/// `intent_struct.craft` (§3). `compliance` is in the FORMAT vocabulary but is
/// machine-authored only and is never offered as a composer chip — a surface
/// rule, which is why it validates here and is absent from [ComposerCraft].
const List<String> kCraftVocab = [
  'colour',
  'edit',
  'sound',
  'gfx',
  'compliance',
  'general',
];

/// Closed vocabulary for [Qualifier.mode].
const List<String> kQualifierModeVocab = ['colour-key'];

/// What a malformed capture is: refused at append rather than half-anchored.
class SpatialError implements Exception {
  final String message;
  const SpatialError(this.message);

  @override
  String toString() => message;
}

/// The shape, in normalized SOURCE clean-aperture coords as fixed-point ints.
@immutable
class RegionShape {
  /// JSON key is `type`.
  final String kind;

  /// `[[x, y], …]`, each scaled by [kFixedScale].
  final List<List<int>> points;

  const RegionShape({required this.kind, required this.points});

  Map<String, dynamic> toJson() => {'type': kind, 'points': points};

  static RegionShape? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    return RegionShape(
      kind: j['type'] as String? ?? '',
      points: [
        for (final p in (j['points'] as List? ?? const []))
          if (p is List) [for (final v in p) (v as num).toInt()],
      ],
    );
  }
}

/// The raster the shape was drawn on — pins the aspect / clean-aperture
/// mapping, so a shape drawn on a 960×540 proxy overlays correctly on a 4K
/// master and a letterboxed proxy does not silently skew.
@immutable
class RasterRef {
  final int w;
  final int h;
  const RasterRef({required this.w, required this.h});

  Map<String, dynamic> toJson() => {'w': w, 'h': h};

  static RasterRef? fromJson(Map<String, dynamic>? j) => j == null
      ? null
      : RasterRef(
          w: (j['w'] as num?)?.toInt() ?? 0, h: (j['h'] as num?)?.toInt() ?? 0);
}

/// The reviewer's scrub gesture while composing. Authored content, hence
/// hashed; consumers may ignore it. NOT a tracked extent.
@immutable
class ExtentHint {
  final int frameIn;
  final int frameOut;
  const ExtentHint({required this.frameIn, required this.frameOut});

  Map<String, dynamic> toJson() => {'frame_in': frameIn, 'frame_out': frameOut};

  static ExtentHint? fromJson(Map<String, dynamic>? j) => j == null
      ? null
      : ExtentHint(
          frameIn: (j['frame_in'] as num?)?.toInt() ?? 0,
          frameOut: (j['frame_out'] as num?)?.toInt() ?? 0);
}

/// A colour-keyed QUALIFIER riding the same region family: the drawn shape
/// becomes the SAMPLE AREA — "grade pixels LIKE the ones I drew over". The key
/// colour is never stored; the engine samples it at `key_frame`.
@immutable
class Qualifier {
  final String mode;
  const Qualifier({required this.mode});

  Map<String, dynamic> toJson() => {'mode': mode};

  static Qualifier? fromJson(Map<String, dynamic>? j) =>
      j == null ? null : Qualifier(mode: j['mode'] as String? ?? '');
}

/// A spatial referent that is exact at `key_frame` and raster-independent.
///
/// **A tracker SEED, not a power window.** A static box drawn on frame 100 does
/// not cover frame 150 and the format does not pretend otherwise — which is why
/// the overlay paints a region only on the frame it was drawn on.
@immutable
class NoteRegion {
  /// SOURCE frame the shape was drawn at.
  final int keyFrame;
  final RegionShape shape;
  final RasterRef rasterRef;
  final ExtentHint? extentHint;
  final Qualifier? qualifier;

  const NoteRegion({
    required this.keyFrame,
    required this.shape,
    required this.rasterRef,
    this.extentHint,
    this.qualifier,
  });

  NoteRegion copyWith({ExtentHint? extentHint}) => NoteRegion(
        keyFrame: keyFrame,
        shape: shape,
        rasterRef: rasterRef,
        extentHint: extentHint ?? this.extentHint,
        qualifier: qualifier,
      );

  /// Absent = OMITTED ENTIRELY — never a null-valued key.
  Map<String, dynamic> toJson() => {
        'key_frame': keyFrame,
        'shape': shape.toJson(),
        'raster_ref': rasterRef.toJson(),
        if (extentHint != null) 'extent_hint': extentHint!.toJson(),
        if (qualifier != null) 'qualifier': qualifier!.toJson(),
      };

  static NoteRegion? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final shape = RegionShape.fromJson(j['shape'] as Map<String, dynamic>?);
    final raster = RasterRef.fromJson(j['raster_ref'] as Map<String, dynamic>?);
    if (shape == null || raster == null) return null;
    return NoteRegion(
      keyFrame: (j['key_frame'] as num?)?.toInt() ?? 0,
      shape: shape,
      rasterRef: raster,
      extentHint: ExtentHint.fromJson(j['extent_hint'] as Map<String, dynamic>?),
      qualifier: Qualifier.fromJson(j['qualifier'] as Map<String, dynamic>?),
    );
  }

  /// Mirror of the engine's `Region::validate`.
  void validate() {
    if (!kShapeVocab.contains(shape.kind)) {
      throw SpatialError(
          "region.shape.type '${shape.kind}' not in closed vocab");
    }
    final n = shape.points.length;
    final ok = switch (shape.kind) {
      'point' => n == 1,
      'rect' || 'ellipse' => n == 2,
      _ => n >= 2,
    };
    if (!ok) {
      throw SpatialError('region.shape type=${shape.kind} has $n points');
    }
    if (!shape.points.every((p) => p.length == 2)) {
      throw const SpatialError('region.shape points must be [x, y] pairs');
    }
    if (rasterRef.w <= 0 || rasterRef.h <= 0) {
      throw const SpatialError('region.raster_ref must be positive');
    }
    final hint = extentHint;
    if (hint != null && hint.frameOut < hint.frameIn) {
      throw const SpatialError('region.extent_hint inverted');
    }
    final q = qualifier;
    if (q != null) {
      if (!kQualifierModeVocab.contains(q.mode)) {
        throw SpatialError(
            "region.qualifier.mode '${q.mode}' not in closed vocab");
      }
      // A qualifier SAMPLES the shape — a point has no pixels to sample.
      if (shape.kind == 'point') {
        throw const SpatialError(
            "a qualifier needs a sample AREA: this region is a 'point'");
      }
    }
  }

  /// Project the normalized shape onto a target raster, in PIXELS. Rendering
  /// only — never hashing.
  List<Offset> project(Size target) => [
        for (final p in shape.points)
          if (p.length == 2)
            Offset(fromFixed(p[0]) * target.width,
                fromFixed(p[1]) * target.height),
      ];
}

/// `class=source` — about CONTENT. Frames are SOURCE frames.
@immutable
class SourceRef {
  final String assetHash;
  final int frameIn;
  final int? frameOut;

  const SourceRef({
    required this.assetHash,
    required this.frameIn,
    this.frameOut,
  });

  Map<String, dynamic> toJson() => {
        'asset_hash': assetHash,
        'frame_in': frameIn,
        if (frameOut != null) 'frame_out': frameOut,
      };

  static SourceRef? fromJson(Map<String, dynamic>? j) => j == null
      ? null
      : SourceRef(
          assetHash: j['asset_hash'] as String? ?? '',
          frameIn: (j['frame_in'] as num?)?.toInt() ?? 0,
          frameOut: (j['frame_out'] as num?)?.toInt(),
        );
}

/// The note's identity — what it is ABOUT. The legacy anchor columns remain the
/// ledger key; this is the referent. Exactly ONE payload, matching `class`.
@immutable
class EntryRef {
  final String refClass;
  final SourceRef? src;

  const EntryRef({required this.refClass, this.src});

  factory EntryRef.source(String assetHash, int frameIn, {int? frameOut}) =>
      EntryRef(
        refClass: 'source',
        src: SourceRef(
            assetHash: assetHash, frameIn: frameIn, frameOut: frameOut),
      );

  Map<String, dynamic> toJson() => {
        'class': refClass,
        if (src != null) 'src': src!.toJson(),
      };

  static EntryRef? fromJson(Map<String, dynamic>? j) => j == null
      ? null
      : EntryRef(
          refClass: j['class'] as String? ?? '',
          src: SourceRef.fromJson(j['src'] as Map<String, dynamic>?));

  /// Mirror of `EntryRef::validate` for the class this build writes.
  void validate() {
    if (!kRefClassVocab.contains(refClass)) {
      throw SpatialError("ref.class '$refClass' not in closed vocab");
    }
    if (refClass == 'source') {
      final s = src;
      if (s == null) {
        throw const SpatialError('ref.class=source requires its payload');
      }
      if (s.assetHash.trim().isEmpty) {
        throw const SpatialError('ref.src.asset_hash required');
      }
      // Reversed segments normalize AT CAPTURE; a stored inverted range is a
      // writer bug, not a retime.
      final out = s.frameOut;
      if (out != null && out < s.frameIn) {
        throw const SpatialError(
            'ref.src frame_out < frame_in — normalize at capture');
      }
    }
  }
}

/// `{craft, structured?}`. Routing and training weights read this; absent means
/// general, which is the normative meaning of a skipped chip row.
@immutable
class IntentStruct {
  final String craft;
  final Map<String, dynamic>? structured;

  const IntentStruct({required this.craft, this.structured});

  Map<String, dynamic> toJson() => {
        'craft': craft,
        if (structured != null) 'structured': structured,
      };

  static IntentStruct? fromJson(Map<String, dynamic>? j) => j == null
      ? null
      : IntentStruct(
          craft: j['craft'] as String? ?? '',
          structured: j['structured'] as Map<String, dynamic>?);

  void validate() {
    if (!kCraftVocab.contains(craft)) {
      throw SpatialError("intent_struct.craft '$craft' not in closed vocab");
    }
  }
}

/// What the author was looking at when they wrote the note. **Never part of
/// identity** — two peers capturing the same note, one with a hint and one
/// without, must dedup to ONE row, so this rides alongside the entry unhashed.
@immutable
class CaptureCtx {
  final String? versionId;
  final int? tlFrame;
  final RasterRef? proxyRaster;

  const CaptureCtx({this.versionId, this.tlFrame, this.proxyRaster});

  Map<String, dynamic> toJson() => {
        if (versionId != null) 'version_id': versionId,
        if (tlFrame != null) 'tl_frame': tlFrame,
        if (proxyRaster != null) 'proxy_raster': proxyRaster!.toJson(),
      };

  static CaptureCtx? fromJson(Map<String, dynamic>? j) => j == null
      ? null
      : CaptureCtx(
          versionId: j['version_id'] as String?,
          tlFrame: (j['tl_frame'] as num?)?.toInt(),
          proxyRaster:
              RasterRef.fromJson(j['proxy_raster'] as Map<String, dynamic>?));
}
