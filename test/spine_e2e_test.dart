// test/spine_e2e_test.dart
//
// PARITY face `spine_e2e` — the POST-PRODUCTION SPINE, end to end.
// Acceptance list: scripts/parity_faces/spine_e2e.txt.
//
// Tier-1: drives `ParitySpineView` through the `CyanBackend` seam
// (FakeCyanBackend) with no dylib, no engine and no media. The subject is the
// WALK, so every assertion is checked twice — once on screen, and once against
// the engine's own state, because a console that says a gate cleared while the
// engine still holds it is the exact failure this face exists to prevent.
//
// The spine is the engine's own authored template (`DEMO_SPINE_ID` in
// cyan-backend/src/templates.rs). Its constitution note reads "AUTHORED ORDER
// IS LAW", and these tests walk it in that order: ingest → producer review
// round → markers and timeline sense → picture lock → sound turnover →
// conform → grade → graded master.
//
// THE BAR IS BOTH SIDES OF THE REVIEW GATE. Releasing it WITH notes has to run
// the engine's agent pass first, so a mechanical note becomes a proposed op and
// a creative one stays a note. Releasing it WITHOUT notes has to leave the
// ledger alone entirely. Those are different behaviours and both are pinned.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/models/dashboard_event.dart';
import 'package:cyan_flutter/models/spine_lane.dart';
import 'package:cyan_flutter/providers/dashboard_controller.dart';
import 'package:cyan_flutter/providers/spine_controller.dart';
import 'package:cyan_flutter/widgets/parity/parity_dashboard_view.dart';
import 'package:cyan_flutter/widgets/parity/parity_spine_view.dart';

import 'support/parity_test_harness.dart';

/// A board with nothing authored on it — the spine's cold start.
const _board = 'b-prod-2';
const _tenant = 'g-product';

/// The user the spine's holds wait on, stamped onto the board at clone time.
const _producer = 'producer@studio';

/// A note that fully specifies a mechanical edit inside the engine's closed
/// conform vocabulary. The pass can read this one.
const _mechanicalNote = 'trim 12 frames off the head';

/// Taste. The pass must DECLINE this rather than guess at an op.
const _creativeNote = 'the lower third feels off-brand in the second act';

Future<FakeCyanBackend> engine() async {
  final backend = FakeCyanBackend();
  await backend.initialize();
  return backend;
}

/// Mount the console on an explicit controller so a test drives the walk itself
/// rather than racing the app's own hydrate.
Future<SpineController> mount(
  WidgetTester tester, {
  required FakeCyanBackend backend,
  SpineController? controller,
  Size size = const Size(1100, 1400),
}) async {
  final vm = controller ??
      SpineController(backend: backend, boardId: _board, tenantId: _tenant);
  addTearDown(vm.dispose);
  await vm.hydrate();
  await pumpParity(
    tester,
    ParitySpineView(boardId: _board, tenantId: _tenant, controller: vm),
    backend: backend,
    size: size,
  );
  return vm;
}

/// The spine cloned, its media ingested and its DAG compiled — the state every
/// test past the first one starts from. Driven on the seam, not through the UI:
/// the subject of those tests is what happens AFTER this.
Future<SpineController> spineOn(FakeCyanBackend backend) async {
  final vm =
      SpineController(backend: backend, boardId: _board, tenantId: _tenant);
  await vm.hydrate();
  await vm.cloneSpine();
  await vm.ingestSources();
  await vm.compile();
  return vm;
}

/// Walk the run forward, releasing every gate that has no ritual of its own,
/// until [stop] says we have arrived. Never releases more than the spine has
/// gates, so a test that never arrives fails rather than spins.
Future<void> walkUntil(
    SpineController vm, bool Function(SpineState) stop) async {
  await vm.advance();
  for (var i = 0; i < 24 && !stop(vm.current); i++) {
    if (vm.current.gate == null) break;
    await vm.releaseGate();
  }
}

bool _atPictureLock(SpineState s) => s.isAtPictureLock;
bool _atProduceMaster(SpineState s) => s.isAtProduceMaster;

/// The engine's own view of a step, by the words it was authored with.
PipelineStep stepNamed(PipelineStatus status, String needle) =>
    status.steps.firstWhere((s) => s.title.toLowerCase().contains(needle));

void main() {
  testWidgets('a board clones the multicut review spine template and lands '
      'its steps', (tester) async {
    final backend = await engine();
    final vm = await mount(tester, backend: backend);

    // Cold start: the board has nothing on it, and the console offers the ONE
    // action that changes that.
    expect(vm.current.isCloned, isFalse);
    expect(find.byKey(const ValueKey('spine.clone')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('spine.clone')));
    await tester.pumpAndSettle();

    // The template is the engine's own authored spine, chosen by NAME.
    expect(vm.current.templateName, SpineController.spineTemplateName);

    // Its steps landed on the board as real authorable cells — checked on the
    // ENGINE, not on the console's own count.
    final workflow = await backend.loadWorkflow(_board);
    expect(workflow.steps, hasLength(15));
    expect(workflow.steps.first.text, contains('ingest and probe'));
    expect(workflow.steps.last.text, contains('produce the graded master'));
    // The walk order is the template's, verbatim — the spine's whole contract.
    expect(
      workflow.steps.map((s) => s.text).join(' | '),
      stringContainsInOrder([
        'ingest and probe',
        'producer review',
        'add_markers',
        'picture lock',
        'stage_turnover',
        'cyan-media.conform',
        'apply_look',
        'produce the graded master',
      ]),
    );
    // The template's standing notes travelled with it.
    final notes = await backend.noteListScoped(_board, 'board');
    expect(notes.any((n) => n.text.contains('AUTHORED ORDER IS LAW')), isTrue);

    // And the console has moved on to what is now true.
    expect(find.byKey(const ValueKey('spine.clone')), findsNothing);
    expect(find.byKey(const ValueKey('spine.compile')), findsOneWidget);
  });

  testWidgets('the spine compiles into a runnable DAG', (tester) async {
    final backend = await engine();
    final vm =
        SpineController(backend: backend, boardId: _board, tenantId: _tenant);
    await vm.hydrate();
    await vm.cloneSpine();
    await mount(tester, backend: backend, controller: vm);

    await tester.tap(find.byKey(const ValueKey('spine.compile')));
    await tester.pumpAndSettle();

    // A DAG, not a list: every step but the first waits on the one before it,
    // which is what makes "authored order is law" enforceable at run time.
    final status = await backend.pipelineStatus(_board);
    expect(status.steps, hasLength(15));
    expect(status.steps.first.dependsOn, isEmpty);
    for (var i = 1; i < status.steps.length; i++) {
      expect(status.steps[i].dependsOn, [status.steps[i - 1].stepId]);
    }
    // Compiled and nothing executed yet — the plan, not a run.
    expect(status.status, PipelineRunState.idle);
    expect(status.pending, 15);

    // RUNNABLE: the engine accepts a run against it, which it refuses outright
    // on a board that never compiled.
    expect((await backend.runPipeline(_board)).accepted, isTrue);

    // The console draws the seven rooms the DAG walks through.
    for (final lane in kSpineWalk) {
      expect(find.byKey(ValueKey('spine.lane.${lane.name}')), findsOneWidget);
    }
  });

  testWidgets('running the spine reaches the producer review gate and parks',
      (tester) async {
    final backend = await engine();
    final vm = await spineOn(backend);
    await mount(tester, backend: backend, controller: vm);

    await vm.advance();
    await tester.pumpAndSettle();

    // The ingest room ran and settled on its own; the run stopped dead at the
    // first gate a human owns.
    final gate = vm.current.gate;
    expect(gate, isNotNull);
    expect(gate!.isProducerReview, isTrue);
    expect(gate.lane, SpineLane.review);
    expect(gate.waitingOn, _producer);
    expect(find.byKey(const ValueKey('spine.gate')), findsOneWidget);
    expect(find.text('waiting on $_producer'), findsOneWidget);

    // PARKED means parked. The engine's own state agrees, everything past the
    // gate is still queued, and an UNSCOPED approve cannot move it — a gate
    // with an assignee only ever clears for that assignee.
    final status = await backend.pipelineStatus(_board);
    expect(status.status, PipelineRunState.awaitingApproval);
    expect(status.awaitingStep, gate.id);
    expect(stepNamed(status, 'add_markers').status, PipelineStepState.pending);
    expect(await backend.pipelineApprove(_board, gate.id), isFalse);
    expect((await backend.pipelineStatus(_board)).awaitingStep, gate.id);

    // The review lane opened its round when the proxy went out.
    expect(vm.current.reviewState, 'IN_REVIEW');
  });

  testWidgets('releasing the review gate with notes transpiles them into '
      'proposed ops', (tester) async {
    final backend = await engine();
    final vm = await spineOn(backend);
    await vm.advance();
    await mount(tester, backend: backend, controller: vm);

    // Two notes come back from the producer: one mechanical, one creative. They
    // land through the composer, on the board's own ledger.
    for (final note in const [_mechanicalNote, _creativeNote]) {
      await tester.enterText(
          find.byKey(const ValueKey('spine.note.field')), note);
      await tester.tap(find.byKey(const ValueKey('spine.note.send')));
      await tester.pumpAndSettle();
    }
    expect(vm.current.notes, hasLength(2));
    expect(vm.current.proposedOps, isEmpty);

    await tester.tap(find.byKey(const ValueKey('spine.release.review')));
    await tester.pumpAndSettle();

    // The pass read the notes BEFORE the run was let past the gate. The one
    // that fully specifies an edit is now a PROPOSED op, in the closed conform
    // vocabulary, attributed to the agent and waiting on a human.
    expect(vm.current.agentPassRan, isTrue);
    expect(vm.current.transpiledOps, 1);
    final proposal = vm.current.proposedOps.single;
    expect(proposal.op, 'trim_head');
    expect(proposal.entry.proposedBy, 'agent');
    expect(proposal.state, 'proposed');
    expect(proposal.entry.params['frames'], 12);

    // It is on the ENGINE's ledger, not just on screen, and it references the
    // note it came from rather than overwriting it.
    final lane =
        await backend.changelistCommand({'op': 'list', 'board_id': _board});
    final ops = [for (final e in lane.entries) if (e.kind == 'op') e];
    expect(ops, hasLength(1));
    expect(ops.single.op, 'trim_head');
    expect(find.byKey(ValueKey('spine.entry.${proposal.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('spine.entry.${proposal.id}.approve')),
        findsOneWidget);

    // The creative one was DECLINED with a reason, not silently skipped.
    expect(vm.current.declinedNotes, 1);
    expect(vm.current.creativeNotes.single.text, _creativeNote);

    // And the run moved on past the gate.
    expect(vm.current.gate!.title, contains('add_markers'));
  });

  testWidgets('releasing the review gate without notes continues the run '
      'untouched', (tester) async {
    final backend = await engine();
    final vm = await spineOn(backend);
    await vm.advance();
    await mount(tester, backend: backend, controller: vm);

    // Nobody left a note. The console says so rather than pretending there is
    // work to adjudicate.
    expect(vm.current.ledger, isEmpty);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('spine.gate.notesSummary')))
          .data,
      contains('No notes have come back yet'),
    );
    final held = vm.current.gate!.id;

    await tester.tap(find.byKey(const ValueKey('spine.release.review')));
    await tester.pumpAndSettle();

    // The pass ran and wrote NOTHING — no invented op, no note conjured to
    // justify the round.
    expect(vm.current.agentPassRan, isTrue);
    expect(vm.current.transpiledOps, 0);
    expect(vm.current.declinedNotes, 0);
    final lane =
        await backend.changelistCommand({'op': 'list', 'board_id': _board});
    expect(lane.entries, isEmpty);

    // The run carried straight on: the gate settled and the next one is open.
    final status = await backend.pipelineStatus(_board);
    expect(stepNamed(status, 'producer review').status,
        PipelineStepState.humanApproved);
    expect(vm.current.gate!.id, isNot(held));
    expect(vm.current.gate!.title, contains('add_markers'));
    // A cut nobody had anything to say about is an APPROVED cut, not a
    // conforming one.
    expect(vm.current.reviewState, 'APPROVED');
  });

  testWidgets('a proposed mechanical op can be approved and a creative note '
      'stays a note', (tester) async {
    final backend = await engine();
    final vm = await spineOn(backend);
    await vm.advance();
    await vm.captureReviewNote(_mechanicalNote);
    await vm.captureReviewNote(_creativeNote);
    await vm.releaseReviewGate();
    await mount(tester, backend: backend, controller: vm);

    final proposal = vm.current.proposedOps.single;
    final creative = vm.current.creativeNotes.single;

    // The agent's refusal is on the card, in the agent's own words.
    expect(find.byKey(ValueKey('spine.entry.${creative.id}.declined')),
        findsOneWidget);
    // A note is never offered the op gate — there is nothing to approve.
    expect(find.byKey(ValueKey('spine.entry.${creative.id}.approve')),
        findsNothing);

    await tester.tap(find.byKey(ValueKey('spine.entry.${proposal.id}.approve')));
    await tester.pumpAndSettle();

    // The op is confirmed ON THE ENGINE, and it is the human who confirmed it.
    final lane =
        await backend.changelistCommand({'op': 'list', 'board_id': _board});
    final op = lane.entries.firstWhere((e) => e.id == proposal.id);
    expect(op.state, 'approved');
    expect(op.active, isTrue);
    expect(op.approvedBy, _producer);

    // The creative note is untouched: still a note, still un-adjudicated, and
    // no op anywhere on the ledger was derived from it.
    final note = lane.entries.firstWhere((e) => e.id == creative.id);
    expect(note.kind, 'note');
    expect(note.op, isNull);
    expect(note.state, 'proposed');
    expect(
      [for (final e in lane.entries) if (e.kind == 'op') e.intent],
      isNot(contains(_creativeNote)),
    );
  });

  testWidgets('picture lock releases the sound lane', (tester) async {
    final backend = await engine();
    final vm = await spineOn(backend);
    await walkUntil(vm, _atPictureLock);
    await mount(tester, backend: backend, controller: vm);

    // The cutting room's last step. Until it is confirmed the sound room is
    // shut, and the console names WHAT is holding it rather than just greying
    // the lane out.
    expect(vm.current.isAtPictureLock, isTrue);
    final sound = vm.current.laneFor(SpineLane.sound);
    expect(sound.isOpen, isFalse);
    expect(sound.heldBy!.isPictureLock, isTrue);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('spine.lane.sound.heldBy')))
          .data,
      contains('picture lock'),
    );
    // Nothing in the sound room has run.
    for (final step in sound.steps) {
      expect(step.state, DashboardStepState.pending);
    }

    await tester.tap(find.byKey(const ValueKey('spine.lock')));
    await tester.pumpAndSettle();

    // Confirming FROZE the cut — a version the conform and the delivery both
    // resolve against — and opened the door.
    expect(vm.current.lockedVersion, greaterThan(0));
    expect(vm.current.isPictureLocked, isTrue);
    expect(vm.current.laneFor(SpineLane.sound).isOpen, isTrue);
    expect(find.byKey(const ValueKey('spine.lane.sound.heldBy')), findsNothing);

    // And the run walked INTO the sound room: its first step is the one now
    // parked, on the engine's own reckoning.
    final status = await backend.pipelineStatus(_board);
    expect(stepNamed(status, 'picture lock').status,
        PipelineStepState.humanApproved);
    expect(vm.current.gate!.lane, SpineLane.sound);
    expect(vm.current.gate!.title, contains('stage_turnover'));
  });

  testWidgets('conform and grade steps report their state on the dashboard',
      (tester) async {
    final backend = await engine();
    final vm = await spineOn(backend);
    await walkUntil(vm, _atPictureLock);
    await vm.confirmPictureLock();
    await walkUntil(vm, (s) => s.gate?.lane == SpineLane.color);

    // The conform room has relinked the locked cut and the colour room is the
    // one now waiting on a human.
    expect(vm.current.laneFor(SpineLane.conform).isComplete, isTrue);
    expect(vm.current.gate!.lane, SpineLane.color);

    // The DASHBOARD is where a run is watched, so that is where those two
    // states have to be legible — off the engine's own pipeline read.
    final dashboard = DashboardController(
      backend: backend,
      boardId: _board,
      reviewer: _producer,
    );
    addTearDown(dashboard.dispose);
    await dashboard.hydrate();
    await pumpParity(
      tester,
      ParityDashboardView(boardId: _board, controller: dashboard),
      backend: backend,
      size: const Size(1100, 2200),
    );

    final conform = dashboard.current.steps
        .firstWhere((s) => s.title.contains('cyan-media.conform'));
    final grade = dashboard.current.steps
        .firstWhere((s) => s.title.contains('apply_look'));
    expect(conform.state, DashboardStepState.approved);
    expect(conform.stateLabel, 'Approved');
    expect(grade.state, DashboardStepState.awaitingApproval);
    expect(grade.stateLabel, 'Awaiting you');

    // Both rows are on screen with those states beside them.
    expect(find.text(conform.title), findsWidgets);
    expect(find.text(grade.title), findsWidgets);
    expect(find.text('Awaiting you'), findsWidgets);
    // The grade gate is the one the dashboard is offering a decision on.
    expect(dashboard.current.gates.single.id, grade.id);
  });

  testWidgets('the run finishes and reports a delivered master',
      (tester) async {
    final backend = await engine();
    final vm = await spineOn(backend);
    await walkUntil(vm, _atPictureLock);
    await vm.confirmPictureLock();
    await walkUntil(vm, _atProduceMaster);
    await mount(tester, backend: backend, controller: vm);

    // The last step is the human's hand-off, and nothing has been delivered.
    expect(vm.current.isAtProduceMaster, isTrue);
    expect(vm.current.deliveredMaster, isNull);
    expect(find.byKey(const ValueKey('spine.delivered')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('spine.master')));
    await tester.pumpAndSettle();

    // The delivery came out of the ENGINE's own lane, resolved from the version
    // picture lock froze — the app never named a file.
    final delivered = vm.current.deliveredMaster;
    expect(delivered, isNotNull);
    expect(delivered, contains('/deliveries/'));
    expect(delivered, contains('_v${vm.current.lockedVersion}_master'));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('spine.delivered.path')))
          .data,
      delivered,
    );

    // The run is finished: every step of the spine settled, and the engine says
    // so rather than the console inferring it.
    final status = await backend.pipelineStatus(_board);
    expect(status.status, PipelineRunState.done);
    expect(status.humanApproved, 15);
    expect(status.progressPct, 100);
    expect(vm.current.gate, isNull);
    // The review lane closed with it.
    expect(vm.current.reviewState, 'DELIVERED');
  });

  testWidgets('golden: the spine console parked on the review round',
      (tester) async {
    final backend = await engine();
    final vm = await spineOn(backend);
    await vm.advance();
    await vm.captureReviewNote(_mechanicalNote);
    await vm.captureReviewNote(_creativeNote);
    await vm.releaseReviewGate();
    await mount(tester, backend: backend, controller: vm);
    await expectLater(
      find.byType(ParitySpineView),
      matchesGoldenFile('golden/spine_console.png'),
    );
  }, tags: 'golden');
}
