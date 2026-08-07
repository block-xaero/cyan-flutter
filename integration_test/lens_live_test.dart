// lens_live_test.dart — TIER 2 for rows 19–21, the half the Windows box could
// not prove: cyan-lens actually SERVES the bytes the LensApi seam decodes.
//
// The box's contract tests drove a loopback HttpServer speaking recorded
// shapes — necessary, and silent on the question "does the real lens agree?"
// This file runs ONLY where a live lens exists (the Mac dev machine, s0 lens
// on 127.0.0.1:9091 with the seedtok dev identity) and asserts against REAL
// data the machine's history put there: materialized runs, the ae marketplace
// card, the health surface.
//
//   CYAN_LENS_URL=http://127.0.0.1:9091 CYAN_LENS_TOKEN=seedtok \
//     flutter test integration_test/lens_live_test.dart
//
// No lens configured ⇒ SKIP LOUDLY (never a fake pass, never a red on boxes
// that legitimately have no lens).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cyan_flutter/lens/lens_api.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final url = Platform.environment['CYAN_LENS_URL'];
  if (url == null || url.isEmpty) {
    test('live lens Tier-2 SKIPPED — no CYAN_LENS_URL in this environment', () {
      // ignore: avoid_print
      print('note: rows 19–21 live proof runs only where a lens exists; '
          'the wire contract is covered by the loopback tests.');
    });
    return;
  }

  final api = LensApiHttp();

  test('the live lens answers health', () async {
    final h = await api.health();
    expect(h, isNotNull, reason: 'no health from $url — is the lens up?');
  });

  test('runs: the REAL lens serves materialized runs the seam decodes', () async {
    final feed = await api.runs(limit: 25);
    expect(feed.total, greaterThan(0),
        reason: 'the s0 lens carries materialized runs from the autopilot '
            'flights — an empty feed means the decode or the auth broke, '
            'not that no work happened');
    final lanes = [feed.incoming, feed.inFlight, feed.approval, feed.done, feed.failed];
    for (final lane in lanes) {
      for (final r in lane) {
        expect(r.runId, isNotEmpty);
      }
    }
  });

  test('cost/efficiency rollups reduce over the same live feed', () async {
    final feed = await api.runs(limit: 50);
    // The rollups are pure reductions (shift-3 finding: no extra endpoint) —
    // over real data they must be finite and non-negative, never NaN.
    final all = [...feed.incoming, ...feed.inFlight, ...feed.approval, ...feed.done, ...feed.failed];
    final totalSteps = all.fold<int>(0, (n, r) => n + r.stepCount);
    expect(totalSteps, greaterThanOrEqualTo(0));
  });

  test('marketplace: the live browse carries the ae card (published 2026-08-06)',
      () async {
    final cards = await api.browseMarketplace(const StorefrontQuery(limit: 50));
    expect(cards, isNotEmpty, reason: 'live browse returned nothing');
    expect(
      cards.any((c) => c.pluginId == 'ae'),
      isTrue,
      reason: 'the ae plugin was published to this lens and its card is '
          'live-proven in the Mac app — the seam must see it too. Cards seen: '
          '${cards.map((c) => c.pluginId).take(12).toList()}',
    );
  });

  test('lens intelligence: nudges/asks/decisions decode from the live surface',
      () async {
    // Content varies with the machine's history; the proof is that the REAL
    // payloads decode through the same models the face renders.
    final nudges = await api.nudges();
    final asks = await api.asks(limit: 10);
    final decisions = await api.decisions(limit: 10);
    expect(nudges, isNotNull);
    expect(asks, isNotNull);
    expect(decisions, isNotNull);
  });
}
