// test/dashboard_view_test.dart
//
// PARITY_TRACKER row 4 — Board: Dashboard (the running workflow).
// Acceptance list: scripts/parity_faces/dashboard_face.txt.
//
// Tier-1: drives `ParityDashboardView` through the `CyanBackend` seam
// (FakeCyanBackend) with no dylib. The face reads the engine's own pipeline
// state (`pipelineStatus`) and refines it with `pollEvents` frames, so these
// tests assert against ENGINE truth, not against a fixture the view invented:
// approving here really writes through `pipelineApprove` / `pipelineApproveAs`,
// and "the run advanced" is checked on the backend as well as on screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/providers/dashboard_controller.dart';
import 'package:cyan_flutter/widgets/parity/parity_dashboard_view.dart';

import 'support/parity_test_harness.dart';

/// The flagship board: compiled and mid-run, parked on its producer-review gate.
const _flagship = 'b-eng-1';

/// The schema board: authored, compiled on demand, gates that anyone may clear.
const _schema = 'b-eng-2';

/// The user the flagship board's review hold waits on.
const _producer = 'producer@studio';

/// Mount the face on an explicit controller so a test can step the event pump
/// one drain at a time instead of racing the app's 100ms timer.
Future<DashboardController> mount(
  WidgetTester tester, {
  required FakeCyanBackend backend,
  required String boardId,
  String reviewer = '',
  Size size = const Size(1000, 1000),
}) async {
  final controller = DashboardController(
    backend: backend,
    boardId: boardId,
    reviewer: reviewer,
  );
  addTearDown(controller.dispose);
  await controller.hydrate();
  await pumpParity(
    tester,
    ParityDashboardView(boardId: boardId, controller: controller),
    backend: backend,
    size: size,
  );
  return controller;
}

Future<FakeCyanBackend> engine() async {
  final backend = FakeCyanBackend();
  await backend.initialize();
  return backend;
}

/// The step ids `addWorkflowStep` files, in order.
const _lensStep = 'step-1';
const _deliverStep = 'step-2';

/// The schema board with two steps authored on the end of it — one creative
/// step the compile routes to the LENS (no `@` plugin, no sign-off ask), and a
/// device-bound delivery step chained behind it — then run to the point where
/// everything the compile already knew how to do is settled. The lens step is
/// the next thing the run would reach, and nothing has a model to run it.
Future<FakeCyanBackend> parked() async {
  final backend = await engine();
  await backend.addWorkflowStep(_schema, 'Grade the cut to the creative look');
  await backend.addWorkflowStep(_schema, 'Deliver the master via @shipit.send');
  await backend.pipelineCompile(_schema);
  for (final step in const ['ws1', 'ws2', 'ws3']) {
    await backend.runPipeline(_schema);
    if (!await backend.pipelineApprove(_schema, step)) {
      throw StateError('the fixture could not settle $step');
    }
  }
  return backend;
}

/// Records which step id a resume actually asked the engine to retry. The
/// routing rule picks between the parked step and the one upstream, and the
/// only way to prove which it chose is to watch the seam.
class _RecordingBackend extends FakeCyanBackend {
  final List<String> retried = [];

  @override
  Future<bool> pipelineRetry(String boardId, String stepId) {
    retried.add(stepId);
    return super.pipelineRetry(boardId, stepId);
  }
}

/// The ENGINE's own state for a step — the assertions that matter are made
/// against this, never against what the face decided to draw.
PipelineStepState _stateOf(PipelineStatus status, String stepId) =>
    status.steps.firstWhere((s) => s.stepId == stepId).status;

void main() {
  // ---- dashboard_face.txt, line 1 -----------------------------------------

  testWidgets('the compiled DAG preview renders before a run starts',
      (tester) async {
    // A compiled board that has executed nothing is `idle`: the face shows the
    // PLAN — every authored step, in order, joined by the edges the compile
    // actually authored — not an empty "no run" void. This is the same graph
    // the run lights up, drawn at the moment before it moves.
    final backend = await engine();
    await backend.pipelineCompile(_schema);

    await mount(tester, backend: backend, boardId: _schema);

    expect(find.text('Compiled DAG'), findsOneWidget);
    expect(find.text('3 steps · not started yet'), findsOneWidget);
    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('It lights up live when a run starts.'), findsOneWidget);

    // Every compiled step is on screen (DAG box + step row).
    for (final title in const [
      'Design the schema',
      'Migrate the users table',
      'Backfill from the export',
    ]) {
      expect(find.text(title), findsNWidgets(2),
          reason: '$title is in the DAG');
    }

    // The EDGES: a three-step chain has two dependency arrows.
    expect(find.byIcon(Icons.arrow_forward), findsNWidgets(2));

    // Nothing claims to be live: no run header, no gate, no meter.
    expect(find.text('Workflow'), findsNothing);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Totals'), findsNothing);
  });

  testWidgets('a board with no compiled workflow shows the empty state',
      (tester) async {
    // b-eng-2 has authored steps but has never been compiled, so the engine
    // has no DAG to preview — and the face says exactly that rather than
    // drawing an empty graph.
    final backend = await engine();
    await mount(tester, backend: backend, boardId: _schema);

    expect(find.text('No workflow deployed yet'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsNothing);
  });

  // ---- dashboard_face.txt, line 2 -----------------------------------------

  testWidgets('a running workflow shows per step state', (tester) async {
    // The flagship board mid-run: two steps the producer already approved, one
    // parked on its gate, one still queued. Each step reports ITS OWN state —
    // a run-level pill alone cannot tell an operator where the work actually is.
    final backend = await engine();
    await mount(tester, backend: backend, boardId: _flagship);

    expect(find.text('Running'), findsOneWidget, reason: 'the run-level pill');
    expect(find.text('2 / 4 steps complete'), findsOneWidget);

    // Per-step: settled · gated · queued, each named.
    expect(find.text('Approved'), findsNWidgets(2));
    expect(find.text('Queued'), findsOneWidget);
    // The gate step reads "Awaiting you" in its step row AND on its DAG box.
    expect(find.text('Awaiting you'), findsNWidgets(2));

    // The AI lane and the human lane are distinct signals: the two finished
    // machine steps report the machine half, the manual gate has no AI lane.
    expect(find.text('AI done'), findsNWidgets(2));
    expect(find.text('AI queued'), findsOneWidget);

    expect(find.text('Ingest the master from #shotlist'), findsNWidgets(2));
    expect(find.text('Publish the cut, send to /review'), findsNWidgets(2));
  });

  testWidgets('live frames move a step state without a re-read',
      (tester) async {
    // The persisted read establishes state; events REFINE it. A `StepProgress`
    // frame carries per-item counters that no status read has, so the row shows
    // work advancing inside a step, not just between steps.
    final backend = await engine();
    final vm = await mount(tester, backend: backend, boardId: _flagship);
    final runId = vm.current.runId;
    expect(runId, isNotEmpty);

    backend.scriptEvents([
      '{"type":"StepStateChanged","run_id":"$runId","step_id":"ws4",'
          '"state":"running","actor":"ai"}',
      '{"type":"StepProgress","run_id":"$runId","step_id":"ws4",'
          '"processed":3,"total":10,"current_item":"A001_C002.mxf"}',
    ]);
    await vm.tick();
    await tester.pumpAndSettle();

    expect(find.text('Queued'), findsNothing, reason: 'ws4 left the queue');
    expect(find.text('Running'), findsNWidgets(2),
        reason: 'the pill and the step that is now running');
    expect(find.text('3 / 10'), findsOneWidget);
    expect(find.text('A001_C002.mxf'), findsWidgets);
    expect(find.text('AI running'), findsOneWidget);
  });

  // ---- dashboard_face.txt, line 3 -----------------------------------------

  testWidgets('an approval gate surfaces approve and reject actions',
      (tester) async {
    // The engine breaks the chain at every gate: one step is open at a time,
    // and the human owes it a decision. Both decisions are offered — a gate
    // that can only be approved is not a gate.
    final backend = await engine();
    await backend.pipelineCompile(_schema);
    await backend.runPipeline(_schema);

    await mount(tester, backend: backend, boardId: _schema);

    expect(find.text('Approval needed'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    // Exactly ONE gate is open — the steps behind it are still queued.
    expect(find.text('Queued'), findsNWidgets(2));
  });

  testWidgets('a review hold names the reviewer it waits on and refuses others',
      (tester) async {
    // A producer-review hold clears only for its assignee. This device is not
    // signed in as that user, so the engine refuses — and the refusal is shown
    // verbatim while the gate stays exactly where it was. A gate that reported
    // success it did not get is the one failure this face cannot have.
    final backend = await engine();
    await mount(tester, backend: backend, boardId: _flagship);

    expect(find.text('In review — waiting on $_producer'), findsOneWidget);

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(find.textContaining("waiting on '$_producer'"), findsOneWidget);
    expect((await backend.pipelineStatus(_flagship)).awaitingStep, 'ws3',
        reason: 'the engine did not clear the gate, so neither did the face');
    expect(find.text('Approved'), findsNWidgets(2),
        reason: 'still the two steps that were already approved');
  });

  // ---- dashboard_face.txt, line 4 -----------------------------------------

  testWidgets('approving a gate advances the run', (tester) async {
    // Approve-to-advance: clearing a gate RESUMES the same run from the next
    // step, so the next step executes and parks on its own gate. The face is
    // not asserting that from its own optimism — the engine moved, and the
    // re-read is what put it on screen.
    final backend = await engine();
    await backend.pipelineCompile(_schema);
    await backend.runPipeline(_schema);
    await mount(tester, backend: backend, boardId: _schema);

    expect(find.text('0 / 3 steps complete'), findsOneWidget);

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    // The engine advanced: step one is settled, step two now holds the run.
    final status = await backend.pipelineStatus(_schema);
    expect(status.humanApproved, 1);
    expect(status.awaitingStep, 'ws2');

    expect(find.text('1 / 3 steps complete'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Awaiting you'), findsNWidgets(2),
        reason: 'the newly opened gate, in its row and on its DAG box');
    expect(find.text('Approval needed'), findsOneWidget);
  });

  testWidgets('the assignee clears a review hold and the run advances',
      (tester) async {
    // Signed in AS the reviewer the hold names, the same Approve goes through
    // the reviewer-scoped verb and the chain resumes into the next step.
    final backend = await engine();
    await mount(
      tester,
      backend: backend,
      boardId: _flagship,
      reviewer: _producer,
    );

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    final status = await backend.pipelineStatus(_flagship);
    expect(status.humanApproved, 3);
    expect(status.awaitingStep, 'ws4', reason: 'the resume executed ws4');

    expect(find.text('3 / 4 steps complete'), findsOneWidget);
    expect(find.text('Approval needed'), findsOneWidget);
    expect(find.textContaining('waiting on'), findsNothing);
  });

  testWidgets('rejecting a gate stops the run at that gate', (tester) async {
    // A rejection is a decision NOT to proceed: the step fails, nothing
    // downstream runs, and the run reports its terminal state.
    final backend = await engine();
    await backend.pipelineCompile(_schema);
    await backend.runPipeline(_schema);
    await mount(tester, backend: backend, boardId: _schema);

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();

    final status = await backend.pipelineStatus(_schema);
    expect(status.failed, 1);
    expect(status.status, PipelineRunState.failed);

    expect(find.text('Failed'), findsWidgets);
    expect(find.text('Run failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget,
        reason: 'a failed step is actionable, never simply stuck');
  });

  // ---- dashboard_face.txt, line 5 -----------------------------------------

  testWidgets('a finished run reports its terminal state', (tester) async {
    // Every gate cleared: the engine's own run status is `done`, and the face
    // shows the summary rather than a live surface that quietly stops updating.
    final backend = await engine();
    await backend.pipelineCompile(_schema);
    for (final step in const ['ws1', 'ws2', 'ws3']) {
      await backend.runPipeline(_schema);
      expect(await backend.pipelineApprove(_schema, step), isTrue);
    }

    await mount(tester, backend: backend, boardId: _schema);

    expect(find.text('Run done'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget, reason: 'the run-level pill');
    expect(find.text('3 / 3 steps complete'), findsOneWidget);
    expect(find.text('Approve'), findsNothing, reason: 'no gate is open');
  });

  testWidgets('a WorkflowRunFinished frame reports the terminal state too',
      (tester) async {
    // The other route to terminal: the engine says so on the event buffer.
    final backend = await engine();
    final vm = await mount(tester, backend: backend, boardId: _flagship);

    backend.scriptEvents([
      '{"type":"WorkflowRunFinished","run_id":"${vm.current.runId}",'
          '"state":"cancelled","finished_at":1753900009000}',
    ]);
    await vm.tick();
    await tester.pumpAndSettle();

    expect(find.text('Run cancelled'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
  });

  // ---- dashboard_face.txt, line 6 -----------------------------------------

  testWidgets('run stats update from WorkflowStatsUpdated events',
      (tester) async {
    // The meter is a pure ECHO of the engine's snapshot — the face never sums
    // its own minutes or invents a cost. A frame lands, the numbers change.
    final backend = await engine();
    final vm = await mount(tester, backend: backend, boardId: _flagship);
    final runId = vm.current.runId;

    expect(find.text('Totals'), findsOneWidget);
    expect(find.text('12.5m'), findsNothing);

    backend.scriptEvents([
      '{"type":"WorkflowStatsUpdated","run_id":"$runId","tenant_id":"t1",'
          '"snapshot":{"tenant_id":"t1","run_id":"$runId",'
          '"items_processed":7,"items_total":12,"current_item":"A001_C002.mxf",'
          '"totals":{"wall_minutes":12.5,"human_minutes":3.0,"ai_minutes":9.5,'
          '"files_processed":7,"est_cost_usd":0.42}}}',
    ]);
    await vm.tick();
    await tester.pumpAndSettle();

    expect(find.text('12.5m'), findsOneWidget, reason: 'wall minutes');
    expect(find.text('3.0m'), findsOneWidget, reason: 'human minutes');
    expect(find.text('9.5m'), findsOneWidget, reason: 'ai minutes');
    expect(find.text('7'), findsOneWidget, reason: 'files processed');
    expect(find.text('\$0.42'), findsOneWidget, reason: 'est. cost');
    // The snapshot also carries the run-level item counters.
    expect(find.text('7 / 12'), findsOneWidget);
  });

  testWidgets('a stats frame for another run is not ours to render',
      (tester) async {
    // Run isolation: the surface follows ONE run. A frame from a neighbouring
    // run must not repaint this one's meter.
    final backend = await engine();
    final vm = await mount(tester, backend: backend, boardId: _flagship);

    backend.scriptEvents([
      '{"type":"WorkflowStatsUpdated","run_id":"some-other-run",'
          '"snapshot":{"tenant_id":"t","run_id":"some-other-run",'
          '"totals":{"wall_minutes":99.0,"est_cost_usd":9.99}}}',
    ]);
    await vm.tick();
    await tester.pumpAndSettle();

    expect(find.text('99.0m'), findsNothing);
    expect(find.text('\$9.99'), findsNothing);
  });

  // ---- dashboard_face.txt, line 7 -----------------------------------------

  testWidgets('a step offers run this step now out of order', (tester) async {
    // The DAG's whole point is that a step waits for the ones before it — which
    // leaves an operator with no way to execute just the one step they need
    // while somebody else's gate holds the chain. Run-now dispatches THAT step
    // through the engine's route-local path, ahead of its turn. This is the
    // engine really running it: ws2 is settled by the read, not by optimism.
    final backend = await engine();
    await backend.pipelineCompile(_schema);
    await backend.runPipeline(_schema);
    await mount(tester, backend: backend, boardId: _schema);

    // ws1's gate is open and ws2 is queued BEHIND it — that is the trap.
    expect(find.text('Approval needed'), findsOneWidget);
    expect(find.text('Blocked by Design the schema'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('run-now-ws2')));
    await tester.pumpAndSettle();

    // The engine executed the one step, out of order, behind a gate it never
    // touched: ws1 is still parked on its own approval.
    final status = await backend.pipelineStatus(_schema);
    expect(_stateOf(status, 'ws2'), PipelineStepState.aiComplete,
        reason: 'ws2 ran ahead of its turn');
    expect(_stateOf(status, 'ws1'), PipelineStepState.aiComplete,
        reason: 'run-now jumped no gate — ws1 still owes a decision');

    // Both are now awaiting a human, and ws2 has left the queue.
    expect(find.text('Approval needed'), findsNWidgets(2));
    expect(find.text('Blocked by Design the schema'), findsNothing);
    expect(find.text('Queued'), findsOneWidget, reason: 'only ws3 is left');
  });

  testWidgets('run now surfaces the engine refusal for an unbound step',
      (tester) async {
    // The route-local path only dispatches a step BOUND to this device. The
    // flagship's publish step runs in the CLOUD — there is nothing here to run
    // it — and the engine says so. The face repeats the refusal verbatim and
    // the step stays exactly where it was, rather than reporting a dispatch it
    // never got.
    final backend = await engine();
    await mount(tester, backend: backend, boardId: _flagship);

    await tester.tap(find.byKey(const ValueKey('run-now-ws4')));
    await tester.pumpAndSettle();

    expect(find.text('not_locally_bound'), findsOneWidget);
    expect(_stateOf(await backend.pipelineStatus(_flagship), 'ws4'),
        PipelineStepState.pending,
        reason: 'nothing moved');
    expect(find.text('Queued'), findsOneWidget);
  });

  // ---- dashboard_face.txt, lines 8-10 -------------------------------------

  testWidgets('a needs lens park joins the approval list', (tester) async {
    // A creative step the compile routed to the lens has no model bound to run
    // it. The engine PARKS it — amber and resumable, never a red failure — and
    // the park is a human-actionable item, so it joins the action list. The
    // KEYSTONE finding was exactly this step with no override anywhere: the
    // whole chain wedged behind a model that never arrived.
    final backend = await parked();
    await mount(tester, backend: backend, boardId: _schema);

    expect(find.text('Needs Lens'), findsNothing, reason: 'not parked yet');

    await tester.tap(find.byKey(const ValueKey('run-now-$_lensStep')));
    await tester.pumpAndSettle();

    // The engine's own state, not the face's guess.
    expect(_stateOf(await backend.pipelineStatus(_schema), _lensStep),
        PipelineStepState.needsLens);
    expect(find.text('needs_lens: no model is bound to run this step'),
        findsOneWidget,
        reason: 'the engine said why, verbatim');

    // It is on the action list — a card of its own, beside any real gate.
    expect(find.text('Needs Lens'), findsOneWidget);
    expect(find.text('Grade the cut to the creative look'), findsNWidgets(3),
        reason: 'the DAG box, the gate card and the step row');
    // Parked, not failed: no red terminal state anywhere.
    expect(find.text('Parked'), findsNWidgets(2));
    expect(find.text('Failed'), findsNothing);
    expect(find.text('Run failed'), findsNothing);
  });

  testWidgets(
      'a needs lens card offers a complete affordance as a human override',
      (tester) async {
    // The way out of a park is the human doing the work off-model and saying
    // so. The card offers Complete — and only Complete: nothing ran, so there
    // is no AI result to reject. The write is real; the engine settles the step
    // and the chain resumes into the step that was waiting behind it.
    final backend = await parked();
    await mount(tester, backend: backend, boardId: _schema);
    await tester.tap(find.byKey(const ValueKey('run-now-$_lensStep')));
    await tester.pumpAndSettle();

    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('Reject'), findsNothing,
        reason: 'nothing ran, so there is nothing to reject');
    expect(find.text('Approve'), findsNothing);

    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();

    final status = await backend.pipelineStatus(_schema);
    expect(_stateOf(status, _lensStep), PipelineStepState.humanApproved,
        reason: 'the override settled the step in the engine');
    expect(find.text('Needs Lens'), findsNothing, reason: 'the park cleared');
    expect(find.text('4 / 5 steps complete'), findsOneWidget);
    // And the run moved on: the step behind the park executed and now holds
    // its own gate.
    expect(_stateOf(status, _deliverStep), PipelineStepState.aiComplete);
  });

  testWidgets(
      'a parked step passes its dependencies through rather than blocking them',
      (tester) async {
    // A park cannot be the thing the chain waits on — it clears out of band, so
    // the step behind it waits on whatever the PARKED step waited on. Before
    // the park, the delivery step is held by the lens step; after it, its
    // dependency is passed through to the settled step upstream and it is
    // ready. This is the wedge the KEYSTONE bench found, un-wedged.
    final backend = await parked();
    await mount(tester, backend: backend, boardId: _schema);

    expect(find.text('Blocked by Grade the cut to the creative look'),
        findsOneWidget);
    expect(find.text('Ready'), findsOneWidget,
        reason: 'only the lens step, whose own dependencies are settled');

    await tester.tap(find.byKey(const ValueKey('run-now-$_lensStep')));
    await tester.pumpAndSettle();

    expect(find.text('Blocked by Grade the cut to the creative look'),
        findsNothing,
        reason: 'the park passed its dependencies through');
    expect(find.textContaining('Blocked by'), findsNothing);
    expect(find.text('Ready'), findsOneWidget,
        reason: 'the delivery step, now unblocked by the park in front of it');

    // Not merely cosmetic — the ENGINE steps over the park too, so the run
    // continues into the step that was stuck behind it.
    await backend.runPipeline(_schema);
    final status = await backend.pipelineStatus(_schema);
    expect(_stateOf(status, _deliverStep), PipelineStepState.aiComplete);
    expect(_stateOf(status, _lensStep), PipelineStepState.needsLens,
        reason: 'the park is still parked — it was stepped over, not settled');
  });

  // ---- PARKED (awaiting input) --------------------------------------------
  //
  // A park is not a gate. `isGateOpen` covers approve-or-reject, so an
  // `awaiting_input` step drew a yellow dot, the words "Awaiting input" and NO
  // affordance whatsoever: the operator went and did the thing the ask named —
  // confirmed the edit in the NLE — came back, and had no button. The run
  // wedged, in both gate modes, in the middle of the spine.

  testWidgets('a parked step offers Re-run', (tester) async {
    final backend = await engine();
    final vm = await mount(tester, backend: backend, boardId: _flagship);
    final runId = vm.current.runId;

    backend.scriptEvents([
      '{"type":"StepStateChanged","run_id":"$runId","step_id":"ws4",'
          '"state":"awaiting_input","actor":"human"}',
    ]);
    await vm.tick();
    await tester.pumpAndSettle();

    expect(find.text('Awaiting input'), findsWidgets,
        reason: 'the park must be named');
    expect(find.byKey(const ValueKey('dashboard.rerun.ws4')), findsOneWidget,
        reason: 'a parked step must carry the control that resumes it — '
            'without it the operator does the work and the run stays wedged');
  });

  test('Re-run resumes from the comment/sense step UPSTREAM when there is one',
      () async {
    // D/P-4, and the whole reason rerunParked exists. Re-running the parked
    // step alone could never see the input the operator had just supplied — it
    // re-ran the same step and parked again, a same-step no-op loop. Resuming
    // from the sense step upstream re-READS the source (the comment the
    // reviewer just left) before the parked step re-dispatches.
    final backend = _RecordingBackend();
    await backend.initialize();
    await backend.addWorkflowStep(_schema, 'Sense the reviewer comments');
    await backend.addWorkflowStep(_schema, 'Conform the edit');
    await backend.pipelineCompile(_schema);

    final vm = DashboardController(backend: backend, boardId: _schema);
    addTearDown(vm.dispose);
    await vm.hydrate();

    final ids = vm.current.steps.map((s) => s.id).toList();
    final parkedId = ids.last;
    final upstreamId = ids[ids.length - 2];
    expect(vm.current.steps[ids.length - 2].title, contains('comments'),
        reason: 'the fixture must put the sense step directly upstream');

    await vm.rerunParked(parkedId);

    expect(backend.retried, [upstreamId],
        reason: 'the resume must start at the sense step, not at the parked '
            'step — otherwise the new comment is never read');
  });

  test(
      'Re-run resumes from the parked step itself when nothing upstream '
      'senses', () async {
    // The other half of the rule: an ordinary upstream step is not a source to
    // re-read, so the resume stays where the park is.
    final backend = _RecordingBackend();
    await backend.initialize();

    final vm = DashboardController(backend: backend, boardId: _flagship);
    addTearDown(vm.dispose);
    await vm.hydrate();

    final ids = vm.current.steps.map((s) => s.id).toList();
    final index = ids.indexOf('ws4');
    expect(index, greaterThan(0));
    final upstream = vm.current.steps[index - 1];
    expect(
        '${upstream.id} ${upstream.title}'.toLowerCase(),
        isNot(
            anyOf(contains('comment'), contains('sense'), contains('review'))),
        reason: 'this fixture must NOT trip the upstream hop');

    await vm.rerunParked('ws4');

    expect(backend.retried, ['ws4']);
  });

  testWidgets('golden: dashboard DAG + gated run', (tester) async {
    final backend = await engine();
    await mount(
      tester,
      backend: backend,
      boardId: _flagship,
      size: const Size(900, 700),
    );
    await expectLater(
      find.byType(ParityDashboardView),
      matchesGoldenFile('golden/dashboard_dag.png'),
    );
  }, tags: 'golden');
}
