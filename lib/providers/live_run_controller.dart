// providers/live_run_controller.dart
//
// PARITY port of the SwiftUI live-run pump: `ComponentActor`'s event producer
// (Actors/ComponentActor.swift) feeding `DashboardViewModel.apply(_:)`, with
// `reconstruct()` as the authoritative re-read and `SyncStatusMachine`'s
// connection tier above it (ViewModels/SyncStatusMachine.swift).
//
// This file exists because the pump is where a shipping app meets a HOSTILE
// engine. The four things the engine actually does to us, and what each means
// here:
//
//   1. it answers NOTHING. `pollEvents` returning null is the EMPTY buffer —
//      the normal answer, not a fault. `loadRun` returning null is "this board
//      has no run", a confirmed answer, not a failure. Neither may degrade the
//      surface and neither may stop the pump.
//   2. it speaks a DIALECT WE DON'T KNOW. A newer engine ships a variant this
//      build has never compiled against; a truncated write leaves half a frame
//      in the buffer. Undecodable frames are dropped and COUNTED — never
//      thrown, never allowed to abort the rest of the drain.
//   3. it gets AHEAD OF US. When one drain cycle hits [drainCap] the buffer is
//      producing faster than we consume, so the deltas we hold are a PARTIAL
//      story — applying them paints a state that never existed. We discard the
//      cycle and re-read the authoritative run instead. (Swift bounds the same
//      loop at `drained > 200`; the VM's `reconstruct()` is the re-read.)
//   4. it DIES. A throwing seam call must not blank a surface that was showing
//      a real run a moment ago. We keep the last good read, mark the link
//      degraded, name the engine's own error, and offer Retry.
//
// Talks ONLY to the `CyanBackend` seam — never `CyanFFI`.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/cyan_backend.dart';
import '../ffi/parity_models.dart';
import '../models/dashboard_event.dart';

/// How the surface is currently reaching the engine. Mirrors the honest half
/// of Swift's `SyncState` — the states a run surface can actually be in.
enum LiveRunLink {
  /// Reads are landing. The buffer being empty is still `live`.
  live,

  /// The buffer ran ahead of us; we dropped a partial cycle and re-read.
  catchingUp,

  /// A seam call threw, but we still hold a real run to show.
  degraded,

  /// A seam call threw and we never got a first read in.
  unreachable,
}

/// One step as the live surface knows it: the persisted state, refined by
/// whatever `StepProgress` frames have landed since.
class LiveStep {
  final String id;
  final String title;
  final DashboardStepState state;
  final DashboardStepActor actor;
  final int? processed;
  final int? total;
  final String? currentItem;

  const LiveStep({
    required this.id,
    required this.title,
    required this.state,
    required this.actor,
    this.processed,
    this.total,
    this.currentItem,
  });

  LiveStep copyWith({
    String? title,
    DashboardStepState? state,
    DashboardStepActor? actor,
    int? processed,
    int? total,
    String? currentItem,
  }) =>
      LiveStep(
        id: id,
        title: title ?? this.title,
        state: state ?? this.state,
        actor: actor ?? this.actor,
        processed: processed ?? this.processed,
        total: total ?? this.total,
        currentItem: currentItem ?? this.currentItem,
      );

  /// "12 / 40" when the step reports counts, else null.
  String? get progressLabel =>
      (processed != null && total != null && total! > 0)
          ? '$processed / $total'
          : null;
}

/// Everything the live-run surface renders. Deliberately a plain value: the
/// widget is a pure function of it, so every hostile case is a state, not a
/// special code path in the view.
class LiveRunState {
  /// True once a read attempt (successful or not) has completed. Only false
  /// before the first one — the ONLY time a spinner is honest.
  final bool hydrated;

  /// True when the engine confirmed a run exists. False after a null read is
  /// an ANSWER ("no run yet"), not an absence of one.
  final bool hasRun;

  final String runId;
  final String title;
  final List<LiveStep> steps;

  final LiveRunLink link;

  /// Frames the engine sent that this build could not decode. Surfaced rather
  /// than hidden: silently eating them is how a version skew goes unnoticed.
  final int droppedFrames;

  /// The engine's own error text from the last failed call. Never invented.
  final String? lastError;

  final String? currentItem;
  final int itemsProcessed;
  final int itemsTotal;
  final DashboardSnapshot? snapshot;
  final WorkflowRunState? finished;

  const LiveRunState({
    required this.hydrated,
    required this.hasRun,
    required this.runId,
    required this.title,
    required this.steps,
    required this.link,
    required this.droppedFrames,
    this.lastError,
    this.currentItem,
    this.itemsProcessed = 0,
    this.itemsTotal = 0,
    this.snapshot,
    this.finished,
  });

  static const LiveRunState initial = LiveRunState(
    hydrated: false,
    hasRun: false,
    runId: '',
    title: '',
    steps: [],
    link: LiveRunLink.live,
    droppedFrames: 0,
  );

  LiveRunState copyWith({
    bool? hydrated,
    bool? hasRun,
    String? runId,
    String? title,
    List<LiveStep>? steps,
    LiveRunLink? link,
    int? droppedFrames,
    String? lastError,
    bool clearError = false,
    bool clearFinished = false,
    String? currentItem,
    int? itemsProcessed,
    int? itemsTotal,
    DashboardSnapshot? snapshot,
    WorkflowRunState? finished,
  }) =>
      LiveRunState(
        hydrated: hydrated ?? this.hydrated,
        hasRun: hasRun ?? this.hasRun,
        runId: runId ?? this.runId,
        title: title ?? this.title,
        steps: steps ?? this.steps,
        link: link ?? this.link,
        droppedFrames: droppedFrames ?? this.droppedFrames,
        lastError: clearError ? null : (lastError ?? this.lastError),
        currentItem: currentItem ?? this.currentItem,
        itemsProcessed: itemsProcessed ?? this.itemsProcessed,
        itemsTotal: itemsTotal ?? this.itemsTotal,
        snapshot: snapshot ?? this.snapshot,
        finished: clearFinished ? null : (finished ?? this.finished),
      );

  /// The run-level pill, derived exactly as the Dashboard face derives it.
  String get statusLabel {
    if (finished != null) {
      return switch (finished!) {
        WorkflowRunState.done => 'Done',
        WorkflowRunState.failed => 'Failed',
        WorkflowRunState.cancelled => 'Cancelled',
        WorkflowRunState.running => 'Running',
      };
    }
    if (steps.isEmpty) return 'Queued';
    if (steps.every((s) => s.state == DashboardStepState.done)) return 'Done';
    if (steps.any((s) =>
        s.state == DashboardStepState.running ||
        s.state == DashboardStepState.awaitingApproval)) {
      return 'Running';
    }
    return 'Queued';
  }

  int get completedSteps =>
      steps.where((s) => s.state == DashboardStepState.done).length;
}

/// The pump. Owns the drain loop, the decode, the scoping and the healing.
///
/// The timer is NOT wired in the constructor: [start] is explicit so a test
/// can drive [tick] frame by frame and assert what one cycle did, exactly as
/// the Swift producer task is one `while` body per cycle.
class LiveRunController extends StateNotifier<LiveRunState> {
  LiveRunController({
    required this.backend,
    required this.boardId,
    this.component = 'status',
  }) : super(LiveRunState.initial);

  /// The bound on ONE drain cycle. The Swift producer breaks at `drained > 200`
  /// — the same number, because it is the producer's own contract with us, not
  /// a figure invented here.
  static const int drainCap = 200;

  final CyanBackend backend;
  final String boardId;

  /// The engine buffer these events ride. The live producer routes dashboard
  /// events onto the shared `status` buffer (there is no bespoke "dashboard"
  /// channel; an unknown name simply returns nothing).
  final String component;

  /// The published state, readable by callers that drive the pump directly
  /// (`StateNotifier.state` is protected).
  LiveRunState get current => state;

  Timer? _timer;
  bool _stopped = false;

  /// Coalesces overlapping cycles — a slow engine drops the tick that would
  /// stack behind it rather than queueing reads (Swift's `reconstructInFlight`).
  bool _inFlight = false;

  /// Read the authoritative run. This is the ONLY way state is established:
  /// events refine it, they never bootstrap it.
  Future<void> hydrate() async {
    if (_stopped) return;
    try {
      await backend.initialize();
      final run = await backend.loadRun(boardId);
      state = _authoritative(run);
    } catch (e) {
      state = _degrade(e);
    }
  }

  /// One pump cycle: drain, decode, apply. Never throws.
  Future<void> tick() async {
    if (_stopped || _inFlight) return;
    _inFlight = true;
    try {
      final healing = state.link == LiveRunLink.degraded ||
          state.link == LiveRunLink.unreachable;

      // Drain everything available, bounded. A null answer ends the cycle —
      // that is the buffer being empty, which is the normal case.
      final frames = <String>[];
      while (frames.length < drainCap) {
        final raw = await backend.pollEvents(component);
        if (raw == null) break;
        frames.add(raw);
      }

      // We filled the whole cycle: the producer is ahead of us and these
      // deltas are a partial story. Discard them and re-read the truth.
      final lagged = frames.length >= drainCap;

      if (healing || lagged) {
        final run = await backend.loadRun(boardId);
        state = _authoritative(run).copyWith(
          link: lagged ? LiveRunLink.catchingUp : LiveRunLink.live,
          droppedFrames: state.droppedFrames,
          clearError: true,
        );
        // The deltas were never applied — the re-read replaced them.
        if (lagged) return;
      }

      var next = state;
      var dropped = 0;
      for (final raw in frames) {
        final event = DashboardEvent.fromJson(raw);
        if (event == null) {
          // A variant we don't know, a truncated write, a non-object, or a
          // frame with no run to attach to. Count it and keep draining — one
          // bad frame must never cost us the good frames behind it.
          dropped++;
          continue;
        }
        next = _applyEvent(next, event);
      }

      state = next.copyWith(
        hydrated: true,
        link: LiveRunLink.live,
        droppedFrames: state.droppedFrames + dropped,
        clearError: true,
      );
    } catch (e) {
      state = _degrade(e);
    } finally {
      _inFlight = false;
    }
  }

  /// Start the real pump. Idle cadence matches the Swift producer's 100ms
  /// empty-buffer sleep.
  void start({Duration interval = const Duration(milliseconds: 100)}) {
    if (_stopped || _timer != null) return;
    _timer = Timer.periodic(interval, (_) => tick());
  }

  void stopPump() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  /// The Retry affordance on the degraded strip: re-read authoritatively.
  Future<void> retry() async {
    _stopped = false;
    await hydrate();
  }

  @override
  void dispose() {
    stopPump();
    super.dispose();
  }

  // ---- state construction --------------------------------------------------

  /// Build state from an authoritative read. A null [run] is an ANSWER: this
  /// board has no run. It is not a failure and it does not degrade the link.
  LiveRunState _authoritative(WorkflowRun? run) {
    if (run == null) {
      return LiveRunState.initial.copyWith(
        hydrated: true,
        hasRun: false,
        link: LiveRunLink.live,
        droppedFrames: state.droppedFrames,
        clearError: true,
      );
    }
    return state.copyWith(
      hydrated: true,
      hasRun: true,
      title: run.title,
      // The persisted read is the truth about STATE; per-step progress
      // counters are event-only detail and are not carried across it.
      steps: [
        for (final s in run.steps)
          LiveStep(
            id: s.id,
            title: s.title,
            state: _stateOf(s.status),
            actor: s.kind == RunStepKind.human
                ? DashboardStepActor.human
                : DashboardStepActor.ai,
          ),
      ],
      link: LiveRunLink.live,
      clearError: true,
    );
  }

  /// Keep every byte of the last good read and say what broke. A surface that
  /// was showing a run must not become a blank one because a poll threw.
  LiveRunState _degrade(Object error) => state.copyWith(
        hydrated: true,
        link: state.hasRun ? LiveRunLink.degraded : LiveRunLink.unreachable,
        lastError: _describe(error),
      );

  static String _describe(Object e) {
    final text = e.toString().trim();
    // Strip Dart's own decoration so the strip shows the ENGINE's words.
    const prefixes = ['Exception: ', 'Bad state: ', 'StateError: '];
    for (final p in prefixes) {
      if (text.startsWith(p)) return text.substring(p.length);
    }
    return text;
  }

  static DashboardStepState _stateOf(RunStepStatus s) => switch (s) {
        RunStepStatus.pending => DashboardStepState.pending,
        RunStepStatus.running => DashboardStepState.running,
        RunStepStatus.awaitingApproval => DashboardStepState.awaitingApproval,
        RunStepStatus.done => DashboardStepState.done,
        RunStepStatus.failed => DashboardStepState.failed,
      };

  // ---- event application ---------------------------------------------------

  /// Apply one decoded event. Pure: takes a state, returns a state — so a
  /// discarded drain cycle costs nothing.
  LiveRunState _applyEvent(LiveRunState s, DashboardEvent e) {
    // Run scoping. The surface follows ONE run; the first frame latches which,
    // and a frame for a different run is not ours to render.
    if (s.runId.isNotEmpty && s.runId != e.runId) return s;
    var next = s.runId.isEmpty ? s.copyWith(runId: e.runId) : s;

    switch (e) {
      case RunStarted():
        return next.copyWith(
          hasRun: true,
          title: e.workflowLabel.isEmpty ? next.title : e.workflowLabel,
          clearFinished: true,
          steps: next.steps.isEmpty
              ? [
                  for (var i = 0; i < e.totalSteps; i++)
                    LiveStep(
                      id: 'step-$i',
                      title: 'Step ${i + 1}',
                      state: DashboardStepState.pending,
                      actor: DashboardStepActor.ai,
                    ),
                ]
              : next.steps,
        );

      case StepStateChanged():
        return _upsert(next, e.stepId,
            name: e.name,
            actor: e.actor,
            mutate: (st) => st.copyWith(state: e.state));

      case StepProgress():
        next = next.copyWith(
          itemsProcessed: e.processed,
          itemsTotal: e.total,
          currentItem: e.currentItem,
        );
        return _upsert(next, e.stepId,
            mutate: (st) => st.copyWith(
                  processed: e.processed,
                  total: e.total,
                  currentItem: e.currentItem,
                ));

      case ApprovalRequested():
        return _upsert(next, e.stepId,
            name: e.name,
            mutate: (st) =>
                st.copyWith(state: DashboardStepState.awaitingApproval));

      case ApprovalResolved():
        return _upsert(next, e.stepId,
            mutate: (st) => st.copyWith(
                  state: e.decision == 'approved'
                      ? DashboardStepState.approved
                      : DashboardStepState.failed,
                ));

      case RunFinished():
        return next.copyWith(finished: e.state);

      case StatsUpdated():
        return next.copyWith(
          snapshot: e.snapshot,
          currentItem: e.snapshot.currentItem,
          itemsProcessed: e.snapshot.itemsProcessed,
          itemsTotal: e.snapshot.itemsTotal,
          title: e.snapshot.workflowLabel.isEmpty
              ? next.title
              : e.snapshot.workflowLabel,
        );
    }
  }

  /// Mutate a step by id, appending one if the engine names a step we have
  /// never seen — a live run may grow steps we were not told about up front.
  LiveRunState _upsert(
    LiveRunState s,
    String stepId, {
    String? name,
    DashboardStepActor? actor,
    required LiveStep Function(LiveStep) mutate,
  }) {
    final steps = [...s.steps];
    final idx = steps.indexWhere((st) => st.id == stepId);
    if (idx >= 0) {
      var st = steps[idx];
      if (name != null && name.isNotEmpty) st = st.copyWith(title: name);
      if (actor != null) st = st.copyWith(actor: actor);
      steps[idx] = mutate(st);
    } else {
      steps.add(mutate(LiveStep(
        id: stepId,
        title: (name == null || name.isEmpty) ? stepId : name,
        state: DashboardStepState.pending,
        actor: actor ?? DashboardStepActor.ai,
      )));
    }
    return s.copyWith(steps: steps, hasRun: true);
  }
}
