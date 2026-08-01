// test/resilience_test.dart
//
// PARITY face — RESILIENCE: the live run surface against a HOSTILE engine.
//
// The acceptance list (scripts/parity_faces/resilience.txt) is four ways the
// engine misbehaves in production. Each is scripted here through
// `FakeCyanBackend` — no dylib, no running engine — by subclassing it into a
// backend that lies, dies, or floods.
//
// Reference behaviour: Cyan/Cyan/Actors/ComponentActor.swift (the bounded drain
// loop) and Cyan/Cyan/ViewModels/DashboardViewModel.swift (`apply` / the
// `reconstruct` authoritative re-read).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/models/dashboard_event.dart';
import 'package:cyan_flutter/providers/live_run_controller.dart';
import 'package:cyan_flutter/widgets/parity/parity_live_run_view.dart';

import 'support/parity_test_harness.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Hostile backends
// ═══════════════════════════════════════════════════════════════════════════

/// Counts authoritative reads so a test can prove a REFETCH happened rather
/// than inferring it from the rendered state.
class _CountingBackend extends FakeCyanBackend {
  int runReads = 0;

  @override
  Future<WorkflowRun?> loadRun(String boardId) {
    runReads++;
    return super.loadRun(boardId);
  }
}

/// An engine that is simply gone: every seam call throws with the engine's own
/// words. Flip [down] to bring it back.
class _DeadBackend extends _CountingBackend {
  bool down = true;

  @override
  Future<String?> pollEvents(String component) async {
    if (down) throw StateError('engine socket closed');
    return super.pollEvents(component);
  }

  @override
  Future<WorkflowRun?> loadRun(String boardId) {
    if (down) throw StateError('engine socket closed');
    return super.loadRun(boardId);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Frame builders — raw JSON, exactly as the engine writes it
// ═══════════════════════════════════════════════════════════════════════════

const _run = 'run-7';

String _stepState(String stepId, String state, {String name = ''}) =>
    '{"type":"StepStateChanged","run_id":"$_run","tenant_id":"t1",'
    '"step_id":"$stepId","name":"$name","stage":"render","state":"$state",'
    '"actor":"ai","at":1}';

String _progress(String stepId, int processed, int total, String item) =>
    '{"type":"StepProgress","run_id":"$_run","tenant_id":"t1",'
    '"step_id":"$stepId","processed":$processed,"total":$total,'
    '"current_item":"$item"}';

String _stats({double cost = 1.25, int files = 3}) =>
    '{"type":"WorkflowStatsUpdated","run_id":"$_run","tenant_id":"t1",'
    '"snapshot":{"tenant_id":"t1","run_id":"$_run","board_id":"b-eng-1",'
    '"workflow_id":"wf1","workflow_label":"Render + Review Pipeline",'
    '"updated_at":9,"items_processed":$files,"items_total":10,'
    '"totals":{"wall_minutes":4.0,"ai_minutes":3.0,"human_minutes":1.0,'
    '"files_processed":$files,"est_cost_usd":$cost}}}';

LiveRunController _pump(FakeCyanBackend backend, {String board = 'b-eng-1'}) =>
    LiveRunController(backend: backend, boardId: board);

/// Pump the surface with an explicitly-driven controller (no timer), so each
/// test owns the cycle boundaries.
Future<void> _show(WidgetTester tester, LiveRunController c) =>
    pumpParity(tester, ParityLiveRunView(boardId: c.boardId, controller: c));

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  // 1. NULL
  // ═════════════════════════════════════════════════════════════════════════

  testWidgets('a null return from the backend does not crash the surface',
      (tester) async {
    // b-eng-2 has no run: `loadRun` answers null, and the event buffer is
    // empty so every `pollEvents` answers null too. Both are ANSWERS.
    final backend = _CountingBackend();
    final c = _pump(backend, board: 'b-eng-2');
    await c.hydrate();
    await _show(tester, c);

    expect(find.text('No run yet'), findsOneWidget);
    expect(c.current.hasRun, isFalse);
    // A null read is not a fault: the link stays live, not degraded.
    expect(c.current.link, LiveRunLink.live);
    expect(c.current.lastError, isNull);

    // And it keeps pumping a null queue indefinitely without souring.
    for (var i = 0; i < 5; i++) {
      await c.tick();
    }
    await tester.pump();

    expect(c.current.link, LiveRunLink.live);
    expect(find.text('No run yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a null poll answer is the empty buffer, not a fault',
      (tester) async {
    final backend = _CountingBackend();
    final c = _pump(backend);
    await c.hydrate();
    await _show(tester, c);

    expect(await backend.pollEvents('status'), isNull);
    await c.tick();
    await tester.pump();

    // The run read at hydrate is still fully on screen after an empty cycle.
    expect(find.text('Render + Review Pipeline'), findsOneWidget);
    expect(find.text('Ingest assets'), findsOneWidget);
    expect(c.current.link, LiveRunLink.live);
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 2. UNKNOWN VARIANTS
  // ═════════════════════════════════════════════════════════════════════════

  testWidgets('an unknown event variant is ignored and never fatal',
      (tester) async {
    final backend = _CountingBackend();
    // Four ways a frame can be undecodable, and one good frame BEHIND them —
    // a bad frame must not cost us the frames queued after it.
    backend.scriptEvents([
      // a variant a newer engine ships and this build has never compiled against
      '{"type":"QuantumLensRebalanced","run_id":"$_run","tenant_id":"t1"}',
      // a truncated write
      '{"type":"StepProgress","run_id":',
      // valid JSON, but not an object
      '["StepProgress", 3]',
      // the right variant, missing the id that scopes it
      '{"type":"StepStateChanged","tenant_id":"t1","step_id":"s2"}',
      // the good one
      _stepState('s2', 'failed'),
    ]);

    final c = _pump(backend);
    await c.hydrate();
    await c.tick();
    await _show(tester, c);

    // Never fatal.
    expect(tester.takeException(), isNull);
    // All four were dropped, and counted rather than hidden.
    expect(c.current.droppedFrames, 4);
    expect(find.text('4 unreadable'), findsOneWidget);
    // The good frame behind them still landed.
    expect(
      c.current.steps.firstWhere((s) => s.id == 's2').state,
      DashboardStepState.failed,
    );
    // The link is untouched — a dialect we don't speak is not a broken link.
    expect(c.current.link, LiveRunLink.live);
  });

  testWidgets('an unknown step state decodes to pending rather than throwing',
      (tester) async {
    final backend = _CountingBackend();
    // The variant IS known; the STATE spelling is not. That must degrade to a
    // safe state, not drop the frame (the engine still told us about a step).
    backend.scriptEvents([_stepState('s9', 'transmogrifying', name: 'New step')]);

    final c = _pump(backend);
    await c.hydrate();
    await c.tick();
    await _show(tester, c);

    expect(c.current.droppedFrames, 0);
    final step = c.current.steps.firstWhere((s) => s.id == 's9');
    expect(step.state, DashboardStepState.pending);
    expect(find.text('New step'), findsOneWidget);
  });

  testWidgets('events for a different run are not rendered', (tester) async {
    final backend = _CountingBackend();
    backend.scriptEvents([
      _stepState('s2', 'running'),
      // another board's run, on the SAME shared status buffer
      '{"type":"StepStateChanged","run_id":"run-99","tenant_id":"t1",'
          '"step_id":"s2","name":"","stage":"","state":"failed","actor":"ai","at":2}',
    ]);

    final c = _pump(backend);
    await c.hydrate();
    await c.tick();
    await _show(tester, c);

    expect(c.current.runId, _run);
    expect(
      c.current.steps.firstWhere((s) => s.id == 's2').state,
      DashboardStepState.running,
    );
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 3. LAG
  // ═════════════════════════════════════════════════════════════════════════

  testWidgets('a lagged event pump refetches authoritative state',
      (tester) async {
    final backend = _CountingBackend();
    // The producer has run away with us: a full cycle's worth of frames, all
    // claiming s1 failed. Those deltas are a PARTIAL story — the tail of the
    // truth is still sitting in a buffer we did not reach this cycle.
    backend.scriptEvents([
      for (var i = 0; i < LiveRunController.drainCap; i++)
        _stepState('s1', 'failed'),
    ]);

    final c = _pump(backend);
    await c.hydrate();
    final readsAfterHydrate = backend.runReads;

    await c.tick();
    await _show(tester, c);

    // It REFETCHED: an extra authoritative read this cycle.
    expect(backend.runReads, readsAfterHydrate + 1);
    // And it rendered the refetched truth, not the discarded deltas: the
    // persisted s1 is done, the frames claimed failed.
    expect(
      c.current.steps.firstWhere((s) => s.id == 's1').state,
      DashboardStepState.done,
    );
    expect(c.current.link, LiveRunLink.catchingUp);
    expect(find.text('Catching up…'), findsOneWidget);
  });

  testWidgets('a drain under the cap applies its deltas instead of refetching',
      (tester) async {
    final backend = _CountingBackend();
    backend.scriptEvents([
      for (var i = 0; i < LiveRunController.drainCap - 1; i++)
        _progress('s2', i, LiveRunController.drainCap, 'shot_$i.mov'),
    ]);

    final c = _pump(backend);
    await c.hydrate();
    final readsAfterHydrate = backend.runReads;

    await c.tick();
    await _show(tester, c);

    // Not lagged — no refetch, the deltas are the whole story.
    expect(backend.runReads, readsAfterHydrate);
    expect(c.current.link, LiveRunLink.live);
    expect(c.current.steps.firstWhere((s) => s.id == 's2').processed, 198);
    expect(find.textContaining('shot_198.mov'), findsWidgets);
  });

  testWidgets('catching up clears once the backlog drains', (tester) async {
    final backend = _CountingBackend();
    backend.scriptEvents([
      for (var i = 0; i < LiveRunController.drainCap; i++)
        _stepState('s1', 'failed'),
      _stepState('s4', 'running'),
    ]);

    final c = _pump(backend);
    await c.hydrate();
    await c.tick(); // hits the cap -> catching up
    await _show(tester, c);
    expect(c.current.link, LiveRunLink.catchingUp);

    await c.tick(); // the 1 remaining frame -> back to live
    await tester.pump();

    expect(c.current.link, LiveRunLink.live);
    expect(find.text('Live'), findsOneWidget);
    expect(
      c.current.steps.firstWhere((s) => s.id == 's4').state,
      DashboardStepState.running,
    );
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 4. LOSS
  // ═════════════════════════════════════════════════════════════════════════

  testWidgets('losing the backend surfaces a degraded state not a blank screen',
      (tester) async {
    final backend = _DeadBackend()..down = false;
    backend.scriptEvents([_progress('s2', 4, 10, 'reel_04.mov')]);

    final c = _pump(backend);
    await c.hydrate();
    await c.tick();
    await _show(tester, c);
    expect(find.text('Render + Review Pipeline'), findsOneWidget);

    // The engine dies mid-run.
    backend.down = true;
    await c.tick();
    await tester.pump();

    // Degraded — and NOT blank: the run, its steps and the last progress line
    // are all still on screen, because they are still the last true thing we
    // know.
    expect(c.current.link, LiveRunLink.degraded);
    expect(find.text('Reconnecting…'), findsOneWidget);
    expect(find.text('Render + Review Pipeline'), findsOneWidget);
    expect(find.text('Ingest assets'), findsOneWidget);
    expect(find.text('Producer approval'), findsOneWidget);
    expect(find.textContaining('reel_04.mov'), findsWidgets);
    // The engine's own words, and a way out.
    expect(find.textContaining('engine socket closed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a degraded surface heals on the next successful poll',
      (tester) async {
    final backend = _DeadBackend()..down = false;
    final c = _pump(backend);
    await c.hydrate();
    backend.down = true;
    await c.tick();
    await _show(tester, c);
    expect(c.current.link, LiveRunLink.degraded);

    // The engine comes back, and the recovering cycle re-reads authoritatively
    // rather than trusting whatever deltas survived the outage.
    backend.down = false;
    final readsBefore = backend.runReads;
    await c.tick();
    await tester.pump();

    expect(backend.runReads, readsBefore + 1);
    expect(c.current.link, LiveRunLink.live);
    expect(c.current.lastError, isNull);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('an engine that was never reachable offers Retry, not a spinner',
      (tester) async {
    final backend = _DeadBackend(); // down from the start
    final c = _pump(backend);
    await c.hydrate();
    await _show(tester, c);

    expect(c.current.link, LiveRunLink.unreachable);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Cannot reach the engine'), findsWidgets);
    expect(find.text('Retry'), findsOneWidget);

    // Retry re-reads, and the surface comes up for real.
    backend.down = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(c.current.link, LiveRunLink.live);
    expect(find.text('Render + Review Pipeline'), findsOneWidget);
  });

  // ═════════════════════════════════════════════════════════════════════════
  // The face itself — it has to be a real surface, not a strip over a spinner
  // ═════════════════════════════════════════════════════════════════════════

  testWidgets('renders the live run header, steps and metering',
      (tester) async {
    final backend = _CountingBackend();
    backend.scriptEvents([
      _stepState('s3', 'awaiting_approval', name: 'Producer approval'),
      _progress('s2', 7, 10, 'reel_07.mov'),
      _stats(),
    ]);

    final c = _pump(backend);
    await c.hydrate();
    await c.tick();
    await _show(tester, c);

    expect(find.text('Render + Review Pipeline'), findsOneWidget);
    expect(find.text('Running'), findsWidgets);
    expect(find.text('2 / 4 steps complete'), findsOneWidget);
    expect(find.text('Awaiting you'), findsOneWidget);
    expect(find.text('7 / 10'), findsOneWidget);
    expect(find.textContaining('Processing reel_07.mov'), findsOneWidget);
    // Totals come off the snapshot verbatim — never recomputed here.
    expect(find.text('Totals'), findsOneWidget);
    expect(find.text('3.0m'), findsOneWidget);
    expect(find.text('\$1.25'), findsOneWidget);
  });

  testWidgets('a finished run shows its terminal state', (tester) async {
    final backend = _CountingBackend();
    backend.scriptEvents([
      _stepState('s3', 'approved'),
      '{"type":"WorkflowRunFinished","run_id":"$_run","tenant_id":"t1",'
          '"state":"done","finished_at":42}',
    ]);

    final c = _pump(backend);
    await c.hydrate();
    await c.tick();
    await _show(tester, c);

    expect(c.current.finished, WorkflowRunState.done);
    expect(find.text('Done'), findsWidgets);
  });
}
