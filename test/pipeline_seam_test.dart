// pipeline_seam_test.dart — the oracle for the pipeline spine on the seam.
//
// The `ffi_pipeline` cluster binds the 13 `cyan_*` verbs that compile, run and
// gate a workflow. This file pins the SEAM behaviour those bindings expose:
// the typed models the wrappers decode into, and the state machine
// `FakeCyanBackend` drives so the widget/VM tiers can step a workflow with no
// dylib present.
//
// The real FFI backend is not exercised here — it needs a live engine. What is
// pinned is the contract both implementations share, taken from the Rust
// signatures in cyan-backend/src/ffi/core.rs:
//   - compile/run ACKNOWLEDGE ("compiling" / "started"); they do not finish.
//   - the run-level status is derived: failed > awaiting > running > done >
//     in-progress > idle.
//   - a producer-review hold clears ONLY for the user it waits on.
//   - undo/redo report the REMAINING depths, and refuse at the ends.

import 'package:flutter_test/flutter_test.dart';
import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';

void main() {
  late FakeCyanBackend backend;

  setUp(() async {
    backend = FakeCyanBackend();
    await backend.initialize();
  });

  group('wire decoding', () {
    test('step status strings map to the typed state', () {
      expect(PipelineStepStateX.fromWire('ai_complete'),
          PipelineStepState.aiComplete);
      expect(PipelineStepStateX.fromWire('human_approved'),
          PipelineStepState.humanApproved);
      // The engine reports a queued step as "scheduled"; it is still running.
      expect(PipelineStepStateX.fromWire('scheduled'), PipelineStepState.running);
      expect(PipelineStepStateX.fromWire('running'), PipelineStepState.running);
      expect(PipelineStepStateX.fromWire('failed'), PipelineStepState.failed);
      // Anything unrecognised (or absent) is pending, never an exception.
      expect(PipelineStepStateX.fromWire('nonsense'), PipelineStepState.pending);
      expect(PipelineStepStateX.fromWire(null), PipelineStepState.pending);
    });

    test('run status strings map to the typed state', () {
      expect(PipelineRunStateX.fromWire('awaiting_approval'),
          PipelineRunState.awaitingApproval);
      expect(PipelineRunStateX.fromWire('in_progress'),
          PipelineRunState.inProgress);
      expect(PipelineRunStateX.fromWire('done'), PipelineRunState.done);
      expect(PipelineRunStateX.fromWire(null), PipelineRunState.idle);
    });

    test('travel direction carries the engine int: 0 = undo', () {
      expect(StepTravelDirection.undo.wireValue, 0);
      expect(StepTravelDirection.redo.wireValue, 1);
    });
  });

  group('status snapshot', () {
    test('an uncompiled board is idle with no steps', () async {
      final status = await backend.pipelineStatus('b-prod-2');
      expect(status.status, PipelineRunState.idle);
      expect(status.totalSteps, 0);
      expect(status.awaitingStep, isNull);
      expect(status.runId, isNull);
    });

    test('the seeded board is parked on its producer-review gate', () async {
      final status = await backend.pipelineStatus('b-eng-1');
      expect(status.status, PipelineRunState.awaitingApproval);
      expect(status.totalSteps, 4);
      expect(status.humanApproved, 2);
      expect(status.progressPct, 50);
      expect(status.awaitingStep, 'ws3');
      expect(status.totalCostDollars, greaterThan(0));

      final gate = status.steps.firstWhere((s) => s.stepId == 'ws3');
      expect(gate.status, PipelineStepState.aiComplete);
      expect(gate.status.needsApproval, isTrue);
      expect(gate.isReviewHold, isTrue);
      expect(gate.waitingOn, 'producer@studio');
    });

    test('a step that has not run reports no duration and no cost', () async {
      final status = await backend.pipelineStatus('b-eng-1');
      final last = status.steps.firstWhere((s) => s.stepId == 'ws4');
      expect(last.status, PipelineStepState.pending);
      expect(last.durationSecs, isNull);
      expect(last.costDollars, 0);
    });
  });

  group('compile and run acknowledge', () {
    test('compile is accepted and resets the DAG to pending', () async {
      final ack = await backend.pipelineCompile('b-eng-1');
      expect(ack.accepted, isTrue);
      expect(ack.status, 'compiling');
      expect(ack.boardId, 'b-eng-1');

      final status = await backend.pipelineStatus('b-eng-1');
      expect(status.status, PipelineRunState.idle);
      expect(status.pending, 4);
      expect(status.totalCostDollars, 0);
    });

    test('a board with nothing authored refuses to compile', () async {
      final ack = await backend.pipelineCompile('b-prod-2');
      expect(ack.accepted, isFalse);
      expect(ack.error, isNotNull);
    });

    test('run cannot start before a compile', () async {
      final ack = await backend.runPipeline('b-des-2');
      expect(ack.accepted, isFalse);
      expect(ack.error, 'compile first');
    });

    test('run executes ONE step, which then parks on its own gate', () async {
      await backend.pipelineCompile('b-eng-2');
      final ack = await backend.runPipeline('b-eng-2');
      expect(ack.accepted, isTrue);
      expect(ack.status, 'started');

      final status = await backend.pipelineStatus('b-eng-2');
      expect(status.status, PipelineRunState.awaitingApproval);
      expect(status.awaitingStep, 'ws1');
      expect(status.pending, 2);
      expect(status.runId, isNotNull);
    });

    test('a held gate blocks the next step until it clears', () async {
      await backend.pipelineCompile('b-eng-2');
      await backend.runPipeline('b-eng-2');
      // Second run: ws1 still holds, so nothing else may execute.
      await backend.runPipeline('b-eng-2');
      expect((await backend.pipelineStatus('b-eng-2')).awaitingStep, 'ws1');

      expect(await backend.pipelineApprove('b-eng-2', 'ws1'), isTrue);
      await backend.runPipeline('b-eng-2');
      final status = await backend.pipelineStatus('b-eng-2');
      expect(status.awaitingStep, 'ws2');
      expect(status.humanApproved, 1);
    });

    test('stepping every gate walks the run to done', () async {
      await backend.pipelineCompile('b-eng-2');
      for (final step in ['ws1', 'ws2', 'ws3']) {
        await backend.runPipeline('b-eng-2');
        expect(await backend.pipelineApprove('b-eng-2', step), isTrue);
      }
      final status = await backend.pipelineStatus('b-eng-2');
      expect(status.status, PipelineRunState.done);
      expect(status.status.isTerminal, isTrue);
      expect(status.progressPct, 100);
    });
  });

  group('gates', () {
    test('approve refuses a step that is not awaiting approval', () async {
      expect(await backend.pipelineApprove('b-eng-1', 'ws4'), isFalse);
      expect(await backend.pipelineApprove('b-eng-1', 'nope'), isFalse);
    });

    test('an unscoped approve cannot clear a producer-review hold', () async {
      expect(await backend.pipelineApprove('b-eng-1', 'ws3'), isFalse);
      expect((await backend.pipelineStatus('b-eng-1')).awaitingStep, 'ws3');
    });

    test('the review hold names WHO it waits on when it refuses', () async {
      final ack = await backend.pipelineApproveAs('b-eng-1', 'ws3', 'editor@studio');
      expect(ack.success, isFalse);
      expect(ack.error, contains('producer@studio'));
    });

    test('the assignee clears the review hold', () async {
      final ack =
          await backend.pipelineApproveAs('b-eng-1', 'ws3', 'producer@studio');
      expect(ack.success, isTrue);
      expect(ack.error, isNull);

      final status = await backend.pipelineStatus('b-eng-1');
      expect(status.humanApproved, 3);
      expect(status.awaitingStep, isNull);
      expect(status.status, PipelineRunState.inProgress);
    });

    test('rejecting as the assignee fails the run', () async {
      final ack =
          await backend.pipelineRejectAs('b-eng-1', 'ws3', 'producer@studio');
      expect(ack.success, isTrue);

      final status = await backend.pipelineStatus('b-eng-1');
      expect(status.status, PipelineRunState.failed);
      expect(status.failed, 1);
      final gate = status.steps.firstWhere((s) => s.stepId == 'ws3');
      expect(gate.error, contains('producer@studio'));
    });

    test('a missing step is reported, not silently accepted', () async {
      final ack = await backend.pipelineApproveAs('b-eng-1', 'nope', 'anyone');
      expect(ack.success, isFalse);
      expect(ack.error, 'step not found');
    });
  });

  group('retry / reset', () {
    test('retry puts a failed step back to pending and clears its error',
        () async {
      await backend.pipelineRejectAs('b-eng-1', 'ws3', 'producer@studio');
      expect(await backend.pipelineRetry('b-eng-1', 'ws3'), isTrue);

      final status = await backend.pipelineStatus('b-eng-1');
      expect(status.status, PipelineRunState.inProgress);
      final step = status.steps.firstWhere((s) => s.stepId == 'ws3');
      expect(step.status, PipelineStepState.pending);
      expect(step.error, isNull);
    });

    test('reset_step only touches its own step', () async {
      expect(await backend.pipelineResetStep('b-eng-1', 'ws1'), isTrue);
      final status = await backend.pipelineStatus('b-eng-1');
      expect(status.steps.firstWhere((s) => s.stepId == 'ws1').status,
          PipelineStepState.pending);
      expect(status.steps.firstWhere((s) => s.stepId == 'ws2').status,
          PipelineStepState.humanApproved);
    });

    test('reset returns the whole board to idle with no cost', () async {
      expect(await backend.pipelineReset('b-eng-1'), isTrue);
      final status = await backend.pipelineStatus('b-eng-1');
      expect(status.status, PipelineRunState.idle);
      expect(status.pending, 4);
      expect(status.totalCostDollars, 0);
      expect(status.runId, isNull);
    });

    test('reset and reset_step refuse a board that has no pipeline', () async {
      expect(await backend.pipelineReset('b-prod-2'), isFalse);
      expect(await backend.pipelineResetStep('b-prod-2', 'ws1'), isFalse);
    });
  });

  group('local step dispatch', () {
    test('a locally-bound step runs and reports its summary', () async {
      await backend.pipelineCompile('b-eng-1');
      final result = await backend.pipelineRunStepLocal('b-eng-1', 'ws1');
      expect(result.success, isTrue);
      expect(result.summary, isNotEmpty);
      expect(result.error, isNull);
      expect((await backend.pipelineStatus('b-eng-1')).awaitingStep, 'ws1');
    });

    test('a cloud step reports not_locally_bound', () async {
      final result = await backend.pipelineRunStepLocal('b-eng-1', 'ws4');
      expect(result.success, isFalse);
      expect(result.error, 'not_locally_bound');
    });

    test('an unknown step asks for a compile', () async {
      final result = await backend.pipelineRunStepLocal('b-eng-1', 'nope');
      expect(result.success, isFalse);
      expect(result.error, contains('compile first'));
    });
  });

  group('edit travel', () {
    test('undo restores the prior revision and reports both depths', () async {
      final travel = await backend.stepEditTravel(
          'b-eng-1', 'ws1', StepTravelDirection.undo);
      expect(travel.travelled, isTrue);
      expect(travel.content, isNotEmpty);
      expect(travel.canUndo, isTrue);
      expect(travel.redoDepth, 1);
    });

    test('redo walks back to where undo started', () async {
      final before = await backend.stepEditTravel(
          'b-eng-1', 'ws1', StepTravelDirection.undo);
      final after = await backend.stepEditTravel(
          'b-eng-1', 'ws1', StepTravelDirection.redo);
      expect(after.travelled, isTrue);
      expect(after.undoDepth, before.undoDepth + 1);
      expect(after.redoDepth, 0);
    });

    test('travelling past the end refuses with a reason', () async {
      final redo = await backend.stepEditTravel(
          'b-eng-1', 'ws1', StepTravelDirection.redo);
      expect(redo.travelled, isFalse);
      expect(redo.error, 'nothing to redo');

      await backend.stepEditTravel('b-eng-1', 'ws1', StepTravelDirection.undo);
      await backend.stepEditTravel('b-eng-1', 'ws1', StepTravelDirection.undo);
      final undo = await backend.stepEditTravel(
          'b-eng-1', 'ws1', StepTravelDirection.undo);
      expect(undo.travelled, isFalse);
      expect(undo.error, 'nothing to undo');
    });

    test('an unknown cell is reported, not travelled', () async {
      final travel = await backend.stepEditTravel(
          'b-eng-1', 'nope', StepTravelDirection.undo);
      expect(travel.travelled, isFalse);
      expect(travel.error, contains('not found'));
    });
  });

  group('workflow deploy state', () {
    test('a deployed board is locked and has a dashboard', () async {
      final state = await backend.boardWorkflowState('b-eng-1');
      expect(state.isDeployed, isTrue);
      expect(state.hasDashboard, isTrue);
      expect(state.isLocked, isTrue);
      expect(state.updatedAt, isNotNull);
    });

    test('an undeployed board reads back as the authoring default', () async {
      final state = await backend.boardWorkflowState('b-eng-2');
      expect(state.isDeployed, isFalse);
      expect(state.hasDashboard, isFalse);
      expect(state.isLocked, isFalse);
      expect(state.updatedAt, isNull);
      // The authoring default is an ANSWER, not a failure to read.
      expect(state.error, isNull);
    });
  });
}
