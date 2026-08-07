// lens/fake_lens_api.dart
//
// The Tier-1 half of the `LensApi` seam — the mirror of Swift's
// `FakeLensConsoleClient`. Returns scripted feeds and RECORDS every call, so a
// widget test can assert both what the face DREW and what it ASKED FOR.
//
// Two rules this fake keeps, both learned the expensive way on the FFI seam:
//
//   • IT NEVER SHIPS. `FakeLensApi` is injected by tests and by nothing else;
//     the production provider builds `LensApiHttp`. "No mock data in the
//     shipped path" is the same discipline `FakeCyanBackend` follows.
//
//   • IT LIES AS LITTLE AS POSSIBLE. The seeded runs carry the SAME §3 step
//     records the live lens nests in `/runs`, including the metering fields —
//     because Cost and Efficiency are reductions over exactly those records. A
//     fake that seeded pre-computed totals would make the two faces green while
//     proving nothing about the arithmetic they exist to do. That is the class
//     of defect Tier-1 could not see on the FFI seam and it is not being
//     rebuilt here.
//
// The seed is FIXED (no clocks, no randomness) so goldens are deterministic.

import 'lens_api.dart';
import 'lens_models.dart';

/// One recorded call — the method and the arguments the face passed.
class LensCall {
  final String method;
  final Map<String, Object?> args;

  const LensCall(this.method, [this.args = const {}]);

  @override
  String toString() => '$method($args)';
}

/// A scripted [LensApi]. Every read is answerable offline; every write records
/// itself and reconciles the in-memory feed the way the lens would.
class FakeLensApi implements LensApi {
  FakeLensApi({
    List<RunSummary>? runs,
    List<LensPluginCardWire>? cards,
    LensNudgeReport? nudgeReport,
    List<LensAskRow>? askRows,
    List<LensDecisionRow>? decisionRows,
    LensHealth? healthReport,
    this.failWith,
  })  : _runs = [...(runs ?? seededRuns())],
        _cards = [...(cards ?? seededCards())],
        _nudges = nudgeReport ?? seededNudges(),
        _asks = [...(askRows ?? seededAsks())],
        _decisions = [...(decisionRows ?? seededDecisions())],
        _health = healthReport ?? seededHealth();

  /// When set, EVERY call throws this instead of answering — the "the lens is
  /// down" state a face must survive without blanking.
  final LensApiException? failWith;

  final List<RunSummary> _runs;
  final List<LensPluginCardWire> _cards;
  LensNudgeReport _nudges;
  final List<LensAskRow> _asks;
  final List<LensDecisionRow> _decisions;
  final LensHealth _health;

  /// Every call, in order.
  final List<LensCall> calls = [];

  /// The ask ids answered / dismissed through this fake.
  final Map<String, String> answered = {};
  final Set<String> dismissed = {};
  final List<String> resolvedBlockers = [];
  final Map<String, String> reactions = {};

  LensCall get lastCall => calls.last;

  void _record(String method, [Map<String, Object?> args = const {}]) {
    calls.add(LensCall(method, args));
    final f = failWith;
    if (f != null) throw f;
  }

  RunSummary? _find(String id) {
    for (final r in _runs) {
      if (r.runId == id) return r;
    }
    return null;
  }

  void _replace(RunSummary updated) {
    for (var i = 0; i < _runs.length; i++) {
      if (_runs[i].runId == updated.runId) {
        _runs[i] = updated;
        return;
      }
    }
  }

  // ---- Ops console --------------------------------------------------------

  @override
  Future<RunBoardFeed> runs(
      {String? board, RunStatusValue? status, int limit = 50}) async {
    _record('runs', {'board': board, 'status': status?.wire, 'limit': limit});
    var rows = board == null || board.isEmpty
        ? _runs
        : [for (final r in _runs) if (r.boardId == board) r];
    if (status != null && status != RunStatusValue.unknown) {
      rows = [for (final r in rows) if (r.status == status) r];
    }
    if (rows.length > limit) rows = rows.sublist(0, limit);
    return RunBoardFeed.assembled(boardId: board ?? '', runs: rows);
  }

  @override
  Future<RunTrace> run(String id) async {
    _record('run', {'id': id});
    final summary = _find(id);
    if (summary == null) {
      throw LensApiException('no such run: $id', statusCode: 404);
    }
    final steps = summary.steps ?? const <RunStepDetail>[];
    // The bottleneck is the slowest EXECUTED step — derived, never seeded, so
    // the drill's highlight is the same arithmetic the console does.
    int? bottleneck;
    var slowest = -1;
    for (final s in steps) {
      final e = s.execMsComputed ?? 0;
      if (e > slowest) {
        slowest = e;
        bottleneck = s.stepIndex;
      }
    }
    return RunTrace(
      runId: summary.runId,
      tenantId: summary.tenantId,
      status: summary.status,
      lane: summary.effectiveLane,
      attempts: summary.attempts,
      currentStepIndex: summary.currentStepIndex,
      createdAt: summary.createdAt,
      startedAt: summary.startedAt,
      updatedAt: summary.updatedAt,
      finishedAt: summary.finishedAt,
      runErrorClass: summary.errorClass,
      steps: steps,
      stepCount: steps.length,
      totalGpuSeconds: summary.gpuSeconds ?? 0,
      totalCostCents: (summary.costCents ?? 0).round(),
      bottleneckStepIndex: bottleneck,
      totalBilledMinutes: summary.billedMinutes,
      totalBilledCents: summary.billedCents,
    );
  }

  @override
  Future<RunSummary> retry(String id) async {
    _record('retry', {'id': id});
    final run = _find(id);
    if (run == null) throw LensApiException('no such run: $id');
    // The lens refuses a retry on anything but a Failed run, and says so in
    // plain text. Mirrored, because a face that never sees the refusal cannot
    // be shown to handle it.
    if (!run.status.canRetry) {
      throw const LensApiException('CONFLICT only a Failed run can be retried',
          statusCode: 409);
    }
    final updated = run.asQueued();
    _replace(updated);
    return updated;
  }

  @override
  Future<RunSummary> approve(String id, {String? step}) async {
    _record('approve', {'id': id, 'step': step});
    return _gate(id, ApprovalDecision.approve);
  }

  @override
  Future<RunSummary> reject(String id, {String? step}) async {
    _record('reject', {'id': id, 'step': step});
    return _gate(id, ApprovalDecision.reject);
  }

  RunSummary _gate(String id, ApprovalDecision decision) {
    final run = _find(id);
    if (run == null) throw LensApiException('no such run: $id');
    if (!run.status.canApprove) {
      throw const LensApiException(
          'CONFLICT that run is not parked at a gate',
          statusCode: 409);
    }
    final updated = decision == ApprovalDecision.approve
        ? run.asQueued()
        : run.asFailed(errorClass: 'rejected');
    _replace(updated);
    return updated;
  }

  // ---- Marketplace --------------------------------------------------------

  @override
  Future<List<LensPluginCardWire>> browseMarketplace(
      StorefrontQuery query) async {
    _record('browseMarketplace', {
      'q': query.text,
      'aisle': query.aisle,
      'publisher': query.publisher,
      'limit': query.limit,
    });
    var rows = _cards;
    final q = query.text?.trim().toLowerCase();
    if (q != null && q.isNotEmpty) {
      rows = [
        for (final c in rows)
          if ('${c.pluginId} ${c.name ?? ''} ${c.description ?? ''}'
              .toLowerCase()
              .contains(q))
            c
      ];
    }
    final aisle = query.aisle;
    if (aisle != null && aisle.isNotEmpty) {
      rows = [for (final c in rows) if (c.stage == aisle) c];
    }
    return rows.length > query.limit ? rows.sublist(0, query.limit) : rows;
  }

  // ---- Lens AI ------------------------------------------------------------

  @override
  Future<LensNudgeReport> nudges() async {
    _record('nudges');
    return _nudges;
  }

  @override
  Future<List<LensAskRow>> asks({int limit = 50}) async {
    _record('asks', {'limit': limit});
    final rows = [for (final a in _asks) if (!dismissed.contains(a.id)) a];
    return rows.length > limit ? rows.sublist(0, limit) : rows;
  }

  @override
  Future<List<LensDecisionRow>> decisions({int limit = 50}) async {
    _record('decisions', {'limit': limit});
    return _decisions.length > limit ? _decisions.sublist(0, limit) : _decisions;
  }

  @override
  Future<LensHealth> health() async {
    _record('health');
    return _health;
  }

  @override
  Future<void> answerAsk(String askId,
      {required String answer,
      required String answererId,
      required String answererName}) async {
    _record('answerAsk', {'id': askId, 'answer': answer});
    answered[askId] = answer;
    for (var i = 0; i < _asks.length; i++) {
      final a = _asks[i];
      if (a.id != askId) continue;
      _asks[i] = LensAskRow(
        id: a.id,
        sourceNodeId: a.sourceNodeId,
        groupId: a.groupId,
        content: a.content,
        askerName: a.askerName,
        assigneeName: a.assigneeName,
        status: 'answered',
        answerSummary: answer,
        answeredByName: answererName,
        answeredAt: a.createdAt + 3600,
        createdAt: a.createdAt,
      );
      return;
    }
  }

  @override
  Future<void> dismissAsk(String askId) async {
    _record('dismissAsk', {'id': askId});
    dismissed.add(askId);
  }

  @override
  Future<void> reactToDecision(String decisionId,
      {required String reaction,
      required String nodeId,
      required String displayName}) async {
    _record('reactToDecision', {'id': decisionId, 'reaction': reaction});
    reactions[decisionId] = reaction;
  }

  @override
  Future<void> resolveBlocker(String nodeId) async {
    _record('resolveBlocker', {'nodeId': nodeId});
    resolvedBlockers.add(nodeId);
    // A resolved blocker drops out of the nudge report — the same reconcile the
    // lens does on its next generation.
    _nudges = LensNudgeReport(
      groupId: _nudges.groupId,
      generatedAt: _nudges.generatedAt,
      nudges: [
        for (final n in _nudges.nudges)
          if (n.id != nodeId) n
      ],
      staleAsks: _nudges.staleAsks,
      staleBlockers:
          _nudges.staleBlockers > 0 ? _nudges.staleBlockers - 1 : 0,
      unimplementedDecisions: _nudges.unimplementedDecisions,
    );
  }

  // ---- The seed -----------------------------------------------------------
  //
  // Fixed epoch-MILLISECOND stamps (the lens's unit — treating them as seconds
  // was the 1109:35 duration garbage) and a fixed shape: six runs spread over
  // the five lanes and three boards, each carrying real §3 step records.

  /// 2026-08-07T12:00:00Z in epoch ms, the anchor every seeded stamp is off.
  static const int seedNow = 1786104000000;

  static List<RunSummary> seededRuns() => [
        // ── b-eng-1: a settled run with a cache hit and a gate that waited ──
        const RunSummary(
          runId: 'run-done-1',
          tenantId: 'g-eng',
          boardId: 'b-eng-1',
          status: RunStatusValue.done,
          lane: RunLane.done,
          stepCount: 3,
          currentStepIndex: 3,
          attempts: 1,
          createdAt: seedNow - 600000,
          startedAt: seedNow - 590000,
          updatedAt: seedNow - 470000,
          finishedAt: seedNow - 470000,
          gpuSeconds: 42.5,
          costCents: 310,
          asset: 'big-buck-bunny.mp4',
          stepDone: 3,
          stepTotal: 3,
          wallMs: 120000,
          billedMinutes: 9.6,
          billedCents: 288,
          retryMinutes: 0,
          cacheSavedMinutes: 3.2,
          steps: [
            RunStepDetail(
              stepIndex: 0,
              stepId: 'run-done-1:0',
              action: 'transcode',
              actor: 'agent',
              stepStatus: 'Done',
              attempt: 1,
              gpuSeconds: 30,
              startedAt: seedNow - 590000,
              finishedAt: seedNow - 530000,
              assetMinutes: 6.4,
              billedMinutes: 6.4,
              billedCents: 192,
              execMs: 60000,
            ),
            RunStepDetail(
              stepIndex: 1,
              stepId: 'run-done-1:1',
              action: 'qc',
              actor: 'agent',
              stepStatus: 'Skipped',
              attempt: 1,
              idempotentSkipped: true,
              cacheHit: true,
              assetMinutes: 3.2,
              billedMinutes: 0,
              billedCents: 0,
              execMs: 120,
            ),
            RunStepDetail(
              stepIndex: 2,
              stepId: 'run-done-1:2',
              action: 'deliver',
              actor: 'human',
              stepStatus: 'Done',
              attempt: 1,
              startedAt: seedNow - 529000,
              finishedAt: seedNow - 470000,
              assetMinutes: 3.2,
              billedMinutes: 3.2,
              billedCents: 96,
              execMs: 59000,
              // The gate stalled ~1h on a human — the §5 bottleneck signal.
              approvalWaitMs: 3540000,
            ),
          ],
        ),
        // ── b-eng-1: parked at a gate, awaiting a human ─────────────────────
        const RunSummary(
          runId: 'run-gate-2',
          tenantId: 'g-eng',
          boardId: 'b-eng-1',
          status: RunStatusValue.awaitingApproval,
          lane: RunLane.approval,
          stepCount: 3,
          currentStepIndex: 2,
          attempts: 1,
          createdAt: seedNow - 300000,
          startedAt: seedNow - 295000,
          updatedAt: seedNow - 60000,
          asset: 'trailer-cut-04.mov',
          stepDone: 2,
          stepTotal: 3,
          billedMinutes: 4.0,
          billedCents: 120,
          steps: [
            RunStepDetail(
              stepIndex: 0,
              stepId: 'run-gate-2:0',
              action: 'transcode',
              stepStatus: 'Done',
              attempt: 1,
              startedAt: seedNow - 295000,
              finishedAt: seedNow - 250000,
              assetMinutes: 4.0,
              billedMinutes: 4.0,
              billedCents: 120,
              execMs: 45000,
            ),
            RunStepDetail(
              stepIndex: 1,
              stepId: 'run-gate-2:1',
              action: 'deliver',
              actor: 'human',
              stepStatus: 'Pending',
              attempt: 1,
              approvalWaitMs: 240000,
            ),
          ],
        ),
        // ── b-eng-2: failed twice on the conform step ───────────────────────
        const RunSummary(
          runId: 'run-fail-3',
          tenantId: 'g-eng',
          boardId: 'b-eng-2',
          status: RunStatusValue.failed,
          lane: RunLane.failed,
          stepCount: 2,
          currentStepIndex: 1,
          attempts: 2,
          createdAt: seedNow - 900000,
          startedAt: seedNow - 890000,
          updatedAt: seedNow - 840000,
          finishedAt: seedNow - 840000,
          errorClass: 'conform_mismatch',
          gpuSeconds: 8,
          costCents: 60,
          asset: 'ep-102-conform.mxf',
          stepDone: 1,
          stepTotal: 2,
          wallMs: 50000,
          billedMinutes: 2.5,
          billedCents: 75,
          retryMinutes: 2.5,
          steps: [
            RunStepDetail(
              stepIndex: 0,
              stepId: 'run-fail-3:0',
              action: 'conform',
              stepStatus: 'Failed',
              attempt: 2,
              retry: 1,
              errorClass: 'conform_mismatch',
              startedAt: seedNow - 890000,
              finishedAt: seedNow - 840000,
              assetMinutes: 2.5,
              billedMinutes: 2.5,
              billedCents: 75,
              execMs: 50000,
            ),
          ],
        ),
        // ── b-eng-2: in flight right now ────────────────────────────────────
        const RunSummary(
          runId: 'run-live-4',
          tenantId: 'g-eng',
          boardId: 'b-eng-2',
          status: RunStatusValue.running,
          lane: RunLane.inFlight,
          stepCount: 4,
          currentStepIndex: 1,
          attempts: 1,
          createdAt: seedNow - 120000,
          startedAt: seedNow - 110000,
          updatedAt: seedNow - 5000,
          asset: 'promo-30s.mp4',
          stepDone: 1,
          stepTotal: 4,
          steps: [
            RunStepDetail(
              stepIndex: 0,
              stepId: 'run-live-4:0',
              action: 'transcode',
              stepStatus: 'Done',
              attempt: 1,
              startedAt: seedNow - 110000,
              finishedAt: seedNow - 80000,
              assetMinutes: 0.5,
              billedMinutes: 0.5,
              billedCents: 15,
              execMs: 30000,
            ),
            RunStepDetail(
              stepIndex: 1,
              stepId: 'run-live-4:1',
              action: 'conform',
              stepStatus: 'Running',
              attempt: 1,
              startedAt: seedNow - 79000,
            ),
          ],
        ),
        // ── b-eng-3: queued, never started, nothing metered ─────────────────
        const RunSummary(
          runId: 'run-queued-5',
          tenantId: 'g-eng',
          boardId: 'b-eng-3',
          status: RunStatusValue.queued,
          lane: RunLane.incoming,
          stepCount: 2,
          attempts: 0,
          createdAt: seedNow - 30000,
          updatedAt: seedNow - 30000,
          asset: 'sizzle-v2.mov',
        ),
        // ── b-eng-3: stuck — the lens lanes this In-flight, not Failed ──────
        const RunSummary(
          runId: 'run-stuck-6',
          tenantId: 'g-eng',
          boardId: 'b-eng-3',
          status: RunStatusValue.stuck,
          lane: RunLane.inFlight,
          stepCount: 2,
          currentStepIndex: 1,
          attempts: 1,
          createdAt: seedNow - 1800000,
          startedAt: seedNow - 1790000,
          updatedAt: seedNow - 1200000,
          asset: 'archive-restore.mxf',
        ),
      ];

  /// The storefront the lens serves. Deliberately the SAME five listings the
  /// FFI fake used to seed — so the storefront's Tier-1 suite keeps testing the
  /// face rather than the seam — but stated in the LENS WIRE SHAPE, which is
  /// the point: it carries `plugin_id` / `name` / `description` /
  /// `tool_summary` / `trust` / `source` / `featured` / `stage` and NOTHING
  /// ELSE. No rating, no publisher, no side-effect, no separate bundle id.
  /// Those fields were the old fake's invention; a card that claims them off a
  /// live lens is claiming something the lens never said.
  static List<LensPluginCardWire> seededCards() => const [
        // The listing id IS the bundle id on this lane (the download leg is
        // `/marketplace/bundle/{plugin_id}`), and this one is ALREADY in the
        // device catalog — so the storefront reads it back as Installed rather
        // than offering it again.
        LensPluginCardWire(
          pluginId: 'ffmpeg',
          name: 'FFmpeg Transcode',
          description: 'Transcode + proxy generation for any master.',
          toolSummary: ['probe', 'transcode'],
          trust: 'trusted',
          source: 'curated',
          featured: true,
          stage: 'editorial',
        ),
        LensPluginCardWire(
          pluginId: 'pl-resolve',
          name: 'Resolve Color Match',
          description: 'Auto color-match shots to a reference grade.',
          toolSummary: ['match_grade'],
          trust: 'trusted',
          source: 'curated',
          featured: true,
          stage: 'color',
        ),
        LensPluginCardWire(
          pluginId: 'pl-loudness',
          name: 'Loudness Normalize',
          description: 'EBU R128 loudness measurement + normalize.',
          toolSummary: ['loudness_run'],
          trust: 'trusted',
          source: 'curated',
          stage: 'sound',
        ),
        // UNTRUSTED but CURATED — the two are independent, and the reference
        // makes a point of it: signing a wrapper gives provenance, not trust.
        // It is also the card the contextualizer bug was found on: "frameio"
        // contains "frame", so running the keyword hint over a curated card
        // stamped it "Use in a workflow to transcode/render video" and forced
        // its stage to Delivery. A curated card's own words win.
        LensPluginCardWire(
          pluginId: 'pl-frameio',
          name: 'Frame.io Review',
          description: 'Push a cut to Frame.io for client review.',
          toolSummary: ['push_review'],
          trust: 'untrusted',
          source: 'curated',
          stage: 'review',
        ),
        LensPluginCardWire(
          pluginId: 'pl-deliver',
          name: 'Spec Delivery',
          description: 'Package + deliver to broadcast spec.',
          toolSummary: ['deliver'],
          trust: 'trusted',
          source: 'curated',
          stage: 'delivery',
        ),
        // A raw PUBLIC-registry id with no description — what the
        // contextualizer exists for, and what the curation filter has to judge.
        LensPluginCardWire(
          pluginId: 'io.github.CSOAI-ORG/voice-audio-mcp',
          trust: 'untrusted',
          source: 'public',
        ),
      ];

  static LensNudgeReport seededNudges() => const LensNudgeReport(
        groupId: 'g-eng',
        generatedAt: seedNow ~/ 1000,
        nudges: [
          LensNudgeWire(
            nudgeType: 'stale_ask',
            question: 'Which LUT ships with the festival master?',
            ageHours: 30,
            askId: 'ask-1',
          ),
          LensNudgeWire(
            nudgeType: 'stale_blocker',
            externalId: 'CYAN-441',
            staleDays: 4,
            nodeId: 'node-blocker-1',
          ),
        ],
        staleAsks: 1,
        staleBlockers: 1,
        unimplementedDecisions: 0,
      );

  static List<LensAskRow> seededAsks() => const [
        LensAskRow(
          id: 'ask-1',
          sourceNodeId: 'node-ask-1',
          groupId: 'g-eng',
          content: 'Which LUT ships with the festival master?',
          askerName: 'Dana',
          assigneeName: 'Rick',
          status: 'open',
          createdAt: 1786104000 - 108000,
        ),
        LensAskRow(
          id: 'ask-2',
          sourceNodeId: 'node-ask-2',
          groupId: 'g-eng',
          content: 'Do we re-conform ep-102 or patch the mix?',
          askerName: 'Rick',
          assigneeName: 'Dana',
          status: 'answered',
          answerSummary: 'Patch the mix — the conform is fine.',
          answeredByName: 'Dana',
          answeredAt: 1786104000 - 3600,
          createdAt: 1786104000 - 7200,
        ),
      ];

  static List<LensDecisionRow> seededDecisions() => const [
        LensDecisionRow(
          id: 'dec-1',
          sourceNodeId: 'node-dec-1',
          groupId: 'g-eng',
          content: 'Deliveries go out at 4K HDR only.',
          deciderName: 'Rick',
          rationale: 'The SDR pass cost more in retries than it earned.',
          createdAt: 1786104000 - 172800,
        ),
      ];

  static LensHealth seededHealth() => const LensHealth(
        postgres: true,
        vllm: true,
        lens: true,
        commit: 'seed',
      );
}
