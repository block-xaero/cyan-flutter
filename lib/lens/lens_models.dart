// lens/lens_models.dart
//
// The Dart mirrors of the cyan-lens `/api/v1/runs…` JSON — the port of
// `Models/LensConsole.swift`, field for field and CodingKey for CodingKey.
//
// PHASE-2 D3: the Ops console, Marketplace and Lens AI faces are LENS-HTTP
// backed on the Mac, not FFI. This file is the shape half of that lane; the
// seam itself is `lens/lens_api.dart`.
//
// Two rules the Swift file states and this one keeps:
//
//   • TOLERANT DECODE. A run the lens has not metered yet, or an older lens
//     that predates a field, must still decode. Only IDENTITY is required
//     (`run_id` on a summary, `step_index`/`step_id` on a step record) — a
//     record with no identity is genuinely corrupt and throws, so the caller
//     SURFACES it rather than drawing a blank card. Everything else is
//     read-if-present.
//
//   • THE CONTRACT GUARD. The lens buckets `status → lane` server-side and
//     ships the `lane` with each run. [RunStatusValue.lane] is the client's
//     copy of that mapping, and the console re-buckets the flat run list
//     through it. If the two ever disagree, the contract test fails — that is
//     the whole point of keeping a second copy.
//
// The lens is METADATA-ONLY: asset bytes and previews never route through it.

import 'dart:convert';

// ---------------------------------------------------------------------------
// Lane + status (mirror lens runstore.rs RunLane / RunStatus)
// ---------------------------------------------------------------------------

/// The five named console lanes, left→right in declaration order. The wire
/// values are the snake_case labels the lens emits in each run's `lane`.
enum RunLane { incoming, inFlight, approval, done, failed }

extension RunLaneX on RunLane {
  /// The snake_case label on the wire.
  String get wire => switch (this) {
        RunLane.incoming => 'incoming',
        RunLane.inFlight => 'in_flight',
        RunLane.approval => 'approval',
        RunLane.done => 'done',
        RunLane.failed => 'failed',
      };

  /// The human label the board column header shows.
  String get title => switch (this) {
        RunLane.incoming => 'Incoming',
        RunLane.inFlight => 'In-flight',
        RunLane.approval => 'Approval',
        RunLane.done => 'Done',
        RunLane.failed => 'Failed',
      };

  /// Parse a wire label. An unknown lane is NOT guessed at — the caller falls
  /// back to the status→lane mapping, which is the contract's own answer.
  static RunLane? parse(String? raw) {
    for (final lane in RunLane.values) {
      if (lane.wire == raw) return lane;
    }
    return null;
  }
}

/// The run-level lifecycle status (mirror lens `RunStatus::as_str`). An unknown
/// value never crashes the board: it parks in [unknown], which lanes to
/// In-flight so the run stays VISIBLE rather than silently vanishing.
enum RunStatusValue {
  queued,
  running,
  awaitingApproval,
  stuck,
  done,
  failed,
  unknown,
}

extension RunStatusValueX on RunStatusValue {
  String get wire => switch (this) {
        RunStatusValue.queued => 'Queued',
        RunStatusValue.running => 'Running',
        RunStatusValue.awaitingApproval => 'AwaitingApproval',
        RunStatusValue.stuck => 'Stuck',
        RunStatusValue.done => 'Done',
        RunStatusValue.failed => 'Failed',
        RunStatusValue.unknown => 'unknown',
      };

  /// The status → lane projection. This MIRRORS lens `RunStatus::lane`; the
  /// contract test asserts the console's re-bucketing agrees with the server's
  /// own `lane` field.
  RunLane get lane => switch (this) {
        RunStatusValue.queued => RunLane.incoming,
        RunStatusValue.running => RunLane.inFlight,
        RunStatusValue.stuck => RunLane.inFlight,
        RunStatusValue.awaitingApproval => RunLane.approval,
        RunStatusValue.done => RunLane.done,
        RunStatusValue.failed => RunLane.failed,
        RunStatusValue.unknown => RunLane.inFlight,
      };

  /// A Failed run shows **Retry**.
  bool get canRetry => this == RunStatusValue.failed;

  /// An AwaitingApproval run shows **Approve / Reject**.
  bool get canApprove => this == RunStatusValue.awaitingApproval;

  /// Short, at-rest badge word for the board wall. Distinct from the console's
  /// labels in exactly one place: [unknown] reads "Running", because an
  /// unrecognized status is still a LIVE run (it lanes to In-flight) and "—" on
  /// the wall would read as broken.
  String get badgeLabel => switch (this) {
        RunStatusValue.queued => 'Queued',
        RunStatusValue.running => 'Running',
        RunStatusValue.awaitingApproval => 'Needs approval',
        RunStatusValue.stuck => 'Stuck',
        RunStatusValue.done => 'Done',
        RunStatusValue.failed => 'Failed',
        RunStatusValue.unknown => 'Running',
      };

  static RunStatusValue parse(Object? raw) {
    for (final s in RunStatusValue.values) {
      if (s != RunStatusValue.unknown && s.wire == raw) return s;
    }
    return RunStatusValue.unknown;
  }
}

// ---------------------------------------------------------------------------
// Decode helpers — tolerant by design
// ---------------------------------------------------------------------------

/// A record the lens served that this client cannot make sense of. Thrown ONLY
/// for missing identity; every metric is optional.
class LensDecodeException implements Exception {
  final String message;
  const LensDecodeException(this.message);

  @override
  String toString() => 'LensDecodeException: $message';
}

int? _optInt(Object? v) {
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) return int.tryParse(v);
  return null;
}

double? _optDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

String? _optString(Object? v) {
  if (v is String) return v.isEmpty ? null : v;
  return null;
}

bool? _optBool(Object? v) => v is bool ? v : null;

List<Map<String, dynamic>> _objects(Object? v) => [
      for (final e in (v as List<dynamic>? ?? const []))
        if (e is Map<String, dynamic>) e,
    ];

// ---------------------------------------------------------------------------
// RunStepDetail — the §3 per-step execution record
// ---------------------------------------------------------------------------

/// One step rail. A full (traced) step carries the cost rails + trace status; a
/// state-only (materialized, not-yet-traced) step carries just the operational
/// flags with zeroed cost — so EVERY field beyond the index/id is optional and
/// the rail renders for both.
class RunStepDetail {
  final int stepIndex;
  final String stepId;
  final String? action;
  final String? actor;

  /// The raw trace status string (e.g. "ok"); the operational state is
  /// [stepStatus].
  final String? status;

  /// The run-state status: Pending / Running / Done / Failed / Skipped.
  final String? stepStatus;
  final int? attempt;
  final bool? idempotentSkipped;
  final String? idempotencyKey;
  final int? retry;
  final String? errorClass;
  final int? tokensIn;
  final int? tokensOut;
  final int? gpuMs;
  final double? gpuSeconds;
  final double? gpuCostCents;
  final int? costCents;
  final int? startedAt;
  final int? finishedAt;

  /// Compute wall for THIS step (finished−started, ms).
  final int? wallMs;

  // §3 metering — the canonical per-step-execution record.
  /// Duration of media THIS step processed — the BILLABLE unit.
  final double? assetMinutes;

  /// What it bills the customer (0 for a cache hit / a step that never ran).
  final double? billedMinutes;
  final double? billedCents;

  /// Processing time (COGS == compute wall, NOT billed).
  final int? execMs;

  /// Human latency queued/gate→decision — the efficiency rail's gate-stall
  /// signal.
  final int? approvalWaitMs;

  /// Result reused, billed 0.
  final bool? cacheHit;

  const RunStepDetail({
    required this.stepIndex,
    required this.stepId,
    this.action,
    this.actor,
    this.status,
    this.stepStatus,
    this.attempt,
    this.idempotentSkipped,
    this.idempotencyKey,
    this.retry,
    this.errorClass,
    this.tokensIn,
    this.tokensOut,
    this.gpuMs,
    this.gpuSeconds,
    this.gpuCostCents,
    this.costCents,
    this.startedAt,
    this.finishedAt,
    this.wallMs,
    this.assetMinutes,
    this.billedMinutes,
    this.billedCents,
    this.execMs,
    this.approvalWaitMs,
    this.cacheHit,
  });

  /// Decode a §3 record from BOTH `/runs/{id}` (the trace) and the `/runs`
  /// feed's nested `steps[]`.
  ///
  /// TOLERANT BY DESIGN, and one field earns a special mention: the lens emits
  /// `retry` as a JSON **bool** (the §3 retry flag), while an older lens
  /// modelled it as an **int** count. On the Swift side that type mismatch
  /// threw the ENTIRE `RunTrace` decode, so the drill-down spun forever. Accept
  /// either — bool → 1/0, int as-is — and never throw on the type.
  factory RunStepDetail.fromJson(Map<String, dynamic> j) {
    final index = _optInt(j['step_index']);
    final id = j['step_id'];
    if (index == null || id is! String || id.isEmpty) {
      throw LensDecodeException(
          'a step record carries no identity (step_index/step_id): $j');
    }
    final rawRetry = j['retry'];
    return RunStepDetail(
      stepIndex: index,
      stepId: id,
      action: _optString(j['action']),
      actor: _optString(j['actor']),
      status: _optString(j['status']),
      stepStatus: _optString(j['step_status']),
      attempt: _optInt(j['attempt']),
      idempotentSkipped: _optBool(j['idempotent_skipped']),
      idempotencyKey: _optString(j['idempotency_key']),
      retry: rawRetry is bool ? (rawRetry ? 1 : 0) : _optInt(rawRetry),
      errorClass: _optString(j['error_class']),
      tokensIn: _optInt(j['tokens_in']),
      tokensOut: _optInt(j['tokens_out']),
      gpuMs: _optInt(j['gpu_ms']),
      gpuSeconds: _optDouble(j['gpu_seconds']),
      gpuCostCents: _optDouble(j['gpu_cost_cents']),
      costCents: _optInt(j['cost_cents']),
      startedAt: _optInt(j['started_at']),
      finishedAt: _optInt(j['finished_at']),
      wallMs: _optInt(j['wall_ms']),
      assetMinutes: _optDouble(j['asset_minutes']),
      billedMinutes: _optDouble(j['billed_minutes']),
      billedCents: _optDouble(j['billed_cents']),
      execMs: _optInt(j['exec_ms']),
      approvalWaitMs: _optInt(j['approval_wait_ms']),
      cacheHit: _optBool(j['cache_hit']),
    );
  }

  /// The operational state the rail badges on — `step_status` if present, else
  /// the raw trace status, else "—".
  String get displayStatus => stepStatus ?? status ?? '—';

  /// Compute wall in ms — the served `wall_ms`, else finished−started
  /// (compute-only; a step that never started or finished has no wall).
  int? get wallMsComputed {
    final w = wallMs;
    if (w != null && w > 0) return w;
    final s = startedAt, f = finishedAt;
    if (s == null || f == null || f <= s) return null;
    return f - s;
  }

  /// Processing time (§3 `exec_ms` = COGS) — the served value, else the wall.
  /// The efficiency rail's step-speed (p95) sample.
  int? get execMsComputed {
    final e = execMs;
    if (e != null && e > 0) return e;
    return wallMsComputed;
  }

  /// Did this step reuse a cached result (billed 0)? The served `cache_hit`,
  /// else inferred from the idempotent-skip / Skipped state the lens emits.
  bool get isCacheHit =>
      cacheHit ?? (idempotentSkipped == true || stepStatus == 'Skipped');

  /// Did this step genuinely FAIL? Keyed on the operational status only —
  /// `error_class` alone can be a non-failure label (idempotent / awaiting).
  bool get isFailure => (stepStatus ?? status ?? '').toLowerCase() == 'failed';

  /// Did this step re-process?
  bool get isRetry => (attempt ?? 1) > 1 || (retry ?? 0) > 0;

  /// Billed media-minutes (0 on a cache hit), null when unmetered.
  double? get billedMinutesValue {
    if (billedMinutes != null) return billedMinutes;
    if (isCacheHit) return 0;
    return null;
  }
}

// ---------------------------------------------------------------------------
// RunSummary — one lane card (mirror `run_summary_json`)
// ---------------------------------------------------------------------------

/// The flat run-level summary each lane card binds to (one `workflow_runs`
/// row). `status` and `lane` ride side by side so the client never has to
/// re-derive the mapping — but the console still re-buckets through
/// `status.lane` as a contract check.
class RunSummary {
  final String runId;
  final String tenantId;
  final String boardId;
  final RunStatusValue status;

  /// The lane the SERVER put this run in. Null when the lens omitted it — the
  /// console then falls back to `status.lane`, and the contract test is what
  /// notices if the two ever disagree.
  final RunLane? lane;
  final int stepCount;
  final int currentStepIndex;
  final int attempts;
  final int createdAt;
  final int? startedAt;
  final int updatedAt;
  final int? finishedAt;
  final String? errorClass;
  final int? deadlineAt;

  /// Per-run metering served on the SUMMARY so a lane card shows cost without
  /// drilling the trace. Optional — a freshly-Queued run can omit them.
  final double? gpuSeconds;
  final double? costCents;

  /// The asset filename the run processed. Builds the thumbnail URL; null → the
  /// cinematic poster.
  final String? asset;

  // The WORKFLOW-level progress + compute wall the backend agent stamps.
  /// Done AUTHORED steps of the board — not the run-level "1/1".
  final int? stepDone;
  final int? stepTotal;

  /// Compute-only (finished−started), the workflow-minute source.
  final int? wallMs;

  // §2/§4 asset-minute meter — the CUSTOMER's bill is MEDIA-MINUTES, never GPU.
  final double? billedMinutes;
  final double? billedCents;

  /// The billed-and-FLAGGED re-work (§2 retry policy).
  final double? retryMinutes;

  /// Minutes a cache hit avoided billing (§5).
  final double? cacheSavedMinutes;

  /// The §3 per-step records the lens nests INSIDE each run on the `/runs`
  /// feed. Carrying them on the summary lets Cost + Efficiency roll up from the
  /// ONE feed call — no per-run `/runs/{id}` fetch.
  final List<RunStepDetail>? steps;

  const RunSummary({
    required this.runId,
    this.tenantId = '',
    this.boardId = '',
    this.status = RunStatusValue.unknown,
    this.lane,
    this.stepCount = 0,
    this.currentStepIndex = 0,
    this.attempts = 0,
    this.createdAt = 0,
    this.startedAt,
    this.updatedAt = 0,
    this.finishedAt,
    this.errorClass,
    this.deadlineAt,
    this.gpuSeconds,
    this.costCents,
    this.asset,
    this.stepDone,
    this.stepTotal,
    this.wallMs,
    this.billedMinutes,
    this.billedCents,
    this.retryMinutes,
    this.cacheSavedMinutes,
    this.steps,
  });

  factory RunSummary.fromJson(Map<String, dynamic> j) {
    final id = j['run_id'];
    if (id is! String || id.isEmpty) {
      throw LensDecodeException('a run summary carries no run_id: $j');
    }
    final rawSteps = j['steps'];
    return RunSummary(
      runId: id,
      tenantId: j['tenant_id'] as String? ?? '',
      boardId: j['board_id'] as String? ?? '',
      status: RunStatusValueX.parse(j['status']),
      lane: RunLaneX.parse(j['lane'] as String?),
      stepCount: _optInt(j['step_count']) ?? 0,
      currentStepIndex: _optInt(j['current_step_index']) ?? 0,
      attempts: _optInt(j['attempts']) ?? 0,
      createdAt: _optInt(j['created_at']) ?? 0,
      startedAt: _optInt(j['started_at']),
      updatedAt: _optInt(j['updated_at']) ?? 0,
      finishedAt: _optInt(j['finished_at']),
      errorClass: _optString(j['error_class']),
      deadlineAt: _optInt(j['deadline_at']),
      gpuSeconds: _optDouble(j['gpu_seconds']),
      costCents: _optDouble(j['cost_cents']),
      asset: _optString(j['asset']),
      stepDone: _optInt(j['step_done']),
      stepTotal: _optInt(j['step_total']),
      wallMs: _optInt(j['wall_ms']),
      billedMinutes: _optDouble(j['billed_minutes']),
      billedCents: _optDouble(j['billed_cents']),
      retryMinutes: _optDouble(j['retry_minutes']),
      cacheSavedMinutes: _optDouble(j['cache_saved_minutes']),
      steps: rawSteps == null
          ? null
          : [for (final s in _objects(rawSteps)) RunStepDetail.fromJson(s)],
    );
  }

  /// The lane this run belongs in: the SERVER's answer when it gave one, else
  /// the client's mapping. Reading it through here is what lets the contract
  /// test compare the two.
  RunLane get effectiveLane => lane ?? status.lane;

  // ---- derived display helpers (views read these — no recompute in a view) --

  /// Wall-clock duration in SECONDS, only for FINISHED runs. The timestamps are
  /// epoch-MILLISECONDS, so divide by 1000 — treating ms as seconds was the
  /// 1109:35 garbage. A non-finished run returns null → the card shows "—".
  double? get durationSeconds {
    final fin = finishedAt;
    if (fin == null) return null;
    final start = startedAt ?? createdAt;
    final d = (fin - start) / 1000.0;
    return d > 0 ? d : null;
  }

  /// `m:ss` timecode for the duration badge; "—" when unknown.
  String get durationTimecode {
    final s = durationSeconds;
    if (s == null || s <= 0) return '—';
    final total = s.round();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  /// `$0.00` spend string for this run; "—" when unmetered.
  String get costDollars {
    final c = costCents;
    return c == null ? '—' : '\$${(c / 100.0).toStringAsFixed(2)}';
  }

  /// True once the lens has metered this run on the asset-minute meter.
  bool get hasAssetMeter => billedMinutes != null;

  /// Billed media-minutes, rounded for display; "—" when unmetered.
  String get billedMinutesLabel {
    final m = billedMinutes;
    if (m == null) return '—';
    return m >= 10 ? m.toStringAsFixed(0) : m.toStringAsFixed(1);
  }

  /// `$0.00` billed (asset-minute meter); null when unmetered so a caller can
  /// fall back. NEVER GPU cost — that is internal COGS only.
  String? get billedDollars {
    final c = billedCents;
    return c == null ? null : '\$${(c / 100.0).toStringAsFixed(2)}';
  }

  /// This run includes retried (billed + flagged) minutes.
  bool get isRetryFlagged => (retryMinutes ?? 0) > 0 || attempts > 1;

  /// A cache hit on this run avoided billing some minutes.
  bool get hasCacheSavings => (cacheSavedMinutes ?? 0) > 0;

  /// The `/api/v1/media/thumbnail` URL for this run's asset, or null → the
  /// poster fallback.
  Uri? thumbnailUrl(String lensBase) {
    final a = asset;
    if (a == null || a.isEmpty) return null;
    return Uri.parse(
        '$lensBase/api/v1/media/thumbnail?asset=${Uri.encodeQueryComponent(a)}');
  }

  // ---- optimistic transitions (mirror the lens command effects) ------------

  /// The optimistic shape after a retry/approve re-enqueue (`→ Queued`,
  /// terminal markers cleared) — mirrors lens `retry_run` / `approve`.
  RunSummary asQueued() => _copy(
        status: RunStatusValue.queued,
        lane: RunLane.incoming,
        clearFinished: true,
        clearErrorClass: true,
      );

  /// The optimistic shape after a reject (`→ Failed`, `error_class`).
  RunSummary asFailed({required String errorClass}) => _copy(
        status: RunStatusValue.failed,
        lane: RunLane.failed,
        errorClass: errorClass,
      );

  RunSummary _copy({
    RunStatusValue? status,
    RunLane? lane,
    String? errorClass,
    bool clearFinished = false,
    bool clearErrorClass = false,
  }) =>
      RunSummary(
        runId: runId,
        tenantId: tenantId,
        boardId: boardId,
        status: status ?? this.status,
        lane: lane ?? this.lane,
        stepCount: stepCount,
        currentStepIndex: currentStepIndex,
        attempts: attempts,
        createdAt: createdAt,
        startedAt: startedAt,
        updatedAt: updatedAt,
        finishedAt: clearFinished ? null : finishedAt,
        errorClass: clearErrorClass ? null : (errorClass ?? this.errorClass),
        deadlineAt: deadlineAt,
        gpuSeconds: gpuSeconds,
        costCents: costCents,
        asset: asset,
        stepDone: stepDone,
        stepTotal: stepTotal,
        wallMs: wallMs,
        billedMinutes: billedMinutes,
        billedCents: billedCents,
        retryMinutes: retryMinutes,
        cacheSavedMinutes: cacheSavedMinutes,
        steps: steps,
      );
}

// ---------------------------------------------------------------------------
// RunBoardFeed — the 4-lane payload (mirror `list_runs`)
// ---------------------------------------------------------------------------

/// The per-lane run counts the lens serves. These are AUTHORITATIVE over the
/// loaded cards: the feed is capped by `limit`, the counts are not.
class LaneCounts {
  final int incoming;
  final int inFlight;
  final int approval;
  final int done;
  final int failed;

  /// The lens's own action-needed total. Null on an older lens — the console
  /// falls back to summing the lanes.
  final int? actionNeeded;

  const LaneCounts({
    this.incoming = 0,
    this.inFlight = 0,
    this.approval = 0,
    this.done = 0,
    this.failed = 0,
    this.actionNeeded,
  });

  factory LaneCounts.fromJson(Map<String, dynamic> j) => LaneCounts(
        incoming: _optInt(j['incoming']) ?? 0,
        inFlight: _optInt(j['in_flight']) ?? 0,
        approval: _optInt(j['approval']) ?? 0,
        done: _optInt(j['done']) ?? 0,
        failed: _optInt(j['failed']) ?? 0,
        actionNeeded: _optInt(j['action_needed']),
      );
}

/// `GET /api/v1/runs?board=&status=&limit=` — the tenant-scoped board feed,
/// runs pre-bucketed into the five lanes (newest-heartbeat first within each).
class RunBoardFeed {
  final String boardId;
  final List<RunSummary> incoming;
  final List<RunSummary> inFlight;
  final List<RunSummary> approval;
  final List<RunSummary> done;
  final List<RunSummary> failed;
  final LaneCounts counts;
  final int total;

  /// The flat action-needed run list the lens computes feed-side.
  final List<RunSummary>? actionNeeded;
  final String? currentAsset;
  final String? nextAsset;

  const RunBoardFeed({
    this.boardId = '',
    this.incoming = const [],
    this.inFlight = const [],
    this.approval = const [],
    this.done = const [],
    this.failed = const [],
    this.counts = const LaneCounts(),
    this.total = 0,
    this.actionNeeded,
    this.currentAsset,
    this.nextAsset,
  });

  static const RunBoardFeed empty = RunBoardFeed();

  factory RunBoardFeed.fromJson(Map<String, dynamic> j) {
    final lanes = j['lanes'] as Map<String, dynamic>? ?? const {};
    List<RunSummary> lane(String key) =>
        [for (final r in _objects(lanes[key])) RunSummary.fromJson(r)];
    final an = j['action_needed'];
    return RunBoardFeed(
      boardId: j['board_id'] as String? ?? '',
      incoming: lane('incoming'),
      inFlight: lane('in_flight'),
      approval: lane('approval'),
      done: lane('done'),
      failed: lane('failed'),
      counts:
          LaneCounts.fromJson(j['counts'] as Map<String, dynamic>? ?? const {}),
      total: _optInt(j['total']) ?? 0,
      actionNeeded: an == null
          ? null
          : [for (final r in _objects(an)) RunSummary.fromJson(r)],
      currentAsset: _optString(j['current_asset']),
      nextAsset: _optString(j['next_asset']),
    );
  }

  List<RunSummary> runsIn(RunLane lane) => switch (lane) {
        RunLane.incoming => incoming,
        RunLane.inFlight => inFlight,
        RunLane.approval => approval,
        RunLane.done => done,
        RunLane.failed => failed,
      };

  /// Every run in the feed, lane order preserved — the flat list the console
  /// re-buckets through the client's `status → lane` mapping.
  List<RunSummary> get allRuns =>
      [...incoming, ...inFlight, ...approval, ...done, ...failed];

  /// The runs awaiting a human gate. Prefers the contract's top-level
  /// `action_needed[]`; falls back to the approval lane.
  List<RunSummary> get approvalRuns {
    final an = actionNeeded;
    if (an != null && an.isNotEmpty) {
      return [
        for (final r in an)
          if (r.status.canApprove) r
      ];
    }
    return approval;
  }

  /// The board's most operator-relevant run: a human gate first, then work in
  /// flight, then a failure, then queued, then history.
  RunSummary? get leadRun {
    for (final lane in [approval, inFlight, failed, incoming, done]) {
      if (lane.isNotEmpty) return lane.first;
    }
    return null;
  }

  /// WORKFLOW-level authored-step progress for the board — NOT a single run's
  /// "1/1". Prefers the backend's per-run `step_done`/`step_total`; falls back
  /// to deriving from the run set when those fields are not served yet.
  ({int done, int total}) get workflowSteps {
    final runs = allRuns;
    final totals = [
      for (final r in runs)
        if (r.stepTotal != null) r.stepTotal!
    ];
    if (totals.isNotEmpty) {
      final total = totals.reduce((a, b) => a > b ? a : b);
      if (total > 0) {
        final dones = [
          for (final r in runs)
            if (r.stepDone != null) r.stepDone!
        ];
        final d =
            dones.isEmpty ? done.length : dones.reduce((a, b) => a > b ? a : b);
        return (done: d.clamp(0, total), total: total);
      }
    }
    // Fallback: one unique run per authored step ⇒ total = run count.
    final total = runs.length > done.length ? runs.length : done.length;
    return (done: done.length, total: total);
  }

  /// Build a feed from a flat run list by bucketing through `status.lane` — the
  /// same mapping the console uses. Seeds per-board state from a tenant-wide
  /// feed so a card shows its action-needed pill without a per-board fetch.
  static RunBoardFeed assembled(
      {required String boardId, required List<RunSummary> runs}) {
    final inc = <RunSummary>[],
        fly = <RunSummary>[],
        ap = <RunSummary>[],
        dn = <RunSummary>[],
        fl = <RunSummary>[];
    for (final r in runs) {
      switch (r.status.lane) {
        case RunLane.incoming:
          inc.add(r);
        case RunLane.inFlight:
          fly.add(r);
        case RunLane.approval:
          ap.add(r);
        case RunLane.done:
          dn.add(r);
        case RunLane.failed:
          fl.add(r);
      }
    }
    return RunBoardFeed(
      boardId: boardId,
      incoming: inc,
      inFlight: fly,
      approval: ap,
      done: dn,
      failed: fl,
      counts: LaneCounts(
        incoming: inc.length,
        inFlight: fly.length,
        approval: ap.length,
        done: dn.length,
        failed: fl.length,
      ),
      total: runs.length,
      actionNeeded: ap,
    );
  }
}

// ---------------------------------------------------------------------------
// BoardRunState — the board wall's honest at-rest run state
// ---------------------------------------------------------------------------

/// What a board card says about its runs AT REST.
///
/// THE LOAD-BEARING DISTINCTION: a null feed is NOT zero runs. A feed is only
/// cached once a lens fetch SUCCEEDS, so null means "never seeded, or the lens
/// is down" — claiming "No runs yet" there would repaint the whole wall as
/// empty during a lens outage. Only a feed that actually ARRIVED and is empty
/// earns "No runs yet".
sealed class BoardRunState {
  const BoardRunState();

  /// No feed for this board — never seeded, or the lens is down. Claim NOTHING.
  const factory BoardRunState.unknown() = BoardRunUnknown;

  /// The feed arrived and is genuinely empty.
  const factory BoardRunState.noRuns() = BoardRunNone;

  /// The board has runs; carries the lead run's status.
  const factory BoardRunState.active(RunStatusValue status) = BoardRunActive;

  factory BoardRunState.fromFeed(RunBoardFeed? feed) {
    if (feed == null) return const BoardRunUnknown();
    final lead = feed.leadRun;
    if (feed.total <= 0 || lead == null) return const BoardRunNone();
    return BoardRunActive(lead.status);
  }

  /// The at-rest badge text. Null ⇒ render NO badge (never invent a claim for
  /// [BoardRunUnknown]).
  String? get label => switch (this) {
        BoardRunUnknown() => null,
        BoardRunNone() => 'No runs yet',
        BoardRunActive(:final status) => status.badgeLabel,
      };
}

class BoardRunUnknown extends BoardRunState {
  const BoardRunUnknown();
}

class BoardRunNone extends BoardRunState {
  const BoardRunNone();
}

class BoardRunActive extends BoardRunState {
  final RunStatusValue status;
  const BoardRunActive(this.status);
}

// ---------------------------------------------------------------------------
// RunTrace — the drill-down (mirror `run_trace_json`)
// ---------------------------------------------------------------------------

/// `GET /api/v1/runs/{id}` — run-level state + per-step rails with the
/// operational flags and the cost rails. Every field a freshly-Queued
/// (state-only) run can omit is optional.
class RunTrace {
  final String runId;
  final String tenantId;
  final RunStatusValue? status;
  final RunLane? lane;
  final int? attempts;
  final int? currentStepIndex;
  final int? createdAt;
  final int? startedAt;
  final int? updatedAt;
  final int? finishedAt;
  final String? runErrorClass;
  final int? deadlineAt;
  final List<RunStepDetail> steps;
  final int stepCount;
  final int totalTokensIn;
  final int totalTokensOut;
  final int totalGpuMs;
  final double totalGpuSeconds;
  final double totalGpuCostCents;
  final double totalGpuPriceCents;
  final int totalCostCents;
  final double totalPriceCents;

  /// The slowest/most-expensive GPU step the mini-dashboard highlights.
  final int? bottleneckStepIndex;

  /// §4 run-level billed rollups the lens reconciles from the step records
  /// (invariant: Σ step billed == run billed).
  final double? totalBilledMinutes;
  final double? totalBilledCents;

  const RunTrace({
    required this.runId,
    this.tenantId = '',
    this.status,
    this.lane,
    this.attempts,
    this.currentStepIndex,
    this.createdAt,
    this.startedAt,
    this.updatedAt,
    this.finishedAt,
    this.runErrorClass,
    this.deadlineAt,
    this.steps = const [],
    this.stepCount = 0,
    this.totalTokensIn = 0,
    this.totalTokensOut = 0,
    this.totalGpuMs = 0,
    this.totalGpuSeconds = 0,
    this.totalGpuCostCents = 0,
    this.totalGpuPriceCents = 0,
    this.totalCostCents = 0,
    this.totalPriceCents = 0,
    this.bottleneckStepIndex,
    this.totalBilledMinutes,
    this.totalBilledCents,
  });

  factory RunTrace.fromJson(Map<String, dynamic> j) {
    final id = j['run_id'];
    if (id is! String || id.isEmpty) {
      throw LensDecodeException('a run trace carries no run_id: $j');
    }
    return RunTrace(
      runId: id,
      tenantId: j['tenant_id'] as String? ?? '',
      status: j['status'] == null ? null : RunStatusValueX.parse(j['status']),
      lane: RunLaneX.parse(j['lane'] as String?),
      attempts: _optInt(j['attempts']),
      currentStepIndex: _optInt(j['current_step_index']),
      createdAt: _optInt(j['created_at']),
      startedAt: _optInt(j['started_at']),
      updatedAt: _optInt(j['updated_at']),
      finishedAt: _optInt(j['finished_at']),
      runErrorClass: _optString(j['run_error_class']),
      deadlineAt: _optInt(j['deadline_at']),
      steps: [for (final s in _objects(j['steps'])) RunStepDetail.fromJson(s)],
      stepCount: _optInt(j['step_count']) ?? 0,
      totalTokensIn: _optInt(j['total_tokens_in']) ?? 0,
      totalTokensOut: _optInt(j['total_tokens_out']) ?? 0,
      totalGpuMs: _optInt(j['total_gpu_ms']) ?? 0,
      totalGpuSeconds: _optDouble(j['total_gpu_seconds']) ?? 0,
      totalGpuCostCents: _optDouble(j['total_gpu_cost_cents']) ?? 0,
      totalGpuPriceCents: _optDouble(j['total_gpu_price_cents']) ?? 0,
      totalCostCents: _optInt(j['total_cost_cents']) ?? 0,
      totalPriceCents: _optDouble(j['total_price_cents']) ?? 0,
      bottleneckStepIndex: _optInt(j['bottleneck_step_index']),
      totalBilledMinutes: _optDouble(j['total_billed_minutes']),
      totalBilledCents: _optDouble(j['total_billed_cents']),
    );
  }

  /// The step the lens flagged as the bottleneck, if any.
  RunStepDetail? get bottleneckStep {
    final idx = bottleneckStepIndex;
    if (idx == null) return null;
    for (final s in steps) {
      if (s.stepIndex == idx) return s;
    }
    return null;
  }

  /// Billed media-minutes for the run — the served total, else Σ over the step
  /// records (§4 invariant). Null → no step metered ("—").
  double? get billedMinutesRollup {
    final t = totalBilledMinutes;
    if (t != null) return t;
    final vals = [
      for (final s in steps)
        if (s.billedMinutesValue != null) s.billedMinutesValue!
    ];
    return vals.isEmpty ? null : vals.reduce((a, b) => a + b);
  }

  /// Billed cents for the run — the served total, else Σ over the step records.
  double? get billedCentsRollup {
    final t = totalBilledCents;
    if (t != null) return t;
    final vals = [
      for (final s in steps)
        if (s.billedCents != null) s.billedCents!
    ];
    return vals.isEmpty ? null : vals.reduce((a, b) => a + b);
  }

  /// `$0.00` billed for the run; null when no step is metered.
  String? get billedDollarsRollup {
    final c = billedCentsRollup;
    return c == null ? null : '\$${(c / 100.0).toStringAsFixed(2)}';
  }
}

// ---------------------------------------------------------------------------
// Command replies (retry / approve — mirror `retry_run` / `approve_run`)
// ---------------------------------------------------------------------------

/// The approve/reject decision sent to the gate. The wire values are the verbs
/// the lens accepts, and they are also the ROUTE.
enum ApprovalDecision { approve, reject }

extension ApprovalDecisionX on ApprovalDecision {
  String get wire => this == ApprovalDecision.approve ? 'approve' : 'reject';
}

/// `POST /api/v1/runs/{id}/retry` reply — `{ success, run }`.
class RetryReply {
  final bool success;
  final RunSummary run;

  const RetryReply({required this.success, required this.run});

  factory RetryReply.fromJson(Map<String, dynamic> j) => RetryReply(
        success: j['success'] == true,
        run: RunSummary.fromJson(
            j['run'] as Map<String, dynamic>? ?? const {'run_id': ''}),
      );
}

/// `POST /api/v1/runs/{id}/approve` reply —
/// `{ success, decision, step_id, step_status, run }`.
class ApproveReply {
  final bool success;
  final String decision;
  final String stepId;
  final String stepStatus;
  final RunSummary run;

  const ApproveReply({
    required this.success,
    this.decision = '',
    this.stepId = '',
    this.stepStatus = '',
    required this.run,
  });

  factory ApproveReply.fromJson(Map<String, dynamic> j) => ApproveReply(
        success: j['success'] == true,
        decision: j['decision'] as String? ?? '',
        stepId: j['step_id'] as String? ?? '',
        stepStatus: j['step_status'] as String? ?? '',
        run: RunSummary.fromJson(
            j['run'] as Map<String, dynamic>? ?? const {'run_id': ''}),
      );
}

// ---------------------------------------------------------------------------
// The lens envelope — `{ success, data, error }`
// ---------------------------------------------------------------------------

/// The lens-cloud endpoints (`/nudges`, `/asks`, `/decisions`, `/health`,
/// `/marketplace/browse`) wrap their payload in `{success, data, error}`. The
/// `/runs` family does NOT — it serves its objects bare.
///
/// WHICH FAMILY AN ENDPOINT IS IN IS DECLARED AT THE CALL SITE, never sniffed.
/// A "does the body contain `success`?" heuristic looks reasonable and is
/// wrong: `POST /runs/{id}/retry` answers `{success, run}` and `/approve`
/// answers `{success, decision, step_id, step_status, run}` — both would be
/// mistaken for the envelope, unwrapped into a null `data`, and every command
/// reply would vanish. That is exactly what happened the first time this was
/// written, and the wire test in `lens_contract_test.dart` is what caught it.
class LensEnvelope {
  /// The payload — the envelope's `data` when there is one, else the whole
  /// body.
  final Object? data;

  /// The envelope's own failure. Null when the body was not an envelope.
  final String? error;
  final bool success;

  const LensEnvelope({this.data, this.error, this.success = true});

  /// Unwrap a body from an endpoint the caller KNOWS is enveloped. Tolerant in
  /// the one safe direction: a body with no `success` key is taken as the bare
  /// payload, so a lens that stops wrapping still decodes. The reverse
  /// tolerance — sniffing a bare body for `success` — is the trap this class
  /// documents; see the note above.
  factory LensEnvelope.of(Object? body) {
    if (body is! Map<String, dynamic> || !body.containsKey('success')) {
      return LensEnvelope(data: body);
    }
    return LensEnvelope(
      data: body['data'],
      error: body['error'] as String?,
      success: body['success'] == true,
    );
  }
}

/// Decode a JSON body, tolerating an empty response.
Object? decodeLensBody(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return null;
  return jsonDecode(trimmed);
}

// ---------------------------------------------------------------------------
// A4 §1b — the NOTES STRUCTURING lane (`POST /api/v1/notes/structure`)
// ---------------------------------------------------------------------------
//
// Freeform text in, TYPED note proposals out. Nothing is persisted by the lens
// call: auto-accept is OFF and every proposal is a suggestion a human must
// confirm, which then writes a real typed note through the engine's own JSON
// door so its RBAC and payload validation still run.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Views/NotesStructuringView.swift

/// One typed-note proposal.
///
/// [payload] is kept as the RAW decoded JSON object so a typed note round-trips
/// verbatim into the write body — the app never reshapes what the lane
/// produced, because reshaping is how a payload stops validating.
class NoteProposal {
  final String proposalId;
  final String kind;

  /// The lane only ever routes `group` or `board`.
  final String scope;
  final String boardId;
  final String text;
  final Map<String, dynamic>? payload;
  final String? originRef;
  final double confidence;
  final String? rationale;

  /// The VERBATIM substring of the operator's own text this came from — the
  /// anti-fabrication quoting gate. A proposal whose span is not in the input
  /// is the model inventing a note.
  final String? sourceSpan;

  const NoteProposal({
    required this.proposalId,
    required this.kind,
    required this.scope,
    required this.boardId,
    required this.text,
    this.payload,
    this.originRef,
    this.confidence = 0,
    this.rationale,
    this.sourceSpan,
  });

  /// Null when the row lacks the three fields that make it a proposal at all —
  /// a half-decoded proposal is dropped rather than shown with blanks.
  static NoteProposal? fromJson(Map<String, dynamic> j) {
    final id = j['proposal_id'];
    final kind = j['kind'];
    final text = j['text'];
    if (id is! String || kind is! String || text is! String) return null;
    return NoteProposal(
      proposalId: id,
      kind: kind,
      scope: j['scope'] is String ? j['scope'] as String : 'board',
      boardId: j['board_id'] is String ? j['board_id'] as String : '',
      text: text,
      payload: j['payload'] is Map
          ? Map<String, dynamic>.from(j['payload'] as Map)
          : null,
      originRef: j['origin_ref'] is String ? j['origin_ref'] as String : null,
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
      rationale: j['rationale'] is String ? j['rationale'] as String : null,
      sourceSpan:
          j['source_span'] is String ? j['source_span'] as String : null,
    );
  }
}

/// A span the lane REFUSED to structure, with the closed reason set
/// (`noise` / `unstructurable` / `invalid_payload_degraded`).
///
/// Surfaced rather than swallowed: the operator sees exactly what was dropped
/// and why, which is the difference between a lane that ignored half your note
/// and one that told you it did.
class RejectedSpan {
  final String span;
  final String reason;

  const RejectedSpan({required this.span, required this.reason});

  static RejectedSpan? fromJson(Map<String, dynamic> j) {
    final span = j['span'];
    final reason = j['reason'];
    if (span is! String || reason is! String) return null;
    return RejectedSpan(span: span, reason: reason);
  }
}

/// What one structuring call answered.
class NoteStructureResult {
  final List<NoteProposal> proposals;
  final List<RejectedSpan> rejected;

  const NoteStructureResult({
    this.proposals = const [],
    this.rejected = const [],
  });

  bool get isEmpty => proposals.isEmpty && rejected.isEmpty;

  factory NoteStructureResult.fromJson(Map<String, dynamic> j) {
    List<T> rows<T>(String key, T? Function(Map<String, dynamic>) decode) {
      final raw = j[key];
      if (raw is! List) return const [];
      final out = <T>[];
      for (final row in raw) {
        if (row is Map) {
          final decoded = decode(Map<String, dynamic>.from(row));
          if (decoded != null) out.add(decoded);
        }
      }
      return out;
    }

    return NoteStructureResult(
      proposals: rows('proposals', NoteProposal.fromJson),
      rejected: rows('rejected', RejectedSpan.fromJson),
    );
  }
}

/// Which structuring lane is driven: a freeform NOTE, or a messy shot-log
/// REPORT import (which the lens types entirely as `shot-log`).
enum NotesLane { note, report }
