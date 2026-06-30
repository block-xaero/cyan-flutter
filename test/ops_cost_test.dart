// test/ops_cost_test.dart
//
// PARITY_TRACKER row 7 — Ops console: Cost (asset-minute meter). Tier-1:
// drives `ParityOpsCost` through the `CyanBackend` seam (FakeCyanBackend) and
// asserts the five-stat headline, the GPU=COGS footnote, and the per-workflow
// reconcile table render. Plus a golden (tagged `golden`).

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

    // The headline values from the seed.
    expect(find.text('24.5'), findsOneWidget); // billed minutes
    expect(find.text('\$12.30'), findsOneWidget); // billed dollars

    // GPU = COGS footnote (margin, not billed).
    expect(find.textContaining('internal COGS'), findsOneWidget);
    expect(find.textContaining('gpu-sec'), findsOneWidget);

    // Per-workflow reconcile table has the seeded workflows.
    expect(find.text('Per-workflow'), findsOneWidget);
    expect(find.text('Render + Review Pipeline'), findsOneWidget);
    expect(find.text('Design System'), findsOneWidget);
  });

  testWidgets('golden: ops cost meter', (tester) async {
    await pumpParity(tester, const ParityOpsCost());
    await expectLater(
      find.byType(ParityOpsCost),
      matchesGoldenFile('golden/ops_cost.png'),
    );
  }, tags: 'golden');
}
