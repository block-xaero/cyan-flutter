// test/ops_runs_test.dart
//
// PARITY_TRACKER row 6 / 19 — Ops console: Runs. Tier-1: drives `ParityOpsRuns`
// through the `LensApi` seam (FakeLensApi) and asserts the four lanes, the
// cinematic run cards, and — new under D3 — that the three actions are REAL:
// Retry / Approve / Reject POST to the lens, the refusal is shown, and the
// optional callbacks still override. Plus a golden (tagged `golden`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/lens/fake_lens_api.dart';
import 'package:cyan_flutter/lens/lens_api.dart';
import 'package:cyan_flutter/widgets/parity/parity_ops_runs.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('renders the four lanes and the feed\'s run cards',
      (tester) async {
    // Tall surface so the lazily-built lanes/cards all lay out (the feed
    // scrolls in production; here we want every lane present to assert on).
    await pumpParity(tester, const ParityOpsRuns(),
        size: const Size(1000, 1700));

    // Console header + segmented control.
    expect(find.text('Ops console'), findsOneWidget);
    expect(find.text('Runs'), findsOneWidget);
    expect(find.text('Cost'), findsOneWidget);
    expect(find.text('Efficiency'), findsOneWidget);

    // The four lanes. Lane headers are matched by key (the parity status badges
    // legitimately reuse the words "Queued"/"Running"/"Done", exactly as the
    // SwiftUI console disambiguates lanes by accessibilityIdentifier).
    expect(find.byKey(const ValueKey('ops-lane-Queued')), findsOneWidget);
    expect(find.byKey(const ValueKey('ops-lane-Running')), findsOneWidget);
    expect(find.byKey(const ValueKey('ops-lane-Action needed')), findsOneWidget);
    expect(find.byKey(const ValueKey('ops-lane-Done')), findsOneWidget);

    // A failed run shows a Retry action; an awaiting-approval run a gate.
    expect(find.text('Retry'), findsWidgets);
    expect(find.text('Approve'), findsWidgets);
    expect(find.text('Reject'), findsWidgets);

    // The asset name off the feed, and the CUSTOMER bill (billed_cents), not
    // the GPU cost that rides on the same row.
    expect(find.text('big-buck-bunny.mp4'), findsOneWidget);
    expect(find.text('\$2.88'), findsOneWidget);

    // A STUCK run lanes with the action-needed set, not with Running — the
    // lens lanes it In-flight but the operator has to do something about it.
    expect(find.text('archive-restore.mxf'), findsOneWidget);
  });

  testWidgets('Retry POSTs to the lens and re-reads the feed', (tester) async {
    final lens = FakeLensApi();
    await pumpParity(tester, const ParityOpsRuns(),
        lens: lens, size: const Size(1000, 1700));

    await tester.tap(find.text('Retry').first);
    await tester.pumpAndSettle();

    final retries = [for (final c in lens.calls) if (c.method == 'retry') c];
    expect(retries, hasLength(1),
        reason: 'the button must reach the lens — a console whose actions are '
            'UI-only is a console that lies about what it did');
    expect(retries.single.args['id'], 'run-fail-3');

    // …and the feed was re-read, so the run has left the Failed lane.
    expect(lens.calls.where((c) => c.method == 'runs').length, greaterThan(1));
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('Approve and Reject are separate lens commands', (tester) async {
    final lens = FakeLensApi();
    await pumpParity(tester, const ParityOpsRuns(),
        lens: lens, size: const Size(1000, 1700));

    await tester.tap(find.text('Reject').first);
    await tester.pumpAndSettle();
    expect(lens.calls.where((c) => c.method == 'reject').single.args['id'],
        'run-gate-2');
    expect(lens.calls.any((c) => c.method == 'approve'), isFalse,
        reason: 'Reject must not route through the approve verb');
  });

  testWidgets('the lens\'s REFUSAL is shown, not swallowed', (tester) async {
    // A lens that refuses everything with its own plain-text reason.
    final lens = FakeLensApi(
      failWith: const LensApiException(
          'CONFLICT only a Failed run can be retried',
          statusCode: 409),
    );
    await pumpParity(tester, const ParityOpsRuns(),
        lens: lens, size: const Size(1000, 1700));

    // The feed itself failed, so the face names that rather than drawing four
    // empty lanes — an empty board would read as "no runs".
    expect(find.byKey(const ValueKey('ops-runs-error')), findsOneWidget);
    expect(find.textContaining('only a Failed run'), findsWidgets);
  });

  testWidgets('a supplied callback OVERRIDES the lens command', (tester) async {
    final lens = FakeLensApi();
    OpsRun? retried;
    await pumpParity(
      tester,
      ParityOpsRuns(onRetry: (r) => retried = r),
      lens: lens,
      size: const Size(1000, 1700),
    );

    await tester.tap(find.text('Retry').first);
    await tester.pumpAndSettle();

    expect(retried, isNotNull);
    expect(retried!.status, RunStatus.failed);
    expect(lens.calls.any((c) => c.method == 'retry'), isFalse,
        reason: 'a host that intercepts the action (to confirm first) must not '
            'ALSO have the command fired underneath it');
  });

  testWidgets('golden: ops runs feed', (tester) async {
    await pumpParity(tester, const ParityOpsRuns());
    await expectLater(
      find.byType(ParityOpsRuns),
      matchesGoldenFile('golden/ops_runs.png'),
    );
  }, tags: 'golden');
}
