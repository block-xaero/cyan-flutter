// providers/notes_editor_controller.dart
//
// PARITY face_notes · LAYER 2 (the portable view-model).
//
// SwiftUI reference (READ-ONLY):
//   Views/NotesEditorView.swift — `NotesFileType.detect`, `NotesEditorViewModel`
//        (load / save / contentDidChange with the 2s autosave, the live stats),
//        and the A2 read-only REVIEW RAIL of sensed reviewer comments
//
// The Notes face's document half. Everything flows through the one
// `CyanBackend` seam; the controller owns the buffer, the dirty flag, the
// detected type, the live stats and the autosave, and NOTHING else.
//
// THE SAVE TELLS THE TRUTH. `saveNotes` answers with a read-back, not an
// acknowledgement, because on this engine baseline they differ: the engine takes
// the write, re-kinds it to `step`, and the editor can then never read it back.
// The controller republishes that verdict verbatim rather than flattening it
// into a green dot.

import 'dart:async';
import 'dart:convert';

import '../ffi/cyan_backend.dart';
import '../ffi/parity_models.dart';

/// How long an idle buffer waits before it autosaves — the reference's 2s.
const Duration kNotesAutosaveDelay = Duration(seconds: 2);

/// The languages the editor detects and labels. Order matters only for display;
/// [detectNotesFileType] decides membership.
enum NotesFileType {
  markdown,
  json,
  yaml,
  swift,
  rust,
  python,
  javascript,
  typescript,
  sql,
  plaintext,
}

extension NotesFileTypeX on NotesFileType {
  String get displayName => switch (this) {
        NotesFileType.markdown => 'Markdown',
        NotesFileType.json => 'JSON',
        NotesFileType.yaml => 'YAML',
        NotesFileType.swift => 'Swift',
        NotesFileType.rust => 'Rust',
        NotesFileType.python => 'Python',
        NotesFileType.javascript => 'JavaScript',
        NotesFileType.typescript => 'TypeScript',
        NotesFileType.sql => 'SQL',
        NotesFileType.plaintext => 'Plain Text',
      };
}

/// The reference's `NotesFileType.detect`, in its exact order: JSON first (and
/// only when it actually PARSES — a `{` is not a document), then YAML by its
/// marker keys, then markdown by its syntax, then the code languages, then
/// plain text.
NotesFileType detectNotesFileType(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return NotesFileType.plaintext;

  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      jsonDecode(trimmed);
      return NotesFileType.json;
    } catch (_) {
      // Not JSON after all — fall through rather than label it by its bracket.
    }
  }

  if (trimmed.contains(':\n') || trimmed.startsWith('---')) {
    const yamlKeys = [
      'apiVersion:',
      'kind:',
      'metadata:',
      'spec:',
      'name:',
      'version:',
    ];
    if (yamlKeys.any(trimmed.contains)) return NotesFileType.yaml;
  }

  const markdown = [
    '# ',
    '## ',
    '### ',
    '```',
    '- [ ]',
    '- [x]',
    '[](',
    '**',
    '__',
  ];
  if (markdown.any(trimmed.contains)) return NotesFileType.markdown;

  if (trimmed.contains('import SwiftUI') ||
      trimmed.contains('struct ') && trimmed.contains('var body')) {
    return NotesFileType.swift;
  }
  if (trimmed.contains('fn ') && trimmed.contains('let mut ') ||
      trimmed.contains('pub fn ')) {
    return NotesFileType.rust;
  }
  if (trimmed.contains('def ') && trimmed.contains(':')) {
    return NotesFileType.python;
  }
  if (trimmed.contains('interface ') || trimmed.contains(': string')) {
    return NotesFileType.typescript;
  }
  if (trimmed.contains('function ') || trimmed.contains('const ')) {
    return NotesFileType.javascript;
  }
  final upper = trimmed.toUpperCase();
  if (upper.contains('SELECT ') && upper.contains(' FROM ')) {
    return NotesFileType.sql;
  }
  return NotesFileType.plaintext;
}

/// One sensed reviewer note — a timecoded note whose kind is `review_comment`,
/// rendered read-only above the editor so the Notes face shows the review
/// conversation instead of "Nothing here".
class ReviewNoteRow {
  final String id;
  final double seconds;
  final String author;
  final String text;

  const ReviewNoteRow({
    required this.id,
    this.seconds = 0,
    this.author = 'reviewer',
    this.text = '',
  });

  String get timecodeLabel {
    final total = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class NotesEditorState {
  final bool hydrated;
  final bool saving;

  /// Bumped ONLY by a load. The view re-seeds its text field on a change here
  /// and never on any other publish — a caret move or a save verdict must not
  /// reach in and rewrite the buffer the operator is typing into.
  final int revision;

  final String fileName;
  final String content;
  final bool dirty;
  final NotesFileType detectedType;

  /// The caret, 1-based, as the status bar reports it.
  final int line;
  final int column;

  final List<ReviewNoteRow> reviewNotes;

  /// The last save's verdict. Null before the first save of this session.
  final NotesSaveResult? lastSave;

  final String? lastError;

  const NotesEditorState({
    this.hydrated = false,
    this.saving = false,
    this.revision = 0,
    this.fileName = 'notes.md',
    this.content = '',
    this.dirty = false,
    this.detectedType = NotesFileType.plaintext,
    this.line = 1,
    this.column = 1,
    this.reviewNotes = const [],
    this.lastSave,
    this.lastError,
  });

  NotesEditorState copyWith({
    bool? hydrated,
    bool? saving,
    int? revision,
    String? fileName,
    String? content,
    bool? dirty,
    NotesFileType? detectedType,
    int? line,
    int? column,
    List<ReviewNoteRow>? reviewNotes,
    NotesSaveResult? lastSave,
    String? lastError,
    bool clearError = false,
  }) =>
      NotesEditorState(
        hydrated: hydrated ?? this.hydrated,
        saving: saving ?? this.saving,
        revision: revision ?? this.revision,
        fileName: fileName ?? this.fileName,
        content: content ?? this.content,
        dirty: dirty ?? this.dirty,
        detectedType: detectedType ?? this.detectedType,
        line: line ?? this.line,
        column: column ?? this.column,
        reviewNotes: reviewNotes ?? this.reviewNotes,
        lastSave: lastSave ?? this.lastSave,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );

  List<String> get lines => content.split('\n');
  int get lineCount => lines.length;
  int get wordCount =>
      content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  /// What the toolbar's save indicator says. Three states, not two: a document
  /// the engine took but cannot read back is NOT saved, and must not show the
  /// same dot as one that is.
  String get saveLabel {
    if (saving) return 'Saving…';
    if (dirty) return 'Unsaved';
    final last = lastSave;
    if (last != null && !last.durable) return 'Not saved';
    return 'Saved';
  }

  /// The reason behind a "Not saved", for the operator. Null otherwise.
  String? get saveProblem => dirty ? null : lastSave?.reason;
}

/// The Notes editor's controller.
class NotesEditorController {
  NotesEditorController({required this.backend, required this.boardId});

  final CyanBackend backend;
  final String boardId;

  NotesEditorState _state = const NotesEditorState();
  NotesEditorState get state => _state;

  Timer? _autosave;
  String _original = '';

  final List<void Function(NotesEditorState)> _listeners = [];

  void Function() addListener(void Function(NotesEditorState) fn) {
    _listeners.add(fn);
    return () => _listeners.remove(fn);
  }

  void dispose() {
    _autosave?.cancel();
    _autosave = null;
    _listeners.clear();
  }

  void _publish(NotesEditorState next) {
    _state = next;
    for (final fn in List.of(_listeners)) {
      fn(next);
    }
  }

  // ---- read ----------------------------------------------------------------

  Future<void> load() async {
    BoardNotes? notes;
    var review = const <ReviewNoteRow>[];
    String? error;
    try {
      notes = await backend.loadNotes(boardId);
    } catch (e) {
      error = _describe(e);
    }
    try {
      // A2: the review rail is the board's timecoded notes filtered to the ones
      // a REVIEWER left. Read leniently — drift on another note kind must never
      // blank this rail.
      final rows = await backend.loadTimecodeNotes(boardId);
      review = [
        for (final n in rows)
          if (n.noteType == 'review_comment')
            ReviewNoteRow(
              id: n.id,
              seconds: n.timecodeSeconds,
              author: n.author.isEmpty ? 'reviewer' : n.author,
              text: n.content,
            ),
      ]..sort((a, b) => a.seconds.compareTo(b.seconds));
    } catch (_) {
      // The rail is additive to the document — a rail that cannot be read must
      // not take the editor down with it.
    }
    final content = notes?.content ?? _state.content;
    _original = content;
    _publish(_state.copyWith(
      hydrated: true,
      revision: _state.revision + 1,
      fileName: notes?.fileName ?? _state.fileName,
      content: content,
      dirty: false,
      detectedType: detectNotesFileType(content),
      reviewNotes: review,
      lastError: error,
      clearError: error == null,
    ));
  }

  // ---- edit ----------------------------------------------------------------

  /// The buffer changed. Re-detects the type, re-derives the stats, and arms the
  /// autosave — the reference's `contentDidChange`.
  void contentDidChange(String next) {
    _publish(_state.copyWith(
      content: next,
      dirty: next != _original,
      detectedType: detectNotesFileType(next),
    ));
    _autosave?.cancel();
    if (next == _original) return;
    _autosave = Timer(kNotesAutosaveDelay, save);
  }

  /// Report the caret. Offsets are into the WHOLE buffer, as a text field
  /// reports them; the line and column are derived here so the status bar and
  /// the buffer can never disagree.
  void cursorMovedTo(int offset) {
    final clamped =
        offset < 0 ? 0 : (offset > _state.content.length ? _state.content.length : offset);
    final before = _state.content.substring(0, clamped);
    final lastBreak = before.lastIndexOf('\n');
    _publish(_state.copyWith(
      line: '\n'.allMatches(before).length + 1,
      column: clamped - lastBreak,
    ));
  }

  // ---- save ----------------------------------------------------------------

  /// Persist the document. A clean buffer is a no-op, exactly as the reference
  /// guards on `hasUnsavedChanges`.
  Future<void> save() async {
    _autosave?.cancel();
    _autosave = null;
    if (!_state.dirty) return;

    final content = _state.content;
    _publish(_state.copyWith(saving: true, clearError: true));
    NotesSaveResult result;
    try {
      result = await backend.saveNotes(boardId, content);
    } catch (e) {
      _publish(_state.copyWith(
          saving: false,
          lastSave: NotesSaveResult(error: _describe(e)),
          lastError: _describe(e)));
      return;
    }
    // The buffer stops being dirty because the write was ATTEMPTED and the
    // verdict is now on screen — but `_original` only moves when the document
    // is genuinely durable, so a later re-save still has something to send.
    if (result.durable) _original = content;
    _publish(_state.copyWith(
        saving: false, dirty: false, lastSave: result));
  }

  static String _describe(Object e) {
    final text = e.toString().trim();
    for (final p in const ['Exception: ', 'Bad state: ', 'StateError: ']) {
      if (text.startsWith(p)) return text.substring(p.length);
    }
    return text;
  }
}
