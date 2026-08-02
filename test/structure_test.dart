// test/structure_test.dart
//
// STAGE face_structure — groups / workspaces / boards CRUD in the Explorer.
// Tier-1: drives `ParityExplorerTree` through the `CyanBackend` seam
// (FakeCyanBackend), so every assertion is about where a node actually LANDED
// in the tree, not merely what got painted.
//
// Behaviour spec: scripts/parity_faces/structure.txt.
//
// SwiftUI reference (read-only):
//   Views/FileTreeView.swift, ViewModels/FileTreeViewModel.swift
//   CyanTests/FirstGroupOnboardingTests.swift — the engine auto-seeds a new
//     group's General + Plugins workspaces and the tree lands on them with no
//     reload
//   CyanTests/NewBoardWorkspaceTests.swift — the New Board target is the
//     SELECTION, resolved most-specific-first

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/widgets/parity/parity_explorer_tree.dart';

import 'support/parity_test_harness.dart';

/// The workspace holding [boardName] in the backend's tree, or null when no
/// board goes by that name. Asserting against the SEAM is the point: it proves
/// where the board was filed, not where it happened to be drawn.
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

/// Every workspace id in the tree that holds a board named [boardName] — the
/// "not elsewhere" half of filing. One entry is correct; two means the board
/// was duplicated into a workspace nobody asked for.
Future<List<String>> _allWorkspacesHolding(
    FakeCyanBackend backend, String boardName) async {
  final out = <String>[];
  for (final g in await backend.loadGroups()) {
    for (final w in g.workspaces) {
      if (w.boards.any((b) => b.name == boardName)) out.add(w.id);
    }
  }
  return out;
}

Future<CyanGroup?> _groupNamed(FakeCyanBackend backend, String name) async {
  for (final g in await backend.loadGroups()) {
    if (g.name == name) return g;
  }
  return null;
}

/// Name a node in the Explorer's name prompt and commit it.
Future<void> _commitName(
  WidgetTester tester, {
  required Key field,
  required String name,
  String action = 'Create',
}) async {
  await tester.enterText(find.byKey(field), name);
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

/// Open the context menu on the row labelled [name].
Future<void> _openRowMenu(WidgetTester tester, String name) async {
  await tester.longPress(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  // ---- scripts/parity_faces/structure.txt, line 1 --------------------------

  testWidgets('creating a group auto seeds a General workspace and lands there',
      (tester) async {
    // The ENGINE seeds General + Plugins behind `.createGroup` — Swift sees
    // them as two `WorkspaceCreated` events behind `GroupCreated` and shows
    // them with NO reload, with the new group expanded. The operator then
    // stands in that General workspace, which is what makes the very next New
    // Board land in the group they just made.
    final backend = FakeCyanBackend();
    final selections = <ExplorerSelection?>[];
    await pumpParity(
      tester,
      ParityExplorerTree(onSelectionChanged: selections.add),
      backend: backend,
      size: const Size(320, 900),
    );

    expect(find.text('Studio'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('explorer.newGroup')));
    await tester.pumpAndSettle();
    await _commitName(tester,
        field: const ValueKey('explorer.newGroup.name'), name: 'Studio');

    // The seam made the group, and the engine's seed came with it.
    final studio = await _groupNamed(backend, 'Studio');
    expect(studio, isNotNull, reason: 'the group reached the seam');
    expect(
      studio!.workspaces.map((w) => w.name),
      containsAll(<String>['General', 'Plugins']),
      reason: 'a new group is auto-seeded with General + Plugins',
    );

    // Both render at once — no reload, and the group came up expanded.
    expect(find.text('Studio'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Plugins'), findsOneWidget);

    // "Lands there": the selection is the seeded General workspace, not the
    // group and not the system Plugins one.
    final general = studio.workspaces.firstWhere((w) => w.name == 'General');
    expect(selections.last, isNotNull);
    expect(selections.last!.kind, ExplorerNodeKind.workspace);
    expect(selections.last!.id, general.id);
    expect(selections.last!.groupId, studio.id);

    // And landing is not decorative: the next board files into it without the
    // operator clicking anything else.
    await tester.tap(find.byKey(const ValueKey('explorer.newBoard')));
    await tester.pumpAndSettle();
    await _commitName(tester,
        field: const ValueKey('explorer.newBoard.name'), name: 'Kickoff');

    expect(await _workspaceHolding(backend, 'Kickoff'), general.id);
  });

  // ---- scripts/parity_faces/structure.txt, line 3 --------------------------

  testWidgets(
      'creating a board inside the selected workspace files it there not '
      'elsewhere', (tester) async {
    // `defaultWorkspaceIdForNewBoard()` resolves the SELECTION, most-specific
    // first. The bug this pins: a board filed into "whichever workspace sorted
    // first" landed in a different group entirely, silently.
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityExplorerTree(),
        backend: backend, size: const Size(320, 900));

    // Stand in Engineering / Infrastructure — deliberately NOT the first
    // workspace in the tree.
    await tester.tap(find.text('Infrastructure'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('explorer.newBoard')));
    await tester.pumpAndSettle();
    await _commitName(tester,
        field: const ValueKey('explorer.newBoard.name'), name: 'Runbook');

    // It is in the selected workspace — and in NO other, which is the half a
    // "did it render?" assertion would miss.
    expect(await _allWorkspacesHolding(backend, 'Runbook'), ['w-eng-infra']);

    // A selected BOARD files into its parent workspace, not into its own id and
    // not back into the workspace the last board went to.
    await tester.tap(find.text('Interview Notes')); // w-prod-research
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('explorer.newBoard')));
    await tester.pumpAndSettle();
    await _commitName(tester,
        field: const ValueKey('explorer.newBoard.name'), name: 'Survey Plan');

    expect(
        await _allWorkspacesHolding(backend, 'Survey Plan'), ['w-prod-research']);

    // Right-clicking a GROUP files into THAT group's General/Plugins-preferred
    // workspace — the row under the cursor, never the selection still sitting
    // in another group.
    await _openRowMenu(tester, 'Design');
    await tester.tap(find.text('New Board'));
    await tester.pumpAndSettle();
    await _commitName(tester,
        field: const ValueKey('explorer.newBoard.name'), name: 'Palette');

    final filed = await _allWorkspacesHolding(backend, 'Palette');
    expect(filed, hasLength(1));
    expect(filed.single, startsWith('w-design-'));
  });

  // ---- workspaces: `addWorkspaceToGroup(groupId:)` --------------------------

  testWidgets('a workspace created on a group row lands inside that group',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityExplorerTree(),
        backend: backend, size: const Size(320, 900));

    await _openRowMenu(tester, 'Design');
    await tester.tap(find.text('New Workspace'));
    await tester.pumpAndSettle();
    await _commitName(tester,
        field: const ValueKey('explorer.newWorkspace.name'), name: 'Motion');

    final design = await _groupNamed(backend, 'Design');
    expect(design!.workspaces.map((w) => w.name), contains('Motion'));

    // It went to Design and nowhere else, and the group is open so it shows.
    for (final g in await backend.loadGroups()) {
      if (g.id == design.id) continue;
      expect(g.workspaces.any((w) => w.name == 'Motion'), isFalse);
    }
    expect(find.text('Motion'), findsOneWidget);

    // A new workspace starts empty — and is a legitimate board target.
    final motion = design.workspaces.firstWhere((w) => w.name == 'Motion');
    expect(motion.boards, isEmpty);

    await tester.tap(find.text('Motion'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('explorer.newBoard')));
    await tester.pumpAndSettle();
    await _commitName(tester,
        field: const ValueKey('explorer.newBoard.name'), name: 'Easing Curves');

    expect(await _workspaceHolding(backend, 'Easing Curves'), motion.id);
  });
}
