// models/dashboard_event.dart
// Dashboard event union matching Swift DashboardTypes.swift (DashboardEvent.fromJSON).
//
// The dashboard is a CONSUMER, not a producer: these seven variants are
// receive-only, decoded off the "dashboard" component of cyan_poll_events.
// There is no client command FFI here — workflow status rides the event poll.
//
// Fields are flat / primitive (Parquet-safe) and every event carries
// `tenant_id` + `run_id`; `run_id` + `board_id` + `workflow_id` are scoping keys.

import 'dart:convert';

// ═══════════════════════════════════════════════════════════════════════════
// STEP STATE / ACTOR / RUN STATE (contract §A)
// ═══════════════════════════════════════════════════════════════════════════

/// state ∈ pending | running | awaiting_approval | approved | done | failed |
/// needs_lens | awaiting_input
enum DashboardStepState {
  pending('pending'),
  running('running'),
  awaitingApproval('awaiting_approval'),
  approved('approved'),
  done('done'),
  failed('failed'),

  /// A CREATIVE step whose model is unavailable (vLLM down or a stub): parked,
  /// never a red failure; Retry resumes it when the GPU is back.
  needsLens('needs_lens'),

  /// A MECHANICAL step whose required input isn't available yet (conform with
  /// no confirmed edits, an upstream output not produced): parked amber and
  /// human-actionable. Never a red failure.
  awaitingInput('awaiting_input');

  const DashboardStepState(this.wire);

  /// The spelling the engine puts on the wire.
  final String wire;

  /// Unrecognised spellings fall back to pending — a new engine state must
  /// never take the dashboard down.
  static DashboardStepState fromWire(String? raw) {
    for (final s in DashboardStepState.values) {
      if (s.wire == raw) return s;
    }
    return DashboardStepState.pending;
  }
}

/// actor ∈ human | ai
enum DashboardStepActor {
  human('human'),
  ai('ai');

  const DashboardStepActor(this.wire);

  final String wire;

  /// Absent or unrecognised means the machine ran it.
  static DashboardStepActor fromWire(String? raw) {
    for (final a in DashboardStepActor.values) {
      if (a.wire == raw) return a;
    }
    return DashboardStepActor.ai;
  }
}

/// state ∈ done | failed | cancelled (a finished run); `running` while live.
enum WorkflowRunState {
  running('running'),
  done('done'),
  failed('failed'),
  cancelled('cancelled');

  const WorkflowRunState(this.wire);

  final String wire;

  /// A run we can't classify is a run that finished — never a phantom live one.
  static WorkflowRunState fromWire(String? raw) {
    for (final s in WorkflowRunState.values) {
      if (s.wire == raw) return s;
    }
    return WorkflowRunState.done;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// NUMERIC COERCION (mirrors iOS DashboardNum)
// ═══════════════════════════════════════════════════════════════════════════

/// JSON numbers arrive as int, double or a numeric string depending on which
/// producer wrote them. Everything coerces; anything else is 0, never a throw.
class DashboardNum {
  const DashboardNum._();

  static int asInt(dynamic any) => asDouble(any).toInt();

  static double asDouble(dynamic any) {
    if (any is num) return any.toDouble();
    if (any is String) return double.tryParse(any.trim()) ?? 0;
    return 0;
  }
}

/// Absent (or non-string) values default to empty, matching `as? String ?? ""`.
String _str(dynamic any) => any is String ? any : '';

/// Nullable strings stay null when absent — the caller distinguishes them.
String? _strOrNull(dynamic any) => any is String ? any : null;

// ═══════════════════════════════════════════════════════════════════════════
// AGGREGATED READ-MODEL (contract §B)
// ═══════════════════════════════════════════════════════════════════════════

class DashboardSnapshot {
  final String tenantId;
  final String boardId;
  final String runId;
  final String workflowId;
  final String workflowLabel;
  final int updatedAt;

  final String? currentItem;
  final String? currentStage;
  final int itemsProcessed;
  final int itemsTotal;

  final DashboardTotals totals;
  final List<DashboardStageStat> perStage;

  const DashboardSnapshot({
    required this.tenantId,
    required this.boardId,
    required this.runId,
    required this.workflowId,
    required this.workflowLabel,
    required this.updatedAt,
    this.currentItem,
    this.currentStage,
    required this.itemsProcessed,
    required this.itemsTotal,
    required this.totals,
    this.perStage = const [],
  });

  /// Decode from the flat/primitive `snapshot` payload. Null without its own
  /// ids — a snapshot we can't scope is a snapshot we can't render.
  static DashboardSnapshot? fromMap(Map<String, dynamic> dict) {
    final tenantId = dict['tenant_id'];
    final runId = dict['run_id'];
    if (tenantId is! String || runId is! String) return null;

    final totalsDict = dict['totals'];
    final totals = DashboardTotals.fromMap(
      totalsDict is Map ? totalsDict : const {},
    );

    final perStage = <DashboardStageStat>[];
    final rawStages = dict['per_stage'];
    if (rawStages is List) {
      for (final s in rawStages) {
        if (s is Map) perStage.add(DashboardStageStat.fromMap(s));
      }
    }

    return DashboardSnapshot(
      tenantId: tenantId,
      boardId: _str(dict['board_id']),
      runId: runId,
      workflowId: _str(dict['workflow_id']),
      workflowLabel: _str(dict['workflow_label']),
      updatedAt: DashboardNum.asInt(dict['updated_at']),
      currentItem: _strOrNull(dict['current_item']),
      currentStage: _strOrNull(dict['current_stage']),
      itemsProcessed: DashboardNum.asInt(dict['items_processed']),
      itemsTotal: DashboardNum.asInt(dict['items_total']),
      totals: totals,
      perStage: perStage,
    );
  }
}

class DashboardTotals {
  final double wallMinutes;
  final double humanMinutes;
  final double aiMinutes;
  final int filesProcessed;
  final double estCostUsd;

  const DashboardTotals({
    required this.wallMinutes,
    required this.humanMinutes,
    required this.aiMinutes,
    required this.filesProcessed,
    required this.estCostUsd,
  });

  /// Absent totals are zeros — an early snapshot has nothing to report yet.
  factory DashboardTotals.fromMap(Map<dynamic, dynamic> d) => DashboardTotals(
        wallMinutes: DashboardNum.asDouble(d['wall_minutes']),
        humanMinutes: DashboardNum.asDouble(d['human_minutes']),
        aiMinutes: DashboardNum.asDouble(d['ai_minutes']),
        filesProcessed: DashboardNum.asInt(d['files_processed']),
        estCostUsd: DashboardNum.asDouble(d['est_cost_usd']),
      );
}

class DashboardStageStat {
  final String stage;
  final String state;
  final double minutes; // wall time in this stage
  final double humanMinutes; // approval-gate time attributed here
  final double aiMinutes;
  final double costUsd;
  final List<String> plugins;

  const DashboardStageStat({
    required this.stage,
    required this.state,
    required this.minutes,
    required this.humanMinutes,
    required this.aiMinutes,
    required this.costUsd,
    this.plugins = const [],
  });

  factory DashboardStageStat.fromMap(Map<dynamic, dynamic> s) {
    final rawPlugins = s['plugins'];
    return DashboardStageStat(
      stage: _str(s['stage']),
      state: _str(s['state']),
      minutes: DashboardNum.asDouble(s['minutes']),
      humanMinutes: DashboardNum.asDouble(s['human_minutes']),
      aiMinutes: DashboardNum.asDouble(s['ai_minutes']),
      costUsd: DashboardNum.asDouble(s['cost_usd']),
      plugins: rawPlugins is List ? rawPlugins.whereType<String>().toList() : const [],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// THE EVENT UNION — receive-only
// ═══════════════════════════════════════════════════════════════════════════

sealed class DashboardEvent {
  final String runId;
  final String tenantId;

  const DashboardEvent({required this.runId, required this.tenantId});

  /// Decode one poll frame. Returns null — never throws and never a
  /// half-built event — for malformed JSON, a non-object, an unknown `type`,
  /// or a variant missing its required id.
  static DashboardEvent? fromJson(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final type = decoded['type'];
    if (type is! String) return null;

    // Variants may arrive flat or wrapped under "data".
    final wrapped = decoded['data'];
    final p = wrapped is Map<String, dynamic> ? wrapped : decoded;
    final tenant = _str(p['tenant_id']);

    // run_id (and step_id where the variant is step-scoped) is the identity:
    // without it there is nothing to attach the event to.
    final runId = p['run_id'];
    if (runId is! String) return null;
    final stepId = p['step_id'];

    switch (type) {
      case 'WorkflowRunStarted':
        return RunStarted(
          runId: runId,
          boardId: _str(p['board_id']),
          workflowId: _str(p['workflow_id']),
          workflowLabel: _str(p['workflow_label']),
          totalSteps: DashboardNum.asInt(p['total_steps']),
          startedAt: DashboardNum.asInt(p['started_at']),
          tenantId: tenant,
        );

      case 'StepStateChanged':
        if (stepId is! String) return null;
        return StepStateChanged(
          runId: runId,
          stepId: stepId,
          name: _str(p['name']),
          stage: _str(p['stage']),
          state: DashboardStepState.fromWire(_strOrNull(p['state'])),
          plugin: _strOrNull(p['plugin']),
          actor: DashboardStepActor.fromWire(_strOrNull(p['actor'])),
          at: DashboardNum.asInt(p['at']),
          tenantId: tenant,
        );

      case 'StepProgress':
        if (stepId is! String) return null;
        return StepProgress(
          runId: runId,
          stepId: stepId,
          processed: DashboardNum.asInt(p['processed']),
          total: DashboardNum.asInt(p['total']),
          currentItem: _strOrNull(p['current_item']),
          detail: _strOrNull(p['detail']),
          tenantId: tenant,
        );

      case 'ApprovalRequested':
        if (stepId is! String) return null;
        return ApprovalRequested(
          runId: runId,
          stepId: stepId,
          name: _str(p['name']),
          requestedAt: DashboardNum.asInt(p['requested_at']),
          tenantId: tenant,
        );

      case 'ApprovalResolved':
        if (stepId is! String) return null;
        return ApprovalResolved(
          runId: runId,
          stepId: stepId,
          decision: _str(p['decision']),
          by: _str(p['by']),
          at: DashboardNum.asInt(p['at']),
          tenantId: tenant,
        );

      case 'WorkflowRunFinished':
        return RunFinished(
          runId: runId,
          state: WorkflowRunState.fromWire(_strOrNull(p['state'])),
          finishedAt: DashboardNum.asInt(p['finished_at']),
          tenantId: tenant,
        );

      case 'WorkflowStatsUpdated':
        final snapDict = p['snapshot'];
        if (snapDict is! Map<String, dynamic>) return null;
        final snapshot = DashboardSnapshot.fromMap(snapDict);
        if (snapshot == null) return null;
        return StatsUpdated(
          runId: runId,
          snapshot: snapshot,
          tenantId: tenant.isEmpty ? snapshot.tenantId : tenant,
        );

      default:
        return null;
    }
  }
}

class RunStarted extends DashboardEvent {
  final String boardId;
  final String workflowId;
  final String workflowLabel;
  final int totalSteps;
  final int startedAt;

  const RunStarted({
    required super.runId,
    required this.boardId,
    required this.workflowId,
    required this.workflowLabel,
    required this.totalSteps,
    required this.startedAt,
    required super.tenantId,
  });
}

class StepStateChanged extends DashboardEvent {
  final String stepId;
  final String name;
  final String stage;
  final DashboardStepState state;
  final String? plugin;
  final DashboardStepActor actor;
  final int at;

  const StepStateChanged({
    required super.runId,
    required this.stepId,
    required this.name,
    required this.stage,
    required this.state,
    this.plugin,
    required this.actor,
    required this.at,
    required super.tenantId,
  });
}

class StepProgress extends DashboardEvent {
  final String stepId;
  final int processed;
  final int total;
  final String? currentItem;
  final String? detail;

  const StepProgress({
    required super.runId,
    required this.stepId,
    required this.processed,
    required this.total,
    this.currentItem,
    this.detail,
    required super.tenantId,
  });
}

class ApprovalRequested extends DashboardEvent {
  final String stepId;
  final String name;
  final int requestedAt;

  const ApprovalRequested({
    required super.runId,
    required this.stepId,
    required this.name,
    required this.requestedAt,
    required super.tenantId,
  });
}

class ApprovalResolved extends DashboardEvent {
  final String stepId;
  final String decision;
  final String by;
  final int at;

  const ApprovalResolved({
    required super.runId,
    required this.stepId,
    required this.decision,
    required this.by,
    required this.at,
    required super.tenantId,
  });
}

class RunFinished extends DashboardEvent {
  final WorkflowRunState state;
  final int finishedAt;

  const RunFinished({
    required super.runId,
    required this.state,
    required this.finishedAt,
    required super.tenantId,
  });
}

class StatsUpdated extends DashboardEvent {
  final DashboardSnapshot snapshot;

  const StatsUpdated({
    required super.runId,
    required this.snapshot,
    required super.tenantId,
  });
}
