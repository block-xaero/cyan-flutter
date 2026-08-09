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
import 'package:cyan_flutter/widgets/parity/parity_constitution_editor.dart';
import 'package:cyan_flutter/lens/fake_lens_api.dart';
import 'package:cyan_flutter/lens/lens_api.dart';
import 'package:cyan_flutter/models/notes_face_mode.dart';
import 'package:cyan_flutter/widgets/parity/parity_notes_ledger.dart';
import 'package:cyan_flutter/widgets/parity/parity_notes_structuring.dart';
import 'package:cyan_flutter/widgets/parity/parity_notes_view.dart';

import 'support/parity_test_harness.dart';

/// Wide enough that the editor and the ledger column both lay out.
const Size _face = Size(1000, 700);

/// The board the fixture seeds a real document on.
const String _board = 'b-eng-4';

/// The board the fixture seeds review comments on — `reviewAddComment` files
/// them as `review_comment` timecoded notes, which is the A2 rail's source.
const String _reviewBoard = 'b-eng-1';

String editorText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('notes-editor')))
    .controller!
    .text;

void main() {
  testWidgets(
      'the document opens in an editable buffer with its name, its '
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

    expect(tester.widget<Text>(find.byKey(const ValueKey('notes-caret'))).data,
        'Ln 3, Col 5');
    expect(tester.widget<Text>(find.byKey(const ValueKey('notes-lines'))).data,
        '3 lines');
    expect(tester.widget<Text>(find.byKey(const ValueKey('notes-words'))).data,
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
    expect(detectNotesFileType('{not json at all'), isNot(NotesFileType.json));
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

  // ---- MODE PICKER: the route to the house rules ---------------------------
  //
  // `ParityConstitutionEditor` is a complete port with four green behaviour
  // tests and, until now, ZERO mount sites — and unlike every other orphaned
  // face it has no in-tree parent either, so mounting the shell did not reach
  // it. Every Mac route to the constitution goes through this picker
  // (NotesEditorView.swift:403-411), and Flutter's Notes face had none.
  //
  // This matters beyond navigation: the constitution IS the WITHOUT-NOTES
  // lever. A board with no review notes takes its arguments from the house
  // rules, so "add a rule, re-run, the output changes" is the whole
  // without-notes demonstration — and it could not be performed at all.

  testWidgets('the Notes face offers all three modes', (tester) async {
    await pumpParity(tester, const ParityNotesView(boardId: 'b-eng-1'),
        size: const Size(1200, 800));

    expect(find.byKey(const ValueKey('notes.mode.picker')), findsOneWidget);
    for (final mode in NotesFaceMode.values) {
      expect(find.byKey(ValueKey(mode.segmentKey)), findsOneWidget,
          reason: 'the ${mode.label} segment');
    }
    // Structure was withheld while `LensApi` had no `structureNote` — a control
    // with no lane behind it is worse than no control. This assertion is the
    // other half of that trade: the segment appears the moment the lane does,
    // and the old "it must be absent" case is what made me come back here.
  });

  // ---- NOTES AS INTENT: the note becomes a workflow ------------------------

  testWidgets(
      'the editor offers "Author workflow with Lens", and it lands '
      'steps without running them', (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityNotesView(boardId: _board),
        backend: backend, size: const Size(1400, 900));

    final button = find.byKey(const ValueKey('notes.authorWithLens'));
    expect(button, findsOneWidget,
        reason: 'the note IS the intent — the editor must offer the lane');

    final stepsBefore = (await backend.loadWorkflow(_board)).steps.length;
    await tester.tap(button);
    await tester.pumpAndSettle();

    // The banner reports what landed and, crucially, tells the operator that
    // NOTHING has run.
    expect(find.byKey(const ValueKey('notes.intent.success')), findsOneWidget);
    expect(find.textContaining('press Run yourself'), findsOneWidget);
    expect((await backend.loadWorkflow(_board)).steps.length,
        greaterThan(stepsBefore),
        reason: 'the drafted steps land on the board through the seam');
  });

  testWidgets('the intent lane\'s failure is shown and dismissible',
      (tester) async {
    await pumpParity(
      tester,
      const ParityNotesView(boardId: _board),
      lens: FakeLensApi(
          failWith:
              const LensApiException('vLLM unreachable', statusCode: 503)),
      size: const Size(1400, 900),
    );

    await tester.tap(find.byKey(const ValueKey('notes.authorWithLens')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('notes.intent.error')), findsOneWidget);
    expect(find.textContaining('vLLM unreachable'), findsOneWidget,
        reason: 'the banner carries the LENS\'s words, not a generic shrug');

    // It clears only when the operator says so — a failure they were not
    // looking at is exactly the one they need to still be there.
    await tester.tap(find.byKey(const ValueKey('notes.intent.dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notes.intent.error')), findsNothing);
  });

  testWidgets(
      'the lane is offered only on the document, not over the '
      'constitution', (tester) async {
    await pumpParity(tester, const ParityNotesView(boardId: _board),
        size: const Size(1400, 900));
    expect(find.byKey(const ValueKey('notes.authorWithLens')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notes-mode-constitution')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notes.authorWithLens')), findsNothing,
        reason: 'there is no document to draft from on that surface');
  });

  testWidgets('selecting Structure mounts the structuring lane',
      (tester) async {
    await pumpParity(tester, const ParityNotesView(boardId: 'b-eng-1'),
        size: const Size(1200, 800));

    await tester.tap(find.byKey(const ValueKey('notes-mode-structure')));
    await tester.pumpAndSettle();

    expect(find.byType(ParityNotesStructuring), findsOneWidget);
    expect(find.byKey(const ValueKey('structuring.draft')), findsOneWidget);
    // The document's status bar is meaningless over this surface.
    expect(find.byKey(const ValueKey('notes-caret')), findsNothing);
  });

  testWidgets('structuring proposes typed notes that QUOTE the input',
      (tester) async {
    await pumpParity(tester, const ParityNotesView(boardId: 'b-eng-1'),
        size: const Size(1200, 900));
    await tester.tap(find.byKey(const ValueKey('notes-mode-structure')));
    await tester.pumpAndSettle();

    const written = 'Warm teal-orange look on the endcard. '
        'Keep it at -14 LUFS integrated. Ok fine.';
    await tester.enterText(
        find.byKey(const ValueKey('structuring.draft')), written);
    await tester.tap(find.byKey(const ValueKey('structuring.run')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('structuring.proposal.prop-0')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('structuring.proposal.prop-1')),
        findsOneWidget);
    // The two-word fragment came back as a NAMED rejection rather than
    // vanishing — "it ignored half my note" and "it told me it did" are very
    // different products.
    expect(find.text('noise'), findsOneWidget);

    // THE QUOTING GATE: every proposal's span is a verbatim substring of what
    // the operator actually wrote. A span that is not is the model inventing.
    for (final key in const ['prop-0', 'prop-1']) {
      final span = tester
          .widget<Text>(find.byKey(ValueKey('structuring.span.$key')))
          .data!;
      final quoted = span.substring(1, span.length - 1);
      expect(written, contains(quoted),
          reason: 'the lane may only surface substrings of the input');
    }
  });

  testWidgets('nothing is written until a proposal is CONFIRMED',
      (tester) async {
    // Auto-accept is off. The lens call persists nothing; confirming is what
    // writes, and it writes through the ENGINE so its validation still runs.
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityNotesView(boardId: 'b-eng-1'),
        backend: backend, size: const Size(1200, 900));
    await tester.tap(find.byKey(const ValueKey('notes-mode-structure')));
    await tester.pumpAndSettle();

    final before = (await backend.noteList('b-eng-1')).length;

    await tester.enterText(find.byKey(const ValueKey('structuring.draft')),
        'Grade the endcard warmer please.');
    await tester.tap(find.byKey(const ValueKey('structuring.run')));
    await tester.pumpAndSettle();

    expect((await backend.noteList('b-eng-1')).length, before,
        reason: 'structuring alone must not write a note');

    await tester.tap(find.byKey(const ValueKey('structuring.confirm.prop-0')));
    await tester.pumpAndSettle();

    expect(find.text('Confirmed'), findsOneWidget);
    expect((await backend.noteList('b-eng-1')).length, greaterThan(before),
        reason: 'confirming writes through the engine');
  });

  testWidgets('selecting Constitution mounts the house-rules editor',
      (tester) async {
    await pumpParity(tester, const ParityNotesView(boardId: 'b-eng-1'),
        size: const Size(1200, 800));

    expect(find.byType(ParityConstitutionEditor), findsNothing,
        reason: 'the face opens on the document');

    await tester.tap(find.byKey(const ValueKey('notes-mode-constitution')));
    await tester.pumpAndSettle();

    expect(find.byType(ParityConstitutionEditor), findsOneWidget,
        reason: 'the WITHOUT-NOTES lever must be reachable');
    expect(find.byType(ParityNotesLedger), findsNothing,
        reason: 'the constitution REPLACES the editor body, as in Swift');

    // Back to the document, with the ledger and the status bar returning.
    await tester.tap(find.byKey(const ValueKey('notes-mode-editor')));
    await tester.pumpAndSettle();

    expect(find.byType(ParityConstitutionEditor), findsNothing);
    expect(find.byType(ParityNotesLedger), findsOneWidget);
  });
}

/// A backend whose notes save behaves like THIS engine baseline: it takes the
/// write, re-kinds it to `step`, and the editor can never read it back.
class _CoercingBackend extends FakeCyanBackend {
  @override
  Future<NotesSaveResult> saveNotes(String boardId, String content) async =>
      const NotesSaveResult(
          accepted: true, readBack: false, storedKind: 'step');
}
