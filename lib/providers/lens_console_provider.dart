// providers/lens_console_provider.dart
//
// Row 19 — the Ops console on the LENS lane (PHASE-2 D3), the port of
// `OperationsConsoleViewModel`.
//
// WHAT MOVED AND WHY. `opsRunsProvider`, `costMeterProvider` and
// `efficiencyProvider` used to hang off the `CyanBackend` (FFI) seam, where the
// last two returned honest zeros because the engine has no cost or efficiency
// verb. PARITY_TRACKER carried them as "blocked: no verb" — accurate, and the
// wrong conclusion. On the Mac these three faces read cyan-lens over HTTP and
// always have. There was never going to be an engine verb. They now read the
// `LensApi` seam, which is what the Mac does.
//
// AND ALL THREE ARE ONE FETCH. The Runs face IS the feed; Cost and Efficiency
// are pure reductions over the §3 step records that same feed already nests in
// every run (`lens_rollups.dart`). Flipping the console's segmented control
// costs nothing and cannot disagree with itself, because there is only one
// source.
//
// The FFI seam's `loadOpsRuns` STAYS — it is the engine-assembled per-board run
// state the boards wall reads (Tier-2 T7 proves it), which is a different
// question from what the tenant's lens says. Two lanes, two questions.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/parity_models.dart';
import '../lens/lens_api.dart';
import '../lens/lens_models.dart';
import '../lens/lens_rollups.dart';
import '../lens/marketplace_mapping.dart';
import 'cyan_backend_provider.dart';

// ---------------------------------------------------------------------------
// The seam
// ---------------------------------------------------------------------------

/// The single `LensApi` instance. Prod = the live HTTP client bound to
/// `CYAN_LENS_URL`. Tests override this with `FakeLensApi` — the same
/// discipline `cyanBackendProvider` follows, and the reason D4 keeps the two
/// seams apart.
final lensApiProvider = Provider<LensApi>((ref) => LensApiHttp());

/// How many runs the console asks for. The lens's `counts` stay authoritative
/// over this cap, so a capped feed still shows correct totals.
const int kOpsRunLimit = 50;

/// The TENANT-WIDE run feed — `board` omitted entirely, which is a different
/// request from `board=`. Everything the console draws comes from here.
final lensRunFeedProvider = FutureProvider<RunBoardFeed>((ref) async {
  final lens = ref.watch(lensApiProvider);
  return lens.runs(limit: kOpsRunLimit);
});

/// One board's feed — the Dashboard's embedded console.
final lensBoardFeedProvider =
    FutureProvider.family<RunBoardFeed, String>((ref, boardId) async {
  final lens = ref.watch(lensApiProvider);
  return lens.runs(board: boardId, limit: kOpsRunLimit);
});

/// Board id → the name an operator recognises. The lens keys everything by
/// board id; the names live in the engine's tree dump. Resolved
/// NON-BLOCKINGLY: until the wall has loaded (or if it fails), the console
/// falls back to the id rather than waiting on a second seam.
final _boardNamesProvider = Provider<Map<String, String>>((ref) {
  final boards = ref.watch(allBoardsProvider).valueOrNull;
  if (boards == null) return const {};
  return {for (final b in boards) b.board.id: b.board.name};
});

// ---------------------------------------------------------------------------
// The three console faces, all derived from the one feed
// ---------------------------------------------------------------------------

/// Ops console — Runs (row 6 / 19).
final opsRunsProvider = FutureProvider<List<OpsRun>>((ref) async {
  final feed = await ref.watch(lensRunFeedProvider.future);
  final names = ref.watch(_boardNamesProvider);
  return [for (final r in feed.allRuns) opsRunFrom(r, boardNames: names)];
});

/// Ops console — the asset-minute meter (row 7 / 19).
final costMeterProvider = FutureProvider<CostMeter>((ref) async {
  final feed = await ref.watch(lensRunFeedProvider.future);
  final names = ref.watch(_boardNamesProvider);
  return costMeterFrom(feed.allRuns, boardNames: names);
});

/// Ops console — the efficiency rollup (row 8 / 19).
final efficiencyProvider = FutureProvider<EfficiencyReport>((ref) async {
  final feed = await ref.watch(lensRunFeedProvider.future);
  return efficiencyReportFrom(EfficiencyRollup.fromRuns(feed.allRuns));
});

// ---------------------------------------------------------------------------
// Row 20 — the Marketplace storefront, on the same lane
// ---------------------------------------------------------------------------

/// The storefront browse (`GET /marketplace/browse`), mapped and curated.
///
/// Install actions are NOT an open endpoint: they flow through the server's
/// RBAC-gated install, which the UI only REFLECTS. What lands on the device is
/// read back from the ENGINE's catalog, never claimed here.
final marketplaceProvider = FutureProvider<List<PluginCard>>((ref) async {
  final lens = ref.watch(lensApiProvider);
  final wire = await lens.browseMarketplace(const StorefrontQuery());
  return storefrontCardsFrom(wire);
});

// ---------------------------------------------------------------------------
// Row 21 — the Lens AI face (nudges / asks / decisions), on the same lane
// ---------------------------------------------------------------------------

/// The clock the age labels are rendered against, in unix SECONDS.
///
/// Injected rather than read at the point of use so a golden and a widget test
/// pin "1d ago" instead of racing the wall clock — the same discipline the
/// Swift `LicenseViewModel` follows with its `now`.
final lensNowProvider =
    Provider<int>((ref) => DateTime.now().millisecondsSinceEpoch ~/ 1000);

/// The Lens AI bundle: is the lens up, and what has it noticed.
///
/// FOUR reads, and the connection one is not optional. `loadLensIntelligence`
/// on the FFI seam answered `connected: false` unconditionally, which was the
/// honest reading of a build that binds no lens — but it is a claim, and the
/// only thing entitled to make it is `/health`. A strict health decode is also
/// what once showed "Disconnected" over a perfectly live lens (the live `data`
/// dropped `iggy` and added `commit`), so the decode is tolerant and the
/// statusText names the leg that is actually down.
final lensIntelligenceProvider =
    FutureProvider<LensIntelligence>((ref) async {
  final lens = ref.watch(lensApiProvider);
  final now = ref.watch(lensNowProvider);

  // Health is asked FIRST and separately: if the lens is down, saying so is
  // the answer, and three more failing reads add nothing.
  LensHealth health;
  try {
    health = await lens.health();
  } on LensApiException {
    return const LensIntelligence(connected: false);
  }

  final report = await lens.nudges();
  final asks = await lens.asks(limit: kLensRowLimit);
  final decisions = await lens.decisions(limit: kLensRowLimit);

  return LensIntelligence(
    connected: health.isHealthy,
    nudges: [for (final n in report.nudges) lensNudgeFrom(n)],
    asks: [for (final a in asks) lensAskFrom(a, now)],
    decisions: [for (final d in decisions) lensDecisionFrom(d, now)],
  );
});

/// How many ask/decision rows the face asks for.
const int kLensRowLimit = 50;

LensNudge lensNudgeFrom(LensNudgeWire n) => LensNudge(
      id: n.id,
      title: n.title,
      detail: n.detail,
      ageLabel: n.ageText,
      // The lens's nudge shape carries a GRAPH reference, not a board. The chip
      // shows the NODE the nudge hangs off — never the external id, which is
      // already the detail line for a blocker and would just print twice — and
      // shows nothing at all when the nudge carries neither, rather than
      // captioning it with a board it was never told about.
      boardLabel: n.sourceNodeId ?? n.nodeId ?? '',
      nudgeType: n.nudgeType,
    );

LensAsk lensAskFrom(LensAskRow a, int nowSeconds) {
  // An ask with a recorded answer IS answered, whatever its status string says
  // — the answer is the fact, the status is a label that can lag.
  final answered = a.answerSummary != null && a.answerSummary!.isNotEmpty;
  return LensAsk(
    id: a.id,
    question: a.content,
    asker: a.askerName,
    // The lens leaves an unassigned ask's assignee null. "Unassigned" is the
    // honest word for that; an empty chip reads as a rendering bug.
    assignee: a.assigneeName ?? 'Unassigned',
    ageLabel: a.ageText(nowSeconds),
    status: answered
        ? AskStatus.answered
        : (a.status == 'stale' ? AskStatus.stale : AskStatus.open),
    answer: a.answerSummary,
    answerer: a.answeredByName,
  );
}

/// Reaction COUNTS are their own endpoint (`/decisions/{id}/reactions`), so the
/// feed cannot supply them without an N+1 fetch. They stay zero here, and the
/// face already draws the reaction row only when a count is positive — so a
/// decision reads as "not asked" rather than as "nobody agreed".
LensDecision lensDecisionFrom(LensDecisionRow d, int nowSeconds) =>
    LensDecision(
      id: d.id,
      content: d.content,
      rationale: d.rationale,
      decider: d.deciderName,
      ageLabel: d.ageText(nowSeconds),
    );

/// The three Lens AI writes, and the routing decision behind the first one.
class LensIntelligenceCommands {
  LensIntelligenceCommands(this._lens, this._onChanged);

  final LensApi _lens;
  final void Function() _onChanged;

  /// Resolving a nudge is TWO different verbs depending on what the nudge is
  /// about: a stale ASK is dismissed (`PATCH /asks/{id}/dismiss`), anything
  /// else is resolved on its graph node (`PATCH /nodes/{id}/resolve-blocker`).
  /// The nudge's id is already whichever one applies — [LensNudge.nudgeType] is
  /// what says which verb it belongs to, and a client that guessed would
  /// silently no-op half the time.
  Future<void> resolve(LensNudge nudge) async {
    if (nudge.id.isEmpty) return;
    if (nudge.nudgeType == 'stale_ask') {
      await _lens.dismissAsk(nudge.id);
    } else {
      await _lens.resolveBlocker(nudge.id);
    }
    _onChanged();
  }

  Future<void> answer(String askId, String answer,
      {required String answererId, required String answererName}) async {
    await _lens.answerAsk(askId,
        answer: answer, answererId: answererId, answererName: answererName);
    _onChanged();
  }

  /// Take an ask off the board without answering it. Distinct from [answer] on
  /// purpose: the lens records these as different things, and a "dismiss"
  /// dressed up as an empty answer would put words in someone's mouth.
  Future<void> dismiss(LensAsk ask) async {
    if (ask.id.isEmpty) return;
    await _lens.dismissAsk(ask.id);
    _onChanged();
  }

  Future<void> react(String decisionId, String reaction,
      {required String nodeId, required String displayName}) async {
    await _lens.reactToDecision(decisionId,
        reaction: reaction, nodeId: nodeId, displayName: displayName);
    _onChanged();
  }
}

final lensIntelligenceCommandsProvider =
    Provider<LensIntelligenceCommands>((ref) {
  return LensIntelligenceCommands(
    ref.watch(lensApiProvider),
    () => ref.invalidate(lensIntelligenceProvider),
  );
});

// ---------------------------------------------------------------------------
// Wire → face mappings (pure; the contract test drives them directly)
// ---------------------------------------------------------------------------

/// The lens's lifecycle status → the face's. An UNKNOWN status becomes
/// [RunStatus.running] rather than being dropped: it lanes to In-flight, and a
/// run this client has not heard of is still a live run.
RunStatus runStatusFrom(RunStatusValue v) => switch (v) {
      RunStatusValue.queued => RunStatus.queued,
      RunStatusValue.running => RunStatus.running,
      RunStatusValue.awaitingApproval => RunStatus.awaitingApproval,
      RunStatusValue.stuck => RunStatus.stuck,
      RunStatusValue.done => RunStatus.done,
      RunStatusValue.failed => RunStatus.failed,
      RunStatusValue.unknown => RunStatus.running,
    };

/// One lane card from one run summary.
///
/// Two deliberate choices:
///   • the card's money is `billed_cents` — the CUSTOMER's asset-minute bill.
///     `cost_cents` (GPU) rides on the same row and is internal COGS; showing
///     it as the bill is the one thing the metering foundation forbids.
///   • the progress is the WORKFLOW's authored steps (`step_done`/`step_total`)
///     when the lens serves them, not the run-level "1/1".
OpsRun opsRunFrom(RunSummary r, {Map<String, String> boardNames = const {}}) {
  return OpsRun(
    runId: r.runId,
    asset: (r.asset == null || r.asset!.isEmpty) ? r.runId : r.asset!,
    workflow: boardNames[r.boardId] ?? r.boardId,
    boardId: r.boardId,
    status: runStatusFrom(r.status),
    currentStep: r.stepDone ?? r.currentStepIndex,
    stepCount: r.stepTotal ?? r.stepCount,
    durationLabel: r.durationTimecode,
    costDollars: (r.billedCents ?? 0) / 100.0,
    billedMinutes: r.billedMinutes ?? 0,
    retryMinutes: r.retryMinutes ?? 0,
    isCacheHit: r.hasCacheSavings,
    stageLabel: _stageLabel(r),
  );
}

/// The in-flight stage strip: the action of the step actually RUNNING. Null
/// when nothing is running — the card then shows its duration instead of
/// inventing a stage.
String? _stageLabel(RunSummary r) {
  // NOTE: `RunStepDetail` and `RunTrace` are declared in BOTH
  // `ffi/parity_models.dart` (the run-audit face's own shapes) and
  // `lens/lens_models.dart` (the wire). This file imports both, so neither
  // name may be written here — hence the untyped walk.
  final steps = r.steps;
  if (steps == null) return null;
  for (final s in steps) {
    if (s.stepStatus == 'Running') {
      final a = s.action;
      if (a != null && a.isNotEmpty) return a;
    }
  }
  return null;
}

/// The Cost face from the §4 rollup over the same runs.
CostMeter costMeterFrom(List<RunSummary> runs,
    {Map<String, String> boardNames = const {}}) {
  final meter = AssetMeterRollup(runs);
  return CostMeter(
    hasMeter: meter.hasMeter,
    billedMinutes: meter.billedMinutes,
    billedDollars: meter.billedCents / 100.0,
    retryMinutes: meter.retryMinutes,
    savedMinutes: meter.cacheSavedMinutes,
    runs: meter.runCount,
    computeMinutes: meter.workflowMinutes,
    gpuSeconds: meter.gpuSeconds,
    perWorkflow: [
      for (final row in AssetMeterRollup.byWorkflow(runs))
        WorkflowCost(
          workflow: boardNames[row.boardId] ?? row.boardId,
          runs: row.meter.runCount,
          assets: row.meter.assetCount,
          billedMinutes: row.meter.billedMinutes,
          billedDollars: row.meter.billedCents / 100.0,
          retryMinutes: row.meter.retryMinutes,
        ),
    ],
  );
}

/// The Efficiency face from the §5 rollup.
///
/// The headline cards name a STEP, so each one reads its own pick's rate rather
/// than the tenant average — "the conform step fails 18%" is actionable in a
/// way "8% of executions failed" is not. The overall rates drive the cache and
/// retry cards, which are genuinely tenant-wide questions.
EfficiencyReport efficiencyReportFrom(EfficiencyRollup rollup) {
  final gate = rollup.gateBottleneck;
  final hotspot = rollup.topFailingStep;
  final slowest = rollup.slowestStep;
  return EfficiencyReport(
    gateBottleneckStep: gate?.label ?? '—',
    gateWaitP95Ms: (gate?.approvalWaitP95Ms ?? 0).toDouble(),
    failureHotspotStep: hotspot?.label ?? '—',
    failureRatePct: (hotspot?.failureRate ?? 0) * 100,
    topErrorClass: hotspot?.topErrorClass,
    slowestStep: slowest?.label ?? '—',
    slowestExecP95Ms: (slowest?.execP95Ms ?? 0).toDouble(),
    cacheHitRatePct: rollup.overallCacheHitRate * 100,
    minutesSaved: rollup.totalMinutesSaved,
    retryRatePct: rollup.overallRetryRate * 100,
    steps: [
      for (final s in rollup.steps)
        StepEfficiency(
          step: s.label,
          runs: s.executions,
          gateP95Ms: (s.approvalWaitP95Ms ?? 0).toDouble(),
          failPct: s.failureRate * 100,
          topError: s.topErrorClass,
          execP95Ms: (s.execP95Ms ?? 0).toDouble(),
          cachePct: s.cacheHitRate * 100,
          savedMinutes: s.minutesSaved,
          retryPct: s.retryRate * 100,
        ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Commands — Retry / Approve / Reject
// ---------------------------------------------------------------------------

/// What the console knows about commands in flight. The busy set is why a tap
/// can neither look like a no-op nor be double-fired.
@immutable
class OpsCommandState {
  final Set<String> busyRunIds;

  /// The lens's own words when a command was refused (e.g. the CONFLICT "only
  /// a Failed run can be retried"). Null when the last command succeeded.
  final String? lastError;

  const OpsCommandState({this.busyRunIds = const {}, this.lastError});

  bool isBusy(String runId) => busyRunIds.contains(runId);

  OpsCommandState copyWith({Set<String>? busyRunIds, String? lastError}) =>
      OpsCommandState(
        busyRunIds: busyRunIds ?? this.busyRunIds,
        lastError: lastError,
      );
}

/// Issues the three lens commands and reconciles by RE-READING the feed.
///
/// The Swift VM also flips the row optimistically before the POST. That is not
/// ported here on purpose: the optimistic row is a claim the client makes about
/// a state only the lens owns, and this console re-reads within the same tap.
/// What IS ported is the part that matters — the busy set, and the lens's
/// refusal surfaced verbatim rather than swallowed into a silent no-op.
class OpsCommandController extends StateNotifier<OpsCommandState> {
  OpsCommandController(this._lens, this._onChanged)
      : super(const OpsCommandState());

  final LensApi _lens;
  final void Function() _onChanged;

  Future<void> retry(String runId) =>
      _run(runId, () => _lens.retry(runId));

  Future<void> approve(String runId, {String? step}) =>
      _run(runId, () => _lens.approve(runId, step: step));

  Future<void> reject(String runId, {String? step}) =>
      _run(runId, () => _lens.reject(runId, step: step));

  Future<void> _run(String runId, Future<RunSummary> Function() command) async {
    if (state.isBusy(runId)) return;
    state = state.copyWith(busyRunIds: {...state.busyRunIds, runId});
    try {
      await command();
      state = OpsCommandState(
          busyRunIds: {...state.busyRunIds}..remove(runId));
    } on LensApiException catch (e) {
      state = OpsCommandState(
        busyRunIds: {...state.busyRunIds}..remove(runId),
        lastError: e.message,
      );
    } catch (e) {
      state = OpsCommandState(
        busyRunIds: {...state.busyRunIds}..remove(runId),
        lastError: '$e',
      );
    }
    // Reconcile either way: on success the run moved lanes, on failure the
    // truth is whatever the lens still holds.
    _onChanged();
  }
}

final opsCommandProvider =
    StateNotifierProvider<OpsCommandController, OpsCommandState>((ref) {
  return OpsCommandController(
    ref.watch(lensApiProvider),
    () => ref.invalidate(lensRunFeedProvider),
  );
});
