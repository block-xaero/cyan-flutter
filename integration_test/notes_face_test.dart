// notes_face_test.dart — TIER 2. The Notes face, row 5, through the PRODUCTION
// seam against a real seeded engine.
//
// `loadNotes` returned an empty `notes.md` for every board — an honest empty
// while nothing was wired, and a blank editor over a board with prose in it
// once the engine was real. The document is the board's markdown cells, which
// is what SwiftUI's `NotesEditorViewModel.load()` reads, so this reads them
// too.
//
// A NOTE ON THE SEED, because a reader will otherwise think this file is wrong:
// cyan-backend's demo seed files its workflow STEPS as `markdown` cells
// (seed.rs calls `cell_insert_simple(..., "markdown", ...)` and hangs the
// pipeline plan off their metadata). So on a SEEDED board the Notes face shows
// the first step's text — and SwiftUI does exactly the same thing, because the
// reference filters on `cellType == .markdown` and nothing else. That is
// faithful parity with an odd seed, not a bug in the read: a board authored
// through the app gets `step` cells, which the markdown filter skips.
//
//   flutter test integration_test/notes_face_test.dart -d windows

import 'dart:io';

import 'package:cyan_flutter/ffi/cyan_backend_ffi.dart';
import 'package:cyan_flutter/ffi/ffi_helpers.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _board = 'pr-tos-trailer';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final backend = CyanBackendFFI();

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('cyan_notes_');
    expect(CyanFFI.setDataDir(tmp.path), isTrue);
    expect(
      CyanFFI.initWithIdentity(
        dbPath: '${tmp.path}/cyan.db',
        secretKeyHex: List.filled(64, 'e').join(),
        relayUrl: '',
        discoveryKey: 'cyan-notes-face-test',
      ),
      isTrue,
      reason: 'the engine refused to boot with an identity',
    );
    await backend.initialize();

    CyanFFI.seedDemo();
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if ((await backend.loadWorkflow(_board)).steps.isNotEmpty) break;
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

  test('the editor opens the board\'s own markdown, not a blank page', () async {
    final notes = await backend.loadNotes(_board);

    expect(notes.boardId, _board);
    expect(notes.content, isNotEmpty,
        reason: 'the board holds markdown cells and the editor came up blank — '
            'that is the seam returning its placeholder over real content');

    // It is the FIRST markdown cell verbatim, exactly as the reference reads
    // it — not a join, not a summary, not a re-render.
    final cells = await backend.notebookCells(_board);
    final firstMarkdown =
        cells.firstWhere((c) => c.kind == NotebookCellKind.markdown);
    expect(notes.content, firstMarkdown.content);
    expect(notes.content, isNot(contains('Start typing here')),
        reason: 'the empty-board template must never appear over a board that '
            'has cells — that would look like the operator\'s notes vanished');
  });

  test('a board the engine has never seen opens on the empty template',
      () async {
    final notes = await backend.loadNotes('no-such-board');
    expect(notes.content, '# Notes\n\nStart typing here...\n',
        reason: 'no cells at all is the one case that gets the template, and '
            'it is what SwiftUI puts in a fresh editor');
  });

  // ── THE BLOCKER, pinned down so nobody has to rediscover it ────────────────
  //
  // The Notes face cannot SAVE at this engine baseline, and this test is the
  // evidence rather than a claim. `cyan_save_notebook_cell` runs every incoming
  // kind through `workflow::coerce_authoring_cell_type`, and ROUND8 §W1 made
  // `step` the one and only authorable kind — "markdown" is on the
  // LEGACY_AUTHORING_KINDS list that collapses into it. So a notes document
  // saved as markdown is stored as a workflow STEP and vanishes from the very
  // filter the editor reads by.
  //
  // Two consequences the tracker records as `blocked`:
  //   1. nothing the Notes face writes can be read back by it;
  //   2. a board authored through THIS engine has no markdown cells at all, so
  //      the reference's markdown filter is a legacy reader — it can only ever
  //      see pre-coercion cells, like the seed's.
  //
  // This is a real conflict between the frozen SwiftUI reference and the engine
  // that shipped after it, not something to paper over in the seam. When the
  // engine grows a notes-document kind (or the face moves to the uncoerced
  // `cyan_note_*` ledger, which is SwiftUI's OTHER notes surface,
  // BoardNotesLedgerView), this test goes red and the block is liftable.
  test('BLOCKED: the engine stores a saved notes document as a step', () async {
    final opened = (await backend.notebookCells(_board))
        .firstWhere((c) => c.kind == NotebookCellKind.markdown);

    const body = '# Trailer notes\n\n- Lock the cut\n- Send for review\n';
    final saved = CyanFFI.saveNotebookCell(_board, {
      'id': opened.id,
      'board_id': _board,
      'cell_type': 'markdown',
      'cell_order': opened.order,
      'content': body,
      'collapsed': false,
    });
    expect(saved, isTrue, reason: 'the engine took the write itself');

    // The content landed — the write is not lost, it is RE-KINDED.
    final after = await backend.notebookCells(_board);
    final cell = after.firstWhere((c) => c.id == opened.id);
    expect(cell.content, body, reason: 'the engine did store the text');
    expect(cell.kind, NotebookCellKind.step,
        reason: 'if this is markdown again the engine has stopped coercing '
            'authored cells — re-read the note above, the Notes face can be '
            'unblocked');

    // …and therefore the editor cannot see it.
    final notes = await backend.loadNotes(_board);
    expect(notes.content, isNot(body),
        reason: 'the editor now reads back what it saved, which means the '
            'block is lifted — unblock row 5 in PARITY_TRACKER.md');
  });
}
