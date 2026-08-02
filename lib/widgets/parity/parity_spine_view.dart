// widgets/parity/parity_spine_view.dart
//
// PARITY face `spine_e2e` — the POST-PRODUCTION SPINE console.
//
// The Dashboard face draws ONE run. This surface draws the WALK: the seven
// rooms the work goes through, which door is shut and what is holding it, the
// producer's notes and what the agent pass made of them, and the delivered
// master at the end. Every other face in the app is a room; this is the
// corridor between them.
//
// It is a pure function of `SpineState` — the console never decides anything.
// Releasing a gate goes through the engine, the note → op boundary is the
// engine's own agent pass, and a refusal is shown in the engine's words with
// NOTHING moved. A console that could clear a producer-review hold on its own
// would be worse than no console.
//
// SwiftUI reference (READ-ONLY):
//   Views/DashboardView.swift      (the run + its gates)
//   Views/ReviewLoopView.swift     (the confirm gate on one entry)
//   Views/WorkflowView.swift       (the clone / compile head of the walk)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../models/dashboard_event.dart';
import '../../models/spine_lane.dart';
import '../../providers/spine_controller.dart';
import '../../providers/spine_provider.dart';
import '../../theme/monokai_theme.dart';

class ParitySpineView extends ConsumerWidget {
  final String boardId;
  final String tenantId;

  /// An explicit controller, for callers that drive the walk themselves (a
  /// Tier-1 test steps it gate by gate). Null uses the app's own per-board one.
  final SpineController? controller;

  const ParitySpineView({
    super.key,
    required this.boardId,
    required this.tenantId,
    this.controller,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SpineController vm = controller ??
        ref.watch(spineProvider((boardId: boardId, tenantId: tenantId)).notifier);
    return _Surface(key: ObjectKey(vm), controller: vm);
  }
}

class _Surface extends StatefulWidget {
  final SpineController controller;

  const _Surface({super.key, required this.controller});

  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  late SpineState _state;
  late final void Function() _unsubscribe;
  bool _mountedOnce = false;

  @override
  void initState() {
    super.initState();
    // fireImmediately hands us the current state synchronously; that first
    // delivery lands before the element can be dirtied, so it assigns.
    _unsubscribe = widget.controller.addListener((s) {
      if (_mountedOnce) {
        setState(() => _state = s);
      } else {
        _state = s;
      }
    });
    _mountedOnce = true;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
        color: MonokaiTheme.background,
        child: _Body(state: _state, controller: widget.controller),
      );
}

class _Body extends StatelessWidget {
  final SpineState state;
  final SpineController controller;

  const _Body({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    // A spinner is honest ONLY before the first read has come back at all.
    if (!state.hydrated) {
      return const Center(
        child: CircularProgressIndicator(color: MonokaiTheme.cyan),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _Header(state: state),
        const SizedBox(height: 16),
        if (!state.isCloned)
          _ColdStart(state: state, controller: controller)
        else ...[
          if (!state.isCompiled)
            _CompileCard(state: state, controller: controller),
          if (state.isCompiled) ...[
            _LaneRail(state: state),
            const SizedBox(height: 18),
          ],
          if (state.gate != null)
            _GateCard(state: state, controller: controller),
          if (state.deliveredMaster != null) ...[
            const SizedBox(height: 12),
            _DeliveredCard(path: state.deliveredMaster!),
          ],
          if (state.ledger.isNotEmpty) ...[
            const SizedBox(height: 20),
            _Ledger(state: state, controller: controller),
          ],
          if (state.isCompiled) ...[
            const SizedBox(height: 20),
            Text('Spine', style: MonokaiTheme.labelLarge),
            const SizedBox(height: 8),
            for (final lane in state.lanes)
              if (!lane.isEmpty) _LaneBlock(lane: lane),
          ],
        ],
        if (state.message != null) ...[
          const SizedBox(height: 12),
          _Banner(
            key: const ValueKey('spine.message'),
            icon: Icons.warning_amber_rounded,
            text: state.message!,
            color: MonokaiTheme.orange,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// head
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final SpineState state;

  const _Header({required this.state});

  @override
  Widget build(BuildContext context) {
    final title =
        state.templateName.isEmpty ? 'Post-production spine' : state.templateName;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: MonokaiTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                state.isCompiled
                    ? '${state.steps.length} steps · '
                        '${state.steps.where((s) => s.isSettled).length} settled'
                    : state.isCloned
                        ? '${state.clonedSteps} steps landed · not compiled'
                        : 'Nothing cloned onto this board yet',
                style: MonokaiTheme.labelMedium,
              ),
            ],
          ),
        ),
        if (state.reviewState.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _Pill(
              key: const ValueKey('spine.review.state'),
              label: state.reviewRound > 0
                  ? '${state.reviewState} · round ${state.reviewRound}'
                  : state.reviewState,
              color: MonokaiTheme.purple,
            ),
          ),
        _Pill(
          key: const ValueKey('spine.run.state'),
          label: _runLabel(state),
          color: _runColor(state),
        ),
      ],
    );
  }

  static String _runLabel(SpineState s) => switch (s.runState) {
        PipelineRunState.idle => s.isCompiled ? 'Not started' : 'No DAG',
        PipelineRunState.inProgress => 'In progress',
        PipelineRunState.running => 'Running',
        PipelineRunState.awaitingApproval => 'Awaiting you',
        PipelineRunState.done => 'Done',
        PipelineRunState.failed => 'Failed',
      };

  static Color _runColor(SpineState s) => switch (s.runState) {
        PipelineRunState.done => MonokaiTheme.green,
        PipelineRunState.failed => MonokaiTheme.red,
        PipelineRunState.awaitingApproval => MonokaiTheme.yellow,
        _ => MonokaiTheme.textMuted,
      };
}

/// The cold start: this board has no spine on it. The template is named and the
/// clone is one action — nothing is pre-decided for the operator.
class _ColdStart extends StatelessWidget {
  final SpineState state;
  final SpineController controller;

  const _ColdStart({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Clone the spine', style: MonokaiTheme.labelLarge),
            const SizedBox(height: 6),
            Text(
              'The authored walk: ingest → producer review round → markers and '
              'timeline sense → picture lock → sound turnover → conform → '
              'grade → graded master. Authored order is law.',
              style: MonokaiTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _Action(
              key: const ValueKey('spine.clone'),
              label: 'Clone ${SpineController.spineTemplateName}',
              color: MonokaiTheme.cyan,
              busy: state.busy,
              onPressed: controller.cloneSpine,
            ),
          ],
        ),
      );
}

/// Cloned, not compiled. The steps are English until the engine turns them into
/// a DAG, and the console says exactly that rather than drawing a graph nobody
/// compiled.
class _CompileCard extends StatelessWidget {
  final SpineState state;
  final SpineController controller;

  const _CompileCard({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${state.clonedSteps} steps landed',
                style: MonokaiTheme.labelLarge),
            const SizedBox(height: 6),
            Text(
              'They are authored English until a compile turns them into a '
              'runnable DAG.',
              style: MonokaiTheme.bodySmall,
            ),
            if (state.pluginsRefused.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'The plugin source had no bundle for '
                '${state.pluginsRefused.join(', ')} — those steps will need it '
                'before they can dispatch.',
                key: const ValueKey('spine.plugins.refused'),
                style: MonokaiTheme.labelMedium,
              ),
            ],
            const SizedBox(height: 12),
            _Action(
              key: const ValueKey('spine.compile'),
              label: 'Compile the spine',
              color: MonokaiTheme.cyan,
              busy: state.busy,
              onPressed: controller.compile,
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// the lane rail
// ---------------------------------------------------------------------------

/// The seven rooms, in walk order. Each says what it is doing and — when its
/// door is shut — the step that is holding it, by name.
class _LaneRail extends StatelessWidget {
  final SpineState state;

  const _LaneRail({required this.state});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final lane in kSpineWalk)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _LaneChip(lane: state.laneFor(lane)),
              ),
          ],
        ),
      );
}

class _LaneChip extends StatelessWidget {
  final SpineLaneView lane;

  const _LaneChip({required this.lane});

  @override
  Widget build(BuildContext context) {
    final color = lane.isEmpty
        ? MonokaiTheme.textDisabled
        : lane.isComplete
            ? MonokaiTheme.green
            : lane.isOpen
                ? MonokaiTheme.cyan
                : MonokaiTheme.textMuted;
    return Container(
      key: ValueKey('spine.lane.${lane.lane.name}'),
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                lane.isComplete
                    ? Icons.check_circle
                    : lane.isOpen
                        ? Icons.radio_button_unchecked
                        : Icons.lock_outline,
                size: 13,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(lane.lane.label,
                  style: MonokaiTheme.labelLarge.copyWith(color: color)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            lane.isEmpty
                ? 'No steps'
                : lane.heldBy != null
                    ? 'Held'
                    : lane.isComplete
                        ? 'Complete'
                        : 'Open',
            style: MonokaiTheme.labelMedium,
          ),
          if (lane.heldBy != null)
            Text(
              'by ${lane.heldBy!.title}',
              key: ValueKey('spine.lane.${lane.lane.name}.heldBy'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: MonokaiTheme.labelMedium
                  .copyWith(color: MonokaiTheme.textDisabled),
            ),
        ],
      ),
    );
  }
}

/// One room's steps, listed with the state the engine reports for each. This is
/// what makes "conform and grade report their state" a fact on screen rather
/// than an inference from a lane colour.
class _LaneBlock extends StatelessWidget {
  final SpineLaneView lane;

  const _LaneBlock({required this.lane});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lane.lane.label.toUpperCase(),
                style: MonokaiTheme.labelMedium
                    .copyWith(color: MonokaiTheme.comment, letterSpacing: 1.1)),
            const SizedBox(height: 4),
            for (final step in lane.steps) _StepRow(step: step),
          ],
        ),
      );
}

class _StepRow extends StatelessWidget {
  final SpineStep step;

  const _StepRow({required this.step});

  @override
  Widget build(BuildContext context) => Container(
        key: ValueKey('spine.step.${step.id}'),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: MonokaiTheme.surface,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(step.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MonokaiTheme.bodySmall),
            ),
            const SizedBox(width: 10),
            _Pill(label: step.stateLabel, color: _stateColor(step.state)),
          ],
        ),
      );

  static Color _stateColor(DashboardStepState s) => switch (s) {
        DashboardStepState.approved || DashboardStepState.done =>
          MonokaiTheme.green,
        DashboardStepState.failed => MonokaiTheme.red,
        DashboardStepState.awaitingApproval ||
        DashboardStepState.awaitingInput =>
          MonokaiTheme.yellow,
        DashboardStepState.needsLens => MonokaiTheme.orange,
        DashboardStepState.running => MonokaiTheme.cyan,
        DashboardStepState.pending => MonokaiTheme.textMuted,
      };
}

// ---------------------------------------------------------------------------
// the parked gate
// ---------------------------------------------------------------------------

/// Whatever the run is parked on, with the action that belongs to THAT step —
/// the producer-review release, the picture-lock confirm, the delivery
/// hand-off, or a plain release for a gate with no ritual of its own.
class _GateCard extends StatelessWidget {
  final SpineState state;
  final SpineController controller;

  const _GateCard({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final gate = state.gate!;
    return _Card(
      key: const ValueKey('spine.gate'),
      border: MonokaiTheme.yellow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pause_circle_outline,
                  size: 16, color: MonokaiTheme.yellow),
              const SizedBox(width: 8),
              Text('Parked', style: MonokaiTheme.labelLarge),
              const Spacer(),
              if (gate.waitingOn != null)
                Text('waiting on ${gate.waitingOn}',
                    key: const ValueKey('spine.gate.waitingOn'),
                    style: MonokaiTheme.labelMedium),
            ],
          ),
          const SizedBox(height: 8),
          Text(gate.title,
              key: const ValueKey('spine.gate.title'),
              style: MonokaiTheme.bodyMedium),
          if (gate.isProducerReview) ...[
            const SizedBox(height: 10),
            _NoteComposer(state: state, controller: controller),
            const SizedBox(height: 10),
            Text(
              state.notes.isEmpty
                  ? 'No notes have come back yet. Releasing the gate with none '
                      'lets the run continue untouched.'
                  : '${state.notes.length} note(s) came back. Releasing the '
                      'gate reads them BEFORE the run moves on: anything '
                      'mechanical becomes a proposed op, anything creative '
                      'stays a note.',
              key: const ValueKey('spine.gate.notesSummary'),
              style: MonokaiTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            _Action(
              key: const ValueKey('spine.release.review'),
              label: 'Release the review gate',
              color: MonokaiTheme.green,
              busy: state.busy,
              onPressed: controller.releaseReviewGate,
            ),
          ] else if (gate.isPictureLock) ...[
            const SizedBox(height: 8),
            Text(
              'Confirming freezes the ledger into a version. Nothing in the '
              'sound room may start until it is.',
              style: MonokaiTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            _Action(
              key: const ValueKey('spine.lock'),
              label: 'Confirm the locked cut',
              color: MonokaiTheme.green,
              busy: state.busy,
              onPressed: controller.confirmPictureLock,
            ),
          ] else if (gate.isProduceMaster) ...[
            const SizedBox(height: 10),
            _Action(
              key: const ValueKey('spine.master'),
              label: 'Produce master',
              color: MonokaiTheme.green,
              busy: state.busy,
              onPressed: controller.produceMaster,
            ),
          ] else ...[
            const SizedBox(height: 10),
            _Action(
              key: const ValueKey('spine.release'),
              label: 'Release',
              color: MonokaiTheme.green,
              busy: state.busy,
              onPressed: controller.releaseGate,
            ),
          ],
        ],
      ),
    );
  }
}

/// The producer's note, landing on the board's own ledger — the same rail a
/// sensed Frame.io comment lands on.
class _NoteComposer extends StatefulWidget {
  final SpineState state;
  final SpineController controller;

  const _NoteComposer({required this.state, required this.controller});

  @override
  State<_NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends State<_NoteComposer> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final value = _text.text;
    if (value.trim().isEmpty) return;
    _text.clear();
    await widget.controller.captureReviewNote(value);
  }

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('spine.note.field'),
              controller: _text,
              style: MonokaiTheme.bodySmall,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'A note from the producer…',
                hintStyle: MonokaiTheme.labelMedium,
                filled: true,
                fillColor: MonokaiTheme.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: MonokaiTheme.border),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _Action(
            key: const ValueKey('spine.note.send'),
            label: 'Leave note',
            color: MonokaiTheme.cyan,
            busy: widget.state.busy,
            onPressed: _send,
          ),
        ],
      );
}

// ---------------------------------------------------------------------------
// the ledger
// ---------------------------------------------------------------------------

/// What the producer said, and what the agent pass made of it. The two are
/// deliberately drawn as different things: a PROPOSAL carries a decision, a
/// declined note carries the agent's reason for leaving it alone.
class _Ledger extends StatelessWidget {
  final SpineState state;
  final SpineController controller;

  const _Ledger({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Review ledger', style: MonokaiTheme.labelLarge),
              const SizedBox(width: 10),
              if (state.agentPassRan)
                Text(
                  '${state.transpiledOps} proposed · '
                  '${state.declinedNotes} left as notes',
                  key: const ValueKey('spine.pass.summary'),
                  style: MonokaiTheme.labelMedium,
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in state.ledger)
            _LedgerRow(row: row, state: state, controller: controller),
        ],
      );
}

class _LedgerRow extends StatelessWidget {
  final SpineLedgerRow row;
  final SpineState state;
  final SpineController controller;

  const _LedgerRow({
    required this.row,
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final isOp = row.kind == 'op';
    return _Card(
      key: ValueKey('spine.entry.${row.id}'),
      border: row.isCreativeNote
          ? MonokaiTheme.purple
          : isOp
              ? MonokaiTheme.cyan
              : MonokaiTheme.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Pill(
                label: isOp ? (row.op ?? 'op') : 'note',
                color: isOp ? MonokaiTheme.cyan : MonokaiTheme.purple,
              ),
              const SizedBox(width: 8),
              if (row.entry.proposedBy == 'agent')
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: _Pill(label: 'agent', color: MonokaiTheme.orange),
                ),
              _Pill(label: row.state, color: MonokaiTheme.textMuted),
            ],
          ),
          const SizedBox(height: 8),
          Text(row.text, style: MonokaiTheme.bodySmall),
          if (row.declined != null) ...[
            const SizedBox(height: 6),
            Text(
              row.declined!,
              key: ValueKey('spine.entry.${row.id}.declined'),
              style: MonokaiTheme.labelMedium
                  .copyWith(color: MonokaiTheme.purple),
            ),
          ],
          if (row.isAgentProposal) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _Action(
                  key: ValueKey('spine.entry.${row.id}.approve'),
                  label: 'Approve',
                  color: MonokaiTheme.green,
                  busy: state.busy,
                  onPressed: () => controller.approveEntry(row.id),
                ),
                const SizedBox(width: 8),
                _Action(
                  key: ValueKey('spine.entry.${row.id}.reject'),
                  label: 'Reject',
                  color: MonokaiTheme.red,
                  busy: state.busy,
                  onPressed: () => controller.rejectEntry(row.id),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DeliveredCard extends StatelessWidget {
  final String path;

  const _DeliveredCard({required this.path});

  @override
  Widget build(BuildContext context) => _Card(
        key: const ValueKey('spine.delivered'),
        border: MonokaiTheme.green,
        child: Row(
          children: [
            const Icon(Icons.movie_creation_outlined,
                size: 16, color: MonokaiTheme.green),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Delivered master', style: MonokaiTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(path,
                      key: const ValueKey('spine.delivered.path'),
                      style: MonokaiTheme.bodySmall
                          .copyWith(fontFamily: MonokaiTheme.fontFamilyMono)),
                ],
              ),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// small parts
// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  final Widget child;
  final Color? border;

  const _Card({super.key, required this.child, this.border});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MonokaiTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border ?? MonokaiTheme.border),
        ),
        child: child,
      );
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;

  const _Pill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: MonokaiTheme.labelMedium.copyWith(color: color)),
      );
}

class _Action extends StatelessWidget {
  final String label;
  final Color color;
  final bool busy;
  final VoidCallback onPressed;

  const _Action({
    super.key,
    required this.label,
    required this.color,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: busy ? null : onPressed,
        style: TextButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.16),
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        child: Text(label, style: MonokaiTheme.labelLarge.copyWith(color: color)),
      );
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Banner({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: MonokaiTheme.bodySmall)),
          ],
        ),
      );
}
