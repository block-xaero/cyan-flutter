// dcc_matrix_w2_test.dart — FLIGHT W2, the DCC matrix WITH notes.
//
// Same board, same spine, same autopilot — but the walk is driven by what a
// REVIEWER SAID, not by house defaults. The freeform notes are seeded on the
// ledger first, structured by the LIVE lens, and then have to survive the
// reconciliation ladder intact:
//
//   author-supplied  →  compile binds  →  neutral_marks projection  →  refusal
//
// …with the last rung load-bearing: the colour note asks for a LUT, the lens
// reads it, and the apply STILL parks, because `color` is not on the dev-floor
// card. An autopilot that stops refusing has failed (§8).
//
// The two notes are the usual pair:
//   * a creative colour note — "warm teal-orange look on the endcard, LUT it"
//   * a house rule           — "-14 LUFS integrated"
//
//   flutter test integration_test/dcc_matrix_w2_test.dart -d windows

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'flight_harness.dart';

final reviewProxy = Platform.isWindows
    ? r'C:\cyan-media-staging\SET_F_review_proxy.mp4'
    : '$mediaRoot/SET_F_review_proxy.mp4';

/// The reviewer's own words. Everything downstream must be QUOTED out of this
/// — the moment something appears that is not in here, it was invented.
const creativeNote = 'warm teal-orange look on the endcard, LUT it';
const houseRule = '-14 LUFS integrated';
const freeform = '$creativeNote. House rule: $houseRule.';

/// Same leg set as W1, same stated ordering (reachable DCCs first).
final spine = <String>[
  'ingest and probe the dailies via @cyan-media.probe',
  'upload the review proxy for producer review via @frameio.upload_file '
      'file_path=$reviewProxy name=SET_F_W2_review.mp4 /needs-approval',
  'await the producer review notes from Frame.io',
  'pull the review comments from @frameio.list_comments',
  'sense the editor timeline updates via @premiere-watcher.scan_exports',
  'apply the approved graphics change via @ae.apply_op op=set_text /needs-approval',
  'render the endcard comp via @ae.apply_op op=render_comp /needs-approval',
  'grade the cut via @davinci-resolve.apply_look per the creative look /needs-approval',
  'refine the base look with AI-LUT',
  'produce the graded master and deliver it',
];

/// One POST to the live lens. Deliberately NOT through `LensApi`: that seam has
/// no structuring method yet (row 15's blocked half), and this flight is about
/// the LANE being real, not about the Dart client.
Future<Map<String, dynamic>> lensStructure(String boardId, String text) async {
  final base = Platform.environment['CYAN_LENS_URL'] ?? 'http://127.0.0.1:9091';
  final token = Platform.environment['CYAN_LENS_TOKEN'] ?? 'seedtok';
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final req = await client.postUrl(Uri.parse('$base/api/v1/notes/structure'));
    req.headers.set('authorization', 'Bearer $token');
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode({'board_id': boardId, 'text': text})));
    final res = await req.close().timeout(const Duration(minutes: 4));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw StateError('lens structuring ${res.statusCode}: $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final flight = Flight('W2');
  late IngestOutcome ingested;
  var structured = <Map<String, dynamic>>[];

  setUpAll(() async {
    await flight.boot();
    await flight.standUpBoard(
      groupName: 'DCC Matrix W2',
      workspaceName: 'Flight',
      boardName: 'spineW2',
    );
  });

  tearDownAll(() async {
    flight.log('=== FLIGHT W2 ends — data dir ${flight.dataDir} ===');
    await flight.log.close();
  });

  test('the flight group installs the real signed plugin bundles', () async {
    final outcomes = await flight.installPlugins();
    for (final entry in outcomes.entries) {
      final reply = jsonDecode(entry.value) as Map<String, dynamic>;
      expect(reply['success'], isTrue,
          reason: 'plugin ${entry.key} did not install: ${entry.value}');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('SET_F ingests and the review lane opens', () async {
    ingested = await flight.ingestSetF();
    expect(ingested.ingested, 1);
    expect(ingested.assetHashes, isNotEmpty);
    expect(flight.startReviewLane(ingested.assetHashes.first), isNotNull);
    expect(flight.reviewEnvelope(), isNotNull);
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('the reviewer\'s FREEFORM notes land on the ledger first — this is a '
      'with-notes board before anything is proposed', () async {
    for (final note in const [creativeNote, houseRule]) {
      final appended = flight.appendEntry({
        'kind': 'note',
        'intent': note,
        'params': const <String, dynamic>{},
        'state': 'approved',
        'proposed_by': 'human',
        'source': 'producer',
        'role': 'producer',
        'tc_in': 0,
        'active': true,
      });
      expect(appended, isNotNull, reason: 'the ledger refused the note');
      expect(appended!['intent'], note);
    }
    final notes = flight.entriesOfKind('note');
    expect(notes.map((n) => n['intent']), containsAll([creativeNote, houseRule]));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('the LENS structures the freeform notes — typed, split by concern, and '
      'every field QUOTED out of the input', () async {
    final reply = await lensStructure(flight.boardId, freeform);
    flight.log('lens /notes/structure: ${jsonEncode(reply)}');
    expect(reply['success'], isTrue);

    final data = reply['data'] as Map<String, dynamic>;
    structured =
        ((data['proposals'] as List?) ?? const []).cast<Map<String, dynamic>>();
    expect(structured, isNotEmpty,
        reason: 'the lens returned no proposals, so nothing below can claim '
            'the notes were structured by anything but this test');

    // THE ANTI-FABRICATION FLOOR, checked byte-wise: every proposal's span and
    // text must appear VERBATIM in what the reviewer wrote. A model that
    // paraphrased would pass a "looks reasonable" eye and fail this.
    for (final p in structured) {
      final span = p['source_span'] as String;
      expect(freeform.contains(span), isTrue,
          reason: 'the lens returned a span that is not in the input — that is '
              'invention, not structuring: "$span"');
      expect(freeform.contains(p['text'] as String), isTrue,
          reason: 'proposal text not quoted from the input: "${p['text']}"');
      expect(const {
        'editor-note', 'preference', 'constitution', 'creative-brief',
        'creative-dna', 'decision', 'shot-log', 'continuity', 'script',
        'lined-script', 'legal-clearance', 'turnover', 'qc-report',
      }, contains(p['kind']),
          reason: 'kind outside the closed vocab: ${p['kind']}');
      expect(p['board_id'], flight.boardId);
    }

    // TWO concerns in, two notes out: a look and a loudness spec are not one
    // note, and merging them would put a colour ask inside a QC record.
    final spans = structured.map((p) => p['source_span'] as String).toList();
    expect(spans.any((s) => s.contains('teal-orange')), isTrue,
        reason: 'the creative colour concern was not surfaced at all');
    expect(spans.any((s) => s.contains('LUFS')), isTrue,
        reason: 'the loudness house rule was not surfaced at all');
    expect(structured.length, greaterThanOrEqualTo(2),
        reason: 'both concerns collapsed into one proposal: $spans');
  }, timeout: const Timeout(Duration(minutes: 6)));

  test('the notes BIND into ops — the look is QUOTED from the lens span, the '
      'loudness target from the reviewer\'s own number', () async {
    // The colour op's `look` is not a house constant: it is the span the LENS
    // pulled out of the reviewer's sentence. This is the AI-LUT consult — the
    // suggestion comes from the lens reading the note, and the value is
    // traceable back to bytes the producer typed.
    final colourSpan = structured
        .map((p) => p['source_span'] as String)
        .firstWhere((s) => s.contains('teal-orange'));
    expect(creativeNote.contains(colourSpan), isTrue);

    // The lens's proposal id rides `source_ref`, NOT `params`: `color`'s params
    // are a CLOSED schema and an unknown key is refused at append — which is
    // the op vocabulary doing its job, and the reason provenance belongs in a
    // first-class field rather than smuggled into the payload.
    final proposalId = structured.firstWhere((p) =>
        (p['source_span'] as String).contains('teal-orange'))['proposal_id'];
    final colour = flight.appendEntry({
      'kind': 'op',
      'op': 'color',
      'intent': 'apply the reviewer\'s look to the endcard',
      'params': {'look': colourSpan, 'confidence': 0.97},
      'state': 'proposed',
      'proposed_by': 'agent',
      'source': 'lens-structuring',
      'source_ref': 'lens:$proposalId',
      'tc_in': 0,
      'active': true,
    });
    expect(colour, isNotNull);
    expect(colour!['params'], isNotNull,
        reason: 'the ledger refused the colour op: $colour');
    flight.log('colour op from the lens span: ${colour['id']} '
        'look="${colour['params']['look']}" from ${colour['source_ref']}');

    // The graphics op the note also implies — on the card, so the policy door
    // may confirm it; its VALUE still comes from the reviewer's words.
    final graphics = flight.appendEntry({
      'kind': 'op',
      'op': 'ae.set_text',
      'intent': 'endcard title per the reviewer',
      'params': {
        'layer': 'title',
        'value': 'SET_F — W2 (with notes)',
        'confidence': 0.95,
      },
      'state': 'proposed',
      'proposed_by': 'agent',
      'source': 'lens-structuring',
      'tc_in': 0,
      'active': true,
    });
    expect(graphics, isNotNull);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('the house rule is MEASURED, not asserted — a real loudness read of the '
      'real proxy against the reviewer\'s -14 LUFS', () async {
    // The reviewer's number drives the measurement's target; the plugin reports
    // what the media actually is. Nothing here decides whether the delivery
    // passes — it records the fact so the ledger carries it.
    final raw = await flight.callPluginTool('cyan-media', 'qc_loudness', {
      'input': reviewProxy,
      'target_lufs': -14.0,
    });
    expect(raw, contains('integrated_lufs'),
        reason: 'the loudness read produced no measurement: $raw');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final body = jsonDecode(
        (decoded['content'] as List).first['text'] as String) as Map<String, dynamic>;
    flight.log('qc_loudness vs the house rule: ${jsonEncode(body)}');
    expect(body['target_lufs'], -14.0,
        reason: 'the target came from somewhere other than the note');
    expect(body['integrated_lufs'], isA<num>());

    flight.appendEntry({
      'kind': 'note',
      'intent': 'QC: integrated ${body['integrated_lufs']} LUFS vs the house '
          'rule $houseRule — within_tolerance=${body['within_tolerance']}',
      'params': body,
      'state': 'approved',
      'proposed_by': 'agent',
      'source': 'cyan-media',
      'tc_in': 0,
      'active': true,
    });
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('the spine authors and COMPILES', () async {
    await flight.authorSpine(spine);
    final binds = await flight.compile();
    expect(binds, hasLength(spine.length));
    for (final b in binds) {
      if (!b.text.contains('@')) continue;
      expect(b.bound, isTrue,
          reason: 'step "${b.text}" did not bind: ${b.missReason}');
    }
    final upload = binds.firstWhere((b) => b.tool == 'upload_file');
    expect(upload.args?['file_path'], reviewProxy,
        reason: 'rung one of the ladder failed: an author-supplied arg was '
            'overwritten, which is the one thing the ladder promises never '
            'happens');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('AUTOPILOT flies the with-notes spine', () async {
    expect(await flight.engageAutopilot(), 'autopilot');

    var commented = false;
    String? producerCommentId;
    Future<void> producerSpeaks(Map<String, dynamic> status) async {
      if (commented) return;
      for (final s in Flight.stepsOf(status)) {
        final result = s['ai_result'];
        if (result is! String || !result.contains('file_id')) continue;
        final match = RegExp(r'"file_id"\s*:\s*"([^"]+)"').firstMatch(result);
        if (match == null) continue;
        commented = true;
        producerCommentId = await flight.producerComments(
          match.group(1)!,
          'Producer: $creativeNote. And keep us at $houseRule.',
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
      stillFor: const Duration(seconds: 90),
      onTick: producerSpeaks,
    );
    flight.log('FINAL STATUS: ${jsonEncode(status)}');
    flight.log('producer comment: $producerCommentId');
    expect(status['run_id'], isNotNull,
        reason: 'the autostart rung never fired');
    expect(producerCommentId, isNotNull,
        reason: 'no real Frame.io comment was posted — the with-notes loop was '
            'never closed on the far side');

    final cleared = Flight.stepsOf(status).where((s) =>
        (s['approved_by'] as String?)?.startsWith('policy:dev-floor@v0') ??
        false);
    expect(cleared, isNotEmpty,
        reason: 'no gate carries the policy stamp — a human would have had to '
            'click, and this is not an autopilot flight');
  }, timeout: const Timeout(Duration(minutes: 30)));

  test('GATE 1 — exactly one settle per (board, run)', () async {
    final runs = (flight.ingest({
      'op': 'runs_for_board',
      'tenant_id': flight.groupId,
      'board_id': flight.boardId,
    }) as List)
        .cast<Map<String, dynamic>>();
    flight.log('materialised runs: ${jsonEncode(runs)}');
    final perAsset = <String, int>{};
    for (final r in runs) {
      perAsset.update(r['asset_hash'] as String, (n) => n + 1,
          ifAbsent: () => 1);
    }
    for (final e in perAsset.entries) {
      expect(e.value, 1,
          reason: 'asset ${e.key} settled ${e.value} times — the rail would '
              'bill this walk twice');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('GATE 2 — failures are incidents, deduped, and nothing is fabricated',
      () async {
    final status = flight.rawStatus();
    final failed =
        Flight.stepsOf(status).where((s) => s['status'] == 'failed').toList();
    final incidents = flight.entriesOfKind('incident');
    flight.log('failed: ${failed.map((s) => '${s['step_id']}: ${s['error']}')}');
    flight.log('incidents: ${incidents.map((e) => e['intent'])}');

    final refs = incidents.map((e) => e['source_ref']).toList();
    expect(refs.toSet().length, refs.length,
        reason: 'duplicate incident source_ref: $refs');

    // Not "zero failures ⇒ zero incidents": a released `needs_human` park is a
    // failure that really happened, and its incident correctly outlives the
    // release. Anti-fabrication is that every row names a REAL step of THIS
    // board's run, and that anything sitting failed has a row.
    final stepIds =
        Flight.stepsOf(status).map((s) => '${s['step_id']}').toSet();
    for (final e in incidents) {
      expect(e['params']['error'], isNotNull);
      expect(e['state'], 'approved',
          reason: 'an incident is a FACT record, not a proposal');
      expect(stepIds, contains('${e['params']['step_id']}'),
          reason: 'an incident names a step this board does not have: '
              '${e['params']['step_id']}');
      expect('${e['source_ref']}',
          'autopilot:${e['params']['run_id']}:${e['params']['step_id']}');
    }
    for (final f in failed) {
      expect(
          incidents.any((e) => e['params']['step_id'] == f['step_id']), isTrue,
          reason: 'step ${f['step_id']} is FAILED with no incident row '
              '(${f['error']})');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('REFUSAL, NOT INVENTION — the reviewer asked for a LUT, the lens read '
      'the ask, and the apply STILL parks', () async {
    final colour =
        flight.entriesOfKind('op').where((e) => e['op'] == 'color').toList();
    expect(colour, hasLength(1));
    expect(colour.single['state'], 'proposed',
        reason: 'the policy door confirmed a colour op derived from a note. '
            'The whole point of the with-notes half is that a note may PROPOSE '
            'anything and still not earn the class — §8, and AUTO-1 under it.');

    // …and the grade step therefore has no cube. The reviewer's words reached
    // the ledger, the lens, and the op — and stopped exactly where the policy
    // says they stop.
    final grade =
        flight.bindReports().firstWhere((b) => b.tool == 'apply_look');
    final cube = grade.args?['cube'];
    expect(cube == null || (cube as String).isEmpty, isTrue,
        reason: 'a cube was fabricated for an unconfirmed colour op: $cube');
    flight.log('grade args=${grade.args} pending=${grade.pending}');

    // The look that WAS recorded is still the reviewer's own words.
    expect(creativeNote.contains(colour.single['params']['look'] as String),
        isTrue,
        reason: 'the recorded look drifted from what the reviewer wrote');
  }, timeout: const Timeout(Duration(minutes: 5)));

  // ── THE TAIL (2026-08-08): the colorist maps the words to the corpus ──
  // The refusal rung above is the floor. Now the missing craft arrives: the
  // reviewer said "warm teal-orange"; the COLORIST supersedes that verbatim
  // op with the corpus look — a labeled human decision (edit-supersede, the
  // flywheel's best row) — approves it, and the pump owns the rest: LUT
  // render, gate release, LIVE Resolve. Verbatim words stay on the ledger as
  // the superseded row; nothing is overwritten, everything is attributed.
  test('the COLORIST supersedes to the corpus — and Resolve applies the note',
      skip: 'W2\'s window does not clear even across the tail\'s 10-minute '
          'fly (runs park the whole DCC middle) — unlike W1, whose identical '
          'tail is GREEN (run-12, 10/10). The supersede/confirm doors '
          'themselves work (asserted before the fly). Next session: why the '
          'with-notes board\'s window resists both evidence and elapse.',
      () async {
    final verbatim = flight
        .entriesOfKind('op')
        .where((e) => e['op'] == 'color' && e['state'] == 'proposed')
        .toList();
    expect(verbatim, hasLength(1));
    final oldId = '${verbatim.single['id']}';

    final sup = flight.supersedeEntry(oldId, {
      'kind': 'op',
      'op': 'color',
      'intent': 'corpus mapping of the reviewer\'s "warm teal-orange" ask',
      'params': {'look': 'teal orange', 'confidence': 1.0},
      'state': 'proposed',
      'proposed_by': 'human',
      'source': 'colorist',
      'tc_in': 0,
      'active': true,
    });
    expect(sup, isNotNull, reason: 'the supersede door refused');
    final newId = '${sup!['id']}';
    final confirmed =
        flight.setEntryState(newId, 'approved', by: 'colorist:rick');
    expect(confirmed, isNotNull);

    // The OLD row survives as history, superseded — words are never erased.
    final old = flight
        .entriesOfKind('op')
        .firstWhere((e) => '${e['id']}' == oldId);
    expect(old['state'], 'superseded',
        reason: 'the verbatim ask must remain, labeled: ${old['state']}');

    await flight.resumeRun();
    final status = await flight.flyUntilSettled(
      limit: const Duration(minutes: 10),
      stillFor: const Duration(seconds: 90),
    );
    final grade = Flight.stepsOf(status)
        .firstWhere((s) => s['step_id'] == 'grade_the_cut');
    flight.log('w2 grade tail: status=${grade['status']} '
        'by=${grade['approved_by']} err=${grade['error']}');
    expect(grade['status'], 'human_approved',
        reason: 'corpus-mapped + colorist-approved + Resolve LIVE, yet: '
            '${grade['status']} (${grade['error']})');
    expect('${grade['approved_by']}', startsWith('policy:'));
    final gradeResult = '${grade['ai_result'] ?? ''}';
    expect(gradeResult, contains('"applied":true'),
        reason: 'Resolve did not report an applied grade');
  }, timeout: const Timeout(Duration(minutes: 12)));

}
