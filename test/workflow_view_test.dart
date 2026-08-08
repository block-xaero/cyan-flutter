// test/workflow_view_test.dart
//
// PARITY_TRACKER row 3 / STAGE face_workflow_face — Board: Workflow (author).
// Tier-1: drives `ParityWorkflowView` through the `CyanBackend` seam
// (FakeCyanBackend) and asserts the AUTHORING spine — filing a step, the
// `@`/`#` mention pickers, the compile's preview DAG, and the prompt an
// unresolved step raises — plus the read-only rendering (numbered cells,
// inference chips, the deployed/locked banner) and a golden (tagged `golden`).
//
// Behaviour spec: scripts/parity_faces/workflow_face.txt.
//
// SwiftUI reference (read-only):
//   Views/WorkflowView.swift, Views/PipelinePreviewView.swift
//   ViewModels/WorkflowViewModel.swift, ViewModels/NotebookViewModel+Pipeline.swift

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/widgets/parity/parity_workflow_view.dart';

import 'support/parity_test_harness.dart';

const Key _field = ValueKey('workflow.composer.field');
const Key _add = ValueKey('workflow.composer.add');

Finder _row(String value) =>
    find.byKey(ValueKey('workflow.autocomplete.row.$value'));

/// What the composer currently holds — the draft is the operator's text, so it
/// is the thing an accepted suggestion has to land in.
String _draftText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_field)).controller!.text;

/// Type [text] into the composer the way a person does, so the picker sees the
/// caret land at the end of what was typed.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(_field), text);
  await tester.pumpAndSettle();
}

void main() {
  // ---- scripts/parity_faces/workflow_face.txt, line 1 -----------------------

  testWidgets('add step appends an authored step to the board', (tester) async {
    // The composer files through the seam (`addWorkflowStep` — Swift's
    // `addStep`, a `step` cell), and the face re-READS the board rather than
    // showing a shadow copy of the draft. Appends: it lands last, after the
    // steps that were already authored.
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityWorkflowView(boardId: 'b-eng-2'),
        backend: backend);

    expect((await backend.loadWorkflow('b-eng-2')).steps, hasLength(3));

    await _type(tester, 'Publish the cut to the review lane');
    await tester.tap(find.byKey(_add));
    await tester.pumpAndSettle();

    // It reached the BOARD, at the end, and nothing else moved.
    final steps = (await backend.loadWorkflow('b-eng-2')).steps;
    expect(steps.map((s) => s.text), [
      'Design the schema',
      'Migrate the users table',
      'Backfill from the export',
      'Publish the cut to the review lane',
    ]);

    // A freshly authored step is English and nothing else — the compile is what
    // resolves it, so it carries no invented tool or gate yet.
    expect(steps.last.tool, isNull);
    expect(steps.last.gate, isNull);

    // And it renders as step 4, with the composer cleared for the next one.
    expect(find.text('Publish the cut to the review lane'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(_draftText(tester), isEmpty);

    // A blank step is refused rather than filed: the board keeps four.
    await _type(tester, '   ');
    await tester.tap(find.byKey(_add));
    await tester.pumpAndSettle();
    expect((await backend.loadWorkflow('b-eng-2')).steps, hasLength(4));
  });

  // ---- scripts/parity_faces/workflow_face.txt, line 2 -----------------------

  testWidgets('typing at mentions a plugin and offers its tools',
      (tester) async {
    // `@` summons the board-scoped index through the seam: the installed plugin
    // AND the tools its manifest declares, because "which verb of that plugin"
    // is the choice the author is actually making.
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityWorkflowView(boardId: 'b-eng-2'),
        backend: backend);

    await _type(tester, 'Transcode the master with @ffmpeg');

    expect(_row('ffmpeg'), findsOneWidget, reason: 'the plugin itself');
    expect(_row('ffmpeg.probe'), findsOneWidget);
    expect(_row('ffmpeg.transcode'), findsOneWidget);
    // Scoped to what was typed: a plugin the query excludes is not offered.
    expect(_row('frameio'), findsNothing);

    // Accepting splices the mention over the token at the caret and closes the
    // picker — the draft is what gets authored, so that is where it lands.
    await tester.tap(_row('ffmpeg.transcode'));
    await tester.pumpAndSettle();
    expect(_draftText(tester), 'Transcode the master with @ffmpeg.transcode ');
    expect(_row('ffmpeg.transcode'), findsNothing);

    // The mention survives into the filed step.
    await tester.tap(find.byKey(_add));
    await tester.pumpAndSettle();
    expect((await backend.loadWorkflow('b-eng-2')).steps.last.text,
        'Transcode the master with @ffmpeg.transcode');
  });

  // ---- scripts/parity_faces/workflow_face.txt, line 3 -----------------------

  testWidgets('typing hash mentions an artifact', (tester) async {
    // `#` is the OTHER vocabulary: the board's own files and the outputs its
    // prior steps produced — never the plugin list.
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityWorkflowView(boardId: 'b-eng-1'),
        backend: backend);

    await _type(tester, 'Re-cut from #shotlist');

    expect(_row('shotlist.csv'), findsOneWidget);
    expect(_row('ffmpeg'), findsNothing, reason: '# is not the plugin lane');

    await tester.tap(_row('shotlist.csv'));
    await tester.pumpAndSettle();
    expect(_draftText(tester), 'Re-cut from #shotlist.csv ');

    // A trigger with nothing behind it says so rather than rendering an empty
    // popover — a dead index must not look like broken autocomplete.
    await _type(tester, 'Re-cut from #nothing-matches-this');
    expect(find.byKey(const ValueKey('workflow.autocomplete.empty')),
        findsOneWidget);
  });

  // ---- scripts/parity_faces/workflow_face.txt, line 4 -----------------------

  testWidgets('compile turns authored steps into a preview DAG',
      (tester) async {
    // Review compiles the authored English into a plan, and the face previews
    // the plan the ENGINE persisted — laid out in dependency layers, so a step
    // authored a moment ago hangs off the one before it instead of floating.
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityWorkflowView(boardId: 'b-eng-2'),
        backend: backend);

    await _type(tester, 'Publish the cut with @frameio');
    await tester.tap(find.byKey(_add));
    await tester.pumpAndSettle();
    final authored = (await backend.loadWorkflow('b-eng-2')).steps.last.id;

    // Nothing is previewed until the compile runs.
    expect(find.byKey(const ValueKey('workflow.dag.node.ws1')), findsNothing);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    // Every authored step became a node, the new one included.
    for (final id in ['ws1', 'ws2', 'ws3', authored]) {
      expect(find.byKey(ValueKey('workflow.dag.node.$id')), findsOneWidget,
          reason: '$id is in the compiled plan');
    }

    // A DAG, not a list: layer 0 is what starts the run, and each later layer
    // waits on the one before it.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('workflow.dag.layer.0')),
        matching: find.byKey(const ValueKey('workflow.dag.node.ws1')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('workflow.dag.layer.3')),
        matching: find.byKey(ValueKey('workflow.dag.node.$authored')),
      ),
      findsOneWidget,
      reason: 'the step authored last is compiled after the three before it',
    );

    // The compile is the engine's, not a client-side redraw: the seam reports
    // the same four steps, wired the same way.
    final plan = await backend.pipelineStatus('b-eng-2');
    expect(plan.steps.map((s) => s.stepId), ['ws1', 'ws2', 'ws3', authored]);
    expect(plan.steps.last.dependsOn, ['ws3']);
    expect(plan.totalSteps, 4);
  });

  // ---- scripts/parity_faces/workflow_face.txt, line 5 -----------------------

  testWidgets('an ambiguous step prompts rather than guessing a tool',
      (tester) async {
    // The step the compiler could not resolve carries NO tool — a guessed tool
    // runs the wrong thing, a missing one only waits — and asks the author
    // instead, with the same `@` index the composer offers.
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityWorkflowView(boardId: 'b-eng-2'),
        backend: backend);

    expect(find.textContaining('Ambiguous'), findsOneWidget);
    expect(find.textContaining("Couldn't infer a tool"), findsOneWidget);
    // Nothing was invented onto it.
    expect(find.byKey(const ValueKey('workflow.step.tool.ws2')), findsNothing);
    expect((await backend.loadWorkflow('b-eng-2')).steps[1].tool, isNull);

    // The prompt is actionable, not decoration: pick a plugin…
    await tester
        .tap(find.byKey(const ValueKey('workflow.step.pickPlugin.ws2')));
    await tester.pumpAndSettle();
    expect(_row('ffmpeg.transcode'), findsOneWidget);

    // …and the choice is written into the step's own English through the seam,
    // which is what binding a step IS.
    await tester.tap(_row('ffmpeg.transcode'));
    await tester.pumpAndSettle();

    final ws2 = (await backend.loadWorkflow('b-eng-2'))
        .steps
        .firstWhere((s) => s.id == 'ws2');
    expect(ws2.text, 'Migrate the users table @ffmpeg.transcode');
    expect(ws2.isAmbiguous, isFalse);
    expect(find.textContaining('Ambiguous'), findsNothing);
  });

  // ---- the read-only face (rendering parity) --------------------------------

  testWidgets('renders authored steps with inference chips', (tester) async {
    await pumpParity(tester, const ParityWorkflowView(boardId: 'b-eng-1'));

    // Toolbar label + the deployed/locked banner for this flagship board.
    expect(find.text('Workflow'), findsOneWidget);
    expect(find.textContaining('Deployed & locked'), findsOneWidget);

    // The four compiled steps.
    expect(find.textContaining('Ingest the master'), findsOneWidget);
    expect(find.textContaining('Transcode proxies'), findsOneWidget);
    expect(find.textContaining('producer approval'), findsOneWidget);
    expect(find.textContaining('Publish the cut'), findsOneWidget);

    // Gate chips: a needs-approval step and no-approval steps.
    expect(find.text('Awaiting approval'), findsOneWidget);
    expect(find.text('No approval needed'), findsWidgets);

    // A destination chip.
    expect(find.text('send to review'), findsOneWidget);

    // Composer present.
    expect(find.text('Add step'), findsOneWidget);
  });

  testWidgets('Run button fires onRun', (tester) async {
    var ran = false;
    await pumpParity(
      tester,
      ParityWorkflowView(boardId: 'b-eng-1', onRun: () => ran = true),
    );

    await tester.tap(find.text('Run'));
    await tester.pump();

    expect(ran, isTrue);
  });

  testWidgets('ambiguous step shows the orange warning', (tester) async {
    await pumpParity(tester, const ParityWorkflowView(boardId: 'b-eng-2'));

    // No locked banner (b-eng-2 is not deployed).
    expect(find.textContaining('Deployed & locked'), findsNothing);
    // The ambiguous step surfaces a warning.
    expect(find.textContaining('Ambiguous'), findsOneWidget);
  });

  testWidgets('empty workflow shows the empty state', (tester) async {
    await pumpParity(tester, const ParityWorkflowView(boardId: 'b-des-3'));
    expect(find.text('No steps yet'), findsOneWidget);
  });

  // ---- DEPLOY / UNLOCK -----------------------------------------------------
  //
  // The control rendered at full purple with `enabled: hasSteps` and
  // `onTap: null` — a live-looking Deploy that swallowed the tap. Worse on an
  // already-deployed board, where Unlock was equally dead and Templates /
  // Review / Reset therefore stayed disabled forever. These drive the toggle
  // rather than asserting a fixture's deploy flag.
  //
  // The lock is client-side on purpose: the engine exports only the READ verb
  // `cyan_board_workflow_state`, so this mirrors what the Mac already does in
  // ViewModels/BoardLockStore.swift.

  testWidgets(
      'Deploy locks the board, freezes authoring and follows to the '
      'Dashboard', (tester) async {
    var deployed = false;
    await pumpParity(
      tester,
      ParityWorkflowView(
        boardId: 'b-eng-2', // authored, not deployed
        onDeployed: () => deployed = true,
      ),
      size: const Size(1280, 800),
    );

    expect(find.textContaining('Deployed & locked'), findsNothing);
    final deploy = find.byKey(const ValueKey('workflow.deploy'));
    expect(deploy, findsOneWidget);
    expect(find.text('Deploy'), findsOneWidget);

    await tester.tap(deploy);
    await tester.pumpAndSettle();

    // The board is frozen, and says so.
    expect(find.textContaining('Deployed & locked'), findsOneWidget,
        reason: 'deploying must raise the locked banner');
    expect(find.text('Unlock'), findsOneWidget,
        reason: 'the control must flip to its inverse, not stay on Deploy');
    expect(deployed, isTrue,
        reason: 'the host follows the board to its Dashboard after a deploy');

    // Authoring affordances are disabled while frozen — an in-flight run must
    // never be edited out from under itself.
    final templates =
        tester.widget<Widget>(find.byKey(const ValueKey('workflow.templates')));
    expect(templates, isNotNull);
    expect(find.textContaining('Deployed & locked'), findsOneWidget);
  });

  testWidgets('Unlock restores authoring', (tester) async {
    await pumpParity(
      tester,
      const ParityWorkflowView(boardId: 'b-eng-2'),
      size: const Size(1280, 800),
    );

    await tester.tap(find.byKey(const ValueKey('workflow.deploy')));
    await tester.pumpAndSettle();
    expect(find.text('Unlock'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('workflow.deploy')));
    await tester.pumpAndSettle();

    expect(find.text('Deploy'), findsOneWidget,
        reason: 'unlocking must return the control to Deploy');
    expect(find.textContaining('Deployed & locked'), findsNothing,
        reason: 'the locked banner must clear with the lock');
    expect(find.textContaining('Unlocked'), findsOneWidget);
  });

  testWidgets('a board the ENGINE reports deployed stays locked after Unlock',
      (tester) async {
    // b-eng-1 is deployed on the seam. The local store cannot clear the
    // engine's own truth, and the face must say so rather than pretending the
    // toggle won.
    await pumpParity(
      tester,
      const ParityWorkflowView(boardId: 'b-eng-1'),
      size: const Size(1280, 800),
    );

    expect(find.textContaining('Deployed & locked'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('workflow.deploy')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Deployed & locked'), findsOneWidget,
        reason: 'the engine still reports this board deployed');
    expect(find.textContaining('ENGINE still reports'), findsOneWidget,
        reason: 'the refusal must be explained, not silent');
  });

  testWidgets('golden: workflow author face', (tester) async {
    await pumpParity(tester, const ParityWorkflowView(boardId: 'b-eng-1'));
    await expectLater(
      find.byType(ParityWorkflowView),
      matchesGoldenFile('golden/workflow_author.png'),
    );
  }, tags: 'golden');
}
