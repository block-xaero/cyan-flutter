// test/notes_intent_test.dart
//
// NOTES AS INTENT — the two lanes that turn words into a workflow, and the one
// landing tail they share.
//
//   • BRIEF  -> /generate   ("author a workflow with Lens")
//   • NOTES  -> /transpile  (the ledger's "Create workflow")
//
// The invariants under test are the ones that make this safe to ship:
//   1. it NEVER runs the workflow — the human presses Run;
//   2. steps land through the SAME seam call the composer uses, so the engine
//      validates them identically to hand-typed ones;
//   3. the board's effective constitution is FORWARDED, which is what lets the
//      house rules steer a draft — the with-notes / without-notes bridge;
//   4. a failure is never silent, and a cost line is never invented.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/ViewModels/NotesIntentViewModel.swift

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/lens/fake_lens_api.dart';
import 'package:cyan_flutter/lens/lens_api.dart';
import 'package:cyan_flutter/lens/lens_models.dart';
import 'package:cyan_flutter/providers/notes_intent_controller.dart';

const _board = 'b-eng-2';

/// Records what reached the engine, so "it never runs" is provable rather than
/// asserted.
class _RecordingBackend extends FakeCyanBackend {
  final List<String> authored = [];
  int compiles = 0;
  int runs = 0;

  @override
  Future<WorkflowStep?> addWorkflowStep(String boardId, String text) async {
    authored.add(text);
    return super.addWorkflowStep(boardId, text);
  }

  @override
  Future<PipelineLaunch> pipelineCompile(String boardId) async {
    compiles++;
    return super.pipelineCompile(boardId);
  }

  @override
  Future<PipelineLaunch> runPipeline(String boardId) async {
    runs++;
    return super.runPipeline(boardId);
  }
}

NotesIntentController _controller(_RecordingBackend backend, FakeLensApi lens) {
  final c =
      NotesIntentController(backend: backend, lens: lens, boardId: _board);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('a brief becomes real steps, compiled, and NOT run', () async {
    final backend = _RecordingBackend();
    final lens = FakeLensApi()
      ..draftResult = const LensDraft(steps: [
        'Ingest the dailies',
        'Transcode proxies',
      ]);
    final c = _controller(backend, lens);

    final before = (await backend.loadWorkflow(_board)).steps.length;
    expect(await c.authorFromBrief('cut the promo'), isTrue);

    // They landed through the composer's own seam call.
    expect(backend.authored, ['Ingest the dailies', 'Transcode proxies']);
    expect((await backend.loadWorkflow(_board)).steps.length, before + 2);
    expect(c.state.lastAuthoredCount, 2);

    // Compiled so the bind chips are ready…
    expect(backend.compiles, 1);
    // …and STOPPED. This is the whole safety property of the lane.
    expect(backend.runs, 0, reason: 'the lens drafts; the human presses Run');
  });

  test('the board\'s constitution is forwarded as the distiller seat',
      () async {
    // Forwarding it is what switches server-side distillation on, and it is the
    // bridge between the with-notes and without-notes paths: without notes the
    // house rules are all there is to steer by.
    final backend = _RecordingBackend();
    final lens = FakeLensApi();
    final c = _controller(backend, lens);

    await c.authorFromBrief('grade the endcard');

    final call = lens.calls.firstWhere((c) => c.method == 'generateSteps');
    final seatJson = call.args['constitution'] as String?;
    expect(seatJson, isNotNull,
        reason: 'a board with a constitution must send the seat');

    final seat = jsonDecode(seatJson!) as Map<String, dynamic>;
    expect(seat['hash'], isNotEmpty);
    expect(seat.containsKey('markdown'), isTrue);
    expect(seat.containsKey('hard'), isTrue,
        reason: 'a present `hard` is what turns distillation on');
  });

  test('transpiling notes keeps the provenance receipts', () async {
    final backend = _RecordingBackend();
    final lens = FakeLensApi()
      ..transpileResult = const LensTranspiled(
        steps: ['Conform the cut', 'Normalize to -14 LUFS'],
        irCached: true,
        bindCached: false,
        provenance: [
          'step 1 ← note editor-note',
          'step 2 ← rule tenant-loudness',
        ],
      );
    final c = _controller(backend, lens);

    expect(
        await c.authorFromNotes(['warm grade', '-14 LUFS integrated']), isTrue);

    expect(backend.authored, ['Conform the cut', 'Normalize to -14 LUFS']);
    expect(c.state.provenance, hasLength(2));
    expect(c.state.provenance.first, contains('note'));
    expect(c.state.costLine, contains('IR cached'));
    expect(backend.runs, 0);
  });

  test('a lens failure is surfaced, never silent, and lands nothing', () async {
    final backend = _RecordingBackend();
    final lens = FakeLensApi(
        failWith: const LensApiException('vLLM unreachable', statusCode: 503));
    final c = _controller(backend, lens);

    expect(await c.authorFromBrief('cut the promo'), isFalse);
    expect(c.state.error, contains('vLLM unreachable'),
        reason: 'the banner says what the LENS said, not a generic shrug');
    expect(backend.authored, isEmpty);
    expect(backend.compiles, 0);
  });

  test('an empty draft says so rather than compiling nothing', () async {
    final backend = _RecordingBackend();
    final lens = FakeLensApi()..draftResult = const LensDraft(steps: []);
    final c = _controller(backend, lens);

    expect(await c.authorFromBrief('...'), isFalse);
    expect(c.state.error, contains('no usable steps'));
    expect(backend.compiles, 0);
  });

  group('the money line', () {
    test('a cache hit leads with the saving and names the free strong model',
        () {
      final line = lensCostLine(
        const LensGenCacheFlags(spec: true, plan: true),
        const LensGenCost(
          strongMicrocents: 0,
          fastMicrocents: 250000,
          totalMicrocents: 250000,
          savedMicrocents: 1750000,
        ),
      );
      expect(line, contains('cached spec+plan'));
      expect(line, contains('saved \$0.02'));
      expect(line, contains('strong model: \$0.00'));
    });

    test('a fresh run splits the spend by rail', () {
      final line = lensCostLine(
        const LensGenCacheFlags(),
        const LensGenCost(
          strongMicrocents: 150000000,
          fastMicrocents: 50000000,
          totalMicrocents: 200000000,
        ),
      );
      expect(line, 'this draft cost \$2.00 (strong \$1.50 + fast \$0.50)');
    });

    test('no cost payload means NO LINE — never an invented number', () {
      expect(lensCostLine(const LensGenCacheFlags(spec: true), null), isNull);
    });
  });

  group('step-line parsing', () {
    test('strips numbering, bullets and fences', () {
      const raw = '```\n'
          '1. Ingest the dailies\n'
          '2) Transcode proxies\n'
          '- Publish to review\n'
          '* Notify the producer\n'
          '• Archive\n'
          '\n'
          '```';
      expect(parseStepLines(raw), [
        'Ingest the dailies',
        'Transcode proxies',
        'Publish to review',
        'Notify the producer',
        'Archive',
      ]);
    });

    test('keeps prose the model wrapped around the list', () {
      // The human gate on the Workflow face is the real filter; silently
      // dropping a line the model meant would be worse than showing it.
      expect(parseStepLines('Here are the steps:\n1. Do the thing'),
          ['Here are the steps:', 'Do the thing']);
    });
  });
}
