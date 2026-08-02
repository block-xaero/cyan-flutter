// test/workspace_view_test.dart
//
// STAGE face_workspaces — one workspace: its board list, the cards, the
// pipeline status strip, and the shortcuts that jump to a board. Tier-1: drives
// `ParityWorkspaceView` through the `CyanBackend` seam (FakeCyanBackend), no
// dylib.
//
// Behaviour spec: scripts/parity_faces/workspaces.txt.
//
// SwiftUI reference (read-only):
//   Views/WorkspaceViewNew.swift         — the workspace shell, `closeBoard`
//   Views/WorkspaceShortcuts.swift       — the shortcut registry + reducer
//   Views/BoardGridView.swift            — the card face
//   ViewModels/BoardRunStateStore.swift  — ONE tenant feed seeds every card
//   Models/LensConsole.swift             — BoardRunState's load-bearing
//                                          unknown-vs-noRuns distinction

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/models/workspace_surface.dart';
import 'package:cyan_flutter/providers/workspace_provider.dart';
import 'package:cyan_flutter/widgets/parity/parity_workspace_view.dart';

import 'support/parity_test_harness.dart';

const _size = Size(1100, 760);

/// The Engineering / Backend Services workspace: two boards, one of them the
/// deployed flagship the tenant run feed actually has runs for.
const _backendServices = 'w-eng-backend';

/// A backend whose lens is DOWN: the tenant run feed never arrives. Every board
/// must then report `unknown` — the outage may not repaint the workspace as
/// "No runs yet".
class _LensDownBackend extends FakeCyanBackend {
  @override
  Future<List<OpsRun>> loadOpsRuns() async =>
      throw StateError('lens unreachable');
}

/// A backend whose ENGINE will not answer `cyan_pipeline_status`. The lens feed
/// still arrives, so the run badges are unaffected — only the asset-class strip
/// has nothing to say, and must say nothing rather than three zeroes.
class _PipelineUnreachableBackend extends FakeCyanBackend {
  @override
  Future<PipelineStatus> pipelineStatus(String boardId) async =>
      throw StateError('engine db mutex held');
}

/// Run [body] with a mouse pointer resting on [target] — SwiftUI's
/// `.onHover(true)`, which is what gates the asset-class strip. The pointer is
/// always withdrawn afterwards, so a second hover in the same test starts from
/// a tree with no mouse in it.
Future<void> _whileHovering(
    WidgetTester tester, Finder target, Future<void> Function() body) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await tester.pump();
  await mouse.moveTo(tester.getCenter(target));
  await tester.pumpAndSettle();
  try {
    await body();
  } finally {
    await mouse.removePointer();
    await tester.pumpAndSettle();
  }
}

Finder _assetClassStrip(String boardId) =>
    find.byKey(ValueKey('workspace.assetClass.$boardId'));

/// The count rendered in one lane chip of the pipeline strip.
String _laneCount(WidgetTester tester, BoardRunLane lane) {
  final texts = tester.widgetList<Text>(find.descendant(
    of: find.byKey(ValueKey('workspace.lane.${lane.name}')),
    matching: find.byType(Text),
  ));
  return texts.last.data!;
}

Finder _runBadge(String boardId) =>
    find.byKey(ValueKey('workspace.runState.$boardId'));

/// Press a control-digit workspace shortcut.
Future<void> _pressShortcut(
    WidgetTester tester, LogicalKeyboardKey digit) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(digit);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

/// The workspace named [name] in [group], read back off the seam.
Future<CyanWorkspace> _workspaceNamed(
    FakeCyanBackend backend, String group, String name) async {
  final g = (await backend.loadGroups()).firstWhere((g) => g.name == group);
  return g.workspaces.firstWhere((w) => w.name == name);
}

void main() {
  // ---- scripts/parity_faces/workspaces.txt, line 1 -------------------------

  testWidgets('a workspace lists its boards with metadata and pipeline status',
      (tester) async {
    await pumpParity(
      tester,
      const ParityWorkspaceView(workspaceId: _backendServices),
      size: _size,
    );

    // Where you are: the group, the workspace, and how much is filed here.
    expect(find.byKey(const ValueKey('workspace.group')), findsOneWidget);
    expect(find.text('Engineering'), findsOneWidget);
    expect(find.text('Backend Services'), findsOneWidget);
    expect(find.text('2 boards'), findsOneWidget);

    // Both boards of THIS workspace — and nothing from the neighbouring one.
    expect(find.text('Render + Review Pipeline'), findsWidgets);
    expect(find.text('Database Schema'), findsWidgets);
    expect(find.text('CI/CD Pipeline'), findsNothing);

    // Pinned first: an operator pins what they come back to, so the pinned
    // board sits ABOVE the unpinned one regardless of when each last moved.
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('workspace.board.b-eng-1')))
          .dy,
      lessThan(tester
          .getTopLeft(find.byKey(const ValueKey('workspace.board.b-eng-2')))
          .dy),
    );

    // METADATA — the face a board opens on, its size, and when it last moved.
    // Absolute dates, so the row reads the same on every machine and clock.
    expect(
        find.text('Dashboard · 4 steps · updated 2026-05-31'), findsOneWidget);
    expect(
        find.text('Workflow · 3 steps · updated 2026-05-31'), findsOneWidget);

    // The labels the board carries.
    expect(find.text('approved'), findsOneWidget);
    expect(find.text('running'), findsOneWidget);
    expect(find.text('development'), findsOneWidget);

    // PIPELINE STATUS — the five lanes, rolled up over the workspace's boards
    // from ONE tenant feed. b-eng-1 has three runs (one awaiting approval, one
    // running, one done); b-eng-2 has none.
    expect(find.byKey(const ValueKey('workspace.pipeline')), findsOneWidget);
    expect(_laneCount(tester, BoardRunLane.incoming), '0');
    expect(_laneCount(tester, BoardRunLane.inFlight), '1');
    expect(_laneCount(tester, BoardRunLane.approval), '1');
    expect(_laneCount(tester, BoardRunLane.done), '1');
    expect(_laneCount(tester, BoardRunLane.failed), '0');

    // A zero lane stays on screen: the strip is read by position, so lanes
    // never reshuffle out from under the eye.
    expect(find.text('Incoming'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);

    // And the strip says how much of that is holding on a person.
    expect(find.text('1 need action'), findsOneWidget);

    // Runs belonging to boards in OTHER workspaces are not counted here: the
    // Design System failure and the Q3 Goals queue live elsewhere.
    expect(_laneCount(tester, BoardRunLane.failed), '0');
  });

  // ---- scripts/parity_faces/workspaces.txt, line 2 -------------------------

  testWidgets('workspace shortcuts navigate to a board', (tester) async {
    final opened = <CyanBoard>[];
    await pumpParity(
      tester,
      ParityWorkspaceView(
        workspaceId: _backendServices,
        onOpenBoard: opened.add,
      ),
      size: _size,
    );

    // A shortcut per board, pinned first, each showing the chord that fires it.
    expect(find.byKey(const ValueKey('workspace.shortcuts')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace.shortcut.b-eng-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('workspace.shortcut.b-eng-2')),
        findsOneWidget);
    expect(find.text('⌃1'), findsOneWidget);
    expect(find.text('⌃2'), findsOneWidget);

    // Nothing is open until a shortcut is used.
    expect(find.byKey(const ValueKey('workspace.openBoard')), findsNothing);

    // Clicking a shortcut navigates to ITS board — not the first one, not the
    // pinned one.
    await tester.tap(find.byKey(const ValueKey('workspace.shortcut.b-eng-2')));
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(opened.single.id, 'b-eng-2');
    // Navigation is not just a callback: the surface says where you now are.
    expect(find.byKey(const ValueKey('workspace.openBoard')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.descendant(
            of: find.byKey(const ValueKey('workspace.openBoard')),
            matching: find.text('Database Schema'),
          ))
          .data,
      'Database Schema',
    );

    // The CHORD navigates too — ⌃1 is the first shortcut, the pinned board.
    await _pressShortcut(tester, LogicalKeyboardKey.digit1);

    expect(opened, hasLength(2));
    expect(opened.last.id, 'b-eng-1');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('workspace.openBoard')),
        matching: find.text('Render + Review Pipeline'),
      ),
      findsOneWidget,
    );

    // esc closes the board and returns to the list — SwiftUI's
    // `WorkspaceShortcut.closeBoard` reducer case.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace.openBoard')), findsNothing);
    // Closing is not a fourth navigation.
    expect(opened, hasLength(2));

    // A chord past the last board is a no-op, not a crash: the binding stays
    // live while the workspace holds fewer boards than there are digits.
    await _pressShortcut(tester, LogicalKeyboardKey.digit9);
    expect(opened, hasLength(2));
    expect(find.byKey(const ValueKey('workspace.openBoard')), findsNothing);
  });

  // ---- scripts/parity_faces/workspaces.txt, line 3 -------------------------

  testWidgets('a board card shows its preview and last run state',
      (tester) async {
    await pumpParity(
      tester,
      const ParityWorkspaceView(workspaceId: _backendServices),
      size: _size,
    );

    // PREVIEW — a deployed board wears its running treatment; an idle one shows
    // the face it opens on and how much is in it.
    expect(find.byKey(const ValueKey('workspace.preview.b-eng-1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('workspace.preview.b-eng-2')),
        findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('workspace.preview.b-eng-1')),
        matching: find.text('Deployed'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('workspace.preview.b-eng-2')),
        matching: find.text('3 steps'),
      ),
      findsOneWidget,
    );

    // LAST RUN STATE — the lead run wins by operator relevance: a human gate
    // outranks the running and the finished run on the same board.
    expect(
      find.descendant(
          of: _runBadge('b-eng-1'), matching: find.text('Needs approval')),
      findsOneWidget,
    );

    // The feed ARRIVED and carried nothing for this board — that is a fact, and
    // it reads differently from a board nobody has heard about.
    expect(
      find.descendant(
          of: _runBadge('b-eng-2'), matching: find.text('No runs yet')),
      findsOneWidget,
    );

    // THE LOAD-BEARING DISTINCTION: with the lens down, no feed ever arrives,
    // so no card may claim anything. "No runs yet" here would repaint a busy
    // workspace as idle for the duration of an outage.
    await pumpParity(
      tester,
      const ParityWorkspaceView(workspaceId: _backendServices),
      backend: _LensDownBackend(),
      size: _size,
    );

    expect(_runBadge('b-eng-1'), findsNothing);
    expect(_runBadge('b-eng-2'), findsNothing);
    expect(find.text('No runs yet'), findsNothing);
    expect(find.text('Needs approval'), findsNothing);

    // The strip says it cannot tell, rather than painting five zeroes.
    expect(find.byKey(const ValueKey('workspace.pipeline')), findsNothing);
    expect(find.text('Pipeline status unavailable'), findsOneWidget);

    // The boards themselves are untouched — an outage never blanks the wall.
    expect(find.text('Render + Review Pipeline'), findsWidgets);
    expect(find.text('Database Schema'), findsWidgets);
    expect(find.byKey(const ValueKey('workspace.preview.b-eng-1')),
        findsOneWidget);
  });

  // ---- scripts/parity_faces/workspaces.txt, line 4 -------------------------

  testWidgets(
      'the Plugins workspace is treated as a system workspace and never a '
      'board target', (tester) async {
    // The ENGINE seeds every new group with General + Plugins. Plugins is the
    // group's registry: bundles land there, boards never do.
    final backend = FakeCyanBackend();
    await backend.initialize();
    await backend.createGroup('Studio');

    final plugins = await _workspaceNamed(backend, 'Studio', 'Plugins');
    final general = await _workspaceNamed(backend, 'Studio', 'General');

    // The seam itself classifies it, so every caller agrees on what "system"
    // means without re-deriving it from a name comparison of its own.
    expect(plugins.isPluginsWorkspace, isTrue);
    expect(plugins.isSystemWorkspace, isTrue);
    expect(plugins.acceptsBoards, isFalse);
    expect(general.isSystemWorkspace, isFalse);
    expect(general.acceptsBoards, isTrue);

    // The board-target resolver never lands on it: asked for the group it
    // answers General, and asked for Plugins ALONE it refuses rather than
    // falling back to the only workspace on offer.
    final studio =
        (await backend.loadGroups()).firstWhere((g) => g.name == 'Studio');
    expect(boardTargetIn(studio.workspaces)?.id, general.id);
    expect(boardTargetIn([plugins]), isNull);

    // On screen it is TREATED as a system workspace: badged, explained, and
    // carrying no board-creation affordance at all.
    await pumpParity(
      tester,
      ParityWorkspaceView(workspaceId: plugins.id),
      backend: backend,
      size: _size,
    );

    expect(find.byKey(const ValueKey('workspace.systemBadge')), findsOneWidget);
    expect(find.text('System workspace'), findsOneWidget);
    expect(find.textContaining('boards are never filed here'), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace.newBoard')), findsNothing);
    expect(
      find.text(
          'This is a system workspace — it holds plugin bundles, not boards.'),
      findsOneWidget,
    );

    // An ordinary workspace in the SAME group is the opposite on every count.
    await pumpParity(
      tester,
      ParityWorkspaceView(workspaceId: general.id),
      backend: backend,
      size: _size,
    );

    expect(find.byKey(const ValueKey('workspace.systemBadge')), findsNothing);
    expect(find.byKey(const ValueKey('workspace.newBoard')), findsOneWidget);

    // And a board made here files into General — never into the registry.
    await tester.tap(find.byKey(const ValueKey('workspace.newBoard')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('workspace.newBoard.name')), 'Kickoff');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final filed = <String>[];
    for (final g in await backend.loadGroups()) {
      for (final w in g.workspaces) {
        if (w.boards.any((b) => b.name == 'Kickoff')) filed.add(w.id);
      }
    }
    expect(filed, [general.id]);
    expect(
      (await _workspaceNamed(backend, 'Studio', 'Plugins')).boards,
      isEmpty,
      reason: 'the registry never accepts a board',
    );

    // It landed, and the surface it landed on shows it.
    expect(find.text('Kickoff'), findsWidgets);
  });

  // ---- scripts/parity_faces/workspaces.txt, line 5 -------------------------

  testWidgets('a board card shows asset class status pending in flight or done',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(
      tester,
      const ParityWorkspaceView(workspaceId: _backendServices),
      backend: backend,
      size: _size,
    );

    // AT REST there is no strip. These counts cost one engine call per board
    // (`cyan_pipeline_status` has no bulk form), so the wall does not fetch
    // them for every card on open — SwiftUI's card asks on hover, and so does
    // this one.
    expect(_assetClassStrip('b-eng-1'), findsNothing);

    await _whileHovering(
        tester, find.byKey(const ValueKey('workspace.board.b-eng-1')),
        () async {
      // The flagship board is compiled to four steps: two approved, one parked
      // on the producer-review gate, one never started.
      final strip = _assetClassStrip('b-eng-1');
      expect(strip, findsOneWidget);
      expect(find.descendant(of: strip, matching: find.text('1 pending')),
          findsOneWidget);
      expect(find.descendant(of: strip, matching: find.text('1 in-flight')),
          findsOneWidget);
      expect(find.descendant(of: strip, matching: find.text('2 done')),
          findsOneWidget);

      // Nothing has failed, so no failed chip is invented.
      expect(find.byKey(const ValueKey('workspace.assetClass.b-eng-1.failed')),
          findsNothing);

      // The strip belongs to the card the pointer is ON — the neighbouring
      // board is not asked about, and does not answer.
      expect(_assetClassStrip('b-eng-2'), findsNothing);
    });

    // The pointer left; so did the strip.
    expect(_assetClassStrip('b-eng-1'), findsNothing);

    // THE CUMULATIVE-COUNTER TRAP. The engine counts an approved step into BOTH
    // `human_approved` and `ai_complete` (src/pipeline.rs `pipeline_status`), so
    // reading `ai_complete` as "in flight" wholesale would report this board as
    // 1 pending + 3 in-flight + 2 done — six states across four steps, with two
    // finished steps still claiming to be moving. The four chips partition the
    // compiled steps exactly once.
    final counts =
        BoardPipelineCounts.from(await backend.pipelineStatus('b-eng-1'))!;
    expect(counts.total, 4);
    expect(counts.pending + counts.inFlight + counts.done + counts.failed,
        counts.total);
    expect(counts.inFlight, 1, reason: 'only the gate-parked step is moving');

    // A FAILURE shows up, and stops being counted as in flight: rejecting the
    // parked step at its gate moves it out of in-flight and into failed.
    final afterReject = FakeCyanBackend();
    expect(
      (await afterReject.pipelineRejectAs('b-eng-1', 'ws3', 'producer@studio'))
          .success,
      isTrue,
    );

    await pumpParity(
      tester,
      const ParityWorkspaceView(workspaceId: _backendServices),
      backend: afterReject,
      size: _size,
    );
    await _whileHovering(
        tester, find.byKey(const ValueKey('workspace.board.b-eng-1')),
        () async {
      final rejected = _assetClassStrip('b-eng-1');
      expect(find.descendant(of: rejected, matching: find.text('1 failed')),
          findsOneWidget);
      expect(find.descendant(of: rejected, matching: find.text('0 in-flight')),
          findsOneWidget);
      expect(find.descendant(of: rejected, matching: find.text('1 pending')),
          findsOneWidget);
      expect(find.descendant(of: rejected, matching: find.text('2 done')),
          findsOneWidget);
    });

    // A board with NO COMPILED STEPS has no strip. Zeroes would say "authored
    // and idle"; the truth is that nothing has been compiled into an
    // asset-class pipeline at all.
    await pumpParity(
      tester,
      const ParityWorkspaceView(workspaceId: _backendServices),
      size: _size,
    );
    await _whileHovering(
        tester, find.byKey(const ValueKey('workspace.board.b-eng-2')),
        () async {
      expect(_assetClassStrip('b-eng-2'), findsNothing);
    });
    expect(
      BoardPipelineCounts.from(
              await FakeCyanBackend().pipelineStatus('b-eng-2'))
          ?.isEmpty,
      isTrue,
    );

    // AND THE SAME RULE AS THE RUN BADGE: a read that did not land claims
    // nothing. An engine that will not answer must not produce a zero-strip on
    // a board that may be mid-workflow.
    expect(BoardPipelineCounts.from(null), isNull);
    expect(
      BoardPipelineCounts.from(
          const PipelineStatus(boardId: 'b-eng-1', error: 'store busy')),
      isNull,
    );

    await pumpParity(
      tester,
      const ParityWorkspaceView(workspaceId: _backendServices),
      backend: _PipelineUnreachableBackend(),
      size: _size,
    );
    await _whileHovering(
        tester, find.byKey(const ValueKey('workspace.board.b-eng-1')),
        () async {
      expect(_assetClassStrip('b-eng-1'), findsNothing);
      expect(find.textContaining('pending'), findsNothing);
      expect(find.textContaining('in-flight'), findsNothing);

      // The run badge is a DIFFERENT feed and is untouched by the engine read
      // failing — the two answer different questions on the same card.
      expect(
        find.descendant(
            of: _runBadge('b-eng-1'), matching: find.text('Needs approval')),
        findsOneWidget,
      );
    });
  });

  // ---- a workspace nobody asked for --------------------------------------

  testWidgets(
      'an unknown workspace id says so instead of rendering an empty '
      'frame', (tester) async {
    await pumpParity(
      tester,
      const ParityWorkspaceView(workspaceId: 'w-does-not-exist'),
      size: _size,
    );

    expect(find.text('No such workspace'), findsOneWidget);
  });

  testWidgets('golden: workspace surface', (tester) async {
    await pumpParity(
      tester,
      const ParityWorkspaceView(workspaceId: _backendServices),
      size: _size,
    );
    await expectLater(
      find.byType(ParityWorkspaceView),
      matchesGoldenFile('golden/workspace_surface.png'),
    );
  }, tags: 'golden');
}
