// chat_face_test.dart — TIER 2. The board Chat face, row 11, through the
// PRODUCTION seam against a real engine.
//
// `loadChat` returned a const empty list, so the transcript was empty for every
// board no matter what had been said on it. Tier-1 seeds a four-message
// transcript into FakeCyanBackend and never notices.
//
// There is no chat SNAPSHOT verb. `cyan_load_chat_history` REPLAYS the board's
// stored messages as `ChatSent` frames onto the `chat_panel` buffer, so the
// read is a replay drained back in — and this file drives the whole loop:
// SEND through the engine, then read the transcript back the way the app does.
//
// The demo seed lays down no chat, which is why this test writes its own. That
// is the stronger test anyway: it proves the send and the read agree, rather
// than proving the reader can parse a fixture.
//
//   flutter test integration_test/chat_face_test.dart -d windows

import 'dart:io';

import 'package:cyan_flutter/ffi/cyan_backend_ffi.dart';
import 'package:cyan_flutter/ffi/ffi_helpers.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _board = 'bc-smpte-qc';
const _otherBoard = 'bc-rgb-align';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final backend = CyanBackendFFI();

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('cyan_chat_');
    expect(CyanFFI.setDataDir(tmp.path), isTrue);
    expect(
      CyanFFI.initWithIdentity(
        dbPath: '${tmp.path}/cyan.db',
        secretKeyHex: List.filled(64, '9').join(),
        relayUrl: '',
        discoveryKey: 'cyan-chat-face-test',
      ),
      isTrue,
      reason: 'the engine refused to boot with an identity',
    );
    await backend.initialize();

    CyanFFI.seedDemo();
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if ((await backend.loadWorkflow(_board)).steps.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
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

  test('a board nobody has spoken on has an empty transcript, not a hang',
      () async {
    // The replay is drained to quiescence, so "nothing was said" has to resolve
    // on its own rather than waiting out the full bound. It must also not
    // return junk: the chat buffer is shared by every board.
    final before = await backend.loadChat(_otherBoard);
    expect(before, isEmpty,
        reason: 'the seed writes no chat, so anything here came from another '
            'board or was invented');
  });

  test('a message sent through the engine comes back in the transcript',
      () async {
    const body = 'Bars look clean — cleared for the QC gate.';
    final echo = await backend.sendChat(_board, body);
    expect(echo, isNotNull, reason: 'the seam refused a perfectly good message');
    expect(echo!.body, body);
    expect(echo.isOwn, isTrue);

    // The send is fire-and-forget on the wire — the engine mints the id and
    // stores the row on its command thread — so poll the READ rather than
    // sleeping a guessed interval.
    List<ChatMessage> transcript = const [];
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      transcript = await backend.loadChat(_board);
      if (transcript.isNotEmpty) break;
    }

    expect(transcript, hasLength(1),
        reason: 'the message was sent and the transcript came back empty — '
            'either the send never landed or the replay is not being drained');
    final m = transcript.single;
    expect(m.body, body);
    expect(m.id, isNotEmpty,
        reason: 'the ENGINE mints the id; an empty one means this side is '
            'echoing its own send rather than reading the stored row');
    expect(m.isOwn, isTrue,
        reason: 'this device authored it — the engine stamps its node id as '
            'the author and the transcript must recognise itself');
    expect(m.author, 'You');
    expect(m.timeLabel, isNotEmpty,
        reason: 'the engine timestamps every message; a blank time means the '
            'stamp was dropped in decode');
  });

  test('the transcript is board-scoped and stays in order', () async {
    const second = 'Second pass: alignment verified.';
    const third = 'Third: packaging now.';
    await backend.sendChat(_board, second);
    await backend.sendChat(_board, third);

    List<ChatMessage> transcript = const [];
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      transcript = await backend.loadChat(_board);
      if (transcript.length >= 3) break;
    }

    expect(transcript, hasLength(3));
    expect(
        transcript.map((m) => m.body),
        containsAll(
            [second, third, 'Bars look clean — cleared for the QC gate.']));

    for (final m in transcript) {
      expect(m.timeLabel, isNotEmpty);
    }

    // ORDERING, tested at the resolution the ENGINE actually keeps.
    // `chrono::Utc::now().timestamp()` is SECONDS, so messages sent inside one
    // second carry identical stamps and their relative order is not something
    // the engine defines — asserting a first message among those three would be
    // asserting a coincidence of buffer order. Waiting past a second boundary
    // gives a message a stamp that is genuinely later, and THAT ordering the
    // transcript must honour.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    const last = 'Fourth, and definitely later.';
    await backend.sendChat(_board, last);

    final after = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(after)) {
      transcript = await backend.loadChat(_board);
      if (transcript.length >= 4) break;
    }
    expect(transcript, hasLength(4));
    expect(transcript.last.body, last,
        reason: 'the newest message must sort last — the transcript is ordered '
            'by the engine\'s timestamp, not by whichever frame the buffer '
            'happened to hand over first');

    // The other board's chat must still be empty: `chat_panel` is one buffer
    // for every board, so a reader that does not filter by board id would show
    // this board's messages over there.
    expect(await backend.loadChat(_otherBoard), isEmpty,
        reason: 'messages leaked across boards — the chat buffer is shared and '
            'the board_id filter is what keeps transcripts apart');
  });

  test('whitespace is refused before it reaches the mesh', () async {
    expect(await backend.sendChat(_board, '   '), isNull);
    expect(await backend.sendChat(_board, ''), isNull);
    // …and nothing was stored: the four from the test above, still four.
    expect(await backend.loadChat(_board), hasLength(4));
  });
}
