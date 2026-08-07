// dashboard_face_test.dart — TIER 2. The Dashboard (DAG + gated run) face,
// row 4, through the PRODUCTION seam against a real seeded engine.
//
// `loadRun` returned null unconditionally — "run hydration arrives with the
// Dashboard screen" — so against a real engine the face drew its "No run yet"
// empty state for every board, forever, including boards the engine holds a
// full pipeline snapshot for. Tier-1 could not tell: FakeCyanBackend seeds a
// run and the widget tests are happy.
//
// The Dashboard IS the pipeline snapshot seen from the run side, so `loadRun`
// now reads `cyan_pipeline_status`. This file asserts the DAG it produces
// against the engine's own seed: one node per compiled step, in order, each in
// the lane its executor puts it in.
//
//   flutter test integration_test/dashboard_face_test.dart -d windows

import 'dart:io';

import 'package:cyan_flutter/ffi/cyan_backend_ffi.dart';
import 'package:cyan_flutter/ffi/ffi_helpers.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// A silent board: four seeded steps, the last one `manual`.
const _board = 'pp-sintel-finish';
const _boardName = 'Sintel — Color & Finish';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final backend = CyanBackendFFI();

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('cyan_dashboard_');
    // Before the boot — the engine's data dir defaults to "." and would drop
    // its blob store in the repo. See tree_hydration_test.dart.
    expect(CyanFFI.setDataDir(tmp.path), isTrue);
    expect(
      CyanFFI.initWithIdentity(
        dbPath: '${tmp.path}/cyan.db',
        secretKeyHex: List.filled(64, 'd').join(),
        relayUrl: '',
        discoveryKey: 'cyan-dashboard-face-test',
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

  test('a seeded board has a run, and it is the engine\'s pipeline snapshot',
      () async {
    final run = await backend.loadRun(_board);

    expect(run, isNotNull,
        reason: 'the engine holds a pipeline snapshot for this board and the '
            'Dashboard drew "No run yet" over it');
    expect(run!.boardId, _board);
    expect(run.title, _boardName,
        reason: 'the run header names the BOARD, as the SwiftUI header does');

    // One DAG node per compiled step — the same four the Workflow face
    // authors, seen from the run side.
    final status = await backend.pipelineStatus(_board);
    expect(status.error, isNull);
    expect(run.steps, hasLength(status.totalSteps));
    expect(run.steps.map((s) => s.id).toList(),
        status.steps.map((s) => s.stepId).toList(),
        reason: 'the DAG must be the snapshot, in the snapshot\'s order');
    for (final s in run.steps) {
      expect(s.title, isNotEmpty,
          reason: 'step ${s.id} has no title — the DAG box would be blank');
    }
  });

  test('each step lands in the lane its executor puts it in', () async {
    final run = await backend.loadRun(_board);
    final status = await backend.pipelineStatus(_board);
    final byId = {for (final s in status.steps) s.stepId: s};

    for (final s in run!.steps) {
      final engine = byId[s.id]!;
      final expectHuman = engine.executor == 'manual' || engine.isReviewHold;
      expect(s.kind, expectHuman ? RunStepKind.human : RunStepKind.ai,
          reason: 'step ${s.id} runs on "${engine.executor}" (review hold: '
              '${engine.isReviewHold}) and was drawn in the wrong lane. The two '
              'lanes are what the face uses to say who is holding the run up.');
    }

    // The seed's last step is the manual `package` one, so at least one node
    // MUST be in the human lane — a mapping that put everything in one lane
    // would otherwise pass the loop above.
    expect(run.steps.map((s) => s.kind).toSet(), contains(RunStepKind.human),
        reason: 'the seeded workflow ends on a manual step; if no node is in '
            'the human lane the executor is not being read at all');
  });

  test('a board with no pipeline has no run — and says so, not "empty run"',
      () async {
    // Every group is provisioned with a Plugins workspace holding no boards, so
    // there is no seeded board without steps to ask about. An id the engine has
    // never heard of is the same question asked more sharply: nothing to draw.
    expect(await backend.loadRun('no-such-board'), isNull,
        reason: 'an unknown board must answer null so the face shows "No run '
            'yet" rather than a run with zero steps, which reads as a run that '
            'lost its work');
  });
}
