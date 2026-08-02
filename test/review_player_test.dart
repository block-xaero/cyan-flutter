// test/review_player_test.dart
//
// PARITY face `review_player` — THE POST-PRODUCTION SURFACE (Swift:
// ReviewPlayerView + ReviewPlayerViewModel, RegionComposerView +
// RegionComposerViewModel, RegionDrawingOverlay, VideoPlayerFace, ScrubberView).
//
// Tier-1: every assertion is driven through the `CyanBackend` seam
// (FakeCyanBackend) and the `ReviewVideoSurface` seam (FakeReviewVideoSurface).
// No dylib, no decoder.
//
// The twelve behaviours in scripts/parity_faces/review_player.txt:
//   • the review player renders a bound video asset and reports playback state
//   • a right drag on the frame draws a region and the region persists
//   • typing an ask against a drawn region proposes a region scoped op
//   • a mechanical note surfaces approve edit and reject actions
//   • approving a proposed op records it on the changelist
//   • a creative note stays a note and is never promoted to an op
//   • flipping between versions checks out playable media for each
//   • produce master is offered once a run has a delivered asset
//   • the composer asks the agent on every entry not only on colour
//   • the version selector plays a preview when the master is undecodable
//   • the version head can be undone and redone
//   • a fast first click loads the ledger then steps rather than no opping

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/models/review_entry.dart';
import 'package:cyan_flutter/providers/review_player_controller.dart';
import 'package:cyan_flutter/widgets/parity/parity_review_player.dart';

import 'support/fake_review_surface.dart';
import 'support/parity_test_harness.dart';

/// The player face wide enough that the hero, the transport and the rail all
/// lay out — the rail is a column OF the face, not a screen of its own.
const Size _face = Size(1100, 760);

/// The flagship board: the only one the fixture has ingested media for, and the
/// one whose review lane has already been through a round.
const String _board = 'b-eng-1';

/// A board with no ingested media and no review lane — the fixture's normal
/// case, and the face's calm state.
const String _bareBoard = 'b-eng-2';

const String _proxy =
    '/Users/cyan/Movies/cyan-media/derived/reel-01_r1_proxy.mp4';

// ---------------------------------------------------------------------------

Future<FakeReviewVideoSurface> pumpPlayer(
  WidgetTester tester,
  FakeCyanBackend backend, {
  String board = _board,
}) async {
  final surface = FakeReviewVideoSurface();
  await pumpParity(
    tester,
    ParityReviewPlayerView(boardId: board, surface: surface),
    backend: backend,
    size: _face,
  );
  return surface;
}

/// The board's lane, read back off the seam — the ledger, not the widget's copy.
Future<List<Map<String, dynamic>>> lane(FakeCyanBackend backend,
    {String board = _board}) async {
  final reply =
      await backend.changelistCommand({'op': 'list', 'board_id': board});
  return [
    for (final e in (reply.fields['entries'] as List? ?? const []))
      if (e is Map<String, dynamic>) e,
  ];
}

/// A point inside the hero, at (fx, fy) of its own rect — so a drag is written
/// against the picture rather than against a window size.
Offset heroAt(WidgetTester tester, double fx, double fy) {
  final rect = tester.getRect(find.byKey(const ValueKey('review.hero')));
  return Offset(rect.left + rect.width * fx, rect.top + rect.height * fy);
}

/// Drag with the SECONDARY button across the hero — the region gesture.
Future<void> rightDrag(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await tester.startGesture(from, buttons: kSecondaryButton);
  await tester.pump();
  await gesture.moveTo(Offset(from.dx + (to.dx - from.dx) / 2,
      from.dy + (to.dy - from.dy) / 2));
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Draw a region and send [ask] against it, exactly as a reviewer does.
Future<void> askAgainstRegion(WidgetTester tester, String ask) async {
  await rightDrag(
      tester, heroAt(tester, 0.25, 0.25), heroAt(tester, 0.6, 0.7));
  await tester.enterText(
      find.byKey(const ValueKey('review.composer.field')), ask);
  await tester.tap(find.byKey(const ValueKey('review.composer.send')));
  await tester.pumpAndSettle();
}

Finder keyStartingWith(String prefix) => find.byWidgetPredicate((w) {
      final key = w.key;
      return key is ValueKey<String> && key.value.startsWith(prefix);
    });

void main() {
  testWidgets('the review player renders a bound video asset and reports '
      'playback state', (tester) async {
    final backend = FakeCyanBackend();
    final surface = await pumpPlayer(tester, backend);

    // The hero mounts what the ENGINE resolved for this board — the newest
    // conformed proxy, not whatever the face was opened with.
    final media = await backend.boardVideoMedia(_board);
    expect(media.proxyPath, _proxy);
    expect(surface.mountedPath, _proxy);
    expect(find.byKey(const ValueKey('review.hero')), findsOneWidget);
    expect(find.byKey(const ValueKey('review.fake.picture')), findsOneWidget);

    // …and it says what the transport is doing. Paused is the honest opening
    // state: nothing was asked to play.
    expect(find.text('Paused'), findsOneWidget);
    expect(find.byKey(const ValueKey('review.timecode')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('review.playPause')));
    await tester.pumpAndSettle();
    expect(surface.isPlaying, isTrue);
    expect(find.text('Playing'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('review.playPause')));
    await tester.pumpAndSettle();
    expect(surface.isPlaying, isFalse);
    expect(find.text('Paused'), findsOneWidget);

    // The playhead is the surface's, and the timecode reads it.
    surface.seek(48);
    await tester.pumpAndSettle();
    expect(find.text(smpteLabel(48, 24)), findsOneWidget);
  });

  testWidgets('a right drag on the frame draws a region and the region persists',
      (tester) async {
    final backend = FakeCyanBackend();
    final surface = await pumpPlayer(tester, backend);
    surface.seek(120);
    await tester.pumpAndSettle();

    await rightDrag(
        tester, heroAt(tester, 0.25, 0.25), heroAt(tester, 0.6, 0.7));

    // The drag seeded a region and opened the composer on the PRESS frame.
    expect(find.byKey(const ValueKey('review.region.draft')), findsOneWidget);
    expect(find.byKey(const ValueKey('review.composer')), findsOneWidget);
    expect(find.text('rect @ ${smpteLabel(120, 24)}'), findsOneWidget);

    // Scrubbing away does not erase it: the draft is the only record of the
    // selection, so it stays visible (dimmed) for the whole life of the
    // composer.
    surface.seek(160);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review.region.draft')), findsOneWidget);

    // And once sent, the region is ON THE LEDGER and is redrawn at the frame it
    // was drawn on — a tracker seed, exact at its key frame.
    await tester.enterText(find.byKey(const ValueKey('review.composer.field')),
        'this corner is distracting');
    await tester.tap(find.byKey(const ValueKey('review.composer.send')));
    await tester.pumpAndSettle();

    final rows = await lane(backend);
    final captured = rows.firstWhere((e) => e['region'] != null);
    final region = captured['region'] as Map<String, dynamic>;
    expect(region['key_frame'], 120, reason: 'the press frame, not the release');
    expect((region['shape'] as Map)['type'], 'rect');
    expect(region['raster_ref'], isNotNull);

    surface.seek(120);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('review.region.${captured['id']}')),
        findsOneWidget);
  });

  testWidgets('typing an ask against a drawn region proposes a region scoped op',
      (tester) async {
    final backend = FakeCyanBackend();
    final surface = await pumpPlayer(tester, backend);
    surface.seek(96);
    await tester.pumpAndSettle();

    // "warm punchy" is a name in the ENGINE's look corpus, so it is not prose
    // about the picture — it is an instruction to change it.
    await askAgainstRegion(tester, 'warm punchy');

    final rows = await lane(backend);
    final proposed = rows.firstWhere((e) => e['region'] != null);
    expect(proposed['kind'], 'op');
    expect(proposed['op'], 'color');
    expect((proposed['params'] as Map)['look'], 'warm punchy');
    expect(proposed['state'], 'proposed');
    // The op is SCOPED to the region: the shape rides on the same entry.
    expect((proposed['region'] as Map)['key_frame'], 96);
    expect(proposed['ref'], isNotNull);

    // The rail shows it as a region-scoped row.
    expect(find.byKey(ValueKey('review.rail.region.${proposed['id']}')),
        findsOneWidget);
  });

  testWidgets('a mechanical note surfaces approve edit and reject actions',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpPlayer(tester, backend);

    // The seeded agent proposal: mechanical, un-adjudicated, waiting on a
    // human. The player preselects it — it is the card the gate exists for.
    final rows = await lane(backend);
    final mechanical = rows.firstWhere(
        (e) => e['kind'] == 'op' && e['proposed_by'] == 'agent');
    final id = mechanical['id'] as String;

    expect(find.byKey(ValueKey('review.card.$id')), findsOneWidget);
    expect(find.byKey(ValueKey('review.card.approve.$id')), findsOneWidget);
    expect(find.byKey(ValueKey('review.card.edit.$id')), findsOneWidget);
    expect(find.byKey(ValueKey('review.card.reject.$id')), findsOneWidget);
    // A mechanical op is not creative — it never says "your call".
    expect(find.byKey(const ValueKey('review.card.creative')), findsNothing);

    // The EDIT leg opens the inline form rather than deciding behind the human.
    await tester.tap(find.byKey(ValueKey('review.card.edit.$id')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review.edit.tcIn')), findsOneWidget);
    expect(find.byKey(const ValueKey('review.edit.params')), findsOneWidget);
    expect(find.byKey(ValueKey('review.edit.commit.$id')), findsOneWidget);
  });

  testWidgets('approving a proposed op records it on the changelist',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpPlayer(tester, backend);

    final before = await lane(backend);
    final mechanical = before.firstWhere(
        (e) => e['kind'] == 'op' && e['proposed_by'] == 'agent');
    final id = mechanical['id'] as String;
    expect(mechanical['state'], 'proposed');
    expect(mechanical['approved_by'], isNull);

    await tester.tap(find.byKey(ValueKey('review.card.approve.$id')));
    await tester.pumpAndSettle();

    final after = await lane(backend);
    final decided = after.firstWhere((e) => e['id'] == id);
    expect(decided['state'], 'approved');
    expect(decided['approved_by'], isNotNull);
    expect(decided['active'], isTrue);
    // The row is a decision on the record, not a replacement: the ledger is
    // append-only and the entry keeps its identity.
    expect(after.length, before.length);
    expect(decided['entry_hash'], mechanical['entry_hash']);
  });

  testWidgets('confirming an edit supersedes the proposal with the nudge',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpPlayer(tester, backend);

    final before = await lane(backend);
    final mechanical = before.firstWhere(
        (e) => e['kind'] == 'op' && e['proposed_by'] == 'agent');
    final id = mechanical['id'] as String;

    await tester.tap(find.byKey(ValueKey('review.card.edit.$id')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('review.edit.params')), 'db=-3');
    await tester.tap(find.byKey(ValueKey('review.edit.commit.$id')));
    await tester.pumpAndSettle();

    final after = await lane(backend);
    // Entry CONTENT is immutable: the nudge is a NEW row that supersedes the
    // proposal and lands approved — the redo chain, not an overwrite.
    final original = after.firstWhere((e) => e['id'] == id);
    expect(original['state'], 'superseded');
    expect(original['active'], isFalse);
    final confirmed = after.firstWhere((e) => e['supersedes'] == id);
    expect(confirmed['state'], 'approved');
    expect(confirmed['op'], mechanical['op']);
    expect((confirmed['params'] as Map)['db'], -3);
  });

  testWidgets('a creative note stays a note and is never promoted to an op',
      (tester) async {
    final backend = FakeCyanBackend();
    final surface = await pumpPlayer(tester, backend);
    surface.seek(240);
    await tester.pumpAndSettle();

    const prose = 'the mood in this act feels colder than the brief';
    final before = await lane(backend);
    await askAgainstRegion(tester, prose);

    final after = await lane(backend);
    final note = after.firstWhere((e) => e['intent'] == prose);
    expect(note['kind'], 'note');
    expect(note['op'], isNull);
    // The agent was asked and DECLINED — nothing mechanical was invented from
    // creative feedback, so the lane grew by exactly the human's note.
    expect(after.length, before.length + 1);
    expect(after.where((e) => e['proposed_by'] == 'agent' && e['kind'] == 'op'),
        hasLength(1),
        reason: 'only the seeded agent proposal — the prose made no new op');

    // On the card it is "your call": there is no approve/reject gate and no
    // promote button, because promoting is a human's decision and this build
    // binds no verb for it.
    await tester.tap(find.byKey(ValueKey('review.rail.row.${note['id']}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review.card.creative')), findsOneWidget);
    expect(find.byKey(ValueKey('review.card.keep.${note['id']}')),
        findsOneWidget);
    expect(find.byKey(ValueKey('review.card.approve.${note['id']}')),
        findsNothing);
  });

  testWidgets('flipping between versions checks out playable media for each',
      (tester) async {
    final backend = FakeCyanBackend();
    final surface = await pumpPlayer(tester, backend);

    // Two cuts: v1 the source and v2 the round-1 conform. The player follows
    // the newest without being asked.
    expect(find.byKey(const ValueKey('review.version.current')), findsOneWidget);
    expect(find.text('v2'), findsOneWidget);
    expect(surface.mountedPath, _proxy);

    await tester.tap(find.byKey(const ValueKey('review.version.selector')));
    await tester.pumpAndSettle();
    expect(find.text('v1 · round 0 — source'), findsOneWidget);
    expect(find.text('v2 · round 1 — conformed (newest)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review.version.option.v1')));
    await tester.pumpAndSettle();

    final v1Path = surface.mountedPath;
    expect(v1Path, isNotNull);
    expect(v1Path, isNot(_proxy));
    expect(find.text('v1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('review.version.selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('review.version.option.v2')));
    await tester.pumpAndSettle();
    expect(surface.mountedPath, _proxy);

    // Both legs were really checked out — one mount per pick, never a version
    // the face only claimed to have.
    expect(surface.mounted, containsAllInOrder([_proxy, v1Path, _proxy]));
  });

  testWidgets('produce master is offered once a run has a delivered asset',
      (tester) async {
    final bare = FakeCyanBackend();
    await pumpPlayer(tester, bare, board: _bareBoard);
    // No run, no delivered version: the delivery is not offered, and nothing
    // pretends it could be produced.
    expect(find.byKey(const ValueKey('review.produceMaster')), findsNothing);

    final backend = FakeCyanBackend();
    await pumpPlayer(tester, backend);
    expect(find.byKey(const ValueKey('review.produceMaster')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('review.produceMaster')));
    await tester.pumpAndSettle();

    // The ENGINE's own delivery lane produced it — the face reports the path it
    // was given rather than composing one.
    final status = tester.widget<Text>(
        find.byKey(const ValueKey('review.produceMaster.status')));
    expect(status.data, startsWith('master: '));
    expect(status.data, contains('_v2_master.mov'));

    final refused = await bare
        .ingestCommand({'op': 'produce_master', 'board_id': _bareBoard});
    expect(refused.ok, isFalse);
    expect(refused.error, contains('no delivered version'));
  });

  testWidgets('the composer asks the agent on every entry not only on colour',
      (tester) async {
    final backend = FakeCyanBackend();
    final surface = await pumpPlayer(tester, backend);
    surface.seek(12);
    await tester.pumpAndSettle();

    // A MECHANICAL ask that names no look at all. Gating the agent on colour is
    // what made every non-colour ask silently stay a note.
    const ask = 'trim 12 frames off the head';
    await askAgainstRegion(tester, ask);

    final rows = await lane(backend);
    final note = rows.firstWhere((e) => e['intent'] == ask && e['kind'] == 'note');
    expect(note['proposed_by'], 'human');

    // The agent read the ledger and PROPOSED — a new fact referencing the note,
    // waiting on a human, never a mutation of what the reviewer wrote.
    final proposal = rows.firstWhere(
        (e) => e['op'] == 'trim_head' && e['proposed_by'] == 'agent');
    expect(proposal['state'], 'proposed');
    expect((proposal['params'] as Map)['frames'], 12);
    expect((proposal['ref'] as Map)['about_entry_hash'], note['entry_hash']);

    // …and the player shows the gate it opened.
    expect(find.byKey(ValueKey('review.rail.row.${proposal['id']}')),
        findsOneWidget);
  });

  testWidgets('the version selector plays a preview when the master is '
      'undecodable', (tester) async {
    final backend = FakeCyanBackend();
    final surface = await pumpPlayer(tester, backend);

    // The board's master is a camera original (.mxf) — AVFoundation cannot
    // decode it, so mounting it would dead-end the v1 leg.
    final media = await backend.boardVideoMedia(_board);
    expect(media.masterUri, endsWith('.mxf'));
    expect(media.previewPath, isNotNull);

    await tester.tap(find.byKey(const ValueKey('review.version.selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('review.version.option.v1')));
    await tester.pumpAndSettle();

    // v1 plays the engine's frame-mapped preview, never the un-decodable
    // master. The ledger stays master-native either way.
    expect(surface.mountedPath, media.previewPath);
    expect(surface.mountedPath, isNot(media.masterUri));
  });

  testWidgets('the version head can be undone and redone', (tester) async {
    final backend = FakeCyanBackend();
    final surface = await pumpPlayer(tester, backend);
    expect(find.text('v2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('review.undo')));
    await tester.pumpAndSettle();

    // The head stepped back: the lane is checked out at v1 and the conformed
    // cut is no longer the version under review.
    var envelope =
        await backend.changelistCommand({'op': 'list', 'board_id': _board});
    expect(envelope.fields['version'], 1);
    expect(find.text('v1'), findsOneWidget);
    expect(surface.mountedPath, isNot(_proxy));

    await tester.tap(find.byKey(const ValueKey('review.redo')));
    await tester.pumpAndSettle();

    envelope =
        await backend.changelistCommand({'op': 'list', 'board_id': _board});
    expect(envelope.fields['version'], 2);
    expect(find.text('v2'), findsOneWidget);
    expect(surface.mountedPath, _proxy);
    // The arrival is announced rather than silently swapped under the reviewer.
    expect(find.byKey(const ValueKey('review.version.badge')), findsOneWidget);
  });

  test('a fast first click loads the ledger then steps rather than no opping',
      () async {
    final backend = FakeCyanBackend();
    final player =
        ReviewPlayerController(backend: backend, boardId: _board);

    // The click beats the async envelope: nothing is resolved yet, so the verb
    // has no anchors to ride and the engine would refuse "" ones.
    expect(player.current.version, 0);
    expect(player.current.tenantId, isNull);

    await player.undoCut();

    // It resolved the ledger FIRST, then stepped — never silently dropped.
    expect(player.current.tenantId, 'g-eng');
    expect(player.current.version, 1);
    final envelope =
        await backend.changelistCommand({'op': 'list', 'board_id': _board});
    expect(envelope.fields['version'], 1);
  });

  test('the render registry describes every entry, including one it has never '
      'seen', () {
    ReviewEntry entryOf(Map<String, dynamic> j) => ReviewEntry.fromJson(j);
    final registry = ReviewEntryRenderRegistry.standard;

    // A mechanical proposal: the confirm gate, in agent tint.
    final agentOp = registry.resolve(entryOf({
      'kind': 'op',
      'op': 'audio_duck',
      'state': 'proposed',
      'proposed_by': 'agent',
    }));
    expect(agentOp.ruleName, 'op.agentProposed');
    expect(agentOp.descriptor.panelActions,
        [PanelAction.approve, PanelAction.edit, PanelAction.reject]);
    expect(agentOp.descriptor.isCreative, isFalse);

    // A note is creative: kept or promoted BY A HUMAN, never auto-op'd.
    final note = registry.resolve(entryOf({'kind': 'note', 'state': 'proposed'}));
    expect(note.ruleName, 'note.creative');
    expect(note.descriptor.isCreative, isTrue);
    expect(note.descriptor.panelActions,
        [PanelAction.keepNote, PanelAction.promoteToOp]);

    // An op this build has never compiled against still renders coherently —
    // extension by DATA, not by a new code branch.
    final unknown = registry.resolve(entryOf({
      'kind': 'op',
      'op': 'depth_relight',
      'state': 'proposed',
      'proposed_by': 'agent',
    }));
    expect(unknown.ruleName, 'default.opLike');
    expect(unknown.descriptor.markerStyle, MarkerStyle.range);
    expect(unknown.descriptor.panelActions,
        [PanelAction.approve, PanelAction.edit, PanelAction.reject]);
  });

  testWidgets('golden: review player', (tester) async {
    final backend = FakeCyanBackend();
    await pumpPlayer(tester, backend);
    await expectLater(
      find.byType(ParityReviewPlayerView),
      matchesGoldenFile('golden/review_player.png'),
    );
  }, tags: 'golden');
}
