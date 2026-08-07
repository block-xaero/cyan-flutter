// lens/lens_rollups.dart
//
// The port of `Models/MeteringRollups.swift` — the §4 billing rollups and the
// §5 efficiency rollups.
//
// THE POINT OF THIS FILE, stated once so nobody re-derives it: Cost and
// Efficiency are NOT endpoints. They are PURE REDUCTIONS of the one canonical
// §3 record the lens already serves on `/api/v1/runs` (each run summary carries
// its `steps[]`). Computing them client-side reconciles BY CONSTRUCTION with a
// server-side rollup — same records, same sum — and needs no per-run
// `/runs/{id}` fetch, which is what the Swift side's "No step traces to roll up
// yet" stall turned out to be.
//
// PARITY_TRACKER listed Ops Cost and Ops Efficiency as "blocked: no engine
// verb". That was true and beside the point: there was never going to BE a
// verb. These two faces are arithmetic over the run feed.
//
// THE DECK'S BILL = ASSET-MINUTES (media-minutes processed), never GPU-seconds.
// GPU/tokens stay INTERNAL cost-of-goods (margin only) and never appear in a
// customer total.

import 'lens_models.dart';

// ---------------------------------------------------------------------------
// §4 Billing rollup — the asset-minute meter
// ---------------------------------------------------------------------------

/// The asset-minute meter rolled up over a set of runs. The scope is whatever
/// set is passed: one run, one board's runs (per-WORKFLOW — a board IS a
/// materialized workflow), or the whole tenant feed (the Ops-console headline).
class AssetMeterRollup {
  final int runCount;

  /// Distinct assets (media files) processed across the runs.
  final int assetCount;

  /// Σ `billed_minutes` — the customer's processed media-minutes.
  final double billedMinutes;

  /// Σ `billed_cents` — the customer's asset-minute bill.
  final double billedCents;

  /// Σ `retry_minutes` — billed-and-FLAGGED re-work (§2 retry policy).
  final double retryMinutes;

  /// Σ `cache_saved_minutes` — minutes a cache hit avoided billing.
  final double cacheSavedMinutes;

  /// True once ANY run in the scope carries the asset-minute meter. Drives
  /// real-meter vs "—" (the backend has not deployed the meter fields yet).
  /// NEVER shows GPU as the bill.
  final bool hasMeter;

  /// INTERNAL cost-of-goods only — our margin, NOT the customer bill. Kept so
  /// the console can still show COGS to an operator, clearly labelled.
  final double gpuSeconds;

  /// Σ compute wall (ms) over SETTLED runs only. Prefers the backend's metered
  /// `wall_ms` (compute-only: finished−started), else the finished run's
  /// wall-clock duration. A non-finished / never-started run contributes 0, so
  /// a long-pending run's elapsed-since-start cannot inflate it — that, plus
  /// ancient seed timestamps, was the absurd 324739-minute figure.
  final int totalWallMs;

  const AssetMeterRollup._({
    required this.runCount,
    required this.assetCount,
    required this.billedMinutes,
    required this.billedCents,
    required this.retryMinutes,
    required this.cacheSavedMinutes,
    required this.hasMeter,
    required this.gpuSeconds,
    required this.totalWallMs,
  });

  static const AssetMeterRollup empty = AssetMeterRollup._(
    runCount: 0,
    assetCount: 0,
    billedMinutes: 0,
    billedCents: 0,
    retryMinutes: 0,
    cacheSavedMinutes: 0,
    hasMeter: false,
    gpuSeconds: 0,
    totalWallMs: 0,
  );

  factory AssetMeterRollup(List<RunSummary> runs) {
    var billedMin = 0.0,
        billedC = 0.0,
        retryMin = 0.0,
        savedMin = 0.0,
        gpu = 0.0;
    var wall = 0;
    var metered = false;
    final assets = <String>{};
    for (final r in runs) {
      final a = r.asset;
      if (a != null && a.isNotEmpty) assets.add(a);
      billedMin += r.billedMinutes ?? 0;
      billedC += r.billedCents ?? 0;
      retryMin += r.retryMinutes ?? 0;
      savedMin += r.cacheSavedMinutes ?? 0;
      gpu += r.gpuSeconds ?? 0;
      if (r.billedMinutes != null) metered = true;

      final ms = r.wallMs;
      if (ms != null && ms > 0) {
        wall += ms;
      } else if (r.finishedAt != null) {
        final d = r.durationSeconds;
        if (d != null && d > 0) wall += (d * 1000).round();
      }
    }
    return AssetMeterRollup._(
      runCount: runs.length,
      assetCount: assets.length,
      billedMinutes: billedMin,
      billedCents: billedC,
      retryMinutes: retryMin,
      cacheSavedMinutes: savedMin,
      hasMeter: metered,
      gpuSeconds: gpu,
      totalWallMs: wall,
    );
  }

  // ---- display helpers (views read these — no recompute in a view) --------

  /// Billed media-minutes; "—" until the backend stamps the meter.
  String get billedMinutesLabel {
    if (!hasMeter) return '—';
    return billedMinutes >= 10
        ? billedMinutes.toStringAsFixed(0)
        : billedMinutes.toStringAsFixed(1);
  }

  /// `$0.00` asset-minute bill; "—" until metered. NEVER GPU cost.
  String get billedDollars =>
      hasMeter ? '\$${(billedCents / 100.0).toStringAsFixed(2)}' : '—';

  /// Flagged retry minutes; "—" when none / unmetered.
  String get retryMinutesLabel {
    if (!hasMeter || retryMinutes <= 0) return '—';
    return retryMinutes >= 10
        ? retryMinutes.toStringAsFixed(0)
        : retryMinutes.toStringAsFixed(1);
  }

  /// Cache-saved minutes; "—" when none / unmetered.
  String get cacheSavedLabel {
    if (!hasMeter || cacheSavedMinutes <= 0) return '—';
    return cacheSavedMinutes >= 10
        ? cacheSavedMinutes.toStringAsFixed(0)
        : cacheSavedMinutes.toStringAsFixed(1);
  }

  /// Workflow-minutes as a fine Double (`totalWallMs / 60000`).
  double get workflowMinutes => totalWallMs / 60000.0;

  /// The workflow-minutes the dashboard SHOWS — `ceil(Σ wall_ms / 60_000)`
  /// applied ONCE at the total, so it reconciles with the lens's analytics
  /// figure instead of per-run rounding that ≈20×-overbilled every sub-minute
  /// run.
  int get workflowMinutesCeil =>
      totalWallMs <= 0 ? 0 : (totalWallMs + 59999) ~/ 60000;

  /// Group a flat run set by board (≡ materialized workflow) → one meter per
  /// workflow, heaviest first.
  static List<WorkflowMeterRow> byWorkflow(List<RunSummary> runs) {
    final groups = <String, List<RunSummary>>{};
    for (final r in runs) {
      (groups[r.boardId] ??= <RunSummary>[]).add(r);
    }
    final rows = [
      for (final e in groups.entries)
        WorkflowMeterRow(boardId: e.key, meter: AssetMeterRollup(e.value))
    ];
    rows.sort((a, b) {
      // Metered workflows first (heaviest billed-minutes), then by run count.
      if (a.meter.billedMinutes != b.meter.billedMinutes) {
        return b.meter.billedMinutes.compareTo(a.meter.billedMinutes);
      }
      return b.meter.runCount.compareTo(a.meter.runCount);
    });
    return rows;
  }
}

/// One row of the §4 per-workflow billing rollup (a board's runs, summed).
class WorkflowMeterRow {
  final String boardId;
  final AssetMeterRollup meter;

  const WorkflowMeterRow({required this.boardId, required this.meter});
}

// ---------------------------------------------------------------------------
// §5 Efficiency rollup
// ---------------------------------------------------------------------------

/// One authored step's efficiency, rolled up over every execution of it across
/// the in-scope runs, keyed by the step's ACTION (its stable authored
/// identity — the step id changes per execution).
///
/// Every figure falls back to fields the lens ALREADY emits (exec↔wall,
/// step_status, attempt), so the view is legible before the new meter fields
/// deploy.
class StepEfficiencyRollup {
  /// The step key (action, else step id).
  final String id;
  final String label;

  /// Sample count across runs.
  final int executions;
  final int? approvalWaitP95Ms;
  final int? execP95Ms;

  /// 0…1.
  final double failureRate;
  final String? topErrorClass;

  /// 0…1.
  final double cacheHitRate;

  /// Σ `asset_minutes` of cache-hit executions.
  final double minutesSaved;

  /// 0…1 share of executions that re-processed.
  final double retryRate;

  const StepEfficiencyRollup({
    required this.id,
    required this.label,
    required this.executions,
    this.approvalWaitP95Ms,
    this.execP95Ms,
    this.failureRate = 0,
    this.topErrorClass,
    this.cacheHitRate = 0,
    this.minutesSaved = 0,
    this.retryRate = 0,
  });

  bool get hasApprovalWait => approvalWaitP95Ms != null;
}

/// The efficiency view's read-model: per-step rollups plus the headline picks
/// an operator reads at a glance.
class EfficiencyRollup {
  final List<StepEfficiencyRollup> steps;
  final int runCount;
  final double totalMinutesSaved;
  final double overallCacheHitRate;
  final double overallRetryRate;
  final double overallFailureRate;

  /// True once ANY step carried a real `approval_wait_ms` (else the gate column
  /// is "—"). The distinction matters: 0ms of gate wait and NO gate data look
  /// identical in a number and are not the same claim.
  final bool hasApprovalData;

  const EfficiencyRollup({
    this.steps = const [],
    this.runCount = 0,
    this.totalMinutesSaved = 0,
    this.overallCacheHitRate = 0,
    this.overallRetryRate = 0,
    this.overallFailureRate = 0,
    this.hasApprovalData = false,
  });

  static const EfficiencyRollup empty = EfficiencyRollup();

  /// Roll up DIRECTLY from the `/runs` feed: each summary already carries its
  /// §3 `steps[]`, so Cost + Efficiency need NO per-run `/runs/{id}` fetch.
  factory EfficiencyRollup.fromRuns(List<RunSummary> runs) =>
      EfficiencyRollup._reduce(
        [for (final r in runs) r.steps ?? const <RunStepDetail>[]],
        runs.length,
      );

  /// Roll up from a set of run TRACES (the drill/hover cache). Reconciles with
  /// the feed-based rollup by construction: the same §3 records, summed.
  factory EfficiencyRollup.fromTraces(List<RunTrace> traces) =>
      EfficiencyRollup._reduce(
        [for (final t in traces) t.steps],
        traces.length,
      );

  /// The ONE reduction both entry points share — group every step execution
  /// across all runs by its authored action, and reduce each group to the §5
  /// p95s and rates.
  factory EfficiencyRollup._reduce(
      List<List<RunStepDetail>> stepGroups, int runCount) {
    final accs = <String, _Acc>{};
    final order = <String>[]; // first-seen order → a stable table

    var allExec = 0, allCache = 0, allRetry = 0, allFail = 0;
    var savedTotal = 0.0;
    var sawApproval = false;

    for (final steps in stepGroups) {
      for (final step in steps) {
        final action = step.action;
        final key = (action != null && action.isNotEmpty) ? action : step.stepId;
        final a = accs.putIfAbsent(key, () {
          order.add(key);
          return _Acc(action ?? step.stepId);
        });
        a.total += 1;
        allExec += 1;

        final e = step.execMsComputed;
        if (e != null && e > 0) a.execSamples.add(e);
        final w = step.approvalWaitMs;
        if (w != null && w >= 0) {
          a.approvalSamples.add(w);
          sawApproval = true;
        }
        if (step.isFailure) {
          a.failures += 1;
          allFail += 1;
          final ec = step.errorClass;
          if (ec != null) a.errorCounts[ec] = (a.errorCounts[ec] ?? 0) + 1;
        }
        if (step.isCacheHit) {
          a.cacheHits += 1;
          allCache += 1;
          final saved = step.assetMinutes ?? 0;
          a.minutesSaved += saved;
          savedTotal += saved;
        }
        if (step.isRetry) {
          a.retries += 1;
          allRetry += 1;
        }
      }
    }

    final rolled = <StepEfficiencyRollup>[];
    for (final key in order) {
      final a = accs[key];
      if (a == null || a.total == 0) continue;
      String? topError;
      var topCount = 0;
      for (final e in a.errorCounts.entries) {
        if (e.value > topCount) {
          topCount = e.value;
          topError = e.key;
        }
      }
      rolled.add(StepEfficiencyRollup(
        id: key,
        label: a.label,
        executions: a.total,
        approvalWaitP95Ms: p95(a.approvalSamples),
        execP95Ms: p95(a.execSamples),
        failureRate: a.failures / a.total,
        topErrorClass: topError,
        cacheHitRate: a.cacheHits / a.total,
        minutesSaved: a.minutesSaved,
        retryRate: a.retries / a.total,
      ));
    }

    return EfficiencyRollup(
      steps: rolled,
      runCount: runCount,
      totalMinutesSaved: savedTotal,
      overallCacheHitRate: allExec > 0 ? allCache / allExec : 0,
      overallRetryRate: allExec > 0 ? allRetry / allExec : 0,
      overallFailureRate: allExec > 0 ? allFail / allExec : 0,
      hasApprovalData: sawApproval,
    );
  }

  /// The step that stalls most on humans (max approval-wait p95).
  StepEfficiencyRollup? get gateBottleneck =>
      _maxBy([for (final s in steps) if (s.approvalWaitP95Ms != null) s],
          (s) => s.approvalWaitP95Ms!.toDouble());

  /// The step that fails most (rate > 0).
  StepEfficiencyRollup? get topFailingStep => _maxBy(
      [for (final s in steps) if (s.failureRate > 0) s], (s) => s.failureRate);

  /// Slowest executing step (by exec p95).
  StepEfficiencyRollup? get slowestStep => _maxBy(
      [for (final s in steps) if (s.execP95Ms != null) s],
      (s) => s.execP95Ms!.toDouble());

  /// Fastest executing step (by exec p95).
  StepEfficiencyRollup? get fastestStep => _maxBy(
      [for (final s in steps) if (s.execP95Ms != null) s],
      (s) => -s.execP95Ms!.toDouble());

  static StepEfficiencyRollup? _maxBy(List<StepEfficiencyRollup> rows,
      double Function(StepEfficiencyRollup) score) {
    StepEfficiencyRollup? best;
    var bestScore = double.negativeInfinity;
    for (final r in rows) {
      final s = score(r);
      if (s > bestScore) {
        bestScore = s;
        best = r;
      }
    }
    return best;
  }

  /// p95 of an Int sample set — NEAREST-RANK, clamped. Null for an empty set.
  static int? p95(List<int> samples) {
    if (samples.isEmpty) return null;
    final sorted = [...samples]..sort();
    final rank = (0.95 * sorted.length).ceil();
    final idx = (rank - 1).clamp(0, sorted.length - 1);
    return sorted[idx];
  }
}

class _Acc {
  _Acc(this.label);

  final String label;
  final List<int> execSamples = [];
  final List<int> approvalSamples = [];
  int total = 0;
  int failures = 0;
  int cacheHits = 0;
  int retries = 0;
  double minutesSaved = 0;
  final Map<String, int> errorCounts = {};
}

// ---------------------------------------------------------------------------
// Shared formatting
// ---------------------------------------------------------------------------

/// The duration/percent formatters the efficiency view shows. One formatter
/// spans both scales on purpose: approval waits run to hours, exec times to
/// milliseconds.
class MeterFormat {
  /// `820ms` · `4.2s` · `6m` · `2.5h`. "—" for null / non-positive.
  static String duration(num? ms) {
    if (ms == null || ms <= 0) return '—';
    final s = ms / 1000.0;
    if (s < 1) return '${ms.round()}ms';
    if (s < 60) return '${s.toStringAsFixed(1)}s';
    final m = s / 60.0;
    if (m < 60) {
      return m < 10 ? '${m.toStringAsFixed(1)}m' : '${m.toStringAsFixed(0)}m';
    }
    return '${(m / 60.0).toStringAsFixed(1)}h';
  }

  /// A 0…1 rate → a `12%` label.
  static String percent(double rate) => '${(rate * 100).toStringAsFixed(0)}%';
}
