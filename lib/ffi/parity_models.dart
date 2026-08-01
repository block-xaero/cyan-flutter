// ffi/parity_models.dart
//
// Plain, immutable view models returned by the `CyanBackend` seam. These are
// deliberately UI-facing and decoupled from the FFI JSON wire format and from
// the legacy `tree_item.dart` models, so the parity screens have one stable
// shape to render whether the data came from the real engine or the fake.
//
// Hierarchy mirrors the SwiftUI app: Group -> Workspace -> Board.

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A top-level group (a P2P collaboration space).
@immutable
class CyanGroup {
  final String id;
  final String name;
  final String colorHex; // e.g. "#66D9EF"
  final int peerCount;
  final List<CyanWorkspace> workspaces;

  const CyanGroup({
    required this.id,
    required this.name,
    required this.colorHex,
    this.peerCount = 0,
    this.workspaces = const [],
  });
}

/// A workspace inside a group.
@immutable
class CyanWorkspace {
  final String id;
  final String groupId;
  final String name;
  final List<CyanBoard> boards;

  const CyanWorkspace({
    required this.id,
    required this.groupId,
    required this.name,
    this.boards = const [],
  });
}

/// The three faces a board can present (canvas is removed in the parity target;
/// kept here only as a fallback for legacy data).
enum BoardFaceKind { workflow, notes, dashboard, canvas }

extension BoardFaceKindX on BoardFaceKind {
  String get label => switch (this) {
        BoardFaceKind.workflow => 'Workflow',
        BoardFaceKind.notes => 'Notes',
        BoardFaceKind.dashboard => 'Dashboard',
        BoardFaceKind.canvas => 'Canvas',
      };

  static BoardFaceKind fromString(String? s) => switch (s?.toLowerCase()) {
        'workflow' || 'notebook' => BoardFaceKind.workflow,
        'notes' => BoardFaceKind.notes,
        'dashboard' => BoardFaceKind.dashboard,
        _ => BoardFaceKind.canvas,
      };
}

/// A board. The unit the living-wall grid renders as a card.
@immutable
class CyanBoard {
  final String id;
  final String workspaceId;
  final String name;
  final BoardFaceKind activeFace;
  final bool isPinned;
  final int rating; // 0..5
  final List<String> labels;
  final int stepCount; // number of workflow steps / cells
  final bool isDeployed; // running workflow => "living" card
  final DateTime createdAt;
  final DateTime? lastModified;

  const CyanBoard({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.activeFace = BoardFaceKind.workflow,
    this.isPinned = false,
    this.rating = 0,
    this.labels = const [],
    this.stepCount = 0,
    this.isDeployed = false,
    required this.createdAt,
    this.lastModified,
  });
}

/// A board plus the group/workspace it lives in. The flat unit the All-Boards
/// living wall renders.
@immutable
class BoardWithContext {
  final CyanBoard board;
  final CyanGroup group;
  final CyanWorkspace workspace;

  const BoardWithContext({
    required this.board,
    required this.group,
    required this.workspace,
  });
}

// ---------------------------------------------------------------------------
// Workflow run (Dashboard face)
// ---------------------------------------------------------------------------

enum RunStepStatus { pending, running, awaitingApproval, done, failed }

enum RunStepKind { ai, human }

@immutable
class RunStep {
  final String id;
  final String title;
  final RunStepKind kind;
  final RunStepStatus status;

  const RunStep({
    required this.id,
    required this.title,
    required this.kind,
    required this.status,
  });
}

@immutable
class WorkflowRun {
  final String boardId;
  final String title;
  final List<RunStep> steps;

  const WorkflowRun({
    required this.boardId,
    required this.title,
    required this.steps,
  });
}

// ---------------------------------------------------------------------------
// Workflow authoring (Workflow face) — SwiftUI WorkflowView parity
// ---------------------------------------------------------------------------

/// The approval gate a step compiled to.
enum StepGate { needsApproval, noApproval }

/// One authored workflow step (a numbered cell). Carries the compiled
/// "inference" chips the SwiftUI StepRow shows: tool, destination, bound
/// inputs, and the gate. `isAmbiguous` surfaces the orange warning treatment.
@immutable
class WorkflowStep {
  final String id;
  final String text;
  final String? tool; // plugin the step compiled to (cyan chip)
  final String? destination; // "send to X" (purple chip)
  final List<String> boundInputs; // # file bindings (green chips)
  final StepGate? gate;
  final bool isAmbiguous;

  const WorkflowStep({
    required this.id,
    required this.text,
    this.tool,
    this.destination,
    this.boundInputs = const [],
    this.gate,
    this.isAmbiguous = false,
  });
}

/// The authored workflow for a board's Workflow face.
@immutable
class Workflow {
  final String boardId;
  final List<WorkflowStep> steps;
  final bool isDeployed; // deployed & locked banner
  final bool isCompiled; // Review/compile already ran

  const Workflow({
    required this.boardId,
    this.steps = const [],
    this.isDeployed = false,
    this.isCompiled = false,
  });
}

// ---------------------------------------------------------------------------
// Notes face — SwiftUI NotesEditorView parity
// ---------------------------------------------------------------------------

/// The notes document for a board's Notes face (plain text / markdown).
@immutable
class BoardNotes {
  final String boardId;
  final String fileName;
  final String content;

  const BoardNotes({
    required this.boardId,
    required this.fileName,
    required this.content,
  });
}

// ---------------------------------------------------------------------------
// Operations console — SwiftUI OperationsConsoleView parity
// ---------------------------------------------------------------------------

/// Lifecycle state of a run, shaping its status pill + which lane it sits in.
enum RunStatus { queued, running, awaitingApproval, stuck, done, failed }

extension RunStatusX on RunStatus {
  String get label => switch (this) {
        RunStatus.queued => 'Queued',
        RunStatus.running => 'Running',
        RunStatus.awaitingApproval => 'Approval',
        RunStatus.stuck => 'Stuck',
        RunStatus.done => 'Done',
        RunStatus.failed => 'Failed',
      };

  /// Action-needed lane = approval / stuck / failed.
  bool get needsAction =>
      this == RunStatus.awaitingApproval ||
      this == RunStatus.stuck ||
      this == RunStatus.failed;

  /// TERMINAL (settled) = the run has stopped for good. These are the runs the
  /// lens invoices on — the metering console reads its totals off exactly this
  /// set, so the run list and the bill can never disagree.
  bool get isTerminal => this == RunStatus.done || this == RunStatus.failed;

  /// The settled outcome a run row reports; null while it is still live.
  String? get terminalLabel => isTerminal ? label : null;
}

/// One run row/card in the Ops Runs feed.
@immutable
class OpsRun {
  final String runId;
  final String asset; // asset filename / run label
  final String workflow; // owning workflow/board name
  final RunStatus status;
  final int currentStep;
  final int stepCount;
  final String durationLabel; // "1:23"
  final double costDollars; // billed $
  final double billedMinutes; // asset-minutes billed
  final double retryMinutes; // re-run minutes
  final bool isCacheHit;
  final String? stageLabel; // humanized in-flight stage

  const OpsRun({
    required this.runId,
    required this.asset,
    required this.workflow,
    required this.status,
    this.currentStep = 0,
    this.stepCount = 0,
    this.durationLabel = '',
    this.costDollars = 0,
    this.billedMinutes = 0,
    this.retryMinutes = 0,
    this.isCacheHit = false,
    this.stageLabel,
  });
}

/// The tenant-wide asset-minute meter headline (Ops Cost face).
@immutable
class CostMeter {
  final bool hasMeter;
  final double billedMinutes; // cyan
  final double billedDollars; // green
  final double retryMinutes; // orange
  final double savedMinutes; // purple (cache savings)
  final int runs;
  // internal COGS (margin, not billed)
  final double computeMinutes;
  final double gpuSeconds;
  final List<WorkflowCost> perWorkflow;

  const CostMeter({
    this.hasMeter = true,
    required this.billedMinutes,
    required this.billedDollars,
    required this.retryMinutes,
    required this.savedMinutes,
    required this.runs,
    required this.computeMinutes,
    required this.gpuSeconds,
    this.perWorkflow = const [],
  });
}

/// One per-workflow row in the cost reconcile table.
@immutable
class WorkflowCost {
  final String workflow;
  final int runs;
  final int assets;
  final double billedMinutes;
  final double billedDollars;
  final double retryMinutes;

  const WorkflowCost({
    required this.workflow,
    required this.runs,
    required this.assets,
    required this.billedMinutes,
    required this.billedDollars,
    required this.retryMinutes,
  });
}

/// Efficiency insight cards + per-step table (Ops Efficiency face).
@immutable
class EfficiencyReport {
  // headline insight cards
  final String gateBottleneckStep;
  final double gateWaitP95Ms; // yellow
  final String failureHotspotStep;
  final double failureRatePct; // red
  final String? topErrorClass;
  final String slowestStep;
  final double slowestExecP95Ms; // orange
  final double cacheHitRatePct; // purple
  final double minutesSaved;
  final double retryRatePct; // cyan
  final List<StepEfficiency> steps;

  const EfficiencyReport({
    required this.gateBottleneckStep,
    required this.gateWaitP95Ms,
    required this.failureHotspotStep,
    required this.failureRatePct,
    this.topErrorClass,
    required this.slowestStep,
    required this.slowestExecP95Ms,
    required this.cacheHitRatePct,
    required this.minutesSaved,
    required this.retryRatePct,
    this.steps = const [],
  });
}

/// One per-step row in the efficiency table.
@immutable
class StepEfficiency {
  final String step;
  final int runs;
  final double gateP95Ms;
  final double failPct;
  final String? topError;
  final double execP95Ms;
  final double cachePct;
  final double savedMinutes;
  final double retryPct;

  const StepEfficiency({
    required this.step,
    required this.runs,
    required this.gateP95Ms,
    required this.failPct,
    this.topError,
    required this.execP95Ms,
    required this.cachePct,
    required this.savedMinutes,
    required this.retryPct,
  });
}

// ---------------------------------------------------------------------------
// Marketplace — SwiftUI MarketplaceView parity
// ---------------------------------------------------------------------------

/// Category band a plugin card sits in (drives the header gradient + glyph).
enum PluginCategory { editorial, color, sound, review, delivery }

extension PluginCategoryX on PluginCategory {
  String get label => switch (this) {
        PluginCategory.editorial => 'Editorial',
        PluginCategory.color => 'Color',
        PluginCategory.sound => 'Sound',
        PluginCategory.review => 'Review',
        PluginCategory.delivery => 'Delivery',
      };
}

/// A side effect drives the approval gate / badge on a plugin card.
enum PluginSideEffect { readOnly, externalSend }

/// One marketplace plugin card.
@immutable
class PluginCard {
  final String id;
  final String name;
  final String publisher;
  final String summary;
  final PluginCategory category;
  final String stage; // controlled-vocab stage label
  final String placement; // "device" | "cloud"
  final PluginSideEffect sideEffect;
  final bool isTrusted;
  final double rating; // 0..5
  final bool isFeatured;

  /// The plugin BUNDLE this listing installs, when the storefront's listing id
  /// is not itself the bundle id. Read [bundleId], never this.
  final String? _bundleId;

  const PluginCard({
    required this.id,
    required this.name,
    required this.publisher,
    required this.summary,
    required this.category,
    required this.stage,
    required this.placement,
    String? bundleId,
    this.sideEffect = PluginSideEffect.readOnly,
    this.isTrusted = true,
    this.rating = 0,
    this.isFeatured = false,
  }) : _bundleId = bundleId;

  /// The id the BUNDLE carries once it lands: what [InstalledPlugin.id] reports
  /// out of the device catalog, what [CyanBackend.installPluginBundle] is asked
  /// for, and what an `@mention` resolves to. The gossiped index usually
  /// publishes a listing under its bundle id, so it falls back to [id].
  String get bundleId => _bundleId ?? id;
}

// ---------------------------------------------------------------------------
// Plugins — the device catalog and bundle install
// ---------------------------------------------------------------------------

/// One tool a bundled plugin declares, as the catalog serializes it.
@immutable
class InstalledPluginTool {
  final String name;

  /// The tool's declared side effects, straight off the manifest — empty for a
  /// sensor. The ENGINE owns the vocabulary AND which labels gate on a human
  /// (`external_send` · `delete` · `mutate_local`), so they are carried here,
  /// never re-judged.
  final List<String> sideEffects;

  const InstalledPluginTool({required this.name, this.sideEffects = const []});

  /// True when this tool needs the human-approval gate before it may
  /// auto-execute — the engine's `requires_approval` predicate.
  bool get requiresApproval => sideEffects.any(_gatedSideEffects.contains);

  static const Set<String> _gatedSideEffects = {
    'external_send',
    'delete',
    'mutate_local',
  };

  /// `{"name","side_effects":[…]}`.
  factory InstalledPluginTool.fromJson(Map<String, dynamic> j) =>
      InstalledPluginTool(
        name: j['name'] as String? ?? '',
        sideEffects:
            (j['side_effects'] as List<dynamic>? ?? const []).cast<String>(),
      );
}

/// A plugin bundle INSTALLED on this device — one subdir under the plugins
/// root, read straight off its manifest. Distinct from [PluginCard], which is
/// the marketplace listing of what COULD be installed.
@immutable
class InstalledPlugin {
  final String id;
  final String version;

  /// The bundle's tools, ordered by name exactly as the engine sorts them.
  final List<InstalledPluginTool> tools;

  const InstalledPlugin({
    required this.id,
    this.version = '',
    this.tools = const [],
  });

  /// `{"id","version","tools":[{name, side_effects}]}`.
  factory InstalledPlugin.fromJson(Map<String, dynamic> j) => InstalledPlugin(
        id: j['id'] as String? ?? '',
        version: j['version'] as String? ?? '',
        tools: [
          for (final t in (j['tools'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>())
            InstalledPluginTool.fromJson(t)
        ],
      );
}

/// What installing a `.cyanplugin` bundle answered: the file object the bytes
/// landed as, or the engine's refusal (a bad base64 body, a bundle whose layout
/// or signature the install policy would not admit, a failed write).
@immutable
class PluginInstallResult {
  final bool success;
  final String pluginId;

  /// The mesh file object the bundle bytes landed as.
  final String? fileId;
  final String? error;

  const PluginInstallResult({
    required this.success,
    this.pluginId = '',
    this.fileId,
    this.error,
  });

  /// Engine unreachable / the call returned no payload at all.
  const PluginInstallResult.unavailable()
      : success = false,
        pluginId = '',
        fileId = null,
        error = 'engine unavailable';

  /// `{"success":true,"plugin_id","file_id"}` or `{"success":false,"error"}`.
  factory PluginInstallResult.fromJson(Map<String, dynamic> j) =>
      PluginInstallResult(
        success: j['success'] == true,
        pluginId: j['plugin_id'] as String? ?? '',
        fileId: j['file_id'] as String?,
        error: j['error'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Lens AI — SwiftUI LensAIView parity (nudges / asks / decisions)
// ---------------------------------------------------------------------------

/// A nudge: a proactive focus prompt derived from the graph.
@immutable
class LensNudge {
  final String id;
  final String title;
  final String detail;
  final String ageLabel; // "2h ago"
  final String boardLabel; // owning workflow/board

  const LensNudge({
    required this.id,
    required this.title,
    required this.detail,
    required this.ageLabel,
    required this.boardLabel,
  });
}

enum AskStatus { open, answered, stale }

extension AskStatusX on AskStatus {
  String get label => switch (this) {
        AskStatus.open => 'open',
        AskStatus.answered => 'answered',
        AskStatus.stale => 'stale',
      };
}

/// An ask: an open question extracted from collaboration signal.
@immutable
class LensAsk {
  final String id;
  final String question;
  final String asker;
  final String assignee;
  final String ageLabel;
  final AskStatus status;
  final String? answer;
  final String? answerer;

  const LensAsk({
    required this.id,
    required this.question,
    required this.asker,
    required this.assignee,
    required this.ageLabel,
    required this.status,
    this.answer,
    this.answerer,
  });
}

/// A decision: a recorded choice with rationale + reactions.
@immutable
class LensDecision {
  final String id;
  final String content;
  final String? rationale;
  final String decider;
  final String ageLabel;
  final int agreeCount;
  final int disagreeCount;
  final int commentCount;

  const LensDecision({
    required this.id,
    required this.content,
    this.rationale,
    required this.decider,
    required this.ageLabel,
    this.agreeCount = 0,
    this.disagreeCount = 0,
    this.commentCount = 0,
  });
}

/// The Lens intelligence bundle for a tenant/board.
@immutable
class LensIntelligence {
  final bool connected;
  final List<LensNudge> nudges;
  final List<LensAsk> asks;
  final List<LensDecision> decisions;

  const LensIntelligence({
    this.connected = true,
    this.nudges = const [],
    this.asks = const [],
    this.decisions = const [],
  });
}

// ---------------------------------------------------------------------------
// Chat — SwiftUI ChatPanel parity (board-only chat)
// ---------------------------------------------------------------------------

/// One chat message in a board's chat.
@immutable
class ChatMessage {
  final String id;
  final String author;
  final bool isOwn;
  final String body; // markdown-ish
  final String timeLabel; // "10:32 AM"

  const ChatMessage({
    required this.id,
    required this.author,
    required this.isOwn,
    required this.body,
    required this.timeLabel,
  });
}

// ---------------------------------------------------------------------------
// Run audit — SwiftUI `RunAuditView` / `RunTrace` parity
// ---------------------------------------------------------------------------
//
// The per-step provenance behind ONE run: what each step processed, what it
// billed, what it burned internally, and the operational flags (cache ♻ /
// retry ⟳ / skipped / error) that explain the bill. The customer's bill is
// MEDIA-MINUTES (`assetMinutes` → `billedMinutes`); GPU/tokens are internal
// COGS and are NEVER billed. Every field beyond the identity is optional: a
// materialized-but-not-yet-traced step renders as a rail with "—" columns
// rather than being hidden.

/// One step rail in the run drill-down.
@immutable
class RunStepDetail {
  final int stepIndex;
  final String stepId;
  final String? action;
  final String? actor;

  /// The raw trace status (e.g. "ok"); the operational state is [stepStatus].
  final String? status;

  /// The run-state status: Pending / Running / Done / Failed / Skipped.
  final String? stepStatus;
  final int? attempt;
  final bool? idempotentSkipped;
  final int? retry;
  final String? errorClass;

  // internal COGS
  final int? tokensIn;
  final int? tokensOut;
  final int? gpuMs;
  final int? costCents;

  // timing
  final int? startedAt; // epoch ms
  final int? finishedAt; // epoch ms
  final int? wallMs;
  final int? execMs;

  /// Human latency on a gate — queued/gate → decision.
  final int? approvalWaitMs;

  // the bill (asset-minute meter)
  final double? assetMinutes;
  final double? billedMinutes;
  final double? billedCents;
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
    this.retry,
    this.errorClass,
    this.tokensIn,
    this.tokensOut,
    this.gpuMs,
    this.costCents,
    this.startedAt,
    this.finishedAt,
    this.wallMs,
    this.execMs,
    this.approvalWaitMs,
    this.assetMinutes,
    this.billedMinutes,
    this.billedCents,
    this.cacheHit,
  });

  /// The state the rail badges on — `stepStatus` if present, else the raw
  /// trace status, else "—".
  String get displayStatus => stepStatus ?? status ?? '—';

  /// Compute wall for this step in ms — the served [wallMs], else
  /// finished−started. A step that never started or finished has none.
  int? get wallMsComputed {
    final w = wallMs;
    if (w != null && w > 0) return w;
    final s = startedAt, f = finishedAt;
    if (s == null || f == null || f <= s) return null;
    return f - s;
  }

  /// Processing time (COGS) — the served [execMs], else the compute wall.
  int? get execMsComputed {
    final e = execMs;
    if (e != null && e > 0) return e;
    return wallMsComputed;
  }

  /// Did this step reuse a cached result (billed 0)? The served flag, else
  /// inferred from the idempotent-skip / Skipped operational state.
  bool get isCacheHit {
    final c = cacheHit;
    if (c != null) return c;
    return idempotentSkipped == true || stepStatus == 'Skipped';
  }

  /// Did this step genuinely FAIL? Keyed on the operational status only — an
  /// `errorClass` alone can be a non-failure label.
  bool get isFailure => (stepStatus ?? status ?? '').toLowerCase() == 'failed';

  /// Did this step re-process?
  bool get isRetry => (attempt ?? 1) > 1 || (retry ?? 0) > 0;

  /// Billed media-minutes (0 on a cache hit), null when unmetered.
  double? get billedMinutesValue {
    if (billedMinutes != null) return billedMinutes;
    if (isCacheHit) return 0;
    return null;
  }

  /// Total tokens this step burned (internal COGS), null when unmetered.
  int? get tokensTotal {
    if (tokensIn == null && tokensOut == null) return null;
    return (tokensIn ?? 0) + (tokensOut ?? 0);
  }
}

/// The whole per-step trace for one run — what `RunAuditView` renders.
@immutable
class RunTrace {
  final String runId;
  final String tenantId;

  /// The run-level terminal/lifecycle status ("Done" / "Failed" / …).
  final String? status;
  final String? runErrorClass;
  final List<RunStepDetail> steps;
  final int stepCount;

  // served internal-COGS totals
  final int totalTokensIn;
  final int totalTokensOut;
  final double totalGpuSeconds;

  /// Internal GPU price in cents (COGS, never the bill).
  final double totalPriceCents;

  /// The slowest / most-expensive step the audit flags.
  final int? bottleneckStepIndex;

  // served bill rollups; null ⇒ sum the step records instead (§4 invariant:
  // Σ step billed == run billed, so both paths agree by construction).
  final double? totalBilledMinutes;
  final double? totalBilledCents;

  const RunTrace({
    required this.runId,
    required this.tenantId,
    this.status,
    this.runErrorClass,
    this.steps = const [],
    required this.stepCount,
    this.totalTokensIn = 0,
    this.totalTokensOut = 0,
    this.totalGpuSeconds = 0,
    this.totalPriceCents = 0,
    this.bottleneckStepIndex,
    this.totalBilledMinutes,
    this.totalBilledCents,
  });

  /// The step flagged as the bottleneck, if any.
  RunStepDetail? get bottleneckStep {
    final idx = bottleneckStepIndex;
    if (idx == null) return null;
    for (final s in steps) {
      if (s.stepIndex == idx) return s;
    }
    return null;
  }

  /// Compute-only wall for the run (Σ per-step wall, ms).
  int get wallMsRollup =>
      steps.fold<int>(0, (sum, s) => sum + (s.wallMsComputed ?? 0));

  /// Total tokens (in + out) — internal COGS.
  int get tokensRollup => totalTokensIn + totalTokensOut;

  /// Billed media-minutes — the served total, else Σ over the step records.
  /// Null when no step is metered at all ("—", never a fabricated 0).
  double? get billedMinutesRollup {
    if (totalBilledMinutes != null) return totalBilledMinutes;
    final vals = steps
        .map((s) => s.billedMinutesValue)
        .whereType<double>()
        .toList(growable: false);
    if (vals.isEmpty) return null;
    return vals.fold<double>(0.0, (a, b) => a + b);
  }

  /// Billed cents — the served total, else Σ over the step records.
  double? get billedCentsRollup {
    if (totalBilledCents != null) return totalBilledCents;
    final vals = steps
        .map((s) => s.billedCents)
        .whereType<double>()
        .toList(growable: false);
    if (vals.isEmpty) return null;
    return vals.fold<double>(0.0, (a, b) => a + b);
  }

  /// Media-minutes a cache hit avoided billing — the "saved via cache" line.
  /// Null when nothing in this run was reused (never a fake $0.00).
  double? get savedMinutesRollup {
    final vals = steps
        .where((s) => s.isCacheHit)
        .map((s) => s.assetMinutes)
        .whereType<double>()
        .toList(growable: false);
    if (vals.isEmpty) return null;
    return vals.fold<double>(0.0, (a, b) => a + b);
  }
}

// ---------------------------------------------------------------------------
// Entitlement — SwiftUI `Entitlement.swift` parity (the commercial half)
// ---------------------------------------------------------------------------
//
// A Dart mirror of cyan-identity's `entitlement.rs`, restated so a "locked"
// surface means the SAME thing on every verification path. Pure, synchronous,
// tenant-scoped. GRACEFUL EXPIRY is the rule: local data + LAN/local P2P stay
// readable forever; only the PAID cloud surfaces gate.

/// The billing plan a tenant is on. `trial` is the 7-day full-access grant that
/// HARD-STOPS at [Entitlement.trialExpiry].
enum Plan { trial, pro, enterprise }

extension PlanX on Plan {
  bool get isTrial => this == Plan.trial;

  /// A paying plan: soft-cap + overage (vs the trial hard-stop).
  bool get isPaid => !isTrial;

  String get wire => switch (this) {
        Plan.trial => 'trial',
        Plan.pro => 'pro',
        Plan.enterprise => 'enterprise',
      };

  String get displayName => switch (this) {
        Plan.trial => 'Trial',
        Plan.pro => 'Pro',
        Plan.enterprise => 'Enterprise',
      };
}

/// A PAID surface gated by the entitlement. Each maps onto one feature flag.
enum Feature { lens, codegen, marketplacePublish }

extension FeatureX on Feature {
  String get wire => switch (this) {
        Feature.lens => 'lens',
        Feature.codegen => 'codegen',
        Feature.marketplacePublish => 'marketplace_publish',
      };

  /// Plain-language label for the upgrade / locked copy.
  String get label => switch (this) {
        Feature.lens => 'Lens runs',
        Feature.codegen => 'Codegen',
        Feature.marketplacePublish => 'Marketplace publishing',
      };
}

/// Which feature flags a plan turns on. Flat bools, mirroring the token claim.
@immutable
class Features {
  final bool lens;
  final bool codegen;
  final bool marketplacePublish;

  const Features({
    required this.lens,
    required this.codegen,
    required this.marketplacePublish,
  });

  /// Every paid surface on — the trial grant.
  static const Features all =
      Features(lens: true, codegen: true, marketplacePublish: true);

  /// Nothing on (deny-all).
  static const Features none =
      Features(lens: false, codegen: false, marketplacePublish: false);

  bool has(Feature feature) => switch (feature) {
        Feature.lens => lens,
        Feature.codegen => codegen,
        Feature.marketplacePublish => marketplacePublish,
      };

  factory Features.fromJson(Map<String, dynamic> j) => Features(
        lens: j['lens'] as bool? ?? false,
        codegen: j['codegen'] as bool? ?? false,
        marketplacePublish: j['marketplace_publish'] as bool? ?? false,
      );
}

/// The metered allowance for the asset-minute revenue mode.
@immutable
class Meter {
  final int includedMinutes;
  final int rateCentsPerMinute;

  const Meter(
      {required this.includedMinutes, required this.rateCentsPerMinute});

  static const Meter zero = Meter(includedMinutes: 0, rateCentsPerMinute: 0);

  factory Meter.fromJson(Map<String, dynamic> j) => Meter(
        includedMinutes: (j['included_minutes'] as num?)?.toInt() ?? 0,
        rateCentsPerMinute: (j['rate_cents_per_minute'] as num?)?.toInt() ?? 0,
      );
}

/// What a tenant is entitled to — the whole commercial model in one record.
/// [trialExpiry] (unix secs) is non-null only for a trial; paid plans carry
/// null (their token `exp` + grace govern validity, not a trial clock).
@immutable
class Entitlement {
  final String tenant;
  final Plan plan;
  final int seats;
  final Features features;
  final int? trialExpiry;
  final Meter meter;

  const Entitlement({
    required this.tenant,
    required this.plan,
    required this.seats,
    required this.features,
    this.trialExpiry,
    this.meter = Meter.zero,
  });

  /// Whether the trial clock has run out at [now] (unix secs). A paid plan is
  /// never "expired" by this check.
  bool isExpired(int now) {
    final exp = trialExpiry;
    if (exp == null) return false;
    return now >= exp;
  }

  /// Whole days remaining at [now], rounded UP so the last partial day still
  /// reads "1 day left". Null for a paid plan, 0 once expired.
  int? trialDaysLeft(int now) {
    final exp = trialExpiry;
    if (exp == null) return null;
    if (now >= exp) return 0;
    return (exp - now + 86399) ~/ 86400;
  }

  /// Decode the cached signed-entitlement JSON the backend caches. Tolerates
  /// the extra `iss/iat/exp` claim fields. Null on a shape mismatch — the
  /// caller falls back to [Entitlement.offlineDefault].
  static Entitlement? decode(String json) {
    try {
      final j = jsonDecode(json);
      if (j is! Map<String, dynamic>) return null;
      final tenant = j['tenant'] as String?;
      final planRaw = j['plan'] as String?;
      if (tenant == null || planRaw == null) return null;
      Plan? plan;
      for (final p in Plan.values) {
        if (p.wire == planRaw) plan = p;
      }
      if (plan == null) return null;
      final featuresJson = j['features'];
      return Entitlement(
        tenant: tenant,
        plan: plan,
        seats: (j['seats'] as num?)?.toInt() ?? 1,
        features: featuresJson is Map<String, dynamic>
            ? Features.fromJson(featuresJson)
            : Features.none,
        trialExpiry: (j['trial_expiry'] as num?)?.toInt(),
        meter: j['meter'] is Map<String, dynamic>
            ? Meter.fromJson(j['meter'] as Map<String, dynamic>)
            : Meter.zero,
      );
    } catch (_) {
      return null;
    }
  }

  /// The offline-safe default when nothing is cached yet (fresh device, never
  /// signed in): a full trial, so the app never hard-locks itself offline. The
  /// backend's real trial replaces it the moment one is cached.
  factory Entitlement.offlineDefault(String tenant, int now,
          {int trialDays = 7}) =>
      Entitlement(
        tenant: tenant,
        plan: Plan.trial,
        seats: 1,
        features: Features.all,
        trialExpiry: now + trialDays * 86400,
      );
}

/// A surface the UI guards. [PaidSurface.localCollab] is the LAN/local-P2P
/// surface that is NEVER gated (the graceful default); the rest map onto a
/// paid [Feature].
enum PaidSurface { localCollab, lensRun, codegen, marketplacePublish }

extension PaidSurfaceX on PaidSurface {
  /// The feature this surface is entitled by — null means "local read", which
  /// is always allowed.
  Feature? get entitledFeature => switch (this) {
        PaidSurface.localCollab => null,
        PaidSurface.lensRun => Feature.lens,
        PaidSurface.codegen => Feature.codegen,
        PaidSurface.marketplacePublish => Feature.marketplacePublish,
      };

  String get label => switch (this) {
        PaidSurface.localCollab => 'Local collaboration',
        PaidSurface.lensRun => 'Lens runs',
        PaidSurface.codegen => 'Codegen',
        PaidSurface.marketplacePublish => 'Marketplace publishing',
      };
}

/// The verdict the UI renders for a surface. `locked == false` ⇒ available.
@immutable
class SurfaceGate {
  final bool locked;

  /// True when the signed-in role can act on the lock itself (upgrade/seats).
  final bool isAdmin;

  /// Plain-language line the locked UI shows.
  final String message;

  const SurfaceGate(
      {required this.locked, required this.isAdmin, required this.message});

  static const SurfaceGate unlocked =
      SurfaceGate(locked: false, isAdmin: false, message: '');

  /// A non-admin on a locked paid surface is pointed at their admin.
  bool get showsAskAdmin => locked && !isAdmin;

  /// An admin sees the upgrade / seat-management path.
  bool get showsUpgrade => locked && isAdmin;
}

/// The computed entitlement gate: `same-tenant AND feature-present AND
/// not-trial-expired`, with local read ALWAYS allowed (graceful expiry).
class EntitlementPolicy {
  const EntitlementPolicy();

  /// Decide whether [tenant] may use [want] given [entitlement] at [now].
  /// A null [want] is the always-allowed local-read surface.
  bool authorize(Entitlement entitlement,
      {required String tenant, required Feature? want, required int now}) {
    // Tenant isolation: an entitlement never authorizes another tenant.
    if (entitlement.tenant != tenant) return false;
    // Graceful expiry: local data + LAN/local P2P read are never gated.
    if (want == null) return true;
    // The plan must include the feature at all.
    if (!entitlement.features.has(want)) return false;
    // A trial grants full access until expiry, then PAID surfaces stop.
    if (entitlement.isExpired(now)) return false;
    return true;
  }

  /// The per-seat gate: an active-seat count is allowed iff within the cap.
  bool withinSeatCap(Entitlement entitlement, int activeSeats) =>
      activeSeats <= entitlement.seats;
}

/// The W11 license read-model — the SwiftUI `LicenseViewModel` restated. Drives
/// the trial banner and the LOCKED/UPGRADE states on the paid surfaces from the
/// cached entitlement + the [EntitlementPolicy] decision. It owns no commands.
@immutable
class LicenseModel {
  final Entitlement entitlement;

  /// The session tenant the entitlement must match (tenant isolation).
  final String tenant;

  /// Admin/Owner act on the lock (upgrade / seats); others are pointed up.
  final bool isAdmin;

  /// Unix secs — injected so the countdown is deterministic in tests.
  final int nowSecs;

  const LicenseModel({
    required this.entitlement,
    required this.tenant,
    required this.nowSecs,
    this.isAdmin = false,
  });

  static const EntitlementPolicy _policy = EntitlementPolicy();

  bool get isTrial => entitlement.plan.isTrial;

  /// Whole days remaining (null on a paid plan, 0 once expired).
  int? get trialDaysLeft => entitlement.trialDaysLeft(nowSecs);

  /// The trial clock has run out.
  bool get trialExpired => entitlement.isExpired(nowSecs);

  /// The banner only shows for trials.
  bool get showsTrialBanner => isTrial;

  /// The banner line: a countdown while the trial runs, an expiry note after.
  String get trialBannerText {
    if (!isTrial) return '';
    final days = trialDaysLeft;
    if (days == null || days <= 0) {
      return 'Your trial has ended — paid features are locked.';
    }
    return days == 1
        ? '1 day left in your trial'
        : '$days days left in your trial';
  }

  /// Seat cap from the entitlement.
  int get seatCap => entitlement.seats;

  /// The plan name, for the banner / settings chrome.
  String get planName => entitlement.plan.displayName;

  /// The gate verdict for a paid surface. Local collaboration is ALWAYS
  /// unlocked; a paid surface locks when the plan lacks the feature or the
  /// trial has expired. On a lock the message differs by role.
  SurfaceGate gate(PaidSurface surface) {
    final allowed = _policy.authorize(entitlement,
        tenant: tenant, want: surface.entitledFeature, now: nowSecs);
    if (allowed) return SurfaceGate.unlocked;
    final message = isAdmin
        ? 'Upgrade your plan to unlock ${surface.label}.'
        : '${surface.label} is locked on your plan. Ask your admin to upgrade.';
    return SurfaceGate(locked: true, isAdmin: isAdmin, message: message);
  }

  /// Convenience: is this surface locked right now?
  bool isLocked(PaidSurface surface) => gate(surface).locked;
}

// ---------------------------------------------------------------------------
// Pipeline control — the compile / run / gate spine
//
// These mirror the JSON envelopes the engine's pipeline FFI returns
// (`cyan_pipeline_*`, `cyan_run_pipeline`, `cyan_step_edit_travel`,
// `cyan_board_workflow_state`). Wire strings are decoded ONCE, at the seam, so
// no screen ever matches on a raw status literal.
// ---------------------------------------------------------------------------

/// Per-step state as the engine's pipeline config reports it.
enum PipelineStepState {
  /// Authored but not executed yet.
  pending,

  /// Executing now (the engine's `running` / `scheduled`).
  running,

  /// The AI half finished; the step is parked on its approval gate.
  aiComplete,

  /// A human cleared the gate — the step is settled.
  humanApproved,

  /// The step errored.
  failed,
}

extension PipelineStepStateX on PipelineStepState {
  String get label => switch (this) {
        PipelineStepState.pending => 'Pending',
        PipelineStepState.running => 'Running',
        PipelineStepState.aiComplete => 'Awaiting approval',
        PipelineStepState.humanApproved => 'Approved',
        PipelineStepState.failed => 'Failed',
      };

  /// A human must act before this step can move.
  bool get needsApproval => this == PipelineStepState.aiComplete;

  static PipelineStepState fromWire(String? s) => switch (s) {
        'ai_complete' => PipelineStepState.aiComplete,
        'human_approved' => PipelineStepState.humanApproved,
        'running' || 'scheduled' => PipelineStepState.running,
        'failed' => PipelineStepState.failed,
        _ => PipelineStepState.pending,
      };
}

/// Run-level state, derived engine-side: failed > awaiting > running > done >
/// in-progress > idle.
enum PipelineRunState { idle, running, awaitingApproval, inProgress, done, failed }

extension PipelineRunStateX on PipelineRunState {
  String get label => switch (this) {
        PipelineRunState.idle => 'Idle',
        PipelineRunState.running => 'Running',
        PipelineRunState.awaitingApproval => 'Awaiting approval',
        PipelineRunState.inProgress => 'In progress',
        PipelineRunState.done => 'Done',
        PipelineRunState.failed => 'Failed',
      };

  /// The run has stopped for good.
  bool get isTerminal =>
      this == PipelineRunState.done || this == PipelineRunState.failed;

  static PipelineRunState fromWire(String? s) => switch (s) {
        'failed' => PipelineRunState.failed,
        'awaiting_approval' => PipelineRunState.awaitingApproval,
        'running' => PipelineRunState.running,
        'done' => PipelineRunState.done,
        'in_progress' => PipelineRunState.inProgress,
        _ => PipelineRunState.idle,
      };
}

/// One compiled step inside a pipeline status snapshot.
@immutable
class PipelineStep {
  final String stepId;
  final String title;
  final PipelineStepState status;
  final String stage;
  final String executor;
  final List<String> dependsOn;
  final String? aiResult;
  final String? error;
  final double? durationSecs;
  final double costDollars;

  /// This step is a producer-review hold: only [waitingOn] can clear it.
  final bool isReviewHold;

  /// The user a review hold waits on (null when unset / not a review hold).
  final String? waitingOn;

  /// Parked on the PRE-dispatch side-effect gate — the operator may release
  /// this one regardless of [waitingOn].
  final bool isLocalGate;

  const PipelineStep({
    required this.stepId,
    required this.title,
    required this.status,
    this.stage = '',
    this.executor = '',
    this.dependsOn = const [],
    this.aiResult,
    this.error,
    this.durationSecs,
    this.costDollars = 0,
    this.isReviewHold = false,
    this.waitingOn,
    this.isLocalGate = false,
  });
}

/// The persisted single-run snapshot for a board (`cyan_pipeline_status`).
@immutable
class PipelineStatus {
  final String boardId;
  final String? runId;
  final PipelineRunState status;
  final int totalSteps;
  final int aiComplete;
  final int humanApproved;
  final int running;
  final int failed;
  final int pending;
  final int progressPct;
  final double totalCostDollars;

  /// The step id currently holding the gate, if any.
  final String? awaitingStep;
  final List<PipelineStep> steps;

  /// Engine-side error envelope (`{"error": …}`); null on a clean read.
  final String? error;

  const PipelineStatus({
    required this.boardId,
    this.runId,
    this.status = PipelineRunState.idle,
    this.totalSteps = 0,
    this.aiComplete = 0,
    this.humanApproved = 0,
    this.running = 0,
    this.failed = 0,
    this.pending = 0,
    this.progressPct = 0,
    this.totalCostDollars = 0,
    this.awaitingStep,
    this.steps = const [],
    this.error,
  });
}

/// The immediate acknowledgement a background launch returns (compile / run).
/// The work itself lands later as engine events — this is the "accepted" reply.
@immutable
class PipelineLaunch {
  final String boardId;

  /// Wire status: "compiling" / "started", or empty on an error envelope.
  final String status;
  final String message;
  final String? error;

  const PipelineLaunch({
    required this.boardId,
    this.status = '',
    this.message = '',
    this.error,
  });

  /// The engine accepted the launch.
  bool get accepted => error == null && status.isNotEmpty;
}

/// The `{"success":…,"error":…}` envelope the reviewer-scoped gate calls return.
@immutable
class PipelineAck {
  final bool success;
  final String? error;

  const PipelineAck({required this.success, this.error});

  static const PipelineAck ok = PipelineAck(success: true);
}

/// The result of dispatching ONE step against a locally-bound plugin.
@immutable
class StepRunResult {
  final bool success;
  final String summary;
  final int findings;

  /// The step stopped on a human gate rather than failing.
  final bool isGated;

  /// The step PARKED (amber, human-actionable) — e.g. nothing confirmed yet.
  final bool isParked;

  /// What the park is waiting for, when [isParked].
  final String? awaiting;
  final String? error;

  const StepRunResult({
    required this.success,
    this.summary = '',
    this.findings = 0,
    this.isGated = false,
    this.isParked = false,
    this.awaiting,
    this.error,
  });
}

/// Which way `cyan_step_edit_travel` walks a step's edit history. The wire
/// value is the engine's `direction` int: 0 = undo, anything else = redo.
enum StepTravelDirection { undo, redo }

extension StepTravelDirectionX on StepTravelDirection {
  int get wireValue => this == StepTravelDirection.undo ? 0 : 1;
}

/// The restored step body after an undo/redo, plus the remaining depths so the
/// editor can enable/disable its arrows.
@immutable
class StepTravel {
  final String content;
  final int undoDepth;
  final int redoDepth;

  /// "nothing to undo" / "cell not found on this board" / … — null on success.
  final String? error;

  const StepTravel({
    this.content = '',
    this.undoDepth = 0,
    this.redoDepth = 0,
    this.error,
  });

  bool get travelled => error == null;
  bool get canUndo => undoDepth > 0;
  bool get canRedo => redoDepth > 0;
}

/// The deploy-state row for a board (`cyan_board_workflow_state`). Absent rows
/// read back as the authoring default: editable, unlocked, no dashboard.
@immutable
class BoardWorkflowState {
  final String boardId;

  /// The workflow is live, not just authored.
  final bool isDeployed;

  /// A live dashboard exists → show the dashboard face, not the editor.
  final bool hasDashboard;

  /// Edits are locked (set on deploy).
  final bool isLocked;
  final DateTime? updatedAt;

  /// Set when the state could not be READ at all. Distinguishes "the engine
  /// says this board is undeployed" from "nobody answered" — the flags below
  /// are meaningless when this is non-null.
  final String? error;

  const BoardWorkflowState({
    required this.boardId,
    this.isDeployed = false,
    this.hasDashboard = false,
    this.isLocked = false,
    this.updatedAt,
    this.error,
  });
}

// ---------------------------------------------------------------------------
// Plugin config — PLUGIN_CREDENTIAL_ONBOARDING stage D (the settings sheet the
// stage-A/C FFI was built for). The engine reference is plugin_config.rs.
// ---------------------------------------------------------------------------

/// Does [key] look like secret material?
///
/// A verbatim port of the engine's `plugin_config::looks_secret` — the SAME
/// vocabulary, so the app's judgement and the engine's never disagree. This is
/// used to shape the UI (a secret-looking key gets a secure field, never a
/// plain one); the engine's write API remains the authority that REFUSES it.
/// Keeping the list here in sync is the whole point: the user is warned before
/// the round trip instead of only by the refusal.
bool pluginConfigKeyLooksSecret(String key) {
  final k = key.toLowerCase();
  const markers = [
    'token',
    'secret',
    'password',
    'passwd',
    'api_key',
    'apikey',
    'private',
  ];
  return markers.any(k.contains);
}

/// The non-secret config rows the engine holds for one (group, plugin), as
/// `cyan_plugin_config_get` answers with no `key`: `{"ok":true,"values":{…}}`.
///
/// Workflow rows already shadow tenant rows by the time they get here — the
/// engine resolves most-specific-wins, this never re-resolves it.
@immutable
class PluginConfig {
  final String pluginId;

  /// key -> value, ordered by key exactly as the engine's `BTreeMap` sorts it.
  final Map<String, String> values;

  /// The engine's refusal, when the read itself failed. Null on success.
  final String? error;

  const PluginConfig({
    required this.pluginId,
    this.values = const {},
    this.error,
  });

  /// Engine unreachable / the call returned no payload at all.
  const PluginConfig.unavailable(this.pluginId)
      : values = const {},
        error = 'engine unavailable';

  bool get isEmpty => values.isEmpty;

  /// `{"ok":true,"values":{k:v}}` or `{"ok":false,"error":"…"}`.
  factory PluginConfig.fromJson(String pluginId, Map<String, dynamic> j) {
    if (j['ok'] != true) {
      return PluginConfig(
        pluginId: pluginId,
        error: j['error'] as String? ?? 'unknown error',
      );
    }
    final raw = (j['values'] as Map<String, dynamic>? ?? const {});
    final keys = raw.keys.toList()..sort();
    return PluginConfig(
      pluginId: pluginId,
      values: {for (final k in keys) k: raw[k]?.toString() ?? ''},
    );
  }
}

/// What one `cyan_plugin_config_set` answered. A refusal is carried VERBATIM —
/// the secret-key guard's message names the key and points at the vault, and
/// that text is what the user must read, so it is never re-worded here.
@immutable
class PluginConfigWrite {
  final bool ok;
  final String? error;

  const PluginConfigWrite.ok()
      : ok = true,
        error = null;

  const PluginConfigWrite.refused(String this.error) : ok = false;

  /// Engine unreachable / the call returned no payload at all.
  const PluginConfigWrite.unavailable()
      : ok = false,
        error = 'engine unavailable';

  /// `{"ok":true}` or `{"ok":false,"error":"…"}`.
  factory PluginConfigWrite.fromJson(Map<String, dynamic> j) => j['ok'] == true
      ? const PluginConfigWrite.ok()
      : PluginConfigWrite.refused(
          j['error'] as String? ?? 'the engine refused the write');
}

/// The signed-in identity on THIS device: `cyan_get_my_node_id` +
/// `cyan_get_my_profile`. The shell's status bar shows [displayName]; the
/// Settings / Identity face additionally states [nodeId] verbatim.
@immutable
class DeviceProfile {
  /// This node's stable mesh id. Never empty — a device with no identity has
  /// NO profile (`myProfile()` answers null), it does not have a blank one.
  final String nodeId;

  final String displayName;
  final String? avatarPath;

  const DeviceProfile({
    required this.nodeId,
    this.displayName = '',
    this.avatarPath,
  });

  /// The `cyan_get_my_profile` payload; [nodeId] rides alongside because the
  /// engine answers it from its own verb.
  factory DeviceProfile.fromJson(Map<String, dynamic> j, {String? nodeId}) {
    final avatar = j['avatar_path'] as String?;
    return DeviceProfile(
      nodeId: nodeId ?? j['node_id'] as String? ?? '',
      displayName: j['display_name'] as String? ?? '',
      avatarPath: (avatar == null || avatar.isEmpty) ? null : avatar,
    );
  }

  /// The one name to put on screen for this device: the display name when the
  /// engine has one, else the node id. NEVER blank — a device with an identity
  /// but no chosen name is still named, by the id the mesh knows it by.
  String get label => displayName.trim().isEmpty ? nodeId : displayName.trim();

  /// "Rick Ames" -> "RA"; a nameless identity falls back to the node id's
  /// first two characters, exactly as the SwiftUI status bar does.
  String get initials {
    final name = displayName.trim();
    if (name.isEmpty) {
      return nodeId.substring(0, nodeId.length < 2 ? nodeId.length : 2)
          .toUpperCase();
    }
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0].substring(0, 1) + parts[1].substring(0, 1))
          .toUpperCase();
    }
    return name.substring(0, name.length < 2 ? name.length : 2).toUpperCase();
  }
}

// ---------------------------------------------------------------------------
// Roster (`cyan_get_group_members`)
// ---------------------------------------------------------------------------

/// One PERSISTENT member of a group. The engine's roster outlives a session —
/// a member who left keeps their cached name and last-seen rather than
/// vanishing — so [online] is a live overlay on a durable row, never the row's
/// existence condition.
@immutable
class GroupMember {
  final String peerId;

  /// The cached profile name, or null when nothing on the mesh has published
  /// one yet. NEVER defaulted to the peer id — the caller decides how to render
  /// a nameless member.
  final String? name;

  final String? avatar;
  final bool online;

  /// Unix seconds. 0 when the mesh has never seen this member.
  final int lastSeen;

  const GroupMember({
    required this.peerId,
    this.name,
    this.avatar,
    this.online = false,
    this.lastSeen = 0,
  });

  /// One element of the `cyan_get_group_members` array.
  factory GroupMember.fromJson(Map<String, dynamic> j) {
    final name = j['name'] as String?;
    final avatar = j['avatar'] as String?;
    return GroupMember(
      peerId: j['peer_id'] as String? ?? '',
      name: (name == null || name.isEmpty) ? null : name,
      avatar: (avatar == null || avatar.isEmpty) ? null : avatar,
      online: j['online'] as bool? ?? false,
      lastSeen: (j['last_seen'] as num?)?.toInt() ?? 0,
    );
  }
}

// ---------------------------------------------------------------------------
// Notes (`cyan_note_list_scoped` / `cyan_note_put_scoped`)
// ---------------------------------------------------------------------------

/// The engine's `NoteDTO`. [boardId] is the scope ANCHOR (a board / group /
/// tenant id depending on [scope]), not necessarily a board.
@immutable
class CyanNote {
  final String id;
  final String boardId;
  final String tenantId;
  final String authorId;
  final String authorName;
  final String text;
  final int createdAt;
  final int updatedAt;

  /// `tenant` | `group` | `board` | … — see the engine's `NOTE_SCOPE_VOCAB`.
  final String scope;

  /// `constitution` | `preference` | `editor-note` | `decision` | …
  final String kind;

  /// The author's CRAFT role at authoring time. PROVENANCE, not authorization,
  /// and null whenever the engine recorded none — never inferred here.
  final String? authorRole;

  const CyanNote({
    required this.id,
    this.boardId = '',
    this.tenantId = '',
    this.authorId = '',
    this.authorName = '',
    this.text = '',
    this.createdAt = 0,
    this.updatedAt = 0,
    this.scope = 'board',
    this.kind = 'editor-note',
    this.authorRole,
  });

  factory CyanNote.fromJson(Map<String, dynamic> j) {
    final role = j['author_role'] as String?;
    return CyanNote(
      id: j['id'] as String? ?? '',
      boardId: j['board_id'] as String? ?? '',
      tenantId: j['tenant_id'] as String? ?? '',
      authorId: j['author_id'] as String? ?? '',
      authorName: j['author_name'] as String? ?? '',
      text: j['text'] as String? ?? '',
      createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (j['updated_at'] as num?)?.toInt() ?? 0,
      scope: j['scope'] as String? ?? 'board',
      kind: j['kind'] as String? ?? 'editor-note',
      authorRole: (role == null || role.isEmpty) ? null : role,
    );
  }
}

// ---------------------------------------------------------------------------
// Timecoded notes (`cyan_load_timecode_notes` / `cyan_save_timecode_note` /
// `cyan_act_on_timecode_note`)
// ---------------------------------------------------------------------------

/// Something the engine's AI already flagged near a timecode. Carried ON the
/// note so the AI rail can be told what NOT to re-report — dedup context, not
/// a finding of its own.
@immutable
class TimecodeAiFlag {
  final double timecodeSeconds;
  final String description;

  /// `info` | `warning` | `critical`.
  final String severity;

  /// The pipeline step that raised it; empty when none did.
  final String sourceStep;
  final bool resolved;

  const TimecodeAiFlag({
    this.timecodeSeconds = 0,
    this.description = '',
    this.severity = 'info',
    this.sourceStep = '',
    this.resolved = false,
  });

  factory TimecodeAiFlag.fromJson(Map<String, dynamic> j) => TimecodeAiFlag(
        timecodeSeconds: (j['timecode_seconds'] as num?)?.toDouble() ?? 0,
        description: j['description'] as String? ?? '',
        severity: j['severity'] as String? ?? 'info',
        sourceStep: j['source_step'] as String? ?? '',
        resolved: j['resolved'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'timecode_seconds': timecodeSeconds,
        'description': description,
        'severity': severity,
        'source_step': sourceStep,
        'resolved': resolved,
      };
}

/// The engine's `TimecodeNote` — a review note pinned to a moment in an asset.
///
/// The WHOLE note travels as JSON in both directions, so this carries a
/// [toJson] as well: a save round-trips what a load produced, and the AI rail
/// is handed the same shape it will re-save.
@immutable
class TimecodeNote {
  final String id;
  final String boardId;

  /// Where in the asset the note is pinned. Seconds, not frames — the engine
  /// orders notes by this.
  final double timecodeSeconds;
  final String content;

  /// `comment` | `qc_issue` | `revision` | `approved` | `action`.
  final String noteType;
  final String author;
  final double createdAt;

  /// The note this one replies to; null for a root note.
  final String? replyTo;

  /// Replies below this note, as the ENGINE cached the count. Never recomputed
  /// here — a client tally would disagree with what synced.
  final int threadCount;

  // ---- pipeline context ----
  final String? pipelineStepId;

  /// `pre_exec` | `during` | `review` | `post_approval`.
  final String? pipelinePhase;
  final bool aiReviewed;
  final bool humanApproved;

  // ---- AI action ----
  /// Which skill to invoke (`dub`, `subtitle`, `qc`), or null when the note
  /// asks for nothing.
  final String? actionSkill;

  /// `pending` | `sent` | `complete` | `rejected`.
  final String? actionStatus;

  /// The AI's raw answer, as the engine stored it.
  final String? actionResult;
  final String? actionModel;

  /// What the AI already found near this timecode — dedup context for the
  /// action rail.
  final List<TimecodeAiFlag> aiFlagsNearby;

  const TimecodeNote({
    required this.id,
    this.boardId = '',
    this.timecodeSeconds = 0,
    this.content = '',
    this.noteType = 'comment',
    this.author = '',
    this.createdAt = 0,
    this.replyTo,
    this.threadCount = 0,
    this.pipelineStepId,
    this.pipelinePhase,
    this.aiReviewed = false,
    this.humanApproved = false,
    this.actionSkill,
    this.actionStatus,
    this.actionResult,
    this.actionModel,
    this.aiFlagsNearby = const [],
  });

  factory TimecodeNote.fromJson(Map<String, dynamic> j) {
    String? opt(String key) {
      final v = j[key] as String?;
      return (v == null || v.isEmpty) ? null : v;
    }

    return TimecodeNote(
      id: j['id'] as String? ?? '',
      boardId: j['board_id'] as String? ?? '',
      timecodeSeconds: (j['timecode_seconds'] as num?)?.toDouble() ?? 0,
      content: j['content'] as String? ?? '',
      noteType: j['note_type'] as String? ?? 'comment',
      author: j['author'] as String? ?? '',
      createdAt: (j['created_at'] as num?)?.toDouble() ?? 0,
      replyTo: opt('reply_to'),
      threadCount: (j['thread_count'] as num?)?.toInt() ?? 0,
      pipelineStepId: opt('pipeline_step_id'),
      pipelinePhase: opt('pipeline_phase'),
      aiReviewed: j['ai_reviewed'] as bool? ?? false,
      humanApproved: j['human_approved'] as bool? ?? false,
      actionSkill: opt('action_skill'),
      actionStatus: opt('action_status'),
      actionResult: opt('action_result'),
      actionModel: opt('action_model'),
      aiFlagsNearby: [
        for (final f in (j['ai_flags_nearby'] as List? ?? const []))
          if (f is Map<String, dynamic>) TimecodeAiFlag.fromJson(f),
      ],
    );
  }

  /// The wire shape the save/act verbs parse. Every optional key is written —
  /// as an explicit null when unset — because the engine deserializes into a
  /// struct whose `Option` fields read a null exactly as "none".
  Map<String, dynamic> toJson() => {
        'id': id,
        'board_id': boardId,
        'timecode_seconds': timecodeSeconds,
        'content': content,
        'note_type': noteType,
        'author': author,
        'created_at': createdAt,
        'reply_to': replyTo,
        'thread_count': threadCount,
        'pipeline_step_id': pipelineStepId,
        'pipeline_phase': pipelinePhase,
        'ai_reviewed': aiReviewed,
        'human_approved': humanApproved,
        'action_skill': actionSkill,
        'action_status': actionStatus,
        'action_result': actionResult,
        'action_model': actionModel,
        'ai_flags_nearby': [for (final f in aiFlagsNearby) f.toJson()],
      };
}

/// What the AI rail answered for one timecoded note. The engine has ALREADY
/// re-saved the note with [result] attached by the time this returns, so the
/// caller re-reads the list rather than patching its own copy.
@immutable
class TimecodeNoteAction {
  final bool success;

  /// The model's raw answer — the engine asks for JSON but never guarantees
  /// it, so this stays the string it returned.
  final String result;
  final String? error;

  const TimecodeNoteAction({
    this.success = false,
    this.result = '',
    this.error,
  });

  factory TimecodeNoteAction.fromJson(Map<String, dynamic> j) {
    final error = j['error'] as String?;
    return TimecodeNoteAction(
      success: j['success'] as bool? ?? false,
      result: j['result'] as String? ?? '',
      error: (error == null || error.isEmpty) ? null : error,
    );
  }
}

// ---------------------------------------------------------------------------
// Constitution (`cyan_constitution_resolved` / `cyan_constitution_effective`)
// ---------------------------------------------------------------------------

/// One note that fed the merged chain, as the resolve reports its provenance.
@immutable
class ConstitutionContribution {
  final String id;
  final String scope;
  final String kind;
  final int updatedAt;

  const ConstitutionContribution({
    required this.id,
    this.scope = '',
    this.kind = '',
    this.updatedAt = 0,
  });

  factory ConstitutionContribution.fromJson(Map<String, dynamic> j) =>
      ConstitutionContribution(
        id: j['id'] as String? ?? '',
        scope: j['scope'] as String? ?? '',
        kind: j['kind'] as String? ?? '',
        updatedAt: (j['updated_at'] as num?)?.toInt() ?? 0,
      );
}

/// The on-device PREVIEW resolve: the merged constitution markdown, the soft
/// preferences kept APART from it, the chain hash and the provenance.
///
/// An empty resolve still carries a real [hash] (empty ≠ unknown); an [error]
/// carries NO hash at all, which is how the two are told apart.
@immutable
class ResolvedConstitution {
  final String markdown;
  final String preferences;
  final String hash;
  final List<ConstitutionContribution> contributing;
  final String? error;

  const ResolvedConstitution({
    this.markdown = '',
    this.preferences = '',
    this.hash = '',
    this.contributing = const [],
    this.error,
  });

  factory ResolvedConstitution.fromJson(Map<String, dynamic> j) {
    final error = j['error'] as String?;
    if (error != null && error.isNotEmpty) {
      return ResolvedConstitution(error: error);
    }
    final rows = j['contributing'];
    return ResolvedConstitution(
      markdown: j['markdown'] as String? ?? '',
      preferences: j['preferences'] as String? ?? '',
      hash: j['hash'] as String? ?? '',
      contributing: rows is List
          ? [
              for (final r in rows)
                if (r is Map<String, dynamic>)
                  ConstitutionContribution.fromJson(r),
            ]
          : const [],
    );
  }
}

/// One HARD constraint the engine classified off the chain — a rule a run may
/// not trade away. [text] is the note text VERBATIM, never a rewording.
@immutable
class HardRule {
  final String id;
  final String scope;

  /// `legal` | `technical` | `delivery`.
  final String category;
  final String text;

  const HardRule({
    required this.id,
    this.scope = '',
    this.category = '',
    this.text = '',
  });

  factory HardRule.fromJson(Map<String, dynamic> j) => HardRule(
        id: j['id'] as String? ?? '',
        scope: j['scope'] as String? ?? '',
        category: j['category'] as String? ?? '',
        text: j['text'] as String? ?? '',
      );
}

/// The cloud-bound constitution read: the merged markdown, its hash, the ids
/// that fed it, and the HARD rules classified off the same chain.
@immutable
class EffectiveConstitution {
  final String markdown;
  final String hash;
  final List<String> contributingIds;
  final List<HardRule> hard;
  final String? error;

  const EffectiveConstitution({
    this.markdown = '',
    this.hash = '',
    this.contributingIds = const [],
    this.hard = const [],
    this.error,
  });

  factory EffectiveConstitution.fromJson(Map<String, dynamic> j) {
    final error = j['error'] as String?;
    if (error != null && error.isNotEmpty) {
      return EffectiveConstitution(error: error);
    }
    final ids = j['contributing_ids'];
    final hard = j['hard'];
    return EffectiveConstitution(
      markdown: j['markdown'] as String? ?? '',
      hash: j['hash'] as String? ?? '',
      contributingIds: ids is List ? [for (final i in ids) '$i'] : const [],
      hard: hard is List
          ? [
              for (final r in hard)
                if (r is Map<String, dynamic>) HardRule.fromJson(r),
            ]
          : const [],
    );
  }
}

// ---------------------------------------------------------------------------
// Craft-role selector (`cyan_selector_resolve`)
// ---------------------------------------------------------------------------

/// A selector resolve, or the engine's REFUSAL of one. A refusal carries the
/// vocabulary it would have accepted, which is the documented way to read the
/// catalog — the UI never keeps its own copy of a vocabulary the engine owns.
@immutable
class SelectorResolution {
  final String? error;

  /// What the engine WOULD accept — populated on a refusal.
  final List<String> allowed;

  /// The value that was refused.
  final String? given;

  /// The landing surface the resolve routes this role to, on success.
  final String primarySurface;

  const SelectorResolution({
    this.error,
    this.allowed = const [],
    this.given,
    this.primarySurface = '',
  });

  bool get resolved => error == null;

  factory SelectorResolution.fromJson(Map<String, dynamic> j) {
    final allowed = j['allowed'];
    return SelectorResolution(
      error: j['error'] as String?,
      allowed: allowed is List ? [for (final a in allowed) '$a'] : const [],
      given: j['given'] as String?,
      primarySurface: j['primary_surface'] as String? ?? '',
    );
  }
}

// ---------------------------------------------------------------------------
// SSO session grants (`cyan_sso_*`)
// ---------------------------------------------------------------------------

/// An installed broker-minted session, or the engine's refusal to install one.
/// A refusal leaves the PREVIOUSLY installed session untouched, so an
/// inactive result is "this grant did not take", never "the device signed out".
@immutable
class SsoSession {
  final bool active;

  /// The tenant the grant is scoped to.
  final String tenant;

  /// The role it confers, in the engine's own vocabulary.
  final String role;

  /// Unix seconds at which the grant stops verifying.
  final int exp;

  /// Why the install was refused; null once [active].
  final String? reason;

  const SsoSession({
    required this.active,
    this.tenant = '',
    this.role = '',
    this.exp = 0,
    this.reason,
  });

  /// No session installed — the engine's fail-open default.
  const SsoSession.signedOut()
      : active = false,
        tenant = '',
        role = '',
        exp = 0,
        reason = null;

  factory SsoSession.fromJson(Map<String, dynamic> j) => SsoSession(
        active: j['active'] as bool? ?? false,
        tenant: j['tenant'] as String? ?? '',
        role: j['role'] as String? ?? '',
        exp: (j['exp'] as num?)?.toInt() ?? 0,
        reason: j['reason'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Anonymous sessions (`cyan_*_anonymous_*`)
// ---------------------------------------------------------------------------

/// Whether this device is behind a handle in ONE scope. Anonymity is per
/// scope by construction, and revealing is ONE WAY.
@immutable
class AnonymousStatus {
  final bool anonymous;

  /// The handle peers see while masked; null when visible.
  final String? handle;

  /// The handle has been bound back to this device's real identity.
  final bool revealed;

  /// Nobody answered. The engine reports "no session in this scope" as a real
  /// object, so an error here is NOT the same as [AnonymousStatus.none].
  final String? error;

  const AnonymousStatus({
    this.anonymous = false,
    this.handle,
    this.revealed = false,
    this.error,
  });

  /// No session in this scope — visible, under this device's own name.
  const AnonymousStatus.none()
      : anonymous = false,
        handle = null,
        revealed = false,
        error = null;

  factory AnonymousStatus.fromJson(Map<String, dynamic> j) {
    final handle = j['handle'] as String?;
    return AnonymousStatus(
      anonymous: j['anonymous'] as bool? ?? false,
      handle: (handle == null || handle.isEmpty) ? null : handle,
      revealed: j['revealed'] as bool? ?? false,
    );
  }
}

/// A freshly minted (or freshly revealed) anonymous session. The engine mints
/// the handle — the screen never invents one.
@immutable
class AnonymousSession {
  final String handle;
  final String scopeId;
  final String ephemeralKey;

  /// Set once the session has been bound back to the real identity.
  final bool revealed;

  /// The real display name, published only by a reveal.
  final String? realName;

  const AnonymousSession({
    this.handle = '',
    this.scopeId = '',
    this.ephemeralKey = '',
    this.revealed = false,
    this.realName,
  });

  factory AnonymousSession.fromJson(Map<String, dynamic> j) {
    final realName = j['real_name'] as String?;
    return AnonymousSession(
      handle: j['handle'] as String? ?? '',
      scopeId: j['scope_id'] as String? ?? '',
      ephemeralKey: j['ephemeral_key'] as String? ?? '',
      revealed: j['revealed'] as bool? ?? false,
      realName: (realName == null || realName.isEmpty) ? null : realName,
    );
  }
}

// ---------------------------------------------------------------------------
// Capability grants + portable group bundles
// ---------------------------------------------------------------------------

/// A minted, signed capability grant — or the engine's refusal to mint one
/// (only a group Owner/Admin may issue).
@immutable
class GrantQrIssue {
  final bool success;

  /// The signed QR payload.
  final String qr;

  /// The role the grant confers.
  final String role;

  /// Unix seconds at which the grant stops verifying.
  final int expiry;
  final String nonce;
  final String? error;

  const GrantQrIssue({
    required this.success,
    this.qr = '',
    this.role = '',
    this.expiry = 0,
    this.nonce = '',
    this.error,
  });

  factory GrantQrIssue.fromJson(Map<String, dynamic> j) => GrantQrIssue(
        success: j['success'] as bool? ?? false,
        qr: j['qr'] as String? ?? '',
        role: j['role'] as String? ?? '',
        expiry: (j['expiry'] as num?)?.toInt() ?? 0,
        nonce: j['nonce'] as String? ?? '',
        error: j['error'] as String?,
      );
}

/// The outcome of scanning a grant QR. A success has JOINED the group; a
/// forged, expired or out-of-scope payload comes back as a refusal FROM THE
/// ENGINE — the screen never adjudicates a grant itself.
@immutable
class GrantScanResult {
  final bool success;
  final String groupId;
  final String groupName;
  final String? error;

  const GrantScanResult({
    required this.success,
    this.groupId = '',
    this.groupName = '',
    this.error,
  });

  factory GrantScanResult.fromJson(Map<String, dynamic> j) => GrantScanResult(
        success: j['success'] as bool? ?? false,
        groupId: j['group_id'] as String? ?? '',
        groupName: j['group_name'] as String? ?? '',
        error: j['error'] as String?,
      );
}

/// A sealed, portable `.cyangroup` export. The bundle is sealed TO one
/// recipient key, so it re-imports on that device and nowhere else.
@immutable
class GroupExportResult {
  final bool success;
  final String groupId;

  /// The bundle body itself.
  final String bundle;

  /// Where the engine also dropped its own copy, when it could.
  final String path;
  final String? error;

  const GroupExportResult({
    required this.success,
    this.groupId = '',
    this.bundle = '',
    this.path = '',
    this.error,
  });

  factory GroupExportResult.fromJson(Map<String, dynamic> j) =>
      GroupExportResult(
        success: j['success'] as bool? ?? false,
        groupId: j['group_id'] as String? ?? '',
        bundle: j['bundle'] as String? ?? '',
        path: j['path'] as String? ?? '',
        error: j['error'] as String?,
      );
}

/// The outcome of importing a `.cyangroup` bundle — signature, grant scope and
/// recipient key all verified by the engine.
@immutable
class GroupImportResult {
  final bool success;
  final String groupId;
  final String? error;

  const GroupImportResult({
    required this.success,
    this.groupId = '',
    this.error,
  });

  factory GroupImportResult.fromJson(Map<String, dynamic> j) =>
      GroupImportResult(
        success: j['success'] as bool? ?? false,
        groupId: j['group_id'] as String? ?? '',
        error: j['error'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Templates (`cyan_template_*` / `cyan_workflow_from_template`)
// ---------------------------------------------------------------------------

/// One pre-written step inside a template: the plain-English step [text] plus
/// the plugin it runs on. Cloning materializes one real authorable step cell
/// per step, verbatim.
@immutable
class TemplateStep {
  final String text;

  /// The plugin bound to this step (`"contido"`), or null when unbound.
  final String? plugin;

  /// The display stage this step belongs to — DISPLAY-ONLY. Compile derives the
  /// real stage from the cell text and accepts no hint, so this never travels
  /// into a cloned cell.
  final String? stage;

  const TemplateStep({required this.text, this.plugin, this.stage});

  factory TemplateStep.fromJson(Map<String, dynamic> j) {
    final plugin = j['plugin'] as String?;
    final stage = j['stage'] as String?;
    return TemplateStep(
      text: j['text'] as String? ?? '',
      plugin: (plugin == null || plugin.isEmpty) ? null : plugin,
      stage: (stage == null || stage.isEmpty) ? null : stage,
    );
  }

  /// The wire shape the save verbs parse. An omitted key IS the engine's
  /// `None`, so an unbound step carries no `plugin` at all rather than an
  /// empty one.
  Map<String, dynamic> toJson() => {
        'text': text,
        if (plugin != null) 'plugin': plugin,
        if (stage != null) 'stage': stage,
      };
}

/// One plugin a roletype template names.
@immutable
class TemplatePlugin {
  final String id;

  /// `live` | `roadmap` — whether the plugin exists yet. A DIFFERENT axis from
  /// [autoInstall]: a roadmap plugin may still auto-install.
  final String status;

  /// `device` | `cloud` | `both`.
  final String execution;

  /// The ONE tool whose installed presence marks the plugin installed.
  final String? flagshipTool;
  final String? spec;

  /// This plugin is in the template's DECLARED auto-install set — cloning the
  /// template installs it if it is missing.
  final bool autoInstall;

  const TemplatePlugin({
    required this.id,
    this.status = 'live',
    this.execution = 'device',
    this.flagshipTool,
    this.spec,
    this.autoInstall = false,
  });

  factory TemplatePlugin.fromJson(Map<String, dynamic> j) {
    final tool = j['flagship_tool'] as String?;
    final spec = j['spec'] as String?;
    return TemplatePlugin(
      id: j['id'] as String? ?? '',
      status: j['status'] as String? ?? '',
      execution: j['execution'] as String? ?? '',
      flagshipTool: (tool == null || tool.isEmpty) ? null : tool,
      spec: (spec == null || spec.isEmpty) ? null : spec,
      autoInstall: j['auto_install'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status,
        'execution': execution,
        if (flagshipTool != null) 'flagship_tool': flagshipTool,
        if (spec != null) 'spec': spec,
        if (autoInstall) 'auto_install': true,
      };
}

/// One note a template CARRIES: the seed a clone lands in the target board's
/// notes, editable afterwards like any note. Role rides along so role-based
/// notes stay apparent.
@immutable
class TemplateNote {
  /// `constitution` | `preference` | `editor-note` | …
  final String kind;
  final String authorRole;
  final String authorName;
  final String text;

  const TemplateNote({
    required this.kind,
    this.authorRole = '',
    this.authorName = '',
    this.text = '',
  });

  factory TemplateNote.fromJson(Map<String, dynamic> j) => TemplateNote(
        kind: j['kind'] as String? ?? '',
        authorRole: j['author_role'] as String? ?? '',
        authorName: j['author_name'] as String? ?? '',
        text: j['text'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'author_role': authorRole,
        'author_name': authorName,
        'text': text,
      };
}

/// A workflow TEMPLATE — a pre-written English workflow you clone into a board.
/// Two sources: built-in seeds ([source] `builtin`, tenant-agnostic) and the
/// tenant's own save-as-template results (`user`). Cloning never mutates one.
@immutable
class CyanTemplate {
  final String id;

  /// The tenant (group) that owns a user template. Empty for a built-in seed,
  /// which is a global default surfaced to every tenant.
  final String tenantId;
  final String name;
  final String description;

  /// `builtin` (media seed), `builtin:postprod` / `builtin:roletype` (the other
  /// tenant-agnostic catalogs) or `user` (save-as-template).
  final String source;
  final List<TemplateStep> steps;
  final int createdAt;

  /// The roletype format (`promo` | `commercial` | …). Null for a LEGACY
  /// template, which lists but never enters the selector.
  final String? formatType;

  /// The stage rail the selector UI renders.
  final List<String> stages;

  /// The note kinds this format works from.
  final List<String> noteKinds;
  final List<TemplatePlugin> plugins;

  /// `mvp` | `extensible`.
  final String? maturity;

  /// The roletype catalog version at save time; null for a pre-roletype row.
  final String? catalogVersion;

  /// `tenant` live; `user`/`group` stored-but-treated-as-tenant.
  final String? scope;
  final List<TemplateNote> notes;

  const CyanTemplate({
    required this.id,
    this.tenantId = '',
    this.name = '',
    this.description = '',
    this.source = '',
    this.steps = const [],
    this.createdAt = 0,
    this.formatType,
    this.stages = const [],
    this.noteKinds = const [],
    this.plugins = const [],
    this.maturity,
    this.catalogVersion,
    this.scope,
    this.notes = const [],
  });

  /// A tenant-agnostic seed rather than one of the tenant's own saves. The
  /// engine keeps its seed catalogs in separate lanes (`builtin`,
  /// `builtin:postprod`, `builtin:roletype`) — all of them are global.
  bool get isBuiltin => source.startsWith('builtin');

  /// The ids of the plugins cloning this template installs if they are missing,
  /// in declaration order. A roadmap-only mention is NOT in the set.
  List<String> get autoInstallSet =>
      [for (final p in plugins) if (p.autoInstall) p.id];

  factory CyanTemplate.fromJson(Map<String, dynamic> j) {
    final formatType = j['format_type'] as String?;
    final maturity = j['maturity'] as String?;
    final catalogVersion = j['catalog_version'] as String?;
    final scope = j['scope'] as String?;
    return CyanTemplate(
      id: j['id'] as String? ?? '',
      tenantId: j['tenant_id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      description: j['description'] as String? ?? '',
      source: j['source'] as String? ?? '',
      steps: _templateSteps(j['steps']),
      createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
      formatType:
          (formatType == null || formatType.isEmpty) ? null : formatType,
      stages: _strings(j['stages']),
      noteKinds: _strings(j['note_kinds']),
      plugins: _templatePlugins(j['plugins']),
      maturity: (maturity == null || maturity.isEmpty) ? null : maturity,
      catalogVersion: (catalogVersion == null || catalogVersion.isEmpty)
          ? null
          : catalogVersion,
      scope: (scope == null || scope.isEmpty) ? null : scope,
      notes: _templateNotes(j['notes']),
    );
  }

  /// The `template_json` body `cyan_template_save_v2` reads. The SERVER stamps
  /// id / tenant_id / source / created_at / catalog_version, so they are left
  /// off rather than sent and ignored.
  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'steps': [for (final s in steps) s.toJson()],
        if (formatType != null) 'format_type': formatType,
        if (stages.isNotEmpty) 'stages': stages,
        if (noteKinds.isNotEmpty) 'note_kinds': noteKinds,
        if (plugins.isNotEmpty)
          'plugins': [for (final p in plugins) p.toJson()],
        if (maturity != null) 'maturity': maturity,
        if (scope != null) 'scope': scope,
        if (notes.isNotEmpty) 'notes': [for (final n in notes) n.toJson()],
      };

  static List<TemplateStep> _templateSteps(dynamic raw) => raw is List
      ? [
          for (final s in raw)
            if (s is Map<String, dynamic>) TemplateStep.fromJson(s),
        ]
      : const [];

  static List<TemplatePlugin> _templatePlugins(dynamic raw) => raw is List
      ? [
          for (final p in raw)
            if (p is Map<String, dynamic>) TemplatePlugin.fromJson(p),
        ]
      : const [];

  static List<TemplateNote> _templateNotes(dynamic raw) => raw is List
      ? [
          for (final n in raw)
            if (n is Map<String, dynamic>) TemplateNote.fromJson(n),
        ]
      : const [];

  static List<String> _strings(dynamic raw) =>
      raw is List ? [for (final s in raw) '$s'] : const [];
}

/// The outcome of a save-as-template. [template] is the row the ENGINE stamped
/// (its id, tenant and timestamps are the engine's, never invented here).
///
/// A refusal carries the engine's own reason: [given] is the value it rejected
/// and [allowed] the vocabulary it WOULD accept, which is how a caller reads
/// the catalog rather than keeping its own copy of it.
@immutable
class TemplateSaveResult {
  final CyanTemplate? template;
  final String? error;
  final String given;
  final List<String> allowed;

  /// The engine's free-text elaboration on the errors that carry no vocabulary
  /// (`bad_template_json`, `invalid_steps`, `store_failed`).
  final String detail;

  const TemplateSaveResult({
    this.template,
    this.error,
    this.given = '',
    this.allowed = const [],
    this.detail = '',
  });

  bool get success => template != null && error == null;

  factory TemplateSaveResult.fromJson(Map<String, dynamic> j) {
    final error = j['error'] as String?;
    if (error != null && error.isNotEmpty) {
      final allowed = j['allowed'];
      return TemplateSaveResult(
        error: error,
        given: j['given'] as String? ?? '',
        allowed: allowed is List ? [for (final a in allowed) '$a'] : const [],
        detail: j['detail'] as String? ?? '',
      );
    }
    return TemplateSaveResult(template: CyanTemplate.fromJson(j));
  }
}

/// What the clone-time auto-install did to ONE declared plugin.
enum TemplatePluginInstallOutcome {
  /// Fetched, admitted, landed, indexed.
  installed,

  /// Already on this device — deduped, not re-fetched.
  alreadyPresent,

  /// This plugin failed; the clone itself still succeeded.
  failed,
}

extension TemplatePluginInstallOutcomeX on TemplatePluginInstallOutcome {
  String get label => switch (this) {
        TemplatePluginInstallOutcome.installed => 'Installed',
        TemplatePluginInstallOutcome.alreadyPresent => 'Already installed',
        TemplatePluginInstallOutcome.failed => 'Failed',
      };

  /// An outcome this build has never heard of reads as [failed]: a plugin is
  /// never reported as landed on a word the engine did not say.
  static TemplatePluginInstallOutcome fromWire(String? s) => switch (s) {
        'installed' => TemplatePluginInstallOutcome.installed,
        'already_present' => TemplatePluginInstallOutcome.alreadyPresent,
        _ => TemplatePluginInstallOutcome.failed,
      };
}

/// One plugin's auto-install outcome inside a clone. A failure is NEVER a
/// silent skip — it is carried here with the reason.
@immutable
class TemplatePluginInstall {
  final TemplatePluginInstallOutcome outcome;
  final String pluginId;

  /// The trusted signer's DID when the bundle was signed; null for an unsigned
  /// bundle allowed under the default policy.
  final String? signer;

  /// Why this plugin failed, verbatim. Null unless [outcome] is failed.
  final String? reason;

  const TemplatePluginInstall({
    required this.outcome,
    required this.pluginId,
    this.signer,
    this.reason,
  });

  factory TemplatePluginInstall.fromJson(Map<String, dynamic> j) {
    final signer = j['signer'] as String?;
    final reason = j['reason'] as String?;
    return TemplatePluginInstall(
      outcome: TemplatePluginInstallOutcomeX.fromWire(j['outcome'] as String?),
      pluginId: j['plugin_id'] as String? ?? '',
      signer: (signer == null || signer.isEmpty) ? null : signer,
      reason: (reason == null || reason.isEmpty) ? null : reason,
    );
  }
}

/// A board's LAST template-clone outcome: how many step cells the clone
/// materialized, and what the declared auto-install set did.
///
/// The clone verb is FIRE-AND-FORGET, so this is what the app polls for the
/// auto-install toast. [pluginInstalls] is empty for a template that declares
/// no set — every pre-auto-install template.
@immutable
class TemplateCloneOutcome {
  final String templateId;
  final String boardId;
  final String tenantId;

  /// The number of step cells the clone created.
  final int steps;
  final List<TemplatePluginInstall> pluginInstalls;

  const TemplateCloneOutcome({
    this.templateId = '',
    this.boardId = '',
    this.tenantId = '',
    this.steps = 0,
    this.pluginInstalls = const [],
  });

  /// At least one declared plugin failed to land. The board still materialized.
  bool get hasFailedInstall => pluginInstalls
      .any((p) => p.outcome == TemplatePluginInstallOutcome.failed);

  factory TemplateCloneOutcome.fromJson(Map<String, dynamic> j) {
    final installs = j['plugin_installs'];
    return TemplateCloneOutcome(
      templateId: j['template_id'] as String? ?? '',
      boardId: j['board_id'] as String? ?? '',
      tenantId: j['tenant_id'] as String? ?? '',
      steps: (j['steps'] as num?)?.toInt() ?? 0,
      pluginInstalls: installs is List
          ? [
              for (final p in installs)
                if (p is Map<String, dynamic>)
                  TemplatePluginInstall.fromJson(p),
            ]
          : const [],
    );
  }
}

// ---------------------------------------------------------------------------
// Step-composer autocomplete (`cyan_workflow_autocomplete`)
// ---------------------------------------------------------------------------

/// One autocomplete suggestion: the [trigger] that summons it, its [kind], the
/// token inserted into the step text on accept ([value]), and the label shown.
@immutable
class AutocompleteEntry {
  /// `@` (plugin / tool), `#` (artifact) or `/` (action).
  final String trigger;

  /// `plugin` | `tool` | `file` | `step_output` | `action`.
  final String kind;

  /// The token inserted into the step text when accepted.
  final String value;
  final String label;

  const AutocompleteEntry({
    required this.trigger,
    this.kind = '',
    this.value = '',
    this.label = '',
  });

  factory AutocompleteEntry.fromJson(Map<String, dynamic> j) =>
      AutocompleteEntry(
        trigger: j['trigger'] as String? ?? '',
        kind: j['kind'] as String? ?? '',
        value: j['value'] as String? ?? '',
        label: j['label'] as String? ?? '',
      );
}

/// The tenant-scoped autocomplete index behind the three trigger vocabularies.
///
/// When the composer's text carries an active trigger at the cursor, ONLY that
/// trigger's list is populated (filtered by the query) and the other two are
/// empty — an empty list means "not this trigger", not "nothing installed".
@immutable
class AutocompleteIndex {
  /// The board's group — the tenant every entry is scoped to.
  final String tenantId;

  /// `@` — installed plugins and their manifest tools.
  final List<AutocompleteEntry> plugins;

  /// `#` — files plus this board's prior-step outputs.
  final List<AutocompleteEntry> artifacts;

  /// `/` — the controlled verb set.
  final List<AutocompleteEntry> actions;
  final String? error;

  const AutocompleteIndex({
    this.tenantId = '',
    this.plugins = const [],
    this.artifacts = const [],
    this.actions = const [],
    this.error,
  });

  /// Nothing to offer at the cursor.
  bool get isEmpty =>
      plugins.isEmpty && artifacts.isEmpty && actions.isEmpty;

  factory AutocompleteIndex.fromJson(Map<String, dynamic> j) {
    final error = j['error'] as String?;
    if (error != null && error.isNotEmpty) {
      return AutocompleteIndex(error: error);
    }
    return AutocompleteIndex(
      tenantId: j['tenant_id'] as String? ?? '',
      plugins: _entries(j['plugins']),
      artifacts: _entries(j['artifacts']),
      actions: _entries(j['actions']),
    );
  }

  static List<AutocompleteEntry> _entries(dynamic raw) => raw is List
      ? [
          for (final e in raw)
            if (e is Map<String, dynamic>) AutocompleteEntry.fromJson(e),
        ]
      : const [];
}

// ---------------------------------------------------------------------------
// Producer review (`cyan_board_video_media` / `cyan_review_*`)
// ---------------------------------------------------------------------------

/// The board's playable video as the engine resolves it — the SAME resolution
/// the cyan-media tools run, so the player and the tool inputs can never
/// disagree about which file this board is.
@immutable
class BoardVideoMedia {
  /// The newest DERIVED proxy, absolute on disk. Null when none has been
  /// rendered yet — the player falls back to [masterUri].
  final String? proxyPath;

  /// The true master: an absolute path or a real URI, never a bare filename.
  final String? masterUri;

  /// A frame-mapped watchable render of a master the player cannot decode
  /// (camera originals: MXF / BRAW / R3D). It is review-for-eyes only — it
  /// never enters the ledger and a real proxy always wins over it.
  final String? previewPath;

  /// The confined media root every relative path resolves against.
  final String mediaRoot;

  /// The engine's store was under contention, so it answered the empty shape
  /// rather than parking the thread. Not an error: the caller reloads.
  final bool isBusy;
  final String? error;

  const BoardVideoMedia({
    this.proxyPath,
    this.masterUri,
    this.previewPath,
    this.mediaRoot = '',
    this.isBusy = false,
    this.error,
  });

  /// What the player should open: a derived proxy first, then the master.
  String? get playable => proxyPath ?? masterUri;

  /// The board has media to play at all.
  bool get hasMedia => playable != null;

  factory BoardVideoMedia.fromJson(Map<String, dynamic> j) => BoardVideoMedia(
        proxyPath: j['proxy_path'] as String?,
        masterUri: j['master_uri'] as String?,
        previewPath: j['preview_path'] as String?,
        mediaRoot: j['media_root'] as String? ?? '',
        isBusy: j['busy'] as bool? ?? false,
      );
}

/// The outcome of posting a frame-anchored review comment. The comment travels
/// back exactly as the review plugin returned it — the shape is the plugin's,
/// not this seam's, so it is carried rather than re-modelled.
@immutable
class ReviewCommentResult {
  final bool success;

  /// The posted comment's payload. Empty on a refusal.
  final Map<String, dynamic> comment;
  final String? error;

  const ReviewCommentResult({
    this.success = false,
    this.comment = const {},
    this.error,
  });

  /// The remote comment id, when the plugin named one.
  String? get id => comment['id'] as String?;

  /// The comment text as it landed.
  String get text => comment['text'] as String? ?? '';

  factory ReviewCommentResult.fromJson(Map<String, dynamic> j) =>
      ReviewCommentResult(
        success: j['success'] as bool? ?? false,
        comment: j['comment'] is Map<String, dynamic>
            ? j['comment'] as Map<String, dynamic>
            : const {},
        error: j['error'] as String?,
      );
}

/// One (tenant, asset, branch) row of the review-loop state machine.
///
/// [state] is the engine's own vocabulary — `DRAFT`, `IN_REVIEW`, `NOTES_IN`,
/// `CONFORMING`, `APPROVED`, `FINISHING`, `DELIVERED` — carried verbatim rather
/// than narrowed to an enum this build would have to keep in step with it.
@immutable
class ReviewState {
  final String tenantId;
  final String assetHash;
  final String branch;
  final String state;

  /// The review round; it increments on each CONFORMING → IN_REVIEW publish.
  final int round;
  final DateTime? updatedAt;

  const ReviewState({
    this.tenantId = '',
    this.assetHash = '',
    this.branch = '',
    this.state = '',
    this.round = 0,
    this.updatedAt,
  });

  factory ReviewState.fromJson(Map<String, dynamic> j) {
    final updated = (j['updated_at'] as num?)?.toInt() ?? 0;
    return ReviewState(
      tenantId: j['tenant_id'] as String? ?? '',
      assetHash: j['asset_hash'] as String? ?? '',
      branch: j['branch'] as String? ?? '',
      state: j['state'] as String? ?? '',
      round: (j['round'] as num?)?.toInt() ?? 0,
      updatedAt: updated > 0
          ? DateTime.fromMillisecondsSinceEpoch(updated * 1000)
          : null,
    );
  }
}

/// One reply from the review-loop's single JSON entrypoint.
///
/// The verb fans out over the whole review vocabulary, so the reply's SHAPE
/// depends on the op: a state row for the transitions, an object for the
/// proposal ops, an array for `nudges_for` / `loop_runs`. All three are carried
/// here — [state] when the reply is a state row, [fields] for any object,
/// [rows] for an array — instead of one op's shape being privileged.
@immutable
class ReviewCommandResult {
  /// The op this answers, echoed from the command that was sent.
  final String op;

  /// The state row the reply carries, when it carries one. Null for the ops
  /// that answer something else, AND for a `get` on a key with no state yet —
  /// that is the engine's own "not started", not a failure.
  final ReviewState? state;

  /// The reply's object fields, verbatim. Empty when the reply was an array.
  final Map<String, dynamic> fields;

  /// The reply's rows, for the ops that answer a JSON array. Empty otherwise.
  final List<Map<String, dynamic>> rows;

  /// The engine's refusal: an invalid transition, an actor that may not fire
  /// the gate, or a store that could not be reached.
  final String? error;

  const ReviewCommandResult({
    this.op = '',
    this.state,
    this.fields = const {},
    this.rows = const [],
    this.error,
  });

  bool get ok => error == null;

  /// Decode a reply for [op]. [decoded] is whatever `jsonDecode` made of it —
  /// an object, an array, or null when the op answers "nothing here".
  factory ReviewCommandResult.fromReply(String op, Object? decoded) {
    if (decoded is List) {
      return ReviewCommandResult(
        op: op,
        rows: [
          for (final row in decoded)
            if (row is Map<String, dynamic>) row,
        ],
      );
    }
    if (decoded is! Map<String, dynamic>) return ReviewCommandResult(op: op);
    final error = decoded['error'] as String?;
    if (error != null && error.isNotEmpty) {
      return ReviewCommandResult(op: op, error: error);
    }
    return ReviewCommandResult(
      op: op,
      // A state row is the dominant reply; anything without one still travels
      // whole in [fields], so no op loses its answer here.
      state: decoded['state'] is String
          ? ReviewState.fromJson(decoded)
          : null,
      fields: decoded,
    );
  }
}

/// One watched ingest source: a board's sensor pointed at a folder, a bucket or
/// a C2C project.
///
/// [scheduleSecs] null is the engine's "manual only" — a source that is scanned
/// when someone asks, not on a cadence — and is distinct from a cadence of 0.
@immutable
class IngestSource {
  final String id;

  /// The tenant (group) boundary every ingest query carries.
  final String tenantId;

  /// The board whose workflow TEMPLATE each ingested asset materializes.
  final String boardId;

  /// folder | s3 | frameio_c2c — the engine's vocabulary, carried verbatim.
  final String kind;

  /// The watched location: a directory path or `file://` URI for `folder`, an
  /// `s3://bucket/prefix` or a C2C project ref for the seam kinds.
  final String uri;

  /// Poll cadence in seconds; null = manual only.
  final int? scheduleSecs;

  /// The last SUCCESSFUL scan; null = never scanned.
  final DateTime? lastScanAt;
  final DateTime? createdAt;

  const IngestSource({
    this.id = '',
    this.tenantId = '',
    this.boardId = '',
    this.kind = '',
    this.uri = '',
    this.scheduleSecs,
    this.lastScanAt,
    this.createdAt,
  });

  /// True when the source is on a cadence rather than waiting to be asked.
  bool get isScheduled => scheduleSecs != null;

  factory IngestSource.fromJson(Map<String, dynamic> j) {
    final scanned = (j['last_scan_at'] as num?)?.toInt() ?? 0;
    final created = (j['created_at'] as num?)?.toInt() ?? 0;
    return IngestSource(
      id: j['id'] as String? ?? '',
      tenantId: j['tenant_id'] as String? ?? '',
      boardId: j['board_id'] as String? ?? '',
      kind: j['kind'] as String? ?? '',
      uri: j['uri'] as String? ?? '',
      scheduleSecs: (j['schedule_secs'] as num?)?.toInt(),
      lastScanAt: scanned > 0
          ? DateTime.fromMillisecondsSinceEpoch(scanned * 1000)
          : null,
      createdAt: created > 0
          ? DateTime.fromMillisecondsSinceEpoch(created * 1000)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'board_id': boardId,
        'kind': kind,
        'uri': uri,
        'schedule_secs': scheduleSecs,
        'last_scan_at': lastScanAt == null
            ? null
            : lastScanAt!.millisecondsSinceEpoch ~/ 1000,
        'created_at':
            createdAt == null ? null : createdAt!.millisecondsSinceEpoch ~/ 1000,
      };
}

/// One materialized per-asset run of a board's workflow template — the run a
/// scan creates for the SPECIFIC asset it ingested, never "the board's file".
@immutable
class MaterializedRun {
  final String runId;
  final String boardId;

  /// The content hash of the asset this run processes.
  final String assetHash;

  /// materialized | running | done | failed — the engine's vocabulary, carried
  /// verbatim rather than narrowed to an enum this build would have to track.
  final String status;
  final DateTime? createdAt;

  const MaterializedRun({
    this.runId = '',
    this.boardId = '',
    this.assetHash = '',
    this.status = '',
    this.createdAt,
  });

  factory MaterializedRun.fromJson(Map<String, dynamic> j) {
    final created = (j['created_at'] as num?)?.toInt() ?? 0;
    return MaterializedRun(
      runId: j['run_id'] as String? ?? '',
      boardId: j['board_id'] as String? ?? '',
      assetHash: j['asset_hash'] as String? ?? '',
      status: j['status'] as String? ?? '',
      createdAt: created > 0
          ? DateTime.fromMillisecondsSinceEpoch(created * 1000)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'run_id': runId,
        'board_id': boardId,
        'asset_hash': assetHash,
        'status': status,
        'created_at':
            createdAt == null ? null : createdAt!.millisecondsSinceEpoch ~/ 1000,
      };
}

/// What one scan did. [discovered] counts the candidate media seen, [ingested]
/// the NEW ones (asset registered + run materialized), [deduped] the
/// already-known content skipped — so a re-scan that ingests nothing is a
/// correct answer, not a silent one.
@immutable
class ScanReport {
  final int discovered;
  final int ingested;
  final int deduped;

  const ScanReport({
    this.discovered = 0,
    this.ingested = 0,
    this.deduped = 0,
  });

  factory ScanReport.fromJson(Map<String, dynamic> j) => ScanReport(
        discovered: (j['discovered'] as num?)?.toInt() ?? 0,
        ingested: (j['ingested'] as num?)?.toInt() ?? 0,
        deduped: (j['deduped'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'discovered': discovered,
        'ingested': ingested,
        'deduped': deduped,
      };
}

/// One reply from the ingest surface's single JSON entrypoint.
///
/// Like the review verb, the op decides the reply's SHAPE: a source row for
/// `source_add`, an array for `source_list` / `scan_due` / `runs_for_board`, a
/// scan report for `scan_now`, an ack for `source_remove`. All of them are
/// carried here — [fields] for any object, [rows] for an array — with the typed
/// views layered on top instead of one op's shape being privileged.
@immutable
class IngestCommandResult {
  /// The op this answers, echoed from the command that was sent.
  final String op;

  /// The reply's object fields, verbatim. Empty when the reply was an array.
  final Map<String, dynamic> fields;

  /// The reply's rows, for the ops that answer a JSON array. Empty otherwise.
  final List<Map<String, dynamic>> rows;

  /// The engine's refusal: an unknown op, a missing key, or a store that could
  /// not be reached inside the read budget.
  final String? error;

  const IngestCommandResult({
    this.op = '',
    this.fields = const {},
    this.rows = const [],
    this.error,
  });

  bool get ok => error == null;

  /// The `source_list` rows, and the single row `source_add` answers with — one
  /// accessor, because both are the same kind of thing.
  List<IngestSource> get sources {
    if (rows.isNotEmpty) return [for (final r in rows) IngestSource.fromJson(r)];
    if (fields['id'] is String && fields['uri'] is String) {
      return [IngestSource.fromJson(fields)];
    }
    return const [];
  }

  /// The `runs_for_board` rows.
  List<MaterializedRun> get runs =>
      [for (final r in rows) MaterializedRun.fromJson(r)];

  /// The `scan_now` report. Null when the reply carried no counts.
  ScanReport? get report =>
      fields['discovered'] is num ? ScanReport.fromJson(fields) : null;

  /// The `scan_due` sweep, per source. One source's error is carried on its own
  /// row — a bad source never sinks the tick — so the entry keeps both.
  List<({String sourceId, ScanReport? report, String? error})> get sweep => [
        for (final r in rows)
          (
            sourceId: r['source_id'] as String? ?? '',
            report: r['report'] is Map<String, dynamic>
                ? ScanReport.fromJson(r['report'] as Map<String, dynamic>)
                : null,
            error: r['error'] as String?,
          ),
      ];

  /// The `produce_master_plan` retrieve list: the (asset, location) pairs for
  /// exactly the masters the frozen cut uses.
  List<({String asset, String location})> get masters => [
        for (final m in (fields['masters'] as List? ?? const []))
          if (m is Map<String, dynamic>)
            (
              asset: m['asset'] as String? ?? '',
              location: m['location'] as String? ?? '',
            ),
      ];

  /// The `source_remove` ack.
  bool get removed => fields['removed'] as bool? ?? false;

  /// Decode a reply for [op]. [decoded] is whatever `jsonDecode` made of it —
  /// an object, an array, or null when the op answers "nothing here".
  factory IngestCommandResult.fromReply(String op, Object? decoded) {
    if (decoded is List) {
      return IngestCommandResult(
        op: op,
        rows: [
          for (final row in decoded)
            if (row is Map<String, dynamic>) row,
        ],
      );
    }
    if (decoded is! Map<String, dynamic>) return IngestCommandResult(op: op);
    final error = decoded['error'] as String?;
    if (error != null && error.isNotEmpty) {
      return IngestCommandResult(op: op, error: error);
    }
    return IngestCommandResult(op: op, fields: decoded);
  }
}

// ---------------------------------------------------------------------------
// ChangeList store (`cyan_changelist_command`)
// ---------------------------------------------------------------------------

/// One entry in the content-addressed change list: a reviewer's note, a
/// mechanical op, or a marker, anchored to a source asset at a timecode.
///
/// An entry's CONTENT is immutable — [entryHash] is the hash of exactly those
/// fields. Only the lifecycle columns ([state], [active], [outcome], the
/// supersede links) ever move, which is why reversing a change toggles
/// [active] instead of deleting the row.
@immutable
class ChangeEntry {
  final String id;

  /// Blake3 of the entry's canonical content fields. Empty only on a row the
  /// engine has not hashed yet.
  final String entryHash;

  /// Blake3 of the SOURCE asset this anchors to — the spine every entry hangs
  /// off.
  final String assetHash;

  /// The tenant boundary (the group id).
  final String tenantId;

  /// The "V1"/"A1" track, or null when the entry is not track-scoped.
  final String? track;

  /// Timecode in, in FRAMES — the asset carries the fps, not the entry.
  final int tcIn;

  /// Timecode out in frames. Null (or equal to [tcIn]) for a point marker.
  final int? tcOut;

  /// note | op | marker.
  final String kind;

  /// The closed-vocab operation, only when [kind] is `op`.
  final String? op;

  /// The op's typed payload, verbatim — its shape is per-op and the engine
  /// owns it, so it is never re-typed here.
  final Map<String, dynamic> params;

  /// The human text the entry came from ("open feels rushed").
  final String intent;

  /// frameio | cyan | resolve | avid | agent — where it originated.
  final String? source;

  /// The id of the originating comment/marker in [source].
  final String? sourceRef;

  final String? author;

  /// producer | editor | reviewer | agent.
  final String? role;

  /// human | agent. An AGENT may only ever PROPOSE — the engine refuses an
  /// agent-proposed entry any state past that without a human actor.
  final String? proposedBy;

  final DateTime? createdAt;

  /// proposed | approved | rejected | applied | superseded.
  final String state;

  /// Is this entry in the CURRENT conform? Toggling it is the non-destructive
  /// reverse — the row stays, the cut changes.
  final bool active;

  final String? approvedBy;
  final DateTime? approvedAt;

  /// The entry id this replaces, and the one that replaced it — the redo chain.
  final String? supersedes;
  final String? supersededBy;

  /// Position in the change list, i.e. apply order.
  final int seq;

  /// The version this entry first appeared in, and the branch it lives on.
  final String? versionRef;
  final String? branch;

  /// pending | shipped | rejected — the taste-learning label, set once.
  final String? outcome;

  const ChangeEntry({
    this.id = '',
    this.entryHash = '',
    this.assetHash = '',
    this.tenantId = '',
    this.track,
    this.tcIn = 0,
    this.tcOut,
    this.kind = '',
    this.op,
    this.params = const {},
    this.intent = '',
    this.source,
    this.sourceRef,
    this.author,
    this.role,
    this.proposedBy,
    this.createdAt,
    this.state = '',
    this.active = false,
    this.approvedBy,
    this.approvedAt,
    this.supersedes,
    this.supersededBy,
    this.seq = 0,
    this.versionRef,
    this.branch,
    this.outcome,
  });

  /// A point marker rather than a range: the engine writes no `tc_out`, or the
  /// same frame as [tcIn].
  bool get isPoint => tcOut == null || tcOut == tcIn;

  /// Proposed by an agent and not yet adjudicated by a human. The face marks
  /// these — an agent's proposal is never quietly treated as a decision.
  bool get isAgentProposal => proposedBy == 'agent' && state == 'proposed';

  factory ChangeEntry.fromJson(Map<String, dynamic> j) {
    final created = (j['created_at'] as num?)?.toInt() ?? 0;
    final approved = (j['approved_at'] as num?)?.toInt() ?? 0;
    return ChangeEntry(
      id: j['id'] as String? ?? '',
      entryHash: j['entry_hash'] as String? ?? '',
      assetHash: j['asset_hash'] as String? ?? '',
      tenantId: j['tenant_id'] as String? ?? '',
      track: j['track'] as String?,
      tcIn: (j['tc_in'] as num?)?.toInt() ?? 0,
      tcOut: (j['tc_out'] as num?)?.toInt(),
      kind: j['kind'] as String? ?? '',
      op: j['op'] as String?,
      params: j['params'] is Map<String, dynamic>
          ? j['params'] as Map<String, dynamic>
          : const {},
      intent: j['intent'] as String? ?? '',
      source: j['source'] as String?,
      sourceRef: j['source_ref'] as String?,
      author: j['author'] as String?,
      role: j['role'] as String?,
      proposedBy: j['proposed_by'] as String?,
      createdAt: created > 0
          ? DateTime.fromMillisecondsSinceEpoch(created * 1000)
          : null,
      state: j['state'] as String? ?? '',
      active: j['active'] as bool? ?? false,
      approvedBy: j['approved_by'] as String?,
      approvedAt: approved > 0
          ? DateTime.fromMillisecondsSinceEpoch(approved * 1000)
          : null,
      supersedes: j['supersedes'] as String?,
      supersededBy: j['superseded_by'] as String?,
      seq: (j['seq'] as num?)?.toInt() ?? 0,
      versionRef: j['version_ref'] as String?,
      branch: j['branch'] as String?,
      outcome: j['outcome'] as String?,
    );
  }
}

/// What one `cyan_changelist_command` answered.
///
/// The op vocabulary is the ENGINE's and the reply shape is per-op — an object
/// for most ops, a JSON array for `conform_plan` — so this carries both rather
/// than narrowing to one. Errors arrive as `{"error":"…"}`, including the
/// bounded-read refusal ("store busy — try again") the read ops answer under
/// contention instead of parking the caller.
@immutable
class ChangelistCommandResult {
  /// The op this answers, echoed from the command that was sent.
  final String op;

  /// The reply's object fields, verbatim. Empty when the reply was an array.
  final Map<String, dynamic> fields;

  /// The reply's rows, for the ops that answer a JSON array. Empty otherwise.
  final List<Map<String, dynamic>> rows;

  /// The engine's refusal: an unknown op, a missing key, a store that could not
  /// be reached inside the read budget, or a board with no review lane.
  final String? error;

  const ChangelistCommandResult({
    this.op = '',
    this.fields = const {},
    this.rows = const [],
    this.error,
  });

  bool get ok => error == null;

  /// The change list itself — what `list` and `get` both answer under
  /// `entries`, already in the engine's apply order (seq, then created_at).
  List<ChangeEntry> get entries => [
        for (final e in (fields['entries'] as List? ?? const []))
          if (e is Map<String, dynamic>) ChangeEntry.fromJson(e),
      ];

  /// The single entry the mutating ops answer with — `append`, `set_state`,
  /// `set_active`, `supersede`. Null when the reply was not one entry.
  ChangeEntry? get entry =>
      fields['id'] is String && fields['asset_hash'] is String
          ? ChangeEntry.fromJson(fields)
          : null;

  /// The board dialect's review state: `{"state","round"}`, or null when the
  /// board's lane has not opened a round yet.
  ({String state, int round})? get reviewState {
    final rs = fields['review_state'];
    if (rs is! Map<String, dynamic>) return null;
    return (
      state: rs['state'] as String? ?? '',
      round: (rs['round'] as num?)?.toInt() ?? 0,
    );
  }

  /// The `diff` answer: entry hashes added / removed between two versions, and
  /// the entry ids in A that B superseded.
  ({List<String> added, List<String> removed, List<String> superseded})
      get diff => (
            added: _strings('added'),
            removed: _strings('removed'),
            superseded: _strings('superseded'),
          );

  /// The `conform_plan` ops, in apply order — the array reply.
  List<({String entryId, int seq, String op})> get plan => [
        for (final r in rows)
          (
            entryId: r['entry_id'] as String? ?? '',
            seq: (r['seq'] as num?)?.toInt() ?? 0,
            op: r['op'] as String? ?? '',
          ),
      ];

  /// The `record_own_ref` / `set_outcome` ack, and the `is_own_source_ref`
  /// answer — the two boolean-shaped replies.
  bool get acked => fields['ok'] as bool? ?? false;
  bool get isOwnRef => fields['own'] as bool? ?? false;

  List<String> _strings(String key) => [
        for (final v in (fields[key] as List? ?? const []))
          if (v is String) v,
      ];

  /// Decode a reply for [op]. [decoded] is whatever `jsonDecode` made of it —
  /// an object, an array (`conform_plan`), or null.
  factory ChangelistCommandResult.fromReply(String op, Object? decoded) {
    if (decoded is List) {
      return ChangelistCommandResult(
        op: op,
        rows: [
          for (final row in decoded)
            if (row is Map<String, dynamic>) row,
        ],
      );
    }
    if (decoded is! Map<String, dynamic>) {
      return ChangelistCommandResult(op: op);
    }
    final error = decoded['error'] as String?;
    if (error != null && error.isNotEmpty) {
      return ChangelistCommandResult(op: op, error: error);
    }
    return ChangelistCommandResult(op: op, fields: decoded);
  }
}

// ---------------------------------------------------------------------------
// Files (`cyan_resolve_file_handle`)
// ---------------------------------------------------------------------------

/// One ACTIVE file in the object store — the engine's `FileDTO`.
///
/// A tombstoned file is never one of these: the engine filters deleted rows out
/// of the resolve, so holding a [CyanFile] means the file was live when it was
/// read, not that it still is.
@immutable
class CyanFile {
  final String id;

  /// The tree context. Each is nullable ENGINE-side — a file uploaded to a
  /// group has no board — so an empty string here means "not scoped to one",
  /// which is the same thing the wire's null says.
  final String groupId;
  final String workspaceId;
  final String boardId;

  final String name;

  /// The content hash the mesh dedupes and gossips on.
  final String hash;
  final int size;

  /// The peer this file arrived from; empty when it originated here.
  final String sourcePeer;

  /// Where the bytes live on THIS device. Empty when only the metadata has
  /// synced — the file is known but not downloaded.
  final String localPath;

  final DateTime? createdAt;

  const CyanFile({
    this.id = '',
    this.groupId = '',
    this.workspaceId = '',
    this.boardId = '',
    this.name = '',
    this.hash = '',
    this.size = 0,
    this.sourcePeer = '',
    this.localPath = '',
    this.createdAt,
  });

  /// True when the bytes are on this device, not just the row describing them.
  bool get isDownloaded => localPath.isNotEmpty;

  factory CyanFile.fromJson(Map<String, dynamic> j) {
    final created = (j['created_at'] as num?)?.toInt() ?? 0;
    return CyanFile(
      id: j['id'] as String? ?? '',
      groupId: j['group_id'] as String? ?? '',
      workspaceId: j['workspace_id'] as String? ?? '',
      boardId: j['board_id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      hash: j['hash'] as String? ?? '',
      size: (j['size'] as num?)?.toInt() ?? 0,
      sourcePeer: j['source_peer'] as String? ?? '',
      localPath: j['local_path'] as String? ?? '',
      createdAt: created > 0
          ? DateTime.fromMillisecondsSinceEpoch(created * 1000)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'group_id': groupId,
        'workspace_id': workspaceId,
        'board_id': boardId,
        'name': name,
        'hash': hash,
        'size': size,
        'source_peer': sourcePeer,
        'local_path': localPath,
        'created_at':
            createdAt == null ? null : createdAt!.millisecondsSinceEpoch ~/ 1000,
      };
}

// ---------------------------------------------------------------------------
// Path autocomplete (`cyan_autocomplete_path`)
// ---------------------------------------------------------------------------

/// One completion of a partial `g\Group\Workspace\Board` path: the leaf [name]
/// the segment completes to, and the whole [path] accepting it types out.
@immutable
class PathSuggestion {
  final String name;
  final String path;

  const PathSuggestion({this.name = '', this.path = ''});

  factory PathSuggestion.fromJson(Map<String, dynamic> j) => PathSuggestion(
        name: j['name'] as String? ?? '',
        path: j['path'] as String? ?? '',
      );
}

// ---------------------------------------------------------------------------
// Lens command bar (`cyan_parse_lens_command`)
// ---------------------------------------------------------------------------

/// A path a lens command named, resolved by the ENGINE to real ids. [kind] is
/// the DEEPEST level it reached — `group` | `workspace` | `board` | `file` —
/// and the levels above it are filled in with it, so a file carries its board
/// and a board carries its workspace.
@immutable
class LensResolvedPath {
  final String kind;
  final String groupId;
  final String groupName;
  final String workspaceId;
  final String workspaceName;
  final String boardId;
  final String boardName;
  final String fileName;

  /// Where the file's bytes live on THIS device. Empty when only the row has
  /// synced, or when the path resolved above file level.
  final String filePath;

  const LensResolvedPath({
    this.kind = '',
    this.groupId = '',
    this.groupName = '',
    this.workspaceId = '',
    this.workspaceName = '',
    this.boardId = '',
    this.boardName = '',
    this.fileName = '',
    this.filePath = '',
  });

  factory LensResolvedPath.fromJson(Map<String, dynamic> j) {
    // The engine serializes its ResolvedPath enum EXTERNALLY TAGGED: one key,
    // the variant name, carrying that variant's fields.
    final variant = j.keys.isEmpty ? '' : j.keys.first;
    final raw = j[variant];
    final f = raw is Map<String, dynamic> ? raw : const <String, dynamic>{};
    return LensResolvedPath(
      kind: variant.toLowerCase(),
      groupId: f['group_id'] as String? ?? '',
      groupName: f['group_name'] as String? ?? '',
      workspaceId: f['workspace_id'] as String? ?? '',
      workspaceName: f['workspace_name'] as String? ?? '',
      boardId: f['board_id'] as String? ?? '',
      boardName: f['board_name'] as String? ?? '',
      fileName: f['file_name'] as String? ?? '',
      filePath: f['file_path'] as String? ?? '',
    );
  }
}

/// One parsed lens command line. [type] is the ENGINE's own discriminant —
/// `help` | `import` | `pipeline` | `natural_language` | `pin` | `summarize` |
/// `summarize_file` | `grep` | `status` | `pulse` — and only the fields that
/// type carries are populated.
///
/// The engine parses AND partly EXECUTES here: a `/pipeline status` comes back
/// carrying its status payload, a `/summarize file` with the text already
/// extracted. So a caller dispatches on [type] rather than re-parsing the line.
@immutable
class LensCommandParse {
  final String type;

  /// The help prose, or the natural-language remainder of a line that named no
  /// verb at all.
  final String text;

  /// The pipeline verb — `compile` | `run` | `status` | `export` | `approve` |
  /// `reject` | `retry` | `help`. Empty on every other type.
  final String action;

  /// The `/import` source (`jira`, …) and the project it targets.
  final String source;
  final String target;

  /// The search term of a `/grep`.
  final String term;

  /// The scope the line's path resolved to. Null when the line named none, or
  /// when the engine could not resolve the one it named.
  final LensResolvedPath? resolved;

  /// The board and step a pipeline verb applies to, when the path named them.
  final String boardId;
  final String stepId;

  /// The text `/summarize file` already extracted, truncated to the engine's
  /// token budget. Null when the path did not resolve to a readable file.
  final String? extractedText;

  /// The Airflow DAG a `/pipeline export` produced.
  final String dag;

  /// A `/pipeline status` payload, verbatim.
  final Map<String, dynamic>? data;

  /// True when a `/pipeline compile` still needs its LLM round-trip before the
  /// board has real step configs — the parse alone does not compile it.
  final bool needsLlm;

  /// The ENGINE's refusal for this line: an unresolvable path, a failed text
  /// extraction, a pipeline verb naming no board. Null when the line parsed.
  final String? error;

  const LensCommandParse({
    this.type = '',
    this.text = '',
    this.action = '',
    this.source = '',
    this.target = '',
    this.term = '',
    this.resolved,
    this.boardId = '',
    this.stepId = '',
    this.extractedText,
    this.dag = '',
    this.data,
    this.needsLlm = false,
    this.error,
  });

  bool get parsed => error == null;

  factory LensCommandParse.fromJson(Map<String, dynamic> j) {
    final resolved = j['resolved'];
    final data = j['data'];
    return LensCommandParse(
      type: j['type'] as String? ?? '',
      text: j['text'] as String? ?? '',
      action: j['action'] as String? ?? '',
      source: j['source'] as String? ?? '',
      target: j['target'] as String? ?? '',
      term: j['term'] as String? ?? '',
      resolved: resolved is Map<String, dynamic>
          ? LensResolvedPath.fromJson(resolved)
          : null,
      boardId: j['board_id'] as String? ?? '',
      stepId: j['step_id'] as String? ?? '',
      extractedText: j['extracted_text'] as String?,
      dag: j['dag'] as String? ?? '',
      data: data is Map<String, dynamic> ? data : null,
      needsLlm: j['needs_llm'] as bool? ?? false,
      error: j['error'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Persona seed (`cyan_seed_personas`)
// ---------------------------------------------------------------------------

/// One seeded persona's landing row: the `seedtok_<persona>` sign-in [token],
/// the craft role it signs in as, and the surface + board that sign-in lands
/// on. [displayRole] is what the UI shows; it differs from [craftRole] only
/// where a persona rides another role's slug.
@immutable
class SeedPersona {
  final String token;
  final String display;
  final String craftRole;
  final String displayRole;
  final String primarySurface;
  final String groupId;
  final String boardId;
  final String boardName;

  const SeedPersona({
    this.token = '',
    this.display = '',
    this.craftRole = '',
    this.displayRole = '',
    this.primarySurface = '',
    this.groupId = '',
    this.boardId = '',
    this.boardName = '',
  });

  factory SeedPersona.fromJson(Map<String, dynamic> j) => SeedPersona(
        token: j['token'] as String? ?? '',
        display: j['display'] as String? ?? '',
        craftRole: j['craft_role'] as String? ?? '',
        displayRole: j['display_role'] as String? ?? '',
        primarySurface: j['primary_surface'] as String? ?? '',
        groupId: j['group_id'] as String? ?? '',
        boardId: j['board_id'] as String? ?? '',
        boardName: j['board_name'] as String? ?? '',
      );
}

/// The manifest a persona seed produced, or the engine's refusal to run one.
/// The seed is GATED: a build without `CYAN_SEED_DEMO=1` answers
/// `seed_disabled` and seeds NOTHING, so a refusal never leaves half a cast
/// behind.
@immutable
class SeedPersonasResult {
  final String? error;
  final List<SeedPersona> personas;

  const SeedPersonasResult({this.error, this.personas = const []});

  bool get seeded => error == null;

  factory SeedPersonasResult.fromJson(Map<String, dynamic> j) {
    final error = j['error'] as String?;
    if (error != null) return SeedPersonasResult(error: error);
    final rows = j['personas'];
    return SeedPersonasResult(
      personas: rows is List
          ? [
              for (final p in rows)
                if (p is Map<String, dynamic>) SeedPersona.fromJson(p),
            ]
          : const [],
    );
  }
}
