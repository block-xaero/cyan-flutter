// test/ops_efficiency_test.dart
//
// PARITY_TRACKER row 8 — Ops console: Efficiency. Tier-1: drives
// `ParityOpsEfficiency` through the `CyanBackend` seam (FakeCyanBackend) and
// asserts the five insight cards + the per-step table render. Plus a golden
// (tagged `golden`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/widgets/parity/parity_ops_efficiency.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('renders the insight cards + per-step table', (tester) async {
    await pumpParity(tester, const ParityOpsEfficiency(),
        size: const Size(1000, 700));

    expect(find.textContaining('Efficiency — all boards'), findsOneWidget);

    // The five insight cards.
    expect(find.text('Gate bottleneck'), findsOneWidget);
    expect(find.text('Failure hotspot'), findsOneWidget);
    expect(find.text('Step speed (p95)'), findsOneWidget);
    expect(find.text('Cache efficiency'), findsOneWidget);
    expect(find.text('Retry burden'), findsOneWidget);

    // A computed metric value (142000ms -> 142.0s).
    expect(find.text('142.0s'), findsWidgets);

    // Per-step table with a seeded step + its error class.
    expect(find.text('Per-step'), findsOneWidget);
    expect(find.text('Transcode proxies'), findsWidgets);
    expect(find.text('TranscodeError'), findsWidgets);
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
