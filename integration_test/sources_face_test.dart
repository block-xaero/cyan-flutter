// sources_face_test.dart — TIER 2. The Sources sheet, row 17, through the
// PRODUCTION seam against a real engine.
//
// The sheet's whole surface is one verb — `cyan_ingest_command` — driven with
// six ops: `source_add` / `source_list` / `source_remove` for the sensor CRUD,
// `scan_now` and `scan_due` for the two ways a source is walked, and
// `runs_for_board` for the strip underneath. Tier-1 drives all six against the
// fake, which answers them perfectly; this file asks whether the ENGINE does.
//
// The sensors are TENANT-scoped and the sheet is BOARD-scoped, so a real
// tenant id matters here: `source_list` answers the whole tenant and the
// controller filters to its board. A test that passed a made-up tenant would
// prove nothing about that filter.
//
//   flutter test integration_test/sources_face_test.dart -d windows

import 'dart:io';

import 'package:cyan_flutter/ffi/cyan_backend_ffi.dart';
import 'package:cyan_flutter/ffi/ffi_helpers.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory watch;
  final backend = CyanBackendFFI();
  late String board;
  late String tenant;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('cyan_sources_');
    expect(CyanFFI.setDataDir(tmp.path), isTrue,
        reason: 'the engine refused ${tmp.path} as its data dir and would '
            'write its blob store into the source tree');
    expect(
      CyanFFI.initWithIdentity(
        dbPath: '${tmp.path}/cyan.db',
        secretKeyHex: List.filled(64, '1').join(),
        relayUrl: '',
        discoveryKey: 'cyan-sources-face-test',
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
      if (boards.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(boards, isNotEmpty, reason: 'the seed never landed');
    board = boards.first.board.id;
    tenant = boards.first.group.id;

    // A real folder to point a sensor at, with one media file in it.
    watch = Directory('${tmp.path}/watch')..createSync(recursive: true);
    File('${watch.path}/reel-01.mov')
        .writeAsBytesSync(List<int>.filled(2048, 3));
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException catch (e) {
      // ignore: avoid_print
      print('note: left ${tmp.path} for the OS to reap — the engine still holds '
          'the database open and has no shutdown verb to call. ($e)');
    }
  });

  test('a board with no sensors lists NONE — an answer, not an error',
      () async {
    final listed = await backend
        .ingestCommand({'op': 'source_list', 'tenant_id': tenant});

    expect(listed.ok, isTrue, reason: 'source_list errored: ${listed.error}');
    expect(listed.sources, isEmpty,
        reason: 'the seed files no ingest sources; if this is non-empty the '
            'rest of this suite is asserting against someone else\'s data');
  });

  test('adding a sensor is a real write the engine keeps, and it comes back '
      'scoped to its board', () async {
    final added = await backend.ingestCommand({
      'op': 'source_add',
      'tenant_id': tenant,
      'board_id': board,
      'kind': 'folder',
      'uri': watch.path,
      'schedule_secs': 900,
    });
    expect(added.ok, isTrue, reason: 'source_add refused: ${added.error}');

    final listed = await backend
        .ingestCommand({'op': 'source_list', 'tenant_id': tenant});
    expect(listed.sources, hasLength(1));
    final source = listed.sources.single;
    expect(source.id, isNotEmpty, reason: 'the engine minted no id');
    expect(source.boardId, board,
        reason: 'the sheet filters the TENANT-wide list down to its board — a '
            'source that comes back on the wrong board disappears from the '
            'sheet that created it');
    expect(source.kind, 'folder');
    expect(source.uri, watch.path);
    expect(source.scheduleSecs, 900);
  });

  test('scanning a sensor NOW walks the folder and reports what it found',
      () async {
    final listed = await backend
        .ingestCommand({'op': 'source_list', 'tenant_id': tenant});
    final source = listed.sources.single;

    final scanned = await backend.ingestCommand({
      'op': 'scan_now',
      'tenant_id': tenant,
      'source_id': source.id,
    });
    expect(scanned.ok, isTrue, reason: 'scan_now refused: ${scanned.error}');

    final report = scanned.report;
    expect(report, isNotNull,
        reason: 'a scan that answers no report leaves the sheet unable to say '
            'anything about what just happened');
    // The folder holds exactly one media file, and the engine walked it: a
    // report of zero over a folder with something in it would mean the sensor
    // is pointed somewhere the engine cannot read.
    expect(report!.discovered, 1,
        reason: 'the engine did not see reel-01.mov in ${watch.path}');
    expect(report.ingested, 1);
    expect(report.deduped, 0);

    // …and a SECOND scan of the same folder ingests nothing and dedups it —
    // ingest is content-addressed, so re-walking is not re-ingesting.
    final again = await backend.ingestCommand({
      'op': 'scan_now',
      'tenant_id': tenant,
      'source_id': source.id,
    });
    expect(again.report!.discovered, 1);
    expect(again.report!.ingested, 0,
        reason: 're-scanning ingested the same bytes again — every tick of a '
            'scheduled sensor would duplicate the board\'s assets');
    expect(again.report!.deduped, 1);

    // Whatever it ingested, the board's run strip is read off the engine too.
    final runs = await backend.ingestCommand({
      'op': 'runs_for_board',
      'tenant_id': tenant,
      'board_id': board,
    });
    expect(runs.ok, isTrue, reason: 'runs_for_board refused: ${runs.error}');
    expect(runs.runs.length, report.ingested,
        reason: 'the strip under the sheet is the runs the scan materialized — '
            'if these disagree the strip is showing something else');
  });

  test('the scheduled sweep is driven by the clock the CALLER passes, not by '
      'the wall clock', () async {
    final listed = await backend
        .ingestCommand({'op': 'source_list', 'tenant_id': tenant});
    final source = listed.sources.single;
    final scannedAt =
        (source.lastScanAt?.millisecondsSinceEpoch ?? 0) ~/ 1000;
    expect(scannedAt, greaterThan(0),
        reason: 'the scan above did not stamp `last_scan_at`, so the cadence '
            'has nothing to measure from and the sweep can never be due');

    // Nothing is due a moment after the scan that just ran.
    final notYet = await backend.ingestCommand({
      'op': 'scan_due',
      'tenant_id': tenant,
      'now': scannedAt + 1,
    });
    expect(notYet.ok, isTrue, reason: 'scan_due refused: ${notYet.error}');
    expect(notYet.sweep.where((o) => o.sourceId == source.id), isEmpty,
        reason: 'a source scanned a second ago is not due again — a sweep that '
            'fires anyway would re-walk every folder on every tick');

    // …and it IS due once its cadence has elapsed.
    final due = await backend.ingestCommand({
      'op': 'scan_due',
      'tenant_id': tenant,
      'now': scannedAt + 901,
    });
    expect(due.sweep.map((o) => o.sourceId), contains(source.id),
        reason: 'the cadence elapsed and the engine did not sweep it — the '
            'sheet\'s scheduled sources would never fire');
  });

  test('removing a sensor removes exactly it', () async {
    final before = await backend
        .ingestCommand({'op': 'source_list', 'tenant_id': tenant});
    final source = before.sources.single;

    final removed = await backend.ingestCommand({
      'op': 'source_remove',
      'tenant_id': tenant,
      'id': source.id,
    });
    expect(removed.ok, isTrue,
        reason: 'source_remove refused: ${removed.error}');

    final after = await backend
        .ingestCommand({'op': 'source_list', 'tenant_id': tenant});
    expect(after.sources, isEmpty);
  });

  test('an op the engine does not have is an ERROR the sheet can show, never a '
      'silent empty', () async {
    final bogus = await backend
        .ingestCommand({'op': 'not_a_real_op', 'tenant_id': tenant});
    expect(bogus.ok, isFalse);
    expect(bogus.error, isNotNull,
        reason: 'an unknown op that comes back "fine but empty" is how a sheet '
            'renders nothing and blames the data');
  });
}
