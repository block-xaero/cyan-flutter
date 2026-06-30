// test/dashboard_view_test.dart
//
// PARITY_TRACKER row 4 — Board: Dashboard (DAG + gated run). Tier-1: drives
// `ParityDashboardView` through the `CyanBackend` seam (FakeCyanBackend) and
// asserts the run header + status pill, the DAG step boxes, the approval gate
// (Approve/Complete), the collapsed step list, and the no-run empty state.
// Plus a golden (tagged `golden`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/widgets/parity/parity_dashboard_view.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('renders the run header, DAG and step list', (tester) async {
    await pumpParity(tester, const ParityDashboardView(boardId: 'b-eng-1'));

    // Run header (title from the seeded run).
    expect(find.text('Render + Review Pipeline'), findsOneWidget);
    expect(find.text('Workflow'), findsOneWidget); // DAG section label
    expect(find.text('Steps'), findsOneWidget); // step-list label

    // The four steps appear (in both the DAG box and the list).
    expect(find.textContaining('Ingest assets'), findsWidgets);
    expect(find.textContaining('Producer approval'), findsWidgets);

    // A status pill is shown (Running, because a step is awaiting approval).
    expect(find.text('Running'), findsOneWidget);
  });

  testWidgets('approval gate shows Approve/Complete for the pending step',
      (tester) async {
    await pumpParity(tester, const ParityDashboardView(boardId: 'b-eng-1'));

    // The pending step is a human step -> a "Complete" gate button.
    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('Awaiting you'), findsWidgets);
  });

  testWidgets('Complete fires onApprove with the pending step', (tester) async {
    RunStep? approved;
    await pumpParity(
      tester,
      ParityDashboardView(
        boardId: 'b-eng-1',
        onApprove: (s) => approved = s,
      ),
    );

    await tester.tap(find.text('Complete'));
    await tester.pump();

    expect(approved, isNotNull);
    expect(approved!.id, 's3');
  });

  testWidgets('a board with no run shows the empty state', (tester) async {
    await pumpParity(tester, const ParityDashboardView(boardId: 'b-eng-2'));
    expect(find.text('No run yet'), findsOneWidget);
  });

  testWidgets('golden: dashboard DAG + gated run', (tester) async {
    await pumpParity(tester, const ParityDashboardView(boardId: 'b-eng-1'));
    await expectLater(
      find.byType(ParityDashboardView),
      matchesGoldenFile('golden/dashboard_dag.png'),
    );
  }, tags: 'golden');
}
