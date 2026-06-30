// test/boards_grid_test.dart
//
// PARITY_TRACKER row 1 — Boards grid + living wall. Tier-1: drives
// `ParityBoardsGrid` through the `CyanBackend` seam (FakeCyanBackend), asserts
// the seeded boards render with their group headers, and captures a golden.
//
// The golden test is tagged `golden` so the blocking `flutter test` gate runs
// the behavior tests on every machine, while goldens are baselined in a
// dedicated CI step (`--update-goldens`, uploaded as an artifact) until Rick
// drops the Day-0 reference shots in test/golden/reference/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/widgets/parity/parity_boards_grid.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('living wall renders seeded groups + boards', (tester) async {
    await pumpParity(tester, const ParityBoardsGrid());

    // Header.
    expect(find.text('All Boards'), findsOneWidget);

    // The three demo groups each appear as a section header.
    expect(find.text('Engineering'), findsWidgets);
    expect(find.text('Product'), findsWidgets);
    expect(find.text('Design'), findsWidgets);

    // A pinned, deployed flagship board card is present.
    expect(find.text('Render + Review Pipeline'), findsOneWidget);

    // Living-wall treatment: a deployed board shows a running pill.
    expect(find.textContaining('Running'), findsWidgets);
  });

  testWidgets('tapping a board card fires onOpenBoard', (tester) async {
    BoardWithContext? tapped;
    await pumpParity(
      tester,
      ParityBoardsGrid(onOpenBoard: (b) => tapped = b),
    );

    await tester.tap(find.text('Render + Review Pipeline'));
    await tester.pump();

    expect(tapped, isNotNull);
    expect(tapped!.board.id, 'b-eng-1');
  });

  testWidgets('golden: boards living wall', (tester) async {
    await pumpParity(tester, const ParityBoardsGrid());
    await expectLater(
      find.byType(ParityBoardsGrid),
      matchesGoldenFile('golden/boards_living_wall.png'),
    );
  }, tags: 'golden');
}
