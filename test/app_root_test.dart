// test/app_root_test.dart
//
// The MOUNT EDGE — the one test that asks "which app actually ships?".
//
// Every other parity test pumps its face directly. That is the right shape for
// proving a face, and it is exactly why the whole `lib/widgets/parity/` tree
// could sit at 436 green assertions while no operator could open a single one
// of those faces: `lib/main.dart` mounted the pre-parity `WorkspaceScreen`
// (canvas / notebook / notes cell editor — the surface SwiftUI's `WorkflowView`
// was written to REPLACE), and nothing outside `lib/widgets/parity/` imported
// anything from `lib/widgets/parity/`.
//
// So this file tests two things no face test can:
//   1. the signed-in workspace mounts `ParityHomeShell`, and a board row in it
//      opens the board CUBE rather than doing nothing;
//   2. a REPO ORACLE, read off disk, that the orphaning cannot come back —
//      app code must reference the parity shell, and must not re-mount the
//      legacy shell widgets.
//
// SwiftUI reference (read only):
//   cyan-iOS/Cyan/Cyan/App/CyanApp.swift          (root -> ContentView)
//   cyan-iOS/Cyan/Cyan/Views/ContentView.swift    (authenticated -> workspace)
//   cyan-iOS/Cyan/Cyan/Views/WorkspaceViewNew.swift
//                                (rail | surface, and the board container
//                                 mounted BESIDE the rail, not over it)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/main.dart';
import 'package:cyan_flutter/widgets/parity/parity_board_container.dart';
import 'package:cyan_flutter/widgets/parity/parity_boards_grid.dart';
import 'package:cyan_flutter/widgets/parity/parity_explorer_tree.dart';
import 'package:cyan_flutter/widgets/parity/parity_home_shell.dart';
import 'package:cyan_flutter/widgets/parity/parity_marketplace.dart';
import 'package:cyan_flutter/widgets/parity/parity_icon_rail.dart';

import 'support/parity_test_harness.dart';

String _read(String relative) {
  final f = File(relative);
  expect(f.existsSync(), isTrue, reason: '$relative must exist');
  return f.readAsStringSync();
}

void main() {
  group('the signed-in workspace is the parity shell', () {
    testWidgets('CyanWorkspace mounts ParityHomeShell', (tester) async {
      await pumpParity(tester, const CyanWorkspace());

      expect(find.byType(ParityHomeShell), findsOneWidget,
          reason: 'the workspace an authenticated operator lands on must be '
              'the parity shell, not the pre-parity cell editor');
      expect(find.byType(ParityIconRail), findsOneWidget);
    });

    testWidgets('opening a board from the Boards wall mounts the board cube',
        (tester) async {
      // The name is READ from the same fake the harness drives, never
      // hard-coded: a test that guesses a seed name fails for a reason that has
      // nothing to do with the mount edge it is guarding.
      final seeded = (await FakeCyanBackend().loadAllBoards()).first.board;

      await pumpParity(tester, const CyanWorkspace());

      // Open the Boards door, then tap a seeded board card.
      await tester.tap(find.descendant(
        of: find.byType(ParityIconRail),
        matching: find.text('Boards'),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(ParityBoardsGrid), findsOneWidget);
      expect(find.byType(ParityBoardContainer), findsNothing,
          reason: 'no board is open yet');

      final card = find.text(seeded.name);
      expect(card, findsWidgets,
          reason: 'the fake seeds boards on the wall to open');
      await tester.tap(card.first);
      await tester.pumpAndSettle();

      expect(find.byType(ParityBoardContainer), findsOneWidget,
          reason:
              'tapping a board card must open the board cube — a card that '
              'does nothing is the whole reason the parity tree was dead');
      expect(find.byType(ParityIconRail), findsOneWidget,
          reason: 'Swift mounts the board container BESIDE the rail, so a '
              'board is never a dead end');
    });

    testWidgets('the Explorer tree opens a board too', (tester) async {
      final seeded = (await FakeCyanBackend().loadAllBoards()).first.board;

      await pumpParity(tester, const CyanWorkspace());

      // The shell opens on Explorer.
      expect(find.byType(ParityExplorerTree), findsOneWidget);

      // The tree keys every row by id, so this taps the board ROW rather than
      // whichever widget happens to carry the same text.
      final board = find.byKey(ValueKey('explorer.row.${seeded.id}'));
      expect(board, findsOneWidget,
          reason: 'the seeded board must have a row in the tree');
      await tester.tap(board);
      await tester.pumpAndSettle();

      expect(find.byType(ParityBoardContainer), findsOneWidget,
          reason: 'both surfaces that LIST boards must open one');
    });
  });

  group('the Market door is handed the group and the role', () {
    // `ParityMarketplace` was mounted bare — `const ParityMarketplace()` — so
    // it evaluated `forgeEntryGate(null)` and hard-locked "Build a custom tool"
    // for EVERYONE, owners included, while Install could never run at all for
    // want of a group id to land in. A ported gate, permanently denying.

    testWidgets('standing in a group threads its id into the storefront',
        (tester) async {
      final seeded = (await FakeCyanBackend().loadAllBoards()).first;

      await pumpParity(tester, const CyanWorkspace());

      // Opening a board from the wall is how the operator says where they are.
      await tester.tap(find.descendant(
        of: find.byType(ParityIconRail),
        matching: find.text('Boards'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(seeded.board.name).first);
      await tester.pumpAndSettle();

      // Leave the board and open the Market door.
      await tester.tap(find.descendant(
        of: find.byType(ParityIconRail),
        matching: find.text('Market'),
      ));
      await tester.pumpAndSettle();

      final market =
          tester.widget<ParityMarketplace>(find.byType(ParityMarketplace));
      expect(market.groupId, seeded.group.id,
          reason: 'an install lands in the group the operator is standing in, '
              'never a guessed one');
    });

    testWidgets('with no session the storefront is handed no role',
        (tester) async {
      await pumpParity(tester, const CyanWorkspace());

      await tester.tap(find.descendant(
        of: find.byType(ParityIconRail),
        matching: find.text('Market'),
      ));
      await tester.pumpAndSettle();

      final market =
          tester.widget<ParityMarketplace>(find.byType(ParityMarketplace));
      expect(market.sessionRole, isNull,
          reason: 'no session means no role — and the gate locks on that, '
              'which is honest. What was wrong was locking an OWNER too.');
    });
  });

  group('repo oracle — the parity tree cannot be orphaned again', () {
    test('app code mounts the parity shell', () {
      final main = _read('lib/main.dart');

      expect(main.contains('widgets/parity/parity_home_shell.dart'), isTrue,
          reason: 'lib/main.dart must import the parity shell; without this '
              'edge every parity face is dead code at runtime');
      expect(main.contains('ParityHomeShell'), isTrue);
      // The IMPORT is the oracle, not the word: prose about the legacy screen
      // (including the comment explaining why it was replaced) must not be able
      // to fail this, and cannot mount anything either.
      expect(main.contains('screens/workspace_screen.dart'), isFalse,
          reason: 'the legacy pre-parity workspace must not be mounted; it is '
              'the canvas/notebook/notes editor SwiftUI replaced');
    });

    test('some app file outside lib/widgets/parity/ imports the parity tree',
        () {
      final importers = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (path.contains('lib/widgets/parity/')) continue;
        if (entity.readAsStringSync().contains('widgets/parity/')) {
          importers.add(path);
        }
      }

      expect(importers, isNotEmpty,
          reason: 'NOTHING outside lib/widgets/parity/ imported the parity '
              'tree — that is precisely how 34 faces passed their tests while '
              'no operator could open one. At least the app entrypoint must.');
    });
  });
}
