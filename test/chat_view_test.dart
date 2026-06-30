// test/chat_view_test.dart
//
// PARITY_TRACKER row 11 — Chat. Tier-1: drives `ParityChatView` through the
// `CyanBackend` seam (FakeCyanBackend) and asserts the header, the transcript
// (colored authors + markdown body), the seeded messages, and that the
// composer Send fires. Plus a golden (tagged `golden`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/widgets/parity/parity_chat_view.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('renders the header and seeded transcript', (tester) async {
    await pumpParity(tester, const ParityChatView());

    // Header.
    expect(find.text('Render + Review Pipeline'), findsOneWidget);
    expect(find.text('Board chat'), findsOneWidget);

    // Seeded authors (own = You, others = Priya/Mara) appear.
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Mara'), findsOneWidget);
    expect(find.text('You'), findsWidgets);

    // A timestamp from the seed.
    expect(find.text('10:14 AM'), findsOneWidget);

    // Composer placeholder.
    expect(find.text('Message…'), findsOneWidget);
  });

  testWidgets('Send fires onSend', (tester) async {
    var sent = false;
    await pumpParity(
      tester,
      ParityChatView(onSend: (_) => sent = true),
    );

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sent, isTrue);
  });

  testWidgets('golden: chat transcript', (tester) async {
    await pumpParity(tester, const ParityChatView());
    await expectLater(
      find.byType(ParityChatView),
      matchesGoldenFile('golden/chat_transcript.png'),
    );
  }, tags: 'golden');
}
