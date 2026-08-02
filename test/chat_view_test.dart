// test/chat_view_test.dart
//
// PARITY_TRACKER row 11 — Chat. Tier-1: drives `ParityChatView` through the
// `CyanBackend` seam (FakeCyanBackend) and asserts the header, the transcript
// (colored authors + markdown body), the seeded messages, and that the
// composer Send fires. Plus a golden (tagged `golden`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
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
    String? sent;
    await pumpParity(
      tester,
      ParityChatView(onSend: (text) => sent = text),
    );

    await tester.enterText(find.byType(TextField), 'Kicking the tyres.');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    // The host hook carries what was actually typed, and only fires once the
    // engine has TAKEN the message.
    expect(sent, 'Kicking the tyres.');
  });

  testWidgets('chat is board scoped and sends a message', (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(
      tester,
      const ParityChatView(boardId: 'b-eng-1'),
      backend: backend,
    );

    await tester.enterText(
        find.byType(TextField), 'Pulling the grade reference now.');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    // It was SENT — the engine holds it, not just the widget.
    final eng = await backend.loadChat('b-eng-1');
    expect(eng.map((m) => m.body), contains('Pulling the grade reference now.'));
    expect(eng.last.isOwn, isTrue);
    expect(eng.last.author, 'You');
    expect(eng.last.id, isNotEmpty); // the write minted an id

    // It is BOARD SCOPED — the board id is the whole chat address, so no other
    // board's lane saw it.
    final prod = await backend.loadChat('b-prod-1');
    expect(prod.map((m) => m.body),
        isNot(contains('Pulling the grade reference now.')));
    expect(prod, hasLength(1));

    // The composer cleared, because the send landed.
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty);
  });

  testWidgets('a sent message appears in the lane', (tester) async {
    await pumpParity(tester, const ParityChatView(boardId: 'b-eng-1'));

    const body = 'Grade reference is on the mesh — pulling it down.';
    expect(find.text(body, findRichText: true), findsNothing);

    await tester.enterText(find.byType(TextField), body);
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    // The lane re-read the engine and the message is in the transcript.
    expect(find.text(body, findRichText: true), findsOneWidget);
    // Sent by this operator, so it renders under the own-author byline.
    expect(find.text('You'), findsWidgets);
  });

  testWidgets('whitespace-only text is never sent', (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(
      tester,
      const ParityChatView(boardId: 'b-eng-1'),
      backend: backend,
    );

    final before = (await backend.loadChat('b-eng-1')).length;

    await tester.enterText(find.byType(TextField), '     ');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(await backend.loadChat('b-eng-1'), hasLength(before));
    // The draft is left alone — a refused send must not eat what was typed.
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '     ');
  });

  testWidgets('deleting a message removes it', (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(
      tester,
      const ParityChatView(boardId: 'b-eng-1'),
      backend: backend,
    );

    const mine = 'Approved. Sending to review now.';
    expect(find.text(mine, findRichText: true), findsOneWidget);

    // Own messages carry the delete affordance; other people's do not — the
    // seeded lane has two of mine (m2, m4) among four messages.
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pumpAndSettle();

    // Gone from the lane...
    expect(find.text(mine, findRichText: true), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    // ...and gone from the engine, which is what makes it a delete rather than
    // a widget hiding a row.
    final after = await backend.loadChat('b-eng-1');
    expect(after.map((m) => m.body), isNot(contains(mine)));
    expect(after, hasLength(3));

    // The messages that were not deleted are untouched.
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Mara'), findsOneWidget);
  });

  testWidgets('golden: chat transcript', (tester) async {
    await pumpParity(tester, const ParityChatView());
    await expectLater(
      find.byType(ParityChatView),
      matchesGoldenFile('golden/chat_transcript.png'),
    );
  }, tags: 'golden');
}
