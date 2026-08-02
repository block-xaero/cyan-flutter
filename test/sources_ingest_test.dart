// test/sources_ingest_test.dart
//
// PARITY face `sources_ingest` — the board's ingest SOURCES sheet (SwiftUI
// `SourcesSheet` / `SourcesViewModel`, plus the `IngestRunsStrip` beside it).
// Tier-1: drives `ParitySourcesSheet` through the `CyanBackend` seam
// (FakeCyanBackend) with no dylib, no media and no engine.
//
// The face makes one sentence true — point this board at a source and new media
// materialises its own pipeline run — so the tests drive that sentence end to
// end: add a sensor, scan it, watch the runs appear, and then scan it AGAIN and
// check that "there was nothing new" comes back as an answer rather than as
// silence.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/providers/ingest_sources_controller.dart';
import 'package:cyan_flutter/widgets/parity/parity_sources_sheet.dart';

import 'support/parity_test_harness.dart';

/// A board with no sensors of its own — the sheet's cold start.
const _freshBoard = 'b-des-2';
const _freshTenant = 'g-des';
const _watched = '/Volumes/dailies/day-04';

/// Register a sensor straight on the seam, for the tests whose subject is what
/// happens AFTER it exists. Returns the engine's id for it.
Future<String> _seedSource(FakeCyanBackend backend, {int? scheduleSecs}) async {
  final added = await backend.ingestCommand({
    'op': 'source_add',
    'tenant_id': _freshTenant,
    'board_id': _freshBoard,
    'kind': 'folder',
    'uri': _watched,
    if (scheduleSecs != null) 'schedule_secs': scheduleSecs,
  });
  expect(added.ok, isTrue, reason: added.error ?? '');
  return added.sources.single.id;
}

Future<List<MaterializedRun>> _runsOnEngine(FakeCyanBackend backend) async {
  final result = await backend.ingestCommand({
    'op': 'runs_for_board',
    'tenant_id': _freshTenant,
    'board_id': _freshBoard,
  });
  return result.runs;
}

void main() {
  testWidgets('the sources sheet adds a media source to a board',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(
      tester,
      const ParitySourcesSheet(boardId: _freshBoard, tenantId: _freshTenant),
      backend: backend,
    );

    // A board nothing is pointed at says so — this is not a spinner.
    expect(find.text('No sources yet'), findsOneWidget);

    // Point it at a watched folder, on a 15-minute cadence.
    await tester.enterText(
        find.byKey(const Key('sources.add.uri')), _watched);
    await tester.pump();
    await tester.tap(find.text('Every 15 minutes'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('sources.add.confirm')));
    await tester.pumpAndSettle();

    // The sensor is on the sheet, reading back its kind, its cadence and the
    // fact that it has not run yet.
    expect(find.text('No sources yet'), findsNothing);
    expect(find.text(_watched), findsOneWidget);
    expect(find.textContaining('folder · every 15m · never scanned'),
        findsOneWidget);

    // The form resets, so the next add starts clean rather than re-submitting.
    expect(tester.widget<TextField>(find.byKey(const Key('sources.add.uri')))
        .controller!
        .text,
        isEmpty);

    // The ENGINE holds it, attached to THIS board inside THIS tenant — the row
    // is not a local optimism.
    final listed = await backend
        .ingestCommand({'op': 'source_list', 'tenant_id': _freshTenant});
    expect(listed.sources, hasLength(1));
    expect(listed.sources.single.uri, _watched);
    expect(listed.sources.single.boardId, _freshBoard);
    expect(listed.sources.single.scheduleSecs, 900);
  });

  testWidgets('an empty location is refused before it reaches the engine',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(
      tester,
      const ParitySourcesSheet(boardId: _freshBoard, tenantId: _freshTenant),
      backend: backend,
    );

    // Nothing typed — there is nothing to point at, so the button rests.
    final button = tester
        .widget<ElevatedButton>(find.byKey(const Key('sources.add.confirm')));
    expect(button.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('sources.add.uri')), '  ');
    await tester.pump();
    expect(
        tester
            .widget<ElevatedButton>(
                find.byKey(const Key('sources.add.confirm')))
            .onPressed,
        isNull);

    final listed = await backend
        .ingestCommand({'op': 'source_list', 'tenant_id': _freshTenant});
    expect(listed.sources, isEmpty);
  });

  testWidgets('scan now materialises runs for newly found media',
      (tester) async {
    final backend = FakeCyanBackend();
    final sourceId = await _seedSource(backend);

    await pumpParity(
      tester,
      const ParitySourcesSheet(boardId: _freshBoard, tenantId: _freshTenant),
      backend: backend,
    );

    // Before the scan there is nothing to show: no report, no runs.
    expect(find.byKey(const Key('workflow.runs.strip')), findsNothing);
    expect(find.byKey(Key('sources.report.$sourceId')), findsNothing);

    await tester.tap(find.byKey(Key('sources.scan.$sourceId')));
    await tester.pumpAndSettle();

    // The scan reports what it did...
    expect(find.text('3 discovered'), findsOneWidget);
    expect(find.text('3 ingested'), findsOneWidget);
    expect(find.text('0 deduped'), findsOneWidget);
    expect(find.text('Ingested 3 of 3'), findsOneWidget);

    // ...and each newly found file materialised its OWN run of this board's
    // workflow template — that is what "workflow = asset class" buys.
    expect(find.byKey(const Key('workflow.runs.strip')), findsOneWidget);
    expect(find.text('Runs · 3'), findsOneWidget);
    expect(find.text('materialized'), findsNWidgets(3));

    // The engine is the truth: three runs, one per ingested asset, each keyed
    // by the asset's content hash rather than by the board.
    final runs = await _runsOnEngine(backend);
    expect(runs, hasLength(3));
    expect(runs.map((r) => r.assetHash).toSet(), hasLength(3));
    expect(runs.every((r) => r.boardId == _freshBoard), isTrue);
  });

  testWidgets('a source reports its last scan time', (tester) async {
    final backend = FakeCyanBackend();
    // The flagship board carries both halves of the split: a folder that has
    // run before, and a C2C project that never has.
    await pumpParity(
      tester,
      const ParitySourcesSheet(boardId: 'b-eng-1', tenantId: 'g-eng'),
      backend: backend,
    );

    final untouched =
        find.textContaining('frameio_c2c · manual · never scanned');
    expect(untouched, findsOneWidget);
    expect(find.textContaining('never scanned'), findsOneWidget);

    // The one that HAS run reports when, not just that it did.
    final dailies = find.textContaining('folder · every 15m · scanned');
    expect(dailies, findsOneWidget);
    expect(tester.widget<Text>(dailies).data, isNot(contains('never')));

    // Scanning the untouched one gives it a time of its own.
    await tester.tap(find.byKey(const Key('sources.scan.src-eng-c2c')));
    await tester.pumpAndSettle();

    expect(find.textContaining('never scanned'), findsNothing);
    expect(find.textContaining('frameio_c2c · manual · scanned'),
        findsOneWidget);
  });

  testWidgets('a scan that finds nothing reports that rather than failing '
      'silently', (tester) async {
    final backend = FakeCyanBackend();
    final sourceId = await _seedSource(backend);
    // The first scan takes everything the location holds.
    final first = await backend.ingestCommand(
        {'op': 'scan_now', 'tenant_id': _freshTenant, 'source_id': sourceId});
    expect(first.report!.ingested, 3);

    await pumpParity(
      tester,
      const ParitySourcesSheet(boardId: _freshBoard, tenantId: _freshTenant),
      backend: backend,
    );

    // Scan it again. Nothing there is new.
    await tester.tap(find.byKey(Key('sources.scan.$sourceId')));
    await tester.pumpAndSettle();

    // The counts are on the row — a scan that ingested nothing still ran, and
    // the sheet says so in words rather than leaving three numbers to be read
    // as a failure.
    expect(find.text('3 discovered'), findsOneWidget);
    expect(find.text('0 ingested'), findsOneWidget);
    expect(find.text('3 deduped'), findsOneWidget);
    expect(find.text('Scanned — nothing new; all 3 already ingested.'),
        findsOneWidget);

    // No banner: nothing failed. And nothing was quietly manufactured either —
    // the run count is exactly where the first scan left it.
    expect(find.byKey(const Key('sources.error.banner')), findsNothing);
    expect(find.text('Runs · 3'), findsOneWidget);
    expect(await _runsOnEngine(backend), hasLength(3));
  });

  testWidgets('a scheduled sweep scans the sources whose cadence came round',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(
      tester,
      const ParitySourcesSheet(boardId: 'b-eng-1', tenantId: 'g-eng'),
      backend: backend,
    );

    // The cadence is app-paced (the engine runs no background thread), so the
    // tick is injected rather than waited out.
    final container = ProviderScope.containerOf(
        tester.element(find.byType(ParitySourcesSheet)));
    await container
        .read(ingestSourcesProvider(
                (boardId: 'b-eng-1', tenantId: 'g-eng')).notifier)
        .tick();
    await tester.pumpAndSettle();

    // The scheduled folder swept and reported; the manual-only C2C project did
    // not — that is what "manual only" means.
    expect(find.text('Ingested 2 of 3 · 1 already known'), findsOneWidget);
    expect(find.byKey(const Key('sources.report.src-eng-c2c')), findsNothing);
  });

  testWidgets('removing a source keeps what it already ingested',
      (tester) async {
    final backend = FakeCyanBackend();
    final sourceId = await _seedSource(backend);
    await backend.ingestCommand(
        {'op': 'scan_now', 'tenant_id': _freshTenant, 'source_id': sourceId});

    await pumpParity(
      tester,
      const ParitySourcesSheet(boardId: _freshBoard, tenantId: _freshTenant),
      backend: backend,
    );
    expect(find.text(_watched), findsOneWidget);

    await tester.tap(find.byKey(Key('sources.remove.$sourceId')));
    await tester.pumpAndSettle();

    // The sensor is gone from the board...
    expect(find.text(_watched), findsNothing);
    expect(find.text('No sources yet'), findsOneWidget);

    // ...and the assets it ingested, with their runs, are not.
    expect(find.text('Runs · 3'), findsOneWidget);
    expect(await _runsOnEngine(backend), hasLength(3));
  });

  testWidgets('an engine refusal is shown rather than swallowed',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(
      tester,
      const ParitySourcesSheet(boardId: 'b-eng-1', tenantId: 'g-eng'),
      backend: backend,
    );

    // The source goes away underneath the open sheet.
    await backend.ingestCommand(
        {'op': 'source_remove', 'tenant_id': 'g-eng', 'id': 'src-eng-c2c'});

    await tester.tap(find.byKey(const Key('sources.scan.src-eng-c2c')));
    await tester.pumpAndSettle();

    final banner = find.byKey(const Key('sources.error.banner'));
    expect(banner, findsOneWidget);
    expect(find.textContaining("no ingest_source 'src-eng-c2c'"),
        findsOneWidget);

    await tester.tap(
        find.descendant(of: banner, matching: find.byIcon(Icons.close)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sources.error.banner')), findsNothing);
  });

  test('a scan report reads as the sheet words it', () {
    expect(ingestScanSummary(const ScanReport()),
        'Scanned — found no media at this location.');
    expect(
        ingestScanSummary(
            const ScanReport(discovered: 4, ingested: 0, deduped: 4)),
        'Scanned — nothing new; all 4 already ingested.');
    expect(
        ingestScanSummary(
            const ScanReport(discovered: 3, ingested: 3, deduped: 0)),
        'Ingested 3 of 3');
    expect(
        ingestScanSummary(
            const ScanReport(discovered: 3, ingested: 2, deduped: 1)),
        'Ingested 2 of 3 · 1 already known');
  });

  test('a source row labels its cadence and its last read', () {
    expect(ingestScheduleLabel(null), 'manual');
    expect(ingestScheduleLabel(45), 'every 45s');
    expect(ingestScheduleLabel(60), 'every 1m');
    expect(ingestScheduleLabel(900), 'every 15m');
    expect(ingestScheduleLabel(3600), 'every 1h');

    final now = DateTime.utc(2026, 6, 1, 12);
    expect(ingestLastScanLabel(null, now: now), 'never scanned');
    expect(
        ingestLastScanLabel(now.subtract(const Duration(seconds: 20)),
            now: now),
        'scanned just now');
    expect(
        ingestLastScanLabel(now.subtract(const Duration(minutes: 7)), now: now),
        'scanned 7m ago');
    expect(ingestLastScanLabel(now.subtract(const Duration(hours: 5)), now: now),
        'scanned 5h ago');
    expect(ingestLastScanLabel(now.subtract(const Duration(days: 3)), now: now),
        'scanned 3d ago');
    expect(ingestLastScanLabel(DateTime.utc(2026, 1, 9), now: now),
        'scanned on 2026-01-09');
  });
}
