// ffi/cyan_backend_ffi.dart
//
// Production implementation of the `CyanBackend` seam. It is a thin adapter
// over the existing `CyanFFI` static surface (ffi_helpers.dart) — it does NOT
// change any FFI signature or behavior. It simply reads the engine via the same
// calls the legacy widgets use today and maps the wire JSON into the parity
// view models (parity_models.dart).
//
// This keeps the rule "no parity screen calls FFI directly": screens depend on
// `CyanBackend`; only this file (and the legacy widgets being migrated) touch
// `CyanFFI`.

import 'dart:convert';

import 'cyan_backend.dart';
import 'ffi_helpers.dart';
import 'parity_models.dart';

class CyanBackendFFI implements CyanBackend {
  bool _ready = false;

  @override
  Future<void> initialize() async {
    await CyanFFI.initializeCache();
    // The engine is initialised by the existing app bootstrap; we only need the
    // cache here. Mark ready once that completes.
    _ready = true;
  }

  @override
  bool get isReady => _ready || CyanFFI.isReady();

  @override
  Future<List<CyanGroup>> loadGroups() async {
    // The legacy tree is assembled by file_tree_provider from several FFI
    // calls. For the seam we read the flat board list and group it; full tree
    // hydration (workspaces with no boards) is added when the Explorer screen
    // lands. For now derive groups from the boards we can see.
    final boards = await loadAllBoards();
    final byGroup = <String, CyanGroup>{};
    for (final b in boards) {
      byGroup.putIfAbsent(b.group.id, () => b.group);
    }
    return byGroup.values.toList();
  }

  @override
  Future<List<BoardWithContext>> loadAllBoards() async {
    final json = CyanFFI.getAllBoards();
    if (json == null || json.isEmpty) return const [];
    final List<dynamic> raw;
    try {
      raw = jsonDecode(json) as List<dynamic>;
    } catch (_) {
      return const [];
    }

    final out = <BoardWithContext>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final boardId = item['id'] as String? ?? '';
      final wsId = item['workspace_id'] as String? ?? '';
      final groupId = item['group_id'] as String? ?? '';
      final groupName = item['group_name'] as String? ?? 'Group';
      final groupColor = item['group_color'] as String? ?? '#66D9EF';
      final wsName = item['workspace_name'] as String? ?? 'Workspace';

      final faceStr = CyanFFI.getBoardMode(boardId);
      final labels = _labels(boardId);

      final board = CyanBoard(
        id: boardId,
        workspaceId: wsId,
        name: item['name'] as String? ?? 'Untitled',
        activeFace: BoardFaceKindX.fromString(faceStr),
        isPinned: CyanFFI.isBoardPinned(boardId),
        rating: item['rating'] as int? ?? 0,
        labels: labels,
        stepCount: item['element_count'] as int? ?? 0,
        isDeployed: item['is_deployed'] as bool? ?? false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            ((item['created_at'] as int?) ?? 0) * 1000),
        lastModified: item['last_modified'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (item['last_modified'] as int) * 1000)
            : null,
      );

      final group = CyanGroup(
          id: groupId, name: groupName, colorHex: groupColor);
      final workspace =
          CyanWorkspace(id: wsId, groupId: groupId, name: wsName);
      out.add(
          BoardWithContext(board: board, group: group, workspace: workspace));
    }
    return out;
  }

  @override
  Future<WorkflowRun?> loadRun(String boardId) async {
    // Run hydration arrives with the Dashboard screen (row 4). Until the engine
    // surfaces a run shape through this seam, return null rather than fake one.
    return null;
  }

  // ---- board faces ---------------------------------------------------------
  //
  // The screens below are ported + tested against `FakeCyanBackend` (Tier-1).
  // Real FFI hydration is Tier-2 (deferred). Until the engine surfaces these
  // shapes through the seam, return honest empty/disconnected defaults rather
  // than fabricate data — a screen that loads nothing is correct for "not wired
  // yet", and the parity look is already proven by the Tier-1 goldens.

  @override
  Future<Workflow> loadWorkflow(String boardId) async =>
      Workflow(boardId: boardId);

  @override
  Future<BoardNotes> loadNotes(String boardId) async =>
      BoardNotes(boardId: boardId, fileName: 'notes.md', content: '');

  @override
  Future<List<OpsRun>> loadOpsRuns() async => const [];

  @override
  Future<CostMeter> loadCostMeter() async => const CostMeter(
        hasMeter: false,
        billedMinutes: 0,
        billedDollars: 0,
        retryMinutes: 0,
        savedMinutes: 0,
        runs: 0,
        computeMinutes: 0,
        gpuSeconds: 0,
      );

  @override
  Future<EfficiencyReport> loadEfficiency() async => const EfficiencyReport(
        gateBottleneckStep: '',
        gateWaitP95Ms: 0,
        failureHotspotStep: '',
        failureRatePct: 0,
        slowestStep: '',
        slowestExecP95Ms: 0,
        cacheHitRatePct: 0,
        minutesSaved: 0,
        retryRatePct: 0,
      );

  @override
  Future<List<PluginCard>> loadMarketplace() async => const [];

  @override
  Future<LensIntelligence> loadLensIntelligence() async =>
      const LensIntelligence(connected: false);

  @override
  Future<List<ChatMessage>> loadChat(String boardId) async => const [];

  List<String> _labels(String boardId) {
    final metaJson = CyanFFI.getBoardMetadata(boardId);
    if (metaJson == null || metaJson.isEmpty) return const [];
    try {
      final meta = jsonDecode(metaJson) as Map<String, dynamic>;
      return (meta['labels'] as List<dynamic>?)?.cast<String>() ?? const [];
    } catch (_) {
      return const [];
    }
  }
}
