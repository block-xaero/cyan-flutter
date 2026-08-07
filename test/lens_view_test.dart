// test/lens_view_test.dart
//
// PARITY_TRACKER row 10 / 21 — Lens AI. Tier-1: drives `ParityLensView` through
// the `LensApi` seam (FakeLensApi) and asserts the header + connection status,
// the Intelligence band, the Nudges/Asks/Decisions/Graph tabs, the cards, and —
// new under D3 — that the three actions are REAL lens writes with the right
// verb behind each. Plus a golden (tagged `golden`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/lens/fake_lens_api.dart';
import 'package:cyan_flutter/lens/lens_api.dart';
import 'package:cyan_flutter/widgets/parity/parity_lens_view.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('renders header, tabs and the nudge report', (tester) async {
    await pumpParity(tester, const ParityLensView());

    // The connection claim is `/health`'s to make, and nothing else's.
    expect(find.text('Lens AI'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);

    // Intelligence band + the four tabs.
    expect(find.text('Intelligence'), findsOneWidget);
    expect(find.byKey(const ValueKey('lens-tab-Nudges')), findsOneWidget);
    expect(find.byKey(const ValueKey('lens-tab-Asks')), findsOneWidget);
    expect(find.byKey(const ValueKey('lens-tab-Decisions')), findsOneWidget);
    expect(find.byKey(const ValueKey('lens-tab-Graph')), findsOneWidget);

    // A lens nudge has NO free-form title: the title is a function of
    // `nudge_type` and the detail is the thing it points at. The old fake
    // seeded headlines ("Producer approval is overdue") the lens never sends,
    // so the face now shows the lens's own vocabulary.
    expect(find.text('Stale Question'), findsOneWidget);
    expect(find.text('Stale Blocker'), findsOneWidget);
    expect(
        find.text(
            'Which loudness target should the ad set use — -23 or -16 LUFS?'),
        findsOneWidget);
    expect(find.text('CYAN-441'), findsOneWidget);
    // Nudge ages carry no "ago" on this shape — the ask/decision rows do.
    expect(find.text('1h'), findsOneWidget);
    expect(find.text('4d'), findsOneWidget);
    expect(find.text('Resolve'), findsWidgets);
  });

  testWidgets('Resolve sends the verb the nudge TYPE calls for — dismiss for '
      'an ask, resolve-blocker for a node', (tester) async {
    final lens = FakeLensApi();
    await pumpParity(tester, const ParityLensView(), lens: lens);

    // First card is the stale ASK.
    await tester.tap(find.text('Resolve').first);
    await tester.pumpAndSettle();
    expect(lens.dismissed, contains('ask-1'));
    expect(lens.resolvedBlockers, isEmpty,
        reason: 'a stale ask resolved through the blocker verb is a silent '
            'no-op — the ask stays on the board and the operator is not told');

    // The second card is the stale BLOCKER. (The dismissed ask has left the
    // ask feed, but the nudge report is what this tab draws.)
    await tester.tap(find.text('Resolve').last);
    await tester.pumpAndSettle();
    expect(lens.resolvedBlockers, contains('node-blocker-1'));
  });

  testWidgets('a supplied callback OVERRIDES the lens write', (tester) async {
    final lens = FakeLensApi();
    LensNudge? resolved;
    await pumpParity(
      tester,
      ParityLensView(onResolveNudge: (n) => resolved = n),
      lens: lens,
    );

    await tester.tap(find.text('Resolve').first);
    await tester.pumpAndSettle();

    expect(resolved, isNotNull);
    expect(resolved!.id, 'ask-1');
    expect(resolved!.nudgeType, 'stale_ask');
    expect(lens.dismissed, isEmpty,
        reason: 'a host that intercepts must not have the write fired '
            'underneath it');
  });

  testWidgets('switching to Asks shows the ask rows and their ages',
      (tester) async {
    await pumpParity(tester, const ParityLensView());

    await tester.tap(find.byKey(const ValueKey('lens-tab-Asks')));
    await tester.pumpAndSettle();

    expect(
        find.text(
            'Which loudness target should the ad set use — -23 or -16 LUFS?'),
        findsOneWidget);
    // The age is rendered against the INJECTED clock, so it is a fact rather
    // than a race.
    expect(find.text('1h ago'), findsOneWidget);
    expect(find.text('3h ago'), findsOneWidget);
    // The answered ask shows its recorded answer, and reads as answered on the
    // strength of HAVING one — the status string can lag.
    expect(find.textContaining('locked as of this morning'), findsOneWidget);
  });

  testWidgets('an unassigned ask says so instead of showing an empty chip',
      (tester) async {
    final lens = FakeLensApi(askRows: const [
      LensAskRow(
        id: 'ask-9',
        content: 'Who owns the festival deliverable?',
        askerName: 'Mara',
        createdAt: FakeLensApi.seedSecs - 7200,
      ),
    ]);
    await pumpParity(tester, const ParityLensView(), lens: lens);
    await tester.tap(find.byKey(const ValueKey('lens-tab-Asks')));
    await tester.pumpAndSettle();

    expect(find.text('Unassigned'), findsOneWidget);
  });

  testWidgets('switching to Decisions shows the decision rows', (tester) async {
    await pumpParity(tester, const ParityLensView());

    await tester.tap(find.byKey(const ValueKey('lens-tab-Decisions')));
    await tester.pumpAndSettle();

    expect(find.text('Ship the review pipeline with the cloud color step.'),
        findsOneWidget);
    expect(find.text('Device-only color was too slow on long masters.'),
        findsOneWidget);
    expect(find.text('5h ago'), findsOneWidget);

    // REACTION COUNTS are a SEPARATE endpoint (`/decisions/{id}/reactions`),
    // so the feed cannot supply them without an N+1 fetch. The face draws the
    // reaction row only when a count is positive, so a decision reads as "not
    // asked" rather than as "nobody agreed" — which is what a hard 0 would say.
    expect(find.byIcon(Icons.thumb_up), findsNothing);
  });

  testWidgets('a lens that is DOWN says Disconnected rather than "all clear"',
      (tester) async {
    final lens = FakeLensApi(
        failWith: const LensApiException.unreachable(
            'the lens is unreachable at http://localhost:8080'));
    await pumpParity(tester, const ParityLensView(), lens: lens);

    // `/health` failing is the answer: the face reports the disconnection and
    // does NOT go on to claim an empty nudge list means there is nothing wrong.
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('All clear!'), findsOneWidget);
    // …and it never asked for the feeds it could not have got.
    expect(lens.calls.map((c) => c.method), ['health']);
  });

  testWidgets('golden: lens AI', (tester) async {
    await pumpParity(tester, const ParityLensView());
    await expectLater(
      find.byType(ParityLensView),
      matchesGoldenFile('golden/lens_ai.png'),
    );
  }, tags: 'golden');
}
