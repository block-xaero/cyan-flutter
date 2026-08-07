// video_face_test.dart — TIER 2. The Video face, row 14, through the PRODUCTION
// seam against a real engine.
//
// The face's Tier-1 suite drives `FakeCyanBackend`, which round-trips a note
// perfectly. This file asks whether the ENGINE does. On 2026-08-07 the answer
// was "mostly" — `reply_to`/`thread_count`/`created_at` were written by nobody
// and read by `load_notes`, so every reply loaded as a root note. Finding that
// is what this test was for; cyan-backend 92ec790 fixed it, and the threading
// test below is now the round trip read the other way up.
//
// The lane is `cyan_save_timecode_note` / `cyan_load_timecode_notes` /
// `cyan_export_notes_markdown` / `cyan_act_on_timecode_note`. A timecoded note
// is stored as a `timecode_note` notebook cell by a DIRECT insert, so unlike an
// authored markdown cell it is NOT run through
// `workflow::coerce_authoring_cell_type` — the note-write lane is real.
//
//   flutter test integration_test/video_face_test.dart -d windows

import 'dart:io';

import 'package:cyan_flutter/ffi/cyan_backend_ffi.dart';
import 'package:cyan_flutter/ffi/ffi_helpers.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/providers/video_face_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final backend = CyanBackendFFI();
  late String board;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('cyan_video_');
    expect(CyanFFI.setDataDir(tmp.path), isTrue,
        reason: 'the engine refused ${tmp.path} as its data dir and would '
            'write its blob store into the source tree');
    expect(
      CyanFFI.initWithIdentity(
        dbPath: '${tmp.path}/cyan.db',
        secretKeyHex: List.filled(64, 'c').join(),
        relayUrl: '',
        discoveryKey: 'cyan-video-face-test',
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

  test('a board that has never been reviewed opens on an empty rail, and the '
      'face says so rather than spinning', () async {
    final face = VideoFaceController(backend: backend, boardId: board);
    await face.load();

    expect(face.state.hydrated, isTrue);
    expect(face.state.notes, isEmpty);
    expect(face.state.roots, isEmpty);
    expect(face.state.aiFindings, isEmpty);
    expect(face.state.humanComments, isEmpty);
    // The media read answered — a board with nothing ingested has null paths,
    // which is a real answer and NOT the seam's unreachable-engine sentinel.
    expect(face.state.media, isNotNull);
    expect(face.state.media!.error, isNull,
        reason: 'cyan_board_video_media did not answer: '
            '${face.state.media!.error}');
  });

  test('a note written through the face survives the engine round trip — '
      'content, timecode, type, author and pipeline context', () async {
    final face = VideoFaceController(
      backend: backend,
      boardId: board,
      author: 'Ada Byron',
      pipelineStepId: 'step-audio-conform',
    );
    await face.load();

    final filed = await face.addNote(
      content: 'Dialogue clips on the wide — level pass before the mix.',
      atSeconds: 42.5,
      noteType: 'qc_issue',
    );
    expect(filed, isNotNull, reason: 'the engine refused the note');

    // Read back through the seam, not from the controller's own copy.
    final stored = await backend.loadTimecodeNotes(board);
    expect(stored, hasLength(1));
    final n = stored.single;
    expect(n.id, filed!.id);
    expect(n.content, filed.content);
    expect(n.timecodeSeconds, 42.5);
    expect(n.noteType, 'qc_issue');
    expect(n.author, 'Ada Byron');
    expect(n.pipelineStepId, 'step-audio-conform');
    expect(n.pipelinePhase, 'review');
    expect(n.aiReviewed, isFalse);
    expect(n.humanApproved, isFalse);
  });

  test('approving a note is a real write the engine keeps', () async {
    final face = VideoFaceController(backend: backend, boardId: board);
    await face.load();
    final before = face.state.roots.single;
    expect(before.humanApproved, isFalse);

    await face.approve(before);

    final after = (await backend.loadTimecodeNotes(board)).single;
    expect(after.humanApproved, isTrue);
    // An approval is not an edit — everything else is byte-identical.
    expect(after.content, before.content);
    expect(after.timecodeSeconds, before.timecodeSeconds);
    expect(after.noteType, before.noteType);
    expect(after.author, before.author);
  });

  test('the export is the ENGINE\'s own markdown rendering, and it lands on the '
      'notes ledger where a reader can find it', () async {
    final face = VideoFaceController(backend: backend, boardId: board);
    await face.load();

    final markdown = await backend.exportNotesMarkdown(board);
    expect(markdown, isNotNull,
        reason: 'cyan_export_notes_markdown answered nothing');
    expect(markdown, contains('Dialogue clips'),
        reason: 'the export does not carry the note it was rendered from');

    final before = (await backend.noteList(board)).length;
    await face.exportToNotes();
    // The ledger write is fire-and-forget engine-side, so poll the read.
    var ledger = await backend.noteList(board);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (ledger.length == before && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      ledger = await backend.noteList(board);
    }
    expect(ledger.length, greaterThan(before),
        reason: 'the export never reached the notes ledger — PHASE-2 D2 makes '
            'that ledger the notes surface, so an export that lands nowhere '
            'else is an export nobody can read');
    expect(ledger.any((n) => n.text.contains('Dialogue clips')), isTrue);
  });

  // ── THREADING — the block this test was written to prove, now LIFTED ───────
  //
  // Until 2026-08-07 `timecode_notes::save_note` built the cell's
  // `metadata_json` from a fixed key set that OMITTED `reply_to`,
  // `thread_count` and `created_at` — while `load_notes` read all three back
  // out of that same metadata. Every reply loaded as a ROOT note, every thread
  // count was 0, and every note was stamped at the epoch. This test was the
  // receipt: it sent the parent id, proved the port sent it, then proved the
  // engine did not keep it.
  //
  // cyan-backend 92ec790 writes all three. The assertions below are the SAME
  // round trip read the other way up — a reply comes back a reply, the face
  // threads it under its parent, and the ordering clock is real.
  test('a reply survives the engine round trip and the face threads it under '
      'its parent', () async {
    final face = VideoFaceController(backend: backend, boardId: board);
    await face.load();
    final parent = face.state.roots.single;

    face.replyTo(parent.id);
    final before = DateTime.now().millisecondsSinceEpoch / 1000;
    final reply = await face.addNote(
      content: 'Agreed — flagging for the mixer, not a re-conform.',
      // Deliberately NOT the parent's timecode: the controller inherits it, so
      // if the inheritance broke this would show up as a wrong timecode too.
      atSeconds: 300,
      noteType: 'comment',
    );
    expect(reply, isNotNull);
    expect(reply!.replyTo, parent.id,
        reason: 'the controller must SEND the parent id — if this fails the '
            'defect is in the port, not the engine');
    expect(reply.timecodeSeconds, parent.timecodeSeconds,
        reason: 'a reply belongs to the moment its parent pinned');

    final stored = await backend.loadTimecodeNotes(board);
    expect(stored, hasLength(2));
    final readBack = stored.firstWhere((n) => n.id == reply.id);

    expect(readBack.replyTo, parent.id,
        reason: 'the engine dropped reply_to again — threading is dead and '
            'row 14 is blocked once more');
    expect(readBack.createdAt, greaterThanOrEqualTo(before),
        reason: 'created_at came back as its default, so the thread has no '
            'ordering clock — replies would sort arbitrarily');

    // `thread_count` is a CLIENT-cached count the engine stores verbatim and
    // never maintains: nothing on either side increments the parent's when a
    // reply lands. The face therefore counts replies from the rail it already
    // holds (`repliesTo`) and never reads this field — pinned here so the
    // round trip is understood rather than trusted.
    expect(readBack.threadCount, 0,
        reason: 'the engine started maintaining thread_count — the face may '
            'now read it instead of counting the rail');

    // The parent's own row is untouched by its reply.
    final parentBack = stored.firstWhere((n) => n.id == parent.id);
    expect(parentBack.replyTo, isNull);

    // …and this is what the face is left holding: ONE root with its reply
    // threaded underneath, which is the shape the reference draws.
    await face.load();
    expect(face.state.roots, hasLength(1),
        reason: 'the reply is drawn as a second top-level note — the engine '
            'did not keep reply_to');
    expect(face.state.roots.single.id, parent.id);
    expect(face.state.repliesTo(parent.id).map((n) => n.id), [reply.id]);
    // The reply is NOT in either panel section — those are cut from the roots.
    expect(face.state.humanComments.map((n) => n.id), [parent.id]);
  });

  test('the AI rail answers rather than crashing when no model is bound',
      () async {
    final face = VideoFaceController(backend: backend, boardId: board);
    await face.load();
    final note = face.state.roots.first;

    // This box binds no lens and no local model. The point is not that the
    // call succeeds — it is that an unbound rail is an ANSWER the face can
    // show, never a hang and never a crash, and that the face is not left
    // stuck with a spinner on the row.
    await face.actOnNote(note);

    expect(face.state.actingNoteId, isNull,
        reason: 'the row would spin forever — the act never resolved');
    final answered = face.state.notes.firstWhere((n) => n.id == note.id);
    expect(answered.aiReviewed || face.state.lastError != null, isTrue,
        reason: 'the rail neither answered nor named a reason; the face has '
            'nothing honest to show');
  });
}
