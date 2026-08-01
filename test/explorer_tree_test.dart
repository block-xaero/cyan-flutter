// test/explorer_tree_test.dart
//
// PARITY_TRACKER row 2 — Explorer / group tree. Tier-1: drives
// `ParityExplorerTree` through the `CyanBackend` seam (FakeCyanBackend) and
// asserts the Group -> Workspace -> Board hierarchy renders with disclosure,
// that a row tap SELECTS (not merely expands), that a new board files into the
// SELECTED workspace, and that a board can be renamed and deleted. Plus a
// golden (tagged `golden`).
//
// Behaviour spec: scripts/parity_faces/explorer.txt.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/widgets/parity/parity_explorer_tree.dart';

import 'support/parity_test_harness.dart';

/// The id of the workspace holding [boardName] in the backend's tree, or null
/// when no board goes by that name. Asserting against the SEAM (not the
/// widget) is the point: it proves the board was actually filed there.
Future<String?> _workspaceHolding(
    FakeCyanBackend backend, String boardName) async {
  for (final g in await backend.loadGroups()) {
    for (final w in g.workspaces) {
      for (final b in w.boards) {
        if (b.name == boardName) return w.id;
      }
    }
  }
  return null;
}

/// Open the context menu on the row labelled [name].
Future<void> _openRowMenu(WidgetTester tester, String name) async {
  await tester.longPress(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  // ---- scripts/parity_faces/explorer.txt, line 1 ---------------------------

  testWidgets('the explorer tree renders groups workspaces and boards with '
      'disclosure', (tester) async {
    await pumpParity(tester, const ParityExplorerTree(),
        size: const Size(320, 700));

    expect(find.text('Files'), findsOneWidget);

    // Level 0 — every seeded group.
    expect(find.text('Engineering'), findsOneWidget);
    expect(find.text('Product'), findsOneWidget);
    expect(find.text('Design'), findsOneWidget);

    // Level 1 — workspaces under them.
    expect(find.text('Backend Services'), findsOneWidget);
    expect(find.text('Infrastructure'), findsOneWidget);
    expect(find.text('Roadmap'), findsOneWidget);

    // Level 2 — leaf boards, visible because the tree starts expanded.
    expect(find.text('Render + Review Pipeline'), findsOneWidget);
    expect(find.text('Database Schema'), findsOneWidget);

    // Disclosure: an expandable node carries a chevron, pointing down while
    // expanded. Leaves carry none.
    final engChevron = find.byKey(const ValueKey('explorer.chevron.g-eng'));
    expect(engChevron, findsOneWidget);
    expect(
      find.descendant(
          of: engChevron, matching: find.byIcon(Icons.keyboard_arrow_down)),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('explorer.chevron.b-eng-1')), findsNothing);

    // And it discloses: collapsing the group hides its subtree, and the
    // chevron flips to the collapsed glyph.
    await tester.tap(engChevron);
    await tester.pumpAndSettle();

    expect(find.text('Engineering'), findsOneWidget);
    expect(find.text('Backend Services'), findsNothing);
    expect(find.text('Render + Review Pipeline'), findsNothing);
    expect(
      find.descendant(
          of: engChevron, matching: find.byIcon(Icons.keyboard_arrow_right)),
      findsOneWidget,
    );
  });

  // ---- scripts/parity_faces/explorer.txt, line 2 ---------------------------

  testWidgets('selecting a row selects it rather than only expanding it',
      (tester) async {
    // `FileTreeRow.onTapGesture` -> `toggleSelection(item)`, then expand IF
    // collapsed. The old bug: the tap only ever toggled expansion, so tapping
    // an already-open row COLLAPSED it and nothing could read the selection.
    final selections = <ExplorerSelection?>[];
    await pumpParity(
      tester,
      ParityExplorerTree(onSelectionChanged: selections.add),
      size: const Size(320, 700),
    );

    // `Infrastructure` starts expanded. Tapping it must select it and LEAVE it
    // expanded — its children stay on screen.
    await tester.tap(find.text('Infrastructure'));
    await tester.pumpAndSettle();

    expect(selections.last, isNotNull);
    expect(selections.last!.id, 'w-eng-infra');
    expect(selections.last!.kind, ExplorerNodeKind.workspace);
    expect(find.text('CI/CD Pipeline'), findsOneWidget);
    expect(find.text('Deployment Notes'), findsOneWidget);

    // Re-tapping the selection clears it (`toggleSelection`) — and still does
    // not collapse the row.
    await tester.tap(find.text('Infrastructure'));
    await tester.pumpAndSettle();
    expect(selections.last, isNull);
    expect(find.text('CI/CD Pipeline'), findsOneWidget);

    // A COLLAPSED row selects and expands in the same tap.
    await tester.tap(find.byKey(const ValueKey('explorer.chevron.w-eng-infra')));
    await tester.pumpAndSettle();
    expect(find.text('CI/CD Pipeline'), findsNothing);

    await tester.tap(find.text('Infrastructure'));
    await tester.pumpAndSettle();
    expect(selections.last, isNotNull);
    expect(selections.last!.id, 'w-eng-infra');
    expect(find.text('CI/CD Pipeline'), findsOneWidget);

    // A board row selects too, carrying its full scope chain.
    await tester.tap(find.text('Database Schema'));
    await tester.pumpAndSettle();
    expect(selections.last!.kind, ExplorerNodeKind.board);
    expect(selections.last!.id, 'b-eng-2');
    expect(selections.last!.workspaceId, 'w-eng-backend');
    expect(selections.last!.groupId, 'g-eng');
  });

  // ---- scripts/parity_faces/explorer.txt, line 3 ---------------------------

  testWidgets('new board files into the selected workspace not the last used '
      'one', (tester) async {
    // `defaultWorkspaceIdForNewBoard()`: the selection decides the target,
    // every time. Never "whichever sorted first", never "wherever the last one
    // went" — both file the board into the wrong group silently.
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityExplorerTree(),
        backend: backend, size: const Size(320, 700));

    // Stand in Engineering / Infrastructure — NOT the first workspace.
    await tester.tap(find.text('Infrastructure'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('explorer.newBoard')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('explorer.newBoard.name')), 'Runbook');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(await _workspaceHolding(backend, 'Runbook'), 'w-eng-infra');
    expect(find.text('Runbook'), findsOneWidget);

    // Now move the selection to a workspace in a DIFFERENT group. The next
    // board must follow the selection, not the workspace last written to.
    await tester.tap(find.text('UI Components'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('explorer.newBoard')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('explorer.newBoard.name')), 'Motion Specs');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(await _workspaceHolding(backend, 'Motion Specs'), 'w-design-ui');
    // The last-used workspace did NOT collect it.
    expect(await _workspaceHolding(backend, 'Motion Specs'),
        isNot('w-eng-infra'));

    // A selected BOARD resolves to its parent workspace, not to its own id.
    await tester.tap(find.text('Interview Notes')); // b-prod-3 / w-prod-research
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('explorer.newBoard')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('explorer.newBoard.name')), 'Survey Plan');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(await _workspaceHolding(backend, 'Survey Plan'), 'w-prod-research');
  });

  // ---- scripts/parity_faces/explorer.txt, line 4 ---------------------------

  testWidgets('the explorer supports rename and delete of a board',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityExplorerTree(),
        backend: backend, size: const Size(320, 700));

    // Rename — `FileTreeRow`'s context menu -> `commitRename()`.
    await _openRowMenu(tester, 'Database Schema');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('explorer.rename.field')), 'Schema v2');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(find.text('Schema v2'), findsOneWidget);
    expect(find.text('Database Schema'), findsNothing);
    // The seam took the rename; the id is unchanged.
    expect(await _workspaceHolding(backend, 'Schema v2'), 'w-eng-backend');

    // Delete — destructive, so it routes through a confirm first.
    await _openRowMenu(tester, 'Schema v2');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete “Schema v2”?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Schema v2'), findsOneWidget); // cancel keeps the board

    await _openRowMenu(tester, 'Schema v2');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Schema v2'), findsNothing);
    expect(await _workspaceHolding(backend, 'Schema v2'), isNull);
    // Its siblings are untouched.
    expect(find.text('Render + Review Pipeline'), findsOneWidget);
  });

  // ---- pre-existing coverage ------------------------------------------------

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

    // Collapse Engineering. The chevron is the collapse affordance — a row tap
    // selects (see `FileTreeRow.onTapGesture`), which is why this drives the
    // chevron rather than the label.
    await tester.tap(find.byKey(const ValueKey('explorer.chevron.g-eng')));
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
