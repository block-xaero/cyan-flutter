// video_face_test.dart — TIER 2. The Video face, row 14, through the PRODUCTION
// seam against a real engine.
//
// The face's Tier-1 suite drives `FakeCyanBackend`, which round-trips a note
// perfectly. This file asks whether the ENGINE does — and the answer is: mostly,
// with one field family that does not survive the trip. Finding that is what
// this test is for.
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

  // ── THE BLOCKER, pinned down with evidence rather than claimed ─────────────
  //
  // `timecode_notes::save_note` builds the cell's `metadata_json` from a fixed
  // set of keys — timecode_seconds, note_type, author, pipeline_step_id,
  // pipeline_phase, ai_reviewed, human_approved, action_* and ai_flags_nearby.
  // It does NOT write `reply_to`, `thread_count` or `created_at`.
  //
  // `load_notes` reads all three back out of that same metadata. So every one
  // of them comes back as its default: a REPLY loads as a ROOT note, the thread
  // count is always 0, and every note is stamped at the epoch.
  //
  // The consequence for this face: threading is DEAD against the real engine.
  // The reference draws replies under their parent with a connector and a
  // reply count; through this engine every reply is a top-level note in the
  // wrong section, at the wrong place in a rail that orders by timecode.
  //
  // This is engine work — one line of JSON in save_note — and engine work
  // belongs to the Mac session. The face is written correctly and this test is
  // the receipt. When the engine starts persisting reply_to, this test goes red
  // and the block is liftable.
  test('BLOCKED: the engine drops reply_to, thread_count and created_at, so a '
      'reply loads as a root note', () async {
    final face = VideoFaceController(backend: backend, boardId: board);
    await face.load();
    final parent = face.state.roots.single;

    face.replyTo(parent.id);
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

    expect(readBack.replyTo, isNull,
        reason: 'the engine now persists reply_to — threading works, this '
            'block is LIFTED and row 14 can be unblocked in PARITY_TRACKER.md');
    expect(readBack.threadCount, 0);
    expect(readBack.createdAt, 0,
        reason: 'the engine now persists created_at — thread ordering is real');

    // …and this is what the face is left holding: two roots where there should
    // be a parent and its reply.
    await face.load();
    expect(face.state.roots, hasLength(2),
        reason: 'the reply is being threaded, so the engine kept reply_to');
    expect(face.state.repliesTo(parent.id), isEmpty);
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
