// providers/notes_ledger_provider.dart
//
// The board's authored NOTES LEDGER, ported from `NotesLedgerViewModel`
// (ViewModels/NotesLedgerViewModel.swift). Decoupled from the notebook /
// Workflow model exactly as the macOS app decouples it: its own store, its own
// verbs — writing a note must NOT create a workflow step.
//
// Every read and write goes through the `CyanBackend` seam (`noteList` /
// `notePut` / `noteDelete`), so the whole ledger is Tier-1 drivable against
// FakeCyanBackend with no dylib.
//
// Two invariants carried over verbatim from the Swift view-model:
//
//   • LWW on `updated_at` — an edit whose clock is BEHIND the note's current
//     `updated_at` loses and is never sent. The same rule the engine's
//     anti-entropy digest converges chat and files under.
//   • The engine is the truth — every write is followed by a re-read of the
//     ledger, so what the face renders is what was persisted rather than a
//     shadow copy of the draft that was typed.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/cyan_backend.dart';
import '../ffi/parity_models.dart';
import 'cyan_backend_provider.dart';

/// The kinds the ledger files under "House rules" — the board's STANDING rules,
/// kept apart from one-off decisions and scratch notes.
const Set<String> kHouseRuleKinds = {
  'constitution',
  'preference',
  'creative-dna',
};

/// The chip text for a note's kind. An unknown kind still renders (as a plain
/// note) — a kind this build does not know is never dropped.
String noteKindLabel(String kind) => switch (kind) {
      'decision' => 'decision',
      'constitution' => 'constitution',
      'preference' => 'preference',
      'creative-dna' => 'creative DNA',
      _ => 'note',
    };

/// The byline for a ledger row. Standing rule from the macOS app
/// (`LedgerAuthorLabel`): a raw node id / hash is NEVER shown to a user. We
/// render the resolved name, fall back to the craft role, then to a human word
/// — but never to hex.
String? noteByline(CyanNote note, {String myNodeId = ''}) {
  final role = (note.authorRole ?? '').trim().replaceAll('_', ' ');
  final name = _authorName(note, myNodeId);
  if (name != null && role.isNotEmpty) return '$name · $role';
  if (name != null) return name;
  if (role.isNotEmpty) return role;
  return note.authorId.isEmpty ? null : 'a teammate';
}

String? _authorName(CyanNote note, String myNodeId) {
  if (myNodeId.isNotEmpty && note.authorId == myNodeId) return 'You';
  final n = note.authorName.trim();
  // A display name that IS the node id is the engine saying "no name known" —
  // it is an id, so it must not reach the screen.
  if (n.isEmpty || n == note.authorId) return null;
  return n;
}

/// A note's edit time as `yyyy-MM-dd HH:mm` in the operator's own timezone.
/// Zero (an engine that recorded no stamp) has no label rather than a fake
/// 1970 one.
String? noteStampLabel(int epochSeconds) {
  if (epochSeconds <= 0) return null;
  final t = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

@immutable
class NotesLedgerState {
  final bool loading;

  /// The ledger could not be read — the panel says so instead of showing an
  /// empty list that reads like "this board has no notes".
  final String? error;

  /// The board's notes, newest EDIT first (the `updated_at` order the macOS
  /// ledger keeps).
  final List<CyanNote> notes;

  /// This device's node id, so a note this operator wrote reads "You".
  final String myNodeId;

  const NotesLedgerState({
    this.loading = true,
    this.error,
    this.notes = const [],
    this.myNodeId = '',
  });

  NotesLedgerState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    List<CyanNote>? notes,
    String? myNodeId,
  }) {
    return NotesLedgerState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      notes: notes ?? this.notes,
      myNodeId: myNodeId ?? this.myNodeId,
    );
  }

  bool get isEmpty => notes.isEmpty;

  /// Board decisions — what the board DECIDED, kept at the top of the ledger.
  List<CyanNote> get decisions =>
      [for (final n in notes) if (n.kind == 'decision') n];

  /// Constitution / preference / creative-dna — the standing house rules.
  List<CyanNote> get houseRules =>
      [for (final n in notes) if (kHouseRuleKinds.contains(n.kind)) n];

  /// Everything else: editor notes, plus any kind this build does not know.
  List<CyanNote> get editorNotes => [
        for (final n in notes)
          if (n.kind != 'decision' && !kHouseRuleKinds.contains(n.kind)) n,
      ];

  CyanNote? byId(String id) {
    for (final n in notes) {
      if (n.id == id) return n;
    }
    return null;
  }
}

/// The ledger for one board. Keyed by board id because a note is anchored on
/// its board — another board's ledger is a different store.
final notesLedgerProvider = StateNotifierProvider.autoDispose
    .family<NotesLedgerController, NotesLedgerState, String>((ref, boardId) {
  final controller = NotesLedgerController(
    backend: ref.watch(cyanBackendProvider),
    boardId: boardId,
  );
  controller.load();
  return controller;
});

class NotesLedgerController extends StateNotifier<NotesLedgerState> {
  final CyanBackend _backend;
  final String boardId;

  NotesLedgerController({
    required CyanBackend backend,
    required this.boardId,
  })  : _backend = backend,
        super(const NotesLedgerState());

  /// Read the board's ledger off the engine and sort it newest-edit first.
  /// This is also the RELOAD: it is what a freshly-mounted face runs, so a note
  /// only survives it because the engine kept it, never because this object
  /// remembered it.
  Future<void> load() async {
    try {
      final notes = await _backend.noteList(boardId);
      final me = await _backend.myProfile();
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        clearError: true,
        notes: _newestEditFirst(notes),
        myNodeId: me?.nodeId ?? '',
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        error: "Could not read this board's ledger: $e",
      );
    }
  }

  /// Record a new note. Blank text is not a note; the engine stamps the author
  /// and both timestamps, which is why the ledger is re-read rather than
  /// guessed at here.
  Future<bool> addNote(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    try {
      await _backend.notePut(boardId, trimmed);
    } catch (e) {
      if (mounted) state = state.copyWith(error: 'Failed to add note: $e');
      return false;
    }
    await load();
    return true;
  }

  /// Edit a note's text. LAST WRITE WINS on `updated_at`: the edit only lands
  /// when its clock is at least the note's current edit time — a write that is
  /// behind the note it is editing is stale, loses, and is never sent to the
  /// engine. [now] is unix seconds; it is a parameter so the rule can be driven
  /// without waiting on a wall clock.
  Future<bool> editNote(String id, String text, {int? now}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final existing = state.byId(id);
    if (existing == null) return false;

    final stamp = now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (stamp < existing.updatedAt) return false; // stale write loses

    try {
      await _backend.notePut(boardId, trimmed, noteId: id);
    } catch (e) {
      if (mounted) state = state.copyWith(error: 'Failed to edit note: $e');
      return false;
    }
    await load();
    return true;
  }

  /// The board's ledger rendered as markdown — the ENGINE's own rendering
  /// (`cyan_export_notes_markdown`), so a copy taken here reads identically to
  /// one taken from the shipping Mac app. Null when the engine rendered nothing
  /// to copy; the caller then puts nothing on the clipboard rather than
  /// clearing it.
  Future<String?> markdownExport() async {
    try {
      final markdown = await _backend.exportNotesMarkdown(boardId);
      if (markdown == null || markdown.isEmpty) return null;
      return markdown;
    } catch (e) {
      if (mounted) state = state.copyWith(error: 'Could not export notes: $e');
      return null;
    }
  }

  /// Remove a note from the ledger.
  Future<bool> deleteNote(String id) async {
    try {
      await _backend.noteDelete(id);
    } catch (e) {
      if (mounted) state = state.copyWith(error: 'Failed to delete note: $e');
      return false;
    }
    await load();
    return true;
  }

  static List<CyanNote> _newestEditFirst(List<CyanNote> notes) =>
      [...notes]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}
