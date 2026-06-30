// ffi/fake_cyan_backend.dart
//
// Tier-1 test/demo implementation of the `CyanBackend` seam. Returns fixed,
// deterministic demo data so widget + golden tests render without any native
// library or running engine. NO FFI, NO async I/O, NO randomness — goldens must
// be byte-stable across runs and machines.
//
// Seeded fixture: 3 groups / 10 boards total, plus one sample workflow run.

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

  late final List<CyanGroup> _groups = _buildGroups();

  @override
  Future<List<CyanGroup>> loadGroups() async => _groups;

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

  // ---- marketplace ----------------------------------------------------------

  @override
  Future<List<PluginCard>> loadMarketplace() async => const [
        PluginCard(
          id: 'pl-ffmpeg',
          name: 'FFmpeg Transcode',
          publisher: 'cyan-core',
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

  // -------------------------------------------------------------------------

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
}
