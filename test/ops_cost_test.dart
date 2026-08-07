// test/ops_cost_test.dart
//
// PARITY_TRACKER row 7 / 19 — Ops console: Cost (asset-minute meter). Tier-1:
// drives `ParityOpsCost` through the `LensApi` seam (FakeLensApi) and asserts
// that the five-stat headline, the GPU=COGS footnote and the per-workflow
// reconcile table are the §4 ROLLUP of the seeded `/api/v1/runs` feed — not
// numbers a fake handed over pre-computed. Plus a golden (tagged `golden`).
//
// The arithmetic being asserted, from the seed (3 metered runs of 6):
//   billed-min  9.6 + 4.0 + 2.5           = 16.1
//   billed  $   288c + 120c + 75c         = $4.83
//   retry-min   0 + 0 + 2.5               = 2.5
//   saved-min   3.2 (one cache hit)       = 3.2
//   runs        every run in the feed     = 6
// A fake that seeded "16.1" directly would prove none of it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/widgets/parity/parity_ops_cost.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('renders the asset-minute meter headline + reconcile table',
      (tester) async {
    await pumpParity(tester, const ParityOpsCost());

    // Scope header.
    expect(find.textContaining('Asset-minute meter'), findsOneWidget);

    // Five-stat headline labels.
    expect(find.text('billed-min'), findsWidgets);
    expect(find.text('saved-min'), findsOneWidget);
    expect(find.text('runs'), findsWidgets);

    // The headline values, summed from the feed's per-run meter.
    expect(find.text('16.1'), findsOneWidget); // billed minutes
    expect(find.text('\$4.83'), findsOneWidget); // billed dollars
    expect(find.text('2.5'), findsWidgets); // retry minutes
    expect(find.text('3.2'), findsWidgets); // cache-saved minutes
    expect(find.text('6'), findsWidgets); // runs — including the unmetered ones

    // GPU = COGS footnote (margin, not billed). 42.5 + 8 gpu-seconds ride on
    // the same rows and are NOT what billed $ reports.
    expect(find.textContaining('internal COGS'), findsOneWidget);
    expect(find.textContaining('gpu-sec'), findsOneWidget);

    // Per-workflow reconcile table, grouped by board and resolved to the board
    // NAME through the FFI seam's tree — heaviest bill first.
    expect(find.text('Per-workflow'), findsOneWidget);
    expect(find.text('Render + Review Pipeline'), findsOneWidget); // 13.6 min
    expect(find.text('Database Schema'), findsOneWidget); // 2.5 min
    expect(find.text('CI/CD Pipeline'), findsOneWidget); // unmetered
  });

  testWidgets('golden: ops cost meter', (tester) async {
    await pumpParity(tester, const ParityOpsCost());
    await expectLater(
      find.byType(ParityOpsCost),
      matchesGoldenFile('golden/ops_cost.png'),
    );
  }, tags: 'golden');
}
