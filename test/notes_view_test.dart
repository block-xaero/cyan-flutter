// test/notes_view_test.dart
//
// PARITY face `notes` — the board's notes DOCUMENT (Swift: NotesEditorView +
// NotesEditorViewModel, on today's cyan-iOS main). Tier-1: driven through the
// `CyanBackend` seam (FakeCyanBackend), no dylib.
//
// The behaviours the reference publishes:
//   • the document opens in an EDITABLE buffer with its name and its stats
//   • the file type is DETECTED from the content, not from the name
//   • typing marks the buffer unsaved, and an idle buffer autosaves after 2s
//   • the caret is reported live in the status bar
//   • a save the engine cannot read back is NOT reported as saved
//   • the A2 reviewer rail shows the board's sensed review comments
//   • the ledger is the face's right column

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/cyan_backend.dart';
import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/providers/notes_editor_controller.dart';
import 'package:cyan_flutter/widgets/parity/parity_notes_ledger.dart';
import 'package:cyan_flutter/widgets/parity/parity_notes_view.dart';

import 'support/parity_test_harness.dart';

/// Wide enough that the editor and the ledger column both lay out.
const Size _face = Size(1000, 700);

/// The board the fixture seeds a real document on.
const String _board = 'b-eng-4';

/// The board the fixture seeds review comments on — `reviewAddComment` files
/// them as `review_comment` timecoded notes, which is the A2 rail's source.
const String _reviewBoard = 'b-eng-1';

String editorText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(const ValueKey('notes-editor')))
        .controller!
        .text;

void main() {
  testWidgets('the document opens in an editable buffer with its name, its '
      'detected type and its stats', (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityNotesView(boardId: _board),
        backend: backend, size: _face);

    expect(find.byKey(const ValueKey('notes-filename')), findsOneWidget);
    expect(find.text('deployment.md'), findsOneWidget);

    // The whole document is IN the buffer — the editor is a field, not a
    // rendered listing, because the reference lets you type into it.
    final seeded = await backend.loadNotes(_board);
    expect(editorText(tester), seeded.content);
    expect(editorText(tester), contains('# Deployment Notes'));

    // The type is DETECTED off the content.
    expect(find.text('Markdown'), findsOneWidget);

    expect(find.byKey(const ValueKey('notes-save-state')), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.textContaining('lines'), findsOneWidget);
    expect(find.textContaining('words'), findsOneWidget);
    expect(find.text('UTF-8'), findsOneWidget);

    // The ledger is the face's right column, exactly as Swift's HStack mounts
    // BoardNotesLedgerView beside the editor.
    expect(find.byType(ParityNotesLedger), findsOneWidget);
  });

  testWidgets('typing marks the buffer unsaved, and an idle buffer autosaves',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityNotesView(boardId: _board),
        backend: backend, size: _face);

    await tester.enterText(find.byKey(const ValueKey('notes-editor')),
        '# Deployment Notes\n\nLocked for the Friday DCP.\n');
    await tester.pump();
    expect(find.text('Unsaved'), findsOneWidget);

    // Nothing has been written yet — the autosave is a DELAY, not a keystroke
    // hook, or every character would be a round trip to the engine.
    expect((await backend.loadNotes(_board)).content,
        isNot(contains('Friday DCP')));

    await tester.pump(kNotesAutosaveDelay);
    await tester.pumpAndSettle();

    expect((await backend.loadNotes(_board)).content,
        contains('Locked for the Friday DCP.'));
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('the caret is reported live in the status bar', (tester) async {
    final backend = FakeCyanBackend();
    final editor = NotesEditorController(backend: backend, boardId: _board);
    await pumpParity(
        tester, ParityNotesView(boardId: _board, controller: editor),
        backend: backend, size: _face);

    // Line 3, column 5 of a three-line buffer.
    await tester.enterText(
        find.byKey(const ValueKey('notes-editor')), 'one\ntwo\nthree');
    await tester.pump();
    editor.cursorMovedTo(12);
    await tester.pump();

    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('notes-caret')))
            .data,
        'Ln 3, Col 5');
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('notes-lines'))).data,
        '3 lines');
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('notes-words'))).data,
        '3 words');

    // Tidy: the autosave armed by the typing must not fire into a dead tree.
    await tester.pump(kNotesAutosaveDelay);
    await tester.pumpAndSettle();
  });

  testWidgets('a save the engine cannot read back is NOT reported as saved',
      (tester) async {
    // The engine this port runs against coerces every authored cell kind to
    // `step`, so a notes document is accepted and then unreadable. The face
    // must say so — a green "Saved" over a document that will come back blank
    // is the single worst thing this editor could do.
    final backend = _CoercingBackend();
    await pumpParity(tester, const ParityNotesView(boardId: _board),
        backend: backend, size: _face);

    await tester.enterText(
        find.byKey(const ValueKey('notes-editor')), '# Gone tomorrow\n');
    await tester.pump(kNotesAutosaveDelay);
    await tester.pumpAndSettle();

    expect(find.text('Not saved'), findsOneWidget);
    expect(find.byKey(const ValueKey('notes-save-problem')), findsOneWidget);
    expect(find.textContaining('stored this as a "step" cell'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('the A2 reviewer rail shows the board\'s sensed review comments',
      (tester) async {
    final backend = FakeCyanBackend();
    await backend.reviewAddComment(_reviewBoard, 'Title card runs long.',
        atSeconds: 74, author: 'Producer');
    await backend.reviewAddComment(_reviewBoard, 'Grade the last shot warmer.',
        atSeconds: 12, author: 'Director');

    await pumpParity(tester, const ParityNotesView(boardId: _reviewBoard),
        backend: backend, size: _face);

    expect(find.byKey(const ValueKey('notes-review-rail')), findsOneWidget);
    expect(find.text('Reviewer notes'), findsOneWidget);
    expect(find.text('Title card runs long.'), findsOneWidget);
    // Timecode-ordered, not insertion-ordered.
    final rail = tester
        .widgetList<Padding>(find.byWidgetPredicate((w) =>
            w is Padding &&
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('notes-review-')))
        .length;
    expect(rail, 2);
    expect(find.text('00:12'), findsOneWidget);
    expect(find.text('01:14'), findsOneWidget);

    // A board with no reviewer comments has NO rail — not an empty one.
    await pumpParity(tester, const ParityNotesView(boardId: _board),
        backend: backend, size: _face);
    expect(find.byKey(const ValueKey('notes-review-rail')), findsNothing);
  });

  test('the file type is detected the way the reference detects it', () {
    // JSON only when it PARSES — a leading brace is not a document.
    expect(detectNotesFileType('{"a": 1}'), NotesFileType.json);
    expect(detectNotesFileType('{not json at all'),
        isNot(NotesFileType.json));
    // YAML is gated on a `---` front matter marker or a bare `:\n` line, then
    // one of the marker keys. Reproduced verbatim, quirk included: a document
    // that is unmistakably YAML to a human but has neither gate is NOT
    // detected, and matching the reference is the point of this port.
    expect(detectNotesFileType('---\napiVersion: v1\nkind: Pod\n'),
        NotesFileType.yaml);
    expect(detectNotesFileType('apiVersion: v1\nkind: Pod\n'),
        isNot(NotesFileType.yaml));
    expect(detectNotesFileType('# Heading\n\nbody'), NotesFileType.markdown);
    expect(detectNotesFileType('SELECT id FROM boards;'), NotesFileType.sql);
    expect(detectNotesFileType('just some prose'), NotesFileType.plaintext);
    expect(detectNotesFileType(''), NotesFileType.plaintext);
    expect(NotesFileType.typescript.displayName, 'TypeScript');
  });

  test('the save verdict keeps its three facts apart', () {
    const durable =
        NotesSaveResult(accepted: true, readBack: true, storedKind: 'markdown');
    expect(durable.durable, isTrue);
    expect(durable.reason, isNull);

    // Accepted, re-kinded, unreadable — the case this engine actually produces.
    const coerced =
        NotesSaveResult(accepted: true, readBack: false, storedKind: 'step');
    expect(coerced.durable, isFalse);
    expect(coerced.reason, contains('"step"'));

    const refused = NotesSaveResult();
    expect(refused.reason, 'the engine refused the write');
    const broke = NotesSaveResult(error: 'the engine was not reachable');
    expect(broke.reason, 'the engine was not reachable');
  });

  testWidgets('golden: notes editor', (tester) async {
    await pumpParity(tester, const ParityNotesView(boardId: _board),
        size: _face);
    await expectLater(
      find.byType(ParityNotesView),
      matchesGoldenFile('golden/notes_editor.png'),
    );
  }, tags: 'golden');
}

/// A backend whose notes save behaves like THIS engine baseline: it takes the
/// write, re-kinds it to `step`, and the editor can never read it back.
class _CoercingBackend extends FakeCyanBackend {
  @override
  Future<NotesSaveResult> saveNotes(String boardId, String content) async =>
      const NotesSaveResult(
          accepted: true, readBack: false, storedKind: 'step');
}
