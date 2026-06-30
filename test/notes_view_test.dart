// test/notes_view_test.dart
//
// PARITY_TRACKER row 5 — Board: Notes. Tier-1: drives `ParityNotesView`
// through the `CyanBackend` seam (FakeCyanBackend) and asserts the toolbar
// file name + saved state, the rendered markdown lines, and the status bar
// (line/word counts). Plus a golden (tagged `golden`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/widgets/parity/parity_notes_view.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('renders the notes document with toolbar + status bar',
      (tester) async {
    await pumpParity(tester, const ParityNotesView(boardId: 'b-eng-4'),
        size: const Size(700, 600));

    // Toolbar: file name + saved indicator.
    expect(find.text('deployment.md'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);

    // Document content lines.
    expect(find.text('# Deployment Notes'), findsOneWidget);
    expect(find.text('## Rollout'), findsOneWidget);

    // Status bar shows a line + word count and the encoding.
    expect(find.textContaining('lines'), findsOneWidget);
    expect(find.textContaining('words'), findsOneWidget);
    expect(find.text('UTF-8'), findsOneWidget);
  });

  testWidgets('golden: notes editor', (tester) async {
    await pumpParity(tester, const ParityNotesView(boardId: 'b-eng-4'),
        size: const Size(700, 600));
    await expectLater(
      find.byType(ParityNotesView),
      matchesGoldenFile('golden/notes_editor.png'),
    );
  }, tags: 'golden');
}
