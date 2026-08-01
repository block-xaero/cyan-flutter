// ffi/fake_cyan_backend.dart
//
// Tier-1 test/demo implementation of the `CyanBackend` seam. Returns fixed,
// deterministic demo data so widget + golden tests render without any native
// library or running engine. NO FFI, NO async I/O, NO randomness — goldens must
// be byte-stable across runs and machines.
//
// Seeded fixture: 3 groups / 10 boards total, plus one sample workflow run.

import 'dart:convert';

import '../models/mesh_status.dart';
import 'cyan_backend.dart';
import 'parity_models.dart';

class FakeCyanBackend implements CyanBackend {
  bool _ready = false;

  // Fixed epoch so dates (and any "x ago" formatting) are deterministic in
  // goldens. 2026-06-01 00:00:00 UTC.
  static final DateTime _epoch = DateTime.utc(2026, 6, 1);

  @override
  Future<void> initialize() async {
    _ready = true;
  }

  @override
  bool get isReady => _ready;

  // Not `final`: the Explorer's create/rename/delete rewrite the tree in place,
  // the same way the engine would answer a FileTree command with a new
  // snapshot. Ids stay a pure function of (workspace, name) so goldens remain
  // byte-stable.
  late List<CyanGroup> _groups = _buildGroups();

  @override
  // A fresh list each read: a provider handed the SAME List instance twice
  // compares equal and never rebuilds, so a mutation would go unseen.
  Future<List<CyanGroup>> loadGroups() async => List<CyanGroup>.of(_groups);

  // ---- tree mutation (Explorer) ---------------------------------------------

  @override
  Future<void> createBoard(String workspaceId, String name) async {
    final board = CyanBoard(
      id: _newBoardId(workspaceId, name),
      workspaceId: workspaceId,
      name: name,
      createdAt: _epoch,
      lastModified: _epoch,
    );
    _rewriteWorkspaces((w) => w.id == workspaceId
        ? _withBoards(w, [...w.boards, board])
        : w);
  }

  @override
  Future<void> renameBoard(String boardId, String name) async {
    _rewriteWorkspaces((w) => _withBoards(w, [
          for (final b in w.boards)
            if (b.id == boardId) _renamed(b, name) else b,
        ]));
  }

  @override
  Future<void> deleteBoard(String boardId) async {
    _rewriteWorkspaces((w) =>
        _withBoards(w, w.boards.where((b) => b.id != boardId).toList()));
  }

  // ---- board pins ------------------------------------------------------------

  @override
  Future<void> pinSet(String boardId, bool pinned) async {
    _rewriteWorkspaces((w) => _withBoards(w, [
          for (final b in w.boards)
            if (b.id == boardId) _repinned(b, pinned) else b,
        ]));
  }

  @override
  Future<String?> pinSummaryAsBoard(
      String workspaceId, String boardName, String markdownContent) async {
    if (_workspace(workspaceId) == null) return null;
    // The engine's board id is a pure function of (workspace, name), so pinning
    // the same summary twice lands on the SAME board rather than a duplicate.
    final id = _newBoardId(workspaceId, boardName);
    _summaries[id] = markdownContent;
    if (_board(id) != null) return id;
    final board = CyanBoard(
      id: id,
      workspaceId: workspaceId,
      name: boardName,
      // The summary arrives as one markdown cell, so the board opens on Notes.
      activeFace: BoardFaceKind.notes,
      stepCount: 1,
      createdAt: _epoch,
      lastModified: _epoch,
    );
    _rewriteWorkspaces((w) =>
        w.id == workspaceId ? _withBoards(w, [...w.boards, board]) : w);
    return id;
  }

  /// The markdown each pinned summary landed with, keyed by the board it made.
  /// Test observability: the seam has no read-back verb for the opening cell.
  final Map<String, String> _summaries = {};

  /// The summary [pinSummaryAsBoard] wrote onto [boardId], if it made it.
  String? summaryFor(String boardId) => _summaries[boardId];

  static CyanBoard _repinned(CyanBoard b, bool pinned) => CyanBoard(
        id: b.id,
        workspaceId: b.workspaceId,
        name: b.name,
        activeFace: b.activeFace,
        isPinned: pinned,
        rating: b.rating,
        labels: b.labels,
        stepCount: b.stepCount,
        isDeployed: b.isDeployed,
        createdAt: b.createdAt,
        lastModified: b.lastModified,
      );

  CyanWorkspace? _workspace(String workspaceId) {
    for (final g in _groups) {
      for (final w in g.workspaces) {
        if (w.id == workspaceId) return w;
      }
    }
    return null;
  }

  /// Rebuild the tree, passing every workspace through [f].
  void _rewriteWorkspaces(CyanWorkspace Function(CyanWorkspace) f) {
    _groups = [
      for (final g in _groups)
        CyanGroup(
          id: g.id,
          name: g.name,
          colorHex: g.colorHex,
          peerCount: g.peerCount,
          workspaces: [for (final w in g.workspaces) f(w)],
        ),
    ];
  }

  static String _newBoardId(String workspaceId, String name) =>
      'b-$workspaceId-'
      '${name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-')}';

  static CyanWorkspace _withBoards(CyanWorkspace w, List<CyanBoard> boards) =>
      CyanWorkspace(id: w.id, groupId: w.groupId, name: w.name, boards: boards);

  static CyanBoard _renamed(CyanBoard b, String name) => CyanBoard(
        id: b.id,
        workspaceId: b.workspaceId,
        name: name,
        activeFace: b.activeFace,
        isPinned: b.isPinned,
        rating: b.rating,
        labels: b.labels,
        stepCount: b.stepCount,
        isDeployed: b.isDeployed,
        createdAt: b.createdAt,
        lastModified: b.lastModified,
      );

  @override
  Future<List<BoardWithContext>> loadAllBoards() async {
    final out = <BoardWithContext>[];
    for (final g in _groups) {
      for (final w in g.workspaces) {
        for (final b in w.boards) {
          out.add(BoardWithContext(board: b, group: g, workspace: w));
        }
      }
    }
    return out;
  }

  // ---- live event pump -----------------------------------------------------

  /// The scripted event buffer. POP-FRONT, exactly like the engine's Rust
  /// VecDeque: a frame is handed to one caller and is then gone. Tests seed it
  /// with [scriptEvents].
  final List<String> _eventQueue = [];

  /// Queue raw event frames for the next [pollEvents] drains. Frames are
  /// handed back in the order given. Deliberately takes STRINGS, not typed
  /// events, so a test can script a frame this build cannot decode.
  void scriptEvents(Iterable<String> frames) => _eventQueue.addAll(frames);

  /// How many frames are still queued (test observability).
  int get queuedEventCount => _eventQueue.length;

  @override
  Future<String?> pollEvents(String component) async {
    // The fake has ONE buffer and ignores the component name, matching the
    // Swift Tier-1 fake: scripted tests address the queue, not the channel.
    if (_eventQueue.isEmpty) return null;
    return _eventQueue.removeAt(0);
  }

  @override
  Future<WorkflowRun?> loadRun(String boardId) async {
    // A sample run for the first deployed board; null otherwise.
    if (boardId != 'b-eng-1') return null;
    return const WorkflowRun(
      boardId: 'b-eng-1',
      title: 'Render + Review Pipeline',
      steps: [
        RunStep(
          id: 's1',
          title: 'Ingest assets',
          kind: RunStepKind.ai,
          status: RunStepStatus.done,
        ),
        RunStep(
          id: 's2',
          title: 'Transcode proxies',
          kind: RunStepKind.ai,
          status: RunStepStatus.done,
        ),
        RunStep(
          id: 's3',
          title: 'Producer approval',
          kind: RunStepKind.human,
          status: RunStepStatus.awaitingApproval,
        ),
        RunStep(
          id: 's4',
          title: 'Publish to review',
          kind: RunStepKind.ai,
          status: RunStepStatus.pending,
        ),
      ],
    );
  }

  // ---- board faces ---------------------------------------------------------

  @override
  Future<Workflow> loadWorkflow(String boardId) async {
    final authored = _authoredWorkflow(boardId);
    final cloned = _clonedSteps[boardId];
    if (cloned == null || cloned.isEmpty) return authored;
    // A clone APPENDS real authorable cells, and new cells are not compiled —
    // the board goes back to needing a compile, exactly as the engine leaves it.
    return Workflow(
      boardId: authored.boardId,
      isDeployed: authored.isDeployed,
      isCompiled: false,
      steps: [...authored.steps, ...cloned],
    );
  }

  Workflow _authoredWorkflow(String boardId) {
    // The flagship deployed board has a compiled, locked workflow; the others
    // have a couple of authored-but-uncompiled steps; unknown boards are empty.
    if (boardId == 'b-eng-1') {
      return const Workflow(
        boardId: 'b-eng-1',
        isDeployed: true,
        isCompiled: true,
        steps: [
          WorkflowStep(
            id: 'ws1',
            text: 'Ingest the master from #shotlist',
            tool: 'asset-ingest',
            boundInputs: ['shotlist.csv'],
            gate: StepGate.noApproval,
          ),
          WorkflowStep(
            id: 'ws2',
            text: 'Transcode proxies with @ffmpeg',
            tool: 'ffmpeg',
            gate: StepGate.noApproval,
          ),
          WorkflowStep(
            id: 'ws3',
            text: 'Wait for producer approval',
            gate: StepGate.needsApproval,
          ),
          WorkflowStep(
            id: 'ws4',
            text: 'Publish the cut, send to /review',
            tool: 'review-publish',
            destination: 'review',
            gate: StepGate.noApproval,
          ),
        ],
      );
    }
    if (boardId == 'b-eng-2') {
      return const Workflow(
        boardId: 'b-eng-2',
        isCompiled: false,
        steps: [
          WorkflowStep(id: 'ws1', text: 'Design the schema'),
          WorkflowStep(
            id: 'ws2',
            text: 'Migrate the users table',
            isAmbiguous: true,
          ),
          WorkflowStep(id: 'ws3', text: 'Backfill from the export'),
        ],
      );
    }
    return Workflow(boardId: boardId);
  }

  @override
  Future<BoardNotes> loadNotes(String boardId) async {
    if (boardId == 'b-eng-4') {
      return const BoardNotes(
        boardId: 'b-eng-4',
        fileName: 'deployment.md',
        content: '# Deployment Notes\n'
            '\n'
            '## Pre-flight\n'
            '- Pin the engine to the baseline tag\n'
            '- Confirm the relay policy is **Disabled** for offline runs\n'
            '\n'
            '## Rollout\n'
            '1. Build the Windows `.dll`\n'
            '2. Wire flutter_rust_bridge\n'
            '3. Smoke the 2-peer mesh\n'
            '\n'
            '> Keep the FFI contract additive — the iOS app depends on it.\n',
      );
    }
    return BoardNotes(
      boardId: boardId,
      fileName: 'notes.md',
      content: '# Notes\n\nStart writing…\n',
    );
  }

  // ---- operations console ---------------------------------------------------

  @override
  Future<List<OpsRun>> loadOpsRuns() async => const [
        OpsRun(
          runId: 'run-7f3a',
          asset: 'reel_master_v4.mov',
          workflow: 'Render + Review Pipeline',
          status: RunStatus.awaitingApproval,
          currentStep: 3,
          stepCount: 4,
          durationLabel: '1:42',
          costDollars: 0.18,
          billedMinutes: 4.5,
          stageLabel: 'Awaiting producer approval',
        ),
        OpsRun(
          runId: 'run-9c21',
          asset: 'promo_cut_02.mov',
          workflow: 'Render + Review Pipeline',
          status: RunStatus.running,
          currentStep: 2,
          stepCount: 4,
          durationLabel: '0:51',
          costDollars: 0.07,
          billedMinutes: 1.8,
          stageLabel: 'Transcoding proxies',
        ),
        OpsRun(
          runId: 'run-4b88',
          asset: 'ad_30s_final.mov',
          workflow: 'Design System',
          status: RunStatus.failed,
          currentStep: 2,
          stepCount: 5,
          durationLabel: '0:33',
          costDollars: 0.04,
          billedMinutes: 1.1,
          retryMinutes: 1.1,
          stageLabel: 'Transcode failed',
        ),
        OpsRun(
          runId: 'run-1de0',
          asset: 'teaser_15s.mov',
          workflow: 'Q3 2026 Goals',
          status: RunStatus.queued,
          currentStep: 0,
          stepCount: 4,
          stageLabel: 'Queued',
        ),
        OpsRun(
          runId: 'run-2a55',
          asset: 'sizzle_v1.mov',
          workflow: 'Render + Review Pipeline',
          status: RunStatus.done,
          currentStep: 4,
          stepCount: 4,
          durationLabel: '2:08',
          costDollars: 0.22,
          billedMinutes: 5.4,
          isCacheHit: true,
        ),
        OpsRun(
          runId: 'run-6e9b',
          asset: 'bumper_clean.mov',
          workflow: 'Design System',
          status: RunStatus.done,
          currentStep: 6,
          stepCount: 6,
          durationLabel: '3:15',
          costDollars: 0.31,
          billedMinutes: 7.7,
        ),
      ];

  @override
  Future<CostMeter> loadCostMeter() async => const CostMeter(
        hasMeter: true,
        billedMinutes: 24.5,
        billedDollars: 12.30,
        retryMinutes: 3.2,
        savedMinutes: 8.1,
        runs: 47,
        computeMinutes: 31.4,
        gpuSeconds: 612,
        perWorkflow: [
          WorkflowCost(
            workflow: 'Render + Review Pipeline',
            runs: 21,
            assets: 18,
            billedMinutes: 12.4,
            billedDollars: 6.20,
            retryMinutes: 1.1,
          ),
          WorkflowCost(
            workflow: 'Design System',
            runs: 14,
            assets: 12,
            billedMinutes: 7.8,
            billedDollars: 3.90,
            retryMinutes: 2.1,
          ),
          WorkflowCost(
            workflow: 'Q3 2026 Goals',
            runs: 12,
            assets: 9,
            billedMinutes: 4.3,
            billedDollars: 2.20,
            retryMinutes: 0,
          ),
        ],
      );

  @override
  Future<EfficiencyReport> loadEfficiency() async => const EfficiencyReport(
        gateBottleneckStep: 'Producer approval',
        gateWaitP95Ms: 142000,
        failureHotspotStep: 'Transcode proxies',
        failureRatePct: 8.3,
        topErrorClass: 'TranscodeError',
        slowestStep: 'Transcode proxies',
        slowestExecP95Ms: 5400,
        cacheHitRatePct: 31.0,
        minutesSaved: 8.1,
        retryRatePct: 6.2,
        steps: [
          StepEfficiency(
            step: 'Ingest assets',
            runs: 47,
            gateP95Ms: 0,
            failPct: 0,
            execP95Ms: 820,
            cachePct: 12,
            savedMinutes: 1.2,
            retryPct: 0,
          ),
          StepEfficiency(
            step: 'Transcode proxies',
            runs: 47,
            gateP95Ms: 0,
            failPct: 8.3,
            topError: 'TranscodeError',
            execP95Ms: 5400,
            cachePct: 31,
            savedMinutes: 6.9,
            retryPct: 6.2,
          ),
          StepEfficiency(
            step: 'Producer approval',
            runs: 47,
            gateP95Ms: 142000,
            failPct: 0,
            execP95Ms: 0,
            cachePct: 0,
            savedMinutes: 0,
            retryPct: 0,
          ),
          StepEfficiency(
            step: 'Publish to review',
            runs: 41,
            gateP95Ms: 0,
            failPct: 1.2,
            execP95Ms: 1100,
            cachePct: 0,
            savedMinutes: 0,
            retryPct: 1.2,
          ),
        ],
      );

  /// Fixed trace clock so wall/exec figures are byte-stable in goldens.
  static final int _traceBase = _epoch.millisecondsSinceEpoch;

  // The per-step audit for the seeded runs. Every trace RECONCILES with its
  // `OpsRun` card by construction — Σ step `billedCents` is the card's
  // `costDollars`, Σ step `billedMinutes` is its `billedMinutes` — so a figure
  // on the run list is explainable against the rows underneath it. The run-level
  // billed totals are deliberately left null: the rollup sums the step records,
  // which is the invariant the audit claims on screen.
  @override
  Future<RunTrace?> loadRunTrace(String runId) async => switch (runId) {
        'run-2a55' => RunTrace(
            runId: 'run-2a55',
            tenantId: 'acme',
            status: 'Done',
            stepCount: 4,
            totalTokensIn: 480,
            totalTokensOut: 1180,
            totalGpuSeconds: 2.46,
            totalPriceCents: 3.4,
            bottleneckStepIndex: 2,
            steps: [
              RunStepDetail(
                stepIndex: 0,
                stepId: 's1',
                action: 'Ingest assets',
                actor: 'agent',
                status: 'ok',
                stepStatus: 'Done',
                attempt: 1,
                startedAt: _traceBase,
                finishedAt: _traceBase + 4200,
                execMs: 4200,
                tokensIn: 200,
                tokensOut: 640,
                gpuMs: 1840,
                assetMinutes: 5.4,
                billedMinutes: 5.4,
                billedCents: 22.0,
              ),
              // Reused result: the media was already transcoded, so it bills 0.
              RunStepDetail(
                stepIndex: 1,
                stepId: 's2',
                action: 'Transcode proxies',
                actor: 'agent',
                status: 'ok',
                stepStatus: 'Done',
                attempt: 1,
                startedAt: _traceBase + 4200,
                finishedAt: _traceBase + 4260,
                execMs: 60,
                tokensIn: 0,
                tokensOut: 0,
                gpuMs: 0,
                assetMinutes: 5.4,
                billedMinutes: 0.0,
                billedCents: 0.0,
                cacheHit: true,
              ),
              // The human gate — the run's bottleneck, and unmetered (no media
              // was processed while it waited).
              RunStepDetail(
                stepIndex: 2,
                stepId: 's3',
                action: 'Producer approval',
                actor: 'human',
                stepStatus: 'Done',
                attempt: 1,
                startedAt: _traceBase + 4260,
                finishedAt: _traceBase + 146260,
                approvalWaitMs: 142000,
              ),
              // Re-published after a failed hand-off: flagged, and not re-billed
              // (no new media minutes).
              RunStepDetail(
                stepIndex: 3,
                stepId: 's4',
                action: 'Publish to review',
                actor: 'agent',
                status: 'ok',
                stepStatus: 'Done',
                attempt: 2,
                startedAt: _traceBase + 146260,
                finishedAt: _traceBase + 147360,
                execMs: 1100,
                tokensIn: 280,
                tokensOut: 540,
                gpuMs: 620,
              ),
            ],
          ),
        'run-4b88' => RunTrace(
            runId: 'run-4b88',
            tenantId: 'acme',
            status: 'Failed',
            runErrorClass: 'TranscodeError',
            stepCount: 5,
            totalTokensIn: 60,
            totalTokensOut: 140,
            totalGpuSeconds: 0.48,
            totalPriceCents: 0.6,
            bottleneckStepIndex: 0,
            steps: [
              RunStepDetail(
                stepIndex: 0,
                stepId: 'd1',
                action: 'Ingest assets',
                actor: 'agent',
                status: 'ok',
                stepStatus: 'Done',
                attempt: 1,
                startedAt: _traceBase,
                finishedAt: _traceBase + 900,
                execMs: 900,
                tokensIn: 60,
                tokensOut: 140,
                gpuMs: 300,
                assetMinutes: 1.1,
                billedMinutes: 1.1,
                billedCents: 4.0,
              ),
              RunStepDetail(
                stepIndex: 1,
                stepId: 'd2',
                action: 'Transcode proxies',
                actor: 'agent',
                status: 'error',
                stepStatus: 'Failed',
                attempt: 2,
                retry: 1,
                errorClass: 'TranscodeError',
                startedAt: _traceBase + 900,
                finishedAt: _traceBase + 1420,
                execMs: 520,
                gpuMs: 180,
                assetMinutes: 1.1,
                billedMinutes: 0.0,
                billedCents: 0.0,
              ),
              // Materialized but never reached — a state-only rail.
              const RunStepDetail(
                stepIndex: 2,
                stepId: 'd3',
                action: 'Color pass',
                actor: 'agent',
                stepStatus: 'Pending',
              ),
              const RunStepDetail(
                stepIndex: 3,
                stepId: 'd4',
                action: 'Producer approval',
                actor: 'human',
                stepStatus: 'Pending',
              ),
              const RunStepDetail(
                stepIndex: 4,
                stepId: 'd5',
                action: 'Publish to review',
                actor: 'agent',
                stepStatus: 'Pending',
              ),
            ],
          ),
        'run-7f3a' => RunTrace(
            runId: 'run-7f3a',
            tenantId: 'acme',
            status: 'AwaitingApproval',
            stepCount: 4,
            totalTokensIn: 150,
            totalTokensOut: 420,
            totalGpuSeconds: 2.5,
            totalPriceCents: 2.9,
            bottleneckStepIndex: 1,
            steps: [
              RunStepDetail(
                stepIndex: 0,
                stepId: 'r1',
                action: 'Ingest assets',
                actor: 'agent',
                status: 'ok',
                stepStatus: 'Done',
                attempt: 1,
                startedAt: _traceBase,
                finishedAt: _traceBase + 1200,
                execMs: 1200,
                tokensIn: 150,
                tokensOut: 420,
                gpuMs: 900,
                assetMinutes: 4.5,
                billedMinutes: 4.5,
                billedCents: 18.0,
              ),
              RunStepDetail(
                stepIndex: 1,
                stepId: 'r2',
                action: 'Transcode proxies',
                actor: 'agent',
                status: 'ok',
                stepStatus: 'Done',
                attempt: 1,
                startedAt: _traceBase + 1200,
                finishedAt: _traceBase + 4600,
                execMs: 3400,
                gpuMs: 1600,
                assetMinutes: 4.5,
                billedMinutes: 0.0,
                billedCents: 0.0,
              ),
              RunStepDetail(
                stepIndex: 2,
                stepId: 'r3',
                action: 'Producer approval',
                actor: 'human',
                stepStatus: 'Running',
                attempt: 1,
                startedAt: _traceBase + 4600,
                approvalWaitMs: 61000,
              ),
              const RunStepDetail(
                stepIndex: 3,
                stepId: 'r4',
                action: 'Publish to review',
                actor: 'agent',
                stepStatus: 'Pending',
              ),
            ],
          ),
        // A run the lens has not traced — the audit face says so rather than
        // rendering an empty shell.
        _ => null,
      };

  // ---- license / entitlement -------------------------------------------------

  /// A cached signed grant: the demo tenant mid-TRIAL, expiring 7 days after
  /// the fixture epoch. Callers inject their own `now`, so the countdown a test
  /// asserts on is deterministic.
  static final int _trialExpirySecs =
      _epoch.millisecondsSinceEpoch ~/ 1000 + 7 * 86400;

  @override
  Future<String?> cachedEntitlementJson() async => '{"tenant":"acme",'
      '"plan":"trial","seats":5,'
      '"features":{"lens":true,"codegen":true,"marketplace_publish":true},'
      '"trial_expiry":$_trialExpirySecs,'
      '"meter":{"included_minutes":500,"rate_cents_per_minute":4}}';

  // ---- marketplace ----------------------------------------------------------

  @override
  Future<List<PluginCard>> loadMarketplace() async => const [
        PluginCard(
          id: 'pl-ffmpeg',
          name: 'FFmpeg Transcode',
          publisher: 'cyan-core',
          // The one seeded listing whose bundle is ALREADY in the device
          // catalog (`_pluginBundles['ffmpeg']`) — the storefront reads it back
          // as Installed rather than offering it again.
          bundleId: 'ffmpeg',
          summary: 'Transcode + proxy generation for any master.',
          category: PluginCategory.editorial,
          stage: 'process',
          placement: 'device',
          sideEffect: PluginSideEffect.readOnly,
          isTrusted: true,
          rating: 5,
          isFeatured: true,
        ),
        PluginCard(
          id: 'pl-resolve',
          name: 'Resolve Color Match',
          publisher: 'studio-tools',
          summary: 'Auto color-match shots to a reference grade.',
          category: PluginCategory.color,
          stage: 'enrich',
          placement: 'cloud',
          sideEffect: PluginSideEffect.readOnly,
          isTrusted: true,
          rating: 4,
          isFeatured: true,
        ),
        PluginCard(
          id: 'pl-loudness',
          name: 'Loudness Normalize',
          publisher: 'audio-lab',
          summary: 'EBU R128 loudness measurement + normalize.',
          category: PluginCategory.sound,
          stage: 'process',
          placement: 'device',
          sideEffect: PluginSideEffect.readOnly,
          isTrusted: true,
          rating: 4,
        ),
        PluginCard(
          id: 'pl-frameio',
          name: 'Frame.io Review',
          publisher: 'community',
          summary: 'Push a cut to Frame.io for client review.',
          category: PluginCategory.review,
          stage: 'deliver',
          placement: 'cloud',
          sideEffect: PluginSideEffect.externalSend,
          isTrusted: false,
          rating: 3,
        ),
        PluginCard(
          id: 'pl-deliver',
          name: 'Spec Delivery',
          publisher: 'cyan-core',
          summary: 'Package + deliver to broadcast spec.',
          category: PluginCategory.delivery,
          stage: 'deliver',
          placement: 'cloud',
          sideEffect: PluginSideEffect.externalSend,
          isTrusted: true,
          rating: 5,
        ),
      ];

  // ---- plugins ---------------------------------------------------------------

  /// The installed bundles by plugin id, each with the tools its manifest
  /// declares. A tool's `side_effects` are the manifest's own — empty for a
  /// sensor, gated labels for an actuator.
  final Map<String, InstalledPlugin> _pluginBundles = {
    'asset-ingest': const InstalledPlugin(
      id: 'asset-ingest',
      version: '1.4.0',
      tools: [
        InstalledPluginTool(
            name: 'ingest_folder', sideEffects: ['mutate_local']),
        InstalledPluginTool(name: 'probe_asset'),
      ],
    ),
    'ffmpeg': const InstalledPlugin(
      id: 'ffmpeg',
      version: '2.1.0',
      tools: [
        InstalledPluginTool(name: 'probe'),
        InstalledPluginTool(name: 'transcode', sideEffects: ['mutate_local']),
      ],
    ),
    // The onboarding doc's worked example: an actuator that sends out, so it
    // needs BOTH a vault credential and non-secret targets in plugin_config.
    'frameio': const InstalledPlugin(
      id: 'frameio',
      version: '1.0.0',
      tools: [
        InstalledPluginTool(name: 'push_review', sideEffects: ['external_send']),
      ],
    ),
  };

  // ---- plugin config ---------------------------------------------------------

  /// The engine's `plugin_config` table: (tenant, plugin) -> key -> value. The
  /// group id IS the tenant. Board-scoped rows are the engine's finer grain;
  /// this seam is tenant-wide, which is what a settings sheet writes.
  ///
  /// Seeded as a plugin already configured once, so the sheet has the shape a
  /// real install leaves behind. NON-SECRET ONLY, exactly like the table.
  final Map<String, Map<String, String>> _pluginConfig = {
    'g-eng|frameio': {
      'account_id': 'acct-9f2c41',
      'folder_id': 'fld-review-inbox',
    },
  };

  String _configKey(String groupId, String pluginId) => '$groupId|$pluginId';

  @override
  Future<PluginConfig> pluginConfigGet(String groupId, String pluginId) async {
    if (pluginId.isEmpty) {
      return const PluginConfig(
          pluginId: '', error: 'plugin_id is required');
    }
    final rows = _pluginConfig[_configKey(groupId, pluginId)] ?? const {};
    final keys = rows.keys.toList()..sort(); // the engine's BTreeMap order
    return PluginConfig(
      pluginId: pluginId,
      values: {for (final k in keys) k: rows[k]!},
    );
  }

  @override
  Future<PluginConfigWrite> pluginConfigSet(
      String groupId, String pluginId, String key, String value) async {
    if (pluginId.isEmpty || key.isEmpty) {
      return const PluginConfigWrite.refused(
          'plugin_id, key, value are required');
    }
    // The engine's guard, worded exactly as `plugin_config::set` words it —
    // a secret in this table would replicate as a plain row, so it is refused
    // here too rather than stored and quietly diverging from the engine.
    if (pluginConfigKeyLooksSecret(key)) {
      return PluginConfigWrite.refused(
        "'$key' looks like a secret — plugin_config stores non-secret targets "
        'only; credentials go to the vault (see '
        'PLUGIN_CREDENTIAL_ONBOARDING.md)',
      );
    }
    _pluginConfig
        .putIfAbsent(_configKey(groupId, pluginId), () => {})[key] = value;
    return const PluginConfigWrite.ok();
  }

  @override
  Future<List<InstalledPlugin>> pluginCatalog() async {
    final ids = _pluginBundles.keys.toList()..sort();
    return [
      for (final id in ids)
        InstalledPlugin(
          id: id,
          version: _pluginBundles[id]!.version,
          tools: _pluginBundles[id]!.tools.toList()
            ..sort((a, b) => a.name.compareTo(b.name)),
        )
    ];
  }

  /// A `.cyanplugin` bundle is a TAR carrying a manifest at its root — the
  /// fake's admit gate looks for that name in the decoded bytes, standing in
  /// for the engine's layout + signature policy, which it cannot run.
  static const String _pluginManifestFile = 'cyan-plugin.toml';

  @override
  Future<PluginInstallResult> installPluginBundle(
      String groupId, String pluginId, String bundleBytesB64) async {
    // The engine words a NULL argument "missing …"; this seam can only ever
    // hand it an empty string, which is the same thing said in Dart.
    if (groupId.isEmpty) {
      return const PluginInstallResult(
          success: false, error: 'missing group_id');
    }
    if (pluginId.isEmpty) {
      return const PluginInstallResult(
          success: false, error: 'missing plugin_id');
    }
    final List<int> bytes;
    try {
      bytes = base64.decode(bundleBytesB64.trim());
    } catch (e) {
      return PluginInstallResult(
          success: false, error: 'base64 decode failed: $e');
    }
    if (bytes.isEmpty) {
      return const PluginInstallResult(
          success: false, error: 'empty bundle bytes');
    }
    final body = String.fromCharCodes(bytes);
    if (!body.contains(_pluginManifestFile)) {
      return const PluginInstallResult(
          success: false,
          error: 'install refused: no $_pluginManifestFile in bundle');
    }
    // Admitted: the bundle lands, and the catalog serves it from here on.
    _pluginBundles[pluginId] = InstalledPlugin(
      id: pluginId,
      version: '1.0.0',
      tools: [InstalledPluginTool(name: '${pluginId.split('-').last}_run')],
    );
    return PluginInstallResult(
      success: true,
      pluginId: pluginId,
      fileId: 'file-$groupId-$pluginId',
    );
  }

  // ---- lens -----------------------------------------------------------------

  @override
  Future<LensIntelligence> loadLensIntelligence() async => const LensIntelligence(
        connected: true,
        nudges: [
          LensNudge(
            id: 'n1',
            title: 'Producer approval is overdue',
            detail:
                'The Render + Review run has been waiting 2h for sign-off on reel_master_v4.',
            ageLabel: '2h ago',
            boardLabel: 'Render + Review Pipeline',
          ),
          LensNudge(
            id: 'n2',
            title: 'Transcode keeps failing',
            detail:
                'ad_30s_final.mov failed transcode twice — the codec may be unsupported.',
            ageLabel: '40m ago',
            boardLabel: 'Design System',
          ),
        ],
        asks: [
          LensAsk(
            id: 'a1',
            question: 'Which loudness target should the ad set use — -23 or -16 LUFS?',
            asker: 'Mara',
            assignee: 'You',
            ageLabel: '1h ago',
            status: AskStatus.open,
          ),
          LensAsk(
            id: 'a2',
            question: 'Is the Q3 teaser locked for the goals board?',
            asker: 'Devon',
            assignee: 'Priya',
            ageLabel: '3h ago',
            status: AskStatus.answered,
            answer: 'Yes — locked as of this morning, proxies regenerated.',
            answerer: 'Priya',
          ),
        ],
        decisions: [
          LensDecision(
            id: 'd1',
            content: 'Ship the review pipeline with the cloud color step.',
            rationale: 'Device-only color was too slow on long masters.',
            decider: 'Priya',
            ageLabel: '5h ago',
            agreeCount: 4,
            disagreeCount: 1,
            commentCount: 2,
          ),
          LensDecision(
            id: 'd2',
            content: 'Adopt Frame.io review as the external delivery surface.',
            decider: 'Mara',
            ageLabel: '1d ago',
            agreeCount: 3,
            disagreeCount: 0,
            commentCount: 1,
          ),
        ],
      );

  // ---- chat -----------------------------------------------------------------

  @override
  Future<List<ChatMessage>> loadChat(String boardId) async => const [
        ChatMessage(
          id: 'm1',
          author: 'Priya',
          isOwn: false,
          body: 'Kicking off the **Render + Review** run on reel_master_v4.',
          timeLabel: '10:14 AM',
        ),
        ChatMessage(
          id: 'm2',
          author: 'You',
          isOwn: true,
          body: 'Proxies look good — `transcode` step is green.',
          timeLabel: '10:31 AM',
        ),
        ChatMessage(
          id: 'm3',
          author: 'Mara',
          isOwn: false,
          body: 'Holding on producer approval before we publish to /review.',
          timeLabel: '10:42 AM',
        ),
        ChatMessage(
          id: 'm4',
          author: 'You',
          isOwn: true,
          body: 'Approved. Sending to review now.',
          timeLabel: '11:05 AM',
        ),
      ];

  @override
  Future<void> loadChatHistory(String boardId) async {
    // The engine REPLAYS a board's stored chat as events rather than answering
    // with one, so the fake does the same: a `ChatSent` frame per message, then
    // `ChatHistoryComplete`. A caller drains them through [pollEvents] exactly
    // as it would from the engine.
    final workspaceId = _board(boardId)?.workspaceId ?? '';
    final messages = await loadChat(boardId);
    final base = _epoch.millisecondsSinceEpoch ~/ 1000;
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      _eventQueue.add(jsonEncode({
        'type': 'ChatSent',
        'id': m.id,
        'board_id': boardId,
        'workspace_id': workspaceId,
        'message': m.body,
        'author': m.author,
        'parent_id': null,
        // A minute apart from the fixed epoch: ordered, and the same on every
        // run, so a replay sorts identically in goldens.
        'timestamp': base + i * 60,
      }));
    }
    _eventQueue.add(jsonEncode({
      'type': 'ChatHistoryComplete',
      'board_id': boardId,
      'workspace_id': workspaceId,
    }));
  }

  // ---- unread ---------------------------------------------------------------

  /// Seeded per-BOARD unread counts. Board-level only, exactly like the engine:
  /// there is no workspace/group rollup here to double-count against. A board
  /// with nothing unread is ABSENT from the map, never present as 0.
  final Map<String, int> _unread = {
    'b-eng-1': 3,
    'b-eng-3': 1,
    'b-prod-1': 7,
    'b-des-2': 2,
  };

  @override
  Future<Map<String, int>> unreadCounts() async => Map<String, int>.of(_unread);

  @override
  Future<void> markRead(String scopeId) async {
    // Reading a board CLEARS it — the count never moves the other way here,
    // which is what makes opening a chat a read and not a write.
    _unread.remove(scopeId);
  }

  // ---- files ----------------------------------------------------------------

  /// The seeded file store, keyed by the engine's stable workflow handle
  /// `group:workspace:board:name` — the same key [resolveFileHandle] resolves.
  late final Map<String, CyanFile> _files = {
    for (final f in <CyanFile>[
      CyanFile(
        id: 'f-reel-master',
        groupId: 'g-eng',
        workspaceId: 'w-eng-backend',
        boardId: 'b-eng-1',
        name: 'reel_master_v4.mov',
        hash: _digest('reel_master_v4.mov'),
        size: 4821003776,
        sourcePeer: 'g-eng-peer-1',
        localPath: '/fake/media/reel_master_v4.mov',
        createdAt: _epoch.subtract(const Duration(days: 2)),
      ),
      CyanFile(
        id: 'f-shot-list',
        groupId: 'g-eng',
        workspaceId: 'w-eng-backend',
        boardId: 'b-eng-1',
        name: 'shot_list.csv',
        hash: _digest('shot_list.csv'),
        size: 18422,
        localPath: '/fake/docs/shot_list.csv',
        createdAt: _epoch.subtract(const Duration(days: 1)),
      ),
      CyanFile(
        id: 'f-brief',
        groupId: 'g-product',
        workspaceId: 'w-prod-roadmap',
        boardId: 'b-prod-1',
        name: 'q3_brief.pdf',
        hash: _digest('q3_brief.pdf'),
        size: 2210481,
        sourcePeer: 'g-product-peer-1',
        // Metadata only: the row has synced, the bytes have not.
        createdAt: _epoch.subtract(const Duration(hours: 9)),
      ),
    ])
      _handle(f.groupId, f.workspaceId, f.boardId, f.name): f,
  };

  /// Tombstoned file ids. The engine soft-deletes and gossips the tombstone —
  /// it never hard-deletes — so a delete here KEEPS the row and only stops it
  /// resolving, which is how the engine's own resolve misses it.
  final Set<String> _deletedFiles = {};

  @override
  Future<void> deleteFile(String fileId) async {
    _deletedFiles.add(fileId);
  }

  @override
  Future<CyanFile?> resolveFileHandle(String groupId, String workspaceId,
      String boardId, String fileName) async {
    final file = _files[_handle(groupId, workspaceId, boardId, fileName)];
    if (file == null || _deletedFiles.contains(file.id)) return null;
    return file;
  }

  /// The handle the engine resolves on: the four scoping parts, in order.
  static String _handle(
          String groupId, String workspaceId, String boardId, String name) =>
      '$groupId:$workspaceId:$boardId:$name';

  /// Extensions the engine's extractor reads. Anything else answers null — the
  /// fake refuses the shapes the engine refuses rather than inventing text for
  /// a `.mov`.
  static const Set<String> _extractable = {
    'pdf', 'txt', 'md', 'csv', 'json', 'dart', 'rs', 'py', 'ts', 'js',
  };

  @override
  Future<String?> extractFileText(String path) async {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return null;
    if (!_extractable.contains(name.substring(dot + 1).toLowerCase())) {
      return null;
    }
    // Deterministic: the same path always extracts the same document, so a
    // golden that renders an extract stays byte-stable.
    return '# $name\n\n'
        'Extracted from $path.\n'
        'Content digest ${_digest(path)}.\n';
  }

  // -------------------------------------------------------------------------

  // ---- presence ------------------------------------------------------------

  /// The live neighbour set, keyed by group. Seeded to agree with each group's
  /// own `peerCount` (3 + 2 + 1), so the gutter's total and the tree's badges
  /// can never disagree. Null until first read; a test that drove
  /// [setLivePeers] owns it instead.
  Map<String, List<String>>? _livePeers;

  /// Move the live neighbour set.
  ///
  /// The mesh is the one thing about a running engine that is never static —
  /// peers arrive and drop — so a test that needs a partitioned or a busy mesh
  /// drives it HERE, and the widget reads the change back through the seam
  /// like any other engine fact.
  void setLivePeers(Map<String, List<String>> peersByGroup) {
    _livePeers = {
      for (final e in peersByGroup.entries)
        if (e.value.isNotEmpty) e.key: List<String>.from(e.value),
    };
  }

  @override
  Future<MeshPresence> meshPresence() async {
    final byGroup = _livePeers ??= {
      for (final g in _groups)
        if (g.peerCount > 0)
          g.id: [for (var i = 1; i <= g.peerCount; i++) '${g.id}-peer-$i'],
    };
    return MeshPresence(
      totalPeers: byGroup.values.fold<int>(0, (sum, p) => sum + p.length),
      peersByGroup: byGroup,
    );
  }

  // ---- identity -------------------------------------------------------------

  /// The seeded signed-in identity. A test that needs a signed-out device
  /// (fresh install / post-wipe) assigns null and re-pumps — the widget reads
  /// the change back through the seam like any other engine fact.
  DeviceProfile? profile = const DeviceProfile(
    nodeId: _localNodeId,
    displayName: 'Ada Byron',
  );

  /// This device's node id. The roster is keyed by it — the seeded member who
  /// carries it IS this device, which is what puts the "you" badge on a row.
  static const String _localNodeId = 'node-fake-local';

  @override
  Future<DeviceProfile?> myProfile() async => profile;

  // ---- pipeline (the compile / run / gate spine) ----------------------------
  //
  // The fake owns a small in-memory pipeline per board so the widget/VM tiers
  // can drive a REAL state machine — compile, run, gate, approve, reject,
  // retry, reset — with no dylib. Seeded and deterministic: from a fresh
  // backend the same call sequence always yields the same snapshot, so goldens
  // stay byte-stable. Only the compiled boards have a pipeline, mirroring the
  // engine, where the per-step config exists only after a compile.

  /// Same rate the engine bills at ($0.02 / GPU-second), so the fake's cost
  /// arithmetic matches the real meter.
  static const double _usdPerGpuMs = 0.00002;

  /// The board's assignee for producer-review gates.
  static const String _reviewAssignee = 'producer@studio';

  /// Compiled pipelines, keyed by board id. Seeded with the flagship board
  /// mid-run (two steps approved, one on the producer-review gate), which is
  /// the run `loadRun` renders.
  late final Map<String, List<_FakePipelineStep>> _pipelines = {
    'b-eng-1': _seedEngOne(),
  };

  /// Per-step edit history for `stepEditTravel`: revisions oldest-first plus
  /// the cursor into them.
  final Map<String, _FakeStepHistory> _stepHistory = {};

  static List<_FakePipelineStep> _seedEngOne() {
    final steps = _template('b-eng-1');
    steps[0].status = PipelineStepState.humanApproved;
    steps[0].hasRun = true;
    steps[0].aiResult = '{"ingested":12}';
    steps[1].status = PipelineStepState.humanApproved;
    steps[1].hasRun = true;
    steps[1].aiResult = '{"proxies":12}';
    steps[2].status = PipelineStepState.aiComplete;
    steps[2].hasRun = true;
    return steps;
  }

  /// The compiled shape of a board's authored workflow. Boards with no authored
  /// workflow compile to nothing, exactly as `loadWorkflow` returns nothing.
  static List<_FakePipelineStep> _template(String boardId) => switch (boardId) {
        'b-eng-1' => [
            _FakePipelineStep(
              stepId: 'ws1',
              title: 'Ingest the master from #shotlist',
              stage: 'ingest',
              executor: 'local',
              durationSecs: 12,
            ),
            _FakePipelineStep(
              stepId: 'ws2',
              title: 'Transcode proxies with @ffmpeg',
              stage: 'transcode',
              executor: 'local',
              dependsOn: ['ws1'],
              durationSecs: 46,
            ),
            _FakePipelineStep(
              stepId: 'ws3',
              title: 'Wait for producer approval',
              stage: 'review',
              executor: 'manual',
              dependsOn: ['ws2'],
              reviewHold: true,
              waitingOn: _reviewAssignee,
              durationSecs: 0,
            ),
            _FakePipelineStep(
              stepId: 'ws4',
              title: 'Publish the cut, send to /review',
              stage: 'deliver',
              executor: 'cloud',
              dependsOn: ['ws3'],
              localGate: true,
              durationSecs: 21,
            ),
          ],
        'b-eng-2' => [
            _FakePipelineStep(
              stepId: 'ws1',
              title: 'Design the schema',
              stage: 'plan',
              executor: 'cloud',
              durationSecs: 8,
            ),
            _FakePipelineStep(
              stepId: 'ws2',
              title: 'Migrate the users table',
              stage: 'apply',
              executor: 'local',
              dependsOn: ['ws1'],
              durationSecs: 33,
            ),
            _FakePipelineStep(
              stepId: 'ws3',
              title: 'Backfill from the export',
              stage: 'apply',
              executor: 'local',
              dependsOn: ['ws2'],
              durationSecs: 17,
            ),
          ],
        _ => <_FakePipelineStep>[],
      };

  @override
  Future<PipelineLaunch> pipelineCompile(String boardId) async {
    final steps = _template(boardId);
    if (steps.isEmpty) {
      return PipelineLaunch(
        boardId: boardId,
        error: 'nothing to compile on this board',
      );
    }
    // A compile re-authors the DAG: every step starts pending again, and the
    // board's CURRENT assignee is stamped into its review holds — that stamp is
    // what `pipelineApproveAs` then clears against, and it only ever lands at
    // compile, exactly as the engine does it.
    final assignee = _reviewAssignees[boardId];
    for (final step in steps) {
      if (step.reviewHold) step.waitingOn = assignee;
    }
    _pipelines[boardId] = steps;
    return PipelineLaunch(
      boardId: boardId,
      status: 'compiling',
      message: 'Pipeline compiling in background',
    );
  }

  @override
  Future<PipelineLaunch> runPipeline(String boardId) async {
    final steps = _pipelines[boardId];
    if (steps == null) {
      return PipelineLaunch(boardId: boardId, error: 'compile first');
    }
    // Walk to the first step that is not settled and execute it. It then parks
    // on its own gate — which is what lets a caller step THROUGH the workflow
    // one approval at a time.
    for (final step in steps) {
      switch (step.status) {
        case PipelineStepState.humanApproved:
          continue;
        case PipelineStepState.aiComplete:
        case PipelineStepState.failed:
          // A gate or a failure holds the run; nothing more executes.
          break;
        case PipelineStepState.pending:
        case PipelineStepState.running:
          step.status = PipelineStepState.aiComplete;
          step.hasRun = true;
          step.error = null;
          step.aiResult ??= '{"step":"${step.stepId}","ok":true}';
      }
      break;
    }
    return PipelineLaunch(
      boardId: boardId,
      status: 'started',
      message: 'Pipeline running in background',
    );
  }

  @override
  Future<PipelineStatus> pipelineStatus(String boardId) async {
    final steps = _pipelines[boardId];
    if (steps == null) return PipelineStatus(boardId: boardId);

    var aiComplete = 0;
    var humanApproved = 0;
    var running = 0;
    var failed = 0;
    var pending = 0;
    var totalCost = 0.0;
    String? awaitingStep;

    for (final step in steps) {
      switch (step.status) {
        case PipelineStepState.aiComplete:
          aiComplete++;
          awaitingStep ??= step.stepId;
        case PipelineStepState.humanApproved:
          humanApproved++;
          aiComplete++;
        case PipelineStepState.running:
          running++;
        case PipelineStepState.failed:
          failed++;
        case PipelineStepState.pending:
          pending++;
      }
      totalCost += step.costDollars;
    }

    final total = steps.length;
    // Same precedence the engine derives with: failed > awaiting > running >
    // done > in-progress > idle.
    final state = failed > 0
        ? PipelineRunState.failed
        : awaitingStep != null
            ? PipelineRunState.awaitingApproval
            : running > 0
                ? PipelineRunState.running
                : total > 0 && humanApproved == total
                    ? PipelineRunState.done
                    : humanApproved > 0 || aiComplete > 0
                        ? PipelineRunState.inProgress
                        : PipelineRunState.idle;

    return PipelineStatus(
      boardId: boardId,
      runId: steps.any((s) => s.hasRun) ? 'run-fake-$boardId' : null,
      status: state,
      totalSteps: total,
      aiComplete: aiComplete,
      humanApproved: humanApproved,
      running: running,
      failed: failed,
      pending: pending,
      progressPct: total > 0 ? (humanApproved * 100) ~/ total : 0,
      totalCostDollars: totalCost,
      awaitingStep: awaitingStep,
      steps: [
        for (final step in steps)
          PipelineStep(
            stepId: step.stepId,
            title: step.title,
            status: step.status,
            stage: step.stage,
            executor: step.executor,
            dependsOn: step.dependsOn,
            aiResult: step.aiResult,
            error: step.error,
            durationSecs: step.hasRun ? step.durationSecs : null,
            costDollars: step.costDollars,
            isReviewHold: step.reviewHold,
            waitingOn: step.reviewHold ? step.waitingOn : null,
            isLocalGate: step.localGate &&
                step.status == PipelineStepState.aiComplete,
          ),
      ],
    );
  }

  @override
  Future<bool> pipelineApprove(String boardId, String stepId) async {
    final step = _step(boardId, stepId);
    if (step == null || step.status != PipelineStepState.aiComplete) {
      return false;
    }
    // An unscoped approve cannot clear a producer-review hold — that gate has
    // an assignee, so it only moves through [pipelineApproveAs].
    if (step.reviewHold) return false;
    step.status = PipelineStepState.humanApproved;
    return true;
  }

  @override
  Future<PipelineAck> pipelineApproveAs(
      String boardId, String stepId, String reviewer) async {
    final step = _step(boardId, stepId);
    if (step == null) {
      return const PipelineAck(success: false, error: 'step not found');
    }
    final refusal = _gateRefusal(step, reviewer);
    if (refusal != null) return PipelineAck(success: false, error: refusal);
    step.status = PipelineStepState.humanApproved;
    return PipelineAck.ok;
  }

  @override
  Future<bool> pipelineReject(String boardId, String stepId) async {
    final step = _step(boardId, stepId);
    if (step == null || step.status != PipelineStepState.aiComplete) {
      return false;
    }
    if (step.reviewHold) return false;
    step.status = PipelineStepState.failed;
    step.error = 'Rejected at the gate';
    return true;
  }

  @override
  Future<PipelineAck> pipelineRejectAs(
      String boardId, String stepId, String reviewer) async {
    final step = _step(boardId, stepId);
    if (step == null) {
      return const PipelineAck(success: false, error: 'step not found');
    }
    final refusal = _gateRefusal(step, reviewer);
    if (refusal != null) return PipelineAck(success: false, error: refusal);
    step.status = PipelineStepState.failed;
    step.error = 'Rejected by $reviewer';
    return PipelineAck.ok;
  }

  @override
  Future<bool> pipelineRetry(String boardId, String stepId) async =>
      pipelineResetStep(boardId, stepId);

  @override
  Future<bool> pipelineReset(String boardId) async {
    final steps = _pipelines[boardId];
    if (steps == null) return false;
    for (final step in steps) {
      step.reset();
    }
    return true;
  }

  @override
  Future<bool> pipelineResetStep(String boardId, String stepId) async {
    final step = _step(boardId, stepId);
    if (step == null) return false;
    step.reset();
    return true;
  }

  @override
  Future<StepRunResult> pipelineRunStepLocal(
      String boardId, String stepId) async {
    final step = _step(boardId, stepId);
    if (step == null) {
      return const StepRunResult(
        success: false,
        error: 'step not found (compile first)',
      );
    }
    if (step.executor != 'local') {
      return const StepRunResult(success: false, error: 'not_locally_bound');
    }
    if (step.reviewHold && step.status == PipelineStepState.aiComplete) {
      return StepRunResult(
        success: false,
        isGated: true,
        error: 'needs_human: waiting on ${step.waitingOn}',
      );
    }
    step.status = PipelineStepState.aiComplete;
    step.hasRun = true;
    step.error = null;
    step.aiResult = '{"step":"${step.stepId}","ok":true}';
    return StepRunResult(
      success: true,
      summary: 'Ran ${step.title} locally',
      findings: step.stepId.length,
    );
  }

  @override
  Future<StepTravel> stepEditTravel(
      String boardId, String cellId, StepTravelDirection direction) async {
    final step = _step(boardId, cellId);
    if (step == null) {
      return const StepTravel(error: 'cell not found on this board');
    }
    final history = _stepHistory.putIfAbsent(
      '$boardId/${step.stepId}',
      () => _FakeStepHistory.seeded(step.title),
    );
    final moved = direction == StepTravelDirection.undo
        ? history.undo()
        : history.redo();
    if (!moved) {
      return StepTravel(
        undoDepth: history.undoDepth,
        redoDepth: history.redoDepth,
        error: direction == StepTravelDirection.undo
            ? 'nothing to undo'
            : 'nothing to redo',
      );
    }
    return StepTravel(
      content: history.content,
      undoDepth: history.undoDepth,
      redoDepth: history.redoDepth,
    );
  }

  @override
  Future<BoardWorkflowState> boardWorkflowState(String boardId) async {
    final board = _board(boardId);
    // Deploying is what locks a board and gives it a dashboard, so the fixture's
    // deployed flag drives all three.
    final deployed = board?.isDeployed ?? false;
    return BoardWorkflowState(
      boardId: boardId,
      isDeployed: deployed,
      hasDashboard: deployed,
      isLocked: deployed,
      updatedAt: deployed ? _epoch : null,
    );
  }

  /// Why [reviewer] may not clear this gate, or null when they may.
  String? _gateRefusal(_FakePipelineStep step, String reviewer) {
    if (step.status != PipelineStepState.aiComplete) {
      return 'step is not awaiting approval';
    }
    // The pre-dispatch side-effect gate is the operator's to release; only the
    // real producer-review hold locks to its assignee.
    if (step.reviewHold && step.waitingOn != null && step.waitingOn != reviewer) {
      return "review gate is waiting on '${step.waitingOn}'";
    }
    return null;
  }

  _FakePipelineStep? _step(String boardId, String stepId) {
    for (final step in _pipelines[boardId] ?? const <_FakePipelineStep>[]) {
      if (step.stepId == stepId) return step;
    }
    return null;
  }

  CyanBoard? _board(String boardId) {
    for (final g in _groups) {
      for (final w in g.workspaces) {
        for (final b in w.boards) {
          if (b.id == boardId) return b;
        }
      }
    }
    return null;
  }

  List<CyanGroup> _buildGroups() {
    int n = 0;
    CyanBoard board(
      String id,
      String wsId,
      String name, {
      BoardFaceKind face = BoardFaceKind.workflow,
      bool pinned = false,
      int rating = 0,
      List<String> labels = const [],
      int steps = 0,
      bool deployed = false,
    }) {
      n++;
      return CyanBoard(
        id: id,
        workspaceId: wsId,
        name: name,
        activeFace: face,
        isPinned: pinned,
        rating: rating,
        labels: labels,
        stepCount: steps,
        isDeployed: deployed,
        createdAt: _epoch.subtract(Duration(days: n)),
        lastModified: _epoch.subtract(Duration(hours: n * 3)),
      );
    }

    // Group 1: Engineering — 4 boards
    final eng = CyanGroup(
      id: 'g-eng',
      name: 'Engineering',
      colorHex: '#66D9EF',
      peerCount: 3,
      workspaces: [
        CyanWorkspace(
          id: 'w-eng-backend',
          groupId: 'g-eng',
          name: 'Backend Services',
          boards: [
            board('b-eng-1', 'w-eng-backend', 'Render + Review Pipeline',
                face: BoardFaceKind.dashboard,
                pinned: true,
                rating: 5,
                labels: ['approved', 'running'],
                steps: 4,
                deployed: true),
            board('b-eng-2', 'w-eng-backend', 'Database Schema',
                face: BoardFaceKind.workflow,
                rating: 4,
                labels: ['development'],
                steps: 3),
          ],
        ),
        CyanWorkspace(
          id: 'w-eng-infra',
          groupId: 'g-eng',
          name: 'Infrastructure',
          boards: [
            board('b-eng-3', 'w-eng-infra', 'CI/CD Pipeline',
                face: BoardFaceKind.workflow,
                labels: ['in-progress'],
                steps: 5),
            board('b-eng-4', 'w-eng-infra', 'Deployment Notes',
                face: BoardFaceKind.notes, rating: 2),
          ],
        ),
      ],
    );

    // Group 2: Product — 3 boards
    final product = CyanGroup(
      id: 'g-product',
      name: 'Product',
      colorHex: '#A6E22E',
      peerCount: 2,
      workspaces: [
        CyanWorkspace(
          id: 'w-prod-roadmap',
          groupId: 'g-product',
          name: 'Roadmap',
          boards: [
            board('b-prod-1', 'w-prod-roadmap', 'Q3 2026 Goals',
                face: BoardFaceKind.workflow,
                pinned: true,
                rating: 5,
                labels: ['approved'],
                steps: 4,
                deployed: true),
            board('b-prod-2', 'w-prod-roadmap', 'Feature Prioritization',
                face: BoardFaceKind.workflow, steps: 2),
          ],
        ),
        CyanWorkspace(
          id: 'w-prod-research',
          groupId: 'g-product',
          name: 'User Research',
          boards: [
            board('b-prod-3', 'w-prod-research', 'Interview Notes',
                face: BoardFaceKind.notes, rating: 4),
          ],
        ),
      ],
    );

    // Group 3: Design — 3 boards
    final design = CyanGroup(
      id: 'g-design',
      name: 'Design',
      colorHex: '#F92672',
      peerCount: 1,
      workspaces: [
        CyanWorkspace(
          id: 'w-design-ui',
          groupId: 'g-design',
          name: 'UI Components',
          boards: [
            board('b-des-1', 'w-design-ui', 'Design System',
                face: BoardFaceKind.workflow,
                pinned: true,
                rating: 5,
                labels: ['approved', 'design'],
                steps: 6,
                deployed: true),
            board('b-des-2', 'w-design-ui', 'Component Specs',
                face: BoardFaceKind.workflow, steps: 3),
            board('b-des-3', 'w-design-ui', 'Accessibility Notes',
                face: BoardFaceKind.notes, rating: 4),
          ],
        ),
      ],
    );

    return [eng, product, design];
  }

  // ---- device prefs + the craft-role vocabulary -----------------------------
  //
  // The engine OWNS the craft-role vocabulary and re-checks it at every write
  // door, so the fake keeps one copy of it here and enforces it the same way:
  // an unknown role is REFUSED and the pref is left untouched.

  /// The engine's `PRODUCTION_ROLE_VOCAB`, in its order.
  static const List<String> _craftRoles = [
    'producer',
    'assistant_editor',
    'editor',
    'director',
    'colorist',
    'sound',
    'studio_exec',
  ];

  /// The engine's `FORMAT_TYPE_VOCAB`.
  static const List<String> _formatTypes = [
    'promo',
    'commercial',
    'short_film',
    'episodic',
    'feature',
  ];

  /// The device-LOCAL craft-role pref. Empty means unset, which is what the
  /// engine stores for "no role" too.
  String _productionRole = '';

  @override
  Future<String?> buildCommit() async => 'fake0000';

  @override
  Future<bool> deleteIdentity() async {
    // A wipe really wipes: the profile goes, and the device-local prefs that
    // were keyed to it go with it.
    profile = null;
    _productionRole = '';
    _anonSessions.clear();
    _ssoSession = null;
    return true;
  }

  @override
  Future<String?> getProductionRole() async =>
      _productionRole.isEmpty ? null : _productionRole;

  @override
  Future<bool> setProductionRole(String role) async {
    if (role.isNotEmpty && !_craftRoles.contains(role)) return false;
    _productionRole = role;
    return true;
  }

  @override
  Future<SelectorResolution> selectorResolve(String role, String formatType,
      {String tenantId = ''}) async {
    // Role first, then format — the same order the engine refuses in, so a
    // probe of both reads back the role catalog rather than the format one.
    if (!_craftRoles.contains(role)) {
      return SelectorResolution(
        error: 'unknown_role',
        given: role,
        allowed: List<String>.of(_craftRoles),
      );
    }
    if (!_formatTypes.contains(formatType)) {
      return SelectorResolution(
        error: 'unknown_format_type',
        given: formatType,
        allowed: List<String>.of(_formatTypes),
      );
    }
    return SelectorResolution(primarySurface: _primarySurface(role));
  }

  /// The engine's deterministic role → landing-surface map.
  static String _primarySurface(String role) => switch (role) {
        'studio_exec' => 'board_wall',
        'producer' => 'shows',
        'director' => 'review_player',
        'editor' || 'colorist' || 'sound' => 'notebook',
        'assistant_editor' => 'ae_queue',
        _ => 'board_wall',
      };

  @override
  Future<String?> friendlyNodeId(String nodeId) async {
    // The engine's own rule: abbreviate anything longer than 8 characters, and
    // hand a short id straight back.
    if (nodeId.isEmpty) return null;
    if (nodeId.length <= 8) return nodeId;
    return 'User-${nodeId.substring(0, 4).toUpperCase()}';
  }

  // ---- SSO session grants ----------------------------------------------------
  //
  // A refusal must leave the installed session ALONE — the fake enforces that,
  // so a screen cannot sign itself out by re-installing a bad grant.

  SsoSession? _ssoSession;

  @override
  Future<SsoSession> ssoInstallGrant(
      String grantToken, String trustJson) async {
    if (grantToken.isEmpty) {
      return const SsoSession(active: false, reason: 'missing grant_token');
    }
    final Map<String, dynamic> trust;
    try {
      final decoded = jsonDecode(trustJson);
      if (decoded is! Map<String, dynamic>) {
        return const SsoSession(active: false, reason: 'missing trust_json');
      }
      trust = decoded;
    } catch (_) {
      return const SsoSession(active: false, reason: 'missing trust_json');
    }
    final tenant = trust['tenant'] as String? ?? '';
    if (tenant.isEmpty) {
      return const SsoSession(active: false, reason: 'missing tenant');
    }
    // At least ONE trust source, the same requirement the engine verifies
    // against — a grant with nothing to check it by is never installed.
    final orgDid = trust['org_did'] as String? ?? '';
    final legacyPem = trust['legacy_rsa_public_pem'] as String? ?? '';
    if (orgDid.isEmpty && legacyPem.isEmpty) {
      return const SsoSession(active: false, reason: 'no trust material');
    }
    final role = _grantRoles[_hash(grantToken) % _grantRoles.length];
    // Re-installing an equivalent grant is idempotent: the engine would verify
    // it and replace the session with one that reads the same.
    final installed = _ssoSession;
    if (installed != null &&
        installed.active &&
        installed.tenant == tenant &&
        installed.role == role) {
      return installed;
    }
    final graceSecs = (trust['grace_secs'] as num?)?.toInt() ?? 604800;
    return _ssoSession = SsoSession(
      active: true,
      tenant: tenant,
      role: role,
      // Off the fixed epoch, so a countdown rendered from it is byte-stable.
      exp: _stamp(0) + 24 * 3600 + graceSecs,
    );
  }

  @override
  Future<void> ssoSignOut() async {
    _ssoSession = null;
  }

  // ---- anonymous sessions ---------------------------------------------------
  //
  // Per SCOPE, and revealing is ONE WAY — the fake enforces both, so a screen
  // cannot un-reveal by toggling.

  final Map<String, _FakeAnonSession> _anonSessions = {};

  @override
  Future<AnonymousSession?> createAnonymousSession(String scopeId) async {
    if (scopeId.isEmpty) return null;
    final existing = _anonSessions[scopeId];
    // Already revealed: the mask cannot be put back on in this scope.
    if (existing != null && existing.revealed) return null;
    final session = existing ??
        (_anonSessions[scopeId] = _FakeAnonSession(
          handle: _mintHandle(scopeId),
          ephemeralKey: _digest('eph|$scopeId'),
        ));
    return AnonymousSession(
      handle: session.handle,
      scopeId: scopeId,
      ephemeralKey: session.ephemeralKey,
    );
  }

  @override
  Future<AnonymousSession?> revealAnonymousIdentity(String scopeId) async {
    final session = _anonSessions[scopeId];
    if (session == null || session.revealed) return null;
    session.revealed = true;
    return AnonymousSession(
      handle: session.handle,
      scopeId: scopeId,
      ephemeralKey: session.ephemeralKey,
      revealed: true,
      realName: profile?.label,
    );
  }

  @override
  Future<AnonymousStatus> getAnonymousStatus(String scopeId) async {
    final session = _anonSessions[scopeId];
    if (session == null) return const AnonymousStatus.none();
    return AnonymousStatus(
      anonymous: !session.revealed,
      handle: session.handle,
      revealed: session.revealed,
    );
  }

  @override
  Future<bool> exitAnonymousMode(String scopeId) async =>
      _anonSessions.remove(scopeId) != null;

  /// A stable, pronounceable handle derived from the scope — deterministic, so
  /// a golden that renders a masked identity stays byte-stable.
  static String _mintHandle(String scopeId) {
    const adjectives = ['amber', 'cobalt', 'crimson', 'jade', 'slate'];
    const creatures = ['heron', 'lynx', 'marten', 'osprey', 'vireo'];
    final h = _hash(scopeId);
    return '${adjectives[h % adjectives.length]}-'
        '${creatures[(h ~/ 5) % creatures.length]}-'
        '${(h % 4096).toRadixString(16).padLeft(3, '0')}';
  }

  // ---- roster ----------------------------------------------------------------
  //
  // The engine's roster is PERSISTENT: an offline member keeps their cached
  // name and last-seen rather than dropping off. Seeded that way — four live
  // neighbours and one who has left — with the member carrying this device's
  // node id standing in for "you".

  late final Map<String, List<GroupMember>> _groupMembers = {
    'g-eng': [
      GroupMember(
          peerId: _localNodeId,
          name: 'Ada Byron',
          online: true,
          lastSeen: _stamp(0)),
      GroupMember(
          peerId: 'node-mara-7c31',
          name: 'Mara',
          online: true,
          lastSeen: _stamp(0)),
      GroupMember(
          peerId: 'node-priya-22b8',
          name: 'Priya',
          online: true,
          lastSeen: _stamp(0)),
      GroupMember(
          peerId: 'node-ravi-91de',
          name: 'Ravi Shah',
          online: true,
          lastSeen: _stamp(0)),
      // No cached profile name yet, and gone for a while — the roster keeps the
      // row and renders the short id.
      GroupMember(peerId: 'node-jun', online: false, lastSeen: _stamp(3)),
    ],
    'g-product': [
      GroupMember(
          peerId: _localNodeId,
          name: 'Ada Byron',
          online: true,
          lastSeen: _stamp(0)),
      GroupMember(
          peerId: 'node-mara-7c31',
          name: 'Mara',
          online: true,
          lastSeen: _stamp(0)),
    ],
    'g-design': [
      GroupMember(
          peerId: _localNodeId,
          name: 'Ada Byron',
          online: true,
          lastSeen: _stamp(0)),
    ],
  };

  @override
  Future<List<GroupMember>> getGroupMembers(String groupId) async =>
      List<GroupMember>.of(_groupMembers[groupId] ?? const []);

  /// Unix seconds [daysAgo] before the fixed epoch, so "last seen" copy is
  /// stable rather than clock-dependent.
  static int _stamp(int daysAgo) =>
      _epoch.subtract(Duration(days: daysAgo)).millisecondsSinceEpoch ~/ 1000;

  // ---- scoped notes ----------------------------------------------------------
  //
  // The one store behind BOTH the constitution chain and the roster's craft-role
  // provenance — exactly as the engine keys them, so a read finds what a write
  // put there. `board` notes are anchored on the board, `group` notes on the
  // GROUP, and the tenant is DERIVED from the anchor rather than passed in.

  late final List<CyanNote> _noteStore = [
    CyanNote(
      id: 'n-const-eng-1',
      boardId: 'b-eng-1',
      tenantId: 'g-eng',
      authorId: _localNodeId,
      authorName: 'Ada Byron',
      text: 'Nothing ships outside the device before the review gate.',
      createdAt: _stamp(9),
      updatedAt: _stamp(9),
      scope: 'board',
      kind: 'constitution',
      authorRole: 'producer',
    ),
    CyanNote(
      id: 'n-pref-eng-1',
      boardId: 'b-eng-1',
      tenantId: 'g-eng',
      authorId: _localNodeId,
      authorName: 'Ada Byron',
      text: 'Cut proxies at 1080p; keep the masters untouched.',
      createdAt: _stamp(8),
      updatedAt: _stamp(8),
      scope: 'board',
      kind: 'preference',
      authorRole: 'producer',
    ),
    // Craft-role provenance for another member: the engine stamps `author_role`
    // on what it persists, and the roster reads roles from exactly there.
    CyanNote(
      id: 'n-note-eng-1',
      boardId: 'b-eng-1',
      tenantId: 'g-eng',
      authorId: 'node-ravi-91de',
      authorName: 'Ravi Shah',
      text: 'Conformed the offline against the EDL; two shots need a retime.',
      createdAt: _stamp(7),
      updatedAt: _stamp(7),
      scope: 'board',
      kind: 'editor-note',
      authorRole: 'editor',
    ),
  ];

  /// Monotonic clock for writes, so later notes sort after earlier ones without
  /// depending on the wall clock.
  int _noteSeq = 0;

  @override
  Future<List<CyanNote>> noteListScoped(String boardId, String scope,
      {String kind = ''}) async {
    // The ENGINE derives the anchor from the scope: a `group` read of a BOARD
    // resolves to that board's group. Reads match writes because both go
    // through this same derivation.
    final anchor = (scope == 'group' || scope == 'tenant')
        ? _groupIdFor(boardId)
        : boardId;
    return [
      for (final note in _noteStore)
        if (note.scope == scope &&
            note.boardId == anchor &&
            (kind.isEmpty || note.kind == kind))
          note,
    ]..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
  }

  @override
  Future<void> notePutScoped(String boardId, String text,
      {String scope = 'board', String kind = 'editor-note'}) async {
    final anchor = (scope == 'group' || scope == 'tenant')
        ? _groupIdFor(boardId)
        : boardId;
    final stamp = _stamp(0) + (++_noteSeq);
    _noteStore.add(CyanNote(
      id: 'n-$kind-$anchor-$_noteSeq',
      boardId: anchor,
      tenantId: _groupIdFor(boardId),
      authorId: profile?.nodeId ?? '',
      authorName: profile?.label ?? '',
      text: text,
      createdAt: stamp,
      updatedAt: stamp,
      scope: scope,
      kind: kind,
      // Provenance is whatever this device authors as RIGHT NOW — null when it
      // has not chosen a craft role, never guessed.
      authorRole: _productionRole.isEmpty ? null : _productionRole,
    ));
  }

  // ---- board notes: the same store read WITHOUT a scope ----------------------
  //
  // The engine's unscoped list is "every note anchored on this board", tenant
  // being the board's group — so it answers off the SAME `_noteStore` the
  // scoped verbs use rather than a second one that could drift from it.

  @override
  Future<List<CyanNote>> noteList(String boardId) async => [
        for (final note in _noteStore)
          if (note.boardId == boardId) note,
      ]..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));

  @override
  Future<void> notePut(String boardId, String text,
      {String? noteId, String? tenantId}) async {
    final stamp = _stamp(0) + (++_noteSeq);
    final existing = noteId == null
        ? -1
        : _noteStore.indexWhere((note) => note.id == noteId);
    // A known id EDITS in place (last write wins on `updatedAt`) and keeps the
    // note's original authorship; anything else mints a new note.
    if (existing >= 0) {
      final prior = _noteStore[existing];
      _noteStore[existing] = CyanNote(
        id: prior.id,
        boardId: prior.boardId,
        tenantId: prior.tenantId,
        authorId: prior.authorId,
        authorName: prior.authorName,
        text: text,
        createdAt: prior.createdAt,
        updatedAt: stamp,
        scope: prior.scope,
        kind: prior.kind,
        authorRole: prior.authorRole,
      );
      return;
    }
    _noteStore.add(CyanNote(
      id: noteId ?? 'n-editor-note-$boardId-$_noteSeq',
      boardId: boardId,
      // Omitted tenant ⇒ DERIVED from the board's group, exactly as the engine
      // derives it, so a later scoped read finds this note.
      tenantId: tenantId ?? _groupIdFor(boardId),
      authorId: profile?.nodeId ?? '',
      authorName: profile?.label ?? '',
      text: text,
      createdAt: stamp,
      updatedAt: stamp,
      authorRole: _productionRole.isEmpty ? null : _productionRole,
    ));
  }

  @override
  Future<void> noteDelete(String id) async =>
      _noteStore.removeWhere((note) => note.id == id);

  // ---- timecoded notes -------------------------------------------------------
  //
  // A separate store because the engine keeps them apart too: these are
  // notebook cells pinned to a moment in an asset, not board notes. Seeded as a
  // real review pass — a QC flag the AI already answered, a revision request
  // still waiting on one, and a reply threaded under the flag.

  late final List<TimecodeNote> _timecodeNotes = [
    TimecodeNote(
      id: 'tc-eng-1',
      boardId: 'b-eng-1',
      timecodeSeconds: 42.5,
      content: 'Dialogue clips on the wide — needs a level pass before the mix.',
      noteType: 'qc_issue',
      author: 'Ravi Shah',
      createdAt: _stamp(3).toDouble(),
      pipelineStepId: 'step-audio-conform',
      pipelinePhase: 'review',
      aiReviewed: true,
      actionSkill: 'qc',
      actionStatus: 'complete',
      actionResult:
          '{"analysis":"Peak at -0.2 dBFS across three lines.",'
          '"action":"Re-run the level pass at -14 LUFS.",'
          '"rerun_step":"step-audio-conform","priority":"high"}',
      actionModel: 'lens-local',
      aiFlagsNearby: const [
        TimecodeAiFlag(
          timecodeSeconds: 41.9,
          description: 'Loudness over target for 1.4s.',
          severity: 'warning',
          sourceStep: 'step-audio-conform',
        ),
      ],
    ),
    TimecodeNote(
      id: 'tc-eng-2',
      boardId: 'b-eng-1',
      timecodeSeconds: 44.0,
      content: 'Agreed — flagging for the mixer, not a re-conform.',
      noteType: 'comment',
      author: 'Ada Byron',
      createdAt: _stamp(3).toDouble(),
      replyTo: 'tc-eng-1',
      pipelineStepId: 'step-audio-conform',
      pipelinePhase: 'review',
    ),
    TimecodeNote(
      id: 'tc-eng-3',
      boardId: 'b-eng-1',
      timecodeSeconds: 118.25,
      content: 'Title card sits two frames long; trim on the outgoing cut.',
      noteType: 'revision',
      author: 'Ada Byron',
      createdAt: _stamp(2).toDouble(),
      pipelineStepId: 'step-titles',
      pipelinePhase: 'review',
      actionSkill: 'qc',
      actionStatus: 'pending',
    ),
  ];

  @override
  Future<List<TimecodeNote>> loadTimecodeNotes(String boardId) async => [
        for (final note in _timecodeNotes)
          if (note.boardId == boardId) note,
      ]..sort((a, b) => a.timecodeSeconds.compareTo(b.timecodeSeconds));

  @override
  Future<bool> saveTimecodeNote(TimecodeNote note) async {
    // The engine's save is an upsert keyed on the note id; an empty id is a
    // note it could not key, which is the one shape it refuses.
    if (note.id.isEmpty) return false;
    final at = _timecodeNotes.indexWhere((n) => n.id == note.id);
    if (at >= 0) {
      _timecodeNotes[at] = note;
    } else {
      _timecodeNotes.add(note);
    }
    return true;
  }

  @override
  Future<TimecodeNoteAction> actOnTimecodeNote(TimecodeNote note) async {
    final result = jsonEncode({
      'analysis': 'Reviewed "${note.content}" at '
          '${note.timecodeSeconds.toStringAsFixed(1)}s.',
      'action': note.actionSkill == null
          ? 'No skill bound to this note; routing to the reviewer.'
          : 'Run the ${note.actionSkill} skill over this range.',
      'rerun_step': note.pipelineStepId,
      'priority': note.noteType == 'qc_issue' ? 'high' : 'medium',
    });
    // The engine re-saves the note with its answer attached before returning,
    // so a caller that re-reads the list sees the result without patching.
    await saveTimecodeNote(TimecodeNote(
      id: note.id,
      boardId: note.boardId,
      timecodeSeconds: note.timecodeSeconds,
      content: note.content,
      noteType: note.noteType,
      author: note.author,
      createdAt: note.createdAt,
      replyTo: note.replyTo,
      threadCount: note.threadCount,
      pipelineStepId: note.pipelineStepId,
      pipelinePhase: note.pipelinePhase,
      aiReviewed: true,
      humanApproved: note.humanApproved,
      actionSkill: note.actionSkill,
      actionStatus: 'complete',
      actionResult: result,
      actionModel: 'lens-local',
      aiFlagsNearby: note.aiFlagsNearby,
    ));
    return TimecodeNoteAction(success: true, result: result);
  }

  @override
  Future<String?> exportNotesMarkdown(String boardId) async {
    // The engine's own rendering, followed exactly: a header carrying the
    // totals, then the ROOT notes grouped by the pipeline step they were raised
    // against (steps in name order, an unstepped note under `general`), each
    // with its AI result and its replies quoted beneath it.
    final notes = [for (final n in _timecodeNotes) if (n.boardId == boardId) n];
    final roots = [for (final n in notes) if (n.replyTo == null) n];
    final replies = [for (final n in notes) if (n.replyTo != null) n];

    final byStep = <String, List<TimecodeNote>>{};
    for (final note in roots) {
      byStep.putIfAbsent(note.pipelineStepId ?? 'general', () => []).add(note);
    }

    final md = StringBuffer()
      ..write('# Review Notes Timeline\n\n')
      ..write('**Board:** `$boardId`\n')
      ..write('**Total notes:** ${notes.length} (${roots.length} threads, '
          '${replies.length} replies)\n\n')
      ..write('---\n\n');

    for (final step in byStep.keys.toList()..sort()) {
      md.write('## $step\n\n');
      for (final note in byStep[step]!) {
        final status = note.humanApproved ? ' ✅' : '';
        md.write('**${_timecode(note.timecodeSeconds)}** '
            '${_noteIcon(note.noteType)} **${note.author}**: '
            '${note.content}$status\n\n');
        final result = note.actionResult;
        if (result != null) {
          final parsed = _decodeResult(result);
          if (parsed == null) {
            md.write('> 🤖 $result\n');
          } else {
            final analysis = parsed['analysis'];
            if (analysis is String) md.write('> 🤖 **AI:** $analysis\n');
            final action = parsed['recommended_action'];
            if (action is String) md.write('> → $action\n');
          }
          md.write('\n');
        }
        for (final reply in replies) {
          if (reply.replyTo != note.id) continue;
          md.write('> **${reply.author}**: ${reply.content}\n');
          final replyResult = reply.actionResult;
          if (replyResult == null) continue;
          final analysis = _decodeResult(replyResult)?['analysis'];
          if (analysis is String) md.write('> > 🤖 $analysis\n');
        }
        md.write('\n');
      }
    }
    return md.toString();
  }

  /// HH:MM:SS, truncated to the second exactly as the engine formats it.
  static String _timecode(double seconds) {
    final total = seconds.floor();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(total ~/ 3600)}:${two((total % 3600) ~/ 60)}:'
        '${two(total % 60)}';
  }

  /// The engine's note-type glyphs; anything outside the vocabulary gets its
  /// generic one rather than nothing.
  static String _noteIcon(String noteType) => switch (noteType) {
        'qc_issue' => '⚠️',
        'revision' => '✏️',
        'approved' => '✅',
        'comment' => '💬',
        _ => '📝',
      };

  /// An action result is JSON when a skill wrote it and prose when a human did;
  /// null here means "quote it verbatim", which is what the engine does.
  static Map<String, dynamic>? _decodeResult(String result) {
    try {
      final decoded = jsonDecode(result);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// The group a board sits in; an id that is already a group answers itself,
  /// which is how a group-anchored write addresses the same key a read looks in.
  String _groupIdFor(String anchor) {
    for (final group in _groups) {
      if (group.id == anchor) return anchor;
      for (final workspace in group.workspaces) {
        for (final board in workspace.boards) {
          if (board.id == anchor) return group.id;
        }
      }
    }
    return anchor;
  }

  // ---- constitution ----------------------------------------------------------
  //
  // The merge chain, least-specific FIRST: the GROUP's rules, then the board's.
  // Preferences are resolved off the same chain but kept APART from the
  // constitution — a soft preference is never a rule a run must obey.

  /// The chain for one board in one note kind, group-scope before board-scope.
  List<CyanNote> _chain(String boardId, String kind) {
    final groupId = _groupIdFor(boardId);
    final rows = [
      for (final note in _noteStore)
        if (note.kind == kind &&
            ((note.scope == 'group' && note.boardId == groupId) ||
                (note.scope == 'board' && note.boardId == boardId)))
          note,
    ];
    // Group rules first, then the board's; ties broken by write order so the
    // merged text is stable.
    rows.sort((a, b) {
      final scoped = _scopeRank(a.scope).compareTo(_scopeRank(b.scope));
      return scoped != 0 ? scoped : a.updatedAt.compareTo(b.updatedAt);
    });
    return rows;
  }

  static int _scopeRank(String scope) => switch (scope) {
        'tenant' => 0,
        'group' => 1,
        'board' => 2,
        _ => 3,
      };

  @override
  Future<ResolvedConstitution> constitutionResolved(String boardId) async {
    final rules = _chain(boardId, 'constitution');
    final prefs = _chain(boardId, 'preference');
    return ResolvedConstitution(
      markdown: [for (final n in rules) n.text].join('\n'),
      preferences: [for (final n in prefs) n.text].join('\n'),
      // An empty resolve still carries a real hash — empty is not unknown.
      hash: _digest([for (final n in [...rules, ...prefs]) n.id].join('|')),
      contributing: [
        for (final n in rules)
          ConstitutionContribution(
            id: n.id,
            scope: n.scope,
            kind: n.kind,
            updatedAt: n.updatedAt,
          ),
      ],
    );
  }

  @override
  Future<EffectiveConstitution> constitutionEffective(String boardId) async {
    final rules = _chain(boardId, 'constitution');
    return EffectiveConstitution(
      markdown: [for (final n in rules) n.text].join('\n'),
      hash: _digest([for (final n in rules) n.id].join('|')),
      contributingIds: [for (final n in rules) n.id],
      hard: [
        for (final n in rules)
          if (_hardCategory(n) != null)
            HardRule(
              id: n.id,
              scope: n.scope,
              category: _hardCategory(n)!,
              // The note text VERBATIM — never a rewording.
              text: n.text,
            ),
      ],
    );
  }

  /// The engine's payload-less hard classification: a `constitution` row is
  /// HARD iff its text hits the hard lexicon, and records `technical`.
  /// Everything else — a preference above all — is soft by definition.
  static String? _hardCategory(CyanNote note) {
    if (note.kind != 'constitution') return null;
    return _lexiconMatches(note.text) ? 'technical' : null;
  }

  /// The modal half of the lexicon, plus the number+unit / resolution /
  /// timecode halves — ANY hit is enough, exactly as the engine reads it.
  static bool _lexiconMatches(String text) =>
      RegExp(r'\b(must|never|always|required|only|max|min)\b',
              caseSensitive: false)
          .hasMatch(text) ||
      RegExp(r'-?\d+(\.\d+)?\s*(LUFS|dBTP|dB|fps|Hz|kHz|Mbps|kbps|px)',
              caseSensitive: false)
          .hasMatch(text) ||
      RegExp(r'\b\d+\s*[xX]\s*\d+\b').hasMatch(text) ||
      RegExp(r'\b\d{2}:\d{2}:\d{2}[:;]\d{2}\b').hasMatch(text);

  // ---- grants + portable group bundles ---------------------------------------
  //
  // The grants the fake mints are really CHECKED when they come back: a payload
  // whose signature, group or expiry does not line up is REFUSED. A screen can
  // no more forge a join here than it could against the engine.

  /// The grant roles the engine's `Role::parse` admits.
  static const List<String> _grantRoles = [
    'owner',
    'admin',
    'member',
    'viewer',
    'guest',
  ];

  /// This device's X25519 bundle public key — stable across the fake's life,
  /// the way the engine derives one deterministically from the node identity.
  static const String _bundlePubkeyHex =
      'b34301f7c0a94e2d8f61aa5c7d0e93b28c41f6a07e5d2b93c8a1f04d6e72b95a';

  @override
  Future<String?> bundlePubkey() async => profile == null ? null : _bundlePubkeyHex;

  @override
  Future<GrantQrIssue> issueGrantQr(String groupId, String role,
      {int ttlSeconds = 0}) async {
    if (!_grantRoles.contains(role)) {
      return const GrantQrIssue(
        success: false,
        error: 'Unknown role (owner|admin|member|viewer|guest)',
      );
    }
    // Authority gate: a grant may only be minted for a group this device holds.
    final group = _groupOrNull(groupId);
    if (group == null) {
      return const GrantQrIssue(
        success: false,
        error: 'Only the group Owner/Admin may issue a grant',
      );
    }
    final expiry = _stamp(0) + (ttlSeconds == 0 ? 24 * 3600 : ttlSeconds);
    final nonce = _digest('nonce|$groupId|$role|$expiry');
    final qr = jsonEncode({
      'group_id': groupId,
      'group_name': group.name,
      'role': role,
      'expiry': expiry,
      'nonce': nonce,
      'inviter_node_id': profile?.nodeId ?? '',
      'sig': _grantSignature(groupId, role, expiry, nonce),
    });
    return GrantQrIssue(
      success: true,
      qr: qr,
      role: role,
      expiry: expiry,
      nonce: nonce,
    );
  }

  @override
  Future<GrantScanResult> scanGrantQr(String qrPayload) async {
    final Map<String, dynamic> invite;
    try {
      final decoded = jsonDecode(qrPayload);
      if (decoded is! Map<String, dynamic>) {
        return const GrantScanResult(
            success: false, error: 'Grant rejected: not a grant payload');
      }
      invite = decoded;
    } catch (_) {
      return const GrantScanResult(
          success: false, error: 'Grant rejected: malformed payload');
    }

    final groupId = invite['group_id'] as String? ?? '';
    final role = invite['role'] as String? ?? '';
    final expiry = (invite['expiry'] as num?)?.toInt() ?? 0;
    final nonce = invite['nonce'] as String? ?? '';
    // The signature is re-derived and compared — a tampered field fails here.
    if (invite['sig'] != _grantSignature(groupId, role, expiry, nonce)) {
      return const GrantScanResult(
          success: false, error: 'Grant rejected: signature does not verify');
    }
    if (expiry <= _stamp(0)) {
      return const GrantScanResult(
          success: false, error: 'Grant rejected: the grant has expired');
    }

    final known = _groupOrNull(groupId);
    if (known == null) {
      // A grant for a group this device has never seen JOINS it, which is the
      // whole point of an invite.
      _groups = [
        ..._groups,
        CyanGroup(
          id: groupId,
          name: invite['group_name'] as String? ?? groupId,
          colorHex: '#00AEEF',
          peerCount: 0,
          workspaces: const [],
        ),
      ];
    }
    return GrantScanResult(
      success: true,
      groupId: groupId,
      groupName: known?.name ?? invite['group_name'] as String? ?? groupId,
    );
  }

  @override
  Future<GroupExportResult> exportGroup(
      String groupId, String inviteePubkey) async {
    final group = _groupOrNull(groupId);
    if (group == null) {
      return const GroupExportResult(
        success: false,
        error: 'Only the group Owner/Admin may export it',
      );
    }
    if (inviteePubkey.isEmpty) {
      return const GroupExportResult(
          success: false, error: 'Invalid invitee_pubkey');
    }
    final bundle = jsonEncode({
      'v': 1,
      'group_id': groupId,
      'group_name': group.name,
      // SEALED TO one recipient key: the import below re-checks it, so a bundle
      // meant for another device does not open here.
      'sealed_to': inviteePubkey,
      'sig': _bundleSignature(groupId, inviteePubkey),
    });
    return GroupExportResult(
      success: true,
      groupId: groupId,
      bundle: bundle,
      path: '/fake/exports/$groupId.cyangroup',
    );
  }

  @override
  Future<GroupImportResult> importGroup(String bundle) async {
    final Map<String, dynamic> parsed;
    try {
      final decoded = jsonDecode(bundle);
      if (decoded is! Map<String, dynamic>) {
        return const GroupImportResult(
            success: false, error: 'Not a group bundle');
      }
      parsed = decoded;
    } catch (_) {
      return const GroupImportResult(
          success: false, error: 'The bundle could not be read');
    }
    final groupId = parsed['group_id'] as String? ?? '';
    final sealedTo = parsed['sealed_to'] as String? ?? '';
    if (sealedTo != _bundlePubkeyHex) {
      return const GroupImportResult(
          success: false, error: 'The bundle is sealed to another device');
    }
    if (parsed['sig'] != _bundleSignature(groupId, sealedTo)) {
      return const GroupImportResult(
          success: false, error: 'The bundle signature does not verify');
    }
    if (_groupOrNull(groupId) == null) {
      _groups = [
        ..._groups,
        CyanGroup(
          id: groupId,
          name: parsed['group_name'] as String? ?? groupId,
          colorHex: '#00AEEF',
          peerCount: 0,
          workspaces: const [],
        ),
      ];
    }
    return GroupImportResult(success: true, groupId: groupId);
  }

  CyanGroup? _groupOrNull(String groupId) {
    for (final group in _groups) {
      if (group.id == groupId) return group;
    }
    return null;
  }

  static String _grantSignature(
          String groupId, String role, int expiry, String nonce) =>
      _digest('grant|$groupId|$role|$expiry|$nonce|$_bundlePubkeyHex');

  static String _bundleSignature(String groupId, String inviteePubkey) =>
      _digest('bundle|$groupId|$inviteePubkey|$_bundlePubkeyHex');

  // ---- templates: the spine cloned onto a board ------------------------------
  //
  // The catalog has the engine's own two sources: tenant-agnostic BUILTIN seeds
  // (every tenant sees them) and the tenant's own saves (only that tenant does).
  // Saving appends to it; cloning materializes real steps onto a board and
  // leaves an outcome behind for the caller to poll.

  static const String _roletypeCatalogVersion = 'roletype.v1';

  /// The engine's vocabularies, mirrored so a v2 refusal here carries exactly
  /// what the engine's refusal would.
  static const List<String> _formatTypeVocab = [
    'promo',
    'commercial',
    'short_film',
    'episodic',
    'feature',
  ];
  static const List<String> _templateMaturityVocab = ['mvp', 'extensible'];
  static const List<String> _templateScopeVocab = ['tenant', 'user', 'group'];
  static const List<String> _pluginStatusVocab = ['live', 'roadmap'];
  static const List<String> _pluginExecutionVocab = ['device', 'cloud', 'both'];
  static const List<String> _noteKindVocab = [
    'constitution',
    'preference',
    'editor-note',
    'decision',
    'creative-dna',
    'creative-brief',
    'shot-log',
    'lined-script',
    'continuity',
    'script',
    'legal-clearance',
    'turnover',
    'qc-report',
  ];

  /// The kinds a save-FROM-a-board carries along: STANDING guidance, never a
  /// run's working notes.
  static const Set<String> _standingNoteKinds = {'constitution', 'preference'};

  /// The plugin ids the fake's stand-in bundle source can serve. A declared
  /// plugin outside it cannot be fetched — which is how a clone reports a
  /// FAILED auto-install while the board's steps still land.
  static const Set<String> _bundleSourcePlugins = {
    'asset-ingest',
    'ffmpeg',
    'frameio',
    'loudness',
  };

  /// The signer the stand-in source seals its bundles with.
  static const String _bundleSignerDid = 'did:cyan:signer-cyan-core';

  late final List<CyanTemplate> _templates = [
    CyanTemplate(
      id: 'tpl-dailies',
      name: 'Dailies turnaround',
      description: 'Ingest, transcode and publish the day\'s rushes.',
      source: 'builtin',
      createdAt: _stamp(120),
      steps: const [
        TemplateStep(text: 'Ingest today\'s cards', plugin: 'asset-ingest'),
        TemplateStep(text: 'Transcode viewing proxies', plugin: 'ffmpeg'),
        TemplateStep(text: 'Wait for the editor to sign off'),
        TemplateStep(text: 'Publish the dailies to review', plugin: 'frameio'),
      ],
    ),
    CyanTemplate(
      id: 'tpl-finishing',
      name: 'Finishing + delivery',
      description: 'Conform, QC and package to broadcast spec.',
      source: 'builtin:postprod',
      createdAt: _stamp(118),
      steps: const [
        TemplateStep(text: 'Conform the locked cut', stage: 'process'),
        TemplateStep(text: 'Normalize loudness', plugin: 'loudness',
            stage: 'process'),
        TemplateStep(text: 'Run the delivery QC report', stage: 'deliver'),
      ],
      stages: const ['process', 'deliver'],
      // `loudness` is in the source and lands; `spec-deliver` is a roadmap
      // plugin nobody can fetch, so a clone reports it failed and says why.
      plugins: const [
        TemplatePlugin(
          id: 'loudness',
          status: 'live',
          execution: 'device',
          flagshipTool: 'normalize',
          autoInstall: true,
        ),
        TemplatePlugin(
          id: 'spec-deliver',
          status: 'roadmap',
          execution: 'cloud',
          autoInstall: true,
        ),
      ],
    ),
    CyanTemplate(
      id: 'tpl-promo',
      name: 'Promo cutdown',
      description: 'The promo roletype spine: brief, cut, grade, deliver.',
      source: 'builtin:roletype',
      createdAt: _stamp(116),
      steps: const [
        TemplateStep(text: 'Read the brief and pull selects', stage: 'ingest'),
        TemplateStep(text: 'Cut the 30s and the 15s', stage: 'process'),
        TemplateStep(text: 'Grade to the reference', stage: 'enrich'),
        TemplateStep(text: 'Deliver both durations', stage: 'deliver'),
      ],
      formatType: 'promo',
      stages: const ['ingest', 'process', 'enrich', 'deliver'],
      noteKinds: const ['creative-brief', 'constitution'],
      maturity: 'mvp',
      catalogVersion: _roletypeCatalogVersion,
      scope: 'tenant',
      notes: const [
        TemplateNote(
          kind: 'constitution',
          authorRole: 'producer',
          authorName: 'Template',
          text: 'Deliver both durations from the same graded master.',
        ),
      ],
    ),
  ];

  /// Step cells a clone materialized, by board. `loadWorkflow` serves them
  /// after the board's authored steps, exactly where the clone appends them.
  final Map<String, List<WorkflowStep>> _clonedSteps = {};

  /// The LAST clone outcome per board — last-write-wins on a re-clone, and
  /// absent until one finishes, which is what makes polling meaningful.
  final Map<String, TemplateCloneOutcome> _cloneOutcomes = {};

  int _templateSeq = 0;

  @override
  Future<List<CyanTemplate>> templateList({String tenantId = ''}) async => [
        for (final t in _templates)
          // The seeds are global; a user template is the OWNING tenant's alone,
          // so an empty tenant reads the seeds and nothing else.
          if (t.isBuiltin || (tenantId.isNotEmpty && t.tenantId == tenantId)) t,
      ];

  @override
  Future<void> workflowFromTemplate(String templateId, String boardId,
      {String tenantId = ''}) async {
    // Tenant: explicit, else the board's own group — the engine's derivation.
    final tenant = tenantId.isEmpty ? _groupIdFor(boardId) : tenantId;
    final template = _templateOrNull(templateId, tenant);
    // An unknown template clones NOTHING and records no outcome: the poll keeps
    // answering null rather than reporting a clone that never happened.
    if (template == null) return;

    final steps = _clonedSteps.putIfAbsent(boardId, () => []);
    for (final step in template.steps) {
      steps.add(WorkflowStep(
        id: 'cloned-${template.id}-${steps.length + 1}',
        text: step.text,
        tool: step.plugin,
      ));
    }
    // The template's standing notes seed the target board, editable afterwards
    // like any note.
    for (final note in template.notes) {
      await notePutScoped(boardId, note.text, kind: note.kind);
    }
    _cloneOutcomes[boardId] = TemplateCloneOutcome(
      templateId: template.id,
      boardId: boardId,
      tenantId: tenant,
      steps: template.steps.length,
      pluginInstalls: [
        for (final id in template.autoInstallSet) _autoInstall(id),
      ],
    );
  }

  /// One declared plugin's clone-time auto-install: already here, fetched and
  /// landed, or refused by the source — and a refusal never fails the clone.
  TemplatePluginInstall _autoInstall(String pluginId) {
    if (_pluginBundles.containsKey(pluginId)) {
      return TemplatePluginInstall(
        outcome: TemplatePluginInstallOutcome.alreadyPresent,
        pluginId: pluginId,
      );
    }
    if (!_bundleSourcePlugins.contains(pluginId)) {
      return TemplatePluginInstall(
        outcome: TemplatePluginInstallOutcome.failed,
        pluginId: pluginId,
        reason: 'no bundle for $pluginId in the plugin source',
      );
    }
    _pluginBundles[pluginId] = InstalledPlugin(
      id: pluginId,
      version: '1.0.0',
      tools: [InstalledPluginTool(name: '${pluginId.split('-').last}_run')],
    );
    return TemplatePluginInstall(
      outcome: TemplatePluginInstallOutcome.installed,
      pluginId: pluginId,
      signer: _bundleSignerDid,
    );
  }

  @override
  Future<TemplateCloneOutcome?> templateCloneOutcome(String boardId) async =>
      _cloneOutcomes[boardId];

  @override
  Future<TemplateSaveResult> templateSave(String tenantId, String name,
          String description, List<TemplateStep> steps) async =>
      TemplateSaveResult(
          template: _insertUserTemplate(tenantId, name, description, steps));

  @override
  Future<TemplateSaveResult> templateSaveFromBoard(String tenantId, String name,
      String description, List<TemplateStep> steps, String boardId) async {
    // The board's STANDING notes travel with the template; a run's working
    // notes (editor-note, decision, …) stay behind.
    final standing = [
      for (final note in _noteStore)
        if (note.boardId == boardId && _standingNoteKinds.contains(note.kind))
          TemplateNote(
            kind: note.kind,
            authorRole: note.authorRole ?? '',
            authorName: note.authorName,
            text: note.text,
          ),
    ];
    return TemplateSaveResult(
      template: _insertUserTemplate(tenantId, name, description, steps,
          notes: standing),
    );
  }

  @override
  Future<TemplateSaveResult> templateSaveV2(
      String tenantId, CyanTemplate template) async {
    // The engine's validation ladder, in the engine's ORDER — the first
    // violation rejects the WHOLE save and carries the vocabulary it wanted.
    final formatType = template.formatType;
    if (formatType == null || !_formatTypeVocab.contains(formatType)) {
      return TemplateSaveResult(
        error: 'invalid_format_type',
        given: formatType ?? '',
        allowed: _formatTypeVocab,
      );
    }
    final maturity = template.maturity;
    if (maturity != null && !_templateMaturityVocab.contains(maturity)) {
      return TemplateSaveResult(
        error: 'invalid_maturity',
        given: maturity,
        allowed: _templateMaturityVocab,
      );
    }
    final scope = template.scope;
    if (scope != null && !_templateScopeVocab.contains(scope)) {
      return TemplateSaveResult(
        error: 'invalid_scope',
        given: scope,
        allowed: _templateScopeVocab,
      );
    }
    for (final plugin in template.plugins) {
      if (!_pluginStatusVocab.contains(plugin.status)) {
        return TemplateSaveResult(
          error: 'invalid_plugin_status',
          given: plugin.status,
          allowed: _pluginStatusVocab,
        );
      }
      if (!_pluginExecutionVocab.contains(plugin.execution)) {
        return TemplateSaveResult(
          error: 'invalid_plugin_execution',
          given: plugin.execution,
          allowed: _pluginExecutionVocab,
        );
      }
    }
    if (template.steps.isEmpty ||
        template.steps.any((s) => s.text.trim().isEmpty)) {
      return const TemplateSaveResult(
        error: 'invalid_steps',
        detail: 'steps must be non-empty with non-empty texts',
      );
    }
    for (final kind in template.noteKinds) {
      if (!_noteKindVocab.contains(kind)) {
        return TemplateSaveResult(
          error: 'invalid_note_kind',
          given: kind,
          allowed: _noteKindVocab,
        );
      }
    }
    if (template.name.trim().isEmpty) {
      return const TemplateSaveResult(error: 'missing_param', given: 'name');
    }

    // Server stamps: the id, tenant, source, timestamp, catalog version and the
    // default scope are the engine's to set, never the caller's.
    final saved = CyanTemplate(
      id: _templateId('template-v2', tenantId, template.name),
      tenantId: tenantId,
      name: template.name,
      description: template.description,
      source: 'user',
      steps: template.steps,
      createdAt: _stamp(0),
      formatType: formatType,
      stages: template.stages,
      noteKinds: template.noteKinds,
      plugins: template.plugins,
      maturity: maturity,
      catalogVersion: _roletypeCatalogVersion,
      scope: scope ?? 'tenant',
      notes: template.notes,
    );
    _templates.add(saved);
    return TemplateSaveResult(template: saved);
  }

  CyanTemplate _insertUserTemplate(String tenantId, String name,
      String description, List<TemplateStep> steps,
      {List<TemplateNote> notes = const []}) {
    final saved = CyanTemplate(
      id: _templateId('template', tenantId, name),
      tenantId: tenantId,
      name: name,
      description: description,
      source: 'user',
      steps: List<TemplateStep>.of(steps),
      createdAt: _stamp(0),
      notes: notes,
    );
    _templates.add(saved);
    return saved;
  }

  /// A stable template id. The engine hashes the tenant, name and the save
  /// instant; the sequence stands in for the instant so two saves of one name
  /// still differ, and goldens stay byte-stable.
  String _templateId(String prefix, String tenantId, String name) =>
      _digest('$prefix:$tenantId:$name:${++_templateSeq}');

  /// A template visible to [tenantId]: a seed (tenant-agnostic) or one of that
  /// tenant's own. Never another tenant's — there is no cross-tenant read.
  CyanTemplate? _templateOrNull(String templateId, String tenantId) {
    for (final t in _templates) {
      if (t.id != templateId) continue;
      if (t.isBuiltin || t.tenantId == tenantId) return t;
    }
    return null;
  }

  // ---- step composer ---------------------------------------------------------

  /// The controlled `/` verb set, verbatim from the engine.
  static const List<List<String>> _controlActions = [
    ['run', 'Run the workflow'],
    ['approve', 'Approve this step'],
    ['needs-approval', 'Require approval before continuing'],
    ['send-to', 'Send the result to a destination'],
    ['connect', 'Connect a plugin'],
    ['compile', 'Compile the workflow'],
    ['retry', 'Retry a failed step'],
    ['skip', 'Skip this step'],
  ];

  @override
  Future<AutocompleteIndex> workflowAutocomplete(
      String boardId, String partial) async {
    // The tenant is the board's group; a board the device has never seen falls
    // back to the engine's own `device` tenant rather than inventing one.
    final tenantId = _board(boardId) == null ? 'device' : _groupIdFor(boardId);

    final plugins = <AutocompleteEntry>[];
    for (final id in _pluginBundles.keys.toList()..sort()) {
      plugins.add(AutocompleteEntry(
        trigger: '@',
        kind: 'plugin',
        value: id,
        label: '$id.cyanplugin',
      ));
      final tools = _pluginBundles[id]!.tools.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      for (final tool in tools) {
        plugins.add(AutocompleteEntry(
          trigger: '@',
          kind: 'tool',
          value: '$id.${tool.name}',
          label: tool.name,
        ));
      }
    }

    // `#` — the board's bound files first, then its prior-step outputs. A step
    // with no output is not an artifact yet, so it is not offered.
    final artifacts = <AutocompleteEntry>[];
    final seenFiles = <String>{};
    final workflow = await loadWorkflow(boardId);
    for (final step in workflow.steps) {
      for (final file in step.boundInputs) {
        if (!seenFiles.add(file)) continue;
        artifacts.add(AutocompleteEntry(
          trigger: '#',
          kind: 'file',
          value: file,
          label: file,
        ));
      }
    }
    for (final step in _pipelines[boardId] ?? const <_FakePipelineStep>[]) {
      if (!step.hasRun || (step.aiResult ?? '').isEmpty) continue;
      artifacts.add(AutocompleteEntry(
        trigger: '#',
        kind: 'step_output',
        value: step.stepId,
        label: step.title,
      ));
    }

    final index = AutocompleteIndex(
      tenantId: tenantId,
      plugins: plugins,
      artifacts: artifacts,
      actions: [
        for (final action in _controlActions)
          AutocompleteEntry(
            trigger: '/',
            kind: 'action',
            value: action[0],
            label: action[1],
          ),
      ],
    );

    // No active trigger at the cursor ⇒ the FULL index passes through and the
    // caller decides what to show.
    final trigger = _parseTrigger(partial);
    if (trigger == null) return index;
    final query = trigger[1];
    return AutocompleteIndex(
      tenantId: tenantId,
      plugins: trigger[0] == '@' ? _matching(index.plugins, query) : const [],
      artifacts: trigger[0] == '#' ? _matching(index.artifacts, query) : const [],
      actions: trigger[0] == '/' ? _matching(index.actions, query) : const [],
    );
  }

  /// The trailing trigger token in [partial] as `[trigger, query]`, or null
  /// when there is no active completion at the cursor.
  static List<String>? _parseTrigger(String partial) {
    // The token at the cursor is the text after the last whitespace.
    final tail = partial.split(RegExp(r'\s')).last;
    if (tail.isEmpty) return null;
    final trigger = tail[0];
    if (trigger != '@' && trigger != '#' && trigger != '/') return null;
    final query = tail.substring(1);
    // A query with an embedded trigger char is not an active completion.
    if (query.contains('@') || query.contains('#') || query.contains('/')) {
      return null;
    }
    return [trigger, query];
  }

  /// Case-insensitive substring match on value OR label; an empty query matches
  /// everything, which is how a bare `@` lists the whole vocabulary.
  static List<AutocompleteEntry> _matching(
      List<AutocompleteEntry> entries, String query) {
    if (query.isEmpty) return entries;
    final q = query.toLowerCase();
    return [
      for (final e in entries)
        if (e.value.toLowerCase().contains(q) ||
            e.label.toLowerCase().contains(q))
          e,
    ];
  }

  // ---- producer review: assignee, media, comments -----------------------------
  //
  // WHO a board's review gates wait on, WHAT the board plays, and the comment
  // rail over it. Seeded as a review IN FLIGHT: the flagship board is a camera
  // original (a master the player cannot decode) with a round-2 proxy published
  // and a producer sitting on it.

  /// The board → assignee store, keyed the way the engine keys it. Seeded so
  /// the flagship board's compiled `waiting_on` and its assignee agree — the
  /// engine stamps one from the other at compile.
  late final Map<String, String> _reviewAssignees = {
    'b-eng-1': _reviewAssignee,
  };

  @override
  Future<String?> boardReviewAssignee(String boardId) async {
    // The engine stores an empty user as an empty string, which reads back as
    // no assignee — the same answer as a board that never had one.
    final user = _reviewAssignees[boardId];
    return (user == null || user.isEmpty) ? null : user;
  }

  @override
  Future<bool> boardSetReviewAssignee(String boardId, String user) async {
    // A plain upsert keyed on the board id, exactly like the engine's: it does
    // not check that the board exists, and the empty user CLEARS the gate's
    // assignee rather than being refused.
    _reviewAssignees[boardId] = user;
    return true;
  }

  /// The confined media root every board's paths resolve against.
  static const String _mediaRoot = '/Users/cyan/Movies/cyan-media';

  /// The board's ingested master. Only the flagship board has media, the same
  /// way only it has a compiled pipeline — a board with nothing ingested is the
  /// fixture's normal case, not an error.
  static const Map<String, String> _boardMasters = {
    'b-eng-1': '$_mediaRoot/masters/reel-01.mxf',
  };

  /// The newest DERIVED proxy per board, from the round already published.
  static const Map<String, String> _boardProxies = {
    'b-eng-1': '$_mediaRoot/derived/reel-01_r1_proxy.mp4',
  };

  @override
  Future<BoardVideoMedia> boardVideoMedia(String boardId) async {
    final master = _boardMasters[boardId];
    // The P-9 preview rung: a master the player cannot decode gets a
    // frame-mapped watchable render, keyed by the asset's own hash. It is
    // review-for-eyes — a real derived proxy still wins for playback.
    final preview = master != null && _undecodable(master)
        ? '$_mediaRoot/preview/${_reviewAsset(boardId)}.mp4'
        : null;
    return BoardVideoMedia(
      proxyPath: _boardProxies[boardId] ?? preview,
      masterUri: master,
      previewPath: preview,
      mediaRoot: _mediaRoot,
    );
  }

  /// Containers the macOS player cannot decode — the camera originals.
  static bool _undecodable(String path) {
    final lower = path.toLowerCase();
    return const ['.mxf', '.braw', '.r3d', '.ari', '.arri']
        .any(lower.endsWith);
  }

  /// The frame rate the fake anchors comments at, matching the engine's own
  /// fallback for a proxy whose fps the registry does not carry.
  static const double _reviewFps = 24;

  /// Comment ids are minted in order so a transcript stays byte-stable.
  int _reviewCommentSeq = 0;

  @override
  Future<ReviewCommentResult> reviewAddComment(String boardId, String text,
      {double atSeconds = 0, String author = 'reviewer'}) async {
    if (text.trim().isEmpty) {
      return const ReviewCommentResult(error: 'empty comment');
    }
    // The comment lands ON the published review proxy, so a board with nothing
    // published has nowhere to put it — the engine's own refusal.
    final media = await boardVideoMedia(boardId);
    if (media.proxyPath == null) {
      return const ReviewCommentResult(
          error: 'board has no published review media yet');
    }
    final at = atSeconds < 0 ? 0.0 : atSeconds;
    final id = 'rc-$boardId-${++_reviewCommentSeq}';
    // Local echo onto the SAME rail sensed comments land on, exactly as the
    // engine does before it answers — so a caller that re-reads the timecoded
    // notes sees the comment without patching its own copy.
    await saveTimecodeNote(TimecodeNote(
      id: id,
      boardId: boardId,
      timecodeSeconds: at,
      content: text,
      noteType: 'review_comment',
      author: author,
      createdAt: _stamp(0).toDouble(),
      humanApproved: true,
    ));
    return ReviewCommentResult(success: true, comment: {
      'id': id,
      'text': text,
      // The anchor travels in FRAMES, which is what the review service stores.
      'timestamp': (at * _reviewFps).round(),
    });
  }

  // ---- the review-loop state machine (`cyan_review_command`) -------------------
  //
  // A real machine, not a canned reply: the transitions, the from-state checks
  // and the three-actor authority model are all enforced here the way the
  // engine enforces them, so a UI can be driven through a whole review round —
  // and REFUSED the same way — with no dylib.

  /// event → [required from-state, resulting state]. `publish_proxy` also
  /// increments the round; `reopen_branch` also moves the row to a new branch.
  static const Map<String, List<String>> _reviewTransitions = {
    'publish': ['DRAFT', 'IN_REVIEW'],
    'notes_arrived': ['IN_REVIEW', 'NOTES_IN'],
    'version_approved': ['IN_REVIEW', 'APPROVED'],
    'confirm_notes': ['NOTES_IN', 'CONFORMING'],
    'conform_run': ['CONFORMING', 'CONFORMING'],
    'conform_failed': ['CONFORMING', 'NOTES_IN'],
    'publish_proxy': ['CONFORMING', 'IN_REVIEW'],
    'finish': ['APPROVED', 'FINISHING'],
    'delivered': ['FINISHING', 'DELIVERED'],
    'reopen_branch': ['DELIVERED', 'NOTES_IN'],
  };

  /// The ops AUTO fires — deterministic work, no human in it. Everything else
  /// in [_reviewTransitions] is human-gated (external_send or the confirm gate)
  /// and an agent may never fire one.
  static const List<String> _autoReviewOps = [
    'notes_arrived',
    'version_approved',
    'conform_run',
    'conform_failed',
    'delivered',
  ];

  static const int _reviewMaxRounds = 10;
  static const int _inReviewStaleSecs = 48 * 3600;
  static const int _notesInStaleSecs = 24 * 3600;

  /// The asset a board's review is keyed on. The engine keys on the content
  /// hash of the ingested master; the fake keys on a stable digest of the board
  /// so a read finds what a write put there.
  static String _reviewAsset(String boardId) => _digest(boardId);

  static String _reviewKey(String tenantId, String assetHash, String branch) =>
      '$tenantId|$assetHash|$branch';

  /// The review rows, keyed exactly as the engine keys them. Seeded with the
  /// flagship board's round-1 cut sitting with the producer — long enough to be
  /// stale, so `nudges_for` has something true to report.
  late final Map<String, ReviewState> _reviewStates = {
    _reviewKey('g-eng', _reviewAsset('b-eng-1'), 'main'): ReviewState(
      tenantId: 'g-eng',
      assetHash: _reviewAsset('b-eng-1'),
      branch: 'main',
      state: 'IN_REVIEW',
      round: 1,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(_stamp(3) * 1000),
    ),
  };

  @override
  Future<ReviewCommandResult> reviewCommand(
      Map<String, dynamic> command) async {
    final op = command['op'] as String? ?? '';
    if (op.isEmpty) return const ReviewCommandResult(error: "missing 'op'");

    // The app dialect keys on a BOARD; the ledger dialect keys on the tenant +
    // asset directly. Both resolve to the same row.
    final boardId = command['board_id'] as String? ?? '';
    final tenantId = (command['tenant_id'] as String?) ?? '';
    final byBoard = tenantId.isEmpty && boardId.isNotEmpty;
    final tenant = byBoard ? _groupIdFor(boardId) : tenantId;
    if (tenant.isEmpty) {
      return ReviewCommandResult(
          op: op, error: "missing 'tenant_id' (or 'board_id')");
    }
    final asset = (command['asset_hash'] as String?) ??
        (byBoard ? _reviewAsset(boardId) : '');
    if (asset.isEmpty) {
      return ReviewCommandResult(op: op, error: "missing 'asset_hash'");
    }
    final branch = (command['branch'] as String?) ?? 'main';
    final key = _reviewKey(tenant, asset, branch);
    final current = _reviewStates[key];

    if (op == 'get') {
      // No row is the engine's own "not started" — an answer, not a failure.
      return ReviewCommandResult(op: op, state: current, fields: const {});
    }
    if (op == 'start_draft') {
      // Idempotent: a review already in flight is never reset by a re-ingest.
      final state = current ??
          _putReviewState(tenant, asset, branch, 'DRAFT', round: 0);
      return ReviewCommandResult(op: op, state: state, fields: const {});
    }
    if (op == 'nudges_for') {
      return ReviewCommandResult(op: op, rows: _reviewNudges(tenant, asset));
    }

    final transition = _reviewTransitions[op];
    if (transition == null) {
      return ReviewCommandResult(op: op, error: "unknown op '$op'");
    }

    // The board-keyed publish/finish dialect IS the app surface, and the app
    // surface is the human — the engine fires those as Actor::Human whatever
    // the envelope says. Every other op is gated on the actor it carries.
    final actor = (command['actor'] as String?) ?? '';
    if (!(byBoard && (op == 'publish' || op == 'finish'))) {
      final gate = _reviewGate(op, actor);
      if (gate != null) return ReviewCommandResult(op: op, error: gate);
    }

    if (current == null) {
      return ReviewCommandResult(
          op: op, error: 'no review_state for ($tenant, $asset, $branch)');
    }
    // A board-keyed `publish` is resolved BY STATE: a draft publishes v1, a
    // conformed cut publishes the next round's proxy.
    final event =
        byBoard && op == 'publish' && current.state == 'CONFORMING'
            ? 'publish_proxy'
            : op;
    final expected = _reviewTransitions[event]![0];
    if (current.state != expected) {
      return ReviewCommandResult(
          op: op,
          error: "invalid transition '$event' from state '${current.state}'");
    }

    var round = current.round;
    if (event == 'publish_proxy') {
      // The round moves on each CONFORMING → IN_REVIEW publish, and the loop is
      // capped so a review can never round forever.
      round += 1;
      final cap = (command['max_rounds'] as num?)?.toInt() ?? _reviewMaxRounds;
      if (round > cap) {
        return ReviewCommandResult(
            op: op, error: 'max review rounds reached: $round >= $cap');
      }
    }
    if (event == 'reopen_branch') {
      final newBranch = command['new_branch'] as String? ?? '';
      if (newBranch.isEmpty) {
        return ReviewCommandResult(op: op, error: "missing 'new_branch'");
      }
      // The reopened notes land on the NEW branch; the delivered row stands.
      return ReviewCommandResult(
        op: op,
        state: _putReviewState(tenant, asset, newBranch, 'NOTES_IN',
            round: round),
        fields: const {},
      );
    }
    return ReviewCommandResult(
      op: op,
      state: _putReviewState(tenant, asset, branch,
          _reviewTransitions[event]![1],
          round: round),
      fields: const {},
    );
  }

  /// The authority model: AUTO ops reject anyone but auto, and the gated ones
  /// reject anyone but a human — an AGENT may only ever propose. Null when the
  /// actor may fire [op].
  static String? _reviewGate(String op, String actor) {
    if (_autoReviewOps.contains(op)) {
      return actor == 'auto'
          ? null
          : "actor '$actor' may not fire '$op' (requires 'auto')";
    }
    return actor == 'human'
        ? null
        : "'$op' is human-gated (external_send / confirm); "
            "actor '$actor' rejected";
  }

  ReviewState _putReviewState(
      String tenantId, String assetHash, String branch, String state,
      {required int round}) {
    final row = ReviewState(
      tenantId: tenantId,
      assetHash: assetHash,
      branch: branch,
      state: state,
      round: round,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(_stamp(0) * 1000),
    );
    _reviewStates[_reviewKey(tenantId, assetHash, branch)] = row;
    return row;
  }

  /// The DERIVED stale signal: a WAITING state (IN_REVIEW / NOTES_IN) sitting
  /// past its threshold. Computed on read — a nudge is never a stored state.
  List<Map<String, dynamic>> _reviewNudges(String tenantId, String assetHash) {
    final out = <Map<String, dynamic>>[];
    for (final row in _reviewStates.values) {
      if (row.tenantId != tenantId || row.assetHash != assetHash) continue;
      final threshold = switch (row.state) {
        'IN_REVIEW' => _inReviewStaleSecs,
        'NOTES_IN' => _notesInStaleSecs,
        _ => null,
      };
      if (threshold == null) continue;
      final waiting =
          _stamp(0) - (row.updatedAt?.millisecondsSinceEpoch ?? 0) ~/ 1000;
      if (waiting < threshold) continue;
      out.add({
        'tenant_id': row.tenantId,
        'asset_hash': row.assetHash,
        'branch': row.branch,
        'state': row.state,
        'round': row.round,
        'waiting_secs': waiting,
        'threshold_secs': threshold,
      });
    }
    return out;
  }

  // ---- ingest sources + materialized runs (`cyan_ingest_command`) -------------
  //
  // A real sensor, not a canned reply: adding a source validates the way the
  // engine validates, a scan walks a deterministic listing and DEDUPES against
  // what that source already ingested, and each new asset materializes its own
  // run. So a second `scan_now` reports zero ingested and all deduped — which is
  // the behaviour a sources UI has to be driven through — with no dylib.

  /// The engine's closed vocab; a kind outside it is refused on add and on scan.
  static const List<String> _ingestKindVocab = ['folder', 's3', 'frameio_c2c'];

  /// The watched sources, keyed by id. Seeded with the flagship board's dailies
  /// folder on a 15-minute cadence and its C2C project set to manual-only, so
  /// `scan_due` has exactly one due row to sweep and `source_list` shows both
  /// halves of the schedule/manual split.
  late final Map<String, IngestSource> _ingestSources = {
    'src-eng-dailies': IngestSource(
      id: 'src-eng-dailies',
      tenantId: 'g-eng',
      boardId: 'b-eng-1',
      kind: 'folder',
      uri: '$_mediaRoot/watch/dailies',
      scheduleSecs: 900,
      lastScanAt: DateTime.fromMillisecondsSinceEpoch(_stamp(2) * 1000),
      createdAt: DateTime.fromMillisecondsSinceEpoch(_stamp(9) * 1000),
    ),
    'src-eng-c2c': IngestSource(
      id: 'src-eng-c2c',
      tenantId: 'g-eng',
      boardId: 'b-eng-1',
      kind: 'frameio_c2c',
      uri: 'c2c://reel-01/camera-a',
      createdAt: DateTime.fromMillisecondsSinceEpoch(_stamp(6) * 1000),
    ),
  };

  /// The runs a scan materialized, per board, oldest first — the order the
  /// engine's `runs_for_board` reads them back in. Seeded with the round the
  /// flagship board's master already went through.
  late final Map<String, List<MaterializedRun>> _ingestRuns = {
    'b-eng-1': [
      MaterializedRun(
        runId: 'run-${_digest('b-eng-1|reel-01.mxf').substring(0, 8)}',
        boardId: 'b-eng-1',
        assetHash: _digest('$_mediaRoot/watch/dailies/reel-01.mxf'),
        status: 'done',
        createdAt: DateTime.fromMillisecondsSinceEpoch(_stamp(2) * 1000),
      ),
    ],
  };

  /// The asset hashes each source has already ingested — what a re-scan dedupes
  /// against. Seeded to match the run above, so the seeded source is not
  /// pretending it never ran.
  late final Map<String, Set<String>> _ingestSeen = {
    'src-eng-dailies': {_digest('$_mediaRoot/watch/dailies/reel-01.mxf')},
  };

  int _ingestSeq = 0;

  /// The deterministic listing behind a watched location. The seeded reel plus
  /// two clips derived from the source's own uri — enough that a first scan
  /// ingests and a second dedupes.
  static List<String> _ingestListing(IngestSource source) {
    if (source.kind == 'folder') {
      return [
        '${source.uri}/reel-01.mxf',
        '${source.uri}/reel-02.mxf',
        '${source.uri}/room-tone.wav',
      ];
    }
    // The seam kinds list remote items by ref rather than by path.
    return ['${source.uri}/clip-a.mov', '${source.uri}/clip-b.mov'];
  }

  @override
  Future<IngestCommandResult> ingestCommand(
      Map<String, dynamic> command) async {
    final op = command['op'] as String? ?? '';
    if (op.isEmpty) return const IngestCommandResult(error: "missing 'op'");

    String? missing(String key) =>
        (command[key] as String?)?.isNotEmpty == true
            ? null
            : "missing '$key'";

    switch (op) {
      case 'source_add':
        for (final key in ['tenant_id', 'board_id', 'kind', 'uri']) {
          final gap = missing(key);
          if (gap != null) return IngestCommandResult(op: op, error: gap);
        }
        final kind = command['kind'] as String;
        if (!_ingestKindVocab.contains(kind)) {
          return IngestCommandResult(
              op: op,
              error:
                  "ingest kind '$kind' not in closed vocab $_ingestKindVocab");
        }
        final schedule = (command['schedule_secs'] as num?)?.toInt();
        if (schedule != null && schedule <= 0) {
          return IngestCommandResult(
              op: op,
              error: 'schedule_secs must be positive '
                  '(or absent for manual-only)');
        }
        final source = IngestSource(
          id: 'src-${_digest('$kind|${command['uri']}|${_ingestSeq++}').substring(0, 12)}',
          tenantId: command['tenant_id'] as String,
          boardId: command['board_id'] as String,
          kind: kind,
          uri: command['uri'] as String,
          scheduleSecs: schedule,
          createdAt: DateTime.fromMillisecondsSinceEpoch(_stamp(0) * 1000),
        );
        _ingestSources[source.id] = source;
        return IngestCommandResult(op: op, fields: source.toJson());

      case 'source_list':
        final gap = missing('tenant_id');
        if (gap != null) return IngestCommandResult(op: op, error: gap);
        final tenant = command['tenant_id'] as String;
        return IngestCommandResult(op: op, rows: [
          for (final s in _ingestSources.values)
            if (s.tenantId == tenant) s.toJson(),
        ]);

      case 'source_remove':
        for (final key in ['tenant_id', 'id']) {
          final gap = missing(key);
          if (gap != null) return IngestCommandResult(op: op, error: gap);
        }
        final id = command['id'] as String;
        // The engine's remove is scoped BY TENANT — a source in another group is
        // not this caller's to drop, and reads as already gone.
        if (_ingestSources[id]?.tenantId == command['tenant_id']) {
          _ingestSources.remove(id);
          _ingestSeen.remove(id);
        }
        return IngestCommandResult(op: op, fields: const {'removed': true});

      case 'scan_now':
        final gap = missing('source_id');
        if (gap != null) return IngestCommandResult(op: op, error: gap);
        final sourceId = command['source_id'] as String;
        final source = _ingestSources[sourceId];
        if (source == null) {
          return IngestCommandResult(
              op: op, error: "no ingest_source '$sourceId'");
        }
        if (!_ingestKindVocab.contains(source.kind)) {
          return IngestCommandResult(
              op: op,
              error: "ingest kind '${source.kind}' not in closed vocab");
        }
        return IngestCommandResult(
            op: op, fields: _ingestScan(sourceId)!.toJson());

      case 'scan_due':
        final at = (command['now'] as num?)?.toInt() ?? _stamp(0);
        return IngestCommandResult(op: op, rows: [
          for (final source in _ingestDue(at))
            // A kind outside the vocab fails ITS row and no other — the sweep
            // carries per-source errors rather than throwing on the first.
            if (!_ingestKindVocab.contains(source.kind))
              {
                'source_id': source.id,
                'error': "ingest kind '${source.kind}' not in closed vocab",
              }
            else
              {
                'source_id': source.id,
                'report': _ingestScan(source.id)!.toJson(),
              },
        ]);

      case 'runs_for_board':
        final gap = missing('board_id');
        if (gap != null) return IngestCommandResult(op: op, error: gap);
        return IngestCommandResult(op: op, rows: [
          for (final run in _ingestRuns[command['board_id']] ?? const [])
            run.toJson(),
        ]);

      case 'produce_master_plan':
        for (final key in ['tenant_id', 'version_id']) {
          final gap = missing(key);
          if (gap != null) return IngestCommandResult(op: op, error: gap);
        }
        final tenant = command['tenant_id'] as String;
        // The SELECTIVE retrieve list: only the masters the tenant's ingested
        // runs actually put in the cut, each at the location it was ingested
        // from — never "every asset the group holds".
        final boards = {
          for (final s in _ingestSources.values)
            if (s.tenantId == tenant) s.boardId,
        };
        final masters = <Map<String, dynamic>>[];
        for (final board in boards) {
          for (final run in _ingestRuns[board] ?? const <MaterializedRun>[]) {
            masters.add({
              'asset': run.assetHash,
              'location': '$_mediaRoot/masters/${run.assetHash}.mxf',
            });
          }
        }
        return IngestCommandResult(op: op, fields: {'masters': masters});
    }
    return IngestCommandResult(op: op, error: "unknown op '$op'");
  }

  /// Every scheduled source whose cadence has come round by [at]. Manual-only
  /// sources are never due — that is what "manual only" means.
  List<IngestSource> _ingestDue(int at) => [
        for (final s in _ingestSources.values)
          if (s.scheduleSecs != null &&
              (s.lastScanAt == null ||
                  at - s.lastScanAt!.millisecondsSinceEpoch ~/ 1000 >=
                      s.scheduleSecs!))
            s,
      ];

  /// Walk one source's listing, materializing a run for each asset it has not
  /// ingested before and counting the rest as deduped. Null when there is no
  /// such source. Stamps `last_scan_at` on success, as the engine does.
  ScanReport? _ingestScan(String sourceId) {
    final source = _ingestSources[sourceId];
    if (source == null) return null;
    final seen = _ingestSeen.putIfAbsent(sourceId, () => <String>{});
    final runs = _ingestRuns.putIfAbsent(source.boardId, () => []);
    var ingested = 0;
    var deduped = 0;
    final listing = _ingestListing(source);
    for (final path in listing) {
      final assetHash = _digest(path);
      if (!seen.add(assetHash)) {
        deduped++;
        continue;
      }
      ingested++;
      runs.add(MaterializedRun(
        runId: 'run-${_digest('${source.boardId}|$path').substring(0, 8)}',
        boardId: source.boardId,
        assetHash: assetHash,
        status: 'materialized',
        createdAt: DateTime.fromMillisecondsSinceEpoch(_stamp(0) * 1000),
      ));
    }
    _ingestSources[sourceId] = IngestSource(
      id: source.id,
      tenantId: source.tenantId,
      boardId: source.boardId,
      kind: source.kind,
      uri: source.uri,
      scheduleSecs: source.scheduleSecs,
      lastScanAt: DateTime.fromMillisecondsSinceEpoch(_stamp(0) * 1000),
      createdAt: source.createdAt,
    );
    return ScanReport(
        discovered: listing.length, ingested: ingested, deduped: deduped);
  }

  // ---- changelist store -------------------------------------------------------
  //
  // The content-addressed review-&-conform ledger, keyed exactly as the engine
  // keys it: (tenant, asset, branch) -> ordered entries, plus the versions a
  // snapshot freezes. Entry CONTENT is immutable here too — `set_active` and
  // `set_state` move only the lifecycle columns, so reversing a change keeps
  // the row and flips `active`, never deletes it.

  /// Wire-shaped entry rows, so a fake reply decodes down the SAME path the
  /// engine's does. Ordered by `seq` within each key, as the engine's query is.
  late final Map<String, List<Map<String, dynamic>>> _changeEntries = {
    _reviewKey('g-eng', _reviewAsset('b-eng-1'), 'main'): [
      _changeEntry(
        tenantId: 'g-eng',
        assetHash: _reviewAsset('b-eng-1'),
        seq: 1,
        kind: 'op',
        op: 'trim_head',
        intent: 'the open feels rushed — hold two beats before the title',
        tcIn: 0,
        tcOut: 48,
        role: 'producer',
        proposedBy: 'human',
        state: 'approved',
        params: const {'frames': 48},
      ),
      _changeEntry(
        tenantId: 'g-eng',
        assetHash: _reviewAsset('b-eng-1'),
        seq: 2,
        kind: 'note',
        intent: 'lower third is off-brand in the second act',
        tcIn: 1440,
        tcOut: 1512,
        role: 'reviewer',
        proposedBy: 'human',
        state: 'proposed',
      ),
      // An agent PROPOSAL: mechanical, and waiting on a human. It is seeded
      // un-adjudicated on purpose — the face must show that distinction.
      _changeEntry(
        tenantId: 'g-eng',
        assetHash: _reviewAsset('b-eng-1'),
        seq: 3,
        kind: 'op',
        op: 'audio_duck',
        intent: 'music covers the VO under the interview',
        tcIn: 2100,
        tcOut: 2340,
        role: 'agent',
        proposedBy: 'agent',
        source: 'agent',
        state: 'proposed',
        active: false,
        params: const {'db': -6},
      ),
    ],
  };

  /// The frozen versions a `snapshot` mints, keyed by version id.
  final Map<String, Map<String, dynamic>> _changeVersions = {};

  /// One wire-shaped `ChangeEntry`. The entry hash is a digest of the CONTENT
  /// fields only, exactly as the engine computes it — two identical proposals
  /// therefore collide, which is the point of a content-addressed ledger.
  Map<String, dynamic> _changeEntry({
    required String tenantId,
    required String assetHash,
    required int seq,
    required String kind,
    required String intent,
    required int tcIn,
    String? op,
    int? tcOut,
    String branch = 'main',
    String? track,
    String? source,
    String? role,
    String? proposedBy,
    String state = 'proposed',
    bool active = true,
    Map<String, dynamic> params = const {},
  }) {
    final hash = _digest(
        '$tenantId|$assetHash|$branch|$kind|${op ?? ''}|$tcIn|${tcOut ?? tcIn}|$intent');
    return {
      'id': 'ce-${hash.substring(0, 12)}',
      'entry_hash': hash,
      'asset_hash': assetHash,
      'tenant_id': tenantId,
      'track': track,
      'tc_in': tcIn,
      'tc_out': tcOut,
      'kind': kind,
      'op': op,
      'params': params,
      'intent': intent,
      'source': source ?? 'cyan',
      'source_ref': null,
      'author': proposedBy == 'agent' ? 'agent-conform' : 'rick',
      'role': role,
      'proposed_by': proposedBy,
      'created_at': _stamp(3) + seq,
      'state': state,
      'active': active,
      'approved_by': state == 'approved' ? 'rick' : null,
      'approved_at': state == 'approved' ? _stamp(2) : null,
      'supersedes': null,
      'superseded_by': null,
      'seq': seq,
      'depends_on': null,
      'version_ref': null,
      'branch': branch,
      'outcome': null,
    };
  }

  /// The entry rows for one lane, in apply order. Never null — a lane nobody
  /// has written to is an EMPTY change list, not a missing one.
  List<Map<String, dynamic>> _changeLane(
          String tenant, String asset, String branch) =>
      _changeEntries.putIfAbsent(_reviewKey(tenant, asset, branch), () => []);

  /// One entry row by id, or null when the lane does not hold it.
  static Map<String, dynamic>? _changeRow(
      List<Map<String, dynamic>> lane, String id) {
    for (final e in lane) {
      if (e['id'] == id) return e;
    }
    return null;
  }

  /// The newest version frozen on a lane, or null when nothing has snapshotted
  /// it yet — an un-versioned change list is the normal starting state.
  Map<String, dynamic>? _changeHead(String asset, String branch) {
    Map<String, dynamic>? head;
    for (final v in _changeVersions.values) {
      if (v['asset_hash'] == asset && v['branch'] == branch) head = v;
    }
    return head;
  }

  @override
  Future<ChangelistCommandResult> changelistCommand(
      Map<String, dynamic> command) async {
    final op = command['op'] as String? ?? '';
    if (op.isEmpty) return const ChangelistCommandResult(error: "missing 'op'");

    String? missing(String key) => (command[key] as String?)?.isNotEmpty == true
        ? null
        : "missing '$key'";

    // The BOARD dialect (the review player) and the LEDGER dialect (tenant +
    // asset directly) both resolve to the same lane, exactly as `reviewCommand`
    // resolves them.
    final boardId = command['board_id'] as String? ?? '';
    final byBoard = (command['tenant_id'] as String?)?.isNotEmpty != true &&
        boardId.isNotEmpty;
    final tenant =
        byBoard ? _groupIdFor(boardId) : (command['tenant_id'] as String? ?? '');
    final asset = (command['asset_hash'] as String?) ??
        (byBoard ? _reviewAsset(boardId) : '');
    final branch = (command['branch'] as String?) ?? 'main';

    switch (op) {
      case 'list':
        final gap = missing('board_id');
        if (gap != null) return ChangelistCommandResult(op: op, error: gap);
        // The player's full envelope: the lane, its head version, and the
        // review round it is sitting in.
        final state = _reviewStates[_reviewKey(tenant, asset, branch)];
        return ChangelistCommandResult(op: op, fields: {
          'asset_hash': asset,
          'branch': branch,
          'tenant_id': tenant,
          'version': _changeHead(asset, branch),
          'review_state': state == null
              ? null
              : {'state': state.state, 'round': state.round},
          'entries': _changeLane(tenant, asset, branch),
        });

      case 'get':
        for (final key in ['tenant_id', 'asset_hash']) {
          final gap = missing(key);
          if (gap != null) return ChangelistCommandResult(op: op, error: gap);
        }
        return ChangelistCommandResult(op: op, fields: {
          'asset_hash': asset,
          'branch': branch,
          'entries': _changeLane(tenant, asset, branch),
          'head_version': _changeHead(asset, branch),
        });

      case 'append':
        for (final key in ['tenant_id', 'asset_hash', 'kind']) {
          final gap = missing(key);
          if (gap != null) return ChangelistCommandResult(op: op, error: gap);
        }
        final kind = command['kind'] as String;
        if (!_changeKindVocab.contains(kind)) {
          return ChangelistCommandResult(
              op: op,
              error: "change kind '$kind' not in closed vocab "
                  '$_changeKindVocab');
        }
        // An `op` entry MUST name its operation; a note must not pretend to be
        // one. The engine's typed payload is what conform reads.
        if (kind == 'op' && (command['op_name'] as String?)?.isEmpty != false) {
          return ChangelistCommandResult(
              op: op, error: "kind 'op' requires 'op_name'");
        }
        final lane = _changeLane(tenant, asset, branch);
        final entry = _changeEntry(
          tenantId: tenant,
          assetHash: asset,
          branch: branch,
          seq: lane.length + 1,
          kind: kind,
          op: command['op_name'] as String?,
          intent: command['intent'] as String? ?? '',
          tcIn: (command['tc_in'] as num?)?.toInt() ?? 0,
          tcOut: (command['tc_out'] as num?)?.toInt(),
          track: command['track'] as String?,
          source: command['source'] as String?,
          role: command['role'] as String?,
          proposedBy: command['proposed_by'] as String?,
          params: command['params'] is Map<String, dynamic>
              ? command['params'] as Map<String, dynamic>
              : const {},
        );
        // Content-addressed: an identical proposal is the SAME entry, so a
        // double-send converges instead of duplicating the note.
        final existing =
            lane.indexWhere((e) => e['entry_hash'] == entry['entry_hash']);
        if (existing >= 0) {
          return ChangelistCommandResult(op: op, fields: lane[existing]);
        }
        lane.add(entry);
        return ChangelistCommandResult(op: op, fields: entry);

      case 'set_state':
      case 'set_active':
      case 'supersede':
        for (final key in ['tenant_id', 'entry_id']) {
          final gap = missing(key);
          if (gap != null) return ChangelistCommandResult(op: op, error: gap);
        }
        final entryId = command['entry_id'] as String;
        final lane = _changeLane(tenant, asset, branch);
        final row = _changeRow(lane, entryId);
        if (row == null) {
          return ChangelistCommandResult(
              op: op, error: "no change_entry '$entryId'");
        }
        if (op == 'set_state') {
          final state = command['state'] as String? ?? '';
          if (!_changeStateVocab.contains(state)) {
            return ChangelistCommandResult(
                op: op,
                error: "change state '$state' not in closed vocab "
                    '$_changeStateVocab');
          }
          row['state'] = state;
          if (state == 'approved') {
            row['approved_by'] = command['actor'] as String? ?? 'rick';
            row['approved_at'] = _stamp(0);
          }
        } else if (op == 'set_active') {
          // The NON-DESTRUCTIVE reverse: the row stays, the cut changes.
          row['active'] = command['active'] as bool? ?? false;
        } else {
          final byId = command['by_entry_id'] as String? ?? '';
          final replacement = _changeRow(lane, byId);
          if (replacement == null) {
            return ChangelistCommandResult(
                op: op, error: "no change_entry '$byId' to supersede with");
          }
          row['superseded_by'] = byId;
          row['state'] = 'superseded';
          row['active'] = false;
          replacement['supersedes'] = entryId;
        }
        row['updated_at'] = _stamp(0);
        return ChangelistCommandResult(op: op, fields: row);

      case 'snapshot':
        for (final key in ['tenant_id', 'asset_hash']) {
          final gap = missing(key);
          if (gap != null) return ChangelistCommandResult(op: op, error: gap);
        }
        final lane = _changeLane(tenant, asset, branch);
        // A version freezes exactly the ACTIVE entries — the reversed ones are
        // still on the ledger and deliberately not in the cut.
        final active = [for (final e in lane) if (e['active'] == true) e];
        final hashes = [for (final e in active) e['entry_hash'] as String];
        final versionId =
            'cv-${_digest('$tenant|$asset|$branch|${hashes.join('|')}').substring(0, 12)}';
        final version = {
          'version_id': versionId,
          'tenant_id': tenant,
          'asset_hash': asset,
          'branch': branch,
          'entry_hashes': hashes,
          'created_at': _stamp(0),
          'outcome': 'pending',
          'label': command['label'] as String? ?? '',
        };
        _changeVersions[versionId] = version;
        for (final e in active) {
          e['version_ref'] ??= versionId;
        }
        return ChangelistCommandResult(op: op, fields: version);

      case 'get_version':
        for (final key in ['tenant_id', 'version_id']) {
          final gap = missing(key);
          if (gap != null) return ChangelistCommandResult(op: op, error: gap);
        }
        final version = _changeVersions[command['version_id']];
        if (version == null) {
          return ChangelistCommandResult(
              op: op, error: "no change_version '${command['version_id']}'");
        }
        return ChangelistCommandResult(op: op, fields: version);

      case 'set_outcome':
        for (final key in ['tenant_id', 'version_id', 'outcome']) {
          final gap = missing(key);
          if (gap != null) return ChangelistCommandResult(op: op, error: gap);
        }
        final version = _changeVersions[command['version_id']];
        if (version == null) {
          return ChangelistCommandResult(
              op: op, error: "no change_version '${command['version_id']}'");
        }
        final outcome = command['outcome'] as String;
        if (!_changeOutcomeVocab.contains(outcome)) {
          return ChangelistCommandResult(
              op: op,
              error: "outcome '$outcome' not in closed vocab "
                  '$_changeOutcomeVocab');
        }
        // Set-ONCE: the taste label is the training signal, so a second write
        // is refused rather than silently overwriting the first.
        if (version['outcome'] != 'pending') {
          return ChangelistCommandResult(
              op: op,
              error: "outcome already set to '${version['outcome']}'");
        }
        version['outcome'] = outcome;
        return ChangelistCommandResult(op: op, fields: const {'ok': true});

      case 'branch':
        for (final key in ['tenant_id', 'asset_hash', 'branch']) {
          final gap = missing(key);
          if (gap != null) return ChangelistCommandResult(op: op, error: gap);
        }
        // Branching COPIES the lane's active entries onto the new name — the
        // source branch is untouched, which is what makes a try-it-out safe.
        final from = command['from_branch'] as String? ?? 'main';
        final target = _changeLane(tenant, asset, branch);
        if (target.isEmpty) {
          var seq = 0;
          for (final e in _changeLane(tenant, asset, from)) {
            if (e['active'] != true) continue;
            target.add({...e, 'branch': branch, 'seq': ++seq});
          }
        }
        return ChangelistCommandResult(op: op, fields: {
          'tenant_id': tenant,
          'asset_hash': asset,
          'branch': branch,
          'head_version': null,
        });

      case 'diff':
        for (final key in ['tenant_id', 'version_a', 'version_b']) {
          final gap = missing(key);
          if (gap != null) return ChangelistCommandResult(op: op, error: gap);
        }
        final a = _changeVersions[command['version_a']];
        final b = _changeVersions[command['version_b']];
        if (a == null || b == null) {
          return ChangelistCommandResult(
              op: op, error: 'both versions must exist to diff');
        }
        final hashesA = {...(a['entry_hashes'] as List).cast<String>()};
        final hashesB = {...(b['entry_hashes'] as List).cast<String>()};
        final lane = _changeLane(tenant, asset, branch);
        return ChangelistCommandResult(op: op, fields: {
          'added': [for (final h in hashesB) if (!hashesA.contains(h)) h],
          'removed': [for (final h in hashesA) if (!hashesB.contains(h)) h],
          // Superseded IN B: the entry was in A, and the row that replaced it
          // is the one B carries. A supersede B never took is not one of these.
          'superseded': [
            for (final e in lane)
              if (hashesA.contains(e['entry_hash']) &&
                  e['superseded_by'] != null &&
                  hashesB.contains(
                      _changeRow(lane, e['superseded_by'] as String)
                          ?['entry_hash']))
                e['id'] as String,
          ],
        });

      case 'conform_plan':
        for (final key in ['tenant_id', 'version_id']) {
          final gap = missing(key);
          if (gap != null) return ChangelistCommandResult(op: op, error: gap);
        }
        final version = _changeVersions[command['version_id']];
        if (version == null) {
          return ChangelistCommandResult(
              op: op, error: "no change_version '${command['version_id']}'");
        }
        final hashes = {...(version['entry_hashes'] as List).cast<String>()};
        // Only `op` entries conform — a note is a note, and the plan is the
        // array reply, ordered by seq exactly as it applies.
        final ops = [
          for (final e in _changeLane(tenant, asset, branch))
            if (hashes.contains(e['entry_hash']) && e['kind'] == 'op')
              {
                'entry_id': e['id'],
                'seq': e['seq'],
                'op': e['op'],
                'tc_in': e['tc_in'],
                'tc_out': e['tc_out'],
                'params': e['params'],
              },
        ]..sort((x, y) => (x['seq'] as int).compareTo(y['seq'] as int));
        return ChangelistCommandResult(op: op, rows: ops);
    }
    return ChangelistCommandResult(op: op, error: "unknown op '$op'");
  }

  /// The engine's closed vocabularies. Held here so the fake refuses exactly
  /// what the engine refuses, rather than accepting a value the real store
  /// would reject on the first live run.
  static const List<String> _changeKindVocab = ['note', 'op', 'marker'];
  static const List<String> _changeStateVocab = [
    'proposed',
    'approved',
    'rejected',
    'applied',
    'superseded',
  ];
  static const List<String> _changeOutcomeVocab = [
    'pending',
    'shipped',
    'rejected',
  ];

  // ---- lens command bar -----------------------------------------------------

  @override
  Future<List<PathSuggestion>> autocompletePath(String partial) async {
    // The engine's own walk: drop the `g\` prefix, then complete whichever
    // level the segment count lands on — the groups, that group's workspaces,
    // that workspace's boards. Name-ordered and capped at ten, exactly as its
    // ORDER BY / LIMIT give. A PARTIAL board name completes to nothing, because
    // it does engine-side too.
    final cleaned = partial.startsWith('g\\') || partial.startsWith('g/')
        ? partial.substring(2)
        : partial;
    final parts = cleaned.split('\\');

    switch (parts.length) {
      case 1:
        return _capped([
          for (final g in _byName(_groups, (g) => g.name))
            if (_startsWith(g.name, parts[0]))
              PathSuggestion(name: g.name, path: 'g\\${g.name}'),
        ]);
      case 2:
        final group = _groupNamed(parts[0]);
        if (group == null) return const [];
        return _capped([
          for (final w in _byName(group.workspaces, (w) => w.name))
            if (_startsWith(w.name, parts[1]))
              PathSuggestion(
                  name: w.name, path: 'g\\${group.name}\\${w.name}'),
        ]);
      case 3 when parts[2].isEmpty:
        final group = _groupNamed(parts[0]);
        final workspace =
            group == null ? null : _workspaceNamed(group, parts[1]);
        if (group == null || workspace == null) return const [];
        return _capped([
          for (final b in _byName(workspace.boards, (b) => b.name))
            PathSuggestion(
                name: b.name,
                path: 'g\\${group.name}\\${workspace.name}\\${b.name}'),
        ]);
      default:
        return const [];
    }
  }

  @override
  Future<LensCommandParse> parseLensCommand(String input) async {
    final trimmed = input.trim();
    // A line that opens with no verb is not a command at all — it goes to the
    // natural-language rail whole.
    if (!trimmed.startsWith('/')) {
      return LensCommandParse(type: 'natural_language', text: trimmed);
    }
    final head = trimmed.indexOf(' ');
    final cmd =
        (head < 0 ? trimmed : trimmed.substring(0, head)).toLowerCase();
    final args = head < 0 ? '' : trimmed.substring(head + 1).trim();

    switch (cmd) {
      case '/summarize' || '/sum' || '/s':
        if (args.isEmpty) {
          return const LensCommandParse(
              type: 'natural_language', text: 'summarize');
        }
        if (args.startsWith('file ') || args.startsWith('file\t')) {
          return _summarizeFile(trimmed, args.substring('file'.length).trim());
        }
        final path = _parseLensPath(args);
        if (path == null) {
          // An unparseable path is not a scope the verb can take, so the whole
          // line falls back to natural language — with the verb kept in it.
          return LensCommandParse(
              type: 'natural_language', text: 'summarize $args');
        }
        final resolved = _resolveLensPath(path);
        return LensCommandParse(
          type: 'summarize',
          resolved: resolved,
          error: resolved == null ? _noSuchPath(args) : null,
        );

      case '/pin' || '/p':
        return const LensCommandParse(type: 'pin');

      case '/grep' || '/search' || '/find':
        final grep = _parseGrepArgs(args);
        if (grep == null) {
          return LensCommandParse(type: 'natural_language', text: trimmed);
        }
        final resolved = _resolveLensPath(grep.path);
        return LensCommandParse(
          type: 'grep',
          term: grep.term,
          resolved: resolved,
          error: resolved == null ? _noSuchPath(args) : null,
        );

      case '/status' || '/st':
        // A scope that neither parses nor resolves leaves the verb standing:
        // `/status` on its own reports the CURRENT scope, so there is nothing
        // to refuse.
        return LensCommandParse(
            type: 'status', resolved: _resolvedOrNull(args));

      case '/pulse' || '/pl':
        return LensCommandParse(
            type: 'pulse', resolved: _resolvedOrNull(args));

      case '/import' || '/i':
        return _import(args);

      case '/help' || '/h' || '/?':
        return const LensCommandParse(type: 'help', text: _lensHelpText);

      case '/pipeline' || '/pipe':
        return _pipelineCommand(args);

      default:
        return LensCommandParse(type: 'natural_language', text: trimmed);
    }
  }

  /// `/summarize file <path>` — the engine extracts the text WHILE parsing, so
  /// the reply already carries it (or the extractor's own refusal).
  Future<LensCommandParse> _summarizeFile(String line, String filePath) async {
    final path = _parseLensPath(filePath);
    if (path == null) {
      return LensCommandParse(type: 'natural_language', text: line);
    }
    final resolved = _resolveLensPath(path);
    if (resolved == null) {
      return LensCommandParse(
          type: 'summarize_file', error: _noSuchPath(filePath));
    }
    // Only a resolved FILE whose bytes are on this device has anything to
    // extract; anything else resolves cleanly with no text, not as an error.
    if (resolved.kind != 'file' || resolved.filePath.isEmpty) {
      return LensCommandParse(type: 'summarize_file', resolved: resolved);
    }
    final text = await extractFileText(resolved.filePath);
    return LensCommandParse(
      type: 'summarize_file',
      resolved: resolved,
      extractedText: text,
      error: text == null
          ? 'Text extraction failed: ${resolved.fileName}'
          : null,
    );
  }

  /// `/import <source> [target] [path]`.
  LensCommandParse _import(String args) {
    if (args.isEmpty) return const LensCommandParse(type: 'import');
    final head = args.indexOf(' ');
    final source = (head < 0 ? args : args.substring(0, head)).toLowerCase();
    final rest = head < 0 ? '' : args.substring(head + 1).trim();
    if (rest.isEmpty) {
      return LensCommandParse(type: 'import', source: source);
    }
    if (rest.startsWith('g\\') || rest.startsWith('g/')) {
      return LensCommandParse(
          type: 'import', source: source, resolved: _resolvedOrNull(rest));
    }
    final split = rest.indexOf(' ');
    return LensCommandParse(
      type: 'import',
      source: source,
      target: split < 0 ? rest : rest.substring(0, split),
      resolved:
          split < 0 ? null : _resolvedOrNull(rest.substring(split + 1).trim()),
    );
  }

  /// `/pipeline <action> [step_id] [path]`. The read-only actions are RUN here,
  /// exactly as the engine runs them while parsing; the acting ones are only
  /// addressed, and the caller fires them through the pipeline verbs.
  Future<LensCommandParse> _pipelineCommand(String args) async {
    if (args.isEmpty) {
      return const LensCommandParse(
          type: 'pipeline', action: 'help', text: _pipelineHelpText);
    }
    final head = args.indexOf(' ');
    final action = (head < 0 ? args : args.substring(0, head)).toLowerCase();
    final rest = head < 0 ? '' : args.substring(head + 1).trim();
    final split = rest.indexOf(' ');
    final arg1 = split < 0 ? rest : rest.substring(0, split);
    final arg2 = split < 0 ? '' : rest.substring(split + 1).trim();

    switch (action) {
      case 'compile' || 'run' || 'status' || 'export':
        final boardId = _pathBoardId(rest);
        if (boardId.isEmpty) {
          return LensCommandParse(
            type: 'pipeline',
            action: action,
            error: action == 'export'
                ? 'No board specified.'
                : 'No board specified. Use: /pipeline $action '
                    'g\\Group\\Workspace\\Board',
          );
        }
        switch (action) {
          case 'compile':
            // The parse ADDRESSES the compile; the LLM round-trip that writes
            // the step configs still has to happen.
            return LensCommandParse(
                type: 'pipeline',
                action: action,
                boardId: boardId,
                needsLlm: true);
          case 'status':
            final status = await pipelineStatus(boardId);
            return LensCommandParse(
              type: 'pipeline',
              action: action,
              data: _statusPayload(status),
            );
          case 'export':
            return LensCommandParse(
                type: 'pipeline', action: action, dag: _airflowDag(boardId));
          default:
            return LensCommandParse(
                type: 'pipeline', action: action, boardId: boardId);
        }
      case 'approve' || 'reject' || 'retry':
        return LensCommandParse(
          type: 'pipeline',
          action: action,
          stepId: arg1,
          boardId: _pathBoardId(arg2),
        );
      default:
        // A bare path means status; anything else is a plea for the help line.
        final boardId = _pathBoardId(args);
        if (boardId.isEmpty) {
          return const LensCommandParse(
              type: 'pipeline', action: 'help', text: _pipelineHelpText);
        }
        final status = await pipelineStatus(boardId);
        return LensCommandParse(
          type: 'pipeline',
          action: 'status',
          data: _statusPayload(status),
        );
    }
  }

  /// A status snapshot on the wire, in the engine's own key names.
  static Map<String, dynamic> _statusPayload(PipelineStatus status) => {
        'board_id': status.boardId,
        'run_id': status.runId,
        'status': _runStateWire(status.status),
        'total_steps': status.totalSteps,
        'ai_complete': status.aiComplete,
        'human_approved': status.humanApproved,
        'running': status.running,
        'failed': status.failed,
        'pending': status.pending,
        'progress_pct': status.progressPct,
        'total_cost_usd': status.totalCostDollars,
        'awaiting_step': status.awaitingStep,
      };

  static String _runStateWire(PipelineRunState state) => switch (state) {
        PipelineRunState.idle => 'idle',
        PipelineRunState.running => 'running',
        PipelineRunState.awaitingApproval => 'awaiting_approval',
        PipelineRunState.inProgress => 'in_progress',
        PipelineRunState.done => 'done',
        PipelineRunState.failed => 'failed',
      };

  /// The board's steps as an Airflow DAG — the same export the `/pipeline
  /// export` verb produces, one task per compiled step in DAG order.
  String _airflowDag(String boardId) {
    final steps = _pipelines[boardId] ?? const [];
    final tasks = [
      for (final step in steps)
        "    ${step.stepId} = BashOperator(task_id='${step.stepId}', "
            "bash_command='cyan run ${step.stepId}')",
    ];
    final chain = [for (final step in steps) step.stepId].join(' >> ');
    return [
      'from airflow import DAG',
      'from airflow.operators.bash import BashOperator',
      '',
      "with DAG('cyan_$boardId', schedule=None) as dag:",
      ...tasks,
      if (chain.isNotEmpty) '    $chain',
      '',
    ].join('\n');
  }

  /// The board a path names, or empty when it names none / resolves to a scope
  /// above a board. The engine reads the board id off the Board and File
  /// variants alone, and so does this.
  String _pathBoardId(String path) {
    if (path.isEmpty) return '';
    final resolved = _resolvedOrNull(path);
    return resolved == null ? '' : resolved.boardId;
  }

  /// Parse then resolve in one step, for the verbs whose scope is optional and
  /// whose refusal is simply "no scope".
  LensResolvedPath? _resolvedOrNull(String path) {
    if (path.isEmpty) return null;
    final parsed = _parseLensPath(path);
    return parsed == null ? null : _resolveLensPath(parsed);
  }

  static String _noSuchPath(String path) => 'Path not found: ${path.trim()}';

  /// `"quoted term" g\path`, or `term g\path`. Null when the line carries no
  /// path at all — the engine hands that back to natural language rather than
  /// searching an unnamed scope.
  _LensGrep? _parseGrepArgs(String args) {
    final trimmed = args.trim();
    if (trimmed.startsWith('"')) {
      final after = trimmed.substring(1);
      final end = after.indexOf('"');
      if (end >= 0) {
        final path = _parseLensPath(after.substring(end + 1).trim());
        if (path == null) return null;
        return _LensGrep(after.substring(0, end), path);
      }
    }
    final split = trimmed.indexOf(' ');
    if (split < 0) return null;
    final path = _parseLensPath(trimmed.substring(split + 1).trim());
    if (path == null) return null;
    return _LensGrep(trimmed.substring(0, split), path);
  }

  /// The path GRAMMAR, kept apart from the lookup exactly as the engine keeps
  /// them apart: a line that does not parse is not a command, while one that
  /// parses but does not resolve is a command carrying "no such scope".
  static _LensPath? _parseLensPath(String input) {
    final trimmed = input.trim();
    if (!trimmed.startsWith('g\\') && !trimmed.startsWith('g/')) return null;
    final parts = [
      for (final p in trimmed.substring(2).split(RegExp(r'[\\/]')))
        if (p.isNotEmpty) p,
    ];
    return switch (parts.length) {
      1 => _LensPath(group: parts[0]),
      2 => _LensPath(group: parts[0], workspace: parts[1]),
      // Three segments are a board, unless the leaf looks like a file — then it
      // is a file sitting in the workspace with no board between them.
      3 when _looksLikeFile(parts[2]) =>
        _LensPath(group: parts[0], workspace: parts[1], file: parts[2]),
      3 => _LensPath(group: parts[0], workspace: parts[1], board: parts[2]),
      4 => _LensPath(
          group: parts[0],
          workspace: parts[1],
          board: parts[2],
          file: parts[3]),
      // Nothing after `g\`, or deeper than group\workspace\board\file.
      _ => null,
    };
  }

  /// The names looked up against the tree. Null when any level of the path
  /// names something that is not there.
  LensResolvedPath? _resolveLensPath(_LensPath path) {
    final group = _groupNamed(path.group);
    if (group == null) return null;
    if (path.workspace.isEmpty) {
      return LensResolvedPath(
          kind: 'group', groupId: group.id, groupName: group.name);
    }
    final workspace = _workspaceNamed(group, path.workspace);
    if (workspace == null) return null;
    if (path.board.isEmpty && path.file.isEmpty) {
      return LensResolvedPath(
        kind: 'workspace',
        groupId: group.id,
        workspaceId: workspace.id,
        workspaceName: workspace.name,
      );
    }
    final board =
        path.board.isEmpty ? null : _boardNamed(workspace, path.board);
    if (path.board.isNotEmpty && board == null) return null;
    if (path.file.isEmpty) {
      return LensResolvedPath(
        kind: 'board',
        groupId: group.id,
        workspaceId: workspace.id,
        boardId: board!.id,
        boardName: board.name,
      );
    }
    final file =
        _files[_handle(group.id, workspace.id, board?.id ?? '', path.file)];
    return LensResolvedPath(
      kind: 'file',
      groupId: group.id,
      workspaceId: workspace.id,
      boardId: board?.id ?? '',
      fileName: path.file,
      // A tombstoned row stops resolving its bytes, the same way the engine's
      // own resolve misses it.
      filePath: file == null || _deletedFiles.contains(file.id)
          ? ''
          : file.localPath,
    );
  }

  /// The extensions the engine's path grammar reads as a file leaf.
  static const Set<String> _pathFileExtensions = {
    '.pdf', '.txt', '.md', '.docx', '.doc', '.csv',
    '.json', '.xml', '.html', '.rtf', '.xlsx', '.pptx',
    '.png', '.jpg', '.jpeg', '.gif', '.heic', '.svg',
  };

  static bool _looksLikeFile(String name) {
    final lower = name.toLowerCase();
    return _pathFileExtensions.any(lower.endsWith);
  }

  CyanGroup? _groupNamed(String name) {
    for (final group in _groups) {
      if (_equalsIgnoreCase(group.name, name)) return group;
    }
    return null;
  }

  static CyanWorkspace? _workspaceNamed(CyanGroup group, String name) {
    for (final workspace in group.workspaces) {
      if (_equalsIgnoreCase(workspace.name, name)) return workspace;
    }
    return null;
  }

  static CyanBoard? _boardNamed(CyanWorkspace workspace, String name) {
    for (final board in workspace.boards) {
      if (_equalsIgnoreCase(board.name, name)) return board;
    }
    return null;
  }

  /// The engine matches names COLLATE NOCASE, so the fake does too — otherwise
  /// a path that resolves against the real store misses here.
  static bool _equalsIgnoreCase(String a, String b) =>
      a.toLowerCase() == b.toLowerCase();

  static bool _startsWith(String name, String filter) =>
      name.toLowerCase().startsWith(filter.toLowerCase());

  static List<T> _byName<T>(Iterable<T> rows, String Function(T) name) =>
      rows.toList()..sort((a, b) => name(a).compareTo(name(b)));

  /// The engine's LIMIT 10 on every completion level.
  static List<PathSuggestion> _capped(List<PathSuggestion> rows) =>
      rows.length <= 10 ? rows : rows.sublist(0, 10);

  static const String _pipelineHelpText =
      'Pipeline commands: compile, run, status, approve, export';

  static const String _lensHelpText = '''CyanLens Commands:

  /summarize g\\Group\\Workspace\\Board    Summarize a scope
  /summarize file g\\...\\file.pdf        Extract and summarize a file
  /grep "term" g\\Group\\Workspace        Search for term in scope
  /pin                                  Pin last summary as a board
  /status                               Status report (current scope)
  /status g\\Group                       Status report for specific scope
  /pulse                                Quick pulse (current scope)
  /import jira                          List Jira projects
  /import jira AUTH                     Import Jira project as boards
  /import jira all                      Import all Jira projects
  /import confluence                    List Confluence spaces
  /import confluence ENG                Import Confluence space as boards
  /import gdocs                         List Google Docs
  /import gdocs all                     Import all docs as boards
  /pipeline compile g\\...\\Board          Compile steps to pipeline config
  /pipeline run g\\...\\Board              Execute pipeline DAG
  /pipeline status g\\...\\Board           Show pipeline state
  /pipeline approve step_id             Approve a pipeline step
  /pipeline export g\\...\\Board           Export as Airflow DAG
  /help                                 Show this help

Path format: g\\GroupName\\WorkspaceName\\BoardName\\file.ext
Shortcuts: /s = /summarize, /st = /status, /pl = /pulse, /p = /pin, /i = /import, /pipe = /pipeline''';

  // ---- demo seeding ---------------------------------------------------------

  @override
  Future<void> seedDemo() async {
    // Idempotent truncate-then-seed of the MANAGED groups, like the engine's:
    // seeding twice converges on exactly one demo set rather than doubling it,
    // and anything seeded outside it (the persona cast) is left standing.
    final fixture = _buildGroups();
    final managed = {for (final g in fixture) g.id};
    _groups = [
      for (final g in _groups)
        if (!managed.contains(g.id)) g,
      ...fixture,
    ];
  }

  @override
  Future<SeedPersonasResult> seedPersonas(
      {String tenantId = '', String ownerNodeId = ''}) async {
    // The gate is the ENGINE's (`CYAN_SEED_DEMO=1`); this is the double for a
    // build with it ON, so the cast really lands and the manifest is real.
    const groupId = 'seedtok-studio';
    const workspaceId = 'seedtok-studio-default';
    final group = CyanGroup(
      id: groupId,
      name: 'SeedTok Studio',
      colorHex: '#F59E0B',
      peerCount: _seedCast.length,
      workspaces: [
        CyanWorkspace(
          id: workspaceId,
          groupId: groupId,
          name: 'Default',
          boards: [
            for (final persona in _seedCast)
              CyanBoard(
                id: persona.boardId,
                workspaceId: workspaceId,
                name: persona.boardName,
                activeFace: BoardFaceKind.notes,
                stepCount: 1,
                createdAt: _epoch,
                lastModified: _epoch,
              ),
          ],
        ),
      ],
    );
    // Idempotent the same way the engine's is: the group is truncated and
    // re-seeded, never appended a second time.
    _groups = [
      for (final g in _groups)
        if (g.id != groupId) g,
      group,
    ];
    return SeedPersonasResult(
      personas: [
        for (final persona in _seedCast)
          SeedPersona(
            token: persona.token,
            display: persona.display,
            craftRole: persona.craftRole,
            displayRole: persona.displayRole,
            // The routing key is DERIVED from the craft role, never stored
            // beside it — the same map [selectorResolve] answers with.
            primarySurface: _primarySurface(persona.craftRole),
            groupId: groupId,
            boardId: persona.boardId,
            boardName: persona.boardName,
          ),
      ],
    );
  }

  /// The engine's six-role cast, in its display order. `display_role` differs
  /// from `craft_role` only for the post supervisor, who rides `studio_exec`.
  /// The routing surface is left off here because it is derived, not stored.
  static const List<SeedPersona> _seedCast = [
    SeedPersona(
      token: 'seedtok_post_super',
      display: 'Morgan Pierce',
      craftRole: 'studio_exec',
      displayRole: 'post_super',
      boardId: 'seedtok-postsuper-wall',
      boardName: 'Post-Production — Slate Overview',
    ),
    SeedPersona(
      token: 'seedtok_producer',
      display: 'Dana Whitfield',
      craftRole: 'producer',
      displayRole: 'producer',
      boardId: 'seedtok-producer-show',
      boardName: "Sintel — Producer's Cut",
    ),
    SeedPersona(
      token: 'seedtok_director',
      display: 'Alex Rivera',
      craftRole: 'director',
      displayRole: 'director',
      boardId: 'seedtok-director-review',
      boardName: 'Tears of Steel — Director Review',
    ),
    SeedPersona(
      token: 'seedtok_editor',
      display: 'Sam Okafor',
      craftRole: 'editor',
      displayRole: 'editor',
      boardId: 'seedtok-editor-notebook',
      boardName: 'Elephants Dream — Assembly',
    ),
    SeedPersona(
      token: 'seedtok_asseditor',
      display: 'Riya Nair',
      craftRole: 'assistant_editor',
      displayRole: 'assistant_editor',
      boardId: 'seedtok-ae-queue',
      boardName: 'Big Buck Bunny — Turnover Prep',
    ),
    SeedPersona(
      token: 'seedtok_colorist',
      display: 'Noa Berger',
      craftRole: 'colorist',
      displayRole: 'colorist',
      boardId: 'seedtok-colorist-review',
      boardName: 'Jellyfish — Color Pass',
    ),
  ];

  /// A stable 16-hex-character digest. Not cryptography — it is the fake's
  /// stand-in for one, and it is deterministic so goldens stay byte-stable.
  static String _digest(String input) {
    var lo = 0x811c9dc5;
    var hi = 0x01000193;
    for (final unit in input.codeUnits) {
      lo = ((lo ^ unit) * 0x01000193) & 0xFFFFFFFF;
      hi = ((hi + unit) * 0x85ebca6b) & 0xFFFFFFFF;
    }
    return lo.toRadixString(16).padLeft(8, '0') +
        hi.toRadixString(16).padLeft(8, '0');
  }

  static int _hash(String input) {
    var h = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }
}

/// A lens path as WRITTEN — the names, before any lookup. Levels the line did
/// not name stay empty, which is how the grammar records its depth.
class _LensPath {
  const _LensPath({
    required this.group,
    this.workspace = '',
    this.board = '',
    this.file = '',
  });

  final String group;
  final String workspace;
  final String board;
  final String file;
}

/// A parsed `/grep`: the term, and the scope it searches.
class _LensGrep {
  const _LensGrep(this.term, this.path);

  final String term;
  final _LensPath path;
}

/// One scope's anonymous session. Mutable: revealing MOVES it, and only ever
/// in the one direction.
class _FakeAnonSession {
  _FakeAnonSession({required this.handle, required this.ephemeralKey});

  final String handle;
  final String ephemeralKey;
  bool revealed = false;
}

/// One step inside a fake compiled pipeline. Mutable — the fake's whole point
/// is that approve/reject/retry/reset actually MOVE the state machine.
class _FakePipelineStep {
  _FakePipelineStep({
    required this.stepId,
    required this.title,
    required this.stage,
    required this.executor,
    required this.durationSecs,
    this.dependsOn = const [],
    this.reviewHold = false,
    this.waitingOn,
    this.localGate = false,
  });

  final String stepId;
  final String title;
  final String stage;
  final String executor; // "local" | "cloud" | "manual"
  final double durationSecs;
  final List<String> dependsOn;
  final bool reviewHold;

  /// Not final: a compile re-stamps it from the board's current assignee.
  String? waitingOn;
  final bool localGate;

  PipelineStepState status = PipelineStepState.pending;
  String? aiResult;
  String? error;

  /// The step has executed at least once — cost and duration only accrue then.
  bool hasRun = false;

  /// Σ(wall-seconds × GPU rate), the same arithmetic the engine bills with.
  double get costDollars =>
      hasRun ? durationSecs * 1000 * FakeCyanBackend._usdPerGpuMs : 0;

  void reset() {
    status = PipelineStepState.pending;
    error = null;
    aiResult = null;
    hasRun = false;
  }
}

/// A step cell's edit history for `stepEditTravel`: revisions oldest-first with
/// a cursor at the live one.
class _FakeStepHistory {
  _FakeStepHistory(this.revisions) : _cursor = revisions.length - 1;

  /// Three deterministic revisions, so undo/redo has somewhere to go.
  factory _FakeStepHistory.seeded(String title) => _FakeStepHistory([
        title,
        '$title, twice',
        '$title, with the reviewed notes',
      ]);

  final List<String> revisions;
  int _cursor;

  String get content => revisions[_cursor];
  int get undoDepth => _cursor;
  int get redoDepth => revisions.length - 1 - _cursor;

  bool undo() {
    if (_cursor == 0) return false;
    _cursor--;
    return true;
  }

  bool redo() {
    if (_cursor == revisions.length - 1) return false;
    _cursor++;
    return true;
  }
}
