// test/autopilot_test.dart
//
// PARITY_TRACKER row 22 — the autopilot control (WorkflowView `workflow.autopilot`)
// and the Auto-approved policy chip (DashboardView `humanSignal`).
//
// The one thing both surfaces exist to guarantee: **the UI never lies about who
// decided.** The toolbar shows the mode the ENGINE holds, not the one that was
// tapped; a gate the policy cleared says "Auto-approved" in its own colour,
// never a generic "Approved" that reads as a person having looked at it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/models/dashboard_event.dart';
import 'package:cyan_flutter/providers/dashboard_controller.dart';
import 'package:cyan_flutter/widgets/parity/parity_dashboard_view.dart';
import 'package:cyan_flutter/widgets/parity/parity_workflow_view.dart';

import 'support/parity_test_harness.dart';

/// A board whose autopilot mode the engine REFUSES to move — the shape of an
/// engine that has the verb but will not take the write.
class _RefusingBackend extends FakeCyanBackend {
  @override
  Future<String> setAutopilotMode(String boardId, String mode) async => 'off';
}

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('workflow.autopilot')));
  await tester.pumpAndSettle();
}

void main() {
  // -------------------------------------------------------------------------
  group('the autopilot control', () {
    testWidgets('a board that has never been flipped reads OFF — the safe '
        'default is that every gate is still yours', (tester) async {
      await pumpParity(tester, const ParityWorkflowView(boardId: 'b-eng-1'),
          size: const Size(1100, 800));

      expect(find.byKey(const ValueKey('workflow.autopilot')), findsOneWidget);
      expect(find.text('Autopilot'), findsOneWidget,
          reason: 'OFF shows the affordance\'s NAME, not the word "off"');
    });

    testWidgets('the menu offers exactly the engine\'s vocabulary, and marks '
        'the mode in force', (tester) async {
      await pumpParity(tester, const ParityWorkflowView(boardId: 'b-eng-1'),
          size: const Size(1100, 800));
      await openMenu(tester);

      for (final m in const ['off', 'assist', 'autopilot']) {
        expect(find.byKey(ValueKey('workflow.autopilot.$m')), findsOneWidget);
      }
      expect(find.text('OFF'), findsOneWidget);
      expect(find.text('ASSIST'), findsOneWidget);
      expect(find.text('AUTOPILOT'), findsOneWidget);
      // The mode in force carries the check.
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('flipping to AUTOPILOT is the adoption act, and flipping back '
        'is the kill switch', (tester) async {
      final backend = FakeCyanBackend();
      await pumpParity(tester, const ParityWorkflowView(boardId: 'b-eng-1'),
          backend: backend, size: const Size(1100, 800));

      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('workflow.autopilot.autopilot')));
      await tester.pumpAndSettle();

      expect(await backend.autopilotMode('b-eng-1'), 'autopilot');
      expect(find.text('AUTOPILOT'), findsOneWidget);

      // …and back off again.
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('workflow.autopilot.off')));
      await tester.pumpAndSettle();

      expect(await backend.autopilotMode('b-eng-1'), 'off');
      expect(find.text('Autopilot'), findsOneWidget);
    });

    testWidgets('the mode is PER BOARD, and re-pointing the face does not '
        'leave the previous board\'s mode on the toolbar', (tester) async {
      final backend = FakeCyanBackend();
      await backend.setAutopilotMode('b-eng-1', 'autopilot');

      await pumpParity(tester, const ParityWorkflowView(boardId: 'b-eng-1'),
          backend: backend, size: const Size(1100, 800));
      expect(find.text('AUTOPILOT'), findsOneWidget);

      await pumpParity(tester, const ParityWorkflowView(boardId: 'b-eng-2'),
          backend: backend, size: const Size(1100, 800));
      expect(find.text('AUTOPILOT'), findsNothing,
          reason: 'b-eng-2 gates on humans; showing b-eng-1\'s mode over it '
              'would claim a delegation nobody made');
      expect(find.text('Autopilot'), findsOneWidget);
    });

    testWidgets('a REFUSED write leaves the toolbar telling the truth',
        (tester) async {
      await pumpParity(tester, const ParityWorkflowView(boardId: 'b-eng-1'),
          backend: _RefusingBackend(), size: const Size(1100, 800));

      await openMenu(tester);
      await tester
          .tap(find.byKey(const ValueKey('workflow.autopilot.autopilot')));
      await tester.pumpAndSettle();

      // The tap asked for AUTOPILOT; the engine kept OFF. The label follows the
      // ENGINE — a toolbar reading AUTOPILOT over a board still gating on
      // humans is exactly the lie this control exists to prevent — and the
      // operator is TOLD rather than left to notice.
      expect(find.text('AUTOPILOT'), findsNothing);
      expect(find.text('Autopilot'), findsOneWidget);
      expect(find.textContaining('kept autopilot on OFF'), findsOneWidget);
    });

    test('an unknown mode is never sent — the engine owns the vocabulary',
        () async {
      final backend = FakeCyanBackend();
      expect(await backend.setAutopilotMode('b-eng-1', 'yolo'), 'off');
      expect(await backend.autopilotMode('b-eng-1'), 'off');
    });
  });

  // -------------------------------------------------------------------------
  group('the Auto-approved chip', () {
    test('a policy clearance is recognised by the engine\'s own prefix', () {
      DagStep step(String? by) => DagStep(
            id: 's1',
            title: 'Producer approval',
            state: DashboardStepState.approved,
            actor: DashboardStepActor.human,
            approvedBy: by,
          );
      expect(step('policy:dev-floor@v0').isPolicyCleared, isTrue);
      expect(step('rick').isPolicyCleared, isFalse);
      expect(step(null).isPolicyCleared, isFalse,
          reason: 'nothing cleared it, so nothing may be claimed');
      // A person whose NAME merely starts with the word is not the policy.
      expect(step('policymaker').isPolicyCleared, isFalse);
    });

    /// The flagship board's producer-review hold — a MANUAL step, so it draws
    /// the human lane, which is the only lane this chip lives in. Run the board
    /// with autopilot in [mode] until that hold is cleared, then mount the face.
    ///
    /// `ws3` is the hold; `ws1`/`ws2` are ordinary gates ahead of it.
    Future<void> settleReviewHold(WidgetTester tester, String mode) async {
      const board = 'b-eng-1';
      const producer = 'producer@studio';
      final backend = FakeCyanBackend();
      await backend.initialize();
      await backend.setAutopilotMode(board, mode);
      await backend.pipelineCompile(board);

      for (final step in const ['ws1', 'ws2']) {
        await backend.runPipeline(board);
        expect(await backend.pipelineApprove(board, step), isTrue,
            reason: 'the fixture could not settle $step');
      }
      await backend.runPipeline(board);
      final ack = await backend.pipelineApproveAs(board, 'ws3', producer);
      expect(ack.success, isTrue, reason: ack.error ?? 'the hold did not clear');

      final status = await backend.pipelineStatus(board);
      final hold = status.steps.firstWhere((s) => s.stepId == 'ws3');
      expect(hold.executor, 'manual',
          reason: 'this fixture depends on ws3 drawing the HUMAN lane');

      final controller = DashboardController(backend: backend, boardId: board);
      addTearDown(controller.dispose);
      await controller.hydrate();
      await pumpParity(
        tester,
        ParityDashboardView(boardId: board, controller: controller),
        backend: backend,
        size: const Size(1200, 1000),
      );
    }

    testWidgets('a gate a PERSON cleared says Approved', (tester) async {
      await settleReviewHold(tester, 'off');
      expect(find.text('Approved'), findsWidgets);
      expect(find.text('Auto-approved'), findsNothing);
    });

    testWidgets('a gate the POLICY cleared says Auto-approved — the UI never '
        'lies about who decided', (tester) async {
      await settleReviewHold(tester, 'autopilot');
      expect(find.text('Auto-approved'), findsWidgets,
          reason: 'a policy clearance drawn as a generic "Approved" reads as a '
              'human having looked at it, which nobody did');
    });

    testWidgets('the card id is the EVIDENCE, and it is reachable',
        (tester) async {
      await settleReviewHold(tester, 'autopilot');
      final tip = tester.widget<Tooltip>(find
          .ancestor(
              of: find.text('Auto-approved').first,
              matching: find.byType(Tooltip))
          .first);
      expect(tip.message, FakeCyanBackend.policyCardId,
          reason: 'a clearance the operator cannot trace back to a card is a '
              'clearance they cannot audit');
    });
  });
}
