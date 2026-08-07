// autopilot_face_test.dart — TIER 2. Row 22's lane, through the PRODUCTION
// seam against a real engine.
//
// The Tier-1 suite drives `FakeCyanBackend`, which round-trips a mode
// perfectly. This asks whether the ENGINE does — and whether the two verbs
// really are the shape the binder declares, which a PE export table cannot say.
//
// The lane is `cyan_autopilot_set` / `cyan_autopilot_get`. Both answer the
// engine's JSON envelope (`{"success":…,"mode":"…"}`), NOT a bool — a binder
// that declared them bool-returning would dereference a JSON pointer as one.
//
//   flutter test integration_test/autopilot_face_test.dart -d windows

import 'dart:io';

import 'package:cyan_flutter/ffi/cyan_backend_ffi.dart';
import 'package:cyan_flutter/ffi/ffi_helpers.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final backend = CyanBackendFFI();
  late String board;
  late String otherBoard;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('cyan_autopilot_');
    expect(CyanFFI.setDataDir(tmp.path), isTrue,
        reason: 'the engine refused ${tmp.path} as its data dir and would '
            'write its blob store into the source tree');
    expect(
      CyanFFI.initWithIdentity(
        dbPath: '${tmp.path}/cyan.db',
        secretKeyHex: List.filled(64, 'a').join(),
        relayUrl: '',
        discoveryKey: 'cyan-autopilot-face-test',
      ),
      isTrue,
      reason: 'the engine refused to boot with an identity',
    );
    await backend.initialize();

    CyanFFI.seedDemo();
    var boards = <BoardWithContext>[];
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      boards = await backend.loadAllBoards();
      if (boards.length >= 2) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(boards.length, greaterThanOrEqualTo(2),
        reason: 'the seed never landed');
    board = boards[0].board.id;
    otherBoard = boards[1].board.id;
  });

  tearDownAll(() {
    // The engine parks CyanSystem in a process-lifetime OnceCell and exports no
    // shutdown verb, so SQLite stays open and Windows will not unlink the file.
    // Name what is tolerated rather than going red or swallowing.
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException catch (e) {
      // ignore: avoid_print
      print('note: left ${tmp.path} for the OS to reap — the engine still '
          'holds the database open and has no shutdown verb to call. ($e)');
    }
  });

  test('a board that has never been flipped reads OFF — the engine\'s own '
      'default is that every gate is human', () async {
    expect(await backend.autopilotMode(board), 'off');
  });

  test('the mode round-trips through the engine, and the READ is what the '
      'toolbar believes', () async {
    for (final mode in const ['assist', 'autopilot', 'off']) {
      final settled = await backend.setAutopilotMode(board, mode);
      expect(settled, mode,
          reason: 'the engine did not keep $mode — the seam answers with a '
              'read-back, so this is the engine\'s word, not the write\'s');
      // …and an independent read agrees, which is the fact the face draws.
      expect(await backend.autopilotMode(board), mode);
    }
  });

  test('the mode is PER BOARD — flipping one does not delegate the other',
      () async {
    await backend.setAutopilotMode(board, 'autopilot');
    expect(await backend.autopilotMode(board), 'autopilot');
    expect(await backend.autopilotMode(otherBoard), 'off',
        reason: 'autopilot leaking across boards would delegate gates on a '
            'board nobody adopted it for');
    // Put it back — the kill switch is the half that has to work.
    expect(await backend.setAutopilotMode(board, 'off'), 'off');
  });

  test('a mode outside the engine\'s vocabulary never reaches it, and the '
      'board keeps what it had', () async {
    await backend.setAutopilotMode(board, 'assist');
    expect(await backend.setAutopilotMode(board, 'ludicrous'), 'assist',
        reason: 'the engine owns the vocabulary; a client that invents one '
            'earns a refusal it would then have to explain');
    expect(await backend.autopilotMode(board), 'assist');
    await backend.setAutopilotMode(board, 'off');
  });

  test('an unknown board does not crash the lane — it answers a mode', () async {
    // The engine has no row for this board. Whatever it decides, the seam must
    // come back with a STRING the toolbar can draw, never a null or a throw.
    final mode = await backend.autopilotMode('board-that-does-not-exist');
    expect(mode, isNotEmpty);
    expect(const {'off', 'assist', 'autopilot'}, contains(mode));
  });

  test('the engine stamps a POLICY clearance so the Dashboard can tell it from '
      'a human one', () async {
    // What the Auto-approved chip is keyed on: `approved_by` carrying the
    // engine's `policy:` prefix. This test does NOT drive the autopilot pump to
    // completion — that is Rust-internal and needs a bound model — so it proves
    // the FIELD reaches Dart, which is the half the port owns. A gate nothing
    // has cleared reports nobody, and that is the honest reading.
    final status = await backend.pipelineStatus(board);
    for (final step in status.steps) {
      final by = step.approvedBy;
      if (by == null) {
        expect(step.isPolicyCleared, isFalse);
      } else {
        // Whatever the engine wrote, the predicate must agree with the prefix.
        expect(step.isPolicyCleared, by.startsWith('policy:'));
      }
    }
  });
}
