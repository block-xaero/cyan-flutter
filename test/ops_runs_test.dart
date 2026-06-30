// test/ops_runs_test.dart
//
// PARITY_TRACKER row 6 — Ops console: Runs. Tier-1: drives `ParityOpsRuns`
// through the `CyanBackend` seam (FakeCyanBackend) and asserts the four lanes,
// the cinematic run cards with status badges + meta, and the action buttons
// (Retry / Approve) fire. Plus a golden (tagged `golden`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/widgets/parity/parity_ops_runs.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('renders the four lanes and seeded run cards', (tester) async {
    await pumpParity(tester, const ParityOpsRuns());

    // Console header + segmented control.
    expect(find.text('Ops console'), findsOneWidget);
    expect(find.text('Runs'), findsOneWidget);
    expect(find.text('Cost'), findsOneWidget);
    expect(find.text('Efficiency'), findsOneWidget);

    // The four lanes.
    expect(find.text('Queued'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Action needed'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    // A failed run shows a Retry action; an awaiting-approval run an Approve.
    expect(find.text('Retry'), findsWidgets);
    expect(find.text('Approve'), findsWidgets);

    // A seeded asset name appears.
    expect(find.text('reel_master_v4.mov'), findsOneWidget);
  });

  testWidgets('Retry fires onRetry with the failed run', (tester) async {
    OpsRun? retried;
    await pumpParity(
      tester,
      ParityOpsRuns(onRetry: (r) => retried = r),
    );

    await tester.tap(find.text('Retry').first);
    await tester.pump();

    expect(retried, isNotNull);
    expect(retried!.status, RunStatus.failed);
  });

  testWidgets('golden: ops runs feed', (tester) async {
    await pumpParity(tester, const ParityOpsRuns());
    await expectLater(
      find.byType(ParityOpsRuns),
      matchesGoldenFile('golden/ops_runs.png'),
    );
  }, tags: 'golden');
}
