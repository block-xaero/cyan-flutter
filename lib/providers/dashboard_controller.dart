// providers/dashboard_controller.dart
//
// PARITY port of `DashboardViewModel` (cyan-iOS/Cyan/Cyan/ViewModels/) — the
// board Dashboard's read-model: the compiled DAG before a run, the live run
// while it moves, its gates, its stats, and its terminal state.
//
// THE SOURCE OF TRUTH IS `pipelineStatus`, not `loadRun`. That is not a detail:
// `CyanBackendFFI.loadRun` is still a stub that answers null, while
// `cyan_pipeline_status` is bound and carries the engine's real per-step
// states, gate assignees, durations and cost. Swift's `reconstruct()` reads the
// same verb for the same reason. A dashboard built on the stub would render an
// empty surface in the shipping app and a green suite in the test one.
//
// Three phases, exactly as Swift derives them:
//   preRun   — the board compiled but nothing has executed: the DAG preview
//   running  — the engine is working the chain (or parked on a gate)
//   done     — the run reached a terminal state (done / failed / cancelled)
//
// Two inputs, in strict precedence:
//   1. `pipelineStatus` — the authoritative persisted read. Establishes state.
//   2. `pollEvents`     — deltas that REFINE it (per-step transitions, progress
//      counters, gate opens/closes, run finish, and the `WorkflowStatsUpdated`
//      snapshot, which is the ONLY source of run stats — never recomputed here).
//
// The gate verbs are real writes: `pipelineApprove` / `pipelineApproveAs` and
// their reject twins. A producer-review hold clears ONLY for the user it waits
// on, and when the engine refuses, its refusal is surfaced verbatim and NOTHING
// moves — a gate that fakes its own approval is the one bug this face cannot
// have.
//
// Talks ONLY to the `CyanBackend` seam — never `CyanFFI`.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/cyan_backend.dart';
import '../ffi/parity_models.dart';
import '../models/dashboard_event.dart';

/// The surface state, derived — never stored twice. Swift `DashboardViewModel.Phase`.
enum DashboardPhase {
  /// Compiled, nothing executed: the DAG preview.
  preRun,

  /// Live: transitions, progress and gates.
  running,

  /// Terminal: the run summary.
  done,
}

/// One step of the DAG as the dashboard knows it: the persisted compile +
/// whatever live frames have landed since.
@immutable
class DagStep {
  final String id;
  final String title;
  final String stage;
  final DashboardStepState state;
  final DashboardStepActor actor;

  /// The step ids this one waits on — the DAG's edges.
  final List<String> dependsOn;

  /// Live per-item counters from `StepProgress`; null until one lands.
  final int? processed;
  final int? total;
  final String? currentItem;

  /// A producer-review hold: only [waitingOn] can clear it.
  final bool isReviewHold;
  final String? waitingOn;

  /// The engine's own error text for a failed step.
  final String? error;

  /// WHO cleared this step's gate — the engine's `approved_by`: a person, or
  /// the autopilot policy card, which the engine writes as `policy:<card>`.
  final String? approvedBy;

  const DagStep({
    required this.id,
    required this.title,
    this.stage = '',
    required this.state,
    required this.actor,
    this.dependsOn = const [],
    this.processed,
    this.total,
    this.currentItem,
    this.isReviewHold = false,
    this.waitingOn,
    this.error,
    this.approvedBy,
  });

  /// AUTOPILOT (design §1) — this gate was cleared by the POLICY, not a person.
  /// The DAG draws its own chip for it, carrying the evidence-stamped card id,
  /// rather than a generic "Approved" that would read as a human having looked.
  bool get isPolicyCleared => approvedBy?.startsWith('policy:') == true;

  DagStep copyWith({
    String? title,
    String? stage,
    DashboardStepState? state,
    DashboardStepActor? actor,
    int? processed,
    int? total,
    String? currentItem,
  }) =>
      DagStep(
        id: id,
        title: title ?? this.title,
        stage: stage ?? this.stage,
        state: state ?? this.state,
        actor: actor ?? this.actor,
        dependsOn: dependsOn,
        processed: processed ?? this.processed,
        total: total ?? this.total,
        currentItem: currentItem ?? this.currentItem,
        isReviewHold: isReviewHold,
        waitingOn: waitingOn,
        error: error,
        approvedBy: approvedBy,
      );

  /// A human has to act before this step can move.
  bool get isGateOpen =>
      state == DashboardStepState.awaitingApproval ||
      state == DashboardStepState.needsLens;

  /// "3 / 10" once the engine reports counts, else null.
  String? get progressLabel =>
      (processed != null && total != null && total! > 0)
          ? '$processed / $total'
          : null;

  /// How the step list spells this state (Swift's per-state chip).
  String get stateLabel => switch (state) {
        DashboardStepState.pending => 'Queued',
        DashboardStepState.running => 'Running',
        DashboardStepState.awaitingApproval => 'Awaiting you',
        DashboardStepState.awaitingInput => 'Awaiting input',
        DashboardStepState.needsLens => 'Parked',
        DashboardStepState.approved => 'Approved',
        DashboardStepState.done => 'Done',
        DashboardStepState.failed => 'Failed',
      };

  @override
  bool operator ==(Object other) =>
      other is DagStep &&
      other.id == id &&
      other.title == title &&
      other.stage == stage &&
      other.state == state &&
      other.actor == actor &&
      listEquals(other.dependsOn, dependsOn) &&
      other.processed == processed &&
      other.total == total &&
      other.currentItem == currentItem &&
      other.isReviewHold == isReviewHold &&
      other.waitingOn == waitingOn &&
      other.error == error;

  @override
  int get hashCode => Object.hash(id, title, stage, state, actor, processed,
      total, currentItem, isReviewHold, waitingOn, error);
}

/// Everything the Dashboard renders. A plain value, so the widget is a pure
/// function of it and every engine answer — including the ugly ones — is a
/// state rather than a branch in the view.
@immutable
class DashboardState {
  /// True once a read has come back. Only false before the first one, which is
  /// the only moment a spinner is honest.
  final bool hydrated;

  final DashboardPhase phase;
  final String runId;
  final String workflowLabel;
  final List<DagStep> steps;

  /// The run-level terminal state, once there is one.
  final WorkflowRunState? finished;

  /// The run meter, straight off `WorkflowStatsUpdated` (or the persisted
  /// durations the engine already summed). Never recomputed in the view.
  final DashboardSnapshot? snapshot;

  final String? currentItem;
  final String? currentStage;
  final int itemsProcessed;
  final int itemsTotal;

  /// The engine's refusal at a gate, verbatim ("review gate is waiting on
  /// 'producer@studio'"). Loud, never silent, and never a fake approval.
  final String? gateMessage;

  /// The engine's own error envelope from the last failed read.
  final String? error;

  /// A gate write is in flight — the buttons hold rather than double-fire.
  final bool busy;

  /// The operator asked the walk to stop after the step in flight.
  ///
  /// CLIENT-SIDE, exactly as Swift holds it: there is no engine pause verb, and
  /// inventing one would be worse than useless — the engine would keep walking
  /// while the UI claimed otherwise. What this actually does is stop THIS client
  /// from advancing the chain; Resume re-runs from the first pending step.
  final bool isPaused;

  /// Frames this build could not decode. Counted, not swallowed.
  final int droppedFrames;

  const DashboardState({
    required this.hydrated,
    required this.phase,
    required this.runId,
    required this.workflowLabel,
    required this.steps,
    this.finished,
    this.snapshot,
    this.currentItem,
    this.currentStage,
    this.itemsProcessed = 0,
    this.itemsTotal = 0,
    this.gateMessage,
    this.error,
    this.busy = false,
    this.droppedFrames = 0,
    this.isPaused = false,
  });

  static const DashboardState initial = DashboardState(
    hydrated: false,
    phase: DashboardPhase.preRun,
    runId: '',
    workflowLabel: '',
    steps: [],
  );

  DashboardState copyWith({
    bool? hydrated,
    DashboardPhase? phase,
    String? runId,
    String? workflowLabel,
    List<DagStep>? steps,
    WorkflowRunState? finished,
    bool clearFinished = false,
    DashboardSnapshot? snapshot,
    String? currentItem,
    String? currentStage,
    int? itemsProcessed,
    int? itemsTotal,
    String? gateMessage,
    bool clearGateMessage = false,
    String? error,
    bool clearError = false,
    bool? busy,
    int? droppedFrames,
    bool? isPaused,
  }) =>
      DashboardState(
        hydrated: hydrated ?? this.hydrated,
        phase: phase ?? this.phase,
        runId: runId ?? this.runId,
        workflowLabel: workflowLabel ?? this.workflowLabel,
        steps: steps ?? this.steps,
        finished: clearFinished ? null : (finished ?? this.finished),
        snapshot: snapshot ?? this.snapshot,
        currentItem: currentItem ?? this.currentItem,
        currentStage: currentStage ?? this.currentStage,
        itemsProcessed: itemsProcessed ?? this.itemsProcessed,
        itemsTotal: itemsTotal ?? this.itemsTotal,
        gateMessage:
            clearGateMessage ? null : (gateMessage ?? this.gateMessage),
        error: clearError ? null : (error ?? this.error),
        busy: busy ?? this.busy,
        droppedFrames: droppedFrames ?? this.droppedFrames,
        isPaused: isPaused ?? this.isPaused,
      );

  /// The engine is working the chain.
  bool get isRunning => phase == DashboardPhase.running;

  /// The open gates, in DAG order. Derived from the steps — a gate list that
  /// can drift from the steps it gates is a gate list that lies. A LENS PARK is
  /// on this list too (`isGateOpen`): the KEYSTONE finding was a lens-parked
  /// editorial step with no human override anywhere, which wedged the whole
  /// chain behind it. It is an action item, so it joins the action list.
  List<DagStep> get gates => [
        for (final s in steps)
          if (s.isGateOpen) s
      ];

  /// The steps the ENGINE parked for want of an input — conform with no
  /// confirmed edits is the canonical one, and it sits in the middle of the
  /// spine. Deliberately NOT folded into [gates]: a gate is approve-or-reject,
  /// while a park is "go and do the thing, then resume", so it needs its own
  /// affordance rather than an Approve button that would decide nothing.
  List<DagStep> get parked => [
        for (final s in steps)
          if (s.state == DashboardStepState.awaitingInput) s
      ];

  DagStep? stepById(String id) {
    for (final s in steps) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The engine has finished with this step and moved on.
  static bool _settled(DagStep s) =>
      s.state == DashboardStepState.approved ||
      s.state == DashboardStepState.done;

  /// What [step] is ACTUALLY waiting for, or null when nothing holds it back.
  ///
  /// A PARKED step is TRANSPARENT here. It has no model to run it and clears
  /// only by a human override, so it can never be the thing the chain waits on
  /// — it passes its own dependencies through to whoever depended on IT, and
  /// the walk continues to the first real blocker. The engine's own run walk
  /// steps over a park for the same reason; if the surface did not, it would
  /// show a chain wedged that the engine is happily still running.
  DagStep? blockedBy(DagStep step) {
    final seen = <String>{step.id};
    final queue = [...step.dependsOn];
    while (queue.isNotEmpty) {
      final id = queue.removeAt(0);
      if (!seen.add(id)) continue;
      final dep = stepById(id);
      if (dep == null || _settled(dep)) continue;
      if (dep.state == DashboardStepState.needsLens) {
        queue.addAll(dep.dependsOn);
        continue;
      }
      return dep;
    }
    return null;
  }

  /// The run-level pill.
  String get statusLabel {
    if (finished != null) {
      return switch (finished!) {
        WorkflowRunState.done => 'Done',
        WorkflowRunState.failed => 'Failed',
        WorkflowRunState.cancelled => 'Cancelled',
        WorkflowRunState.running => 'Running',
      };
    }
    return phase == DashboardPhase.preRun ? 'Not started' : 'Running';
  }

  /// Steps the engine has settled (approved or done).
  int get completedSteps => steps
      .where((s) =>
          s.state == DashboardStepState.approved ||
          s.state == DashboardStepState.done)
      .length;

  @override
  bool operator ==(Object other) =>
      other is DashboardState &&
      other.hydrated == hydrated &&
      other.phase == phase &&
      other.runId == runId &&
      other.workflowLabel == workflowLabel &&
      listEquals(other.steps, steps) &&
      other.finished == finished &&
      identical(other.snapshot, snapshot) &&
      other.currentItem == currentItem &&
      other.currentStage == currentStage &&
      other.itemsProcessed == itemsProcessed &&
      other.itemsTotal == itemsTotal &&
      other.gateMessage == gateMessage &&
      other.error == error &&
      other.busy == busy &&
      other.droppedFrames == droppedFrames &&
      // A field missing from here is a field that SILENTLY never reaches the
      // view: StateNotifier suppresses the publish when the new state compares
      // equal to the old. `isPaused` was added and omitted, and the Pause
      // button did nothing at all until this line existed.
      other.isPaused == isPaused;

  @override
  int get hashCode => Object.hash(
        hydrated,
        phase,
        runId,
        workflowLabel,
        Object.hashAll(steps),
        finished,
        snapshot,
        currentItem,
        currentStage,
        itemsProcessed,
        itemsTotal,
        gateMessage,
        error,
        busy,
        droppedFrames,
        isPaused,
      );
}

/// The Dashboard's view-model. Owns the authoritative re-read, the event drain,
/// and the gate writes.
class DashboardController extends StateNotifier<DashboardState> {
  DashboardController({
    required this.backend,
    required this.boardId,
    this.reviewer = '',
    this.component = 'status',
  }) : super(DashboardState.initial);

  final CyanBackend backend;
  final String boardId;

  /// WHO this device approves as. A producer-review hold clears only for the
  /// user it waits on, so an unset reviewer gets the engine's refusal rather
  /// than a gate that quietly opens for anyone. There is no signed-in user on
  /// the seam yet (`SsoSession` carries a tenant and a role, not a name), so
  /// the shell passes it down when it has one.
  final String reviewer;

  /// The buffer these frames ride. The live producer routes dashboard events
  /// onto the shared `status` buffer — there is no bespoke "dashboard" channel
  /// (Swift `DashboardViewModel.setupActor`).
  final String component;

  /// The bound on ONE drain cycle, the same 200 the Swift producer breaks at.
  static const int drainCap = 200;

  Timer? _timer;
  bool _stopped = false;
  bool _inFlight = false;

  /// The published state, for callers driving the pump directly (a test steps
  /// [tick] one cycle at a time; `StateNotifier.state` is protected).
  DashboardState get current => state;

  /// Notify on VALUE change, not on identity. An idle cycle re-derives an equal
  /// state, and a surface that rebuilt every 100ms for no reason would never
  /// let a widget test settle — nor a laptop sleep.
  @override
  bool updateShouldNotify(DashboardState old, DashboardState current) =>
      old != current;

  /// First read. Events refine an authoritative read; they never bootstrap one.
  Future<void> hydrate() async {
    if (_stopped) return;
    try {
      await backend.initialize();
    } catch (e) {
      state = state.copyWith(hydrated: true, error: _describe(e));
      return;
    }
    await reconstruct();
  }

  /// Re-read the persisted run (Swift `reconstruct()`). Pure read, safe to call
  /// repeatedly, and coalesced — a slow engine drops the overlapping call
  /// instead of stacking reads behind the DB mutex.
  Future<void> reconstruct() async {
    if (_stopped || _inFlight) return;
    _inFlight = true;
    try {
      final status = await backend.pipelineStatus(boardId);
      if (_stopped) return;
      if (status.error != null) {
        // A read that failed must not blank a surface that was showing a run.
        state = state.copyWith(hydrated: true, error: status.error);
        return;
      }
      state = _fromStatus(status);
    } catch (e) {
      state = state.copyWith(hydrated: true, error: _describe(e));
    } finally {
      _inFlight = false;
    }
  }

  /// One pump cycle: drain, decode, apply. Never throws.
  Future<void> tick() async {
    if (_stopped) return;
    try {
      final frames = <String>[];
      while (frames.length < drainCap) {
        final raw = await backend.pollEvents(component);
        if (raw == null) break;
        frames.add(raw);
      }
      if (frames.isEmpty) return;

      // A full cycle means the producer is ahead of us: the deltas we hold are
      // a partial story, so we re-read the truth instead of painting one.
      if (frames.length >= drainCap) {
        await reconstruct();
        return;
      }

      var next = state;
      var dropped = 0;
      for (final raw in frames) {
        final event = DashboardEvent.fromJson(raw);
        if (event == null) {
          // A variant this build never compiled against, a truncated write, or
          // a frame with no run to attach to. Counted, and the drain continues:
          // one bad frame must not cost us the good frames behind it.
          dropped++;
          continue;
        }
        next = _apply(next, event);
      }
      state = next.copyWith(
        hydrated: true,
        droppedFrames: state.droppedFrames + dropped,
      );
    } catch (e) {
      state = state.copyWith(hydrated: true, error: _describe(e));
    }
  }

  /// Start the real pump. Idle cadence matches the Swift producer's empty-buffer
  /// sleep.
  void start({Duration interval = const Duration(milliseconds: 100)}) {
    if (_stopped || _timer != null) return;
    _timer = Timer.periodic(interval, (_) => tick());
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  // ---- gate writes ---------------------------------------------------------

  /// Clear a gate, then ADVANCE: the engine breaks the chain at every gate
  /// (exactly one step open at a time), so approving resumes the SAME run from
  /// the next step — Swift's "approve-to-advance" (item 1). The engine's own
  /// refusal is surfaced and nothing moves; we never settle a step the engine
  /// did not settle.
  Future<void> approve(String stepId) async {
    await _gate(stepId, advance: true, write: (step) async {
      if (step.isReviewHold) {
        final ack = await backend.pipelineApproveAs(boardId, stepId, reviewer);
        return ack.success ? null : (ack.error ?? 'the gate refused to clear');
      }
      final ok = await backend.pipelineApprove(boardId, stepId);
      return ok ? null : 'the engine refused to clear this gate';
    });
  }

  /// Reject an open gate: the step fails and the run STOPS at the gate. No
  /// resume — a rejection is a decision to not proceed.
  Future<void> reject(String stepId) async {
    await _gate(stepId, advance: false, write: (step) async {
      if (step.isReviewHold) {
        final ack = await backend.pipelineRejectAs(boardId, stepId, reviewer);
        return ack.success ? null : (ack.error ?? 'the gate refused to clear');
      }
      final ok = await backend.pipelineReject(boardId, stepId);
      return ok ? null : 'the engine refused to reject this gate';
    });
  }

  /// RUN THIS STEP NOW, out of order (Swift `runNow`). The DAG's whole point is
  /// that a step waits for the ones before it — which leaves an operator with
  /// no way to execute just the one step they need, e.g. a step authored after
  /// the run compiled, or one sitting behind a gate somebody else owes.
  ///
  /// This dispatches the ONE step through the engine's route-local path
  /// (`cyan_pipeline_run_step_local`), which still honours the choke point: a
  /// step that has to park still PARKS, so run-now can never jump a gate — and
  /// when it does park, that is news, so we re-read either way rather than
  /// leaving a step on screen as queued when the engine has moved it.
  Future<void> runNow(String stepId) async {
    if (state.busy) return;
    if (_step(stepId) == null) return;
    state = state.copyWith(busy: true, clearGateMessage: true);
    try {
      final result = await backend.pipelineRunStepLocal(boardId, stepId);
      if (_stopped) return;
      await reconstruct();
      if (_stopped) return;
      state = state.copyWith(
        busy: false,
        gateMessage: result.success
            ? null
            : (result.error ?? 'the engine refused to run this step'),
        clearGateMessage: result.success,
      );
    } catch (e) {
      state = state.copyWith(busy: false, gateMessage: _describe(e));
    }
  }

  /// Put a failed or parked step back to pending and run it again — the
  /// affordance a red step needs so the run is not simply stuck.
  Future<void> retry(String stepId) async {
    await _gate(stepId, advance: true, write: (_) async {
      final ok = await backend.pipelineRetry(boardId, stepId);
      return ok ? null : 'the engine refused to retry this step';
    });
  }

  // ---- run controls --------------------------------------------------------

  /// Stop advancing the chain after the step in flight.
  ///
  /// There is no engine pause verb, so this is what Swift does too: a
  /// client-side flag. It is honest because it only claims what it can do —
  /// this client stops pushing the run forward. It does NOT reach into a step
  /// already executing, and the label must never suggest it did.
  void pauseRun() {
    if (!state.isRunning || state.isPaused) return;
    state = state.copyWith(isPaused: true);
  }

  /// Pick the walk back up from the first step still pending.
  Future<void> resumeRun() async {
    if (!state.isPaused) return;
    state = state.copyWith(isPaused: false);
    final next = state.steps
        .where((s) => s.state == DashboardStepState.pending)
        .firstOrNull;
    if (next == null) return;
    await retry(next.id);
  }

  /// WHOLE-RUN reset: every step back to pending, results cleared.
  ///
  /// STATE SURGERY ONLY — it never runs anything, so nothing re-executes, no
  /// upstream artifact is re-produced and no upload re-fires. That is what
  /// makes it safe to offer on a run that already sent things out into the
  /// world. The human presses Run again.
  ///
  /// Refused while the engine is mid-walk: resetting rows underneath a running
  /// chain would race the engine's own writes.
  Future<void> resetRun() async {
    if (state.busy || state.isRunning) return;
    state = state.copyWith(busy: true, clearGateMessage: true);
    try {
      final ok = await backend.pipelineReset(boardId);
      if (_stopped) return;
      state = state.copyWith(
        busy: false,
        isPaused: false,
        gateMessage: ok ? null : 'the engine refused to reset this run',
      );
      await hydrate();
    } catch (e) {
      if (_stopped) return;
      state = state.copyWith(busy: false, gateMessage: _describe(e));
    }
  }

  /// Put ONE step back to pending — the narrow version of [resetRun], for the
  /// step an operator wants to re-do without discarding the whole walk.
  Future<void> resetStep(String stepId) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearGateMessage: true);
    try {
      final ok = await backend.pipelineResetStep(boardId, stepId);
      if (_stopped) return;
      state = state.copyWith(
        busy: false,
        gateMessage: ok ? null : 'the engine refused to reset that step',
      );
      await hydrate();
    } catch (e) {
      if (_stopped) return;
      state = state.copyWith(busy: false, gateMessage: _describe(e));
    }
  }

  /// Re-run a PARKED (awaiting-input) step.
  ///
  /// When the step directly upstream is the comment/sense step, the run resumes
  /// from THERE, so a comment the reviewer just left is re-read fresh before the
  /// parked step re-dispatches. Anything else resumes from the parked step
  /// itself. Without the hop, Re-run only re-ran the current step and could
  /// never see the new input the operator had just supplied — a same-step no-op
  /// loop, and the reason this exists at all.
  ///
  /// Port of `DashboardViewModel.rerunParked` (D/P-4), matched keyword for
  /// keyword so the two apps resume from the same place.
  Future<void> rerunParked(String stepId) async {
    final index = state.steps.indexWhere((s) => s.id == stepId);
    var target = stepId;
    if (index > 0) {
      final upstream = state.steps[index - 1];
      final hay = '${upstream.id} ${upstream.title}'.toLowerCase();
      if (hay.contains('comment') ||
          hay.contains('sense') ||
          hay.contains('review')) {
        target = upstream.id;
      }
    }
    await retry(target);
  }

  /// The shared gate-write body: guard, write, surface a refusal, else resume
  /// and re-read. [write] returns null on success or the engine's refusal text.
  Future<void> _gate(
    String stepId, {
    required bool advance,
    required Future<String?> Function(DagStep step) write,
  }) async {
    if (state.busy) return;
    final step = _step(stepId);
    if (step == null) return;
    state = state.copyWith(busy: true, clearGateMessage: true);
    try {
      final refusal = await write(step);
      if (_stopped) return;
      if (refusal != null) {
        state = state.copyWith(busy: false, gateMessage: refusal);
        return;
      }
      if (advance) await backend.runPipeline(boardId);
      await reconstruct();
      state = state.copyWith(busy: false);
    } catch (e) {
      state = state.copyWith(busy: false, gateMessage: _describe(e));
    }
  }

  DagStep? _step(String stepId) {
    for (final s in state.steps) {
      if (s.id == stepId) return s;
    }
    return null;
  }

  // ---- the authoritative read ----------------------------------------------

  /// Build the whole surface from one `pipelineStatus` read. The persisted read
  /// is the truth about STATE; live per-item counters are event-only detail and
  /// are deliberately not carried across it.
  DashboardState _fromStatus(PipelineStatus status) {
    final steps = [
      for (final s in status.steps)
        DagStep(
          id: s.stepId,
          title: s.title,
          stage: s.stage,
          state: _stateOf(s.status),
          actor: s.executor == 'manual'
              ? DashboardStepActor.human
              : DashboardStepActor.ai,
          dependsOn: s.dependsOn,
          isReviewHold: s.isReviewHold,
          waitingOn: s.waitingOn,
          error: s.error,
          approvedBy: s.approvedBy,
        ),
    ];

    // idle == compiled but nothing executed: the DAG preview. `failed`/`done`
    // are the engine's terminal states; everything else is live.
    final phase = switch (status.status) {
      PipelineRunState.idle => DashboardPhase.preRun,
      PipelineRunState.done || PipelineRunState.failed => DashboardPhase.done,
      _ => DashboardPhase.running,
    };
    final finished = switch (status.status) {
      PipelineRunState.done => WorkflowRunState.done,
      PipelineRunState.failed => WorkflowRunState.failed,
      _ => null,
    };

    final settled = steps
        .where((s) =>
            s.state == DashboardStepState.approved ||
            s.state == DashboardStepState.done)
        .length;

    return DashboardState(
      hydrated: true,
      phase: phase,
      runId: status.runId ?? '',
      workflowLabel: state.workflowLabel,
      steps: steps,
      finished: finished,
      // Pre-run there is nothing metered yet; a zeroed panel would be a claim
      // about a run that has not happened.
      snapshot: phase == DashboardPhase.preRun
          ? null
          : _localSnapshot(status, settled),
      currentItem: state.currentItem,
      currentStage: state.currentStage,
      itemsProcessed: settled,
      itemsTotal: steps.length,
      gateMessage: state.gateMessage,
      busy: state.busy,
      droppedFrames: state.droppedFrames,
    );
  }

  /// The run meter the PERSISTED read can honestly report: the engine's own
  /// monotonic cost, and minutes from the SAME persisted step durations (one
  /// source of truth — Swift `reconstruct()` builds exactly this dict). A live
  /// `WorkflowStatsUpdated` replaces it wholesale.
  DashboardSnapshot _localSnapshot(PipelineStatus status, int settled) {
    var seconds = 0.0;
    for (final s in status.steps) {
      seconds += s.durationSecs ?? 0;
    }
    final minutes = seconds / 60.0;
    return DashboardSnapshot(
      tenantId: '',
      boardId: status.boardId,
      runId: status.runId ?? '',
      workflowId: status.boardId,
      workflowLabel: state.workflowLabel,
      updatedAt: 0,
      itemsProcessed: settled,
      itemsTotal: status.steps.length,
      totals: DashboardTotals(
        wallMinutes: minutes,
        // AI steps are the agentic work, so wall == ai here; gate time is not
        // separately metered by the engine yet, and inventing a split would be
        // a number nobody measured.
        humanMinutes: 0,
        aiMinutes: minutes,
        filesProcessed: settled,
        estCostUsd: status.totalCostDollars,
      ),
    );
  }

  static DashboardStepState _stateOf(PipelineStepState s) => switch (s) {
        PipelineStepState.pending => DashboardStepState.pending,
        PipelineStepState.running => DashboardStepState.running,
        PipelineStepState.aiComplete => DashboardStepState.awaitingApproval,
        PipelineStepState.humanApproved => DashboardStepState.approved,
        PipelineStepState.needsLens => DashboardStepState.needsLens,
        PipelineStepState.failed => DashboardStepState.failed,
      };

  // ---- event application ---------------------------------------------------

  /// Apply one decoded frame. Pure: takes a state, returns a state, so a
  /// discarded cycle costs nothing.
  DashboardState _apply(DashboardState s, DashboardEvent e) {
    // Run scoping (Swift `accept`): the surface follows ONE run. The first
    // frame latches which; a frame for another run is not ours to render.
    if (s.runId.isNotEmpty && s.runId != e.runId) return s;
    var next = s.runId.isEmpty ? s.copyWith(runId: e.runId) : s;

    switch (e) {
      case RunStarted():
        return next.copyWith(
          phase: DashboardPhase.running,
          clearFinished: true,
          workflowLabel:
              e.workflowLabel.isEmpty ? next.workflowLabel : e.workflowLabel,
          // A resume re-emits the start of the SAME run; reseeding here would
          // wipe the live states we already hold (Swift's first-approve bug).
          steps: next.steps.isEmpty
              ? [
                  for (var i = 0; i < e.totalSteps; i++)
                    DagStep(
                      id: 'step-$i',
                      title: 'Step ${i + 1}',
                      state: DashboardStepState.pending,
                      actor: DashboardStepActor.ai,
                    ),
                ]
              : next.steps,
          itemsTotal: next.steps.isEmpty ? e.totalSteps : next.itemsTotal,
        );

      case StepStateChanged():
        return _upsert(
          _live(next),
          e.stepId,
          name: e.name,
          stage: e.stage,
          actor: e.actor,
          mutate: (st) => st.copyWith(state: e.state),
        );

      case StepProgress():
        next = _live(next).copyWith(
          itemsProcessed: e.processed,
          itemsTotal: e.total,
          currentItem: e.currentItem,
        );
        return _upsert(
          next,
          e.stepId,
          mutate: (st) => st.copyWith(
            processed: e.processed,
            total: e.total,
            currentItem: e.currentItem,
          ),
        );

      case ApprovalRequested():
        return _upsert(
          _live(next),
          e.stepId,
          name: e.name,
          mutate: (st) =>
              st.copyWith(state: DashboardStepState.awaitingApproval),
        );

      case ApprovalResolved():
        return _upsert(
          _live(next),
          e.stepId,
          mutate: (st) => st.copyWith(
            state: e.decision == 'approved'
                ? DashboardStepState.approved
                : DashboardStepState.failed,
          ),
        );

      case RunFinished():
        return next.copyWith(phase: DashboardPhase.done, finished: e.state);

      case StatsUpdated():
        return next.copyWith(
          // The stats panel is a pure echo of the snapshot the engine sends.
          snapshot: e.snapshot,
          currentItem: e.snapshot.currentItem,
          currentStage: e.snapshot.currentStage,
          itemsProcessed: e.snapshot.itemsProcessed,
          itemsTotal: e.snapshot.itemsTotal,
          workflowLabel: e.snapshot.workflowLabel.isEmpty
              ? next.workflowLabel
              : e.snapshot.workflowLabel,
        );
    }
  }

  /// A step-level frame is proof the run is moving: a surface still showing the
  /// pre-run preview has to flip live, or the DAG the operator is watching is a
  /// plan while the engine is already past it.
  DashboardState _live(DashboardState s) => s.phase == DashboardPhase.preRun
      ? s.copyWith(phase: DashboardPhase.running)
      : s;

  /// Mutate a step by id, appending one the engine names that we have never
  /// seen — a live run may grow steps we were not told about up front.
  DashboardState _upsert(
    DashboardState s,
    String stepId, {
    String? name,
    String? stage,
    DashboardStepActor? actor,
    required DagStep Function(DagStep) mutate,
  }) {
    final steps = [...s.steps];
    final idx = steps.indexWhere((st) => st.id == stepId);
    if (idx >= 0) {
      var st = steps[idx];
      if (name != null && name.isNotEmpty) st = st.copyWith(title: name);
      if (stage != null && stage.isNotEmpty) st = st.copyWith(stage: stage);
      if (actor != null) st = st.copyWith(actor: actor);
      steps[idx] = mutate(st);
    } else {
      steps.add(mutate(DagStep(
        id: stepId,
        title: (name == null || name.isEmpty) ? stepId : name,
        stage: stage ?? '',
        state: DashboardStepState.pending,
        actor: actor ?? DashboardStepActor.ai,
      )));
    }
    return s.copyWith(steps: steps, itemsTotal: steps.length);
  }

  static String _describe(Object e) {
    final text = e.toString().trim();
    // Strip Dart's decoration so the surface shows the ENGINE's words.
    for (final p in const ['Exception: ', 'Bad state: ', 'StateError: ']) {
      if (text.startsWith(p)) return text.substring(p.length);
    }
    return text;
  }
}
