// ffi/parity_models.dart
//
// Plain, immutable view models returned by the `CyanBackend` seam. These are
// deliberately UI-facing and decoupled from the FFI JSON wire format and from
// the legacy `tree_item.dart` models, so the parity screens have one stable
// shape to render whether the data came from the real engine or the fake.
//
// Hierarchy mirrors the SwiftUI app: Group -> Workspace -> Board.

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

  const PluginCard({
    required this.id,
    required this.name,
    required this.publisher,
    required this.summary,
    required this.category,
    required this.stage,
    required this.placement,
    this.sideEffect = PluginSideEffect.readOnly,
    this.isTrusted = true,
    this.rating = 0,
    this.isFeatured = false,
  });
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
