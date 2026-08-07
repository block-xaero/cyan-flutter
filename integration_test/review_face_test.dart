// review_face_test.dart — TIER 2. The Review player, row 13, through the
// PRODUCTION seam against a real seeded engine.
//
// The player's Tier-1 suite drives `FakeCyanBackend`, so every one of its
// eighteen assertions passes against a seam method that answers an honest empty
// forever. This file drives `CyanBackendFFI` against the engine and asks the
// two questions Tier-1 cannot:
//
//   1. does the change-list read REACH the engine — is the calm state the
//      engine's own answer, or the seam failing to call it at all?
//   2. does the GRAPHICS RAIL (AE-2, `board_graphics`) list a real registered
//      render, with the engine's own on-disk read-back?
//
// The rail is the row's new surface, and it is the one that can be proved end to
// end from Dart: `cyan_upload_file` files an objects row under a board and
// `asset_upsert` registers that hash as kind='graphic', which is exactly the
// join `board_graphics` reads. Everything else the AE lane does (the render
// itself, `register_ae_render_result`) is Rust-internal and unreachable from
// here — the rail's DATA path is provable, the render that fills it is not.
//
//   flutter test integration_test/review_face_test.dart -d windows

import 'dart:convert';
import 'dart:io';

import 'package:cyan_flutter/ffi/cyan_backend_ffi.dart';
import 'package:cyan_flutter/ffi/ffi_helpers.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/providers/review_player_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final backend = CyanBackendFFI();

  /// A seeded board and the group it belongs to — `board_graphics` joins the
  /// asset registry on the board's TENANT, which is that group id.
  late String board;
  late String tenant;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('cyan_review_');
    expect(CyanFFI.setDataDir(tmp.path), isTrue,
        reason: 'the engine refused ${tmp.path} as its data dir and would '
            'write its blob store into the source tree');
    expect(
      CyanFFI.initWithIdentity(
        dbPath: '${tmp.path}/cyan.db',
        secretKeyHex: List.filled(64, 'a').join(),
        relayUrl: '',
        discoveryKey: 'cyan-review-face-test',
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

  test('the change-list read reaches the engine, and a board with no review '
      'lane lands in the CALM state rather than an error', () async {
    final player = ReviewPlayerController(backend: backend, boardId: board);
    await player.load();

    expect(player.current.hydrated, isTrue,
        reason: 'the face would spin forever — the read never completed');
    // A seeded board has never been through a review round, so the engine has
    // no `review_state` for it. That is the CALM state, and it is the engine's
    // own answer: entries empty, no phase, nothing actionable, no crash.
    expect(player.current.phase, isNull);
    expect(player.current.entries, isEmpty);
    expect(player.current.pendingGates, isEmpty);
    expect(player.current.canProduceMaster, isFalse,
        reason: 'produce master must not be offered over a lane with no '
            'delivered version');

    // …and it is a REAL answer, not the seam swallowing an exception: the same
    // command asked directly comes back parseable and unerrored.
    final reply =
        await backend.changelistCommand({'op': 'list', 'board_id': board});
    expect(reply.error, isNot(contains('engine')),
        reason: 'the engine was not reached at all: ${reply.error}');
  });

  test('the graphics rail is EMPTY for a board with no registered render — an '
      'answer, never an error', () async {
    final reply = await backend
        .changelistCommand({'op': 'board_graphics', 'board_id': board});

    expect(reply.ok, isTrue, reason: 'board_graphics errored: ${reply.error}');
    expect(reply.fields['graphics'], isA<List>(),
        reason: 'the engine always sends the array — a missing key is the op '
            'not existing, which would make the strip untestable');
    expect(reply.fields['graphics'], isEmpty);

    final player = ReviewPlayerController(backend: backend, boardId: board);
    await player.loadGraphics();
    expect(player.current.graphics, isEmpty,
        reason: 'the strip must not exist before a render lands');
  });

  test('a registered graphic asset appears on the rail with the ENGINE\'s own '
      'on-disk read-back, and grays out when its bytes vanish', () async {
    // A render lands on the board: an objects row under it (the upload verb)
    // whose hash is registered in the asset registry as kind='graphic'. That
    // join IS `board_graphics`.
    final source = File('${tmp.path}/CYAN_ENDCARD_gfx1.mp4');
    source.writeAsBytesSync(List<int>.filled(4096, 7));

    final uploaded = CyanFFI.uploadFile(source.path, {
      'type': 'Board',
      'board_id': board,
    });
    expect(uploaded, isNotNull, reason: 'cyan_upload_file answered nothing');
    final upload = jsonDecode(uploaded!) as Map<String, dynamic>;
    expect(upload['success'], isTrue, reason: 'upload failed: $upload');
    final hash = upload['hash'] as String;

    final registered = await backend.changelistCommand({
      'op': 'asset_upsert',
      'asset': {
        'hash': hash,
        'tenant_id': tenant,
        'kind': 'graphic',
        'remote_refs': <String, dynamic>{},
        'profile_json': <String, dynamic>{},
        'created_at': 0,
      },
    });
    expect(registered.ok, isTrue,
        reason: 'asset_upsert refused the graphic: ${registered.error}');

    final player = ReviewPlayerController(backend: backend, boardId: board);
    await player.loadGraphics();

    expect(player.current.graphics, hasLength(1),
        reason: 'the rail did not see a graphic the engine holds a row for — '
            'the read is not reaching the objects⋈asset join');
    final g = player.current.graphics.single;
    expect(g.hash, hash);
    expect(g.name, 'CYAN_ENDCARD_gfx1.mp4');
    expect(g.bytes, 4096);
    expect(g.onDisk, isTrue,
        reason: 'the engine stored the bytes and could not find them again');
    expect(g.playable, isTrue);
    expect(g.path, isNotNull);

    // The honest state the strip exists to draw: the engine reads the
    // filesystem itself, so a render whose file is gone comes back OFFLINE
    // instead of a card that clicks into nothing.
    File(g.path!).deleteSync();
    await player.loadGraphics();
    final gone = player.current.graphics.single;
    expect(gone.onDisk, isFalse,
        reason: 'on_disk is being echoed from the row rather than read from '
            'disk — a vanished render would offer a dead click');
    expect(gone.playable, isFalse);
  });
}
