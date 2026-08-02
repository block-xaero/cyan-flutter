// providers/ingest_sources_controller.dart
//
// The board's INGEST SOURCES surface, ported from `SourcesViewModel`
// (ViewModels/SourcesViewModel.swift): the watched sensors a board points at,
// the scan that walks one of them, and the per-asset runs a scan materializes.
//
// "Point this board at a source" replaces "attach 1–10 files". Every read and
// write rides the ONE ingest gateway on the `CyanBackend` seam —
// `ingestCommand`, the engine's `cyan_ingest_command` JSON op-dispatch — so the
// face is Tier-1 drivable against FakeCyanBackend with no dylib and no media.
//
// Four invariants carried over from the Swift view-model:
//
//   • TENANT IN, BOARD OUT — `source_list` speaks the tenant (the group); the
//     sheet shows only THIS board's sensors, so the listing is filtered here.
//     The same split is why every op carries `tenant_id` and only some carry
//     `board_id`.
//   • AN ENGINE REFUSAL IS AN ANSWER — a `{"error":…}` reply lands in [error]
//     verbatim and is shown, never swallowed. That includes a scan of a source
//     that went away underneath the sheet.
//   • A SCAN THAT INGESTS NOTHING IS A RESULT, not a no-op. The report is
//     recorded and rendered whatever its counts are, so "I pressed Scan now and
//     nothing happened" is never the read.
//   • REMOVING A SENSOR KEEPS WHAT IT INGESTED — the runs a scan materialized
//     outlive the source that found them, so the runs are NOT re-derived from
//     the source list.
//
// CADENCE IS APP-PACED (engine-side scheduling is v2 — the engine deliberately
// runs no background thread). [IngestSourcesController.tick] is one sweep:
// `scan_due` for the tenant, but only when something is actually scheduled.
// Nothing here starts a Timer — the host decides the cadence, and a test drives
// `tick()` directly rather than waiting out a clock.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/cyan_backend.dart';
import '../ffi/parity_models.dart';
import 'cyan_backend_provider.dart';

/// What a sources sheet is pointed at: one board, inside the tenant whose
/// boundary every ingest verb carries. Both halves are needed — the board scopes
/// what is shown, the tenant scopes what may be asked.
typedef IngestScope = ({String boardId, String tenantId});

@immutable
class IngestSourcesState {
  final bool loading;

  /// This board's watched sensors, in engine order.
  final List<IngestSource> sources;

  /// The board's per-asset materialized runs, oldest first — one run per
  /// ingested asset, which is what "workflow = asset class" means here.
  final List<MaterializedRun> runs;

  /// The last scan outcome per source id, from a scan-now or a scheduled
  /// sweep. Absent means "not scanned in this session", which is not the same
  /// as "scanned and found nothing".
  final Map<String, ScanReport> reports;

  /// The engine's refusal, verbatim. Shown in the banner until dismissed.
  final String? error;

  /// The source whose scan is in flight; null when nothing is scanning.
  final String? scanningId;

  const IngestSourcesState({
    this.loading = true,
    this.sources = const [],
    this.runs = const [],
    this.reports = const {},
    this.error,
    this.scanningId,
  });

  bool get isEmpty => sources.isEmpty;
  bool get isScanning => scanningId != null;

  /// True when at least one sensor is on a cadence rather than waiting to be
  /// asked — the condition the scheduled sweep is worth issuing under.
  bool get hasScheduled => sources.any((s) => s.isScheduled);

  IngestSourcesState copyWith({
    bool? loading,
    List<IngestSource>? sources,
    List<MaterializedRun>? runs,
    Map<String, ScanReport>? reports,
    String? error,
    bool clearError = false,
    String? scanningId,
    bool clearScanning = false,
  }) {
    return IngestSourcesState(
      loading: loading ?? this.loading,
      sources: sources ?? this.sources,
      runs: runs ?? this.runs,
      reports: reports ?? this.reports,
      error: clearError ? null : (error ?? this.error),
      scanningId: clearScanning ? null : (scanningId ?? this.scanningId),
    );
  }
}

/// One board's ingest sensors. Keyed by (board, tenant): another board's
/// sensors are a different set, and the same board id under another tenant is
/// not this caller's to read.
final ingestSourcesProvider = StateNotifierProvider.autoDispose
    .family<IngestSourcesController, IngestSourcesState, IngestScope>(
        (ref, scope) {
  final controller = IngestSourcesController(
    backend: ref.watch(cyanBackendProvider),
    scope: scope,
  );
  controller.load();
  return controller;
});

class IngestSourcesController extends StateNotifier<IngestSourcesState> {
  final CyanBackend _backend;
  final IngestScope scope;

  IngestSourcesController({
    required CyanBackend backend,
    required this.scope,
  })  : _backend = backend,
        super(const IngestSourcesState());

  String get boardId => scope.boardId;
  String get tenantId => scope.tenantId;

  /// Send one op through the gateway. An engine refusal lands in [state.error]
  /// and the result comes back null, so every caller either has a reply or has
  /// already reported why it does not.
  Future<IngestCommandResult?> _send(Map<String, dynamic> command) async {
    IngestCommandResult result;
    try {
      result = await _backend.ingestCommand(command);
    } catch (e) {
      if (mounted) state = state.copyWith(error: 'Ingest failed: $e');
      return null;
    }
    if (!mounted) return null;
    if (!result.ok) {
      state = state.copyWith(error: result.error);
      return null;
    }
    return result;
  }

  /// Re-read this board's sensors and its materialized runs. Also the RELOAD
  /// every write ends with — the engine is the truth, so a row is never patched
  /// locally on the strength of what was just sent.
  Future<void> load() async {
    final listed = await _send({'op': 'source_list', 'tenant_id': tenantId});
    if (!mounted) return;
    if (listed == null) {
      state = state.copyWith(loading: false);
      return;
    }
    final mine = [
      for (final s in listed.sources)
        if (s.boardId == boardId) s,
    ];
    state = state.copyWith(loading: false, sources: mine);
    await _loadRuns();
  }

  /// Re-read the board's per-asset runs. Refreshed after any scan so the strip
  /// shows what the scan just materialized.
  Future<void> _loadRuns() async {
    final result = await _send({
      'op': 'runs_for_board',
      'tenant_id': tenantId,
      'board_id': boardId,
    });
    if (!mounted || result == null) return;
    state = state.copyWith(runs: result.runs);
  }

  /// Point this board at a source. [scheduleSecs] null = manual only ("Scan
  /// now"). Returns whether the engine ACCEPTED it — a refused kind, a missing
  /// uri or a non-positive cadence comes back false with the reason in the
  /// banner.
  Future<bool> addSource({
    required String kind,
    required String uri,
    int? scheduleSecs,
  }) async {
    final trimmed = uri.trim();
    if (trimmed.isEmpty) return false;
    state = state.copyWith(clearError: true);
    final result = await _send({
      'op': 'source_add',
      'tenant_id': tenantId,
      'board_id': boardId,
      'kind': kind,
      'uri': trimmed,
      if (scheduleSecs != null) 'schedule_secs': scheduleSecs,
    });
    if (result == null) return false;
    await load();
    return true;
  }

  /// Drop a sensor. Already-ingested assets and the runs they materialized are
  /// UNTOUCHED — the engine's contract, and the reason the runs are re-read
  /// rather than filtered by the surviving sources.
  Future<void> removeSource(String id) async {
    state = state.copyWith(clearError: true);
    final result = await _send({
      'op': 'source_remove',
      'tenant_id': tenantId,
      'id': id,
    });
    if (result == null) return;
    state = state.copyWith(reports: {...state.reports}..remove(id));
    await load();
  }

  /// Scan one source NOW: walk its listing, register what is new, materialize a
  /// run for each newly ingested asset. The report is recorded WHATEVER its
  /// counts are — a scan that ingests nothing has still answered.
  Future<void> scanNow(String sourceId) async {
    if (state.isScanning) return;
    state = state.copyWith(clearError: true, scanningId: sourceId);
    final result =
        await _send({'op': 'scan_now', 'tenant_id': tenantId, 'source_id': sourceId});
    if (!mounted) return;
    if (result == null) {
      state = state.copyWith(clearScanning: true);
      return;
    }
    final report = result.report;
    state = state.copyWith(
      clearScanning: true,
      reports: {
        ...state.reports,
        if (report != null) sourceId: report,
      },
    );
    // `last_scan_at` advanced and new assets materialized their runs.
    await load();
  }

  /// One cadence tick: sweep every source whose schedule has come round. Cheap
  /// no-op when nothing on this board is scheduled, so a host can call it on a
  /// timer without asking the engine anything.
  ///
  /// A per-source failure is carried on its OWN row — one unreadable sensor
  /// surfaces its error without sinking the sweep.
  Future<void> tick({int? now}) async {
    if (!state.hasScheduled) return;
    final result = await _send({
      'op': 'scan_due',
      'tenant_id': tenantId,
      if (now != null) 'now': now,
    });
    if (!mounted || result == null) return;

    final mine = {for (final s in state.sources) s.id};
    final reports = {...state.reports};
    String? failure;
    var swept = false;
    for (final outcome in result.sweep) {
      if (!mine.contains(outcome.sourceId)) continue;
      swept = true;
      if (outcome.error != null) {
        failure = outcome.error;
        continue;
      }
      if (outcome.report != null) reports[outcome.sourceId] = outcome.report!;
    }
    if (!swept) return;
    state = state.copyWith(reports: reports, error: failure);
    await load();
  }

  /// Dismiss the banner. The engine said it; the operator has read it.
  void clearError() {
    if (mounted) state = state.copyWith(clearError: true);
  }
}

// ---------------------------------------------------------------------------
// Row labels (pure — the row's second line, formatted as the macOS sheet reads)
// ---------------------------------------------------------------------------

/// A sensor's cadence, as the row says it. Null = manual only.
String ingestScheduleLabel(int? secs) {
  if (secs == null) return 'manual';
  if (secs % 3600 == 0) return 'every ${secs ~/ 3600}h';
  if (secs % 60 == 0) return 'every ${secs ~/ 60}m';
  return 'every ${secs}s';
}

/// When this sensor was last SUCCESSFULLY scanned. Null = never — which the row
/// says outright, because "no report yet" and "scanned, found nothing" are
/// different facts.
///
/// Recent scans read relatively (the macOS `RelativeDateTimeFormatter`); once a
/// scan is old enough that "2 months ago" stops being useful, the row shows the
/// day itself.
String ingestLastScanLabel(DateTime? at, {DateTime? now}) {
  if (at == null) return 'never scanned';
  final elapsed = (now ?? DateTime.now()).difference(at);
  if (elapsed.isNegative || elapsed.inSeconds < 60) return 'scanned just now';
  if (elapsed.inMinutes < 60) return 'scanned ${elapsed.inMinutes}m ago';
  if (elapsed.inHours < 24) return 'scanned ${elapsed.inHours}h ago';
  if (elapsed.inDays < 30) return 'scanned ${elapsed.inDays}d ago';
  return 'scanned on ${_isoDay(at)}';
}

String _isoDay(DateTime t) =>
    '${t.year}-${_pad(t.month)}-${_pad(t.day)}';

String _pad(int n) => n.toString().padLeft(2, '0');

/// What one scan DID, in a sentence. The two nothing-happened outcomes are
/// named explicitly rather than left to be inferred from three zeroes:
///
///   • nothing at the location at all — the sensor is pointed somewhere empty
///   • nothing NEW — every candidate was already ingested, which is the correct
///     answer to a second scan, not a failure
String ingestScanSummary(ScanReport report) {
  if (report.discovered == 0) {
    return 'Scanned — found no media at this location.';
  }
  if (report.ingested == 0) {
    return 'Scanned — nothing new; '
        'all ${report.discovered} already ingested.';
  }
  final known = report.deduped == 0 ? '' : ' · ${report.deduped} already known';
  return 'Ingested ${report.ingested} of ${report.discovered}$known';
}
