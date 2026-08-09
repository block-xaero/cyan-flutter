// demo_corpus_test.dart — THE DEMO CORPUS BUILD (Rick's mandate, 2026-08-09).
//
// Four styled boards on ONE durable demo island (`~/cyan-demo-island`) that
// the desktop app opens directly (CYAN_DATA_DIR). Each invocation builds and
// walks ONE board (the engine's OnceCell allows one boot per process):
//
//   DEMO_BOARD=lynch   — David Lynch master · AUTOPILOT · WITHOUT notes
//   DEMO_BOARD=wes     — Wes Anderson master · AUTOPILOT · WITH notes
//   DEMO_BOARD=w90s    — warm-90s master · HUMAN-GATED · WITH notes
//   DEMO_BOARD=iphone  — phone-footage lane · separate_tracks first, then a
//                        selectable style (default warm 90s)
//
// Every walk is the proven W1/W2 shape: real Frame.io, the producer window,
// premiere-watcher, real AE title + house render, the colorist's ONE human
// confirm on the colour class (AUTO-1 is the floor, not a nuisance), live
// Resolve apply. Data is PARKED — nothing here cleans up the island.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cyan_flutter/ffi/ffi_helpers.dart';

import 'flight_harness.dart';

final demoIsland =
    '${Platform.environment['HOME']}/cyan-demo-island';

class BoardSpec {
  const BoardSpec({
    required this.key,
    required this.group,
    required this.board,
    required this.setFolder,
    required this.look,
    required this.title,
    required this.autopilot,
    required this.withNotes,
    this.demux = false,
  });
  final String key, group, board, setFolder, look, title;
  final bool autopilot, withNotes, demux;
}

final specs = <String, BoardSpec>{
  'lynch': BoardSpec(
    key: 'lynch',
    group: 'DEMO — Styled Masters',
    board: 'Lynch — In Dreams',
    setFolder: '$mediaRoot/SET_G_demo_sawmill_logc4',
    look: 'lynch',
    title: 'IN DREAMS — A CYAN PICTURE',
    autopilot: true,
    withNotes: false,
  ),
  'wes': BoardSpec(
    key: 'wes',
    group: 'DEMO — Styled Masters',
    board: 'Wes — The Multicut Society',
    setFolder: '$mediaRoot/SET_A_2398_prores422',
    look: 'wes anderson',
    title: 'THE MULTICUT SOCIETY',
    autopilot: true,
    withNotes: true,
  ),
  'w90s': BoardSpec(
    key: 'w90s',
    group: 'DEMO — Styled Masters',
    board: "90s — Summer of '94",
    setFolder: '$mediaRoot/SET_E_ccby_24p_mixed_res',
    look: 'warm 90s',
    title: "SUMMER OF '94",
    autopilot: false,
    withNotes: true,
  ),
  'iphone': BoardSpec(
    key: 'iphone',
    group: 'DEMO — Styled Masters',
    board: 'Phone — Field Notes',
    setFolder:
        '${Platform.environment['HOME']}/cyan-demo-inbox',
    look: 'warm 90s',
    title: 'FIELD NOTES',
    autopilot: true,
    withNotes: false,
    demux: true,
  ),
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final which = Platform.environment['DEMO_BOARD'] ?? 'lynch';
  final spec = specs[which]!;
  final flight = Flight('demo-$which', dataDir: demoIsland);

  setUpAll(() async {
    await flight.boot();
    flight.reviewProxyPathForBinding =
        '$mediaRoot/SET_F_review_proxy.mp4';
  });

  tearDownAll(() async {
    await flight.log.close();
  });

  test('the ${spec.key} board stands up on the demo island', () async {
    // Idempotent rerun: a half-walked same-named board is deleted first so
    // the demo island never accumulates duplicates.
    final stale = (await flight.backend.loadAllBoards())
        .where((b) => b.board.name == spec.board)
        .toList();
    for (final b in stale) {
      CyanFFI.deleteBoard(b.board.id);
      flight.log('stale demo board deleted: ${b.board.id}');
    }
    await flight.standUpBoard(
      groupName: spec.group,
      workspaceName: 'Masters',
      boardName: spec.board,
    );
    final outcomes = await flight.installPlugins();
    final missing = outcomes.entries
        .where((e) => !e.value.contains('"success":true'))
        .map((e) => e.key)
        .toList();
    expect(missing, isEmpty,
        reason: 'plugins refused on the island: $missing / $outcomes');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('the ${spec.key} SET ingests — multi-asset, content-addressed',
      () async {
    final out = await flight.ingestSetF(folder: spec.setFolder);
    final lane = flight.startReviewLane(out.assetHashes.first);
    flight.log('review lane: $lane');
    expect(out.ingested, greaterThan(0),
        reason: 'nothing ingested from ${spec.setFolder}');
    flight.log('demo ingest: discovered=${out.discovered} '
        'ingested=${out.ingested} deduped=${out.deduped}');
  }, timeout: const Timeout(Duration(minutes: 6)));

  test('the ${spec.key} spine authors, binds and compiles', () async {
    final steps = <String>[
      if (spec.demux)
        'separate the source tracks via @cyan-media.separate_tracks',
      'ingest and probe the dailies via @cyan-media.probe',
      'upload the review proxy for producer review via @frameio.upload_file '
          'file_path=$mediaRoot/SET_F_review_proxy.mp4 '
          'name=DEMO_${spec.key}_review.mp4 /needs-approval',
      'await the producer review notes from Frame.io',
      'pull the review comments from @frameio.list_comments',
      'sense the editor timeline updates via @premiere-watcher.scan_exports',
      'apply the approved graphics change via @ae.apply_op op=set_text '
          '/needs-approval',
      'render the endcard comp via @ae.apply_op op=render_comp '
          '/needs-approval',
      'grade the cut via @davinci-resolve.apply_look per the creative look '
          '/needs-approval',
      'produce the graded master and deliver it',
    ];
    await flight.authorSpine(steps);
    final binds = await flight.compile();
    final misses = binds.where((b) => b.missReason != null).toList();
    expect(misses, isEmpty,
        reason: 'unbound mentions: '
            '${misses.map((m) => m.missReason).toList()}');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('the ${spec.key} house doctrine lands: constitution + ops + notes',
      () async {
    // The constitution carries the style AND the title — the demo lever.
    flight.notePutHouse(
        'House rules: grade with the ${spec.look} look. '
        'endcard reads "${spec.title}". '
        'Deliver masters as MP4; keep reviewer timecodes verbatim.');

    // House graphics ops (the proven lane: proposed, policy-confirmed).
    flight.appendEntry({
      'kind': 'op',
      'op': 'ae.set_text',
      'intent': 'endcard title per the house constitution',
      'params': {
        'layer': 'title',
        'value': spec.title,
        'confidence': 0.95,
      },
      'state': 'proposed',
      'proposed_by': 'agent',
      'source': 'house-rules',
      'tc_in': 0,
      'active': true,
    });
    flight.appendEntry({
      'kind': 'op',
      'op': 'ae.render_comp',
      'intent': 'render the endcard comp (house rule)',
      'params': {'comp': 'CYAN_ENDCARD', 'confidence': 0.95},
      'state': 'proposed',
      'proposed_by': 'agent',
      'source': 'house-rules',
      'tc_in': 0,
      'active': true,
    });
    // The colour op: with-notes boards phrase it as the reviewer would and
    // the colorist supersedes later; without-notes boards propose the house
    // look directly.
    flight.appendEntry({
      'kind': 'op',
      'op': 'color',
      'intent': spec.withNotes
          ? 'reviewer asked for the ${spec.look} feel on the master'
          : 'house look for this board',
      'params': {'look': spec.look, 'confidence': 0.95},
      'state': 'proposed',
      'proposed_by': 'agent',
      'source': spec.withNotes ? 'lens-structuring' : 'house-rules',
      'tc_in': 0,
      'active': true,
    });
    expect(
        flight
            .entriesOfKind('op')
            .where((e) => '${e['op']}'.startsWith('ae.'))
            .length,
        greaterThanOrEqualTo(2));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the ${spec.key} walk runs to its master — '
      '${spec.autopilot ? "AUTOPILOT" : "HUMAN-GATED"}', () async {
    if (spec.autopilot) {
      expect(await flight.engageAutopilot(), 'autopilot');
    }
    await flight.resumeRun(); // starts the walk (autopilot would autostart too)

    var commented = false;
    final parkRetries = <String, int>{};
    Future<void> producer(Map<String, dynamic> status) async {
      // The one colour confirm: the colorist approves the house/note look the
      // moment it exists (AUTO-1: colour never auto-approves).
      final colour = flight
          .entriesOfKind('op')
          .where((e) => e['op'] == 'color' && e['state'] == 'proposed');
      for (final c in colour) {
        flight.setEntryState('${c['id']}', 'approved', by: 'colorist:rick');
      }
      if (!spec.autopilot) {
        // HUMAN-GATED: no pump runs, so the humans stamp EVERY creative op —
        // the gfx supervisor confirms the house ae.* proposals the way the
        // policy card would on an autopilot board (ae_release_ready holds the
        // AE steps until a matching approved op exists; run-3 proved it).
        for (final o in flight
            .entriesOfKind('op')
            .where((e) =>
                e['state'] == 'proposed' && '${e['op']}'.startsWith('ae.'))) {
          flight.setEntryState('${o['id']}', 'approved', by: 'gfx:rick');
        }
        // Approve at the run FRONTIER only (the first step not yet approved)
        // so the master can never be stamped before its grade — mirroring the
        // pump's manual_park frontier scan. ai_complete is safe anywhere: the
        // tool already ran. Resume after any approval: an approved gate does
        // not walk by itself (the 90s run-1 stall).
        final steps = Flight.stepsOf(status);
        final frontier = steps.indexWhere(
            (s) => '${s['status']}' != 'human_approved');
        var approvedAny = false;
        for (var i = 0; i < steps.length; i++) {
          final s = steps[i];
          final st = '${s['status']}';
          final err = '${s['error'] ?? ''}';
          final id = '${s['step_id']}';
          if (st == 'ai_complete') {
            approvedAny =
                flight.approveStep(id, by: 'supervisor:rick') || approvedAny;
          } else if (i == frontier &&
              st == 'scheduled' &&
              !('${s['title']}').contains('@')) {
            approvedAny =
                flight.approveStep(id, by: 'supervisor:rick') || approvedAny;
          } else if (i == frontier &&
              st == 'failed' &&
              err.startsWith('needs_human') &&
              (parkRetries[id] ?? 0) < 3) {
            // The product's park release: pending + carried approval in one
            // write, then resume re-dispatches WITH clearance. Approve+Retry
            // loses the clearance each cycle (runs 2-4); release-once means
            // a re-park under an approval is a defect, not a retry.
            parkRetries[id] = (parkRetries[id] ?? 0) + 1;
            approvedAny =
                flight.releaseStep(id, by: 'supervisor:rick') || approvedAny;
          }
        }
        if (approvedAny) await flight.resumeRun();
      }
      if (!commented) {
        for (final s in Flight.stepsOf(status)) {
          final r = s['ai_result'];
          if (r is String && r.contains('file_id')) {
            final m = RegExp(r'"file_id"\s*:\s*"([^"]+)"').firstMatch(r);
            if (m != null) {
              commented = true;
              await flight.producerComments(m.group(1)!,
                  'Producer: love the ${spec.look} direction. Ship it.');
            }
          }
        }
      }
    }

    final status = await flight.flyUntilSettled(
      limit: const Duration(minutes: 20),
      stillFor: const Duration(seconds: 300),
      onTick: producer,
    );

    final steps = Flight.stepsOf(status);
    final done = steps
        .where((s) => s['status'] == 'human_approved')
        .length;
    final grade =
        steps.firstWhere((s) => s['step_id'] == 'grade_the_cut');
    // WHO SIGNED — the demo's whole point. An autopilot board's gates carry the
    // policy identity plus its evidence; a human-gated board's carry people.
    // `anonymous` on either means the stamp lane is broken, not that nobody
    // clicked, so it fails the board rather than shipping a mute ledger.
    final signer = '${grade['approved_by']}';
    expect(signer, isNot(contains('anonymous')),
        reason: 'the grade landed unattributed: $signer');
    expect(signer,
        spec.autopilot ? contains('policy:dev-floor@v0') : contains('rick'),
        reason: 'wrong authority signed the ${spec.key} grade: $signer');
    flight.log('DEMO ${spec.key}: $done/${steps.length} approved; '
        'grade=${grade['status']} by=${grade['approved_by']}');
    expect(done, greaterThanOrEqualTo(steps.length - 2),
        reason: 'the walk left too much behind: '
            '${steps.map((s) => "${s['step_id']}:${s['status']}").join(" ")}');
    expect(grade['status'], 'human_approved',
        reason: 'the ${spec.look} grade did not land: '
            '${grade['status']} (${grade['error']})');
    expect('${grade['ai_result']}', contains('"applied":true'),
        reason: 'Resolve did not report the ${spec.look} grade applied');
  }, timeout: const Timeout(Duration(minutes: 22)));

  test('the ${spec.key} board ACCUMULATES its grade and its master', () async {
    // Rick demos from this island: the graded and mastered artifacts have to be
    // ON the board, not merely in the registry. A registry row is invisible to
    // a board (the D-8 lesson) — this rung is what keeps that honest.
    final version = flight.snapshotVersion();
    expect(version, isNotNull,
        reason: 'no frozen version — the delivery lane has nothing to render');
    final produced = flight.produceMaster();
    final out = produced?['output_path'] as String?;
    if (out == null) {
      flight.log('produce_master returned no output_path: $produced');
    }

    final files = flight.boardFiles();
    final names = files.map((f) => '${f['name']}').toList();
    flight.log('DEMO ${spec.key} board files: ${names.join(' | ')}');

    // Its OWN look, named for the look — not a neighbour's cube. Before the
    // ledger-first pick, four boards shared one board's grade.
    final look = spec.look.replaceAll(' ', '_');
    expect(names.any((n) => n.toLowerCase() == '$look.cube'.toLowerCase()),
        isTrue,
        reason: 'the ${spec.look} grade is not on the board: $names');

    // The graded PICTURE — the artifact that shows the look rather than
    // describing it. A board graded on an earlier run keeps its cube and used
    // to skip this entirely, ending up with a cube and a master but nothing to
    // look at.
    expect(names.any((n) => n.contains('graded')), isTrue,
        reason: 'no graded picture on the board: $names');

    // The endcard render the same run produced (the path that always worked —
    // if this is missing the whole registration lane is broken, not just mine).
    expect(names.any((n) => n.startsWith('CYAN_ENDCARD')), isTrue,
        reason: 'no endcard render on the board: $names');

    if (out != null) {
      expect(File(out).existsSync(), isTrue,
          reason: 'the delivery names a file that is not on disk: $out');
      expect(names.any((n) => n.contains('master')), isTrue,
          reason: 'a master was produced but never landed on the board: $names');
    }
  }, timeout: const Timeout(Duration(minutes: 12)));

  test('the ${spec.key} stage lineage is READABLE — review_versions answers',
      () async {
    final raw = flight.review({
      'op': 'review_versions',
      'board_id': flight.boardId,
    });
    expect(raw, isNotNull);
    final enc = jsonEncode(raw);
    flight.log('demo ${spec.key} versions: '
        '${enc.substring(0, enc.length.clamp(0, 220))}');
    expect((raw as Map)['versions'], isA<List>(),
        reason: 'the stage selector has no lineage to draw');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
