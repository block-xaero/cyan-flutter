// notes_editor_face_test.dart — TIER 2. The Notes EDITOR, row 16, through the
// PRODUCTION seam against a real seeded engine.
//
// This supersedes the row-5 half of `notes_face_test.dart`: that file proved
// `loadNotes` reads the board's markdown and that the SAVE is coerced. This one
// proves the same thing THROUGH THE FACE'S OWN CONTROLLER, which is what the
// operator actually drives — and it pins the verdict the toolbar shows, because
// the whole point of the row-16 rebuild is that the editor now reports what the
// engine did instead of a green dot that is always on.
//
//   flutter test integration_test/notes_editor_face_test.dart -d windows

import 'dart:io';

import 'package:cyan_flutter/ffi/cyan_backend_ffi.dart';
import 'package:cyan_flutter/ffi/ffi_helpers.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/providers/notes_editor_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// A board the demo seed files markdown cells on — cyan-backend's `seed.rs`
/// stores its workflow STEPS as `markdown` cells, which is why a seeded board
/// has a readable notes document at all.
const _seededBoard = 'pr-tos-trailer';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final backend = CyanBackendFFI();

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('cyan_editor_');
    expect(CyanFFI.setDataDir(tmp.path), isTrue,
        reason: 'the engine refused ${tmp.path} as its data dir and would '
            'write its blob store into the source tree');
    expect(
      CyanFFI.initWithIdentity(
        dbPath: '${tmp.path}/cyan.db',
        secretKeyHex: List.filled(64, 'f').join(),
        relayUrl: '',
        discoveryKey: 'cyan-notes-editor-test',
      ),
      isTrue,
      reason: 'the engine refused to boot with an identity',
    );
    await backend.initialize();

    CyanFFI.seedDemo();
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if ((await backend.loadWorkflow(_seededBoard)).steps.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException catch (e) {
      // ignore: avoid_print
      print('note: left ${tmp.path} for the OS to reap — the engine still holds '
          'the database open and has no shutdown verb to call. ($e)');
    }
  });

  test('the editor opens the board\'s own document, detects its type and '
      'counts it', () async {
    final editor =
        NotesEditorController(backend: backend, boardId: _seededBoard);
    await editor.load();

    expect(editor.state.hydrated, isTrue);
    expect(editor.state.content, isNotEmpty,
        reason: 'the board holds markdown cells and the editor came up blank');
    expect(editor.state.dirty, isFalse,
        reason: 'a freshly loaded document is not an unsaved one');
    expect(editor.state.lineCount, greaterThan(0));
    expect(editor.state.wordCount, greaterThan(0));
    // The type is detected off the ENGINE's content, not off the file name.
    expect(editor.state.detectedType, isNotNull);
    expect(editor.state.saveLabel, 'Saved');
  });

  test('a board the engine has never seen opens on the empty template',
      () async {
    final editor =
        NotesEditorController(backend: backend, boardId: 'no-such-board');
    await editor.load();
    expect(editor.state.content, '# Notes\n\nStart typing here...\n');
    expect(editor.state.reviewNotes, isEmpty);
  });

  // ── THE BLOCK, now proved THROUGH THE FACE and reported BY the face ───────
  //
  // `cyan_save_notebook_cell` runs every authored kind through
  // `workflow::coerce_authoring_cell_type`, and ROUND8 §W1 made `step` the only
  // authorable kind — `markdown` is on LEGACY_AUTHORING_KINDS and collapses
  // into it. So a saved notes document is stored as a workflow step and
  // vanishes from the filter the editor reads by.
  //
  // What row 16 changes is not the engine but the HONESTY: the seam returns a
  // read-back beside the acknowledgement, and the toolbar shows "Not saved"
  // with the engine's own reason instead of a green dot over a document that
  // will come back blank. When the engine grows a notes-document kind this test
  // goes red at the `readBack` expectation and the block is liftable.
  test('BLOCKED: the engine takes the save, re-kinds it to step, and the face '
      'reports NOT SAVED rather than lying', () async {
    final editor =
        NotesEditorController(backend: backend, boardId: _seededBoard);
    await editor.load();

    const body = '# Trailer notes\n\n- Lock the cut\n- Send for review\n';
    editor.contentDidChange(body);
    expect(editor.state.dirty, isTrue);
    expect(editor.state.saveLabel, 'Unsaved');

    await editor.save();

    final verdict = editor.state.lastSave!;
    expect(verdict.accepted, isTrue,
        reason: 'the engine refused the write outright — that is a DIFFERENT '
            'failure from the coercion this test is about');
    expect(verdict.storedKind, 'step',
        reason: 'if this is "markdown" the engine has stopped coercing '
            'authored cells: the Notes editor is unblocked, and row 16 can be '
            'marked green in PARITY_TRACKER.md');
    expect(verdict.readBack, isFalse);
    expect(verdict.durable, isFalse);
    expect(verdict.reason, contains('"step"'));

    // The face says so.
    expect(editor.state.saveLabel, 'Not saved');
    expect(editor.state.saveProblem, isNotNull);

    // And the document really is unreadable — a reload does NOT come back with
    // what was typed, which is exactly what the toolbar just warned about.
    await editor.load();
    expect(editor.state.content, isNot(body),
        reason: 'the editor now reads back what it saved — the block is '
            'lifted; unblock the Notes editor in PARITY_TRACKER.md');
  });

  test('the A2 reviewer rail reads the board\'s sensed review comments off the '
      'engine', () async {
    // NOT through `reviewAddComment`: the engine gates that verb on the board
    // having PUBLISHED REVIEW MEDIA ("board has no published review media yet"
    // — a real constraint, recorded here so nobody re-derives it), and a seeded
    // board has none. The rail's source is the timecoded-note store either way,
    // so the comment is filed there directly and the rail is read off it.
    expect(
        await backend.saveTimecodeNote(const TimecodeNote(
          id: 'tc-review-1',
          boardId: _seededBoard,
          timecodeSeconds: 74,
          content: 'Title card runs two frames long.',
          noteType: 'review_comment',
          author: 'Producer',
        )),
        isTrue,
        reason: 'the engine refused the review comment');

    final editor =
        NotesEditorController(backend: backend, boardId: _seededBoard);
    await editor.load();

    expect(editor.state.reviewNotes, isNotEmpty,
        reason: 'the rail is the board\'s `review_comment` timecoded notes — '
            'an empty rail over a comment the engine holds means the filter or '
            'the read is wrong');
    final row = editor.state.reviewNotes
        .firstWhere((n) => n.text.contains('Title card runs'));
    expect(row.seconds, 74);
    expect(row.timecodeLabel, '01:14');
    expect(row.author, 'Producer');

    // The rail is filtered, not everything: the notes document is untouched by
    // it and a non-review timecoded note stays off it.
    expect(await backend.saveTimecodeNote(const TimecodeNote(
          id: 'tc-not-a-review',
          boardId: _seededBoard,
          timecodeSeconds: 5,
          content: 'An editor note, not a reviewer one.',
          noteType: 'comment',
          author: 'Editor',
        )),
        isTrue);
    await editor.load();
    expect(editor.state.reviewNotes.any((n) => n.id == 'tc-not-a-review'),
        isFalse);
  });
}
