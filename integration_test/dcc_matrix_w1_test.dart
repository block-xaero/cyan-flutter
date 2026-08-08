// dcc_matrix_w1_test.dart — FLIGHT W1, the DCC matrix WITHOUT notes.
//
// The full DCC spine on SET_F, on Windows, driven through the REAL engine with
// the REAL apps: a clean board, no reviewer notes seeded, the step-text rungs
// and the authored house op driving the walk while the AUTOPILOT PUMP clears
// the gates its policy card covers.
//
// What this flight is FOR (AGENTIC_AUTOPILOT_DESIGN §8, the WITHOUT-notes half):
//   * the spine binds and dispatches to the real DCCs from a fresh group;
//   * the producer-review WINDOW is never skipped — policy waits for external
//     comments, and the stamp says which evidence cleared it;
//   * COLOR stays gated: `@davinci-resolve.apply_look`'s STEP gate is on the
//     dev-floor card and is released once, evidence-stamped, but the `color`
//     OP-CLASS is not on the card, so an agent-proposed grade is REFUSED and
//     the LUT is never invented (AUTO-1 — Agent/Auto never confirm);
//   * every failure lands ONE `incident` ledger row, deduped on source_ref;
//   * exactly one settle per (board, run).
//
// A leg this box cannot reach PARKS with its real error. Nothing here rounds a
// park up to a pass.
//
//   flutter test integration_test/dcc_matrix_w1_test.dart -d windows

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'flight_harness.dart';

/// The proxy the producer reviews. Real bytes: a 540p H.264 the cyan-media
/// plugin transcoded from the SET_F hero plate on this box.
final reviewProxy = Platform.isWindows
    ? r'C:\cyan-media-staging\SET_F_review_proxy.mp4'
    : '$mediaRoot/SET_F_review_proxy.mp4';

/// The spine, authored order. Authored order is law — the engine runs exactly
/// this, and a step that FAILS halts the walk with everything downstream
/// blocked ("Run halted: step FAILED — downstream blocked", `pipeline.rs`).
///
/// ORDERING, STATED: the brief's leg list runs graphics before review. This
/// board runs the legs THIS BOX CAN ACTUATE first (cyan-media, Frame.io, the
/// watcher) and the ones it cannot (After Effects, Resolve) after. The leg SET
/// is the brief's, unchanged; only the order moved, and it moved because a
/// halt on an unreachable DCC in position 2 would have left the Frame.io
/// round-trip — the half this box CAN prove — untested. The parks are reported
/// as parks either way.
final spine = <String>[
  // 1 — ingest + probe the dailies. Real ffprobe on the real ARRI plate.
  'ingest and probe the dailies via @cyan-media.probe',
  // 2 — the review proxy goes out for producer review. `file_path`/`name` are
  // AUTHOR-SUPPLIED inline (the reconciliation ladder's first rung); the
  // executor backstop fills the plugin-config invariants (account/folder).
  'upload the review proxy for producer review via @frameio.upload_file '
      'file_path=$reviewProxy name=SET_F_W1_review.mp4 /needs-approval',
  // 3 — the producer WINDOW. A real park: policy holds here until a
  // frameio-sourced note newer than the window's open exists, or the
  // explicitly configured elapse — and the stamp says WHICH.
  'await the producer review notes from Frame.io',
  // 4 — the sense leg: pull what the producer actually said.
  'pull the review comments from @frameio.list_comments',
  // 5 — the editor's side, sensed rather than assumed.
  'sense the editor timeline updates via @premiere-watcher.scan_exports',
  // 6/7 — the graphics rail: the confirmed house op fills set_text, then the
  // endcard comp renders to a registered asset.
  'apply the approved graphics change via @ae.apply_op op=set_text /needs-approval',
  'render the endcard comp via @ae.apply_op op=render_comp /needs-approval',
  // 8 — grade. Gated by design; the cube must come from a CONFIRMED color op.
  'grade the cut via @davinci-resolve.apply_look per the creative look /needs-approval',
  // 9 — the manual close.
  'produce the graded master and deliver it',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final flight = Flight('W1');
  late IngestOutcome ingested;

  setUpAll(() async {
    await flight.boot();
    await flight.standUpBoard(
      groupName: 'DCC Matrix W1',
      workspaceName: 'Flight',
      boardName: 'spineW1',
    );
  });

  tearDownAll(() async {
    flight.log('=== FLIGHT W1 ends — data dir ${flight.dataDir} ===');
    await flight.log.close();
  });

  test('the flight group installs the real signed plugin bundles', () async {
    final outcomes = await flight.installPlugins();
    for (final entry in outcomes.entries) {
      final reply = jsonDecode(entry.value) as Map<String, dynamic>;
      expect(reply['success'], isTrue,
          reason: 'plugin ${entry.key} did not install into the flight group: '
              '${entry.value}. `workflow_bind` refuses to bind an @mention '
              'whose plugin is not installed in the BOARD\'S GROUP, so a spine '
              'authored over a missing bundle can never dispatch.');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('SET_F ingests for real — content-hashed, registered, run materialised',
      () async {
    ingested = await flight.ingestSetF();
    expect(ingested.discovered, 1,
        reason: 'the sensor did not see the SET_F plate in $setFFolder');
    expect(ingested.ingested, 1,
        reason: 'the plate was discovered but never registered');
    expect(ingested.assetHashes, isNotEmpty,
        reason: 'no run materialised, so the ledger has nothing to anchor to');

    // The review lane opens on the ingested MASTER — the ledger anchor every
    // op, note and incident below hangs from.
    final lane = flight.startReviewLane(ingested.assetHashes.first);
    expect(lane, isNotNull);
    final env = flight.reviewEnvelope();
    expect(env, isNotNull,
        reason: 'the board still resolves no review lane, so `changelist` '
            'cannot address it and the incident rail has nowhere to write');
    expect(env!['asset_hash'], ingested.assetHashes.first);
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('the house graphics ops are proposed and the POLICY DOOR confirms them '
      '— an agent proposal, a policy approval, never an agent approval',
      () async {
    // WITHOUT notes: the ops come from the house rules the step text carries,
    // proposed by the agent lane exactly as a note-derived op would be. The
    // difference from W2 is their PROVENANCE, not their authority — and the
    // authority floor is what this asserts.
    for (final op in const [
      {
        'op': 'ae.set_text',
        'intent': 'endcard title reads the house sign-off',
        // The op-vocab's CLOSED schema for `ae.set_text` is {layer, value}
        // (+confidence). `comp` is the op's ANCHOR, not a param — passing it
        // here is refused at append, which is the vocabulary doing its job.
        'params': {
          'layer': 'title',
          'value': 'SET_F — W1 (no notes)',
          'confidence': 0.95,
        },
      },
      {
        'op': 'ae.render_comp',
        'intent': 'render the endcard comp for the conform',
        'params': {'comp': 'CYAN_ENDCARD', 'confidence': 0.95},
      },
    ]) {
      final appended = flight.appendEntry({
        'kind': 'op',
        'op': op['op'],
        'intent': op['intent'],
        'params': op['params'],
        'state': 'proposed',
        'proposed_by': 'agent',
        'source': 'house-rules',
        'tc_in': 0,
        'active': true,
        'asset_hash': ingested.assetHashes.first,
        'tenant_id': flight.groupId,
      });
      expect(appended, isNotNull, reason: 'the ledger refused ${op['op']}');
      flight.log('proposed ${op['op']} -> ${appended!['id']} '
          'state=${appended['state']}');
      expect(appended['state'], 'proposed',
          reason: 'an AGENT proposal that lands already-approved would be the '
              'AUTO-1 floor breaking, not the flight working');
    }

    final proposed = flight
        .entriesOfKind('op')
        .where((e) => e['state'] == 'proposed')
        .toList();
    expect(proposed, hasLength(2));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a COLOR op is proposed too — and must still be sitting there, refused, '
      'when the flight ends', () async {
    final appended = flight.appendEntry({
      'kind': 'op',
      'op': 'color',
      'intent': 'warm the endcard toward the house look',
      'params': {
        'look': 'teal orange',
        // Deliberately ABOVE the batch floor: the refusal must come from the
        // op-class not being on the card, not from a low number. A card that
        // cleared this because the confidence was high would be the §8 color
        // invariant breaking.
        'confidence': 0.97,
      },
      'state': 'proposed',
      'proposed_by': 'agent',
      'source': 'house-rules',
      'tc_in': 0,
      'active': true,
      'asset_hash': ingested.assetHashes.first,
      'tenant_id': flight.groupId,
    });
    expect(appended, isNotNull);
    flight.log('proposed color -> ${appended!['id']}');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('the spine authors and COMPILES — every @mention binds to a real '
      'installed tool', () async {
    await flight.authorSpine(spine);
    final binds = await flight.compile();
    expect(binds, hasLength(spine.length));

    // Every step that names a tool must have BOUND it. A miss here means the
    // walk would fall to the lens ReAct rail instead of dispatching the DCC.
    for (final b in binds) {
      if (!b.text.contains('@')) continue;
      expect(b.bound, isTrue,
          reason: 'step "${b.text}" did not bind: ${b.missReason}');
    }

    // The author-supplied upload args survived the bind — rung one of the
    // reconciliation ladder (author-supplied ALWAYS wins).
    final upload = binds.firstWhere((b) => b.tool == 'upload_file');
    expect(upload.args?['file_path'], reviewProxy,
        reason: 'the inline file_path was dropped, so the upload would have '
            'fallen back to the board media — a 490 MB camera master');
    expect(upload.sideEffects, contains('external_send'),
        reason: 'an upload that does not declare external_send would not be '
            'gated, and autopilot would send it with no gate to stamp');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('AUTOPILOT flies the spine', () async {
    expect(await flight.engageAutopilot(), 'autopilot');

    // THE FAR SIDE OF THE LOOP. Once the upload lands, a real producer comment
    // goes onto the real Frame.io file, through the real plugin — so the sense
    // leg reads back something a person said, not an empty list. Posted once,
    // and never a second upload: the proxy is reused, exactly as the brief
    // requires ("real park, reuse the same proxy — never re-upload over it").
    var commented = false;
    var producerFileId = '';
    String? producerCommentId;
    Future<void> producerSpeaks(Map<String, dynamic> status) async {
      if (commented) return;
      for (final s in Flight.stepsOf(status)) {
        final result = s['ai_result'];
        if (result is! String || !result.contains('file_id')) continue;
        final match = RegExp(r'"file_id"\s*:\s*"([^"]+)"').firstMatch(result);
        if (match == null) continue;
        producerFileId = match.group(1)!;
        commented = true;
        flight.log('producer comments on Frame.io file $producerFileId');
        producerCommentId = await flight.producerComments(
          producerFileId,
          'Producer: endcard title is fine, ship it. Colour pass still to come.',
        );
        return;
      }
    }

    final status = await flight.flyUntilSettled(
      limit: const Duration(minutes: 25),
      // 90s, not minutes: the process reproducibly DIES about 2m45s after the
      // walk stalls on the held window (§7.3), and the normative gates below
      // are non-negotiable. A park is a park at 90s or at 5min; what changes
      // is whether GATE 1 and GATE 2 ever get to run.
      stillFor: const Duration(seconds: 150),
      onTick: producerSpeaks,
    );
    flight.log('producer comment posted=$commented file=$producerFileId '
        'comment=$producerCommentId');
    expect(producerCommentId, isNotNull,
        reason: 'no real Frame.io comment was posted, so the producer window '
            'had no evidence to clear on and the sense leg had nothing to '
            'read — the review loop was never closed');

    // THE WINDOW WAS NOT SKIPPED. Whatever cleared it, the stamp says which:
    // real comments, or the explicitly configured elapse.
    final window = Flight.stepsOf(status)
        .firstWhere((s) => '${s['step_id']}'.contains('await'));
    flight.log('producer window: ${jsonEncode(window)}');
    final windowStamp = window['approved_by'] as String?;
    if (windowStamp != null) {
      expect(windowStamp, contains('window:'),
          reason: 'the window cleared on something that is not window '
              'evidence: $windowStamp');
    }
    flight.log('FINAL STATUS: ${jsonEncode(status)}');

    // The pump must have STARTED the walk on its own: flip-to-autopilot means
    // "run this", not "wait for a human to press Run".
    expect(status['run_id'], isNotNull,
        reason: 'no run id — the autostart rung never fired, so nothing the '
            'rest of this flight claims about the walk can be true');

    final steps = Flight.stepsOf(status);
    final cleared = steps.where((s) =>
        (s['approved_by'] as String?)?.startsWith('policy:dev-floor@v0') ??
        false);
    expect(cleared, isNotEmpty,
        reason: 'not one gate carries the policy card stamp — the pump either '
            'never ran or cleared nothing, and a human would have had to click');
    for (final s in cleared) {
      expect(s['approved_by'], contains('['),
          reason: 'a policy clearance with no evidence bracket cannot be '
              'audited: ${s['approved_by']}');
    }
  }, timeout: const Timeout(Duration(minutes: 30)));

  test('GATE 1 — exactly one settle per (board, run)', () async {
    final status = flight.rawStatus();
    flight.log('run id: ${status['run_id']}  last_run: ${status['last_run']}');

    final runs = (flight.ingest({
      'op': 'runs_for_board',
      'tenant_id': flight.groupId,
      'board_id': flight.boardId,
    }) as List)
        .cast<Map<String, dynamic>>();
    flight.log('materialised runs: ${jsonEncode(runs)}');

    // One ingested master ⇒ one materialised run row. A second row for the
    // same asset is the double-settle this gate exists to catch.
    final perAsset = <String, int>{};
    for (final r in runs) {
      perAsset.update(r['asset_hash'] as String, (n) => n + 1,
          ifAbsent: () => 1);
    }
    for (final entry in perAsset.entries) {
      expect(entry.value, 1,
          reason: 'asset ${entry.key} settled ${entry.value} times on this '
              'board — the metering rail would bill the walk twice');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('GATE 2 — every failure is on the ledger as an incident, deduped, and '
      'nothing is invented', () async {
    final status = flight.rawStatus();
    final failed = Flight.stepsOf(status)
        .where((s) => s['status'] == 'failed')
        .toList();
    final incidents = flight.entriesOfKind('incident');
    flight.log('failed steps: ${failed.map((s) => '${s['step_id']}: '
        '${s['error']}').toList()}');
    flight.log('incidents: ${incidents.map((e) => e['intent']).toList()}');

    // Dedupe is the load-bearing half: `source_ref` is
    // `autopilot:<run>:<step>` and the pump ticks every few seconds, so an
    // un-deduped writeback would have written hundreds of rows.
    final refs = incidents.map((e) => e['source_ref']).toList();
    expect(refs.toSet().length, refs.length,
        reason: 'the incident rail wrote the same source_ref twice: $refs');

    // "No step is failed RIGHT NOW" is not "nothing failed": the upload step's
    // pre-approval `needs_human` park IS a failure, and its incident is a
    // historical fact that correctly outlives the release. So the anti-
    // fabrication test is not "zero failures ⇒ zero incidents" (which was my
    // own wrong model of the rail, and which this suite caught) — it is that
    // every incident names a REAL step of THIS board's run. A fabricated row
    // would name a step or a run that does not exist.
    final stepIds =
        Flight.stepsOf(status).map((s) => '${s['step_id']}').toSet();
    for (final e in incidents) {
      expect(e['params']['error'], isNotNull);
      expect(e['state'], 'approved',
          reason: 'an incident is a FACT record, not a proposal');
      expect(stepIds, contains('${e['params']['step_id']}'),
          reason: 'an incident names a step this board does not have: '
              '${e['params']['step_id']} — that row was invented');
      expect('${e['source_ref']}',
          'autopilot:${e['params']['run_id']}:${e['params']['step_id']}',
          reason: 'the dedupe key and the row disagree, so the dedupe cannot '
              'be doing what it claims');
    }
    for (final f in failed) {
      expect(
          incidents.any((e) => e['params']['step_id'] == f['step_id']), isTrue,
          reason: 'step ${f['step_id']} is sitting FAILED and the ledger '
              'records none of it — the next run would rediscover the same '
              'wall (${f['error']})');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('AUTO-1 held: the COLOR op is still proposed, and no LUT was invented',
      () async {
    final color = flight
        .entriesOfKind('op')
        .where((e) => e['op'] == 'color')
        .toList();
    expect(color, hasLength(1));
    expect(color.single['state'], 'proposed',
        reason: 'the policy door CONFIRMED a color op. §8 is explicit: the '
            'captured grade\'s proposal is scored, not auto-approved, until '
            'the color class is EARNED. This is the invariant the whole '
            'autopilot design rests on.');
    expect(color.single['approved_by'], isNull);

    // …and the grade step therefore never got a cube out of thin air.
    final grade = flight
        .bindReports()
        .firstWhere((b) => b.tool == 'apply_look');
    final cube = grade.args?['cube'];
    expect(cube == null || (cube as String).isEmpty, isTrue,
        reason: 'a cube arrived on the grade step with no confirmed color op '
            'behind it — that is fabrication: $cube');
    flight.log('grade step args=${grade.args} pending=${grade.pending}');

    // The ae ops, by contrast, ARE on the card — so the door should have
    // confirmed them, and their approver must name the policy, not a human.
    for (final e in flight.entriesOfKind('op').where(
        (e) => (e['op'] as String).startsWith('ae.'))) {
      flight.log('ae op ${e['op']}: state=${e['state']} by=${e['approved_by']}');
      if (e['state'] == 'approved') {
        expect(e['approved_by'], startsWith('policy:'),
            reason: 'an ae op approved by something other than the policy card '
                'means an agent approved its own proposal');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  // ── THE TAIL (2026-08-08, Rick's mandate: the full colour back-and-forth) ──
  // AUTO-1 held above: the colour op sat PROPOSED and no cube was invented.
  // Now the missing actor arrives — a COLORIST. The human confirm rides the
  // same shipping set_state door the player rides; the pump then owns the
  // rest: the LUT renders from the CONFIRMED op, the grade gate releases
  // once (mention on the card), and LIVE DaVinci Resolve applies the cube.
  // The invariant under test: the HUMAN approves the colour; the POLICY
  // clears the gate — two different doors, two different stamps, and the
  // ledger keeps them apart.
  test('the COLORIST confirms — the LUT renders and LIVE Resolve applies it',
      () async {
    final color = flight
        .entriesOfKind('op')
        .where((e) => e['op'] == 'color')
        .toList();
    expect(color, hasLength(1), reason: 'the AUTO-1 rung pinned exactly one');
    final entryId = '${color.single['id']}';

    final confirmed =
        flight.setEntryState(entryId, 'approved', by: 'colorist:rick');
    expect(confirmed, isNotNull, reason: 'the set_state door refused');
    final after = flight
        .entriesOfKind('op')
        .firstWhere((e) => '${e['id']}' == entryId);
    expect(after['state'], 'approved');
    expect('${after['approved_by']}', contains('colorist'),
        reason: 'a HUMAN approved the colour — the ledger must name them, '
            'never a policy card (AUTO-1 is about who may not, not who may)');

    await flight.resumeRun();
    final status = await flight.flyUntilSettled(
      limit: const Duration(minutes: 10),
      stillFor: const Duration(seconds: 90),
    );
    final steps = Flight.stepsOf(status);
    final grade =
        steps.firstWhere((s) => s['step_id'] == 'grade_the_cut');
    flight.log('grade tail: status=${grade['status']} '
        'by=${grade['approved_by']} err=${grade['error']}');

    // The gate clearance is the POLICY's (mention on the card) — the human
    // stamp stays on the ledger op, the policy stamp on the step.
    expect(grade['status'], 'human_approved',
        reason: 'with the colour op confirmed and Resolve LIVE, the grade '
            'step must walk: not ${grade['status']} (${grade['error']})');
    expect('${grade['approved_by']}', startsWith('policy:'),
        reason: 'the step gate is the policy door\'s clearance');

    // And the cube is REAL: the fill composes at DISPATCH (the compile-time
    // bind stamp never learns it — run-11 taught that), so the proof surface
    // is the step's own dispatch result: Resolve's structured reply carries
    // applied:true and the lut it mounted.
    final gradeResult = '${grade['ai_result'] ?? ''}';
    expect(gradeResult, contains('"applied":true'),
        reason: 'Resolve did not report an applied grade: '
            '${gradeResult.substring(0, gradeResult.length.clamp(0, 300))}');
    final lutMatch =
        RegExp(r'"lut"\s*:\s*"([^"]+)"').firstMatch(gradeResult);
    expect(lutMatch, isNotNull,
        reason: 'no lut named in the apply_look result');

    // The artifact row itself: a color-lane entry now carries lut_ref — the
    // content-addressed render the conform lane will reuse.
    final lutRows = flight.entriesOfKind('op').where((e) =>
        e['op'] == 'color' &&
        (e['params']?['lut_ref'] ?? '') != '');
    expect(lutRows, isNotEmpty,
        reason: 'the confirmed look rendered no lut_ref artifact row');
  }, timeout: const Timeout(Duration(minutes: 12)));
}
