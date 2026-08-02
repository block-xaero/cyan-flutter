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

import '../models/mesh_status.dart';
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

  // ---- tree mutation --------------------------------------------------------
  //
  // `cyan_create_group` / `cyan_create_workspace` / `cyan_create_board` /
  // `cyan_rename_board` / `cyan_delete_board` are already bound
  // (cyan_bindings.dart); these are the seam-side names for them. Void on the
  // wire, exactly like the Swift actor sends.

  @override
  // `CyanFFI.createGroup` already defaults to the `folder.fill` / `#00AEEF`
  // pair `commitRename` hardcodes on the Swift side. The engine seeds General +
  // Plugins behind this call and reports them as WorkspaceCreated events.
  Future<void> createGroup(String name) async => CyanFFI.createGroup(name);

  @override
  Future<void> createWorkspace(String groupId, String name) async =>
      CyanFFI.createWorkspace(groupId, name);

  @override
  Future<void> createBoard(String workspaceId, String name) async =>
      CyanFFI.createBoard(workspaceId, name);

  @override
  Future<void> renameBoard(String boardId, String name) async =>
      CyanFFI.renameBoard(boardId, name);

  @override
  Future<void> deleteBoard(String boardId) async =>
      CyanFFI.deleteBoard(boardId);

  // ---- board pins ------------------------------------------------------------

  @override
  Future<void> pinSet(String boardId, bool pinned) async =>
      CyanFFI.pinSet(boardId, pinned);

  @override
  Future<String?> pinSummaryAsBoard(
      String workspaceId, String boardName, String markdownContent) async {
    final id =
        CyanFFI.pinSummaryAsBoard(workspaceId, boardName, markdownContent);
    return (id == null || id.isEmpty) ? null : id;
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

  // The Workflow face IS wired: the authored steps are the board's `step`
  // cells, and the compile stamps its plan into each cell's `metadata_json`.
  // Same reading as Swift's `WorkflowViewModel.parseSteps`.

  @override
  Future<Workflow> loadWorkflow(String boardId) async {
    final steps = _workflowSteps(boardId);
    // Deploy/lock is its own engine row, not something the cells carry.
    final state = await boardWorkflowState(boardId);
    return Workflow(
      boardId: boardId,
      steps: steps,
      isDeployed: state.error == null && state.isDeployed,
      // "Compiled" is not a flag the engine keeps — it is visible in the cells:
      // a compile is what puts a `pipeline` object into a step's metadata.
      isCompiled: steps.isNotEmpty && steps.every(_isCompiled),
    );
  }

  static bool _isCompiled(WorkflowStep s) =>
      s.tool != null || s.destination != null || s.gate != null;

  /// The board's authored steps, oldest-first by `cell_order`.
  List<WorkflowStep> _workflowSteps(String boardId) {
    final raw = CyanFFI.loadNotebookCells(boardId);
    if (raw == null || raw.isEmpty) return const [];
    final List<dynamic> cells;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      cells = decoded;
    } catch (_) {
      return const [];
    }

    final out = <({int order, WorkflowStep step})>[];
    for (final cell in cells) {
      if (cell is! Map<String, dynamic>) continue;
      final kind = cell['cell_type'] as String?;
      // `timecode_note` cells are run RESULTS the executor persisted — their
      // metadata carries a `pipeline_step_id`, never an authored step.
      if (kind == 'timecode_note') continue;
      final id = cell['id'] as String?;
      if (id == null) continue;
      final text = cell['content'] as String? ?? '';
      // Authored English can never parse as a JSON container, so a cell whose
      // BODY is one is a run result an older build wrote into the ledger —
      // whatever kind or metadata it carries.
      if (_isJsonBody(text)) continue;
      final meta = _decode(cell['metadata_json'] as String?);
      final plan = meta?['pipeline'];
      if (kind != 'step' && plan is! Map<String, dynamic>) continue;
      out.add((
        order: _int(cell['cell_order']),
        step: _workflowStep(id, text, meta),
      ));
    }
    out.sort((a, b) => a.order.compareTo(b.order));
    return [for (final e in out) e.step];
  }

  static bool _isJsonBody(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return false;
    try {
      final parsed = jsonDecode(trimmed);
      return parsed is Map || parsed is List;
    } catch (_) {
      return false;
    }
  }

  /// One step's compile verdict, read from the cell metadata the compile wrote.
  /// The bind is ENGINE truth (`mcp_tool` / `mcp_tool_miss`) — never guessed
  /// from the pipeline config's model placeholder, which would show every step
  /// as routed to the lens.
  WorkflowStep _workflowStep(
      String id, String text, Map<String, dynamic>? meta) {
    final plan = meta?['pipeline'];
    if (plan is! Map<String, dynamic>) {
      // Authored but not yet compiled: no chips, and no ambiguity verdict
      // either — nothing has tried to resolve it yet.
      return WorkflowStep(id: id, text: text);
    }
    var tool = _boundToolName(meta);
    if (tool == null) {
      final model = plan['model'] as String?;
      // `cyan-lens` is the MODEL placeholder, not a tool — rendering it as one
      // reads as "routes to cyan-lens" on every step.
      if (model != null && model.isNotEmpty && model != 'cyan-lens') {
        tool = model;
      }
    }
    final missed = meta?['mcp_tool_miss'] is Map<String, dynamic>;
    return WorkflowStep(
      id: id,
      text: text,
      tool: tool,
      destination: _executorLabel(plan['executor'] as String?),
      boundInputs: (plan['depends_on'] as List<dynamic>?)?.cast<String>() ??
          const <String>[],
      gate: plan['auto_advance'] == true
          ? StepGate.noApproval
          : StepGate.needsApproval,
      // The compile ran and resolved nothing: the face asks rather than
      // inventing a tool for it.
      isAmbiguous: tool == null || missed,
    );
  }

  /// The tool a compile BOUND to a cell, as engine truth: the `mcp_tool` the
  /// bind wrote, else the command its pipeline runs. Null when the compile
  /// resolved nothing — the model placeholder is deliberately not read here,
  /// because "routes to the lens" is not a bound tool.
  static String? _boundToolName(Map<String, dynamic>? meta) {
    final bound = meta?['mcp_tool'];
    if (bound is Map<String, dynamic> &&
        bound['plugin_id'] is String &&
        bound['tool'] is String) {
      return '${bound['plugin_id']}.${bound['tool']}';
    }
    final plan = meta?['pipeline'];
    if (plan is Map<String, dynamic>) {
      final command = (plan['command'] as String?)?.trim();
      if (command != null && command.isNotEmpty) return command;
    }
    return null;
  }

  static String? _executorLabel(String? executor) => switch (executor) {
        'local' => 'Local',
        'cloud' => 'Cloud',
        'manual' => 'Manual',
        'lens' => 'AI (Lens)',
        _ => null,
      };

  // The notebook DOCUMENT: the same `cyan_load_notebook_cells` ledger the
  // Workflow face reads its steps out of, unfiltered — every cell the board
  // holds, in `cell_order`.

  @override
  Future<List<NotebookCell>> notebookCells(String boardId) async {
    final raw = CyanFFI.loadNotebookCells(boardId);
    if (raw == null || raw.isEmpty) return const [];
    final List<dynamic> cells;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      cells = decoded;
    } catch (_) {
      return const [];
    }

    final out = <NotebookCell>[];
    for (final cell in cells) {
      if (cell is! Map<String, dynamic>) continue;
      final id = cell['id'] as String?;
      if (id == null) continue;
      final meta = _decode(cell['metadata_json'] as String?);
      out.add(NotebookCell(
        id: id,
        boardId: cell['board_id'] as String? ?? boardId,
        kind: notebookCellKindFrom(cell['cell_type'] as String?),
        order: _int(cell['cell_order']),
        content: cell['content'] as String? ?? '',
        output: cell['output'] as String?,
        language: meta?['language'] as String?,
        tool: _boundToolName(meta),
        generatedFrom: meta?['generated_from'] as String?,
        caption: meta?['caption'] as String?,
        collapsed: cell['collapsed'] == true,
      ));
    }
    out.sort((a, b) => a.order.compareTo(b.order));
    return out;
  }

  @override
  Future<WorkflowStep?> addWorkflowStep(String boardId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final existing = _workflowSteps(boardId);
    final step = WorkflowStep(
      id: 'step-${DateTime.now().microsecondsSinceEpoch}',
      text: trimmed,
    );
    final saved = CyanFFI.saveNotebookCell(
        boardId, _stepCell(boardId, step, existing.length));
    return saved ? step : null;
  }

  @override
  Future<bool> updateWorkflowStep(
      String boardId, String stepId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final steps = _workflowSteps(boardId);
    final index = steps.indexWhere((s) => s.id == stepId);
    if (index < 0) return false;
    return CyanFFI.saveNotebookCell(
      boardId,
      _stepCell(boardId, WorkflowStep(id: stepId, text: trimmed), index),
    );
  }

  /// The `cyan_save_notebook_cell` payload for an authored step. `cell_type` is
  /// always `step` — the engine coerces anyway, we are explicit.
  Map<String, dynamic> _stepCell(String boardId, WorkflowStep step, int order) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return {
      'id': step.id,
      'board_id': boardId,
      'cell_type': 'step',
      'cell_order': order,
      'content': step.text,
      'collapsed': false,
      'created_at': now,
      'updated_at': now,
    };
  }

  @override
  Future<BoardNotes> loadNotes(String boardId) async =>
      BoardNotes(boardId: boardId, fileName: 'notes.md', content: '');

  // The board container's face, straight through to the engine's board-mode
  // pair — the two verbs Swift's `BoardFaceBridge` wraps.

  @override
  Future<String?> boardActiveFace(String boardId) async =>
      CyanFFI.getBoardMode(boardId);

  @override
  Future<bool> setBoardActiveFace(String boardId, String face) async =>
      CyanFFI.setBoardMode(boardId, face);

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

  // The run audit rides the lens console rail, which this build does not bind.
  // No trace rather than a fabricated one: the audit face says so on screen.
  @override
  Future<RunTrace?> loadRunTrace(String runId) async => null;

  // No `cyan_*` verb caches the signed grant on this build, so nothing is
  // cached — the license read-model falls back to the offline trial default
  // and the app never hard-locks itself.
  @override
  Future<String?> cachedEntitlementJson() async => null;

  @override
  Future<List<PluginCard>> loadMarketplace() async => const [];

  // The device's own plugin catalog: `cyan_plugin_catalog` walks the plugins
  // root and skips any bundle whose manifest will not parse, so an empty list
  // means "nothing installed", never "nothing readable". A dead binding answers
  // null, which is NOT the same thing — that path yields the empty list too,
  // because either way there is no bundle to name and inventing one would be
  // worse than saying nothing.

  @override
  Future<List<InstalledPlugin>> pluginCatalog() async {
    final map = _decode(CyanFFI.pluginCatalog());
    if (map == null) return const [];
    return [
      for (final p in (map['plugins'] as List? ?? const []))
        if (p is Map<String, dynamic>) InstalledPlugin.fromJson(p),
    ];
  }

  @override
  Future<PluginInstallResult> installPluginBundle(
      String groupId, String pluginId, String bundleBytesB64) async {
    // The ENGINE gates layout + signature policy before anything lands, so a
    // malformed or unadmitted bundle comes back as its own refusal — nothing
    // is judged here. No payload at all is the one case this seam names.
    final map = _decode(
        CyanFFI.installPluginBundle(groupId, pluginId, bundleBytesB64));
    if (map == null) return const PluginInstallResult.unavailable();
    return PluginInstallResult.fromJson(map);
  }

  // The non-secret half of a plugin's setup. Both verbs take the engine's JSON
  // envelope; the group id IS the engine's tenant. Credentials never come
  // through here — `cyan_plugin_config_set` refuses a secret-looking key itself
  // and that refusal is carried verbatim to the sheet.

  @override
  Future<PluginConfig> pluginConfigGet(String groupId, String pluginId) async {
    // No `key`: the engine answers every row for the tenant, workflow
    // overrides already merged over tenant defaults.
    final map = _decode(CyanFFI.pluginConfigGet(
        jsonEncode({'plugin_id': pluginId, 'tenant_id': groupId})));
    if (map == null) return PluginConfig.unavailable(pluginId);
    return PluginConfig.fromJson(pluginId, map);
  }

  @override
  Future<PluginConfigWrite> pluginConfigSet(
      String groupId, String pluginId, String key, String value) async {
    final map = _decode(CyanFFI.pluginConfigSet(jsonEncode({
      'plugin_id': pluginId,
      'tenant_id': groupId,
      'key': key,
      'value': value,
    })));
    if (map == null) return const PluginConfigWrite.unavailable();
    return PluginConfigWrite.fromJson(map);
  }

  @override
  Future<LensIntelligence> loadLensIntelligence() async =>
      const LensIntelligence(connected: false);

  @override
  Future<List<ChatMessage>> loadChat(String boardId) async => const [];

  @override
  Future<void> loadChatHistory(String boardId) async =>
      CyanFFI.loadChatHistory(boardId);

  @override
  Future<ChatMessage?> sendChat(String boardId, String message,
      {String? parentId}) async {
    // Whitespace-only is refused HERE, before the wire — the engine would
    // happily gossip an empty message to every peer.
    final trimmed = message.trim();
    if (trimmed.isEmpty) return null;
    CyanFFI.sendChat(boardId, trimmed, parentId: parentId);
    // The send is VOID on the wire: the engine mints the id and echoes the
    // message back as a `ChatSent` frame rather than answering here. The
    // transcript therefore comes from the event stream, and this local echo
    // carries no id to claim one the engine did not mint.
    return ChatMessage(
      id: '',
      author: 'You',
      isOwn: true,
      body: trimmed,
      timeLabel: _clockLabel(DateTime.now()),
    );
  }

  @override
  Future<void> deleteChat(String messageId) async =>
      CyanFFI.deleteChat(messageId);

  /// A wall-clock stamp as the transcript renders it (`10:14 AM`).
  static String _clockLabel(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  // ---- unread ---------------------------------------------------------------

  @override
  Future<Map<String, int>> unreadCounts() async {
    // The engine answers `{}` for a device with nothing unread, which decodes
    // to the same empty map a dead binding gives — and both mean the caller has
    // no badge to draw, so neither is singled out.
    final map = _decode(CyanFFI.unreadCounts());
    if (map == null) return const {};
    return {
      for (final e in map.entries)
        if (e.value is num) e.key: (e.value as num).toInt(),
    };
  }

  @override
  Future<void> markRead(String scopeId) async => CyanFFI.markRead(scopeId);

  // ---- files ----------------------------------------------------------------

  @override
  Future<List<CyanFile>> filesForBoard(String boardId) async {
    // An empty list is the engine's answer for a board with no files, and it
    // is also what a dead binding leaves — both mean there is nothing to list.
    final json = CyanFFI.getFiles({'type': 'board', 'id': boardId});
    if (json == null) return const [];
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return [
      for (final row in decoded)
        if (row is Map<String, dynamic>) CyanFile.fromJson(row),
    ];
  }

  @override
  Future<bool> requestFileDownload(String fileId) async =>
      CyanFFI.requestFileDownload(fileId);

  @override
  Future<FileTransfer?> fileStatus(String fileId) async {
    // Null is the engine's "I do not know that id" — a file it cannot place has
    // no transfer to report, and reporting `unknown` instead would tell a
    // caller the file exists.
    final map = _decode(CyanFFI.getFileStatus(fileId));
    if (map == null) return null;
    return FileTransfer.fromJson(map);
  }

  @override
  Future<void> deleteFile(String fileId) async => CyanFFI.deleteFile(fileId);

  @override
  Future<CyanFile?> resolveFileHandle(String groupId, String workspaceId,
      String boardId, String fileName) async {
    // Null IS the engine's answer for "no active file under that handle", so a
    // dead binding reads the same way — either way there is no file to hand
    // back, and inventing one would be worse than saying so.
    final map = _decode(
        CyanFFI.resolveFileHandle(groupId, workspaceId, boardId, fileName));
    if (map == null) return null;
    return CyanFile.fromJson(map);
  }

  // Null is the engine's own "could not read it". An empty string back from a
  // file it COULD read is a real answer — a document with no extractable text —
  // so it is passed through rather than flattened into null.
  @override
  Future<String?> extractFileText(String path) async =>
      CyanFFI.extractFileText(path);

  @override
  Future<MeshPresence> meshPresence() async {
    // The engine's own total is authoritative — the per-group map is what is
    // BEHIND it. A node that cannot answer has no peers to report, which is
    // the honest reading rather than an error to swallow upstream.
    final total = CyanFFI.getTotalPeerCount();
    final json = CyanFFI.getAllPeers();
    if (json == null || json.isEmpty) {
      return MeshPresence(totalPeers: total);
    }
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return MeshPresence(totalPeers: total);
      return MeshPresence.fromJson(decoded, totalPeers: total);
    } catch (_) {
      return MeshPresence(totalPeers: total);
    }
  }

  @override
  Future<DeviceProfile?> myProfile() async {
    // No node id means no identity on this device — signed-out, not a blank
    // profile. The profile verb's payload is optional on top of that: a node
    // that never set a display name still HAS an identity.
    final nodeId = CyanFFI.getMyNodeId();
    if (nodeId == null || nodeId.isEmpty) return null;
    final json = CyanFFI.getMyProfile();
    if (json != null && json.isNotEmpty) {
      try {
        final decoded = jsonDecode(json);
        if (decoded is Map<String, dynamic>) {
          return DeviceProfile.fromJson(decoded, nodeId: nodeId);
        }
      } catch (_) {}
    }
    return DeviceProfile(nodeId: nodeId);
  }

  // ---- pipeline (the compile / run / gate spine) ----------------------------
  //
  // Straight through to the engine: one `cyan_pipeline_*` / `cyan_run_pipeline`
  // / `cyan_step_edit_travel` call each, decoded from its JSON envelope into
  // the parity model. Nothing here invents progress — a missing dylib answers
  // with the no-op binding (null), which surfaces as [_engineUnreachable] on
  // the envelope, and an engine-side `{"error":…}` is passed through verbatim.

  /// What a null FFI reply means: the bindings are no-ops because no native
  /// library loaded. Reported as an error, never as a clean empty result.
  static const String _engineUnreachable = 'engine unreachable';

  @override
  Future<PipelineLaunch> pipelineCompile(String boardId) async =>
      _launch(boardId, CyanFFI.pipelineCompile(boardId));

  @override
  Future<PipelineLaunch> runPipeline(String boardId) async =>
      _launch(boardId, CyanFFI.runPipeline(boardId));

  @override
  Future<PipelineStatus> pipelineStatus(String boardId) async {
    final map = _decode(CyanFFI.pipelineStatus(boardId));
    if (map == null) {
      return PipelineStatus(boardId: boardId, error: _engineUnreachable);
    }
    final error = map['error'] as String?;
    if (error != null) {
      return PipelineStatus(boardId: boardId, error: error);
    }
    return PipelineStatus(
      boardId: map['board_id'] as String? ?? boardId,
      runId: map['run_id'] as String?,
      status: PipelineRunStateX.fromWire(map['status'] as String?),
      totalSteps: _int(map['total_steps']),
      aiComplete: _int(map['ai_complete']),
      humanApproved: _int(map['human_approved']),
      running: _int(map['running']),
      failed: _int(map['failed']),
      pending: _int(map['pending']),
      progressPct: _int(map['progress_pct']),
      totalCostDollars: _double(map['total_cost_usd']),
      awaitingStep: map['awaiting_step'] as String?,
      steps: _pipelineSteps(map['steps']),
    );
  }

  @override
  Future<bool> pipelineApprove(String boardId, String stepId) async =>
      CyanFFI.pipelineApprove(boardId, stepId);

  @override
  Future<PipelineAck> pipelineApproveAs(
          String boardId, String stepId, String reviewer) async =>
      _ack(CyanFFI.pipelineApproveAs(boardId, stepId, reviewer));

  @override
  Future<bool> pipelineReject(String boardId, String stepId) async =>
      CyanFFI.pipelineReject(boardId, stepId);

  @override
  Future<PipelineAck> pipelineRejectAs(
          String boardId, String stepId, String reviewer) async =>
      _ack(CyanFFI.pipelineRejectAs(boardId, stepId, reviewer));

  @override
  Future<bool> pipelineRetry(String boardId, String stepId) async =>
      CyanFFI.pipelineRetry(boardId, stepId);

  @override
  Future<bool> pipelineReset(String boardId) async =>
      CyanFFI.pipelineReset(boardId);

  @override
  Future<bool> pipelineResetStep(String boardId, String stepId) async =>
      CyanFFI.pipelineResetStep(boardId, stepId);

  @override
  Future<StepRunResult> pipelineRunStepLocal(
      String boardId, String stepId) async {
    final map = _decode(CyanFFI.pipelineRunStepLocal(boardId, stepId));
    if (map == null) {
      return const StepRunResult(success: false, error: _engineUnreachable);
    }
    return StepRunResult(
      success: map['success'] as bool? ?? false,
      summary: map['summary'] as String? ?? '',
      findings: _int(map['findings']),
      isGated: map['gated'] as bool? ?? false,
      isParked: map['parked'] as bool? ?? false,
      awaiting: map['awaiting'] as String?,
      error: map['error'] as String?,
    );
  }

  @override
  Future<StepTravel> stepEditTravel(
      String boardId, String cellId, StepTravelDirection direction) async {
    final map =
        _decode(CyanFFI.stepEditTravel(boardId, cellId, direction.wireValue));
    if (map == null) return const StepTravel(error: _engineUnreachable);
    final error = map['error'] as String?;
    if (error != null) return StepTravel(error: error);
    return StepTravel(
      content: map['content'] as String? ?? '',
      undoDepth: _int(map['undo_depth']),
      redoDepth: _int(map['redo_depth']),
    );
  }

  @override
  Future<BoardWorkflowState> boardWorkflowState(String boardId) async {
    final map = _decode(CyanFFI.boardWorkflowState(boardId));
    // The engine always answers this one with an object — an undeployed board
    // comes back as the authoring default. So a null reply is NOT "undeployed",
    // it is "nobody answered", and it says so rather than inventing a state.
    if (map == null) {
      return BoardWorkflowState(boardId: boardId, error: _engineUnreachable);
    }
    final updatedAt = _int(map['updated_at']);
    return BoardWorkflowState(
      boardId: map['board_id'] as String? ?? boardId,
      isDeployed: map['deployed'] as bool? ?? false,
      hasDashboard: map['dashboard_available'] as bool? ?? false,
      isLocked: map['locked'] as bool? ?? false,
      updatedAt: updatedAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(updatedAt * 1000)
          : null,
    );
  }

  /// The shared decode for the compile/run acknowledgement envelope.
  PipelineLaunch _launch(String boardId, String? json) {
    final map = _decode(json);
    if (map == null) {
      return PipelineLaunch(boardId: boardId, error: _engineUnreachable);
    }
    final error = map['error'] as String?;
    if (error != null) return PipelineLaunch(boardId: boardId, error: error);
    return PipelineLaunch(
      boardId: map['board_id'] as String? ?? boardId,
      status: map['status'] as String? ?? '',
      message: map['message'] as String? ?? '',
    );
  }

  /// The shared decode for the `{"success":…,"error":…}` reviewer envelope.
  PipelineAck _ack(String? json) {
    final map = _decode(json);
    if (map == null) {
      return const PipelineAck(success: false, error: _engineUnreachable);
    }
    return PipelineAck(
      success: map['success'] as bool? ?? false,
      error: map['error'] as String?,
    );
  }

  List<PipelineStep> _pipelineSteps(dynamic raw) {
    if (raw is! List) return const [];
    final out = <PipelineStep>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      out.add(PipelineStep(
        stepId: item['step_id'] as String? ?? '',
        title: item['title'] as String? ?? '',
        status: PipelineStepStateX.fromWire(item['status'] as String?),
        stage: item['stage'] as String? ?? '',
        executor: item['executor'] as String? ?? '',
        dependsOn:
            (item['depends_on'] as List<dynamic>?)?.cast<String>() ?? const [],
        aiResult: item['ai_result'] as String?,
        error: item['error'] as String?,
        durationSecs: (item['duration'] as num?)?.toDouble(),
        costDollars: _double(item['cost_usd']),
        isReviewHold: item['review_hold'] as bool? ?? false,
        waitingOn: item['waiting_on'] as String?,
        isLocalGate: item['local_gate'] as bool? ?? false,
      ));
    }
    return out;
  }

  Map<String, dynamic>? _decode(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

  double _double(dynamic v) => (v as num?)?.toDouble() ?? 0;

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

  // ---- device identity + prefs ---------------------------------------------

  @override
  Future<String?> buildCommit() async {
    final commit = CyanFFI.buildCommit();
    return (commit == null || commit.isEmpty) ? null : commit;
  }

  @override
  Future<bool> deleteIdentity() async => CyanFFI.deleteIdentity();

  @override
  Future<String?> getProductionRole() async {
    // The engine answers "" for an unset pref, which is a real answer — no
    // role, not a failure. Either way there is no role to report.
    final role = CyanFFI.getProductionRole();
    return (role == null || role.isEmpty) ? null : role;
  }

  @override
  Future<bool> setProductionRole(String role) async =>
      CyanFFI.setProductionRole(role);

  @override
  Future<SelectorResolution> selectorResolve(String role, String formatType,
      {String tenantId = ''}) async {
    final map = _decode(CyanFFI.selectorResolve(tenantId, role, formatType));
    if (map == null) return const SelectorResolution(error: _engineUnreachable);
    return SelectorResolution.fromJson(map);
  }

  @override
  Future<String?> friendlyNodeId(String nodeId) async {
    final name = CyanFFI.friendlyNodeId(nodeId);
    return (name == null || name.isEmpty) ? null : name;
  }

  // ---- SSO session grants ----------------------------------------------------

  @override
  Future<SsoSession> ssoInstallGrant(
      String grantToken, String trustJson) async {
    // The engine answers a refusal as a real {"active":false,"reason":…}
    // object, so a null reply is "nobody answered" and says so — it must not
    // read back as a grant the engine rejected.
    final map = _decode(CyanFFI.ssoInstallGrant(grantToken, trustJson));
    if (map == null) {
      return const SsoSession(active: false, reason: _engineUnreachable);
    }
    return SsoSession.fromJson(map);
  }

  @override
  Future<void> ssoSignOut() async => CyanFFI.ssoSignOut();

  // ---- anonymous sessions ---------------------------------------------------

  @override
  Future<AnonymousSession?> createAnonymousSession(String scopeId) async {
    final map = _decode(CyanFFI.createAnonymousSession(scopeId));
    if (map == null) return null;
    return AnonymousSession.fromJson(map);
  }

  @override
  Future<AnonymousSession?> revealAnonymousIdentity(String scopeId) async {
    // Null is the engine's OWN answer for "no session here, or it was already
    // revealed" — a reveal cannot be undone, so it is not retried as an error.
    final map = _decode(CyanFFI.revealAnonymousIdentity(scopeId));
    if (map == null) return null;
    return AnonymousSession.fromJson(map);
  }

  @override
  Future<AnonymousStatus> getAnonymousStatus(String scopeId) async {
    // The engine answers "no session in this scope" with a real object, so a
    // null reply is "nobody answered" and says so rather than reporting the
    // device as visible.
    final map = _decode(CyanFFI.getAnonymousStatus(scopeId));
    if (map == null) return const AnonymousStatus(error: _engineUnreachable);
    return AnonymousStatus.fromJson(map);
  }

  @override
  Future<bool> exitAnonymousMode(String scopeId) async =>
      CyanFFI.exitAnonymousMode(scopeId);

  // ---- groups: roster, grants, portable bundles ------------------------------

  @override
  Future<List<GroupMember>> getGroupMembers(String groupId) async => [
        for (final m in _decodeList(CyanFFI.getGroupMembers(groupId)))
          GroupMember.fromJson(m),
      ];

  @override
  Future<GrantQrIssue> issueGrantQr(String groupId, String role,
      {int ttlSeconds = 0}) async {
    final map = _decode(CyanFFI.issueGrantQr(groupId, role, ttlSeconds));
    if (map == null) {
      return const GrantQrIssue(success: false, error: _engineUnreachable);
    }
    return GrantQrIssue.fromJson(map);
  }

  @override
  Future<GrantScanResult> scanGrantQr(String qrPayload) async {
    final map = _decode(CyanFFI.scanGrantQr(qrPayload));
    if (map == null) {
      return const GrantScanResult(success: false, error: _engineUnreachable);
    }
    return GrantScanResult.fromJson(map);
  }

  @override
  Future<String?> bundlePubkey() async {
    final key = CyanFFI.bundlePubkey();
    return (key == null || key.isEmpty) ? null : key;
  }

  @override
  Future<GroupExportResult> exportGroup(
      String groupId, String inviteePubkey) async {
    final map = _decode(CyanFFI.exportGroup(groupId, inviteePubkey));
    if (map == null) {
      return const GroupExportResult(success: false, error: _engineUnreachable);
    }
    return GroupExportResult.fromJson(map);
  }

  @override
  Future<GroupImportResult> importGroup(String bundle) async {
    final map = _decode(CyanFFI.importGroup(bundle));
    if (map == null) {
      return const GroupImportResult(success: false, error: _engineUnreachable);
    }
    return GroupImportResult.fromJson(map);
  }

  // ---- board notes: the review rail's plain CRUD ------------------------------

  @override
  Future<List<CyanNote>> noteList(String boardId) async => [
        for (final n in _decodeList(CyanFFI.noteList(boardId)))
          CyanNote.fromJson(n),
      ];

  @override
  Future<void> notePut(String boardId, String text,
      {String? noteId, String? tenantId}) async {
    // Fire-and-forget engine-side (it queues a command), so there is no receipt
    // to decode — the caller reads the note back instead.
    CyanFFI.notePut(boardId, text, noteId: noteId, tenantId: tenantId);
  }

  @override
  Future<void> noteDelete(String id) async => CyanFFI.noteDelete(id);

  // ---- timecoded notes: review pinned to a moment in the asset ----------------

  @override
  Future<List<TimecodeNote>> loadTimecodeNotes(String boardId) async => [
        for (final n in _decodeList(CyanFFI.loadTimecodeNotes(boardId)))
          TimecodeNote.fromJson(n),
      ];

  @override
  Future<bool> saveTimecodeNote(TimecodeNote note) async =>
      CyanFFI.saveTimecodeNote(jsonEncode(note.toJson()));

  @override
  Future<TimecodeNoteAction> actOnTimecodeNote(TimecodeNote note) async {
    final map = _decode(CyanFFI.actOnTimecodeNote(jsonEncode(note.toJson())));
    if (map == null) {
      return const TimecodeNoteAction(error: _engineUnreachable);
    }
    return TimecodeNoteAction.fromJson(map);
  }

  @override
  Future<String?> exportNotesMarkdown(String boardId) async {
    // Raw markdown on the wire, not JSON — the engine renders the timeline
    // itself, so there is nothing to decode. A board with no notes still has a
    // real export (the header and the totals), so only a null is "no answer".
    final markdown = CyanFFI.exportNotesMarkdown(boardId);
    return (markdown == null || markdown.isEmpty) ? null : markdown;
  }

  // ---- scoped notes + the constitution chain they feed ------------------------

  @override
  Future<List<CyanNote>> noteListScoped(String boardId, String scope,
          {String kind = ''}) async =>
      [
        for (final n
            in _decodeList(CyanFFI.noteListScoped(boardId, scope, kind: kind)))
          CyanNote.fromJson(n),
      ];

  @override
  Future<void> notePutScoped(String boardId, String text,
      {String scope = 'board', String kind = 'editor-note'}) async {
    // The write verb is fire-and-forget engine-side (it queues a command), so
    // there is no receipt to decode — the caller reads the note back instead.
    CyanFFI.notePutScoped(boardId, text, scope: scope, kind: kind);
  }

  @override
  Future<ResolvedConstitution> constitutionResolved(String boardId) async {
    // The preview verb takes a request envelope; `include_user` /
    // `include_project` default to true on this surface, which is what the
    // device owner's own preview means.
    final request = jsonEncode({'board_id': boardId});
    final map = _decode(CyanFFI.constitutionResolved(request));
    if (map == null) {
      return const ResolvedConstitution(error: _engineUnreachable);
    }
    return ResolvedConstitution.fromJson(map);
  }

  @override
  Future<EffectiveConstitution> constitutionEffective(String boardId) async {
    final map = _decode(CyanFFI.constitutionEffective(boardId));
    if (map == null) {
      return const EffectiveConstitution(error: _engineUnreachable);
    }
    return EffectiveConstitution.fromJson(map);
  }

  // ---- templates: the spine cloned onto a board ------------------------------
  //
  // Straight through to the engine: one `cyan_template_*` /
  // `cyan_workflow_from_template` call each, decoded into the parity model.
  // The clone is fire-and-forget on the wire, exactly as it is here — nothing
  // reports a clone this side has not seen the engine finish.

  @override
  Future<List<CyanTemplate>> templateList({String tenantId = ''}) async => [
        for (final t in _decodeList(CyanFFI.templateList(tenantId: tenantId)))
          CyanTemplate.fromJson(t),
      ];

  @override
  Future<void> workflowFromTemplate(String templateId, String boardId,
      {String tenantId = ''}) async {
    CyanFFI.workflowFromTemplate(templateId, boardId, tenantId: tenantId);
  }

  @override
  Future<TemplateCloneOutcome?> templateCloneOutcome(String boardId) async {
    // Null is the engine's OWN answer for "no clone has finished for this board
    // since launch" — the poll simply has nothing yet, so it is not an error.
    final map = _decode(CyanFFI.templateCloneOutcome(boardId));
    if (map == null) return null;
    return TemplateCloneOutcome.fromJson(map);
  }

  @override
  Future<TemplateSaveResult> templateSave(String tenantId, String name,
          String description, List<TemplateStep> steps) async =>
      _saved(CyanFFI.templateSave(
          tenantId, name, description, _stepsJson(steps)));

  @override
  Future<TemplateSaveResult> templateSaveFromBoard(String tenantId, String name,
          String description, List<TemplateStep> steps, String boardId) async =>
      _saved(CyanFFI.templateSaveFromBoard(
          tenantId, name, description, _stepsJson(steps), boardId));

  @override
  Future<TemplateSaveResult> templateSaveV2(
      String tenantId, CyanTemplate template) async {
    // The v2 verb answers an error ENVELOPE rather than null, so a null here is
    // only ever the no-op binding — reported as such, never as a rejection the
    // engine did not make.
    final map =
        _decode(CyanFFI.templateSaveV2(tenantId, jsonEncode(template.toJson())));
    if (map == null) {
      return const TemplateSaveResult(error: _engineUnreachable);
    }
    return TemplateSaveResult.fromJson(map);
  }

  /// The shared decode for the two v1 save verbs. Both answer a bare null for
  /// EITHER a refusal or a dead engine — they carry no error channel — so the
  /// result says exactly that rather than picking one.
  TemplateSaveResult _saved(String? json) {
    final map = _decode(json);
    if (map == null) {
      return const TemplateSaveResult(
          error: 'the engine returned no template '
              '(rejected input, or $_engineUnreachable)');
    }
    return TemplateSaveResult.fromJson(map);
  }

  String _stepsJson(List<TemplateStep> steps) =>
      jsonEncode([for (final s in steps) s.toJson()]);

  // ---- step composer --------------------------------------------------------

  @override
  Future<AutocompleteIndex> workflowAutocomplete(
      String boardId, String partial) async {
    // The engine answers this one with an object even when every list is empty
    // (a board with nothing installed), so a null reply is "nobody answered"
    // and says so rather than reading as an empty index.
    final map = _decode(CyanFFI.workflowAutocomplete(boardId, partial));
    if (map == null) return const AutocompleteIndex(error: _engineUnreachable);
    return AutocompleteIndex.fromJson(map);
  }

  // ---- producer review: assignee, media, comments -----------------------------
  //
  // Straight through to the engine: one `cyan_board_*` / `cyan_review_*` call
  // each. The two command verbs take a JSON envelope, so the envelope is built
  // here from the typed arguments and the reply decoded back — nothing is
  // adjudicated on this side.

  @override
  Future<String?> boardReviewAssignee(String boardId) async {
    // The engine answers "" for a board with no assignee, which is a real
    // answer — nobody in particular — and reads the same as a dead binding.
    // Either way there is no assignee to report.
    final user = CyanFFI.boardReviewAssignee(boardId);
    return (user == null || user.isEmpty) ? null : user;
  }

  @override
  Future<bool> boardSetReviewAssignee(String boardId, String user) async =>
      CyanFFI.boardSetReviewAssignee(boardId, user);

  @override
  Future<BoardVideoMedia> boardVideoMedia(String boardId) async {
    // The engine always answers this one with an object — a board with nothing
    // ingested comes back with null paths. So a null reply is NOT "no media",
    // it is "nobody answered", and it says so rather than reporting the board
    // as media-less.
    final map = _decode(CyanFFI.boardVideoMedia(boardId));
    if (map == null) return const BoardVideoMedia(error: _engineUnreachable);
    return BoardVideoMedia.fromJson(map);
  }

  @override
  Future<ReviewCommentResult> reviewAddComment(String boardId, String text,
      {double atSeconds = 0, String author = 'reviewer'}) async {
    final map = _decode(CyanFFI.reviewAddComment(jsonEncode({
      'board_id': boardId,
      'text': text,
      'at_seconds': atSeconds,
      'author': author,
    })));
    if (map == null) {
      return const ReviewCommentResult(
          success: false, error: _engineUnreachable);
    }
    return ReviewCommentResult.fromJson(map);
  }

  @override
  Future<ReviewCommandResult> reviewCommand(
      Map<String, dynamic> command) async {
    final op = command['op'] as String? ?? '';
    final reply = CyanFFI.reviewCommand(jsonEncode(command));
    if (reply == null || reply.isEmpty) {
      return ReviewCommandResult(op: op, error: _engineUnreachable);
    }
    // The op's reply may be an object, an array (`nudges_for`, `loop_runs`) or
    // a bare null (`get` on a key with no state) — all three are the engine's
    // own answers, so the decode is not narrowed to one of them.
    final Object? decoded;
    try {
      decoded = jsonDecode(reply);
    } catch (_) {
      return ReviewCommandResult(op: op, error: 'unreadable reply: $reply');
    }
    return ReviewCommandResult.fromReply(op, decoded);
  }

  @override
  Future<IngestCommandResult> ingestCommand(
      Map<String, dynamic> command) async {
    final op = command['op'] as String? ?? '';
    final reply = CyanFFI.ingestCommand(jsonEncode(command));
    if (reply == null || reply.isEmpty) {
      return IngestCommandResult(op: op, error: _engineUnreachable);
    }
    // The reply is an object for most ops and an array for the list reads
    // (`source_list`, `scan_due`, `runs_for_board`) — both are the engine's own
    // answers, so the decode is not narrowed to one of them.
    final Object? decoded;
    try {
      decoded = jsonDecode(reply);
    } catch (_) {
      return IngestCommandResult(op: op, error: 'unreadable reply: $reply');
    }
    return IngestCommandResult.fromReply(op, decoded);
  }

  @override
  Future<ChangelistCommandResult> changelistCommand(
      Map<String, dynamic> command) async {
    final op = command['op'] as String? ?? '';
    final reply = CyanFFI.changelistCommand(jsonEncode(command));
    if (reply == null || reply.isEmpty) {
      return ChangelistCommandResult(op: op, error: _engineUnreachable);
    }
    // An object for most ops and an array for `conform_plan` — both are the
    // engine's own answers, so the decode is not narrowed to one of them.
    final Object? decoded;
    try {
      decoded = jsonDecode(reply);
    } catch (_) {
      return ChangelistCommandResult(op: op, error: 'unreadable reply: $reply');
    }
    return ChangelistCommandResult.fromReply(op, decoded);
  }

  /// The array twin of [_decode], for the verbs that answer a JSON list. A null
  /// or undecodable reply reads as no rows, matching the other list reads here.
  List<Map<String, dynamic>> _decodeList(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic>) item,
      ];
    } catch (_) {
      return const [];
    }
  }

  // ---- lens command bar -----------------------------------------------------

  @override
  Future<List<PathSuggestion>> autocompletePath(String partial) async => [
        for (final s in _decodeList(CyanFFI.autocompletePath(partial)))
          PathSuggestion.fromJson(s),
      ];

  @override
  Future<LensCommandParse> parseLensCommand(String input) async {
    final map = _decode(CyanFFI.parseLensCommand(input));
    if (map == null) return const LensCommandParse(error: _engineUnreachable);
    return LensCommandParse.fromJson(map);
  }

  // ---- demo seeding ---------------------------------------------------------

  @override
  Future<void> seedDemo() async {
    // Fire-and-forget engine-side (it queues the seed and emits a tree
    // snapshot when it lands), so there is no receipt to decode.
    CyanFFI.seedDemo();
  }

  @override
  Future<SeedPersonasResult> seedPersonas(
      {String tenantId = '', String ownerNodeId = ''}) async {
    final map = _decode(CyanFFI.seedPersonas(tenantId, ownerNodeId));
    if (map == null) {
      return const SeedPersonasResult(error: _engineUnreachable);
    }
    return SeedPersonasResult.fromJson(map);
  }

  // ---- live event pump -----------------------------------------------------

  @override
  Future<String?> pollEvents(String component) async =>
      CyanFFI.pollEvents(component);
}
