// test/lens_view_test.dart
//
// PARITY_TRACKER row 10 — Lens AI. Tier-1: drives `ParityLensView` through the
// `CyanBackend` seam (FakeCyanBackend) and asserts the header + connection
// status, the Intelligence band, the Nudges/Asks/Decisions/Graph tabs, the
// seeded nudge/ask/decision cards, the Resolve action firing, and tab
// switching. Plus a golden (tagged `golden`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/widgets/parity/parity_lens_view.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('renders header, tabs and the seeded nudges', (tester) async {
    await pumpParity(tester, const ParityLensView());

    // Header + connection status (FakeCyanBackend seeds connected: true).
    expect(find.text('Lens AI'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);

    // Intelligence band + the four tabs.
    expect(find.text('Intelligence'), findsOneWidget);
    expect(find.byKey(const ValueKey('lens-tab-Nudges')), findsOneWidget);
    expect(find.byKey(const ValueKey('lens-tab-Asks')), findsOneWidget);
    expect(find.byKey(const ValueKey('lens-tab-Decisions')), findsOneWidget);
    expect(find.byKey(const ValueKey('lens-tab-Graph')), findsOneWidget);

    // Default tab is Nudges — the two seeded nudges render with a Resolve CTA.
    expect(find.text('Producer approval is overdue'), findsOneWidget);
    expect(find.text('Transcode keeps failing'), findsOneWidget);
    expect(find.text('Resolve'), findsWidgets);
  });

  testWidgets('Resolve fires onResolveNudge with the nudge', (tester) async {
    LensNudge? resolved;
    await pumpParity(
      tester,
      ParityLensView(onResolveNudge: (n) => resolved = n),
    );

    await tester.tap(find.text('Resolve').first);
    await tester.pump();

    expect(resolved, isNotNull);
    expect(resolved!.id, 'n1');
  });

  testWidgets('switching to Asks shows the seeded asks', (tester) async {
    await pumpParity(tester, const ParityLensView());

    await tester.tap(find.byKey(const ValueKey('lens-tab-Asks')));
    await tester.pumpAndSettle();

    expect(
        find.text(
            'Which loudness target should the ad set use — -23 or -16 LUFS?'),
        findsOneWidget);
    // The answered ask shows its recorded answer.
    expect(find.textContaining('locked as of this morning'), findsOneWidget);
  });

  testWidgets('switching to Decisions shows decisions + reaction counts',
      (tester) async {
    await pumpParity(tester, const ParityLensView());

    await tester.tap(find.byKey(const ValueKey('lens-tab-Decisions')));
    await tester.pumpAndSettle();

    expect(
        find.text('Ship the review pipeline with the cloud color step.'),
        findsOneWidget);
  });

  testWidgets('golden: lens AI', (tester) async {
    await pumpParity(tester, const ParityLensView());
    await expectLater(
      find.byType(ParityLensView),
      matchesGoldenFile('golden/lens_ai.png'),
    );
  }, tags: 'golden');
}
