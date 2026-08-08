// test/board_container_test.dart
//
// STAGE face_board_container — the board cube: one board, three faces, and the
// selector that turns it. Tier-1: drives `ParityBoardContainer` through the
// `CyanBackend` seam (FakeCyanBackend), no dylib.
//
// Behaviour spec: scripts/parity_faces/board_container.txt.
//
// SwiftUI reference (read-only):
//   Views/BoardContainerViewNew.swift  — the container + `switchToFace`, which
//                                        persists through `BoardFaceBridge`
//                                        BEFORE the tab moves
//   Views/BoardFace.swift              — `standardFaces`, `fromLegacy`,
//                                        `resolved(saved:deployment:)`
//   CyanTests/BoardFacesVMTests.swift  — `test_canvas_face_absent`

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/models/board_face.dart';
import 'package:cyan_flutter/widgets/parity/parity_board_container.dart';
import 'package:cyan_flutter/widgets/parity/parity_dashboard_view.dart';
import 'package:cyan_flutter/widgets/parity/parity_notes_view.dart';
import 'package:cyan_flutter/widgets/parity/parity_review_player.dart';
import 'package:cyan_flutter/widgets/parity/parity_workflow_view.dart';

import 'support/parity_test_harness.dart';

/// Engineering / Backend Services / "Database Schema" — authored, NOT deployed,
/// so it opens on its saved face instead of being pulled onto the Dashboard.
const _schema = 'b-eng-2';

/// Engineering / Infrastructure / "Deployment Notes" — saved on the Notes face.
const _deployNotes = 'b-eng-4';

/// A board still SAVED on the face that was removed. The engine happily hands
/// back what was written years ago; the app has to survive reading it.
class _CanvasBoardBackend extends FakeCyanBackend {
  @override
  Future<String?> boardActiveFace(String boardId) async => 'canvas';
}

/// An engine that REFUSES the face write (locked board / DB contention).
class _RefusingBackend extends FakeCyanBackend {
  @override
  Future<bool> setBoardActiveFace(String boardId, String face) async => false;
}

Finder _tab(BoardFace face) =>
    find.byKey(ValueKey('board.face.${face.rawValue}'));

Future<void> _tapFace(WidgetTester tester, BoardFace face) async {
  await tester.tap(_tab(face));
  await tester.pumpAndSettle();
}

/// The board name the header is standing on.
String _headerBoard(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('board.name'))).data!;

void main() {
  // ---- board_container.txt, line 1 -----------------------------------------

  testWidgets(
      'the board container exposes exactly three faces Workflow Notes and '
      'Dashboard', (tester) async {
    // Swift: `BoardFace.standardFaces == [.notebook, .notes, .dashboard]`, and
    // the selector renders exactly that array. Three tabs, three surfaces, and
    // one of them mounted at a time — a fourth would be a face the engine has
    // no mode string for.
    await pumpParity(tester, const ParityBoardContainer(boardId: _schema));

    for (final face in kStandardBoardFaces) {
      expect(_tab(face), findsOneWidget,
          reason: 'the selector must offer the ${face.label} face');
    }
    // STRICTER than the old `BoardFace.values.length == 3`, which conflated the
    // enum with what a board OFFERS. Swift declares four faces
    // (BoardFace.swift:12-16) and appends `.video` to `availableFaces` only
    // when the board resolves a media asset. So: four declared, three standard,
    // and this board — which has no media — shows exactly three tabs.
    expect(BoardFace.values, hasLength(4),
        reason: 'Swift declares notebook / notes / dashboard / video');
    expect(kStandardBoardFaces, hasLength(3),
        reason: 'the faces EVERY board carries');
    expect(kStandardBoardFaces, isNot(contains(BoardFace.video)),
        reason: 'video is conditional, never standard');
    expect(
        find.byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('board.face.')),
        findsNWidgets(3),
        reason: 'a board with no media shows no Video tab');
    expect(_tab(BoardFace.video), findsNothing,
        reason: 'a Video tab onto an empty player is worse than no tab');

    // The other half of the same contract, asserted where the fixture has
    // media. `ParityReviewPlayerView` (scrubber, timecode rail, graphics strip,
    // approve/reject, PRODUCE MASTER) was fully ported and had no door:
    // `BoardFace` had no video member and `_face` was a three-arm switch, so no
    // click path in the app reached a delivered master — the end of the spine.
    await pumpParity(tester, const ParityBoardContainer(boardId: 'b-eng-1'),
        size: const Size(1200, 900));

    expect(_tab(BoardFace.video), findsOneWidget,
        reason: 'b-eng-1 resolves a review proxy, so it carries the face');
    expect(
        find.byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('board.face.')),
        findsNWidgets(4),
        reason: 'the standard three plus Video');

    await _tapFace(tester, BoardFace.video);
    expect(find.byType(ParityReviewPlayerView), findsOneWidget,
        reason: 'the Video face mounts the surface that carries approve, the '
            'graphics rail and produce-master');

    // Back to the media-less board for the rest of this case.
    await pumpParity(tester, const ParityBoardContainer(boardId: _schema));

    // Each tab is named, and each one MOUNTS a real surface: the authored
    // workflow, the editor, the run dashboard.
    for (final face in kStandardBoardFaces) {
      expect(find.descendant(of: _tab(face), matching: find.text(face.label)),
          findsOneWidget,
          reason: 'the ${face.label} tab is labelled');
    }

    expect(find.byType(ParityWorkflowView), findsOneWidget);
    expect(find.text('Design the schema'), findsOneWidget,
        reason: 'the Workflow face shows THIS board\'s authored steps');
    expect(find.byType(ParityNotesView), findsNothing);
    expect(find.byType(ParityDashboardView), findsNothing);

    await _tapFace(tester, BoardFace.notes);
    expect(find.byType(ParityNotesView), findsOneWidget);
    expect(find.byType(ParityWorkflowView), findsNothing);
    expect(find.byType(ParityDashboardView), findsNothing);

    await _tapFace(tester, BoardFace.dashboard);
    expect(find.byType(ParityDashboardView), findsOneWidget);
    expect(find.byType(ParityWorkflowView), findsNothing);
    expect(find.byType(ParityNotesView), findsNothing);
  });

  // ---- board_container.txt, line 2 -----------------------------------------

  testWidgets('switching face preserves the board selection', (tester) async {
    // Turning the cube is a change of VIEW, never a change of board: the header
    // keeps naming the same board, every face mounts on the same id, and the
    // engine is told about that board's face and no other's.
    final backend = FakeCyanBackend();
    final faces = <BoardFace>[];
    await pumpParity(
      tester,
      ParityBoardContainer(boardId: _schema, onFaceChanged: faces.add),
      backend: backend,
    );

    expect(_headerBoard(tester), 'Database Schema');
    expect(
        tester
            .widget<ParityWorkflowView>(find.byType(ParityWorkflowView))
            .boardId,
        _schema);

    await _tapFace(tester, BoardFace.notes);
    expect(_headerBoard(tester), 'Database Schema',
        reason: 'the open board survives the face switch');
    expect(tester.widget<ParityNotesView>(find.byType(ParityNotesView)).boardId,
        _schema,
        reason: 'the new face mounts on the SAME board');

    await _tapFace(tester, BoardFace.dashboard);
    expect(_headerBoard(tester), 'Database Schema');
    expect(
        tester
            .widget<ParityDashboardView>(find.byType(ParityDashboardView))
            .boardId,
        _schema);

    // Back to Workflow: the same board's authored steps, not another board's.
    await _tapFace(tester, BoardFace.workflow);
    expect(find.text('Design the schema'), findsOneWidget);
    expect(faces, [BoardFace.notes, BoardFace.dashboard, BoardFace.workflow]);

    // The face was written for THIS board only — the sibling board is untouched
    // and still on the face it was authored with.
    expect(await backend.boardActiveFace(_schema), BoardFace.workflow.rawValue);
    expect(await backend.boardActiveFace(_deployNotes), 'notes');
  });

  testWidgets(
      'the face is remembered per board so reopening one restores its face',
      (tester) async {
    // The other half of "preserves the selection": the face belongs to the
    // board, so standing on a second board and coming back is not a reset.
    // Swift keys the mode by board id in `cyan_set_board_mode`.
    final backend = FakeCyanBackend();
    await pumpParity(tester, const _BoardHost(_schema), backend: backend);

    void open(String boardId) =>
        tester.state<_BoardHostState>(find.byType(_BoardHost)).open(boardId);

    await _tapFace(tester, BoardFace.notes);
    expect(find.byType(ParityNotesView), findsOneWidget);

    // Stand on another board: it opens on ITS OWN saved face (Notes here),
    // never on the face the previous board was turned to by accident.
    open(_deployNotes);
    await tester.pumpAndSettle();
    expect(_headerBoard(tester), 'Deployment Notes');
    expect(find.text('deployment.md'), findsOneWidget);

    // Return: the board comes back on the face it was left on.
    open(_schema);
    await tester.pumpAndSettle();
    expect(_headerBoard(tester), 'Database Schema');
    expect(find.byType(ParityNotesView), findsOneWidget,
        reason: 'the board reopens on the face it was left on');
  });

  testWidgets('a refused face write leaves the container where it was',
      (tester) async {
    // Swift's `switchToFace` publishes only after `setActiveFace` returns true.
    // A tab that moves on a refused write is a lie about what the board is on.
    await pumpParity(tester, const ParityBoardContainer(boardId: _schema),
        backend: _RefusingBackend());

    expect(find.byType(ParityWorkflowView), findsOneWidget);
    await _tapFace(tester, BoardFace.notes);

    expect(find.byType(ParityNotesView), findsNothing,
        reason: 'the engine refused the write — the face must not move');
    expect(find.byType(ParityWorkflowView), findsOneWidget);
  });

  testWidgets('a deployed board with a live dashboard opens on the Dashboard',
      (tester) async {
    // R12 D2 / `BoardFace.resolved(saved:deployment:)`: the flagship board is
    // deployed and running, so opening it shows the RUN, not the editor —
    // even though its saved face would also be dashboard, the resolution is
    // what makes an undeployed board keep its own.
    await pumpParity(tester, const ParityBoardContainer(boardId: 'b-eng-1'));

    expect(find.byType(ParityDashboardView), findsOneWidget);
    expect(find.byType(ParityWorkflowView), findsNothing);
  });

  testWidgets('the face chords ⌘1 ⌘2 ⌘3 turn the cube', (tester) async {
    // Swift Tier 3.5: ⌘1 Workflow · ⌘2 Notes · ⌘3 Dashboard, bound on the
    // container so they work from any face.
    await pumpParity(tester, const ParityBoardContainer(boardId: _schema));

    Future<void> chord(LogicalKeyboardKey digit) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(digit);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    await chord(LogicalKeyboardKey.digit2);
    expect(find.byType(ParityNotesView), findsOneWidget);

    await chord(LogicalKeyboardKey.digit3);
    expect(find.byType(ParityDashboardView), findsOneWidget);

    await chord(LogicalKeyboardKey.digit1);
    expect(find.byType(ParityWorkflowView), findsOneWidget);
  });

  // ---- board_container.txt, line 3 -----------------------------------------

  test('there is no canvas or whiteboard face', () {
    // Run A removed the canvas face: in Swift `BoardFace(rawValue: "canvas")`
    // is nil and the enum has no such case. Both halves hold here — the strict
    // parse refuses the removed spellings outright…
    // The enum matches Swift's four cases in Swift's order (BoardFace.swift:12),
    // and `standardFaces` is the three every board carries — the pair the old
    // single assertion conflated.
    expect(BoardFace.values.map((f) => f.rawValue),
        ['notebook', 'notes', 'dashboard', 'video']);
    expect(BoardFace.values.map((f) => f.label),
        ['Workflow', 'Notes', 'Dashboard', 'Video']);
    expect(kStandardBoardFaces.map((f) => f.rawValue),
        ['notebook', 'notes', 'dashboard']);
    expect(kStandardBoardFaces, isNot(BoardFace.values),
        reason: 'video is a real face but a conditional one');

    for (final gone in const ['canvas', 'whiteboard', 'freeform']) {
      expect(tryParseBoardFace(gone), isNull,
          reason: '"$gone" is not a face this app has');
    }

    // …and a board SAVED on one of them is migrated onto Workflow rather than
    // stranded on a face that no longer exists (Swift `fromLegacy`).
    for (final legacy in const [
      'canvas',
      'whiteboard',
      'freeform',
      'nonsense'
    ]) {
      expect(boardFaceFromLegacy(legacy), BoardFace.workflow);
    }
    expect(boardFaceFromLegacy(null), BoardFace.workflow);
    expect(boardFaceFromLegacy('notes'), BoardFace.notes);
    expect(boardFaceFromLegacy('notebook'), BoardFace.workflow);
    expect(boardFaceFromLegacy('dashboard'), BoardFace.dashboard);
  });

  testWidgets('a board saved on the removed canvas face opens on Workflow',
      (tester) async {
    // The container half of the same rule: a legacy board is readable, and the
    // selector it lands in never grows a Canvas or Whiteboard tab for it.
    await pumpParity(tester, const ParityBoardContainer(boardId: _schema),
        backend: _CanvasBoardBackend());

    expect(find.byType(ParityWorkflowView), findsOneWidget);
    expect(find.text('Canvas'), findsNothing);
    expect(find.text('Whiteboard'), findsNothing);
    expect(find.byIcon(Icons.brush), findsNothing);
  });
}

/// A host that can swap which board the container stands on — how the workspace
/// surface opens one board after another without rebuilding the world.
class _BoardHost extends StatefulWidget {
  final String initialBoardId;
  const _BoardHost(this.initialBoardId);

  @override
  State<_BoardHost> createState() => _BoardHostState();
}

class _BoardHostState extends State<_BoardHost> {
  late String _boardId = widget.initialBoardId;

  void open(String boardId) => setState(() => _boardId = boardId);

  @override
  Widget build(BuildContext context) => ParityBoardContainer(boardId: _boardId);
}
