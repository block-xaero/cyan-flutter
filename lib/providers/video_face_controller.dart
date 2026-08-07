// providers/video_face_controller.dart
//
// PARITY face_video · LAYER 2 (the portable view-model).
//
// SwiftUI reference (READ-ONLY):
//   Views/VideoPlayerFace.swift — the player area, the timecoded-note timeline,
//        the AI/human segmented notes panel, threads, "act on this", approve /
//        dismiss / add-to-pipeline, and the markdown export
//
// The VIDEO face is the review player's plainer sibling: the SAME asset, read
// through the SAME seam, but pinned by SECONDS rather than frames, and its unit
// is the TIMECODED NOTE (`cyan_load_timecode_notes` / `cyan_save_timecode_note`
// / `cyan_act_on_timecode_note` / `cyan_export_notes_markdown`) rather than the
// change list. Every read and every write goes through the one `CyanBackend`
// seam; the controller never touches a decoder — the view hands it the surface's
// position in seconds.
//
// TWO HONEST LIMITS, carried from the engine and NOT papered over:
//
//   1. there is no timecode-note DELETE verb in the engine's export table, so
//      `dismiss` is SESSION-LOCAL and says so — the note returns on the next
//      read. The reference has exactly this behaviour (`dismissNote` mutates
//      the in-memory list and nothing else); naming it is the difference
//      between a port and a lie.
//   2. "Add to pipeline" files an authored STEP. The reference writes a
//      `markdown` cell with pipeline metadata, but this engine runs every
//      authored kind through `workflow::coerce_authoring_cell_type` and `step`
//      is the only authorable one — so a markdown write lands as a step
//      anyway. Filing it as a step is the same destination, honestly named.

import 'dart:convert';

import '../ffi/cyan_backend.dart';
import '../ffi/parity_models.dart';

/// A machine step-result note (raw tool output pinned at 0.0s) belongs to the
/// Dashboard's findings, not to the player overlay — the reference filters it
/// out of the face on load and so does this.
const String kPluginResultNoteType = 'plugin_result';

/// The note types the composer can raise, in the order the reference's menu
/// offers them.
const List<String> kComposableNoteTypes = [
  'comment',
  'qc_issue',
  'revision',
  'approved',
];

/// Everything the video face renders. A plain value: every state the engine can
/// put the face in is a state, never a special code path.
class VideoFaceState {
  /// True once a read attempt has completed. A spinner is only honest before it.
  final bool hydrated;

  /// The board's media, as the engine resolved it. Null before the first read.
  final BoardVideoMedia? media;

  /// Every timecoded note on the board, engine-ordered by timecode, with the
  /// machine step-results filtered out.
  final List<TimecodeNote> notes;

  /// The note the human has focused (a row tap or a marker tap).
  final String? selectedNoteId;

  /// The note whose AI call is in flight — the row draws a spinner in place of
  /// its "act on this" bolt.
  final String? actingNoteId;

  /// The note being replied to; null when the composer writes a root note.
  final String? replyingToId;

  /// Notes dismissed in THIS session. The engine has no delete verb for a
  /// timecoded note, so a dismissal cannot outlive the process — it is tracked
  /// here so the face can say so rather than imply a delete that never happened.
  final Set<String> dismissed;

  /// The last pipeline step id "Add to pipeline" filed, for the confirmation
  /// chip. Null once acknowledged.
  final String? addedToPipeline;

  /// The last export's receipt: how many notes went to the notes ledger. Null
  /// until an export lands.
  final String? exportStatus;

  final String? lastError;

  const VideoFaceState({
    this.hydrated = false,
    this.media,
    this.notes = const [],
    this.selectedNoteId,
    this.actingNoteId,
    this.replyingToId,
    this.dismissed = const {},
    this.addedToPipeline,
    this.exportStatus,
    this.lastError,
  });

  VideoFaceState copyWith({
    bool? hydrated,
    BoardVideoMedia? media,
    List<TimecodeNote>? notes,
    String? selectedNoteId,
    bool clearSelected = false,
    String? actingNoteId,
    bool clearActing = false,
    String? replyingToId,
    bool clearReplying = false,
    Set<String>? dismissed,
    String? addedToPipeline,
    bool clearAdded = false,
    String? exportStatus,
    String? lastError,
    bool clearError = false,
  }) =>
      VideoFaceState(
        hydrated: hydrated ?? this.hydrated,
        media: media ?? this.media,
        notes: notes ?? this.notes,
        selectedNoteId:
            clearSelected ? null : (selectedNoteId ?? this.selectedNoteId),
        actingNoteId: clearActing ? null : (actingNoteId ?? this.actingNoteId),
        replyingToId:
            clearReplying ? null : (replyingToId ?? this.replyingToId),
        dismissed: dismissed ?? this.dismissed,
        addedToPipeline:
            clearAdded ? null : (addedToPipeline ?? this.addedToPipeline),
        exportStatus: exportStatus ?? this.exportStatus,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );

  /// What the face actually shows: the engine's notes minus this session's
  /// dismissals.
  List<TimecodeNote> get visible =>
      [for (final n in notes) if (!dismissed.contains(n.id)) n];

  /// The root notes, in timecode order — the panel's two sections are cut from
  /// these, and the timeline's markers are drawn from them.
  List<TimecodeNote> get roots {
    final rows = [for (final n in visible) if (n.replyTo == null) n];
    rows.sort((a, b) => a.timecodeSeconds.compareTo(b.timecodeSeconds));
    return rows;
  }

  /// The reference's split, verbatim: a note the AI has reviewed OR one authored
  /// under an `AI/` name is a FINDING; everything else is a review comment.
  static bool isAiNote(TimecodeNote n) =>
      n.aiReviewed || n.author.startsWith('AI/');

  List<TimecodeNote> get aiFindings => [for (final n in roots) if (isAiNote(n)) n];

  List<TimecodeNote> get humanComments =>
      [for (final n in roots) if (!isAiNote(n)) n];

  /// The replies under [noteId], oldest first — the thread the reference draws
  /// with a connector.
  List<TimecodeNote> repliesTo(String noteId) {
    final rows = [for (final n in visible) if (n.replyTo == noteId) n];
    rows.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return rows;
  }

  TimecodeNote? get selectedNote {
    for (final n in visible) {
      if (n.id == selectedNoteId) return n;
    }
    return null;
  }

  /// The note under the playhead is whichever ROOT note the playhead has most
  /// recently passed — the reference's "active note" overlay.
  TimecodeNote? activeNoteAt(double seconds) {
    TimecodeNote? hit;
    for (final n in roots) {
      if (n.timecodeSeconds <= seconds) {
        hit = n;
      } else {
        break;
      }
    }
    return hit;
  }

  /// The ad-break revenue strip only exists when the board HAS ad breaks — the
  /// reference computes $3,800 per break per 1M views.
  int get adBreakCount =>
      [for (final n in roots) if (n.noteType == 'ad_break') n].length;

  int get adBreakRevenue => adBreakCount * 3800;
}

/// The video face's controller. Owns the media read, the note rail and the four
/// writes the face offers — nothing else.
class VideoFaceController {
  VideoFaceController({
    required this.backend,
    required this.boardId,
    this.author = 'you',
    this.pipelineStepId,
  });

  final CyanBackend backend;
  final String boardId;

  /// Who a note authored here is signed as.
  final String author;

  /// Set when the face was opened FROM a pipeline step — every note raised here
  /// then carries that step and the `review` phase, exactly as the reference
  /// stamps them.
  final String? pipelineStepId;

  VideoFaceState _state = const VideoFaceState();
  VideoFaceState get state => _state;

  final List<void Function(VideoFaceState)> _listeners = [];

  /// Subscribe; the returned callback unsubscribes.
  void Function() addListener(void Function(VideoFaceState) fn) {
    _listeners.add(fn);
    return () => _listeners.remove(fn);
  }

  void _publish(VideoFaceState next) {
    _state = next;
    for (final fn in List.of(_listeners)) {
      fn(next);
    }
  }

  // ---- read ----------------------------------------------------------------

  /// The board's media and its note rail. Either failing leaves the face
  /// hydrated with what it could read — a face that cannot show the picture
  /// still shows the notes.
  Future<void> load() async {
    BoardVideoMedia? media;
    var notes = _state.notes;
    String? error;
    try {
      media = await backend.boardVideoMedia(boardId);
      if (media.error != null) error = media.error;
    } catch (e) {
      error = _describe(e);
    }
    try {
      final rows = await backend.loadTimecodeNotes(boardId);
      notes = [
        for (final n in rows)
          if (n.noteType != kPluginResultNoteType) n,
      ];
    } catch (e) {
      error ??= _describe(e);
    }
    _publish(_state.copyWith(
      hydrated: true,
      media: media,
      notes: notes,
      lastError: error,
      clearError: error == null,
    ));
  }

  // ---- focus ---------------------------------------------------------------

  void select(String? noteId) => _publish(_state.copyWith(
      selectedNoteId: noteId, clearSelected: noteId == null));

  void replyTo(String? noteId) => _publish(_state.copyWith(
      replyingToId: noteId, clearReplying: noteId == null));

  void acknowledgePipelineChip() =>
      _publish(_state.copyWith(clearAdded: true));

  // ---- writes --------------------------------------------------------------

  /// Raise a note at [atSeconds]. A reply inherits its PARENT's timecode — the
  /// reply belongs to the moment the parent pinned, not to wherever the
  /// playhead drifted while it was being typed.
  ///
  /// Returns the note as it was filed, or null when nothing was: blank text is
  /// refused here rather than persisted, and a write the engine rejects answers
  /// null too.
  Future<TimecodeNote?> addNote({
    required String content,
    required double atSeconds,
    String noteType = 'comment',
  }) async {
    final text = content.trim();
    if (text.isEmpty) return null;

    final parentId = _state.replyingToId;
    var timecode = atSeconds;
    if (parentId != null) {
      for (final n in _state.notes) {
        if (n.id == parentId) {
          timecode = n.timecodeSeconds;
          break;
        }
      }
    }

    final note = TimecodeNote(
      id: _mintId(text, timecode),
      boardId: boardId,
      timecodeSeconds: timecode,
      content: text,
      noteType: noteType,
      author: author,
      createdAt: DateTime.now().millisecondsSinceEpoch / 1000,
      replyTo: parentId,
      pipelineStepId: pipelineStepId,
      pipelinePhase: pipelineStepId == null ? null : 'review',
    );

    bool saved;
    try {
      saved = await backend.saveTimecodeNote(note);
    } catch (e) {
      _publish(_state.copyWith(lastError: _describe(e)));
      return null;
    }
    if (!saved) {
      _publish(_state.copyWith(
          lastError: 'the engine refused the note at '
              '${timecode.toStringAsFixed(1)}s'));
      return null;
    }
    _publish(_state.copyWith(clearReplying: true));
    await load();
    return note;
  }

  /// Send a note to the engine's AI rail. The engine builds the prompt from the
  /// note's pipeline context and RE-SAVES the note with the answer attached, so
  /// this re-reads the rail rather than patching its own copy.
  Future<void> actOnNote(TimecodeNote note) async {
    _publish(_state.copyWith(actingNoteId: note.id, clearError: true));
    TimecodeNoteAction result;
    try {
      result = await backend.actOnTimecodeNote(note);
    } catch (e) {
      _publish(_state.copyWith(clearActing: true, lastError: _describe(e)));
      return;
    }
    if (!result.success) {
      _publish(_state.copyWith(
          clearActing: true,
          lastError: result.error ?? 'the AI rail answered nothing'));
      return;
    }
    _publish(_state.copyWith(clearActing: true));
    await load();
  }

  /// Mark a finding as accepted by a human. It is the SAME note re-saved — the
  /// engine's save is an upsert on the id.
  Future<void> approve(TimecodeNote note) async {
    final approved = _withApproval(note);
    try {
      if (!await backend.saveTimecodeNote(approved)) {
        _publish(_state.copyWith(
            lastError: 'the engine refused the approval of ${note.id}'));
        return;
      }
    } catch (e) {
      _publish(_state.copyWith(lastError: _describe(e)));
      return;
    }
    await load();
  }

  /// Take a finding off THIS session's face. The engine exports no delete verb
  /// for a timecoded note, so this cannot be a delete and does not claim to be
  /// one — the note is still in the store and the next read brings it back.
  void dismiss(TimecodeNote note) {
    _publish(_state.copyWith(
      dismissed: {..._state.dismissed, note.id},
      clearSelected: _state.selectedNoteId == note.id,
    ));
  }

  /// File the AI's recommended action as an authored workflow step, then accept
  /// the finding it came from — the reference's "Add to Pipeline" in one move.
  ///
  /// The reference writes a `markdown` cell carrying pipeline metadata; this
  /// engine coerces every authored kind to `step`, so the step IS where that
  /// write lands. Filing it as a step is the same destination without the
  /// detour.
  Future<void> addToPipeline(TimecodeNote note, String action) async {
    final text = 'AI-suggested: ${action.trim()}';
    final stepId = 'ai_fix_${note.timecodeSeconds.toInt()}';
    try {
      final step = await backend.addWorkflowStep(boardId, text);
      if (step == null) {
        _publish(_state.copyWith(
            lastError: 'the engine refused the step for ${note.id}'));
        return;
      }
    } catch (e) {
      _publish(_state.copyWith(lastError: _describe(e)));
      return;
    }
    _publish(_state.copyWith(addedToPipeline: stepId));
    await approve(note);
  }

  /// Render the whole rail as the ENGINE's own markdown timeline and file it on
  /// the board's notes LEDGER (`cyan_note_put`).
  ///
  /// The reference appends a markdown notebook cell; PHASE-2 D2 moved the notes
  /// surface to the uncoerced `cyan_note_*` ledger, which is where an exported
  /// document can actually be read back from — a markdown cell would be stored
  /// as a workflow step and vanish from every notes reader.
  Future<void> exportToNotes() async {
    String? markdown;
    try {
      markdown = await backend.exportNotesMarkdown(boardId);
    } catch (e) {
      _publish(_state.copyWith(
          exportStatus: 'export failed', lastError: _describe(e)));
      return;
    }
    if (markdown == null || markdown.isEmpty) {
      _publish(_state.copyWith(
          exportStatus: 'export: the engine rendered nothing to export'));
      return;
    }
    try {
      await backend.notePut(boardId, markdown);
    } catch (e) {
      _publish(_state.copyWith(
          exportStatus: 'export failed', lastError: _describe(e)));
      return;
    }
    _publish(_state.copyWith(
        exportStatus: 'exported ${_state.roots.length} notes to Notes'));
  }

  // ---- helpers -------------------------------------------------------------

  TimecodeNote _withApproval(TimecodeNote n) => TimecodeNote(
        id: n.id,
        boardId: n.boardId,
        timecodeSeconds: n.timecodeSeconds,
        content: n.content,
        noteType: n.noteType,
        author: n.author,
        createdAt: n.createdAt,
        replyTo: n.replyTo,
        threadCount: n.threadCount,
        pipelineStepId: n.pipelineStepId,
        pipelinePhase: n.pipelinePhase,
        aiReviewed: n.aiReviewed,
        humanApproved: true,
        actionSkill: n.actionSkill,
        actionStatus: n.actionStatus,
        actionResult: n.actionResult,
        actionModel: n.actionModel,
        aiFlagsNearby: n.aiFlagsNearby,
      );

  /// A stable-enough client id. The engine's save is an upsert keyed on it, so
  /// the only thing it must not be is empty or a repeat of a live note.
  String _mintId(String text, double at) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    var hash = 0x811c9dc5;
    for (final unit in '$text|$at|$stamp'.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return 'tc-${hash.toRadixString(16).padLeft(8, '0')}';
  }

  static String _describe(Object e) {
    final text = e.toString().trim();
    for (final p in const ['Exception: ', 'Bad state: ', 'StateError: ']) {
      if (text.startsWith(p)) return text.substring(p.length);
    }
    return text;
  }
}

/// The AI's answer, parsed for display. The engine asks the model for JSON but
/// never guarantees it, so this is TOLERANT in the reference's exact order:
/// whole-string JSON, then the first `{`…`}` inside it, then nothing.
Map<String, String> parseAiResponse(String raw) {
  Map<String, String>? flatten(Object? decoded) {
    if (decoded is! Map) return null;
    final out = <String, String>{};
    decoded.forEach((k, v) {
      if (v == null) return;
      out['$k'] = v is String ? v : v.toString();
    });
    return out;
  }

  final direct = flatten(_tryDecode(raw));
  if (direct != null) return direct;
  final open = raw.indexOf('{');
  final close = raw.lastIndexOf('}');
  if (open < 0 || close <= open) return const {};
  return flatten(_tryDecode(raw.substring(open, close + 1))) ?? const {};
}

Object? _tryDecode(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

/// The unparseable answer, shown rather than swallowed: the model said
/// something and the reviewer is entitled to read it.
String cleanRawResponse(String raw) {
  final text = raw
      .replaceAll('{', '')
      .replaceAll('}', '')
      .replaceAll('"', '')
      .replaceAll('\\n', ' ')
      .trim();
  return text.length <= 200 ? text : text.substring(0, 200);
}

/// `H:MM:SS` for an hour-plus asset, `MM:SS` below it — the reference's
/// `formatTimecode`.
String formatTimecode(double seconds) {
  final total = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}
