// notes_ledger_face_test.dart — TIER 2. The Notes LEDGER, row 15, through the
// PRODUCTION seam against a real engine.
//
// PHASE-2 D2 made the ledger the Notes surface: the `cyan_note_*` verbs write to
// their own store and are NOT run through `workflow::coerce_authoring_cell_type`,
// which is what killed the markdown-cell editor's save (see the row-5 block in
// PARITY_TRACKER.md). This file is the receipt for that decision — it proves the
// ledger's whole CRUD against the engine, and it proves the C7 lane the ledger
// rows are drawn from (anchor + provenance) survives a write.
//
// The note write is FIRE-AND-FORGET engine-side: `cyan_note_put` queues a
// command and acknowledges nothing, so every assertion here polls the READ
// rather than trusting a receipt that does not exist.
//
//   flutter test integration_test/notes_ledger_face_test.dart -d windows

import 'dart:io';

import 'package:cyan_flutter/ffi/cyan_backend_ffi.dart';
import 'package:cyan_flutter/ffi/ffi_helpers.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final backend = CyanBackendFFI();
  late String board;

  /// Poll the ledger until [test] holds or the budget runs out — the write side
  /// is a queued command, so a read straight after a put is a race.
  Future<List<CyanNote>> until(bool Function(List<CyanNote>) test) async {
    var notes = await backend.noteList(board);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!test(notes) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      notes = await backend.noteList(board);
    }
    return notes;
  }

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('cyan_ledger_');
    expect(CyanFFI.setDataDir(tmp.path), isTrue,
        reason: 'the engine refused ${tmp.path} as its data dir and would '
            'write its blob store into the source tree');
    expect(
      CyanFFI.initWithIdentity(
        dbPath: '${tmp.path}/cyan.db',
        secretKeyHex: List.filled(64, 'd').join(),
        relayUrl: '',
        discoveryKey: 'cyan-notes-ledger-test',
      ),
      isTrue,
      reason: 'the engine refused to boot with an identity',
    );
    await backend.initialize();

    CyanFFI.seedDemo();
    var boards = <BoardWithContext>[];
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      boards = await backend.loadAllBoards();
      if (boards.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(boards, isNotEmpty, reason: 'the seed never landed');
    board = boards.first.board.id;
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

  test('the ledger write lane is REAL — a note authored through the seam is '
      'read back off the engine', () async {
    expect(await backend.noteList(board), isEmpty,
        reason: 'the seed files no board notes; if this is non-empty the rest '
            'of this suite is asserting against someone else\'s data');

    await backend.notePut(board, 'Nothing ships before the review gate.');
    final notes =
        await until((n) => n.any((x) => x.text.contains('review gate')));

    expect(notes, hasLength(1),
        reason: 'the note never landed — this is the lane PHASE-2 D2 moved the '
            'Notes face onto, so a dead write here voids that decision');
    final note = notes.single;
    expect(note.boardId, board);
    expect(note.kind, 'editor-note');
    expect(note.scope, 'board');
    // The ENGINE stamps these — the port never invents an author or a clock.
    expect(note.id, isNotEmpty);
    expect(note.createdAt, greaterThan(0));
    expect(note.updatedAt, greaterThan(0));
    expect(note.tenantId, isNotEmpty,
        reason: 'an omitted tenant must be DERIVED from the board\'s group, '
            'or a later scoped read will not find this note');
  });

  test('an edit lands in place, and a delete removes exactly one note',
      () async {
    final before = (await backend.noteList(board)).single;

    await backend.notePut(board, 'Nothing ships before the review gate. (v2)',
        noteId: before.id);
    final edited = await until((n) => n.single.text.endsWith('(v2)'));
    expect(edited.single.id, before.id, reason: 'the edit MINTED a second note');
    expect(edited.single.createdAt, before.createdAt,
        reason: 'an edit must not restamp when the note was created');

    await backend.notePut(board, 'Cut proxies at 1080p.');
    await until((n) => n.length == 2);

    await backend.noteDelete(before.id);
    final after = await until((n) => n.length == 1);
    expect(after.single.text, 'Cut proxies at 1080p.');
  });

  test('the ANCHOR and the PROVENANCE survive the write — the C7 lane the '
      'ledger rows are drawn from', () async {
    // The plain C verbs hardcode these to null, so this goes through the JSON
    // command door exactly as the reference's `BoardNote.toJSON()` does.
    final queued = await backend.notePutAnchored(
      board,
      'We ship the 1080 proxy for producer review.',
      kind: 'decision',
      anchorKind: 'step',
      anchorId: 'step-audio-conform',
      originRef: 'chat:msg-eng-42',
      authorRole: 'editor',
    );
    expect(queued, isTrue, reason: 'the command could not even be queued');

    final notes =
        await until((n) => n.any((x) => x.kind == 'decision'));
    final decision = notes.firstWhere((n) => n.kind == 'decision');

    expect(decision.anchorKind, 'step',
        reason: 'the ledger row cannot draw an anchor label the engine did not '
            'keep — the C7 write lane is not reaching the store');
    expect(decision.anchorId, 'step-audio-conform');
    expect(decision.originRef, 'chat:msg-eng-42');
    expect(decision.authorRole, 'editor');

    // …and the two derivations the ledger row is actually built from.
    expect(decision.anchorLabel, 'on step step-a');
    expect(decision.isPromotedFromChat, isTrue);
  });

  test('the markdown export is the ENGINE\'s rendering of the board, not a '
      're-render of the rows', () async {
    final markdown = await backend.exportNotesMarkdown(board);
    expect(markdown, isNotNull,
        reason: 'cyan_export_notes_markdown answered nothing — "Copy notes" '
            'would put an empty clipboard over the operator\'s selection');
    expect(markdown, isNotEmpty);
  });
}
