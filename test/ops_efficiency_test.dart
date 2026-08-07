// test/ops_efficiency_test.dart
//
// PARITY_TRACKER row 8 / 19 — Ops console: Efficiency. Tier-1: drives
// `ParityOpsEfficiency` through the `LensApi` seam (FakeLensApi) and asserts
// the five insight cards + the per-step table are the §5 ROLLUP of the seeded
// `/api/v1/runs` feed. Plus a golden (tagged `golden`).
//
// What the seed's 8 step-executions roll up to, grouped by AUTHORED action
// (the step id changes per execution; the action is the stable identity):
//   transcode  3 executions, exec p95 60000ms
//   qc         1 execution, a cache hit — billed 0, 3.2 min saved
//   deliver    2 executions, gate p95 3_540_000ms (the human bottleneck)
//   conform    2 executions, 1 failed (conform_mismatch), 1 retried
// ⇒ cache 1/8 = 13%, retry 1/8 = 12.5%, failure hotspot = conform at 50%.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/widgets/parity/parity_ops_efficiency.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('renders the insight cards + per-step table', (tester) async {
    await pumpParity(tester, const ParityOpsEfficiency(),
        size: const Size(1000, 900));

    expect(find.textContaining('Efficiency — all boards'), findsOneWidget);

    // The five insight cards.
    expect(find.text('Gate bottleneck'), findsOneWidget);
    expect(find.text('Failure hotspot'), findsOneWidget);
    expect(find.text('Step speed (p95)'), findsOneWidget);
    expect(find.text('Cache efficiency'), findsOneWidget);
    expect(find.text('Retry burden'), findsOneWidget);

    // The gate bottleneck is the step HUMANS sit on longest, and it names the
    // step rather than reporting a tenant average.
    expect(find.text('3540.0s'), findsWidgets);
    expect(find.textContaining('deliver · p95 wait'), findsOneWidget);

    // The failure hotspot reads its OWN rate (1 of conform's 2 executions),
    // not the 12.5% tenant-wide figure, and carries the error class. The 50%
    // also appears in the per-step table (conform's fail AND retry columns),
    // so the card is identified by its detail line.
    expect(find.text('50.0%'), findsWidgets);
    expect(find.textContaining('conform · conform_mismatch'), findsOneWidget);

    // Slowest executing step.
    expect(find.textContaining('slowest: transcode'), findsOneWidget);

    // Cache + retry are genuinely tenant-wide questions.
    expect(find.text('13%'), findsOneWidget); // 1 of 8 executions cached
    expect(find.textContaining('3.2 min saved'), findsOneWidget);
    expect(find.text('12.5%'), findsOneWidget); // 1 of 8 re-ran

    // Per-step table, in first-seen (authored) order.
    expect(find.text('Per-step'), findsOneWidget);
    expect(find.text('transcode'), findsWidgets);
    expect(find.text('qc'), findsWidgets);
    expect(find.text('deliver'), findsWidgets);
    expect(find.text('conform'), findsWidgets);
    expect(find.text('conform_mismatch'), findsWidgets);
  });

  testWidgets('golden: ops efficiency', (tester) async {
    await pumpParity(tester, const ParityOpsEfficiency(),
        size: const Size(1000, 700));
    await expectLater(
      find.byType(ParityOpsEfficiency),
      matchesGoldenFile('golden/ops_efficiency.png'),
    );
  }, tags: 'golden');
}
