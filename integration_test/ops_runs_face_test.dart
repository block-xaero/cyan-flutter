// ops_runs_face_test.dart — TIER 2. The Ops console's Runs face, row 6, through
// the PRODUCTION seam against a real seeded engine.
//
// `loadOpsRuns` returned a const empty list, so the console showed four empty
// lanes over an engine holding ten compiled pipelines. Tier-1 could not tell:
// FakeCyanBackend seeds six runs across the lanes and the widget tests are
// happy with those.
//
// There is no tenant-wide runs verb — a run lives on its board — so the feed is
// ASSEMBLED from every board's `cyan_pipeline_status`. This file asserts the
// assembly against the engine's own seed: one card per compiled board, each in
// the lane the engine's own derived run state puts it in, and never a card for
// a board with no pipeline.
//
//   flutter test integration_test/ops_runs_face_test.dart -d windows

import 'dart:io';

import 'package:cyan_flutter/ffi/cyan_backend_ffi.dart';
import 'package:cyan_flutter/ffi/ffi_helpers.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The seed lays down ten boards, every one of them compiled.
const _seededBoards = 10;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final backend = CyanBackendFFI();
  List<OpsRun> runs = const [];

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('cyan_ops_');
    expect(CyanFFI.setDataDir(tmp.path), isTrue);
    expect(
      CyanFFI.initWithIdentity(
        dbPath: '${tmp.path}/cyan.db',
        secretKeyHex: List.filled(64, 'f').join(),
        relayUrl: '',
        discoveryKey: 'cyan-ops-runs-face-test',
      ),
      isTrue,
      reason: 'the engine refused to boot with an identity',
    );
    await backend.initialize();

    CyanFFI.seedDemo();
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      runs = await backend.loadOpsRuns();
      if (runs.length >= _seededBoards) break;
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

  test('the console shows one card per compiled board, not four empty lanes',
      () {
    expect(runs, hasLength(_seededBoards),
        reason: 'the seed compiles ten boards; the feed is assembled one '
            'pipeline snapshot at a time and came back with ${runs.length}');

    for (final r in runs) {
      expect(r.boardId, isNotEmpty,
          reason: 'a card with no board id cannot be opened from the console');
      expect(r.workflow, isNotEmpty,
          reason: 'run ${r.runId} has no workflow name — the card would be a '
              'blank poster');
      expect(r.runId, isNotEmpty);
      expect(r.stepCount, greaterThan(0),
          reason: 'a card with zero steps reads as a run that lost its work');
      expect(r.currentStep, lessThanOrEqualTo(r.stepCount),
          reason: 'run ${r.runId} reports more steps done than it has — the '
              'in-flight progress bar would overrun');
    }

    // Every card must be a DISTINCT board: an assembly bug that reused one
    // snapshot would still produce ten cards.
    expect(runs.map((r) => r.boardId).toSet(), hasLength(_seededBoards));
  });

  test('the lane is the engine\'s own derived run state, not a re-derivation',
      () async {
    for (final r in runs) {
      final status = await backend.pipelineStatus(r.boardId);
      expect(status.error, isNull);

      final expected = switch (status.status) {
        PipelineRunState.failed => RunStatus.failed,
        PipelineRunState.awaitingApproval => RunStatus.awaitingApproval,
        PipelineRunState.running || PipelineRunState.inProgress =>
          RunStatus.running,
        PipelineRunState.done => RunStatus.done,
        PipelineRunState.idle => RunStatus.queued,
      };
      expect(r.status, expected,
          reason: 'board ${r.boardId} is "${status.status}" to the engine and '
              'the console filed it under "${r.status.label}"');

      expect(r.stepCount, status.totalSteps);
      expect(r.costDollars, status.totalCostDollars);
    }

    // No card may land in the Stuck lane: the engine has no such state, and a
    // lane this side invented would be a diagnosis it never made.
    expect(runs.map((r) => r.status), isNot(contains(RunStatus.stuck)));
  });

  test('a board with no pipeline gets no card at all', () async {
    // Every seeded board is compiled, so the honest way to ask this is to
    // compare the feed against the board list: a board the feed skipped must
    // be one the engine has no snapshot for.
    final boards = await backend.loadAllBoards();
    final feed = runs.map((r) => r.boardId).toSet();
    for (final b in boards) {
      if (feed.contains(b.board.id)) continue;
      final status = await backend.pipelineStatus(b.board.id);
      expect(status.steps, isEmpty,
          reason: 'board ${b.board.id} has a pipeline the console dropped');
    }
    // …and nothing in the feed is a board that does not exist.
    expect(feed.difference(boards.map((b) => b.board.id).toSet()), isEmpty,
        reason: 'the feed invented a run for a board that is not there');
  });
}
