// lens/lens_api.dart
//
// The SECOND seam. PHASE-2 D4: `CyanBackend` (FFI) and `LensApi` (HTTP) stay
// two seams, each with a Fake, and no view talks to either directly — providers
// only.
//
// This is the port of Swift's `LensConsoleClient` protocol plus the
// lens-cloud reads the Marketplace and Lens AI faces need
// (`CyanLensCloudService`). One transport, one bearer, one place the base URL
// is resolved.
//
// WHY A SEAM AND NOT A CLIENT: the four faces that hang off this lane — Ops
// Runs / Cost / Efficiency, Marketplace, Lens AI — were all recorded in
// PARITY_TRACKER as "blocked: no engine verb". They are not engine work at
// all; they are HTTP, and the engine will never grow a verb for them. The seam
// is what lets the faces be built, tested and reviewed on a box with no lens
// running: Tier-1 injects [FakeLensApi], and the live read is Tier-2 against a
// running lens (which this box does not have — see the contract test).
//
// SCOPED, NEVER TRUSTED: the lens enforces tenant scope from the verified
// bearer. This client only attaches the token and relays board/status/limit.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lens_models.dart';

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

/// The one place the lens base URL and bearer are resolved.
///
/// The macOS app reads both off `UserDefaults` (`cyan_lens_url`, plus the
/// installed SSO session token). This box has neither, so the port reads the
/// environment the launcher sets — the SAME `CYAN_LENS_URL` the marketplace
/// bundle fetcher already uses, so the two legs of an install can never point
/// at different lenses.
class LensConfig {
  static const String defaultBaseUrl = 'http://localhost:8080';

  /// The dev bearer `LensConsoleHTTPClient.effectiveToken` falls back to when
  /// no SSO session is installed. Without it, a persona-picker sign-in sent NO
  /// bearer and every `/runs` fetch 403'd into a false "0 runs" — found live on
  /// the demo island, 2026-07-21, and worth not re-finding.
  static const String devToken = 'seedtok';

  final String baseUrl;

  /// The bearer source. A function, not a string, so a session token that
  /// arrives after construction is still picked up — and so tests need no
  /// keychain.
  final String? Function() tokenProvider;

  /// The tenant's group id, needed by the lens-cloud reads that scope by path
  /// segment (`/nudges/{group}`, `/asks/{group}`, `/decisions/{group}`).
  final String groupId;

  const LensConfig({
    required this.baseUrl,
    required this.tokenProvider,
    this.groupId = 'default',
  });

  /// Resolve from the process environment. Empty/unset values fall back the way
  /// the macOS defaults do.
  factory LensConfig.fromEnvironment([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    String read(String key, String fallback) {
      final v = e[key]?.trim() ?? '';
      return v.isEmpty ? fallback : v;
    }

    final token = read('CYAN_LENS_TOKEN', devToken);
    return LensConfig(
      baseUrl: read('CYAN_LENS_URL', defaultBaseUrl),
      tokenProvider: () => token,
      groupId: read('CYAN_GROUP_ID', 'default'),
    );
  }

  /// The bearer for a request: the installed session when present, else the dev
  /// token. Mirrors `LensConsoleHTTPClient.effectiveToken`.
  String get effectiveToken {
    final t = tokenProvider();
    return (t == null || t.isEmpty) ? devToken : t;
  }
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Something the lens lane could not deliver. Carries the plain-language line a
/// face shows. NEVER carries the bearer.
class LensApiException implements Exception {
  final String message;

  /// The HTTP status when there was one — null for a transport failure.
  final int? statusCode;

  const LensApiException(this.message, {this.statusCode});

  /// The lens is not reachable at all (offline box, no tunnel, wrong port).
  const LensApiException.unreachable(String detail)
      : message = detail,
        statusCode = null;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// The seam
// ---------------------------------------------------------------------------

/// The ONE entry the Ops console, Marketplace and Lens AI faces read and
/// command through.
abstract class LensApi {
  // ---- Ops console (mirror `LensConsoleClient`) ----------------------------

  /// The lane feed (`GET /runs`). [board] null → TENANT-WIDE (the `board` query
  /// param is omitted entirely); non-null → that board only. [status] narrows
  /// to one lane's statuses.
  Future<RunBoardFeed> runs({String? board, RunStatusValue? status, int limit});

  /// One run's per-step drill-down trace (`GET /runs/{id}`).
  Future<RunTrace> run(String id);

  /// Re-enqueue a Failed run (`POST /runs/{id}/retry`) → the re-queued summary.
  Future<RunSummary> retry(String id);

  /// Clear an AwaitingApproval run's gate (`POST /runs/{id}/approve`). [step] is
  /// the gate step id when known; null lets the lens resolve the parked gate.
  Future<RunSummary> approve(String id, {String? step});

  /// Halt an AwaitingApproval run at its gate (`POST /runs/{id}/reject`) — its
  /// OWN route.
  Future<RunSummary> reject(String id, {String? step});

  // ---- Marketplace (mirror `CyanLensCloudService.browseMarketplace`) -------

  /// `GET /marketplace/browse?q=&aisle=&publisher=&limit=` — the tenant-scoped
  /// storefront. Install actions are NOT an open endpoint; they flow through
  /// the RBAC-gated server-side install, which the UI only REFLECTS.
  Future<List<LensPluginCardWire>> browseMarketplace(StorefrontQuery query);

  // ---- Lens AI (mirror the nudges / asks / decisions reads) ----------------

  /// `GET /nudges/{group}` — the proactive focus report.
  Future<LensNudgeReport> nudges();

  /// `GET /asks/{group}?limit=` — the open-question rows.
  Future<List<LensAskRow>> asks({int limit});

  /// `GET /decisions/{group}?limit=` — the recorded-decision rows.
  Future<List<LensDecisionRow>> decisions({int limit});

  /// `GET /health` — is the lens actually up, and which leg is down.
  Future<LensHealth> health();

  /// `PATCH /asks/{id}/answer`.
  Future<void> answerAsk(String askId,
      {required String answer,
      required String answererId,
      required String answererName});

  /// `PATCH /asks/{id}/dismiss`.
  Future<void> dismissAsk(String askId);

  /// `POST /decisions/{id}/react`.
  Future<void> reactToDecision(String decisionId,
      {required String reaction,
      required String nodeId,
      required String displayName});

  /// `PATCH /nodes/{id}/resolve-blocker` — what a nudge's Resolve does.
  Future<void> resolveBlocker(String nodeId);

  // ---- notes structuring (A4 §1b) -------------------------------------------

  /// Turn freeform text into TYPED note proposals.
  ///
  /// Nothing is persisted by this call: auto-accept is OFF, every proposal is a
  /// suggestion the human confirms, and confirming writes through the ENGINE's
  /// own note door so its RBAC and payload validation still run. Spans the lane
  /// refused come back in `rejected` rather than being dropped silently.
  Future<NoteStructureResult> structureNote({
    required String boardId,
    required String text,
    NotesLane lane = NotesLane.note,
  });

  // ---- notes as intent: brief -> steps, notes -> steps ----------------------

  /// Draft structured workflow steps from a plain-English [brief].
  ///
  /// [constitutionJson] is the board's EFFECTIVE constitution as
  /// `constitutionEffective` returns it. Forwarding it is what switches
  /// server-side distillation on, so the draft steers by the house rules and
  /// splices hard constraints verbatim — the bridge between the with-notes and
  /// without-notes paths.
  Future<LensDraft> generateSteps({
    required String boardId,
    required String brief,
    String? constitutionJson,
  });

  /// Turn the board's NOTES into bound steps, keeping the provenance receipts
  /// that say which note or rule shaped each one.
  Future<LensTranspiled> transpileNotes({
    required String boardId,
    required List<String> notes,
    String? constitutionJson,
  });
}

// ---------------------------------------------------------------------------
// Marketplace + Lens AI wire shapes (the ones that live only on this lane)
// ---------------------------------------------------------------------------

/// The browse/search filter the storefront sends
/// (`GET /marketplace/browse?q=&aisle=&publisher=&limit=`).
class StorefrontQuery {
  final String? text;

  /// The aisle (stage) label, as the lens's controlled vocabulary spells it.
  final String? aisle;
  final String? publisher;
  final int limit;

  const StorefrontQuery({
    this.text,
    this.aisle,
    this.publisher,
    this.limit = 50,
  });
}

/// One curated/forge plugin card AS THE LENS SERVES IT.
///
/// This is deliberately NOT the commercial card the storefront draws. The app
/// once decoded `data` as a bare list of commercial cards, but the lens wraps
/// them in `{cards:[…]}` AND its card shape is the forge/plugin shape
/// (plugin_id / description / tool_summary / trust / source). That mismatch
/// threw the whole decode, and the storefront reported "Lens is offline" over a
/// perfectly live lens. Decode the REAL shape here; the mapping to the card the
/// face draws is a separate, testable step.
class LensPluginCardWire {
  final String pluginId;
  final String? name;
  final String? description;
  final List<String> toolSummary;
  final String? trust;
  final String? source;

  /// The server's DELIBERATE curation flag (`CYAN_FEATURED_PLUGINS`).
  final bool? featured;

  /// The curated tier's TRUE stage/aisle; null for a public card.
  final String? stage;

  const LensPluginCardWire({
    required this.pluginId,
    this.name,
    this.description,
    this.toolSummary = const [],
    this.trust,
    this.source,
    this.featured,
    this.stage,
  });

  factory LensPluginCardWire.fromJson(Map<String, dynamic> j) {
    final id = j['plugin_id'];
    if (id is! String || id.isEmpty) {
      throw LensDecodeException('a marketplace card carries no plugin_id: $j');
    }
    return LensPluginCardWire(
      pluginId: id,
      name: j['name'] as String?,
      description: j['description'] as String?,
      toolSummary: [
        for (final t in (j['tool_summary'] as List<dynamic>? ?? const []))
          if (t is String) t
      ],
      trust: j['trust'] as String?,
      source: j['source'] as String?,
      featured: j['featured'] as bool?,
      stage: j['stage'] as String?,
    );
  }

  /// `trust == "trusted"` is the ONLY trusted value — anything else, including
  /// a missing field, is untrusted. The client never widens a trust the server
  /// owns.
  bool get isTrusted => trust == 'trusted';

  /// A public-registry entry (a raw repo id) vs a curated/forged one.
  bool get isPublicRegistry => source == 'public';
}

/// One nudge in the report.
class LensNudgeWire {
  /// `stale_ask` | `stale_blocker` | `unimplemented_decision` | …
  final String nudgeType;
  final String? question;
  final String? externalId;
  final String? decision;
  final int? ageHours;
  final int? staleDays;
  final String? sourceNodeId;
  final String? askId;
  final String? decisionId;
  final String? nodeId;

  const LensNudgeWire({
    this.nudgeType = '',
    this.question,
    this.externalId,
    this.decision,
    this.ageHours,
    this.staleDays,
    this.sourceNodeId,
    this.askId,
    this.decisionId,
    this.nodeId,
  });

  factory LensNudgeWire.fromJson(Map<String, dynamic> j) => LensNudgeWire(
        nudgeType: j['nudge_type'] as String? ?? '',
        question: j['question'] as String?,
        externalId: j['external_id'] as String?,
        decision: j['decision'] as String?,
        ageHours:
            j['age_hours'] is num ? (j['age_hours'] as num).round() : null,
        staleDays:
            j['stale_days'] is num ? (j['stale_days'] as num).round() : null,
        sourceNodeId: j['source_node_id'] as String?,
        askId: j['ask_id'] as String?,
        decisionId: j['decision_id'] as String?,
        nodeId: j['node_id'] as String?,
      );

  /// The identity the face keys a row by. The Swift falls back to a fresh UUID;
  /// this falls back to the type + detail, because a row whose id changes on
  /// every poll cannot be resolved, and an unresolvable Resolve button is worse
  /// than a missing one.
  String get id =>
      askId ?? decisionId ?? nodeId ?? sourceNodeId ?? '$nudgeType:$detail';

  String get title => switch (nudgeType) {
        'stale_ask' => 'Stale Question',
        'stale_blocker' => 'Stale Blocker',
        'unimplemented_decision' => 'Unimplemented Decision',
        _ => 'Nudge',
      };

  String get detail => question ?? decision ?? externalId ?? '';

  String get ageText {
    final h = ageHours;
    if (h != null) return h < 24 ? '${h}h' : '${h ~/ 24}d';
    final d = staleDays;
    if (d != null) return '${d}d';
    return '';
  }
}

/// `GET /nudges/{group}` — the report.
class LensNudgeReport {
  final String groupId;
  final int generatedAt;
  final List<LensNudgeWire> nudges;
  final int staleAsks;
  final int staleBlockers;
  final int unimplementedDecisions;

  const LensNudgeReport({
    this.groupId = '',
    this.generatedAt = 0,
    this.nudges = const [],
    this.staleAsks = 0,
    this.staleBlockers = 0,
    this.unimplementedDecisions = 0,
  });

  static const LensNudgeReport empty = LensNudgeReport();

  factory LensNudgeReport.fromJson(Map<String, dynamic> j) {
    final s = j['summary'] as Map<String, dynamic>? ?? const {};
    int count(String k) => s[k] is num ? (s[k] as num).round() : 0;
    return LensNudgeReport(
      groupId: j['group_id'] as String? ?? '',
      generatedAt:
          j['generated_at'] is num ? (j['generated_at'] as num).round() : 0,
      nudges: [
        for (final n in (j['nudges'] as List<dynamic>? ?? const []))
          if (n is Map<String, dynamic>) LensNudgeWire.fromJson(n)
      ],
      staleAsks: count('stale_asks'),
      staleBlockers: count('stale_blockers'),
      unimplementedDecisions: count('unimplemented_decisions'),
    );
  }

  int get totalCount => staleAsks + staleBlockers + unimplementedDecisions;
}

/// One `GET /asks/{group}` row.
class LensAskRow {
  final String id;
  final String sourceNodeId;
  final String groupId;
  final String content;
  final String askerName;
  final String? assigneeName;
  final String? status;
  final String? answerSummary;
  final String? answeredByName;
  final int? answeredAt;
  final int createdAt;

  const LensAskRow({
    required this.id,
    this.sourceNodeId = '',
    this.groupId = '',
    this.content = '',
    this.askerName = '',
    this.assigneeName,
    this.status,
    this.answerSummary,
    this.answeredByName,
    this.answeredAt,
    this.createdAt = 0,
  });

  factory LensAskRow.fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String || id.isEmpty) {
      throw LensDecodeException('an ask row carries no id: $j');
    }
    return LensAskRow(
      id: id,
      sourceNodeId: j['source_node_id'] as String? ?? '',
      groupId: j['group_id'] as String? ?? '',
      content: j['content'] as String? ?? '',
      askerName: j['asker_name'] as String? ?? '',
      assigneeName: j['assignee_name'] as String?,
      status: j['status'] as String?,
      answerSummary: j['answer_summary'] as String?,
      answeredByName: j['answered_by_name'] as String?,
      answeredAt:
          j['answered_at'] is num ? (j['answered_at'] as num).round() : null,
      createdAt: j['created_at'] is num ? (j['created_at'] as num).round() : 0,
    );
  }

  /// "3h ago" / "2d ago", against [now] (seconds). The clock is a parameter so
  /// a golden and a contract test can pin the string instead of racing it.
  String ageText(int nowSeconds) {
    final hours = (nowSeconds - createdAt) ~/ 3600;
    if (hours < 24) return '${hours}h ago';
    return '${hours ~/ 24}d ago';
  }
}

/// One `GET /decisions/{group}` row.
class LensDecisionRow {
  final String id;
  final String sourceNodeId;
  final String groupId;
  final String content;
  final String deciderName;
  final String? rationale;
  final int createdAt;

  const LensDecisionRow({
    required this.id,
    this.sourceNodeId = '',
    this.groupId = '',
    this.content = '',
    this.deciderName = '',
    this.rationale,
    this.createdAt = 0,
  });

  factory LensDecisionRow.fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String || id.isEmpty) {
      throw LensDecodeException('a decision row carries no id: $j');
    }
    return LensDecisionRow(
      id: id,
      sourceNodeId: j['source_node_id'] as String? ?? '',
      groupId: j['group_id'] as String? ?? '',
      content: j['content'] as String? ?? '',
      deciderName: j['decider_name'] as String? ?? '',
      rationale: j['rationale'] as String?,
      createdAt: j['created_at'] is num ? (j['created_at'] as num).round() : 0,
    );
  }

  String ageText(int nowSeconds) {
    final hours = (nowSeconds - createdAt) ~/ 3600;
    if (hours < 24) return '${hours}h ago';
    return '${hours ~/ 24}d ago';
  }
}

/// `GET /health` — TOLERANT on purpose. The live lens's health `data` dropped
/// `iggy` and added `commit`; a STRICT decode threw, `isAvailable` went false,
/// and Lens AI showed "Disconnected" against a perfectly live lens. Every field
/// is optional; a missing one is null, never a parse error.
class LensHealth {
  final bool? postgres;
  final bool? iggy;
  final bool? vllm;
  final bool? lens;
  final String? commit;

  const LensHealth({
    this.postgres,
    this.iggy,
    this.vllm,
    this.lens,
    this.commit,
  });

  static const LensHealth down = LensHealth();

  factory LensHealth.fromJson(Map<String, dynamic> j) => LensHealth(
        postgres: j['postgres'] as bool?,
        iggy: j['iggy'] as bool?,
        vllm: j['vllm'] as bool?,
        lens: j['lens'] as bool?,
        commit: j['commit'] as String?,
      );

  bool get isHealthy => (postgres ?? false) && (lens ?? false);

  String get statusText {
    if (isHealthy) return 'Connected';
    final issues = <String>[];
    if (!(postgres ?? false)) issues.add('DB');
    if (!(vllm ?? false)) issues.add('LLM');
    if (!(iggy ?? true)) issues.add('Queue');
    return issues.isEmpty ? 'Disconnected' : '${issues.join(", ")} down';
  }
}

// ---------------------------------------------------------------------------
// The live (Tier-2) HTTP client
// ---------------------------------------------------------------------------

/// Binds the seam to a running cyan-lens.
///
/// Built on `dart:io`'s `HttpClient` with an injectable factory, exactly like
/// [LensPluginBundleFetcher] — the two legs of a marketplace install then share
/// a transport shape and a base URL, and a test can drive either with no
/// package dependency and no network.
class LensApiHttp implements LensApi {
  /// A COLD call (tunnel first-connect + a just-woken vLLM/Postgres) routinely
  /// takes 2–4s end to end; the old 4s budget tripped the very FIRST fetch and
  /// blanked the console until a later warm tick. 12s is generous for cold and
  /// still bounded.
  static const Duration defaultTimeout = Duration(seconds: 12);

  final LensConfig config;
  final Duration timeout;
  final HttpClient Function() _newClient;

  LensApiHttp({
    LensConfig? config,
    this.timeout = defaultTimeout,
    HttpClient Function()? newClient,
  })  : config = config ?? LensConfig.fromEnvironment(),
        _newClient = newClient ?? HttpClient.new;

  String get _base => config.baseUrl;

  // ---- Ops console --------------------------------------------------------

  @override
  Future<RunBoardFeed> runs(
      {String? board, RunStatusValue? status, int limit = 50}) async {
    final params = <String, String>{'limit': '$limit'};
    // Tenant-wide = omit `board` ENTIRELY; per-board = attach it. An empty
    // string is not the same request.
    if (board != null && board.isNotEmpty) params['board'] = board;
    if (status != null && status != RunStatusValue.unknown) {
      params['status'] = status.wire;
    }
    final body = await _send('GET', _uri('/api/v1/runs', params));
    return RunBoardFeed.fromJson(_asMap(body, 'the run feed'));
  }

  @override
  Future<RunTrace> run(String id) async {
    final body = await _send('GET', _uri('/api/v1/runs/${_seg(id)}'));
    return RunTrace.fromJson(_asMap(body, 'the run trace'));
  }

  @override
  Future<RunSummary> retry(String id) async {
    final body = await _send('POST', _uri('/api/v1/runs/${_seg(id)}/retry'));
    final reply = RetryReply.fromJson(_asMap(body, 'the retry reply'));
    if (!reply.success) throw const LensApiException('retry rejected');
    return reply.run;
  }

  @override
  Future<RunSummary> approve(String id, {String? step}) =>
      _gate(id, ApprovalDecision.approve, step, 'approval rejected');

  @override
  Future<RunSummary> reject(String id, {String? step}) =>
      _gate(id, ApprovalDecision.reject, step, 'reject rejected');

  /// The shared approve/reject POST. The verb is the ROUTE; `step_id` rides
  /// only when known (else the lens resolves the parked gate itself).
  Future<RunSummary> _gate(String id, ApprovalDecision decision, String? step,
      String failMessage) async {
    final payload = step == null ? const <String, String>{} : {'step_id': step};
    final body = await _send(
      'POST',
      _uri('/api/v1/runs/${_seg(id)}/${decision.wire}'),
      jsonBody: payload,
    );
    final reply = ApproveReply.fromJson(_asMap(body, 'the gate reply'));
    if (!reply.success) throw LensApiException(failMessage);
    return reply.run;
  }

  // ---- Marketplace --------------------------------------------------------

  @override
  Future<List<LensPluginCardWire>> browseMarketplace(
      StorefrontQuery query) async {
    final params = <String, String>{'limit': '${query.limit}'};
    final text = query.text;
    if (text != null && text.isNotEmpty) params['q'] = text;
    final aisle = query.aisle;
    if (aisle != null && aisle.isNotEmpty) params['aisle'] = aisle;
    final publisher = query.publisher;
    if (publisher != null && publisher.isNotEmpty) {
      params['publisher'] = publisher;
    }
    final body = await _send('GET', _uri('/api/v1/marketplace/browse', params),
        envelope: true);
    final browse = _asMap(body, 'the marketplace browse');
    return [
      for (final c in (browse['cards'] as List<dynamic>? ?? const []))
        if (c is Map<String, dynamic>) LensPluginCardWire.fromJson(c)
    ];
  }

  // ---- Lens AI ------------------------------------------------------------

  @override
  Future<LensNudgeReport> nudges() async {
    final body = await _send(
        'GET', _uri('/api/v1/nudges/${_seg(config.groupId)}'),
        envelope: true);
    return LensNudgeReport.fromJson(_asMap(body, 'the nudge report'));
  }

  @override
  Future<List<LensAskRow>> asks({int limit = 50}) async {
    final body = await _send('GET',
        _uri('/api/v1/asks/${_seg(config.groupId)}', {'limit': '$limit'}),
        envelope: true);
    final map = _asMap(body, 'the ask feed');
    return [
      for (final a in (map['asks'] as List<dynamic>? ?? const []))
        if (a is Map<String, dynamic>) LensAskRow.fromJson(a)
    ];
  }

  @override
  Future<List<LensDecisionRow>> decisions({int limit = 50}) async {
    final body = await _send('GET',
        _uri('/api/v1/decisions/${_seg(config.groupId)}', {'limit': '$limit'}),
        envelope: true);
    final map = _asMap(body, 'the decision feed');
    return [
      for (final d in (map['decisions'] as List<dynamic>? ?? const []))
        if (d is Map<String, dynamic>) LensDecisionRow.fromJson(d)
    ];
  }

  @override
  Future<LensHealth> health() async {
    final body = await _send('GET', _uri('/api/v1/health'), envelope: true);
    return LensHealth.fromJson(_asMap(body, 'the health report'));
  }

  @override
  Future<void> answerAsk(String askId,
      {required String answer,
      required String answererId,
      required String answererName}) async {
    await _send('PATCH', _uri('/api/v1/asks/${_seg(askId)}/answer'),
        envelope: true,
        jsonBody: {
          'answer': answer,
          'answerer_id': answererId,
          'answerer_name': answererName,
        });
  }

  @override
  Future<void> dismissAsk(String askId) async {
    await _send('PATCH', _uri('/api/v1/asks/${_seg(askId)}/dismiss'),
        envelope: true);
  }

  @override
  Future<void> reactToDecision(String decisionId,
      {required String reaction,
      required String nodeId,
      required String displayName}) async {
    await _send('POST', _uri('/api/v1/decisions/${_seg(decisionId)}/react'),
        envelope: true,
        jsonBody: {
          'node_id': nodeId,
          'display_name': displayName,
          'reaction': reaction,
        });
  }

  @override
  Future<void> resolveBlocker(String nodeId) async {
    await _send('PATCH', _uri('/api/v1/nodes/${_seg(nodeId)}/resolve-blocker'),
        envelope: true);
  }

  @override
  Future<NoteStructureResult> structureNote({
    required String boardId,
    required String text,
    NotesLane lane = NotesLane.note,
  }) async {
    // The REPORT lane is a different endpoint, not a flag — a messy shot-log
    // import is typed entirely as `shot-log` by the lens, so routing it through
    // the note lane would mis-type every row.
    final path = lane == NotesLane.report
        ? '/api/v1/notes/structure/report'
        : '/api/v1/notes/structure';
    final body = await _send('POST', _uri(path), envelope: true, jsonBody: {
      'board_id': boardId,
      'text': text,
    });
    if (body is! Map) return const NoteStructureResult();
    return NoteStructureResult.fromJson(Map<String, dynamic>.from(body));
  }

  /// The deadline the two generation lanes get. Minutes, not seconds: the
  /// server walks spec -> plan -> tasks -> steps -> sweep on a fresh brief.
  static const Duration kGenerationDeadline = Duration(seconds: 360);

  /// The distiller SEAT — only the three fields the server reads, and only when
  /// the constitution actually has a hash. Forwarding a hashless or unparseable
  /// constitution would ask the server to steer by nothing.
  static Map<String, dynamic>? _seat(String? constitutionJson) {
    if (constitutionJson == null || constitutionJson.trim().isEmpty)
      return null;
    try {
      final obj = jsonDecode(constitutionJson);
      if (obj is! Map) return null;
      final hash = obj['hash'];
      if (hash is! String || hash.isEmpty) return null;
      return {
        'hash': hash,
        'markdown': obj['markdown'] is String ? obj['markdown'] : '',
        if (obj['hard'] != null) 'hard': obj['hard'],
      };
    } catch (_) {
      return null;
    }
  }

  @override
  Future<LensDraft> generateSteps({
    required String boardId,
    required String brief,
    String? constitutionJson,
  }) async {
    final seat = _seat(constitutionJson);
    final body = await _send(
      'POST',
      _uri('/api/v1/generate'),
      envelope: true,
      deadline: kGenerationDeadline,
      jsonBody: {
        'board_id': boardId,
        'brief': brief,
        if (seat != null) 'constitution': seat,
      },
    );
    if (body is! Map) return const LensDraft();
    final map = Map<String, dynamic>.from(body);
    final rows = map['steps'];
    final steps = <String>[];
    if (rows is List) {
      for (final row in rows) {
        if (row is Map && row['text'] is String) {
          steps.add(row['text'] as String);
        } else if (row is String) {
          steps.add(row);
        }
      }
    }
    return LensDraft(
      steps: steps,
      cache: map['cache'] is Map
          ? LensGenCacheFlags.fromJson(Map<String, dynamic>.from(map['cache']))
          : null,
      cost: map['cost'] is Map
          ? LensGenCost.fromJson(Map<String, dynamic>.from(map['cost']))
          : null,
    );
  }

  @override
  Future<LensTranspiled> transpileNotes({
    required String boardId,
    required List<String> notes,
    String? constitutionJson,
  }) async {
    final seat = _seat(constitutionJson);
    final body = await _send(
      'POST',
      _uri('/api/v1/transpile'),
      envelope: true,
      deadline: kGenerationDeadline,
      jsonBody: {
        'board_id': boardId,
        'notes': notes,
        if (seat != null) 'constitution': seat,
      },
    );
    if (body is! Map) return const LensTranspiled();
    final map = Map<String, dynamic>.from(body);
    List<String> strings(Object? raw) => raw is List
        ? [
            for (final r in raw)
              if (r is String)
                r
              else if (r is Map && r['text'] is String)
                r['text'] as String
          ]
        : const <String>[];
    return LensTranspiled(
      steps: strings(map['steps']),
      irCached: map['ir_cached'] == true,
      bindCached: map['bind_cached'] == true,
      provenance: strings(map['provenance']),
    );
  }

  // ---- Transport ----------------------------------------------------------

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$_base$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  /// One path SEGMENT. Encoded so an id carrying `/` or `..` can neither
  /// traverse nor split the route.
  String _seg(String component) => Uri.encodeComponent(component);

  Map<String, dynamic> _asMap(Object? body, String what) {
    if (body is Map<String, dynamic>) return body;
    throw LensApiException('$what came back as something other than an object');
  }

  /// Send and decode.
  ///
  /// [envelope] declares which endpoint FAMILY this is: the lens-cloud routes
  /// wrap their payload in `{success, data, error}`; the `/runs` family serves
  /// its objects bare. It is a parameter and not a sniff on purpose — the
  /// command replies (`{success, run}`, `{success, decision, …, run}`) carry a
  /// `success` key of their OWN, so any heuristic unwraps them into nothing.
  Future<Object?> _send(String method, Uri url,
      {Map<String, dynamic>? jsonBody,
      bool envelope = false,
      Duration? deadline}) async {
    // GENERATION-SCALE calls need their own deadline. A fresh /generate or
    // /transpile walks a staged pipeline and the ordinary read timeout killed
    // every first run while cached ones flew — which reads as "the lens is
    // broken" exactly when it is doing the most work.
    final timeout = deadline ?? this.timeout;
    final client = _newClient();
    client.connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, url).timeout(timeout);
      // Attach the cached bearer. NEVER logged. Tenant scope is the lens's.
      request.headers.set(
          HttpHeaders.authorizationHeader, 'Bearer ${config.effectiveToken}');
      if (jsonBody != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(jsonBody));
      }
      final response = await request.close().timeout(timeout);
      final text =
          await response.transform(utf8.decoder).join().timeout(timeout);

      if (response.statusCode != HttpStatus.ok) {
        // Surface the lens's plain-text error (e.g. the CONFLICT "only a Failed
        // run can be retried") without ever echoing the bearer.
        final detail = text.trim();
        throw LensApiException(
          detail.isEmpty ? 'HTTP ${response.statusCode}' : detail,
          statusCode: response.statusCode,
        );
      }

      final decoded = decodeLensBody(text);
      if (!envelope) return decoded;
      final unwrapped = LensEnvelope.of(decoded);
      if (!unwrapped.success) {
        throw LensApiException(
            unwrapped.error ?? 'the lens reported a failure');
      }
      return unwrapped.data;
    } on LensApiException {
      rethrow;
    } on SocketException catch (e) {
      throw LensApiException.unreachable(
          'the lens is unreachable at $_base (${e.osError?.message ?? e.message})');
    } on TimeoutException {
      throw LensApiException.unreachable(
          'the lens did not answer within ${timeout.inSeconds}s at $_base');
    } on HttpException catch (e) {
      throw LensApiException(e.message);
    } on FormatException catch (e) {
      throw LensApiException('the lens sent a body this client cannot read: '
          '${e.message}');
    } finally {
      client.close(force: true);
    }
  }
}
