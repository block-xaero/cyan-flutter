// test/video_face_test.dart
//
// PARITY face `video` — the board's media with its review pinned to it BY
// SECONDS (Swift: VideoPlayerFace).
//
// Tier-1: every assertion is driven through the `CyanBackend` seam
// (FakeCyanBackend) and the `ReviewVideoSurface` seam (FakeReviewVideoSurface).
// No dylib, no decoder.
//
// The behaviours the reference publishes:
//   • the face plays the board's media and reports the playhead as a timecode
//   • the timeline carries one marker per root note, in the note's type colour
//   • the notes panel segments AI findings from review comments and counts both
//   • a note's thread hangs under it, with its reply count
//   • a note the AI has answered shows the analysis, the action and the priority
//   • Approve is a real WRITE, and it is the same note re-saved
//   • Dismiss is SESSION-LOCAL — the engine has no delete verb and the note
//     comes back on the next read
//   • filing a note writes it at the CURRENT timecode; a reply inherits its
//     parent's
//   • "Add to Pipeline" files an authored step and accepts the finding
//   • the export renders the ENGINE's markdown onto the notes ledger
//   • a board with no notes says so instead of drawing an empty rail

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/providers/video_face_controller.dart';
import 'package:cyan_flutter/widgets/parity/parity_video_face.dart';

import 'support/fake_review_surface.dart';
import 'support/parity_test_harness.dart';

/// Tall enough that the player, the timeline and the whole notes panel lay out.
const Size _face = Size(900, 900);

/// The flagship board — the only one the fixture has ingested media and
/// timecoded notes for.
const String _board = 'b-eng-1';

/// A board with media but no review rail — the fixture's normal case.
const String _bareBoard = 'b-eng-2';

Future<FakeReviewVideoSurface> pumpFace(
  WidgetTester tester,
  FakeCyanBackend backend, {
  String board = _board,
  VideoFaceController? controller,
}) async {
  final surface = FakeReviewVideoSurface();
  await pumpParity(
    tester,
    ParityVideoFace(boardId: board, surface: surface, controller: controller),
    backend: backend,
    size: _face,
  );
  return surface;
}

/// The board's rail read back off the seam — the store, not the widget's copy.
Future<List<TimecodeNote>> rail(FakeCyanBackend backend,
        {String board = _board}) =>
    backend.loadTimecodeNotes(board);

void main() {
  testWidgets('the face plays the board\'s media and reports the playhead as a '
      'timecode', (tester) async {
    final backend = FakeCyanBackend();
    final surface = await pumpFace(tester, backend);

    // The engine resolved a proxy for this board, and that is what mounted.
    final media = await backend.boardVideoMedia(_board);
    expect(surface.mountedPath, media.proxyPath);

    expect(find.byKey(const ValueKey('video.timecode')), findsOneWidget);
    expect(find.text('00:00'), findsWidgets);

    // 42.5s at 24fps is frame 1020 — the face reads the surface in SECONDS
    // because a timecoded note is pinned in seconds.
    surface.seek(1020);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.descendant(
                of: find.byKey(const ValueKey('video.timecode')),
                matching: find.byType(Text)))
            .data,
        '00:42');
  });

  testWidgets('the timeline carries one marker per root note and seeking to one '
      'raises it', (tester) async {
    final backend = FakeCyanBackend();
    final surface = await pumpFace(tester, backend);

    final notes = await rail(backend);
    final roots = [for (final n in notes) if (n.replyTo == null) n];
    expect(roots, hasLength(2));
    for (final n in roots) {
      expect(find.byKey(ValueKey('video.marker.${n.id}')), findsOneWidget);
    }
    // A reply is part of its parent's thread, not a second mark on the bed.
    final reply = notes.firstWhere((n) => n.replyTo != null);
    expect(find.byKey(ValueKey('video.marker.${reply.id}')), findsNothing);

    await tester.tap(find.byKey(ValueKey('video.marker.${roots.first.id}')));
    await tester.pumpAndSettle();
    expect(surface.currentFrame, (roots.first.timecodeSeconds * 24).round());
    expect(surface.isPlaying, isFalse,
        reason: 'jumping to a note must stop the picture — the reviewer is '
            'reading, not watching');
  });

  testWidgets('the notes panel segments AI findings from review comments, and '
      'threads hang under their parent', (tester) async {
    final backend = FakeCyanBackend();
    await pumpFace(tester, backend);

    expect(find.byKey(const ValueKey('video.section.ai')), findsOneWidget);
    expect(find.byKey(const ValueKey('video.section.human')), findsOneWidget);
    expect(find.text('AI Findings'), findsOneWidget);
    expect(find.text('Review Comments'), findsOneWidget);

    // The split is the reference's: reviewed-by-AI (or an `AI/` author) is a
    // finding, everything else is a comment.
    final notes = await rail(backend);
    final roots = [for (final n in notes) if (n.replyTo == null) n];
    final ai = [for (final n in roots) if (VideoFaceState.isAiNote(n)) n];
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('video.counts')))
            .data,
        '${ai.length} AI · ${roots.length - ai.length} human');

    // tc-eng-2 replies to tc-eng-1 — the thread renders with its count.
    expect(find.byKey(const ValueKey('video.note.tc-eng-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('video.thread.count.tc-eng-1')),
        findsOneWidget);
    expect(find.text('1 reply'), findsOneWidget);

    // Collapsing a section hides its notes and nothing else.
    await tester.tap(find.byKey(const ValueKey('video.section.ai')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video.note.tc-eng-1')), findsNothing);
    expect(find.byKey(const ValueKey('video.note.tc-eng-3')), findsOneWidget);
  });

  testWidgets('a note the AI answered shows the analysis, the action and the '
      'priority it returned', (tester) async {
    final backend = FakeCyanBackend();
    await pumpFace(tester, backend);

    expect(find.byKey(const ValueKey('video.note.analysis.tc-eng-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('video.note.action.tc-eng-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('video.note.priority.tc-eng-1')),
        findsOneWidget);
    expect(find.textContaining('Peak at -0.2 dBFS'), findsOneWidget);
    expect(find.textContaining('Priority: high'), findsOneWidget);

    // …and a reviewed note is NOT offered to the AI again.
    expect(find.byKey(const ValueKey('video.note.act.tc-eng-1')), findsNothing);
    // A note the AI has never seen is.
    expect(
        find.byKey(const ValueKey('video.note.act.tc-eng-3')), findsOneWidget);
  });

  testWidgets('sending a note to the AI rail writes the answer back onto it',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpFace(tester, backend);

    expect((await rail(backend))
        .firstWhere((n) => n.id == 'tc-eng-3')
        .actionResult,
        isNull);

    await tester.tap(find.byKey(const ValueKey('video.note.act.tc-eng-3')));
    await tester.pumpAndSettle();

    // The engine re-saves the note with the answer attached, so the face
    // re-reads rather than patching its own copy — the store is the proof.
    final acted = (await rail(backend)).firstWhere((n) => n.id == 'tc-eng-3');
    expect(acted.aiReviewed, isTrue);
    expect(acted.actionResult, isNotNull);
    expect(find.byKey(const ValueKey('video.note.analysis.tc-eng-3')),
        findsOneWidget);
  });

  testWidgets('Approve is a real write — the same note, re-saved',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpFace(tester, backend);

    expect((await rail(backend))
        .firstWhere((n) => n.id == 'tc-eng-1')
        .humanApproved,
        isFalse);

    await tester.tap(find.byKey(const ValueKey('video.note.approve.tc-eng-1')));
    await tester.pumpAndSettle();

    final after = (await rail(backend)).firstWhere((n) => n.id == 'tc-eng-1');
    expect(after.humanApproved, isTrue);
    // Everything else about the note is untouched — an approval is not an edit.
    expect(after.content, contains('Dialogue clips'));
    expect(after.actionResult, isNotNull);
    expect(find.byKey(const ValueKey('video.note.approvedChip.tc-eng-1')),
        findsOneWidget);
  });

  testWidgets('Dismiss takes a finding off THIS session only — the engine has '
      'no delete verb and the note is still in the store', (tester) async {
    final backend = FakeCyanBackend();
    final controller = VideoFaceController(backend: backend, boardId: _board);
    await pumpFace(tester, backend, controller: controller);

    await tester.tap(find.byKey(const ValueKey('video.note.dismiss.tc-eng-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video.note.tc-eng-1')), findsNothing);

    // The store still holds it. This is the honest state, not a bug: there is
    // no `cyan_delete_timecode_note` in the engine's export table, so a
    // dismissal cannot outlive the process and the face does not pretend it
    // can. If a delete verb ever lands, this expectation is what changes.
    expect((await rail(backend)).any((n) => n.id == 'tc-eng-1'), isTrue);
    await controller.load();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video.note.tc-eng-1')), findsNothing,
        reason: 'a dismissal must survive a re-read WITHIN the session — '
            'otherwise the note the reviewer just cleared reappears under '
            'their cursor');
  });

  testWidgets('filing a note writes it at the CURRENT timecode', (tester) async {
    final backend = FakeCyanBackend();
    final surface = await pumpFace(tester, backend);

    surface.seek(2400); // 100.0s at 24fps
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('video.compose')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('video.composer.field')),
        'Boom shadow enters frame left.');
    await tester.tap(find.byKey(const ValueKey('video.composer.send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('video.composer.type.qc_issue')));
    await tester.pumpAndSettle();

    final filed = (await rail(backend))
        .where((n) => n.content == 'Boom shadow enters frame left.');
    expect(filed, hasLength(1), reason: 'the note never reached the store');
    expect(filed.single.timecodeSeconds, 100.0);
    expect(filed.single.noteType, 'qc_issue');
    expect(filed.single.replyTo, isNull);
  });

  testWidgets('a reply inherits its parent\'s timecode, not the playhead\'s',
      (tester) async {
    final backend = FakeCyanBackend();
    final surface = await pumpFace(tester, backend);

    await tester.tap(find.byKey(const ValueKey('video.note.reply.tc-eng-3')));
    await tester.pumpAndSettle();

    // The playhead moves WHILE the reply is being typed — the reply still
    // belongs to the moment the parent pinned.
    surface.seek(2000);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('video.composer.field')), 'Trimmed on the cut.');
    await tester.tap(find.byKey(const ValueKey('video.composer.send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('video.composer.type.comment')));
    await tester.pumpAndSettle();

    final parent =
        (await rail(backend)).firstWhere((n) => n.id == 'tc-eng-3');
    final reply = (await rail(backend))
        .firstWhere((n) => n.content == 'Trimmed on the cut.');
    expect(reply.replyTo, 'tc-eng-3');
    expect(reply.timecodeSeconds, parent.timecodeSeconds);
  });

  testWidgets('"Add to Pipeline" files an authored step and accepts the '
      'finding it came from', (tester) async {
    final backend = FakeCyanBackend();
    await pumpFace(tester, backend);

    final before = (await backend.loadWorkflow(_board)).steps.length;

    await tester
        .tap(find.byKey(const ValueKey('video.note.toPipeline.tc-eng-1')));
    await tester.pumpAndSettle();

    final after = await backend.loadWorkflow(_board);
    expect(after.steps, hasLength(before + 1),
        reason: 'the AI action never reached the workflow');
    expect(after.steps.last.text, contains('AI-suggested:'));
    expect(after.steps.last.text, contains('Re-run the level pass'));
    // The finding it came from is accepted in the same move.
    expect(
        (await rail(backend))
            .firstWhere((n) => n.id == 'tc-eng-1')
            .humanApproved,
        isTrue);
    expect(find.byKey(const ValueKey('video.pipeline.chip')), findsOneWidget);
  });

  testWidgets('the export renders the ENGINE\'s markdown onto the notes ledger',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpFace(tester, backend);

    final before = (await backend.noteList(_board)).length;
    await tester.tap(find.byKey(const ValueKey('video.export')));
    await tester.pumpAndSettle();

    final ledger = await backend.noteList(_board);
    expect(ledger, hasLength(before + 1),
        reason: 'the export never landed anywhere a reader can find it');
    // It is the engine's own rendering, verbatim — not a re-render.
    expect(ledger.last.text, await backend.exportNotesMarkdown(_board));
    expect(find.byKey(const ValueKey('video.export.status')), findsOneWidget);
  });

  testWidgets('a board with no timecoded notes says so instead of drawing an '
      'empty rail', (tester) async {
    final backend = FakeCyanBackend();
    await pumpFace(tester, backend, board: _bareBoard);

    expect(await rail(backend, board: _bareBoard), isEmpty);
    expect(find.byKey(const ValueKey('video.empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('video.section.ai')), findsNothing);
    expect(find.byKey(const ValueKey('video.section.human')), findsNothing);
    expect(find.byKey(const ValueKey('video.adRevenue')), findsNothing);
  });

  test('the AI answer parser is tolerant in the reference\'s exact order', () {
    // Whole-string JSON.
    expect(parseAiResponse('{"analysis":"a","priority":"high"}'),
        {'analysis': 'a', 'priority': 'high'});
    // JSON embedded in prose — the model narrating around its own answer.
    expect(parseAiResponse('Sure! {"action":"trim"} hope that helps'),
        {'action': 'trim'});
    // Nothing parseable is EMPTY, and the raw text is still readable.
    expect(parseAiResponse('no json here'), isEmpty);
    expect(cleanRawResponse('{"a": "b"}'), 'a: b');
  });

  test('the timecode formatter matches the reference', () {
    expect(formatTimecode(0), '00:00');
    expect(formatTimecode(42.5), '00:42');
    expect(formatTimecode(618), '10:18');
    expect(formatTimecode(3725), '1:02:05');
    // A surface that has not reported a position must not render "-1".
    expect(formatTimecode(-4), '00:00');
  });

  testWidgets('golden: video face', (tester) async {
    final backend = FakeCyanBackend();
    await pumpFace(tester, backend);
    await expectLater(
      find.byType(ParityVideoFace),
      matchesGoldenFile('golden/video_face.png'),
    );
  }, tags: 'golden');
}
