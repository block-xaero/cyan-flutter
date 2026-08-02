// providers/region_composer_controller.dart
//
// PARITY face_review_player — THE CAPTURE SURFACE.
//
// SwiftUI reference (READ-ONLY):
//   ViewModels/RegionComposerViewModel.swift — the vocabulary, the tap budget,
//        capture-time resolution, the look corpus, and the agent ask
//   Media/RegionGestureController.swift      — the anchor-at-the-press machine
//
// The discipline this obeys, imported not reinvented: **nobody will ever
// annotate for our model.** The reviewer is writing to a human. The annotation
// they make to communicate IS the training example — the region they draw is
// the spatial referent, the chips they tap are the classification, the
// lifecycle the note already has is the outcome label. A sensor that taxes the
// message kills the message, and then there is no sensor.
//
// Hence, hard rules rather than preferences:
//   - tap budget 0–3, every row skippable, NO follow-up nag EVER;
//   - zero taps + free text + Enter is a VALID note at weight 0.25;
//   - the displayed shortlist never exceeds 4 (the tenant vocabulary may);
//   - pre-ranking permutes ORDER ONLY — never the vocabulary, never the count.
//
// Everything leaves through the ONE `CyanBackend` seam. The composer has no
// authority and no persistence of its own — and it READS THE RESPONSE: a
// capture that did not persist fails loudly and KEEPS the draft, because a
// clear() after a write that never happened throws the reviewer's work away.

import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../ffi/cyan_backend.dart';
import '../ffi/parity_models.dart';
import '../models/region_gesture.dart';
import '../models/spatial_note.dart';

/// The craft row — EXACTLY these four. `compliance` is in the format vocabulary
/// but is machine-authored only and is never offered as a chip; `general` is
/// what no tap means, so it is not a chip either.
enum ComposerCraft { colour, edit, sound, gfx }

extension ComposerCraftX on ComposerCraft {
  String get wireName => name;
  String get label => switch (this) {
        ComposerCraft.colour => 'colour',
        ComposerCraft.edit => 'edit',
        ComposerCraft.sound => 'sound',
        ComposerCraft.gfx => 'gfx',
      };
}

/// Per-tenant vocabularies. Sizes are deliberately allowed to exceed 4 — the
/// SHORTLIST is capped, not the vocabulary.
class ComposerVocabulary {
  final Map<ComposerCraft, List<String>> subjects;
  final Map<String, List<String>> defects;

  const ComposerVocabulary({required this.subjects, required this.defects});

  static const ComposerVocabulary standard = ComposerVocabulary(
    subjects: {
      ComposerCraft.colour: ['skin', 'sky', 'practical', 'product', 'mood', 'foliage'],
      ComposerCraft.edit: ['trim', 'hold', 'swap', 'reorder'],
      ComposerCraft.sound: ['level', 'mute', 'fade', 'sync'],
      ComposerCraft.gfx: ['swap', 'insert'],
    },
    defects: {
      'skin': ['too-warm', 'too-cool', 'plastic', 'muddy', 'mismatch'],
      'sky': ['too-cyan', 'blown', 'banded', 'mismatch'],
      'practical': ['too-hot', 'colour-shift', 'mismatch'],
      'product': ['off-brand', 'too-warm', 'mismatch'],
      'mood': ['too-flat', 'too-heavy', 'mismatch'],
      'foliage': ['too-yellow', 'too-saturated', 'mismatch'],
    },
  );
}

/// The displayed shortlist cap. Not a layout constant — a capture-design rule.
const int kShortlistLimit = 4;

/// A drawn shape plus the EXACT frame it was drawn on, captured at gesture time.
///
/// The frame is snapshotted here and never re-read: between the gesture and the
/// send the playhead may move (the reviewer scrubs while typing), and re-reading
/// it at send time would anchor the note to a frame nobody was looking at.
class RegionDraft {
  final RegionShape shape;
  final RasterRef raster;

  /// The timeline frame displayed at the moment of the gesture.
  final int displayedFrame;

  /// Frames the playhead visited while composing — becomes `extent_hint`.
  final int? scrubbedLow;
  final int? scrubbedHigh;

  const RegionDraft({
    required this.shape,
    required this.raster,
    required this.displayedFrame,
    this.scrubbedLow,
    this.scrubbedHigh,
  });

  RegionDraft withScrub(int low, int high) => RegionDraft(
        shape: shape,
        raster: raster,
        displayedFrame: displayedFrame,
        scrubbedLow: low,
        scrubbedHigh: high,
      );
}

/// A drag in progress — the overlay draws the rubber band off this.
class RegionInFlight {
  final List<Offset> points;
  final RegionModifiers modifiers;

  /// The playhead frame AT THE PRESS. The whole point of this type: a drag
  /// takes real time, and resolving the region against the RELEASE frame
  /// anchors the note to a picture nobody pointed at.
  final int anchorFrame;
  final bool wasPlaying;

  const RegionInFlight({
    required this.points,
    required this.modifiers,
    required this.anchorFrame,
    required this.wasPlaying,
  });

  RegionInFlight extended(Offset p) => RegionInFlight(
        points: [...points, p],
        modifiers: modifiers,
        anchorFrame: anchorFrame,
        wasPlaying: wasPlaying,
      );
}

/// Published composer state.
class RegionComposerState {
  final RegionInFlight? inFlight;
  final RegionDraft? draft;
  final ComposerCraft? craft;
  final String? subject;
  final String? defect;

  /// Counts chip taps only — text and send are not taps against the budget.
  final int tapCount;

  /// The colour-keyed QUALIFIER toggle: the drawn shape becomes the SAMPLE area
  /// ("grade pixels LIKE these") instead of the grade window.
  final bool qualifyByColour;

  /// Why the last capture did not land. Never success-into-noise: a refused
  /// write says so and the draft survives it.
  final String? failure;

  /// An agent pass is running. The picture on screen is still the ungraded one.
  final bool isAsking;

  /// What the agent produced for the last entry, when it produced anything.
  final String? gradedPath;

  /// The agent DECIDED not to act, and said why. A real answer, not a failure.
  final String? declined;

  const RegionComposerState({
    this.inFlight,
    this.draft,
    this.craft,
    this.subject,
    this.defect,
    this.tapCount = 0,
    this.qualifyByColour = false,
    this.failure,
    this.isAsking = false,
    this.gradedPath,
    this.declined,
  });

  RegionComposerState copyWith({
    RegionInFlight? inFlight,
    bool clearInFlight = false,
    RegionDraft? draft,
    bool clearDraft = false,
    ComposerCraft? craft,
    bool clearCraft = false,
    String? subject,
    bool clearSubject = false,
    String? defect,
    bool clearDefect = false,
    int? tapCount,
    bool? qualifyByColour,
    String? failure,
    bool clearFailure = false,
    bool? isAsking,
    String? gradedPath,
    bool clearGraded = false,
    String? declined,
    bool clearDeclined = false,
  }) =>
      RegionComposerState(
        inFlight: clearInFlight ? null : (inFlight ?? this.inFlight),
        draft: clearDraft ? null : (draft ?? this.draft),
        craft: clearCraft ? null : (craft ?? this.craft),
        subject: clearSubject ? null : (subject ?? this.subject),
        defect: clearDefect ? null : (defect ?? this.defect),
        tapCount: tapCount ?? this.tapCount,
        qualifyByColour: qualifyByColour ?? this.qualifyByColour,
        failure: clearFailure ? null : (failure ?? this.failure),
        isAsking: isAsking ?? this.isAsking,
        gradedPath: clearGraded ? null : (gradedPath ?? this.gradedPath),
        declined: clearDeclined ? null : (declined ?? this.declined),
      );

  /// 1.0 when the reason is fully expressed, 0.25 otherwise. A skipped chip is
  /// not a defect in the note: zero-tap notes are first-class, they simply
  /// carry less signal. NEVER part of hashed content — a weight is a reading of
  /// the entry, not part of its identity.
  double get trainingWeight {
    final c = craft;
    if (c == null) return 0.25;
    if (c == ComposerCraft.colour) {
      return (subject != null && defect != null) ? 1.0 : 0.25;
    }
    return subject != null ? 1.0 : 0.25;
  }
}

/// What the surface has to be able to tell the composer for a capture to be
/// trustworthy. Kept as closures rather than a reference to the player
/// controller because BOTH the tenant and the version arrive ASYNC — capturing
/// either by value at construction freezes a placeholder forever, which is the
/// exact anti-pattern that shipped a composer whose every note the engine
/// refused with "tenant_id required" while the UI reported success.
typedef LiveString = String Function();
typedef FrameResolver = int Function(int displayFrame);

class RegionComposerController extends StateNotifier<RegionComposerState> {
  RegionComposerController({
    required this.backend,
    required this.boardId,
    required this.resolveTenantId,
    required this.resolveAssetHash,
    required this.resolveVersionId,
    required this.resolveSourceFrame,
    required this.isCaptureGrade,
    required this.playheadFrame,
    required this.isPlaying,
    required this.pause,
    this.vocabulary = ComposerVocabulary.standard,
    this.aspect = 16 / 9,
  }) : super(const RegionComposerState());

  final CyanBackend backend;

  /// The board whose media a grade renders against.
  final String boardId;

  final LiveString resolveTenantId;
  final LiveString resolveAssetHash;
  final LiveString resolveVersionId;

  /// Capture-time resolution: the displayed (timeline) frame → the SOURCE frame
  /// the note anchors on, through the engine's conform map.
  final FrameResolver resolveSourceFrame;

  final bool Function() isCaptureGrade;
  final int Function() playheadFrame;
  final bool Function() isPlaying;
  final void Function() pause;

  final ComposerVocabulary vocabulary;

  /// The displayed picture's aspect — carried explicitly so the normalization
  /// stays correct once the surface reports a real natural size.
  final double aspect;

  /// The author's recent craft taps. Breaks ties in ranking ONLY.
  final List<ComposerCraft> _recentCrafts = [];

  /// The engine's look table, fetched once. NEVER a second copy of the corpus:
  /// the engine owns it and refuses against it, so a hardcoded list here would
  /// drift into "the app offered a look the engine will not render".
  Map<String, String>? _lookCorpus;

  final Uuid _uuid = const Uuid();

  RegionComposerState get current => state;

  // ---- the drag ------------------------------------------------------------

  /// Pointer down on the picture. Snapshots the anchor frame and PAUSES:
  /// drawing on a moving picture is not a thing an editor does, and a paused
  /// surface makes the frame the human sees and the frame we anchor to the same
  /// frame by construction rather than by timing luck.
  void beginDrag(Offset point, {RegionModifiers modifiers = RegionModifiers.none}) {
    final wasPlaying = isPlaying();
    if (wasPlaying) pause();
    state = state.copyWith(
      inFlight: RegionInFlight(
        points: [point],
        modifiers: modifiers,
        anchorFrame: playheadFrame(),
        wasPlaying: wasPlaying,
      ),
      clearFailure: true,
    );
  }

  void extendDrag(Offset point) {
    final f = state.inFlight;
    if (f == null) return;
    state = state.copyWith(inFlight: f.extended(point));
  }

  /// Pointer up — reduce the drag and open the composer ON THE ANCHOR FRAME.
  /// False when there was no live drag or the geometry could not be reduced
  /// (a zero-size box, typically).
  bool endDrag(Size bounds) {
    final f = state.inFlight;
    if (f == null) return false;
    final reduced = reduceRegionGesture(
      dragPoints: f.points,
      modifiers: f.modifiers,
      bounds: bounds,
      aspect: aspect,
    );
    if (reduced == null) {
      state = state.copyWith(clearInFlight: true);
      return false;
    }
    final picture = pictureRect(bounds, aspect);
    beginRegion(
      kind: reduced.kind,
      normalizedPoints: reduced.points,
      raster: RasterRef(w: picture.width.round(), h: picture.height.round()),
      // THE FIX: the press frame, not the release frame.
      anchorFrame: f.anchorFrame,
    );
    return true;
  }

  /// Abandon a drag. Restores playback only if the press interrupted it.
  void cancelDrag({void Function()? resume}) {
    final f = state.inFlight;
    if (f == null) return;
    state = state.copyWith(clearInFlight: true);
    if (f.wasPlaying) resume?.call();
  }

  /// Seed a region and open the composer. [anchorFrame] is the frame the human
  /// was LOOKING AT when the gesture started.
  void beginRegion({
    required String kind,
    required List<Offset> normalizedPoints,
    required RasterRef raster,
    int? anchorFrame,
  }) {
    final anchor = anchorFrame ?? playheadFrame();
    state = RegionComposerState(
      draft: RegionDraft(
        shape: RegionShape(
          kind: kind,
          points: [
            for (final p in normalizedPoints) [toFixed(p.dx), toFixed(p.dy)]
          ],
        ),
        raster: raster,
        displayedFrame: anchor,
      ),
    );
  }

  /// A scrub WHILE composing is authored content: it records the reviewer's
  /// sense of extent. No scrub leaves `extent_hint` ABSENT — never null.
  void notePlayhead(int frame) {
    final d = state.draft;
    if (d == null) return;
    final low = (d.scrubbedLow ?? d.displayedFrame) < frame
        ? (d.scrubbedLow ?? d.displayedFrame)
        : frame;
    final high = (d.scrubbedHigh ?? d.displayedFrame) > frame
        ? (d.scrubbedHigh ?? d.displayedFrame)
        : frame;
    if (low == high) return;
    state = state.copyWith(draft: d.withScrub(low, high));
  }

  void cancel() => state = const RegionComposerState();

  // ---- the chip rows (0–3 taps, every row skippable) -----------------------

  /// The craft row — exactly 4, order permuted by cheap context.
  ///
  /// **Pre-ranking is context, not CV**: a drawn region ranks colour/gfx up, an
  /// audio-lane gesture ranks sound up, a trim/speed op under the playhead ranks
  /// edit up, and the author's recent taps break ties.
  List<ComposerCraft> craftShortlist({
    bool? regionPresent,
    bool audioLane = false,
    String? opUnderPlayhead,
  }) {
    final hasRegion = regionPresent ?? (state.draft != null);
    final scored = <({ComposerCraft craft, int score, int order})>[];
    var order = 0;
    for (final craft in ComposerCraft.values) {
      var score = 0;
      if (hasRegion &&
          (craft == ComposerCraft.colour || craft == ComposerCraft.gfx)) {
        score += 3;
      }
      if (audioLane && craft == ComposerCraft.sound) score += 5;
      if (opUnderPlayhead != null &&
          const ['trim', 'speed', 'reorder', 'swap'].contains(opUnderPlayhead) &&
          craft == ComposerCraft.edit) {
        score += 4;
      }
      // Recency breaks ties only — a weaker signal than the gesture itself.
      final idx = _recentCrafts.indexOf(craft);
      if (idx >= 0) score += (2 - idx) < 0 ? 0 : (2 - idx);
      scored.add((craft: craft, score: score, order: order++));
    }
    // Stable: equal scores keep the canonical order, or the "order only"
    // guarantee is untestable.
    scored.sort((a, b) =>
        a.score != b.score ? b.score.compareTo(a.score) : a.order.compareTo(b.order));
    return [for (final s in scored) s.craft];
  }

  /// Second row — the tenant vocabulary, DISPLAYED shortlist capped at 4.
  List<String> subjectShortlist() {
    final c = state.craft;
    if (c == null) return const [];
    return (vocabulary.subjects[c] ?? const []).take(kShortlistLimit).toList();
  }

  /// Third row — colour only, and only after a SUBJECT tap.
  List<String> defectShortlist() {
    final subject = state.subject;
    if (state.craft != ComposerCraft.colour || subject == null) return const [];
    return (vocabulary.defects[subject] ?? const []).take(kShortlistLimit).toList();
  }

  void tapCraft(ComposerCraft value) {
    if (state.draft == null) return;
    // Changing craft invalidates the rows below it.
    state = state.copyWith(
        craft: value,
        clearSubject: true,
        clearDefect: true,
        tapCount: state.tapCount + 1);
  }

  void tapSubject(String value) {
    if (state.craft == null || !subjectShortlist().contains(value)) return;
    state = state.copyWith(
        subject: value, clearDefect: true, tapCount: state.tapCount + 1);
  }

  void tapDefect(String value) {
    if (!defectShortlist().contains(value)) return;
    state = state.copyWith(defect: value, tapCount: state.tapCount + 1);
  }

  /// Toggle the colour-keyed qualifier. Refused (silently, like every other
  /// chip guard) on a point draft — a point has no pixels to sample.
  void toggleQualifier() {
    final d = state.draft;
    if (d == null || d.shape.kind == 'point') return;
    state = state.copyWith(
        qualifyByColour: !state.qualifyByColour, tapCount: state.tapCount + 1);
  }

  // ---- the look corpus (engine-owned) --------------------------------------

  /// canonical + every alias → canonical, lowercased. Fetched once; an engine
  /// that cannot answer leaves colour text as prose, which degrades to a note
  /// rather than a wrong grade.
  Future<Map<String, String>> _corpus() async {
    final cached = _lookCorpus;
    if (cached != null) return cached;
    final table = <String, String>{};
    try {
      final reply = await backend.changelistCommand({'op': 'look_corpus'});
      for (final row in (reply.fields['looks'] as List? ?? const [])) {
        if (row is! Map<String, dynamic>) continue;
        final canonical = row['look'] as String?;
        if (canonical == null) continue;
        table[normalizeLook(canonical)] = canonical;
        for (final alias in (row['aliases'] as List? ?? const [])) {
          if (alias is String) table[normalizeLook(alias)] = canonical;
        }
      }
    } catch (_) {
      // No corpus is not a wrong corpus: the text stays prose.
    }
    _lookCorpus = table;
    return table;
  }

  /// Match the engine's `normalize_look`: case-folded, punctuation dropped,
  /// whitespace collapsed. EXACT alternate spellings only — never a prefix and
  /// never fuzzy, because guessing which look a reviewer meant is the
  /// silent-wrong-grade failure the engine refuses to make.
  static String normalizeLook(String s) {
    final kept = s
        .toLowerCase()
        .split('')
        .map((ch) => RegExp(r'[a-z0-9]').hasMatch(ch) ? ch : ' ')
        .join();
    return kept.split(' ').where((p) => p.isNotEmpty).join(' ');
  }

  /// The canonical look this text names, or null if it is prose.
  Future<String?> resolvedLook(String text) async =>
      (await _corpus())[normalizeLook(text)];

  // ---- send (capture-time resolution) --------------------------------------

  /// Enter with text only, zero chips, is a valid note. There is no required
  /// field and nothing prompts for more.
  ///
  /// Returns the entry row the ENGINE stored, or null on a refusal — in which
  /// case [RegionComposerState.failure] says why and the draft SURVIVES.
  Future<Map<String, dynamic>?> send(String text) async {
    // THE GATE. Region capture turns the displayed frame into a permanent
    // source anchor; on a surface that cannot report the frame it is showing
    // that anchor is silently wrong and no later pass can tell which rows are
    // affected. Refuse loudly instead.
    if (!isCaptureGrade()) {
      state = state.copyWith(
          failure:
              'the video surface is not frame-exact — capture refused rather than write a wrong anchor');
      return null;
    }
    final draft = state.draft;
    if (draft == null) {
      state = state.copyWith(failure: 'no region drawn');
      return null;
    }

    // Resolve against the frame SNAPSHOTTED AT THE GESTURE, never a fresh read.
    final tlFrame = draft.displayedFrame;
    final assetHash = resolveAssetHash();
    if (assetHash.isEmpty) {
      state = state.copyWith(
          failure: 'no source resolves at timeline frame $tlFrame');
      return null;
    }
    final srcFrame = resolveSourceFrame(tlFrame);

    var region = NoteRegion(
      keyFrame: srcFrame,
      shape: draft.shape,
      rasterRef: draft.raster,
      qualifier:
          state.qualifyByColour ? const Qualifier(mode: 'colour-key') : null,
    );
    if (draft.scrubbedLow != null && draft.scrubbedHigh != null) {
      // Map the scrub's timeline ends into source space.
      final lo = resolveSourceFrame(draft.scrubbedLow!);
      final hi = resolveSourceFrame(draft.scrubbedHigh!);
      region = region.copyWith(
          extentHint: ExtentHint(
              frameIn: lo < hi ? lo : hi, frameOut: lo < hi ? hi : lo));
    }

    final ref = EntryRef.source(assetHash, srcFrame);
    try {
      ref.validate();
      region.validate();
    } on SpatialError catch (e) {
      state = state.copyWith(failure: e.message);
      return null;
    }

    // Text that NAMES a corpus look is not prose ABOUT the picture — it is an
    // instruction to change it, and the ledger already has the shape: `color`
    // is in the op vocabulary with {look} params, documented as pairing with
    // the entry's additive `region`. Everything else stays a note. Colour prose
    // is NOT approximated onto the nearest look: matching is EXACT, the engine
    // refuses unknown looks, and guessing which look a reviewer meant is
    // exactly the silent-wrong-grade failure.
    //
    // The chip gate is one-sided: zero taps + a corpus name IS a colour
    // instruction (the demo gesture is draw + "warm punchy" + Enter, no chips).
    // An EXPLICIT non-colour craft tap still wins — "edit: warm punchy" is
    // prose about an edit.
    final look = (state.craft == ComposerCraft.colour || state.craft == null)
        ? await resolvedLook(text)
        : null;

    final tenantId = resolveTenantId();
    // Preflight the one field the engine hard-requires and the app resolves
    // async. Refuse loudly AND KEEP the draft — the engine would refuse it
    // anyway; this just says why in the app's terms.
    if (tenantId.isEmpty) {
      state = state.copyWith(
          failure:
              'the engine refused the note: tenant not resolved yet — the review probe has not answered');
      return null;
    }

    final intentStruct = _intentStruct();
    final entry = <String, dynamic>{
      'id': _uuid.v4(),
      'asset_hash': assetHash,
      'tenant_id': tenantId,
      'tc_in': tlFrame,
      'kind': look == null ? 'note' : 'op',
      if (look != null) 'op': 'color',
      'params': look == null ? const {} : {'look': look},
      'intent': text,
      'source': 'cyan-player',
      'role': 'reviewer',
      'proposed_by': 'human',
      'state': 'proposed',
      'ref': ref.toJson(),
      'region': region.toJson(),
      if (intentStruct != null) 'intent_struct': intentStruct.toJson(),
      // Capture context is provenance, NEVER identity: two peers capturing the
      // same note with and without it must dedup to one row.
      'capture_ctx': CaptureCtx(
        versionId: resolveVersionId(),
        tlFrame: tlFrame,
        proxyRaster: draft.raster,
      ).toJson(),
    };

    ChangelistCommandResult reply;
    try {
      reply = await backend
          .changelistCommand({'op': 'append_entry', 'entry': entry});
    } catch (e) {
      // THE RESPONSE IS NOT OPTIONAL TO READ. Discarding it is what let a
      // non-existent verb ship: the note never landed and nothing — not the
      // UI, not the suite — could tell.
      state = state.copyWith(
          failure: 'the engine refused the note: ${e.toString()}');
      return null;
    }
    if (!reply.ok) {
      state = state.copyWith(
          failure: 'the engine refused the note: ${reply.error}');
      return null;
    }
    final stored = reply.fields;
    final craft = state.craft;
    if (craft != null) {
      _recentCrafts.insert(0, craft);
      if (_recentCrafts.length > 10) _recentCrafts.removeRange(10, _recentCrafts.length);
    }
    state = const RegionComposerState();
    await askAgent(stored['id'] as String?);
    return stored;
  }

  /// TICK the note-triggered agent. Deliberately NOT "grade this".
  ///
  /// The app tells the engine only that something changed. WHICH notes to act
  /// on, what each one means, and whether to act at all are the agent's
  /// decisions, taken from the persisted ledger — `agent_act` takes no entry,
  /// no look and no region, so there is no way for the app to command a
  /// particular grade. That is the line between "the agent did the work" and
  /// "we moved the button".
  ///
  /// Asked on EVERY composer entry, not only colour ones: a mechanical ask
  /// typed on the player ("trim 12 frames off the head") proposes exactly like
  /// a producer comment would. Gating this on a resolved look is what made
  /// every non-colour ask silently stay a note — the "Creative — your call"
  /// dead end. An unparseable note still just stays a note; the engine answers
  /// with no decisions and nothing is invented.
  Future<void> askAgent(String? entryId) async {
    state = state.copyWith(
        isAsking: true, clearGraded: true, clearDeclined: true);
    ChangelistCommandResult reply;
    try {
      reply = await backend
          .changelistCommand({'op': 'agent_act', 'board_id': boardId});
    } catch (e) {
      state = state.copyWith(
          isAsking: false, failure: 'the engine did not answer the grade');
      return;
    }
    if (!reply.ok) {
      state = state.copyWith(isAsking: false, failure: reply.error);
      return;
    }
    final acted = [
      for (final row in (reply.fields['acted'] as List? ?? const []))
        if (row is Map<String, dynamic>) row,
    ];
    // Prefer THIS note's outcome; fall back to the newest decision the pass
    // produced, because the agent legitimately acts on notes this app did not
    // draw (a peer's synced note, a connector's).
    Map<String, dynamic>? outcome;
    for (final row in acted) {
      if (row['entry_id'] == entryId) outcome = row;
    }
    if (outcome == null) {
      for (final row in acted) {
        if (row['output_path'] is String) outcome = row;
      }
    }
    final declined = outcome?['declined'] as String?;
    if (declined != null) {
      // The agent DECIDED not to act, and said why. A real answer.
      state = state.copyWith(isAsking: false, declined: declined);
      return;
    }
    final path = outcome?['output_path'] as String?;
    if (path == null || path.isEmpty) {
      state = state.copyWith(isAsking: false);
      return;
    }
    state = state.copyWith(isAsking: false, gradedPath: path);
  }

  /// Absent when no chip was tapped — `intent_struct` omitted entirely means
  /// "general", which is the normative meaning of a skip.
  IntentStruct? _intentStruct() {
    final craft = state.craft;
    if (craft == null) return null;
    final structured = <String, dynamic>{
      if (state.subject != null) 'subject': state.subject,
      if (state.defect != null) 'defect': state.defect,
    };
    return IntentStruct(
      craft: craft.wireName,
      structured: structured.isEmpty ? null : structured,
    );
  }
}
