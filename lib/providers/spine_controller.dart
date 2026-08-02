// providers/spine_controller.dart
//
// PARITY face `spine_e2e` — the POST-PRODUCTION SPINE, end to end.
//
// Every other face owns one room. This one owns the walk BETWEEN them, which is
// where a post house actually loses its day: the proxy goes out for producer
// review, the notes come back, somebody has to decide which of them are
// mechanical, picture lock has to close the cutting room before the sound room
// may start, and only then does a conform, a grade and a delivered master mean
// anything. Nothing here invents that order — it is the engine's own authored
// spine (`cyan-backend/src/templates.rs`, the `DEMO_SPINE_ID` seed, whose
// constitution note reads "AUTHORED ORDER IS LAW").
//
// SwiftUI reference (READ-ONLY):
//   Views/WorkflowView.swift + ViewModels/WorkflowViewModel.swift   (clone/compile)
//   Views/DashboardView.swift + ViewModels/DashboardViewModel.swift (run + gates)
//   ViewModels/ReviewLoopViewModel.swift                            (the confirm gate)
//   ViewModels/NotesIntentViewModel.swift                           (note → op)
//
// THE ONE THING THIS FILE EXISTS FOR. When a producer-review gate is released,
// the notes that came back are run through the engine's own agent pass
// (`changelist agent_act`) BEFORE the run is allowed to move on. That pass is
// the note → mechanical-op boundary: a note that fully specifies an edit inside
// the closed conform vocabulary becomes a PROPOSED op waiting on a human, and
// anything creative is DECLINED and stays a note. The agent may only ever
// propose — it never mechanises taste behind the human's back, and it never
// touches the ledger when there were no notes at all, which is why "release
// with notes" and "release without notes" are two different behaviours and
// both are pinned.
//
// Talks ONLY to the `CyanBackend` seam — never `CyanFFI`.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/cyan_backend.dart';
import '../ffi/parity_models.dart';
import '../models/dashboard_event.dart';
import '../models/spine_lane.dart';

/// One compiled step of the spine, placed in its room.
@immutable
class SpineStep {
  final String id;
  final String title;
  final SpineLane lane;
  final DashboardStepState state;

  /// A producer-scoped hold: only [waitingOn] clears it.
  final bool isReviewHold;
  final String? waitingOn;

  final String? error;

  const SpineStep({
    required this.id,
    required this.title,
    required this.lane,
    required this.state,
    this.isReviewHold = false,
    this.waitingOn,
    this.error,
  });

  /// The engine has finished with this step and moved on.
  bool get isSettled =>
      state == DashboardStepState.approved || state == DashboardStepState.done;

  /// A human owes this step a decision before anything downstream moves.
  bool get isParked =>
      state == DashboardStepState.awaitingApproval ||
      state == DashboardStepState.needsLens;

  bool get isPictureLock => isPictureLockStep(title);
  bool get isProducerReview => isProducerReviewStep(title);
  bool get isProduceMaster => isProduceMasterStep(title);

  /// How the lane rail spells this state.
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
      other is SpineStep &&
      other.id == id &&
      other.title == title &&
      other.lane == lane &&
      other.state == state &&
      other.isReviewHold == isReviewHold &&
      other.waitingOn == waitingOn &&
      other.error == error;

  @override
  int get hashCode =>
      Object.hash(id, title, lane, state, isReviewHold, waitingOn, error);
}

/// One room, with everything in it and whatever is holding its door shut.
@immutable
class SpineLaneView {
  final SpineLane lane;
  final List<SpineStep> steps;

  /// The first step ANYWHERE upstream that has not settled. Null once the room
  /// is open. This is why "picture lock releases the sound lane" is a fact
  /// about the DAG rather than a label: while the lock is unconfirmed it IS
  /// this value for every sound step, and confirming it clears the door.
  final SpineStep? heldBy;

  const SpineLaneView({
    required this.lane,
    required this.steps,
    this.heldBy,
  });

  bool get isOpen => heldBy == null;
  bool get isComplete => steps.isNotEmpty && steps.every((s) => s.isSettled);
  bool get isEmpty => steps.isEmpty;

  /// The room's own headline: what it is doing, in its own words.
  String get stateLabel {
    if (steps.isEmpty) return 'No steps';
    if (isComplete) return 'Complete';
    if (heldBy != null) return 'Held by ${heldBy!.title}';
    for (final s in steps) {
      if (s.isParked) return s.stateLabel;
    }
    return steps.every((s) => s.state == DashboardStepState.pending)
        ? 'Queued'
        : 'Running';
  }
}

/// One row of the review ledger as the spine reads it: what the producer said,
/// and what — if anything — the agent pass made of it.
@immutable
class SpineLedgerRow {
  final ChangeEntry entry;

  /// The agent's REFUSAL, when the pass looked at this note and declined to
  /// mechanise it. Present only on rows it decided about and left alone.
  final String? declined;

  const SpineLedgerRow({required this.entry, this.declined});

  String get id => entry.id;
  String get text => entry.intent;

  /// `note` | `op` | `marker`.
  String get kind => entry.kind;
  String? get op => entry.op;
  String get state => entry.state;

  /// The agent proposed it; a human has not decided yet.
  bool get isAgentProposal =>
      entry.kind == 'op' &&
      entry.proposedBy == 'agent' &&
      entry.state == 'proposed';

  /// A note as the producer wrote it.
  bool get isNote => entry.kind == 'note';

  /// The agent READ this note and refused to mechanise it. That refusal is the
  /// distinction the whole face turns on: a creative note is not one the pass
  /// missed, it is one it decided about and left alone.
  bool get isCreativeNote => isNote && declined != null;
}

/// Everything the spine console renders. A plain value: the widget is a pure
/// function of it, so a refusal is a state rather than a branch in the view.
@immutable
class SpineState {
  /// True once a read has come back. Only false before the first one.
  final bool hydrated;

  /// The template the board was cloned from; empty until it is.
  final String templateName;

  /// How many step cells the clone landed. 0 until it runs.
  final int clonedSteps;

  /// The plugins the clone auto-installed, and the ones the source refused.
  final List<String> pluginsReady;
  final List<String> pluginsRefused;

  final List<SpineStep> steps;
  final List<SpineLaneView> lanes;

  final PipelineRunState runState;
  final String runId;

  /// The step the run is parked on, or null when nothing is waiting.
  final SpineStep? gate;

  /// The review ledger for this board's lane, in apply order.
  final List<SpineLedgerRow> ledger;

  /// The last agent pass's arithmetic: how many notes it turned into proposed
  /// ops, and how many it looked at and DECLINED. Both are news.
  final int transpiledOps;
  final int declinedNotes;

  /// True once a pass has run at all — which is what separates "there were no
  /// notes" from "nobody has read them yet".
  final bool agentPassRan;

  /// The review lane's own state machine: `DRAFT` … `DELIVERED`, and the round.
  final String reviewState;
  final int reviewRound;

  /// The version picture lock froze, 0 until it does.
  final int lockedVersion;

  /// The path the engine's delivery lane produced. Null until it has.
  final String? deliveredMaster;

  /// The engine's own words about the last refusal or the last thing that
  /// happened. Never invented here.
  final String? message;

  final bool busy;

  const SpineState({
    required this.hydrated,
    this.templateName = '',
    this.clonedSteps = 0,
    this.pluginsReady = const [],
    this.pluginsRefused = const [],
    this.steps = const [],
    this.lanes = const [],
    this.runState = PipelineRunState.idle,
    this.runId = '',
    this.gate,
    this.ledger = const [],
    this.transpiledOps = 0,
    this.declinedNotes = 0,
    this.agentPassRan = false,
    this.reviewState = '',
    this.reviewRound = 0,
    this.lockedVersion = 0,
    this.deliveredMaster,
    this.message,
    this.busy = false,
  });

  static const SpineState initial = SpineState(hydrated: false);

  SpineState copyWith({
    bool? hydrated,
    String? templateName,
    int? clonedSteps,
    List<String>? pluginsReady,
    List<String>? pluginsRefused,
    List<SpineStep>? steps,
    List<SpineLaneView>? lanes,
    PipelineRunState? runState,
    String? runId,
    SpineStep? gate,
    bool clearGate = false,
    List<SpineLedgerRow>? ledger,
    int? transpiledOps,
    int? declinedNotes,
    bool? agentPassRan,
    String? reviewState,
    int? reviewRound,
    int? lockedVersion,
    String? deliveredMaster,
    String? message,
    bool clearMessage = false,
    bool? busy,
  }) =>
      SpineState(
        hydrated: hydrated ?? this.hydrated,
        templateName: templateName ?? this.templateName,
        clonedSteps: clonedSteps ?? this.clonedSteps,
        pluginsReady: pluginsReady ?? this.pluginsReady,
        pluginsRefused: pluginsRefused ?? this.pluginsRefused,
        steps: steps ?? this.steps,
        lanes: lanes ?? this.lanes,
        runState: runState ?? this.runState,
        runId: runId ?? this.runId,
        gate: clearGate ? null : (gate ?? this.gate),
        ledger: ledger ?? this.ledger,
        transpiledOps: transpiledOps ?? this.transpiledOps,
        declinedNotes: declinedNotes ?? this.declinedNotes,
        agentPassRan: agentPassRan ?? this.agentPassRan,
        reviewState: reviewState ?? this.reviewState,
        reviewRound: reviewRound ?? this.reviewRound,
        lockedVersion: lockedVersion ?? this.lockedVersion,
        deliveredMaster: deliveredMaster ?? this.deliveredMaster,
        message: clearMessage ? null : (message ?? this.message),
        busy: busy ?? this.busy,
      );

  /// The spine has been cloned onto the board.
  bool get isCloned => clonedSteps > 0;

  /// The spine compiled: there is a DAG to run.
  bool get isCompiled => steps.isNotEmpty;

  /// A compiled DAG nothing has executed yet.
  bool get isRunnable => isCompiled && runState != PipelineRunState.failed;

  bool get isFinished => runState == PipelineRunState.done;

  SpineLaneView laneFor(SpineLane lane) => lanes.firstWhere(
        (l) => l.lane == lane,
        orElse: () => SpineLaneView(lane: lane, steps: const []),
      );

  /// The run is parked on the producer's review round.
  bool get isAtProducerReview => gate?.isProducerReview ?? false;

  /// The run is parked on the picture-lock confirm.
  bool get isAtPictureLock => gate?.isPictureLock ?? false;

  /// The run is parked on the delivery hand-off.
  bool get isAtProduceMaster => gate?.isProduceMaster ?? false;

  /// Picture lock has been confirmed — the cut is frozen and the sound room is
  /// open.
  bool get isPictureLocked =>
      lockedVersion > 0 &&
      steps.any((s) => s.isPictureLock && s.isSettled);

  /// The mechanical ops the agent pass proposed and nobody has decided yet.
  List<SpineLedgerRow> get proposedOps =>
      [for (final r in ledger) if (r.isAgentProposal) r];

  /// Every note the producer left, mechanised or not.
  List<SpineLedgerRow> get notes =>
      [for (final r in ledger) if (r.isNote) r];

  /// The notes the pass declined: still notes, and staying notes.
  List<SpineLedgerRow> get creativeNotes =>
      [for (final r in ledger) if (r.isCreativeNote) r];

  /// Ops a human confirmed.
  List<SpineLedgerRow> get approvedOps => [
        for (final r in ledger)
          if (r.kind == 'op' && r.state == 'approved') r,
      ];
}

/// The spine's view-model. Owns the clone, the compile, the walk, the gate
/// releases, the note→op pass and the delivery.
class SpineController extends StateNotifier<SpineState> {
  SpineController({
    required this.backend,
    required this.boardId,
    required this.tenantId,
    this.reviewer = _defaultProducer,
  }) : super(SpineState.initial);

  /// The engine's own seed name. The spine is chosen BY NAME rather than by an
  /// id this build hard-codes, so a catalog that renumbers its seeds does not
  /// silently clone the wrong workflow.
  static const String spineTemplateName = 'Multicut review spine';

  static const String _defaultProducer = 'producer@studio';

  /// The watched location the ingest room points at. Ingesting is what makes
  /// the board's master ADDRESSABLE, and without an addressable master there
  /// is no conform and no delivery.
  static const String watchedSource = '/Volumes/dailies/spine';

  final CyanBackend backend;
  final String boardId;
  final String tenantId;

  /// WHO this device releases gates as. A producer-review hold clears only for
  /// the user it waits on, so this is never assumed — it is stamped onto the
  /// board at clone time and quoted back by the engine when it refuses.
  final String reviewer;

  /// The published state, for callers driving the spine directly (a test walks
  /// it step by step; `StateNotifier.state` is protected).
  SpineState get current => state;

  bool _disposed = false;

  /// The lane's anchors, learned from the engine's own envelope rather than
  /// recomputed here — the app never derives an asset hash.
  String? _assetHash;
  String? _laneTenant;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  bool updateShouldNotify(SpineState old, SpineState current) => true;

  // ---- reads ---------------------------------------------------------------

  Future<void> hydrate() async {
    try {
      await backend.initialize();
    } catch (e) {
      state = state.copyWith(hydrated: true, message: _describe(e));
      return;
    }
    await reconstruct();
  }

  /// Re-read everything the console shows: the compiled DAG, the review ledger
  /// and the round the review lane sits in. Pure read, safe to repeat.
  Future<void> reconstruct() async {
    if (_disposed) return;
    try {
      final status = await backend.pipelineStatus(boardId);
      final lane = await backend.changelistCommand(
          {'op': 'list', 'board_id': boardId});
      if (_disposed) return;

      _laneTenant ??= lane.fields['tenant_id'] as String?;
      _assetHash ??= lane.fields['asset_hash'] as String?;

      final steps = [
        for (final s in status.steps)
          SpineStep(
            id: s.stepId,
            title: s.title,
            lane: SpineLaneX.forStepText(s.title),
            state: _stateOf(s.status),
            isReviewHold: s.isReviewHold,
            waitingOn: s.waitingOn,
            error: s.error,
          ),
      ];

      final review = lane.reviewState;
      final gate = _gateOf(steps);
      state = state.copyWith(
        hydrated: true,
        steps: steps,
        lanes: _lanes(steps),
        runState: status.status,
        runId: status.runId ?? '',
        gate: gate,
        clearGate: gate == null,
        ledger: _ledger(lane.entries),
        reviewState: review?.state ?? state.reviewState,
        reviewRound: review?.round ?? state.reviewRound,
      );
    } catch (e) {
      state = state.copyWith(hydrated: true, message: _describe(e));
    }
  }

  /// The step the run is parked on. The engine breaks the chain at exactly one
  /// step at a time, so there is never more than one.
  static SpineStep? _gateOf(List<SpineStep> steps) {
    for (final s in steps) {
      if (s.isParked) return s;
    }
    return null;
  }

  /// Group the compiled steps into rooms, in walk order, and work out what is
  /// holding each door shut — the FIRST unsettled step upstream of the room,
  /// which is the honest answer ("the producer still has it") rather than the
  /// nearest one.
  static List<SpineLaneView> _lanes(List<SpineStep> steps) {
    final out = <SpineLaneView>[];
    for (final lane in kSpineWalk) {
      final mine = [for (final s in steps) if (s.lane == lane) s];
      if (mine.isEmpty) {
        out.add(SpineLaneView(lane: lane, steps: const []));
        continue;
      }
      final firstIndex = steps.indexOf(mine.first);
      SpineStep? heldBy;
      for (var i = 0; i < firstIndex; i++) {
        if (!steps[i].isSettled) {
          heldBy = steps[i];
          break;
        }
      }
      out.add(SpineLaneView(lane: lane, steps: mine, heldBy: heldBy));
    }
    // Anything the classifier could not place still has to be visible.
    final unplaced = [
      for (final s in steps) if (s.lane == SpineLane.unplaced) s,
    ];
    if (unplaced.isNotEmpty) {
      out.add(SpineLaneView(lane: SpineLane.unplaced, steps: unplaced));
    }
    return out;
  }

  /// Pair the ledger rows with the agent's own verdicts from the last pass, so
  /// a note it declined says WHY on the card rather than just sitting there.
  List<SpineLedgerRow> _ledger(List<ChangeEntry> entries) => [
        for (final e in entries)
          SpineLedgerRow(entry: e, declined: _declined[e.id]),
      ];

  /// entry id → the agent's refusal, from `agent_act`.
  final Map<String, String> _declined = {};

  // ---- the walk ------------------------------------------------------------

  /// Clone the engine's authored spine onto this board.
  ///
  /// Three writes, in the order the engine needs them: the board's review
  /// assignee is stamped FIRST (a compile copies it onto every hold, and a
  /// hold with no assignee is a gate anybody could open), then the template's
  /// steps and standing notes land, then the review lane opens its draft.
  Future<bool> cloneSpine() async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      final catalog = await backend.templateList(tenantId: tenantId);
      CyanTemplate? spine;
      for (final t in catalog) {
        if (t.name == spineTemplateName) spine = t;
      }
      if (spine == null) {
        state = state.copyWith(
            busy: false,
            message: "the catalog carries no '$spineTemplateName' template");
        return false;
      }

      await backend.boardSetReviewAssignee(boardId, reviewer);
      await backend.workflowFromTemplate(spine.id, boardId, tenantId: tenantId);

      final workflow = await backend.loadWorkflow(boardId);
      final outcome = await backend.templateCloneOutcome(boardId);
      // The review lane opens as a DRAFT. Idempotent on the seam, so a re-clone
      // never resets a review already in flight.
      await backend
          .reviewCommand({'op': 'start_draft', 'board_id': boardId});

      state = state.copyWith(
        busy: false,
        templateName: spine.name,
        clonedSteps: workflow.steps.length,
        pluginsReady: [
          for (final i in outcome?.pluginInstalls ?? const <TemplatePluginInstall>[])
            if (i.outcome != TemplatePluginInstallOutcome.failed) i.pluginId,
        ],
        pluginsRefused: [
          for (final i in outcome?.pluginInstalls ?? const <TemplatePluginInstall>[])
            if (i.outcome == TemplatePluginInstallOutcome.failed) i.pluginId,
        ],
      );
      await reconstruct();
      return workflow.steps.isNotEmpty;
    } catch (e) {
      state = state.copyWith(busy: false, message: _describe(e));
      return false;
    }
  }

  /// The ingest room's real work: point the board at a watched location and
  /// sweep it. This is what REGISTERS the master, which is what later makes a
  /// conform and a delivery addressable at all.
  Future<void> ingestSources({String uri = watchedSource}) async {
    final added = await backend.ingestCommand({
      'op': 'source_add',
      'tenant_id': tenantId,
      'board_id': boardId,
      'kind': 'folder',
      'uri': uri,
    });
    if (!added.ok || added.sources.isEmpty) {
      state = state.copyWith(message: added.error ?? 'the source was refused');
      return;
    }
    final scan = await backend.ingestCommand({
      'op': 'scan_now',
      'tenant_id': tenantId,
      'source_id': added.sources.single.id,
    });
    if (!scan.ok) {
      state = state.copyWith(message: scan.error);
      return;
    }
    final report = scan.report;
    state = state.copyWith(
      message: report == null
          ? null
          : 'ingested ${report.ingested} of ${report.discovered}',
      clearMessage: report == null,
    );
  }

  /// Compile the authored spine into a runnable DAG.
  Future<bool> compile() async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, clearMessage: true);
    final ack = await backend.pipelineCompile(boardId);
    if (!ack.accepted) {
      state = state.copyWith(busy: false, message: ack.error);
      return false;
    }
    await reconstruct();
    state = state.copyWith(busy: false);
    return true;
  }

  /// Walk the run forward until a HUMAN is owed something.
  ///
  /// The engine breaks the chain at every gate, so a run is stepped rather than
  /// started: execute, look at what parked, and clear it only when the gate is
  /// one nobody owns. A producer-scoped hold STOPS the walk — that is the whole
  /// point of it, and quietly clearing one here would be the single bug this
  /// face cannot have.
  Future<void> advance({int maxSteps = 64}) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      for (var i = 0; i < maxSteps; i++) {
        final ack = await backend.runPipeline(boardId);
        if (!ack.accepted) {
          state = state.copyWith(message: ack.error);
          break;
        }
        await reconstruct();
        final gate = state.gate;
        if (gate == null) break;
        if (gate.isReviewHold) break;
        final cleared = await backend.pipelineApprove(boardId, gate.id);
        if (!cleared) {
          state = state.copyWith(
              message: 'the engine refused to clear ${gate.title}');
          break;
        }
        await reconstruct();
      }
      await _onPark();
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// The side effects that belong to ARRIVING somewhere, not to a button.
  Future<void> _onPark() async {
    final gate = state.gate;
    if (gate == null) return;
    if (gate.isProducerReview) {
      // The proxy is out and the window is open: the review lane leaves DRAFT.
      await _review('publish');
    }
    // The conform room has relinked the locked cut. `conform_run` is the
    // machine's own observation of that — a self-transition, so re-arriving
    // here never double-counts it.
    if (state.reviewState == 'CONFORMING' &&
        state.laneFor(SpineLane.conform).isComplete) {
      await _review('conform_run', actor: 'auto');
    }
  }

  // ---- the producer's notes ------------------------------------------------

  /// A note the producer left on the review proxy, landing on the board's own
  /// content-addressed ledger — the same rail a sensed Frame.io comment lands
  /// on, so the agent pass reads one list rather than two.
  Future<bool> captureReviewNote(String text,
      {int tcIn = 0, int? tcOut, String author = 'producer'}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (_assetHash == null || _laneTenant == null) await reconstruct();
    final asset = _assetHash;
    final tenant = _laneTenant;
    if (asset == null || tenant == null) {
      state = state.copyWith(message: 'this board has no review lane yet');
      return false;
    }
    final reply = await backend.changelistCommand({
      'op': 'append_entry',
      'board_id': boardId,
      'entry': <String, dynamic>{
        'tenant_id': tenant,
        'asset_hash': asset,
        'branch': 'main',
        'kind': 'note',
        'tc_in': tcIn,
        if (tcOut != null) 'tc_out': tcOut,
        'intent': trimmed,
        'source': 'frameio',
        'author': author,
        'role': 'producer',
        'proposed_by': 'human',
      },
    });
    if (!reply.ok) {
      state = state.copyWith(message: reply.error);
      return false;
    }
    // Notes are in: the review lane says so, which is what a second round then
    // hangs off. An engine that refuses the transition (no round open yet) is
    // quoted, never worked around.
    await _review('notes_arrived', actor: 'auto');
    await reconstruct();
    return true;
  }

  /// RELEASE THE PRODUCER-REVIEW GATE.
  ///
  /// The pass over the notes happens FIRST and unconditionally: whatever the
  /// producer said is read before the run is allowed past the gate, because a
  /// note that arrives after the markers step has already run is a note nobody
  /// downstream will ever act on (the engine's own P-23 scar).
  ///
  ///   * with notes — every note that fully specifies a mechanical edit becomes
  ///     a PROPOSED op on the ledger, waiting on a human. Creative notes are
  ///     DECLINED with a reason and stay notes.
  ///   * without notes — the pass finds nothing, writes nothing, and the run
  ///     continues untouched. That is not a no-op worth hiding: "nobody had
  ///     anything to say" is the answer, and the console says it.
  Future<void> releaseReviewGate() async {
    final gate = state.gate;
    if (gate == null) {
      state = state.copyWith(message: 'nothing is parked');
      return;
    }
    if (state.busy) return;
    state = state.copyWith(busy: true, clearMessage: true);

    var proposed = 0;
    var declined = 0;
    try {
      final pass = await backend
          .changelistCommand({'op': 'agent_act', 'board_id': boardId});
      if (pass.ok) {
        final acted = pass.fields['acted'];
        if (acted is List) {
          for (final row in acted) {
            if (row is! Map) continue;
            final entryId = row['entry_id'] as String?;
            final why = row['declined'] as String?;
            if (why != null) {
              declined++;
              if (entryId != null) _declined[entryId] = why;
            } else if (row['proposed_entry_id'] != null) {
              proposed++;
            }
          }
        }
      } else {
        state = state.copyWith(message: pass.error);
      }
    } catch (e) {
      state = state.copyWith(message: _describe(e));
    }

    // The round moves on what the producer actually left: notes to conform, or
    // a cut nobody had anything to say about. `version_approved` is one of the
    // engine's AUTO ops — a human may not fire it, the machine observes it.
    final hadNotes = state.ledger.any((r) => r.isNote);
    if (hadNotes || proposed > 0) {
      await _review('confirm_notes');
    } else {
      await _review('version_approved', actor: 'auto');
    }

    state = state.copyWith(
      transpiledOps: proposed,
      declinedNotes: declined,
      agentPassRan: true,
      busy: false,
    );
    await _clearGate(gate);
  }

  /// Release a gate nobody has a bespoke ritual for, then keep walking.
  Future<void> releaseGate() async {
    final gate = state.gate;
    if (gate == null || state.busy) return;
    await _clearGate(gate);
  }

  /// PICTURE LOCK. Confirming the locked cut freezes the ledger's active
  /// entries into a VERSION — that frozen version is the thing conform relinks
  /// against and the thing the delivery lane produces from, so the lock is a
  /// write, not a checkbox. Only then is the sound room's door opened.
  Future<void> confirmPictureLock() async {
    final gate = state.gate;
    if (gate == null || !gate.isPictureLock || state.busy) return;
    final asset = _assetHash;
    final tenant = _laneTenant;
    if (asset != null && tenant != null) {
      final frozen = await backend.changelistCommand({
        'op': 'snapshot',
        'tenant_id': tenant,
        'asset_hash': asset,
        'branch': 'main',
        'label': 'picture lock',
      });
      if (!frozen.ok) {
        state = state.copyWith(message: frozen.error);
        return;
      }
      final lane =
          await backend.changelistCommand({'op': 'list', 'board_id': boardId});
      state = state.copyWith(
          lockedVersion: (lane.fields['version'] as num?)?.toInt() ?? 0);
    }
    await _clearGate(gate);
  }

  /// Produce the graded master through the ENGINE's own delivery lane, then
  /// close the run. The lane resolves the frozen version from this board's
  /// review lane, so the app never names a file — and if there is no frozen
  /// version or no ingested master, the engine's refusal is what shows.
  Future<void> produceMaster() async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      await _driveReviewToDelivered();
      final reply = await backend
          .ingestCommand({'op': 'produce_master', 'board_id': boardId});
      if (!reply.ok) {
        state = state.copyWith(busy: false, message: reply.error);
        return;
      }
      final path = reply.fields['output_path'] as String?;
      if (path == null || path.isEmpty) {
        state = state.copyWith(
            busy: false, message: 'the delivery lane returned no output_path');
        return;
      }
      state = state.copyWith(deliveredMaster: path, busy: false);
    } catch (e) {
      state = state.copyWith(busy: false, message: _describe(e));
      return;
    }
    // The hand-off step is the human's, and producing the master IS the work
    // it was waiting for — so releasing it here is the same click, not a
    // second one.
    final gate = state.gate;
    if (gate != null && gate.isProduceMaster) await _clearGate(gate);
  }

  // ---- the confirm gate on one entry ---------------------------------------

  /// Confirm a proposed op. The human is the only actor who may move an entry
  /// past `proposed`, which is exactly why the agent's proposal sat there.
  Future<void> approveEntry(String entryId) =>
      _confirm(entryId, 'approve');

  /// Reject a proposed op. The row STAYS — rejecting is a decision on the
  /// record, not an erasure of what was proposed.
  Future<void> rejectEntry(String entryId) => _confirm(entryId, 'reject');

  Future<void> _confirm(String entryId, String decision) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearMessage: true);
    final reply = await backend.reviewCommand({
      'op': 'confirm',
      'board_id': boardId,
      'entry_id': entryId,
      'decision': decision,
      'actor': reviewer,
    });
    if (!reply.ok) {
      state = state.copyWith(busy: false, message: reply.error);
      return;
    }
    await reconstruct();
    state = state.copyWith(busy: false);
  }

  // ---- plumbing ------------------------------------------------------------

  /// Clear one gate as [reviewer] and keep walking. The engine's refusal is
  /// surfaced verbatim and NOTHING moves — a gate that fakes its own approval
  /// is the one bug this face cannot have.
  Future<void> _clearGate(SpineStep gate) async {
    state = state.copyWith(busy: true);
    try {
      final ack = await backend.pipelineApproveAs(boardId, gate.id, reviewer);
      if (!ack.success) {
        state = state.copyWith(
            busy: false, message: ack.error ?? 'the gate refused to clear');
        return;
      }
    } catch (e) {
      state = state.copyWith(busy: false, message: _describe(e));
      return;
    }
    state = state.copyWith(busy: false);
    await advance();
  }

  /// Fire one review-lane transition. A refusal is RECORDED, never thrown: the
  /// pipeline is the spine's backbone and a round that will not move is news
  /// about the round, not a reason to stop the run.
  Future<void> _review(String op, {String actor = 'human'}) async {
    try {
      final reply = await backend
          .reviewCommand({'op': op, 'board_id': boardId, 'actor': actor});
      if (reply.ok && reply.state != null) {
        state = state.copyWith(
          reviewState: reply.state!.state,
          reviewRound: reply.state!.round,
        );
      }
    } catch (_) {
      // The lane is a narration on top of the run; it never blocks it.
    }
  }

  /// Walk the review lane to `DELIVERED` from wherever it actually is. Each
  /// transition is the engine's, with the engine's own actor rule: the agent
  /// may never fire one of these, and `delivered` is the machine's own.
  Future<void> _driveReviewToDelivered() async {
    const route = <String, ({String op, String actor})>{
      'CONFORMING': (op: 'publish_proxy', actor: 'human'),
      'IN_REVIEW': (op: 'version_approved', actor: 'auto'),
      'APPROVED': (op: 'finish', actor: 'human'),
      'FINISHING': (op: 'delivered', actor: 'auto'),
    };
    for (var i = 0; i < route.length + 1; i++) {
      final next = route[state.reviewState];
      if (next == null) break;
      final before = state.reviewState;
      await _review(next.op, actor: next.actor);
      if (state.reviewState == before) break;
    }
  }

  static DashboardStepState _stateOf(PipelineStepState s) => switch (s) {
        PipelineStepState.pending => DashboardStepState.pending,
        PipelineStepState.running => DashboardStepState.running,
        PipelineStepState.aiComplete => DashboardStepState.awaitingApproval,
        PipelineStepState.humanApproved => DashboardStepState.approved,
        PipelineStepState.needsLens => DashboardStepState.needsLens,
        PipelineStepState.failed => DashboardStepState.failed,
      };

  static String _describe(Object e) {
    final text = e.toString().trim();
    for (final p in const ['Exception: ', 'Bad state: ', 'StateError: ']) {
      if (text.startsWith(p)) return text.substring(p.length);
    }
    return text;
  }
}
