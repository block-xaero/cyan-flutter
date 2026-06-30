// test/workflow_view_test.dart
//
// PARITY_TRACKER row 3 — Board: Workflow (author). Tier-1: drives
// `ParityWorkflowView` through the `CyanBackend` seam (FakeCyanBackend) and
// asserts the numbered step cells, compiled inference chips, the deployed/
// locked banner, and the composer render. Plus a golden (tagged `golden`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/widgets/parity/parity_workflow_view.dart';

import 'support/parity_test_harness.dart';

void main() {
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

  testWidgets('golden: workflow author face', (tester) async {
    await pumpParity(tester, const ParityWorkflowView(boardId: 'b-eng-1'));
    await expectLater(
      find.byType(ParityWorkflowView),
      matchesGoldenFile('golden/workflow_author.png'),
    );
  }, tags: 'golden');
}
