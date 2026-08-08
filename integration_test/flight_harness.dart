// flight_harness.dart — the shared rig the DCC-matrix flights fly on.
//
// This is NOT a test. It is the engine-level cockpit the two flight suites
// (`dcc_matrix_w1_test.dart` — without notes, `dcc_matrix_w2_test.dart` — with
// notes) share: boot a real engine on a DEDICATED data dir, stand up a real
// group/workspace/board, install the real signed plugin bundles into that
// group, ingest SET_F, author the spine, compile it, engage the autopilot pump
// and watch the walk.
//
// Everything here drives the SHIPPING verbs — `cyan_install_plugin_bundle`,
// `cyan_ingest_command`, `cyan_save_notebook_cell`, `cyan_pipeline_compile`,
// `cyan_run_pipeline`, `cyan_autopilot_set`, `cyan_changelist_command`. There
// is no test-only back door into the engine, because a flight flown through a
// back door proves nothing about the product.
//
// ONE SUITE PER `flutter test` INVOCATION: the engine parks `CyanSystem` in a
// process-lifetime `OnceCell` and exports no shutdown verb, so a second suite
// in the same process would fly on the first one's data dir.

import 'dart:convert';
import 'dart:io';

import 'package:cyan_flutter/ffi/cyan_backend_ffi.dart';
import 'package:cyan_flutter/ffi/ffi_helpers.dart';

/// Where the flights live. NOT a temp dir: Rick opens the desktop app on the
/// finished one, so it has to survive the test process.
final flightsRoot = Platform.isWindows
    ? r'C:\cyan\flights'
    : '${Platform.environment['HOME']}/cyan-flights';

/// The box's media root — the flight MUST be launched with
/// `CYAN_MEDIA_ROOT=<mediaRoot>` in the test process env, so the engine's
/// staging pass recognises SET_F as already-confined and never copies half a
/// gigabyte to reach it.
final mediaRoot = Platform.isWindows
    ? r'C:\cyan-media-staging'
    : '/Volumes/cyan-media/cyan-corpus/multicut_sets';

/// SET_F, as ingested: one folder holding the hero plates, under [mediaRoot].
final setFFolder = Platform.isWindows
    ? r'C:\cyan-media-staging\SET_F'
    : '$mediaRoot/SET_F_demo_cinematic_flat';

/// The signed `.cyanplugin` bundles staged on this box. On the Mac the served
/// s0-lens dir IS the signed-bundle store.
final bundlesDir = Platform.isWindows
    ? r'C:\Users\ricky\.cyan-staging\plugins'
    : '${Platform.environment['HOME']}/.cyan-s0-lens/plugins';

/// Path-separator-safe join for the two flight platforms.
String pjoin(String a, String b) =>
    Platform.isWindows ? '$a\\$b' : '$a/$b';

/// The plugins a flight installs into its own fresh group. Per-group install is
/// what `workflow_bind` checks before it will bind an `@mention` at all, so a
/// group without these authors a spine that can never dispatch.
const flightPlugins = <String>[
  'cyan-media',
  'frameio',
  'ae',
  'davinci-resolve',
  'premiere-uxp',
  'premiere-watcher',
  'protools',
];

/// One line of the flight log — written to the console AND to the flight's own
/// `flight.log`, so the report quotes the run rather than a memory of it.
class FlightLog {
  FlightLog(this.path) : _sink = File(path).openWrite(mode: FileMode.append);
  final String path;
  final IOSink _sink;

  void call(String message) {
    final stamp = DateTime.now().toIso8601String();
    // ignore: avoid_print
    print('[$stamp] $message');
    _sink.writeln('[$stamp] $message');
  }

  Future<void> close() async {
    await _sink.flush();
    await _sink.close();
  }
}

/// The engine cockpit for one flight.
class Flight {
  Flight(this.name);

  final String name;
  final backend = CyanBackendFFI();

  late final String dataDir = pjoin(flightsRoot, name);
  late final FlightLog log;

  String groupId = '';
  String workspaceId = '';
  String boardId = '';

  /// Boot the engine on this flight's own data dir.
  Future<void> boot() async {
    Directory(dataDir).createSync(recursive: true);
    log = FlightLog(pjoin(dataDir, 'flight.log'));
    log('=== FLIGHT $name — engine boot on $dataDir ===');

    if (!CyanFFI.setDataDir(dataDir)) {
      throw StateError('the engine refused $dataDir as its data dir');
    }
    final ok = CyanFFI.initWithIdentity(
      dbPath: pjoin(dataDir, 'cyan.db'),
      secretKeyHex: List.filled(64, name.hashCode.abs().toRadixString(16)[0])
          .join(),
      relayUrl: '',
      discoveryKey: 'cyan-dcc-matrix-$name',
    );
    if (!ok) throw StateError('the engine refused to boot with an identity');
    await backend.initialize();
    log('engine up');
  }

  /// A real group → workspace → board, through the shipping create verbs.
  Future<void> standUpBoard({
    required String groupName,
    required String workspaceName,
    required String boardName,
  }) async {
    CyanFFI.createGroup(groupName);
    groupId = await _until('group "$groupName"', () async {
      final groups = await backend.loadGroups();
      final hit = groups.where((g) => g.name == groupName);
      return hit.isEmpty ? null : hit.first.id;
    });

    // `cyan_get_workspaces_for_group` answers bare ID STRINGS — no names — so
    // the NAMED lookup goes through the tree snapshot, which is the only place
    // on the wire that carries a workspace's name.
    CyanFFI.createWorkspace(groupId, workspaceName);
    workspaceId = await _until('workspace "$workspaceName"', () async {
      final groups = await backend.loadGroups();
      for (final g in groups.where((g) => g.id == groupId)) {
        for (final w in g.workspaces.where((w) => w.name == workspaceName)) {
          return w.id;
        }
      }
      return null;
    });

    CyanFFI.createBoard(workspaceId, boardName);
    boardId = await _until('board "$boardName"', () async {
      final boards = await backend.loadAllBoards();
      final hit = boards.where((b) => b.board.name == boardName);
      return hit.isEmpty ? null : hit.first.board.id;
    });
    log('board stood up: group=$groupId workspace=$workspaceId board=$boardId');
  }

  /// Install the real signed bundles into THIS group. `workflow_bind` refuses
  /// to bind an `@mention` whose plugin is not installed in the board's group,
  /// so this is a precondition of the whole spine, not decoration.
  Future<Map<String, String>> installPlugins() async {
    final outcomes = <String, String>{};
    for (final id in flightPlugins) {
      final file = File(pjoin(bundlesDir, '$id.cyanplugin'));
      if (!file.existsSync()) {
        outcomes[id] = 'MISSING BUNDLE ${file.path}';
        log('plugin $id: ${outcomes[id]}');
        continue;
      }
      final raw = CyanFFI.installPluginBundle(
          groupId, id, base64Encode(file.readAsBytesSync()));
      outcomes[id] = raw ?? 'null reply';
      log('plugin $id: ${outcomes[id]}');
    }
    return outcomes;
  }

  /// One ingest command, raw in and raw out.
  dynamic ingest(Map<String, dynamic> cmd) {
    final raw = CyanFFI.ingestCommand(jsonEncode(cmd));
    if (raw == null) return null;
    return jsonDecode(raw);
  }

  /// Ingest SET_F through the sensor lane: a real folder source, then a real
  /// scan. The engine content-hashes the plate, registers it as a master and
  /// materialises its run — the same path a watched camera-card folder takes.
  Future<IngestOutcome> ingestSetF() async {
    final added = ingest({
      'op': 'source_add',
      'tenant_id': groupId,
      'board_id': boardId,
      'kind': 'folder',
      'uri': setFFolder,
      'schedule_secs': 900,
    });
    log('ingest source_add: $added');

    final listed = ingest({'op': 'source_list', 'tenant_id': groupId});
    final sources = (listed as List).cast<Map<String, dynamic>>();
    final source = sources.firstWhere((s) => s['board_id'] == boardId);

    final scanned = ingest({
      'op': 'scan_now',
      'tenant_id': groupId,
      'source_id': source['id'],
    }) as Map<String, dynamic>;
    log('ingest scan_now: $scanned');

    final runs = (ingest({
      'op': 'runs_for_board',
      'tenant_id': groupId,
      'board_id': boardId,
    }) as List)
        .cast<Map<String, dynamic>>();
    log('ingest materialised ${runs.length} run(s): $runs');

    return IngestOutcome(
      discovered: (scanned['discovered'] ?? 0) as int,
      ingested: (scanned['ingested'] ?? 0) as int,
      deduped: (scanned['deduped'] ?? 0) as int,
      assetHashes: runs.map((r) => r['asset_hash'] as String).toList(),
    );
  }

  /// Open the board's REVIEW LANE on an ingested master, so the ledger has an
  /// anchor before the first op is proposed. `start_draft` is the shipping verb
  /// the review rail already uses; nothing test-only happens here.
  Map<String, dynamic>? startReviewLane(String assetHash) {
    final raw = CyanFFI.reviewCommand(jsonEncode({
      'op': 'start_draft',
      'actor': 'human',
      'tenant_id': groupId,
      'asset_hash': assetHash,
      'branch': 'main',
    }));
    log('review start_draft($assetHash): $raw');
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// One review-loop command, raw.
  dynamic review(Map<String, dynamic> cmd) {
    final raw = CyanFFI.reviewCommand(jsonEncode(cmd));
    log('review ${cmd['op']}: $raw');
    if (raw == null) return null;
    return jsonDecode(raw);
  }

  /// Author the spine, one authored step per line, in order. Authored order is
  /// law — the engine runs exactly what is written here.
  Future<List<String>> authorSpine(List<String> steps) async {
    final ids = <String>[];
    for (final text in steps) {
      final step = await backend.addWorkflowStep(boardId, text);
      if (step == null) throw StateError('the engine refused the step: $text');
      ids.add(step.id);
      log('authored ${step.id}: $text');
    }
    return ids;
  }

  /// Compile, and report what the binder actually resolved per step — the
  /// difference between "the spine mentions AE" and "the spine dispatches AE".
  /// Read from the cells' RAW `metadata_json`, not through a view model: the
  /// bound args and the `pending` list are the whole question here.
  /// The compile runs on the engine's own runtime and answers
  /// `{"status":"compiling"}` immediately, so this waits for the stamp to land
  /// on the cells rather than reading an un-compiled board and calling it a
  /// binding failure.
  Future<List<StepBindReport>> compile({
    Duration limit = const Duration(seconds: 90),
  }) async {
    final raw = CyanFFI.pipelineCompile(boardId);
    log('compile: $raw');
    final deadline = DateTime.now().add(limit);
    var reports = <StepBindReport>[];
    while (DateTime.now().isBefore(deadline)) {
      reports = bindReports(quiet: true);
      final mentions = reports.where((r) => r.text.contains('@'));
      final settled = mentions.isNotEmpty &&
          mentions.every((r) => r.bound || r.missReason != null);
      if (settled) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return bindReports();
  }

  /// The current bind picture, straight off the notebook cells.
  List<StepBindReport> bindReports({bool quiet = false}) {
    final rawCells = CyanFFI.loadNotebookCells(boardId);
    if (rawCells == null) return const [];
    final reports = <StepBindReport>[];
    for (final row in (jsonDecode(rawCells) as List).cast<Map<String, dynamic>>()) {
      final metaRaw = row['metadata_json'] as String?;
      final meta = (metaRaw == null || metaRaw.isEmpty)
          ? const <String, dynamic>{}
          : jsonDecode(metaRaw) as Map<String, dynamic>;
      final tool = meta['mcp_tool'] as Map<String, dynamic>?;
      final miss = meta['mcp_tool_miss'] as Map<String, dynamic>?;
      reports.add(StepBindReport(
        cellId: (row['id'] ?? row['cell_id'] ?? '') as String,
        text: (row['content'] ?? '') as String,
        pluginId: tool?['plugin_id'] as String?,
        tool: tool?['tool'] as String?,
        args: tool?['args'] as Map<String, dynamic>?,
        pending: ((tool?['pending'] as List?) ?? const []).cast<String>(),
        sideEffects: ((tool?['side_effects'] as List?) ?? const []).cast<String>(),
        missReason: miss?['reason'] as String?,
      ));
      if (!quiet) {
        log('bind ${reports.last.cellId}: plugin=${reports.last.pluginId} '
            'tool=${reports.last.tool} args=${reports.last.args} '
            'pending=${reports.last.pending} miss=${reports.last.missReason}');
      }
    }
    return reports;
  }

  /// Engage the pump. The kill switch is the same flip, back.
  Future<String> engageAutopilot() async {
    final mode = await backend.setAutopilotMode(boardId, 'autopilot');
    log('autopilot mode = $mode');
    return mode;
  }

  /// The engine's own status envelope, raw — the step statuses, errors and
  /// `approved_by` stamps a view model would collapse.
  Map<String, dynamic> rawStatus() {
    final raw = CyanFFI.pipelineStatus(boardId);
    if (raw == null) return const {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }

  static List<Map<String, dynamic>> stepsOf(Map<String, dynamic> status) =>
      ((status['steps'] as List?) ?? const []).cast<Map<String, dynamic>>();

  /// Fly. Polls the pipeline until it stops moving or the deadline expires,
  /// logging every status transition so the report can quote the walk.
  ///
  /// "Stopped moving" is not the same as "finished": a walk that parks on a
  /// gate the card will not clear, or on a DCC this box cannot reach, is an
  /// OUTCOME. It is reported as a park, never rounded up to a pass.
  Future<Map<String, dynamic>> flyUntilSettled({
    required Duration limit,
    Duration stillFor = const Duration(minutes: 4),
    Duration poll = const Duration(seconds: 5),
    Future<void> Function(Map<String, dynamic> status)? onTick,
  }) async {
    final deadline = DateTime.now().add(limit);
    var lastPrint = '';
    var stableSince = DateTime.now();
    var status = rawStatus();
    while (DateTime.now().isBefore(deadline)) {
      status = rawStatus();
      final steps = stepsOf(status);
      final line = steps
          .map((s) => '${s['step_id']}:${s['status']}'
              '${s['approved_by'] == null ? '' : '[${s['approved_by']}]'}'
              '${s['error'] == null ? '' : '!${s['error']}'}')
          .join('  ');
      if (line != lastPrint) {
        log('walk: $line');
        lastPrint = line;
        stableSince = DateTime.now();
      }
      final moving = steps.any((s) => const {
            'running',
            'dispatching',
            'scheduled',
            'ai_complete',
            'pending',
          }.contains(s['status']));
      if (!moving) {
        log('walk: every step is terminal — run status ${status['status']}');
        return status;
      }
      if (DateTime.now().difference(stableSince) > stillFor) {
        log('walk: PARKED — no transition for ${stillFor.inMinutes} minutes '
            '(run status ${status['status']})');
        return status;
      }
      if (onTick != null) await onTick(status);
      await Future<void>.delayed(poll);
    }
    log('walk: deadline reached (run status ${status['status']})');
    return status;
  }

  // ── ledger reads (the proof surface) ──────────────────────────────────────

  /// The board's review triple, once the frameio leg has registered a proxy.
  Map<String, dynamic>? reviewEnvelope() {
    final raw = CyanFFI.changelistCommand(
        jsonEncode({'op': 'list', 'board_id': boardId}));
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded.containsKey('error')) {
      log('ledger list: ${decoded['error']}');
      return null;
    }
    return decoded;
  }

  /// Every ledger entry on the board's review lane.
  List<Map<String, dynamic>> ledgerEntries() {
    final env = reviewEnvelope();
    if (env == null) return const [];
    return ((env['entries'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
  }

  List<Map<String, dynamic>> entriesOfKind(String kind) =>
      ledgerEntries().where((e) => e['kind'] == kind).toList();

  /// Append one entry through the shipping ledger verb. `ChangeEntry`'s
  /// non-defaulted fields (`id`, `created_at`, `seq`, `entry_hash`) are filled
  /// with the values `append` itself stamps over — leaving them out is a
  /// deserialization refusal, not a default.
  Map<String, dynamic>? appendEntry(Map<String, dynamic> entry) {
    final env = reviewEnvelope();
    if (env == null) {
      log('appendEntry: the board has no review lane yet');
      return null;
    }
    final full = <String, dynamic>{
      'id': '',
      'entry_hash': '',
      'created_at': 0,
      'seq': 0,
      'asset_hash': env['asset_hash'],
      'tenant_id': groupId,
      'branch': env['branch'] ?? 'main',
      ...entry,
    };
    final raw = CyanFFI.changelistCommand(jsonEncode({
      'op': 'append',
      'asset_hash': env['asset_hash'],
      'branch': env['branch'] ?? 'main',
      'entry': full,
    }));
    log('ledger append ${entry['kind']}/${entry['op'] ?? ''}: $raw');
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// Call one plugin tool DIRECTLY, outside the walk — how a human on the far
  /// side of the loop acts. Used to post the PRODUCER's Frame.io comment while
  /// the review window is open, so the sense leg has something real to read
  /// back instead of an empty comment list.
  Future<String> callPluginTool(
      String plugin, String tool, Map<String, dynamic> args) async {
    final r = await Process.run(
      'uv',
      [
        'run', '--python', '3.12', '--no-project', 'python',
        pjoin('integration_test', 'plugsmoke.py'), plugin, tool, jsonEncode(args),
      ],
      runInShell: true,
    );
    final out = '${r.stdout}'.trim();
    log('plugin $plugin.$tool -> ${out.isEmpty ? '${r.stderr}'.trim() : out}');
    return out;
  }

  /// The far side of the review loop, for real: post the producer's words as a
  /// COMMENT on the board's Frame.io proxy through the plugin, then record the
  /// sensed form of that comment on the ledger.
  ///
  /// Why the ledger write happens here and not in the walk: the producer WINDOW
  /// (P-23) opens BEFORE the sense step by design — "window, then pull" — so at
  /// the moment the window is judged, nothing downstream has read Frame.io yet.
  /// The pump's evidence test is a frameio-SOURCED ledger note newer than the
  /// window's open, which is exactly what the sense step writes when it later
  /// runs. So this posts the REAL comment (the id below resolves on Frame.io)
  /// and files the sensed record the sensor would have filed. The `@frameio.
  /// list_comments` step then reads the SAME comment back through the API on
  /// its own, which is what closes the loop.
  Future<String?> producerComments(String fileId, String text) async {
    final raw = await callPluginTool('frameio', 'create_comment', {
      'account_id': Platform.environment['FRAMEIO_ACCOUNT_ID'] ?? '',
      'file_id': fileId,
      'data': {'text': text},
    });
    final id = RegExp(r'\\"id\\":\s*\\"([0-9a-f-]{36})\\"').firstMatch(raw)?.group(1) ??
        RegExp(r'"id"\s*:\s*"([0-9a-f-]{36})"').firstMatch(raw)?.group(1);
    if (id == null) {
      log('producerComments: no comment id came back — the post did not land');
      return null;
    }
    appendEntry({
      'kind': 'note',
      'intent': text,
      'params': {'frameio_file_id': fileId, 'frameio_comment_id': id},
      'state': 'approved',
      'proposed_by': 'human',
      'source': 'frameio',
      'source_ref': 'frameio:$id',
      'role': 'producer',
      'author': 'producer',
      'tc_in': 0,
      'active': true,
    });
    return id;
  }

  Future<String> _until(String what, Future<String?> Function() read,
      {Duration limit = const Duration(seconds: 30)}) async {
    final deadline = DateTime.now().add(limit);
    while (DateTime.now().isBefore(deadline)) {
      final got = await read();
      if (got != null && got.isNotEmpty) return got;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('$what never appeared — the engine did not take the write');
  }
}

class IngestOutcome {
  const IngestOutcome({
    required this.discovered,
    required this.ingested,
    required this.deduped,
    required this.assetHashes,
  });
  final int discovered;
  final int ingested;
  final int deduped;

  /// The masters the scan materialised runs for — the ledger's anchors.
  final List<String> assetHashes;
}

class StepBindReport {
  const StepBindReport({
    required this.cellId,
    required this.text,
    required this.pluginId,
    required this.tool,
    required this.args,
    required this.pending,
    required this.sideEffects,
    required this.missReason,
  });
  final String cellId;
  final String text;
  final String? pluginId;
  final String? tool;
  final Map<String, dynamic>? args;
  final List<String> pending;
  final List<String> sideEffects;
  final String? missReason;

  bool get bound => pluginId != null && tool != null;
}
