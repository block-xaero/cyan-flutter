// lens_contract_test.dart — the CONTRACT guard for the `LensApi` seam.
//
// There is no live lens on this box, so this suite cannot prove that cyan-lens
// serves these bytes. What it CAN prove — and what the FFI half of this port
// learned to insist on — is everything between the bytes and the face:
//
//   1. THE SHAPES. Every fixture below is the JSON `Models/LensConsole.swift`
//      and `CyanLensCloudService.swift` decode, transcribed key for key from
//      their `CodingKeys`. If the Dart decode and the Swift decode ever
//      disagree about a key, this file is where it shows up.
//
//   2. THE CONTRACT GUARD. The lens buckets `status → lane` server-side and
//      ships the `lane`; the client keeps its own copy of that mapping. The
//      point of keeping two copies is to compare them — so the feed fixture
//      carries the server's lane on every run and the test asserts the client's
//      mapping agrees, run by run.
//
//   3. THE TOLERANCE. `retry` arrives as a JSON bool from today's lens and as
//      an int from an older one; on the Swift side that mismatch threw the
//      ENTIRE trace decode and the drill-down spun forever. Identity is
//      required, every metric is optional, an unknown status parks rather than
//      throws. Each of those is a test, because each of them was a bug.
//
//   4. THE WIRE ITSELF. `LensApiHttp` is driven against a real loopback
//      `HttpServer` that records what it was asked for. That is how the
//      endpoints, the query params, the bearer and the `{success,data,error}`
//      envelope are proved without a lens — the same trick that would have
//      caught the FFI arity drift a year earlier.
//
// Tier-2 (a real lens answering these routes) belongs to the Mac session.

import 'dart:convert';
import 'dart:io';

import 'package:cyan_flutter/lens/lens_api.dart';
import 'package:cyan_flutter/lens/lens_models.dart';
import 'package:cyan_flutter/lens/lens_rollups.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// The recorded shapes — transcribed from the Swift CodingKeys
// ---------------------------------------------------------------------------

/// One `run_summary_json` row with the full §2/§3/§4 metering surface, exactly
/// as `RunSummary`'s CodingKeys spell it.
const Map<String, dynamic> kRunSummaryJson = {
  'run_id': 'run-7f3a',
  'tenant_id': 'g-eng',
  'board_id': 'b-eng-1',
  'status': 'Done',
  'lane': 'done',
  'step_count': 3,
  'current_step_index': 3,
  'attempts': 1,
  'created_at': 1786104000000,
  'started_at': 1786104010000,
  'updated_at': 1786104130000,
  'finished_at': 1786104130000,
  'error_class': null,
  'deadline_at': null,
  'gpu_seconds': 42.5,
  'cost_cents': 310.0,
  'asset': 'big buck bunny.mp4',
  'step_done': 3,
  'step_total': 3,
  'wall_ms': 120000,
  'billed_minutes': 9.6,
  'billed_cents': 288.0,
  'retry_minutes': 0.0,
  'cache_saved_minutes': 3.2,
  'steps': [
    {
      'step_index': 0,
      'step_id': 'run-7f3a:0',
      'action': 'transcode',
      'actor': 'agent',
      'status': 'ok',
      'step_status': 'Done',
      'attempt': 1,
      'idempotent_skipped': false,
      'idempotency_key': 'idem-0',
      // TODAY's lens: the §3 retry FLAG, a JSON bool.
      'retry': false,
      'error_class': null,
      'tokens_in': 120,
      'tokens_out': 80,
      'gpu_ms': 30000,
      'gpu_seconds': 30.0,
      'gpu_cost_cents': 200.0,
      'cost_cents': 210,
      'started_at': 1786104010000,
      'finished_at': 1786104070000,
      'wall_ms': 60000,
      'asset_minutes': 6.4,
      'billed_minutes': 6.4,
      'billed_cents': 192.0,
      'exec_ms': 60000,
      'approval_wait_ms': 0,
      'cache_hit': false,
    },
    {
      'step_index': 1,
      'step_id': 'run-7f3a:1',
      'action': 'qc',
      'step_status': 'Skipped',
      'attempt': 1,
      'idempotent_skipped': true,
      'cache_hit': true,
      'asset_minutes': 3.2,
      'billed_minutes': 0.0,
      'billed_cents': 0.0,
      'exec_ms': 120,
    },
    {
      'step_index': 2,
      'step_id': 'run-7f3a:2',
      'action': 'deliver',
      'actor': 'human',
      'step_status': 'Done',
      'attempt': 1,
      'asset_minutes': 3.2,
      'billed_minutes': 3.2,
      'billed_cents': 96.0,
      'exec_ms': 59000,
      'approval_wait_ms': 3540000,
    },
  ],
};

/// The `/api/v1/runs` board feed — `lanes` + `counts` + the additive top-level
/// hints. One run per lane, each carrying the SERVER's own `lane`.
Map<String, dynamic> runFeedJson() => {
      'board_id': 'b-eng-1',
      'lanes': {
        'incoming': [
          _row('run-q', 'Queued', 'incoming'),
        ],
        'in_flight': [
          _row('run-r', 'Running', 'in_flight'),
          // A Stuck run lanes to In-flight — NOT Failed. The lens says so and
          // the client must agree.
          _row('run-s', 'Stuck', 'in_flight'),
        ],
        'approval': [
          _row('run-a', 'AwaitingApproval', 'approval'),
        ],
        'done': [kRunSummaryJson],
        'failed': [
          _row('run-f', 'Failed', 'failed', errorClass: 'conform_mismatch'),
        ],
      },
      'counts': {
        'incoming': 1,
        'in_flight': 2,
        'approval': 1,
        'done': 9,
        'failed': 1,
        'action_needed': 5,
      },
      'total': 14,
      'action_needed': [
        _row('run-a', 'AwaitingApproval', 'approval'),
      ],
      'current_asset': 'big buck bunny.mp4',
      'next_asset': 'trailer-cut-04.mov',
    };

Map<String, dynamic> _row(String id, String status, String lane,
        {String? errorClass}) =>
    {
      'run_id': id,
      'tenant_id': 'g-eng',
      'board_id': 'b-eng-1',
      'status': status,
      'lane': lane,
      'step_count': 2,
      'current_step_index': 1,
      'attempts': 1,
      'created_at': 1786104000000,
      'updated_at': 1786104000000,
      if (errorClass != null) 'error_class': errorClass,
    };

void main() {
  // -------------------------------------------------------------------------
  group('the recorded run-summary shape', () {
    test('decodes every key the Swift RunSummary declares', () {
      final r = RunSummary.fromJson(kRunSummaryJson);

      expect(r.runId, 'run-7f3a');
      expect(r.tenantId, 'g-eng');
      expect(r.boardId, 'b-eng-1');
      expect(r.status, RunStatusValue.done);
      expect(r.lane, RunLane.done);
      expect(r.stepCount, 3);
      expect(r.currentStepIndex, 3);
      expect(r.attempts, 1);
      expect(r.createdAt, 1786104000000);
      expect(r.startedAt, 1786104010000);
      expect(r.updatedAt, 1786104130000);
      expect(r.finishedAt, 1786104130000);
      expect(r.errorClass, isNull);
      expect(r.deadlineAt, isNull);
      expect(r.gpuSeconds, 42.5);
      expect(r.costCents, 310.0);
      expect(r.asset, 'big buck bunny.mp4');
      expect(r.stepDone, 3);
      expect(r.stepTotal, 3);
      expect(r.wallMs, 120000);
      expect(r.billedMinutes, 9.6);
      expect(r.billedCents, 288.0);
      expect(r.retryMinutes, 0.0);
      expect(r.cacheSavedMinutes, 3.2);
      expect(r.steps, hasLength(3));
    });

    test('durations are read as epoch MILLISECONDS, not seconds', () {
      final r = RunSummary.fromJson(kRunSummaryJson);
      // finished − started = 120_000 ms = 120 s = 2:00. Treating the stamps as
      // seconds is what produced the 1109:35 garbage on the Swift side.
      expect(r.durationSeconds, 120.0);
      expect(r.durationTimecode, '2:00');
    });

    test('a run with no finishedAt has no duration — never elapsed-since-start',
        () {
      final r = RunSummary.fromJson(_row('run-r', 'Running', 'in_flight'));
      expect(r.durationSeconds, isNull);
      expect(r.durationTimecode, '—');
    });

    test('the customer bill is asset-minutes, and GPU is never it', () {
      final r = RunSummary.fromJson(kRunSummaryJson);
      expect(r.hasAssetMeter, isTrue);
      expect(r.billedMinutesLabel, '9.6');
      expect(r.billedDollars, r'$2.88');
      // GPU rides on the same row and is NOT the bill.
      expect(r.costDollars, r'$3.10');
    });

    test('an unmetered run says "—" rather than showing a zero bill', () {
      final r = RunSummary.fromJson(_row('run-q', 'Queued', 'incoming'));
      expect(r.hasAssetMeter, isFalse);
      expect(r.billedMinutesLabel, '—');
      expect(r.billedDollars, isNull);
      expect(r.costDollars, '—');
    });

    test('the thumbnail URL query-encodes an asset name with spaces', () {
      final r = RunSummary.fromJson(kRunSummaryJson);
      final url = r.thumbnailUrl('http://lens:8080');
      expect(url, isNotNull);
      expect(url!.path, '/api/v1/media/thumbnail');
      expect(url.queryParameters['asset'], 'big buck bunny.mp4');
      // A raw space would break the request line.
      expect(url.toString(), isNot(contains(' ')));
    });

    test('a summary with no run_id is CORRUPT and throws — a blank card would '
        'be a lie the caller could not see', () {
      expect(() => RunSummary.fromJson(const {'status': 'Done'}),
          throwsA(isA<LensDecodeException>()));
    });
  });

  // -------------------------------------------------------------------------
  group('the status → lane contract guard', () {
    test('the client mapping agrees with the SERVER lane on every run', () {
      final feed = RunBoardFeed.fromJson(runFeedJson());
      expect(feed.allRuns, hasLength(6));
      for (final run in feed.allRuns) {
        expect(run.status.lane, run.lane,
            reason: 'the client and the lens disagree about where '
                '${run.runId} (${run.status.wire}) belongs — one of the two '
                'mappings has drifted');
      }
    });

    test('re-bucketing the flat list reproduces the server lanes exactly', () {
      final served = RunBoardFeed.fromJson(runFeedJson());
      final rebucketed =
          RunBoardFeed.assembled(boardId: 'b-eng-1', runs: served.allRuns);
      for (final lane in RunLane.values) {
        expect(
          [for (final r in rebucketed.runsIn(lane)) r.runId],
          [for (final r in served.runsIn(lane)) r.runId],
          reason: 'lane ${lane.wire} re-bucketed differently than the lens '
              'bucketed it',
        );
      }
    });

    test('Stuck lanes to In-flight, not Failed — a stall is not a break', () {
      expect(RunStatusValue.stuck.lane, RunLane.inFlight);
    });

    test('an UNKNOWN status stays visible in In-flight instead of vanishing',
        () {
      final r = RunSummary.fromJson(const {
        'run_id': 'run-new',
        'status': 'SomeStatusThisClientHasNeverHeardOf',
      });
      expect(r.status, RunStatusValue.unknown);
      expect(r.status.lane, RunLane.inFlight);
      // …and on the board wall it reads as a live run, not as "—".
      expect(r.status.badgeLabel, 'Running');
    });

    test('only Failed offers Retry and only AwaitingApproval offers a gate',
        () {
      expect(RunStatusValue.failed.canRetry, isTrue);
      expect(RunStatusValue.awaitingApproval.canApprove, isTrue);
      for (final s in RunStatusValue.values) {
        if (s != RunStatusValue.failed) expect(s.canRetry, isFalse);
        if (s != RunStatusValue.awaitingApproval) {
          expect(s.canApprove, isFalse);
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('the board feed', () {
    test('counts are the SERVER\'s, not a tally of the loaded cards', () {
      final feed = RunBoardFeed.fromJson(runFeedJson());
      // 9 done runs exist; the feed shipped 1 card for that lane.
      expect(feed.done, hasLength(1));
      expect(feed.counts.done, 9);
      expect(feed.total, 14);
      expect(feed.counts.actionNeeded, 5);
    });

    test('approvalRuns prefers the top-level action_needed hint', () {
      final feed = RunBoardFeed.fromJson(runFeedJson());
      expect([for (final r in feed.approvalRuns) r.runId], ['run-a']);
      expect(feed.currentAsset, 'big buck bunny.mp4');
      expect(feed.nextAsset, 'trailer-cut-04.mov');
    });

    test('leadRun is the human gate first — approval outranks everything', () {
      final feed = RunBoardFeed.fromJson(runFeedJson());
      expect(feed.leadRun?.runId, 'run-a');
    });

    test('workflowSteps reads the WORKFLOW progress, not one run\'s 1/1', () {
      final feed = RunBoardFeed.fromJson(runFeedJson());
      final steps = feed.workflowSteps;
      expect(steps.total, 3);
      expect(steps.done, 3);
    });

    test('an assembled feed drops nothing — every run lands in exactly one lane',
        () {
      final runs = RunBoardFeed.fromJson(runFeedJson()).allRuns;
      final feed = RunBoardFeed.assembled(boardId: 'b', runs: runs);
      expect(feed.total, runs.length);
      expect(feed.allRuns, hasLength(runs.length));
    });
  });

  // -------------------------------------------------------------------------
  group('BoardRunState — "we have not heard" is not "there is nothing"', () {
    test('a NULL feed claims nothing at all', () {
      final state = BoardRunState.fromFeed(null);
      expect(state, isA<BoardRunUnknown>());
      expect(state.label, isNull,
          reason: 'a lens outage would repaint the whole wall as empty');
    });

    test('a feed that ARRIVED and is empty earns "No runs yet"', () {
      final state = BoardRunState.fromFeed(
          RunBoardFeed.assembled(boardId: 'b', runs: const []));
      expect(state, isA<BoardRunNone>());
      expect(state.label, 'No runs yet');
    });

    test('a feed with runs reports its lead run\'s status', () {
      final state =
          BoardRunState.fromFeed(RunBoardFeed.fromJson(runFeedJson()));
      expect(state, isA<BoardRunActive>());
      expect(state.label, 'Needs approval');
    });
  });

  // -------------------------------------------------------------------------
  group('the tolerant step decode', () {
    Map<String, dynamic> step(Object? retry) => {
          'step_index': 0,
          'step_id': 's0',
          'action': 'conform',
          if (retry != null) 'retry': retry,
        };

    test('`retry` as a BOOL (today\'s lens) decodes to 1/0', () {
      expect(RunStepDetail.fromJson(step(true)).retry, 1);
      expect(RunStepDetail.fromJson(step(false)).retry, 0);
    });

    test('`retry` as an INT (an older lens) decodes as-is — the type mismatch '
        'that used to throw the whole trace', () {
      expect(RunStepDetail.fromJson(step(3)).retry, 3);
    });

    test('a step with nothing but its identity decodes cleanly', () {
      final s = RunStepDetail.fromJson(const {
        'step_index': 4,
        'step_id': 'run:4',
      });
      expect(s.stepIndex, 4);
      expect(s.displayStatus, '—');
      expect(s.execMsComputed, isNull);
      expect(s.isFailure, isFalse);
      expect(s.isCacheHit, isFalse);
      expect(s.billedMinutesValue, isNull);
    });

    test('a step with NO identity throws — that record is genuinely corrupt',
        () {
      expect(() => RunStepDetail.fromJson(const {'action': 'conform'}),
          throwsA(isA<LensDecodeException>()));
    });

    test('exec falls back to the computed wall when exec_ms is absent', () {
      final s = RunStepDetail.fromJson(const {
        'step_index': 0,
        'step_id': 's0',
        'started_at': 1000,
        'finished_at': 4200,
      });
      expect(s.wallMsComputed, 3200);
      expect(s.execMsComputed, 3200);
    });

    test('a cache hit is inferred from the idempotent skip the lens already '
        'emits', () {
      final s = RunStepDetail.fromJson(const {
        'step_index': 0,
        'step_id': 's0',
        'idempotent_skipped': true,
      });
      expect(s.isCacheHit, isTrue);
      expect(s.billedMinutesValue, 0);
    });

    test('a failure is keyed on step_status — error_class alone is not one',
        () {
      final labelled = RunStepDetail.fromJson(const {
        'step_index': 0,
        'step_id': 's0',
        'step_status': 'Done',
        'error_class': 'idempotent_replay',
      });
      expect(labelled.isFailure, isFalse,
          reason: 'a non-failure error_class would inflate the failure rate');
      final real = RunStepDetail.fromJson(const {
        'step_index': 1,
        'step_id': 's1',
        'step_status': 'Failed',
      });
      expect(real.isFailure, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('the run trace', () {
    Map<String, dynamic> traceJson() => {
          'run_id': 'run-7f3a',
          'tenant_id': 'g-eng',
          'status': 'Done',
          'lane': 'done',
          'attempts': 1,
          'current_step_index': 3,
          'created_at': 1786104000000,
          'started_at': 1786104010000,
          'updated_at': 1786104130000,
          'finished_at': 1786104130000,
          'run_error_class': null,
          'deadline_at': null,
          'steps': kRunSummaryJson['steps'],
          'step_count': 3,
          'total_tokens_in': 120,
          'total_tokens_out': 80,
          'total_gpu_ms': 30000,
          'total_gpu_seconds': 30.0,
          'total_gpu_cost_cents': 200.0,
          'total_gpu_price_cents': 400.0,
          'total_cost_cents': 310,
          'total_price_cents': 620.0,
          'bottleneck_step_index': 0,
        };

    test('decodes every key the Swift RunTrace declares', () {
      final t = RunTrace.fromJson(traceJson());
      expect(t.runId, 'run-7f3a');
      expect(t.status, RunStatusValue.done);
      expect(t.lane, RunLane.done);
      expect(t.steps, hasLength(3));
      expect(t.stepCount, 3);
      expect(t.totalGpuSeconds, 30.0);
      expect(t.totalPriceCents, 620.0);
      expect(t.bottleneckStep?.stepId, 'run-7f3a:0');
    });

    test('the §4 invariant holds: Σ step billed == the run rollup', () {
      final t = RunTrace.fromJson(traceJson());
      // 6.4 + 0 (cache hit) + 3.2 — the served totals are absent here, so the
      // rollup MUST come out of the step records.
      expect(t.totalBilledMinutes, isNull);
      expect(t.billedMinutesRollup, closeTo(9.6, 1e-9));
      expect(t.billedCentsRollup, closeTo(288.0, 1e-9));
      expect(t.billedDollarsRollup, r'$2.88');
      // …and it agrees with what the SUMMARY reported for the same run.
      final summary = RunSummary.fromJson(kRunSummaryJson);
      expect(t.billedMinutesRollup, closeTo(summary.billedMinutes!, 1e-9));
    });

    test('a served total WINS over the sum — the lens reconciles, we do not '
        'second-guess it', () {
      final t = RunTrace.fromJson({
        ...traceJson(),
        'total_billed_minutes': 11.0,
        'total_billed_cents': 330.0,
      });
      expect(t.billedMinutesRollup, 11.0);
      expect(t.billedDollarsRollup, r'$3.30');
    });
  });

  // -------------------------------------------------------------------------
  group('the §4 asset-minute rollup', () {
    test('sums the customer bill and keeps GPU as internal COGS', () {
      final feed = RunBoardFeed.fromJson(runFeedJson());
      final meter = AssetMeterRollup(feed.allRuns);
      expect(meter.runCount, 6);
      expect(meter.hasMeter, isTrue);
      expect(meter.billedMinutes, closeTo(9.6, 1e-9));
      expect(meter.billedDollars, r'$2.88');
      expect(meter.cacheSavedMinutes, closeTo(3.2, 1e-9));
      expect(meter.cacheSavedLabel, '3.2');
      // GPU is summed, but it is NOT what billedDollars reports.
      expect(meter.gpuSeconds, closeTo(42.5, 1e-9));
    });

    test('an entirely unmetered scope says "—", never a confident zero', () {
      final meter = AssetMeterRollup([
        RunSummary.fromJson(_row('run-q', 'Queued', 'incoming')),
      ]);
      expect(meter.hasMeter, isFalse);
      expect(meter.billedMinutesLabel, '—');
      expect(meter.billedDollars, '—');
      expect(meter.retryMinutesLabel, '—');
    });

    test('workflow-minutes ceil ONCE at the total, not per run', () {
      // Three sub-minute runs: per-run ceiling would bill 3 minutes for 1.5.
      final runs = [
        for (var i = 0; i < 3; i++)
          RunSummary(
            runId: 'run-$i',
            boardId: 'b',
            status: RunStatusValue.done,
            createdAt: 0,
            startedAt: 0,
            finishedAt: 30000,
            wallMs: 30000,
          ),
      ];
      final meter = AssetMeterRollup(runs);
      expect(meter.totalWallMs, 90000);
      expect(meter.workflowMinutes, closeTo(1.5, 1e-9));
      expect(meter.workflowMinutesCeil, 2,
          reason: 'per-run rounding would report 3 minutes for 90 seconds');
    });

    test('a never-finished run contributes ZERO wall — elapsed-since-start is '
        'not compute time', () {
      final meter = AssetMeterRollup([
        RunSummary.fromJson(_row('run-r', 'Running', 'in_flight')),
      ]);
      expect(meter.totalWallMs, 0);
      expect(meter.workflowMinutesCeil, 0);
    });

    test('byWorkflow groups by board, heaviest bill first', () {
      final rows = AssetMeterRollup.byWorkflow([
        RunSummary.fromJson(kRunSummaryJson), // b-eng-1, 9.6 min
        const RunSummary(
            runId: 'x', boardId: 'b-eng-2', billedMinutes: 20, billedCents: 600),
        const RunSummary(runId: 'y', boardId: 'b-eng-3'),
      ]);
      expect([for (final r in rows) r.boardId],
          ['b-eng-2', 'b-eng-1', 'b-eng-3']);
      expect(rows.first.meter.billedDollars, r'$6.00');
      expect(rows.last.meter.hasMeter, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('the §5 efficiency rollup', () {
    test('rolls up from the feed\'s nested steps — no per-run trace fetch', () {
      final feed = RunBoardFeed.fromJson(runFeedJson());
      final eff = EfficiencyRollup.fromRuns(feed.allRuns);
      expect(eff.runCount, 6);
      expect([for (final s in eff.steps) s.id], ['transcode', 'qc', 'deliver']);
      expect(eff.hasApprovalData, isTrue);
    });

    test('the feed rollup and the trace rollup RECONCILE — same §3 records', () {
      final summary = RunSummary.fromJson(kRunSummaryJson);
      final fromFeed = EfficiencyRollup.fromRuns([summary]);
      final fromTrace = EfficiencyRollup.fromTraces([
        RunTrace(runId: summary.runId, steps: summary.steps!),
      ]);
      expect(fromTrace.steps.length, fromFeed.steps.length);
      for (var i = 0; i < fromFeed.steps.length; i++) {
        expect(fromTrace.steps[i].id, fromFeed.steps[i].id);
        expect(fromTrace.steps[i].execP95Ms, fromFeed.steps[i].execP95Ms);
        expect(fromTrace.steps[i].cacheHitRate, fromFeed.steps[i].cacheHitRate);
      }
      expect(fromTrace.totalMinutesSaved, fromFeed.totalMinutesSaved);
    });

    test('the gate bottleneck is the step humans sit on longest', () {
      final eff = EfficiencyRollup.fromRuns(
          [RunSummary.fromJson(kRunSummaryJson)]);
      expect(eff.gateBottleneck?.id, 'deliver');
      // 3_540_000ms = 59 minutes. The formatter only reaches for hours PAST 60
      // minutes, so a 59-minute stall reads "59m" — same threshold as Swift's.
      expect(MeterFormat.duration(eff.gateBottleneck!.approvalWaitP95Ms), '59m');
    });

    test('a cache hit is billed 0 and counted as minutes saved', () {
      final eff = EfficiencyRollup.fromRuns(
          [RunSummary.fromJson(kRunSummaryJson)]);
      final qc = eff.steps.firstWhere((s) => s.id == 'qc');
      expect(qc.cacheHitRate, 1.0);
      expect(qc.minutesSaved, closeTo(3.2, 1e-9));
      expect(eff.totalMinutesSaved, closeTo(3.2, 1e-9));
      expect(MeterFormat.percent(eff.overallCacheHitRate), '33%');
    });

    test('executions of the same authored step group across runs', () {
      final a = RunSummary.fromJson(kRunSummaryJson);
      final eff = EfficiencyRollup.fromRuns([a, a]);
      expect(eff.steps, hasLength(3));
      expect(eff.steps.first.executions, 2);
    });

    test('the top error class is the most FREQUENT one, not the last seen', () {
      RunSummary failing(String id, List<String> classes) => RunSummary(
            runId: id,
            steps: [
              for (var i = 0; i < classes.length; i++)
                RunStepDetail(
                  stepIndex: i,
                  stepId: '$id:$i',
                  action: 'conform',
                  stepStatus: 'Failed',
                  errorClass: classes[i],
                ),
            ],
          );
      final eff = EfficiencyRollup.fromRuns([
        failing('r1', ['disk_full', 'conform_mismatch', 'conform_mismatch']),
      ]);
      final conform = eff.steps.single;
      expect(conform.failureRate, 1.0);
      expect(conform.topErrorClass, 'conform_mismatch');
    });

    test('p95 is NEAREST-RANK and clamps — 1 sample is its own p95', () {
      expect(EfficiencyRollup.p95(const []), isNull);
      expect(EfficiencyRollup.p95(const [42]), 42);
      expect(EfficiencyRollup.p95(List.generate(100, (i) => i + 1)), 95);
      expect(EfficiencyRollup.p95(const [5, 1, 3]), 5);
    });

    test('an empty scope rolls up to empty rather than to zeros with a claim',
        () {
      final eff = EfficiencyRollup.fromRuns(const []);
      expect(eff.steps, isEmpty);
      expect(eff.hasApprovalData, isFalse,
          reason: '"0ms of gate wait" and "no gate data" are not the same '
              'claim, and the table shows "—" for the second');
    });

    test('MeterFormat spans milliseconds to hours in one formatter', () {
      expect(MeterFormat.duration(null), '—');
      expect(MeterFormat.duration(0), '—');
      expect(MeterFormat.duration(820), '820ms');
      expect(MeterFormat.duration(4200), '4.2s');
      expect(MeterFormat.duration(360000), '6.0m');
      expect(MeterFormat.duration(9000000), '2.5h');
      expect(MeterFormat.percent(0.125), '13%');
    });
  });

  // -------------------------------------------------------------------------
  group('the envelope', () {
    test('a `{success,data,error}` body unwraps to its data', () {
      final e = LensEnvelope.of(jsonDecode('{"success":true,"data":{"a":1}}'));
      expect(e.success, isTrue);
      expect(e.data, const {'a': 1});
    });

    test('a BARE payload (the /runs family) passes straight through', () {
      final e = LensEnvelope.of(jsonDecode('{"board_id":"b","total":0}'));
      expect(e.success, isTrue);
      expect((e.data as Map)['board_id'], 'b');
    });

    test('`success:false` carries the lens\'s own reason', () {
      final e =
          LensEnvelope.of(jsonDecode('{"success":false,"error":"no tenant"}'));
      expect(e.success, isFalse);
      expect(e.error, 'no tenant');
    });

    test('the COMMAND replies carry a `success` of their own — which is why the '
        'family is declared at the call site and never sniffed', () {
      // `{success, run}` from /retry and `{success, decision, …, run}` from
      // /approve both look exactly like an envelope to a key sniff, and would
      // unwrap to a null `data`. This is the shape that broke it once.
      final retryBody = {'success': true, 'run': kRunSummaryJson};
      final sniffed = LensEnvelope.of(retryBody);
      expect(sniffed.data, isNull,
          reason: 'a sniff finds no `data` here and throws the reply away — '
              'the /runs family must decode BARE');
      // Decoded as the reply it actually is, the run survives.
      expect(RetryReply.fromJson(retryBody).run.runId, 'run-7f3a');
    });
  });

  // -------------------------------------------------------------------------
  // The wire itself — LensApiHttp against a recording loopback server.
  // -------------------------------------------------------------------------
  group('LensApiHttp on the wire', () {
    late HttpServer server;
    late List<HttpRequest> seen;
    late List<String> bodies;
    late LensApiHttp api;
    // What the next request is answered with.
    late int replyStatus;
    late String replyBody;

    setUp(() async {
      seen = [];
      bodies = [];
      replyStatus = 200;
      replyBody = '{}';
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        seen.add(req);
        bodies.add(await utf8.decoder.bind(req).join());
        req.response.statusCode = replyStatus;
        req.response.headers.contentType = ContentType.json;
        req.response.write(replyBody);
        await req.response.close();
      });
      api = LensApiHttp(
        config: LensConfig(
          baseUrl: 'http://${server.address.address}:${server.port}',
          tokenProvider: () => 'tok-abc',
          groupId: 'g-eng',
        ),
        timeout: const Duration(seconds: 5),
      );
    });

    tearDown(() async => server.close(force: true));

    test('a TENANT-WIDE feed omits the board param entirely', () async {
      replyBody = jsonEncode(runFeedJson());
      final feed = await api.runs(limit: 25);
      expect(feed.total, 14);
      expect(seen.single.uri.path, '/api/v1/runs');
      expect(seen.single.uri.queryParameters['limit'], '25');
      expect(seen.single.uri.queryParameters.containsKey('board'), isFalse,
          reason: 'an empty board param is a DIFFERENT request from no board '
              'param, and the lens scopes on the difference');
    });

    test('a per-board feed attaches board + status', () async {
      replyBody = jsonEncode(runFeedJson());
      await api.runs(
          board: 'b-eng-1', status: RunStatusValue.awaitingApproval, limit: 50);
      final q = seen.single.uri.queryParameters;
      expect(q['board'], 'b-eng-1');
      expect(q['status'], 'AwaitingApproval');
    });

    test('every request carries the bearer, and the bearer is never in the URL',
        () async {
      replyBody = jsonEncode(runFeedJson());
      await api.runs();
      expect(seen.single.headers.value('authorization'), 'Bearer tok-abc');
      expect(seen.single.uri.toString(), isNot(contains('tok-abc')));
    });

    test('an EMPTY session token falls back to the dev bearer — a request with '
        'no bearer 403s into a false "0 runs"', () async {
      final anon = LensApiHttp(
        config: LensConfig(
          baseUrl: 'http://${server.address.address}:${server.port}',
          tokenProvider: () => null,
        ),
      );
      replyBody = jsonEncode(runFeedJson());
      await anon.runs();
      expect(seen.single.headers.value('authorization'),
          'Bearer ${LensConfig.devToken}');
    });

    test('the drill-down hits /runs/{id} with the id path-encoded', () async {
      replyBody = jsonEncode({'run_id': 'a/b', 'steps': <dynamic>[]});
      await api.run('a/b');
      expect(seen.single.uri.path, '/api/v1/runs/a%2Fb',
          reason: 'an unencoded id would split the route');
    });

    test('retry POSTs and returns the re-queued summary', () async {
      replyBody = jsonEncode({
        'success': true,
        'run': _row('run-f', 'Queued', 'incoming'),
      });
      final run = await api.retry('run-f');
      expect(seen.single.method, 'POST');
      expect(seen.single.uri.path, '/api/v1/runs/run-f/retry');
      expect(run.status, RunStatusValue.queued);
    });

    test('approve and reject are SEPARATE routes, and step_id rides only when '
        'known', () async {
      replyBody = jsonEncode({
        'success': true,
        'decision': 'approve',
        'step_id': 's2',
        'step_status': 'Done',
        'run': _row('run-a', 'Queued', 'incoming'),
      });
      await api.approve('run-a', step: 's2');
      expect(seen.last.uri.path, '/api/v1/runs/run-a/approve');
      expect(jsonDecode(bodies.last), const {'step_id': 's2'});

      replyBody = jsonEncode({
        'success': true,
        'decision': 'reject',
        'step_id': '',
        'step_status': 'Failed',
        'run': _row('run-a', 'Failed', 'failed'),
      });
      await api.reject('run-a');
      expect(seen.last.uri.path, '/api/v1/runs/run-a/reject');
      expect(jsonDecode(bodies.last), const <String, dynamic>{},
          reason: 'with no step id the LENS resolves the parked gate');
    });

    test('a reply with success:false is a REFUSAL, not a success', () async {
      replyBody = jsonEncode({
        'success': false,
        'run': _row('run-f', 'Failed', 'failed'),
      });
      await expectLater(api.retry('run-f'),
          throwsA(isA<LensApiException>().having(
              (e) => e.message, 'message', 'retry rejected')));
    });

    test('a non-200 surfaces the lens\'s plain-text reason, never the bearer',
        () async {
      replyStatus = 409;
      replyBody = 'CONFLICT only a Failed run can be retried';
      await expectLater(
        api.retry('run-r'),
        throwsA(isA<LensApiException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.message, 'message', contains('only a Failed run'))
            .having((e) => e.message, 'message', isNot(contains('tok-abc')))),
      );
    });

    test('marketplace browse relays q/aisle/limit and unwraps {cards:[…]}',
        () async {
      replyBody = jsonEncode({
        'success': true,
        'data': {
          'cards': [
            {
              'plugin_id': 'cyan.transcode',
              'name': 'Transcode',
              'description': 'Normalize any master.',
              'tool_summary': ['transcode'],
              'trust': 'trusted',
              'source': 'curated',
              'featured': true,
              'stage': 'delivery',
            }
          ],
          'curated_status': 'ok',
        }
      });
      final cards = await api.browseMarketplace(
          const StorefrontQuery(text: 'trans', aisle: 'delivery', limit: 10));
      final q = seen.single.uri.queryParameters;
      expect(seen.single.uri.path, '/api/v1/marketplace/browse');
      expect(q['q'], 'trans');
      expect(q['aisle'], 'delivery');
      expect(q['limit'], '10');
      expect(cards, hasLength(1));
      expect(cards.single.pluginId, 'cyan.transcode');
      expect(cards.single.isTrusted, isTrue);
      expect(cards.single.stage, 'delivery');
      expect(cards.single.featured, isTrue);
    });

    test('a marketplace card whose trust the client does not know is UNTRUSTED',
        () async {
      replyBody = jsonEncode({
        'success': true,
        'data': {
          'cards': [
            {'plugin_id': 'io.github.someone/thing', 'source': 'public'}
          ]
        }
      });
      final cards = await api.browseMarketplace(const StorefrontQuery());
      expect(cards.single.isTrusted, isFalse,
          reason: 'the client never widens a trust the server owns');
      expect(cards.single.isPublicRegistry, isTrue);
    });

    test('nudges / asks / decisions are scoped by the GROUP path segment',
        () async {
      replyBody = jsonEncode({
        'success': true,
        'data': {
          'group_id': 'g-eng',
          'generated_at': 1786104000,
          'nudges': [
            {
              'nudge_type': 'stale_ask',
              'question': 'Which LUT ships?',
              'age_hours': 30,
              'ask_id': 'ask-1',
            }
          ],
          'summary': {
            'stale_asks': 1,
            'stale_blockers': 0,
            'unimplemented_decisions': 0,
          },
        }
      });
      final report = await api.nudges();
      expect(seen.last.uri.path, '/api/v1/nudges/g-eng');
      expect(report.totalCount, 1);
      final n = report.nudges.single;
      expect(n.id, 'ask-1');
      expect(n.title, 'Stale Question');
      expect(n.detail, 'Which LUT ships?');
      expect(n.ageText, '1d');

      replyBody = jsonEncode({
        'success': true,
        'data': {
          'asks': [
            {
              'id': 'ask-1',
              'source_node_id': 'node-1',
              'group_id': 'g-eng',
              'content': 'Which LUT ships?',
              'asker_name': 'Dana',
              'assignee_name': 'Rick',
              'status': 'open',
              'created_at': 1786000000,
            }
          ]
        }
      });
      final asks = await api.asks(limit: 20);
      expect(seen.last.uri.path, '/api/v1/asks/g-eng');
      expect(seen.last.uri.queryParameters['limit'], '20');
      expect(asks.single.askerName, 'Dana');
      expect(asks.single.ageText(1786000000 + 7200), '2h ago');
      expect(asks.single.ageText(1786000000 + 172800), '2d ago');

      replyBody = jsonEncode({
        'success': true,
        'data': {
          'decisions': [
            {
              'id': 'dec-1',
              'source_node_id': 'node-2',
              'group_id': 'g-eng',
              'content': '4K HDR only.',
              'decider_name': 'Rick',
              'rationale': 'SDR cost more in retries.',
              'created_at': 1786000000,
            }
          ]
        }
      });
      final decisions = await api.decisions();
      expect(seen.last.uri.path, '/api/v1/decisions/g-eng');
      expect(decisions.single.deciderName, 'Rick');
      expect(decisions.single.rationale, 'SDR cost more in retries.');
    });

    test('health tolerates the live lens dropping iggy and adding commit — a '
        'strict decode showed "Disconnected" over a live lens', () async {
      replyBody = jsonEncode({
        'success': true,
        'data': {
          'postgres': true,
          'vllm': true,
          'lens': true,
          'commit': 'deadbeef',
        }
      });
      final h = await api.health();
      expect(h.isHealthy, isTrue);
      expect(h.statusText, 'Connected');
      expect(h.iggy, isNull);
      expect(h.commit, 'deadbeef');
    });

    test('a lens with its DB down names the leg that is down', () async {
      replyBody = jsonEncode({
        'success': true,
        'data': {'postgres': false, 'vllm': true, 'lens': true}
      });
      final h = await api.health();
      expect(h.isHealthy, isFalse);
      expect(h.statusText, 'DB down');
    });

    test('the ask/decision writes use the methods the lens routes on',
        () async {
      replyBody = jsonEncode({'success': true, 'data': {}});
      await api.answerAsk('ask-1',
          answer: 'Patch the mix.', answererId: 'x1', answererName: 'Dana');
      expect(seen.last.method, 'PATCH');
      expect(seen.last.uri.path, '/api/v1/asks/ask-1/answer');
      expect(jsonDecode(bodies.last), const {
        'answer': 'Patch the mix.',
        'answerer_id': 'x1',
        'answerer_name': 'Dana',
      });

      await api.dismissAsk('ask-1');
      expect(seen.last.method, 'PATCH');
      expect(seen.last.uri.path, '/api/v1/asks/ask-1/dismiss');

      await api.reactToDecision('dec-1',
          reaction: 'agree', nodeId: 'x1', displayName: 'Dana');
      expect(seen.last.method, 'POST');
      expect(seen.last.uri.path, '/api/v1/decisions/dec-1/react');

      await api.resolveBlocker('node-9');
      expect(seen.last.method, 'PATCH');
      expect(seen.last.uri.path, '/api/v1/nodes/node-9/resolve-blocker');
    });

    test('an envelope failure is reported with the lens\'s own words',
        () async {
      replyBody = jsonEncode({'success': false, 'error': 'no tenant on token'});
      await expectLater(
        api.nudges(),
        throwsA(isA<LensApiException>()
            .having((e) => e.message, 'message', 'no tenant on token')),
      );
    });

    test('an unreachable lens is a NAMED failure, not a hang or a crash',
        () async {
      // Read the port BEFORE closing — a closed HttpServer has no socket to
      // ask.
      final port = server.port;
      await server.close(force: true);
      final dead = LensApiHttp(
        config: LensConfig(
          baseUrl: 'http://127.0.0.1:$port',
          tokenProvider: () => 'tok',
        ),
        timeout: const Duration(seconds: 1),
      );
      // A dead port refuses the connection on some platforms and simply never
      // answers on others (Windows drops the SYN) — so the assertion is on
      // what the FACE gets, not on which of the two happened: a named
      // LensApiException carrying the address, with no HTTP status because
      // there was no HTTP. Never a raw SocketException, never a hang.
      await expectLater(
        dead.runs(),
        throwsA(isA<LensApiException>()
            .having((e) => e.message, 'message', contains('127.0.0.1:$port'))
            .having((e) => e.statusCode, 'statusCode', isNull)),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('LensConfig', () {
    test('reads CYAN_LENS_URL / CYAN_LENS_TOKEN / CYAN_GROUP_ID', () {
      final cfg = LensConfig.fromEnvironment(const {
        'CYAN_LENS_URL': 'https://lens.example:8443',
        'CYAN_LENS_TOKEN': 'live-token',
        'CYAN_GROUP_ID': 'g-eng',
      });
      expect(cfg.baseUrl, 'https://lens.example:8443');
      expect(cfg.effectiveToken, 'live-token');
      expect(cfg.groupId, 'g-eng');
    });

    test('falls back to the macOS defaults when the launcher sets nothing', () {
      final cfg = LensConfig.fromEnvironment(const {});
      expect(cfg.baseUrl, LensConfig.defaultBaseUrl);
      expect(cfg.effectiveToken, LensConfig.devToken);
      expect(cfg.groupId, 'default');
    });

    test('a blank env var is treated as unset, not as an empty base URL', () {
      final cfg = LensConfig.fromEnvironment(const {
        'CYAN_LENS_URL': '   ',
        'CYAN_LENS_TOKEN': '',
      });
      expect(cfg.baseUrl, LensConfig.defaultBaseUrl);
      expect(cfg.effectiveToken, LensConfig.devToken);
    });
  });
}
