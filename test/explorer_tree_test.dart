// test/explorer_tree_test.dart
//
// PARITY_TRACKER row 2 — Explorer / group tree. Tier-1: drives
// `ParityExplorerTree` through the `CyanBackend` seam (FakeCyanBackend) and
// asserts the Group -> Workspace -> Board hierarchy renders, expand/collapse
// works, board taps fire, and search filters. Plus a golden (tagged `golden`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/widgets/parity/parity_explorer_tree.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('renders the group -> workspace -> board hierarchy',
      (tester) async {
    await pumpParity(tester, const ParityExplorerTree(),
        size: const Size(320, 700));

    // Header.
    expect(find.text('Files'), findsOneWidget);

    // All three seeded groups (expanded by default).
    expect(find.text('Engineering'), findsOneWidget);
    expect(find.text('Product'), findsOneWidget);
    expect(find.text('Design'), findsOneWidget);

    // A workspace under Engineering.
    expect(find.text('Backend Services'), findsOneWidget);

    // A leaf board, visible because the tree starts fully expanded.
    expect(find.text('Render + Review Pipeline'), findsOneWidget);
  });

  testWidgets('collapsing a group hides its workspaces', (tester) async {
    await pumpParity(tester, const ParityExplorerTree(),
        size: const Size(320, 700));

    expect(find.text('Backend Services'), findsOneWidget);

    // Tap the Engineering group row -> collapses it.
    await tester.tap(find.text('Engineering'));
    await tester.pumpAndSettle();

    expect(find.text('Engineering'), findsOneWidget); // group still shown
    expect(find.text('Backend Services'), findsNothing); // children hidden
    expect(find.text('Render + Review Pipeline'), findsNothing);
  });

  testWidgets('tapping a board row fires onOpenBoard', (tester) async {
    CyanBoard? opened;
    await pumpParity(
      tester,
      ParityExplorerTree(onOpenBoard: (b) => opened = b),
      size: const Size(320, 700),
    );

    await tester.tap(find.text('Render + Review Pipeline'));
    await tester.pump();

    expect(opened, isNotNull);
    expect(opened!.id, 'b-eng-1');
  });

  testWidgets('search filters to matching boards + their ancestors',
      (tester) async {
    await pumpParity(tester, const ParityExplorerTree(),
        size: const Size(320, 700));

    await tester.enterText(find.byType(TextField), 'Render');
    await tester.pumpAndSettle();

    // The matching board and its group/workspace context remain.
    expect(find.text('Render + Review Pipeline'), findsOneWidget);
    expect(find.text('Engineering'), findsOneWidget);
    expect(find.text('Backend Services'), findsOneWidget);

    // A non-matching sibling board is filtered out.
    expect(find.text('Database Schema'), findsNothing);
    // An unrelated group with no match is gone.
    expect(find.text('Design'), findsNothing);
  });

  testWidgets('golden: explorer tree', (tester) async {
    await pumpParity(tester, const ParityExplorerTree(),
        size: const Size(320, 700));
    await expectLater(
      find.byType(ParityExplorerTree),
      matchesGoldenFile('golden/explorer_tree.png'),
    );
  }, tags: 'golden');
}
