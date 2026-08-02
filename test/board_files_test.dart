// test/board_files_test.dart
//
// PARITY face `chat_files` — the board FILES lane (SwiftUI `BoardFilesView` /
// `BoardFilesViewModel`). Tier-1: drives `ParityBoardFilesView` through the
// `CyanBackend` seam (FakeCyanBackend) with no dylib and no mesh.
//
// The face exists to answer "is this file actually HERE?", so the tests drive
// the three states a row can be in — on this device, on the mesh, and moving —
// and the transfer that carries a row from the second to the first.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/providers/board_files_controller.dart';
import 'package:cyan_flutter/widgets/parity/parity_board_files_view.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('board files list renders and reports download progress',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(
      tester,
      const ParityBoardFilesView(boardId: 'b-eng-1'),
      backend: backend,
    );

    // --- the list RENDERS: every file attached to this board, with its size
    // and where its bytes are.
    expect(find.text('reel_master_v4.mov'), findsOneWidget);
    expect(find.text('shot_list.csv'), findsOneWidget);
    expect(find.text('grade_reference.mov'), findsOneWidget);

    // Two are here; one has only synced its row.
    expect(find.textContaining('on this device'), findsNWidgets(2));
    expect(find.textContaining('on the mesh'), findsOneWidget);
    expect(find.textContaining('4.8 GB'), findsOneWidget);
    expect(find.textContaining('18.4 KB'), findsOneWidget);

    // Only the remote row offers a download — the bytes of the other two are
    // already on this device.
    expect(find.byIcon(Icons.arrow_circle_down), findsOneWidget);

    // --- it REPORTS DOWNLOAD PROGRESS: the transfer is polled off the seam and
    // the row shows the fraction climbing, not just a spinner.
    await tester.tap(find.byIcon(Icons.arrow_circle_down));
    await tester.pump();

    expect(find.textContaining('downloading'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    final seen = <int>[];
    for (var i = 0; i < 3; i++) {
      await tester.pump(BoardFilesController.pollInterval * 2);
      await tester.pump();
      final row = tester
          .widgetList<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator))
          .firstOrNull;
      if (row == null) break; // the transfer finished — the bar is gone
      seen.add(((row.value ?? 0) * 100).round());
    }

    // The reported progress MOVED, and only ever forward.
    expect(seen, isNotEmpty);
    expect(seen.first, greaterThan(0));
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThan(seen[i - 1]));
    }

    // --- and it lands: the transfer settles and the row is on this device.
    await tester.pumpAndSettle();
    expect(find.textContaining('on this device'), findsNWidgets(3));
    expect(find.textContaining('on the mesh'), findsNothing);
    expect(find.byIcon(Icons.arrow_circle_down), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    // The engine is the truth: the listing itself now carries the local path,
    // rather than the row having been patched in the widget.
    final files = await backend.filesForBoard('b-eng-1');
    final grade = files.firstWhere((f) => f.name == 'grade_reference.mov');
    expect(grade.isDownloaded, isTrue);
  });

  testWidgets('files are board scoped', (tester) async {
    await pumpParity(
      tester,
      const ParityBoardFilesView(boardId: 'b-prod-1'),
    );

    // b-prod-1 holds the brief and nothing from the engineering board.
    expect(find.text('q3_brief.pdf'), findsOneWidget);
    expect(find.text('reel_master_v4.mov'), findsNothing);
    expect(find.text('grade_reference.mov'), findsNothing);
  });

  testWidgets('a board with no files shows the empty state', (tester) async {
    await pumpParity(
      tester,
      const ParityBoardFilesView(boardId: 'b-des-2'),
    );

    expect(find.text('No files on this board yet'), findsOneWidget);
  });

  testWidgets('deleting a file drops it from the listing', (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(
      tester,
      const ParityBoardFilesView(boardId: 'b-prod-1'),
      backend: backend,
    );

    expect(find.text('q3_brief.pdf'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('q3_brief.pdf'), findsNothing);
    expect(await backend.filesForBoard('b-prod-1'), isEmpty);
  });

  test('file sizes read as the macOS row formats them', () {
    expect(fileSizeLabel(512), '512 bytes');
    expect(fileSizeLabel(18422), '18.4 KB');
    expect(fileSizeLabel(2210481), '2.2 MB');
    expect(fileSizeLabel(4821003776), '4.8 GB');
  });
}
