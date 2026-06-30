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
