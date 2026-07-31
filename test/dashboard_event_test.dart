// dashboard_event_test.dart — THE GATE for the Dashboard event union.
//
// This file is the acceptance oracle for `lib/models/dashboard_event.dart`.
// It is written BEFORE the implementation and must not be edited to make the
// implementation pass: the supervisor's gate checks both that these tests pass
// AND that this file is unchanged. A decoder that only satisfies a weakened test
// is exactly the false green the loop exists to prevent.
//
// The contract mirrors iOS `DashboardEvent.fromJSON` in
// cyan-iOS/Cyan/Cyan/Models/DashboardTypes.swift, which is the shipped, live
// reference. Where this test and prose disagree, this test wins.
//
// Seven variants, all carried by `cyan_poll_events` on the "dashboard" component:
//   WorkflowRunStarted · StepStateChanged · StepProgress · ApprovalRequested
//   ApprovalResolved   · WorkflowRunFinished · WorkflowStatsUpdated
//
// Three behaviours are easy to miss and are pinned deliberately:
//   1. A payload may arrive FLAT or wrapped under "data".
//   2. Numbers may arrive as int, double or numeric string — all coerce; a
//      missing number is 0, never an exception.
//   3. An unknown "type", malformed JSON, or a variant missing its REQUIRED id
//      returns null. Never a throw, never a partially-built event.

import 'package:flutter_test/flutter_test.dart';
import 'package:cyan_flutter/models/dashboard_event.dart';

void main() {
  group('WorkflowRunStarted', () {
    test('decodes a flat payload', () {
      final e = DashboardEvent.fromJson('''
        {"type":"WorkflowRunStarted","run_id":"r1","board_id":"b1",
         "workflow_id":"w1","workflow_label":"Multicut review spine",
         "total_steps":15,"started_at":1753900000000,"tenant_id":"t1"}
      ''') as RunStarted;
      expect(e.runId, 'r1');
      expect(e.boardId, 'b1');
      expect(e.workflowId, 'w1');
      expect(e.workflowLabel, 'Multicut review spine');
      expect(e.totalSteps, 15);
      expect(e.startedAt, 1753900000000);
      expect(e.tenantId, 't1');
    });

    test('decodes the same payload wrapped under "data"', () {
      final e = DashboardEvent.fromJson('''
        {"type":"WorkflowRunStarted",
         "data":{"run_id":"r1","board_id":"b1","total_steps":15,"tenant_id":"t1"}}
      ''') as RunStarted;
      expect(e.runId, 'r1');
      expect(e.boardId, 'b1');
      expect(e.totalSteps, 15);
      expect(e.tenantId, 't1');
    });

    test('absent optional strings default to empty, not null', () {
      final e = DashboardEvent.fromJson('{"type":"WorkflowRunStarted","run_id":"r1"}')
          as RunStarted;
      expect(e.boardId, '');
      expect(e.workflowLabel, '');
      expect(e.tenantId, '');
      expect(e.totalSteps, 0);
      expect(e.startedAt, 0);
    });

    test('without run_id it is null — run_id is the required identity', () {
      expect(DashboardEvent.fromJson('{"type":"WorkflowRunStarted","board_id":"b1"}'), isNull);
    });
  });

  group('StepStateChanged', () {
    test('decodes every state spelling the engine emits', () {
      const wire = {
        'pending': DashboardStepState.pending,
        'running': DashboardStepState.running,
        'awaiting_approval': DashboardStepState.awaitingApproval,
        'approved': DashboardStepState.approved,
        'done': DashboardStepState.done,
        'failed': DashboardStepState.failed,
        'needs_lens': DashboardStepState.needsLens,
        'awaiting_input': DashboardStepState.awaitingInput,
      };
      wire.forEach((raw, want) {
        final e = DashboardEvent.fromJson(
          '{"type":"StepStateChanged","run_id":"r","step_id":"s","state":"$raw"}',
        ) as StepStateChanged;
        expect(e.state, want, reason: 'state "$raw" must decode to $want');
      });
    });

    test('an unrecognised state falls back to pending rather than throwing', () {
      final e = DashboardEvent.fromJson(
        '{"type":"StepStateChanged","run_id":"r","step_id":"s","state":"martian"}',
      ) as StepStateChanged;
      expect(e.state, DashboardStepState.pending);
    });

    test('actor decodes, defaulting to ai', () {
      final human = DashboardEvent.fromJson(
        '{"type":"StepStateChanged","run_id":"r","step_id":"s","actor":"human"}',
      ) as StepStateChanged;
      expect(human.actor, DashboardStepActor.human);

      final none = DashboardEvent.fromJson(
        '{"type":"StepStateChanged","run_id":"r","step_id":"s"}',
      ) as StepStateChanged;
      expect(none.actor, DashboardStepActor.ai, reason: 'absent actor defaults to ai');
    });

    test('plugin is nullable — absent means null, not empty string', () {
      final withPlugin = DashboardEvent.fromJson(
        '{"type":"StepStateChanged","run_id":"r","step_id":"s","plugin":"cyan-media"}',
      ) as StepStateChanged;
      expect(withPlugin.plugin, 'cyan-media');

      final without = DashboardEvent.fromJson(
        '{"type":"StepStateChanged","run_id":"r","step_id":"s"}',
      ) as StepStateChanged;
      expect(without.plugin, isNull);
    });

    test('needs BOTH run_id and step_id', () {
      expect(DashboardEvent.fromJson('{"type":"StepStateChanged","run_id":"r"}'), isNull);
      expect(DashboardEvent.fromJson('{"type":"StepStateChanged","step_id":"s"}'), isNull);
    });
  });

  group('StepProgress', () {
    test('decodes counts and nullable detail fields', () {
      final e = DashboardEvent.fromJson('''
        {"type":"StepProgress","run_id":"r","step_id":"s","processed":3,"total":10,
         "current_item":"A001_C002.mxf","detail":"probing","tenant_id":"t"}
      ''') as StepProgress;
      expect(e.processed, 3);
      expect(e.total, 10);
      expect(e.currentItem, 'A001_C002.mxf');
      expect(e.detail, 'probing');
    });

    test('absent current_item and detail are null', () {
      final e = DashboardEvent.fromJson(
        '{"type":"StepProgress","run_id":"r","step_id":"s","processed":1,"total":2}',
      ) as StepProgress;
      expect(e.currentItem, isNull);
      expect(e.detail, isNull);
    });
  });

  group('approval gates', () {
    test('ApprovalRequested decodes', () {
      final e = DashboardEvent.fromJson('''
        {"type":"ApprovalRequested","run_id":"r","step_id":"s",
         "name":"ingest and probe","requested_at":1753900001000,"tenant_id":"t"}
      ''') as ApprovalRequested;
      expect(e.name, 'ingest and probe');
      expect(e.requestedAt, 1753900001000);
    });

    test('ApprovalResolved decodes the decision and who made it', () {
      final e = DashboardEvent.fromJson('''
        {"type":"ApprovalResolved","run_id":"r","step_id":"s",
         "decision":"approved","by":"rick","at":1753900002000}
      ''') as ApprovalResolved;
      expect(e.decision, 'approved');
      expect(e.by, 'rick');
      expect(e.at, 1753900002000);
    });
  });

  group('WorkflowRunFinished', () {
    test('decodes each terminal state', () {
      const wire = {
        'running': WorkflowRunState.running,
        'done': WorkflowRunState.done,
        'failed': WorkflowRunState.failed,
        'cancelled': WorkflowRunState.cancelled,
      };
      wire.forEach((raw, want) {
        final e = DashboardEvent.fromJson(
          '{"type":"WorkflowRunFinished","run_id":"r","state":"$raw"}',
        ) as RunFinished;
        expect(e.state, want);
      });
    });

    test('an unrecognised state falls back to done', () {
      final e = DashboardEvent.fromJson(
        '{"type":"WorkflowRunFinished","run_id":"r","state":"???"}',
      ) as RunFinished;
      expect(e.state, WorkflowRunState.done);
    });
  });

  group('WorkflowStatsUpdated', () {
    const statsJson = '''
      {"type":"WorkflowStatsUpdated","run_id":"r","tenant_id":"t",
       "snapshot":{"tenant_id":"t","run_id":"r",
         "totals":{"wall_minutes":12.5,"human_minutes":3.0,"ai_minutes":9.5,
                   "files_processed":7,"est_cost_usd":0.42}}}
    ''';

    test('decodes the snapshot totals', () {
      final e = DashboardEvent.fromJson(statsJson) as StatsUpdated;
      expect(e.snapshot.runId, 'r');
      expect(e.snapshot.tenantId, 't');
      expect(e.snapshot.totals.wallMinutes, 12.5);
      expect(e.snapshot.totals.humanMinutes, 3.0);
      expect(e.snapshot.totals.aiMinutes, 9.5);
      expect(e.snapshot.totals.filesProcessed, 7);
      expect(e.snapshot.totals.estCostUsd, 0.42);
    });

    test('a snapshot missing its own ids makes the whole event null', () {
      expect(
        DashboardEvent.fromJson(
          '{"type":"WorkflowStatsUpdated","run_id":"r","snapshot":{"totals":{}}}',
        ),
        isNull,
      );
    });

    test('absent totals decode as zeros rather than failing', () {
      final e = DashboardEvent.fromJson(
        '{"type":"WorkflowStatsUpdated","run_id":"r","snapshot":{"tenant_id":"t","run_id":"r"}}',
      ) as StatsUpdated;
      expect(e.snapshot.totals.wallMinutes, 0);
      expect(e.snapshot.totals.filesProcessed, 0);
    });
  });

  group('numeric coercion', () {
    // The engine is not consistent about int vs double vs string on the wire,
    // and a dashboard that throws on a stringly-typed count is a dashboard that
    // dies mid-run. Mirrors iOS DashboardNum.
    test('ints, doubles and numeric strings all coerce', () {
      for (final raw in ['15', '15.0', '15']) {
        final e = DashboardEvent.fromJson(
          '{"type":"WorkflowRunStarted","run_id":"r","total_steps":"$raw"}',
        ) as RunStarted;
        expect(e.totalSteps, 15, reason: 'total_steps "$raw" must coerce to 15');
      }
      final d = DashboardEvent.fromJson(
        '{"type":"WorkflowRunStarted","run_id":"r","total_steps":15.0}',
      ) as RunStarted;
      expect(d.totalSteps, 15);
    });

    test('a non-numeric value is 0, not an exception', () {
      final e = DashboardEvent.fromJson(
        '{"type":"WorkflowRunStarted","run_id":"r","total_steps":"lots"}',
      ) as RunStarted;
      expect(e.totalSteps, 0);
    });
  });

  group('hostile input is null, never a throw', () {
    test('unknown type', () {
      expect(DashboardEvent.fromJson('{"type":"SomethingNewWeShipLater","run_id":"r"}'), isNull);
    });
    test('malformed JSON', () {
      expect(DashboardEvent.fromJson('{not json at all'), isNull);
    });
    test('empty string', () {
      expect(DashboardEvent.fromJson(''), isNull);
    });
    test('JSON that is not an object', () {
      expect(DashboardEvent.fromJson('[1,2,3]'), isNull);
    });
    test('object with no type', () {
      expect(DashboardEvent.fromJson('{"run_id":"r"}'), isNull);
    });
  });
}
