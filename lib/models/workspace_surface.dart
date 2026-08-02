// models/workspace_surface.dart
//
// PARITY face_workspaces — the data the workspace surface renders: one
// workspace, the boards filed in it, each board's honest at-rest RUN STATE, and
// the workspace-level pipeline roll-up the status strip shows.
//
// SwiftUI reference (read-only):
//   Views/WorkspaceViewNew.swift              — the workspace shell
//   ViewModels/BoardGridViewModel.swift       — `loadBoardsForWorkspace(_:)`
//   ViewModels/BoardRunStateStore.swift       — ONE tenant feed seeds every card
//   Models/LensConsole.swift                  — RunLane / RunBoardFeed / BoardRunState
//   Models/FileTreeTypes.swift                — the `Plugins` workspace convention
//
// THE LOAD-BEARING DISTINCTION (ported verbatim from `BoardRunState`): a MISSING
// feed is not zero runs. The store only writes a feed once a fetch SUCCEEDS, so
// "no feed" means "never seeded, or the lens is down" — saying "No runs yet"
// there repaints a whole workspace as empty during an outage. Only a feed that
// actually arrived and is empty earns "No runs yet". Idle and broken must never
// look the same.

import 'package:flutter/foundation.dart';

import '../ffi/parity_models.dart';

// ---------------------------------------------------------------------------
// The Plugins convention (Models/FileTreeTypes.swift §"Plugins convention")
// ---------------------------------------------------------------------------

/// Conventional name of the per-group registry workspace. Plugin bundles the
/// Marketplace installs land here; it is the group's registry, not a place work
/// is authored.
const String kPluginsWorkspaceName = 'Plugins';

extension CyanWorkspaceSystemX on CyanWorkspace {
  /// True when this workspace is the group's plugins/registry workspace —
  /// SwiftUI's `TreeItem.isPluginsWorkspace`.
  bool get isPluginsWorkspace => name == kPluginsWorkspaceName;

  /// A SYSTEM workspace is one the engine owns. It is listed and browsable, but
  /// it is never where a board is filed: the New Board target resolver skips it
  /// and the surface withholds the affordance entirely rather than offering a
  /// button that files work somewhere it does not belong.
  bool get isSystemWorkspace => isPluginsWorkspace;

  /// Whether a board may be created here. The inverse of [isSystemWorkspace],
  /// named for the question the caller is actually asking.
  bool get acceptsBoards => !isSystemWorkspace;

  /// What the system workspace holds instead of boards, for the surface to say
  /// out loud. Null for an ordinary workspace.
  String? get systemPurpose =>
      isPluginsWorkspace ? 'Installed plugin bundles for this group' : null;
}

// ---------------------------------------------------------------------------
// Lanes (mirror lens runstore.rs RunLane, via Models/LensConsole.swift)
// ---------------------------------------------------------------------------

/// The five named pipeline lanes, in left→right strip order.
enum BoardRunLane { incoming, inFlight, approval, done, failed }

extension BoardRunLaneX on BoardRunLane {
  String get title => switch (this) {
        BoardRunLane.incoming => 'Incoming',
        BoardRunLane.inFlight => 'In-flight',
        BoardRunLane.approval => 'Approval',
        BoardRunLane.done => 'Done',
        BoardRunLane.failed => 'Failed',
      };
}

extension RunStatusLaneX on RunStatus {
  /// The status → lane projection. MIRRORS the lens `RunStatus::lane` exactly;
  /// a stuck run stays visible in In-flight rather than vanishing.
  BoardRunLane get lane => switch (this) {
        RunStatus.queued => BoardRunLane.incoming,
        RunStatus.running || RunStatus.stuck => BoardRunLane.inFlight,
        RunStatus.awaitingApproval => BoardRunLane.approval,
        RunStatus.done => BoardRunLane.done,
        RunStatus.failed => BoardRunLane.failed,
      };

  /// Short, at-rest badge word for a board card — SwiftUI's
  /// `RunStatusValue.badgeLabel`. Deliberately distinct from the Ops console's
  /// pill labels: a board wall says "Needs approval", not "Approval".
  String get boardBadgeLabel => switch (this) {
        RunStatus.queued => 'Queued',
        RunStatus.running => 'Running',
        RunStatus.awaitingApproval => 'Needs approval',
        RunStatus.stuck => 'Stuck',
        RunStatus.done => 'Done',
        RunStatus.failed => 'Failed',
      };
}

// ---------------------------------------------------------------------------
// One board's feed
// ---------------------------------------------------------------------------

/// Every run the tenant feed carried for ONE board, bucketed into lanes.
/// Assembled client-side by re-bucketing through `status.lane`, exactly as
/// `RunBoardFeed.assembled` does — the app never trusts a pre-bucketed lane it
/// did not derive itself.
@immutable
class BoardRunFeed {
  final String boardId;
  final Map<BoardRunLane, List<OpsRun>> lanes;

  const BoardRunFeed({required this.boardId, required this.lanes});

  factory BoardRunFeed.assembled(String boardId, Iterable<OpsRun> runs) {
    final lanes = <BoardRunLane, List<OpsRun>>{
      for (final l in BoardRunLane.values) l: <OpsRun>[],
    };
    for (final r in runs) {
      lanes[r.status.lane]!.add(r);
    }
    return BoardRunFeed(boardId: boardId, lanes: lanes);
  }

  int count(BoardRunLane lane) => lanes[lane]?.length ?? 0;

  int get total => BoardRunLane.values.fold(0, (n, l) => n + count(l));

  /// The board's most operator-relevant run: a human gate first, then work in
  /// flight, then a failure, then queued, then history.
  OpsRun? get leadRun {
    for (final lane in const [
      BoardRunLane.approval,
      BoardRunLane.inFlight,
      BoardRunLane.failed,
      BoardRunLane.incoming,
      BoardRunLane.done,
    ]) {
      final runs = lanes[lane];
      if (runs != null && runs.isNotEmpty) return runs.first;
    }
    return null;
  }

  /// The runs holding on a human — what the card's action-needed pill counts.
  int get actionNeeded =>
      count(BoardRunLane.approval) + count(BoardRunLane.failed);
}

// ---------------------------------------------------------------------------
// BoardRunState — what a card is allowed to CLAIM
// ---------------------------------------------------------------------------

enum BoardRunPhase {
  /// No feed for this board — never seeded, or the lens is down. Claim NOTHING.
  unknown,

  /// The feed arrived and is genuinely empty: the board has never run.
  noRuns,

  /// The board has runs; [BoardRunState.status] is the lead run's.
  active,
}

@immutable
class BoardRunState {
  final BoardRunPhase phase;

  /// The lead run's status. Non-null exactly when [phase] is
  /// [BoardRunPhase.active].
  final RunStatus? status;

  const BoardRunState._(this.phase, this.status);

  static const BoardRunState unknown =
      BoardRunState._(BoardRunPhase.unknown, null);
  static const BoardRunState noRuns =
      BoardRunState._(BoardRunPhase.noRuns, null);
  const BoardRunState.active(RunStatus this.status)
      : phase = BoardRunPhase.active;

  /// Derive from the cached feed. A null feed is `unknown` — never `noRuns`.
  factory BoardRunState.from(BoardRunFeed? feed) {
    if (feed == null) return unknown;
    final lead = feed.leadRun;
    if (feed.total == 0 || lead == null) return noRuns;
    return BoardRunState.active(lead.status);
  }

  /// The at-rest badge text. Null ⇒ render NO badge; never invent a claim for
  /// a board whose feed never arrived.
  String? get label => switch (phase) {
        BoardRunPhase.unknown => null,
        BoardRunPhase.noRuns => 'No runs yet',
        BoardRunPhase.active => status!.boardBadgeLabel,
      };

  /// True while this run is holding on a person.
  bool get needsAction => phase == BoardRunPhase.active && status!.needsAction;

  @override
  bool operator ==(Object other) =>
      other is BoardRunState && other.phase == phase && other.status == status;

  @override
  int get hashCode => Object.hash(phase, status);
}

// ---------------------------------------------------------------------------
// Asset-class step counts — what a card says about the board's own pipeline
// ---------------------------------------------------------------------------

/// The board's ASSET-CLASS step counts: pending / in-flight / done (+ failed
/// only when real), read from `cyan_pipeline_status` — the board's COMPILED
/// steps — not from the lens run feed.
///
/// SwiftUI reference (read-only):
///   Views/Components/BoardPipelineStatusStrip.swift — `BoardPipelineCounts`
///
/// The two feeds answer different questions and a card needs both. The lens
/// feed says what RUNS the board has ([BoardRunState]); this says how far the
/// board's own asset-class pipeline has got. A board mid-workflow shows step
/// progress here even when no lens run is in flight, which is exactly the case
/// the run badge alone cannot describe.
///
/// THE ENGINE'S COUNTER IS CUMULATIVE, and the mapping has to know it.
/// `pipeline_status` (src/pipeline.rs) counts a `human_approved` step into BOTH
/// `human_approved` and `ai_complete` — approving a step does not decrement the
/// gate counter it passed through. So the parked-at-a-gate count is
/// `aiComplete - humanApproved`, and reading `ai_complete` as "in flight"
/// wholesale would report every finished step as still moving: a board with 2
/// approved and 1 parked step would claim 3 in flight and 2 done out of 4. The
/// five engine buckets partition the step list exactly once, so [pending],
/// [inFlight], [done] and [failed] always sum to [total] — an invariant worth
/// more than a literal transcription of the Swift arithmetic.
@immutable
class BoardPipelineCounts {
  /// Authored but not started.
  final int pending;

  /// Started: executing now, or parked on its human gate.
  final int inFlight;

  /// Finished THROUGH the human gate.
  final int done;

  /// Errored. Rendered only when non-zero — honest, never hidden.
  final int failed;

  /// Every compiled step on the board.
  final int total;

  const BoardPipelineCounts({
    this.pending = 0,
    this.inFlight = 0,
    this.done = 0,
    this.failed = 0,
    this.total = 0,
  });

  /// A board with no compiled steps has no strip — nothing has been authored
  /// into an asset-class pipeline yet, and zeroes would imply it had.
  bool get isEmpty => total == 0;

  /// Project an engine snapshot onto the three chips.
  ///
  /// Null for an ERROR envelope: a read that did not land says nothing, the
  /// same rule [BoardRunState.unknown] enforces for the run feed. A zero-strip
  /// invented from a failed read is a claim the app has not earned.
  static BoardPipelineCounts? from(PipelineStatus? status) {
    if (status == null || status.error != null) return null;
    return BoardPipelineCounts(
      pending: status.pending,
      // `running` covers the engine's `running` + `scheduled`; the gate-parked
      // remainder is what `ai_complete` holds beyond the approved steps.
      inFlight: status.running + (status.aiComplete - status.humanApproved),
      done: status.humanApproved,
      failed: status.failed,
      total: status.totalSteps,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BoardPipelineCounts &&
      other.pending == pending &&
      other.inFlight == inFlight &&
      other.done == done &&
      other.failed == failed &&
      other.total == total;

  @override
  int get hashCode => Object.hash(pending, inFlight, done, failed, total);
}

// ---------------------------------------------------------------------------
// The workspace-level roll-up (the pipeline status strip)
// ---------------------------------------------------------------------------

/// Lane totals across every board in one workspace. `isKnown` is false when the
/// tenant feed never arrived — the strip then reports that it cannot say,
/// rather than painting five confident zeroes.
@immutable
class WorkspacePipeline {
  final Map<BoardRunLane, int> counts;
  final bool isKnown;

  const WorkspacePipeline._(this.counts, this.isKnown);

  static const WorkspacePipeline unavailable =
      WorkspacePipeline._(<BoardRunLane, int>{}, false);

  factory WorkspacePipeline.from(Iterable<BoardRunFeed> feeds) {
    final counts = <BoardRunLane, int>{
      for (final l in BoardRunLane.values) l: 0,
    };
    for (final f in feeds) {
      for (final l in BoardRunLane.values) {
        counts[l] = counts[l]! + f.count(l);
      }
    }
    return WorkspacePipeline._(counts, true);
  }

  int count(BoardRunLane lane) => counts[lane] ?? 0;

  int get total => BoardRunLane.values.fold(0, (n, l) => n + count(l));

  /// Runs holding on a person across the workspace.
  int get actionNeeded =>
      count(BoardRunLane.approval) + count(BoardRunLane.failed);
}

// ---------------------------------------------------------------------------
// The assembled surface
// ---------------------------------------------------------------------------

/// One workspace, everything on it, and what its runs are doing.
@immutable
class WorkspaceSurface {
  final CyanGroup group;
  final CyanWorkspace workspace;

  /// The boards filed in this workspace, pinned first then most-recently
  /// modified — `BoardGridViewModel.filteredBoards`' default ordering.
  final List<CyanBoard> boards;

  /// Per-board run state, keyed by board id. A board missing from the map is
  /// `BoardRunState.unknown`; [runState] applies that rule for callers.
  final Map<String, BoardRunState> runStates;

  final WorkspacePipeline pipeline;

  const WorkspaceSurface({
    required this.group,
    required this.workspace,
    required this.boards,
    required this.runStates,
    required this.pipeline,
  });

  BoardRunState runState(String boardId) =>
      runStates[boardId] ?? BoardRunState.unknown;

  bool get isSystem => workspace.isSystemWorkspace;

  /// The boards a shortcut can jump to, in shortcut order: pinned first (an
  /// operator pins what they return to), then the rest in board order.
  List<CyanBoard> get shortcutBoards => [
        ...boards.where((b) => b.isPinned),
        ...boards.where((b) => !b.isPinned),
      ];

  /// Bucket a tenant-wide run feed into one workspace's boards — the ONE call
  /// that seeds every card, mirroring `BoardRunStateStore.seedFromTenant`.
  ///
  /// [tenantRuns] null means the feed never arrived (lens down / not wired):
  /// every board reports `unknown` and the strip says it cannot tell. Only a
  /// feed that ARRIVED lets a board with no runs claim `noRuns`.
  factory WorkspaceSurface.assemble({
    required CyanGroup group,
    required CyanWorkspace workspace,
    required List<OpsRun>? tenantRuns,
  }) {
    final boards = [...workspace.boards]..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        final am = a.lastModified ?? a.createdAt;
        final bm = b.lastModified ?? b.createdAt;
        return bm.compareTo(am);
      });

    if (tenantRuns == null) {
      return WorkspaceSurface(
        group: group,
        workspace: workspace,
        boards: boards,
        runStates: const {},
        pipeline: WorkspacePipeline.unavailable,
      );
    }

    final feeds = <String, BoardRunFeed>{};
    for (final b in boards) {
      // The feed is keyed by board id. A run that predates the id on the wire
      // still carries its board's NAME in `workflow`, which is how the Ops
      // console groups today — accept both rather than lose the run.
      final mine = tenantRuns.where((r) =>
          r.boardId.isNotEmpty ? r.boardId == b.id : r.workflow == b.name);
      feeds[b.id] = BoardRunFeed.assembled(b.id, mine);
    }

    return WorkspaceSurface(
      group: group,
      workspace: workspace,
      boards: boards,
      runStates: {
        for (final e in feeds.entries) e.key: BoardRunState.from(e.value),
      },
      pipeline: WorkspacePipeline.from(feeds.values),
    );
  }
}
