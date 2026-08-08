// widgets/parity/parity_dashboard_view.dart
//
// PARITY port of the SwiftUI `DashboardView` — the Board "Dashboard" face
// (PARITY_TRACKER row 4): the running workflow.
//
// Three phases, the same three Swift derives (`DashboardViewModel.Phase`):
//
//   preRun  — the board is compiled and nothing has executed yet, so the face
//             shows the COMPILED DAG: the plan, its edges, its gates. Swift
//             unifies the Notebook's `PipelinePreviewView` with the dashboard
//             here for exactly one reason — the preview and the live run are
//             the same graph at two moments, and drawing them differently
//             makes the operator re-learn the picture the instant it matters.
//   running — the live graph: per-step state, per-item progress, open gates
//             with Approve / Reject, and the run meter.
//   done    — the same graph plus its terminal state.
//
// Everything comes off `DashboardController` (the `CyanBackend` seam) — the
// persisted `pipelineStatus` read refined by `pollEvents` frames. This widget
// never touches `CyanFFI`, and it never computes a number the engine did not
// send: the stats panel is a pure echo of `WorkflowStatsUpdated`.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Views/DashboardView.swift
//   cyan-iOS/Cyan/Cyan/Views/PipelinePreviewView.swift  (the DAG step boxes)
//   cyan-iOS/Cyan/Cyan/ViewModels/DashboardViewModel.swift

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/dashboard_event.dart';
import '../../providers/dashboard_controller.dart';
import '../../providers/dashboard_provider.dart';
import '../../theme/monokai_theme.dart';

class ParityDashboardView extends ConsumerWidget {
  final String boardId;

  /// An explicit controller, for callers that drive their own cycles (Tier-1
  /// tests step [DashboardController.tick] one drain at a time). Null uses the
  /// app's own per-board pump.
  final DashboardController? controller;

  const ParityDashboardView({
    super.key,
    required this.boardId,
    this.controller,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DashboardController vm =
        controller ?? ref.watch(dashboardProvider(boardId).notifier);
    return _Surface(key: ObjectKey(vm), controller: vm);
  }
}

/// Subscribes to the controller and rebuilds on every published state.
class _Surface extends StatefulWidget {
  final DashboardController controller;

  const _Surface({super.key, required this.controller});

  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  late DashboardState _state;
  late final void Function() _unsubscribe;
  bool _mountedOnce = false;

  @override
  void initState() {
    super.initState();
    // fireImmediately hands us the current state synchronously; that first
    // delivery lands before the element can be marked dirty, so it assigns
    // rather than setState.
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
  Widget build(BuildContext context) {
    return Material(
      color: MonokaiTheme.background,
      child: _Body(state: _state, controller: widget.controller),
    );
  }
}

class _Body extends StatelessWidget {
  final DashboardState state;
  final DashboardController controller;

  const _Body({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    // A spinner is honest ONLY before the first read has come back at all.
    if (!state.hydrated) {
      return const Center(
        child: CircularProgressIndicator(color: MonokaiTheme.cyan),
      );
    }
    // The engine answered with an error and we hold nothing to show: say what
    // it said, rather than an empty surface that reads like "no workflow".
    if (state.error != null && state.steps.isEmpty) {
      return _Placeholder(
        icon: Icons.cloud_off,
        title: 'Cannot read this run',
        detail: state.error!,
        color: MonokaiTheme.red,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: state.phase == DashboardPhase.preRun
          ? _preRun(context)
          : _live(context),
    );
  }

  // ---- pre-run: the compiled DAG ------------------------------------------

  List<Widget> _preRun(BuildContext context) {
    if (state.steps.isEmpty) {
      return const [
        SizedBox(
          height: 320,
          child: _Placeholder(
            icon: Icons.account_tree_outlined,
            title: 'No workflow deployed yet',
            detail:
                'Compile a workflow in the Notebook to preview its DAG here.',
            color: MonokaiTheme.textDisabled,
          ),
        ),
      ];
    }
    return [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Compiled DAG', style: MonokaiTheme.titleMedium),
                const SizedBox(height: 4),
                Text('${state.steps.length} steps · not started yet',
                    style: MonokaiTheme.labelMedium),
              ],
            ),
          ),
          const _StatusPill(
              label: 'Not started', color: MonokaiTheme.textMuted),
        ],
      ),
      const SizedBox(height: 16),
      _Dag(steps: state.steps),
      const SizedBox(height: 12),
      Text('It lights up live when a run starts.',
          style: MonokaiTheme.labelMedium),
      const SizedBox(height: 20),
      Text('Steps', style: MonokaiTheme.labelLarge),
      const SizedBox(height: 8),
      for (final s in state.steps) _StepRow(step: s),
    ];
  }

  // ---- running / done: the live graph -------------------------------------

  List<Widget> _live(BuildContext context) {
    final gates = state.gates;
    return [
      _RunHeader(state: state),
      const SizedBox(height: 16),
      Text('Workflow', style: MonokaiTheme.labelLarge),
      const SizedBox(height: 8),
      _Dag(steps: state.steps),
      if (gates.isNotEmpty) ...[
        const SizedBox(height: 20),
        for (final gate in gates)
          _GateCard(
            step: gate,
            busy: state.busy,
            onApprove: () => controller.approve(gate.id),
            onReject: () => controller.reject(gate.id),
          ),
      ],
      if (state.parked.isNotEmpty) ...[
        const SizedBox(height: 12),
        for (final step in state.parked)
          _ParkedCard(
            step: step,
            busy: state.busy,
            onRerun: () => controller.rerunParked(step.id),
          ),
      ],
      // The engine's refusal, verbatim ("review gate is waiting on
      // 'producer@studio'"). Loud, never silent — a gate that fails quietly is
      // a gate the operator believes they cleared.
      if (state.gateMessage != null) ...[
        const SizedBox(height: 4),
        _Banner(
          icon: Icons.warning_amber_rounded,
          text: state.gateMessage!,
          color: MonokaiTheme.orange,
        ),
      ],
      if (state.currentItem != null) ...[
        const SizedBox(height: 16),
        _CurrentItem(state: state),
      ],
      const SizedBox(height: 20),
      Text('Steps', style: MonokaiTheme.labelLarge),
      const SizedBox(height: 8),
      for (final s in state.steps)
        _StepRow(
          step: s,
          // What the step is really waiting for, with parks resolved through.
          blockedBy:
              s.state == DashboardStepState.pending ? state.blockedBy(s) : null,
          // Nothing to show a wait for unless the step is queued.
          showReadiness: s.state == DashboardStepState.pending,
          onRetry: s.state == DashboardStepState.failed
              ? () => controller.retry(s.id)
              : null,
          onRunNow: s.state == DashboardStepState.pending && !state.busy
              ? () => controller.runNow(s.id)
              : null,
        ),
      if (state.snapshot != null) ...[
        const SizedBox(height: 20),
        _Totals(snapshot: state.snapshot!),
      ],
      if (state.phase == DashboardPhase.done) ...[
        const SizedBox(height: 20),
        _DoneSummary(finished: state.finished),
      ],
    ];
  }
}

// ---------------------------------------------------------------------------
// Run header
// ---------------------------------------------------------------------------

class _RunHeader extends StatelessWidget {
  final DashboardState state;
  const _RunHeader({required this.state});

  Color get _pillColor => switch (state.statusLabel) {
        'Done' => MonokaiTheme.green,
        'Failed' => MonokaiTheme.red,
        'Cancelled' => MonokaiTheme.comment,
        'Running' => MonokaiTheme.cyan,
        _ => MonokaiTheme.textMuted,
      };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.workflowLabel.isEmpty
                    ? 'Workflow Run'
                    : state.workflowLabel,
                style: MonokaiTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${state.completedSteps} / ${state.steps.length} steps complete',
                style: MonokaiTheme.labelMedium,
              ),
            ],
          ),
        ),
        _StatusPill(label: state.statusLabel, color: _pillColor),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child:
          Text(label, style: MonokaiTheme.labelMedium.copyWith(color: color)),
    );
  }
}

// ---------------------------------------------------------------------------
// The DAG — step boxes joined by their dependency edges
// ---------------------------------------------------------------------------

Color _stateColor(DashboardStepState s) => switch (s) {
      DashboardStepState.pending => MonokaiTheme.comment,
      DashboardStepState.running => MonokaiTheme.cyan,
      DashboardStepState.awaitingApproval => MonokaiTheme.yellow,
      DashboardStepState.awaitingInput => MonokaiTheme.yellow,
      DashboardStepState.needsLens => MonokaiTheme.orange,
      DashboardStepState.approved => MonokaiTheme.green,
      DashboardStepState.done => MonokaiTheme.green,
      DashboardStepState.failed => MonokaiTheme.red,
    };

/// Horizontal scroll of step boxes. An arrow is drawn only where the next step
/// actually DEPENDS on the one before it — a chain the compile did not author
/// is not an edge, and drawing it anyway would claim an order the engine will
/// not honour.
class _Dag extends StatelessWidget {
  final List<DagStep> steps;
  const _Dag({required this.steps});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            _StepBox(step: steps[i]),
            if (i < steps.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  steps[i + 1].dependsOn.contains(steps[i].id)
                      ? Icons.arrow_forward
                      : Icons.more_horiz,
                  size: 14,
                  color: MonokaiTheme.comment,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StepBox extends StatelessWidget {
  final DagStep step;
  const _StepBox({required this.step});

  @override
  Widget build(BuildContext context) {
    final color = _stateColor(step.state);
    return Container(
      width: 150,
      height: 92,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: _AiSignal(step: step)),
              const SizedBox(width: 6),
              Flexible(child: _HumanSignal(step: step)),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(step.title,
                style: MonokaiTheme.labelMedium
                    .copyWith(color: MonokaiTheme.foreground),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          if (step.stage.isNotEmpty)
            Text(step.stage,
                style: MonokaiTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// The AI (machine) lane — present only for steps a model actually runs. A
/// MANUAL step never ran on a model, so it has no AI lane to report.
class _AiSignal extends StatelessWidget {
  final DagStep step;
  const _AiSignal({required this.step});

  @override
  Widget build(BuildContext context) {
    if (step.actor != DashboardStepActor.ai) {
      return Text('·',
          style: MonokaiTheme.labelSmall
              .copyWith(color: MonokaiTheme.comment.withValues(alpha: 0.5)));
    }
    final (icon, label, color) = switch (step.state) {
      DashboardStepState.pending => (
          Icons.circle_outlined,
          'AI queued',
          MonokaiTheme.comment
        ),
      DashboardStepState.running => (
          Icons.settings,
          'AI running',
          MonokaiTheme.cyan
        ),
      DashboardStepState.failed => (
          Icons.cancel,
          'AI failed',
          MonokaiTheme.red
        ),
      DashboardStepState.needsLens => (
          Icons.pause_circle_outline,
          'AI parked',
          MonokaiTheme.orange
        ),
      // Awaiting approval means the machine half FINISHED and a human now owes
      // a decision — the AI lane is done, not pending.
      _ => (Icons.check_circle, 'AI done', MonokaiTheme.cyan),
    };
    return _Lane(icon: icon, label: label, color: color);
  }
}

/// The human (gate) lane. Silent for a machine step nobody has to sign off.
class _HumanSignal extends StatelessWidget {
  final DagStep step;
  const _HumanSignal({required this.step});

  @override
  Widget build(BuildContext context) {
    if (step.actor != DashboardStepActor.human && !step.isGateOpen) {
      return const SizedBox.shrink();
    }
    final (icon, label, color) = switch (step.state) {
      DashboardStepState.awaitingApproval => (
          Icons.pending_actions,
          'Awaiting you',
          MonokaiTheme.yellow
        ),
      DashboardStepState.needsLens => (
          Icons.pending_actions,
          'Parked',
          MonokaiTheme.orange
        ),
      // AUTOPILOT (design §1): the UI never lies about who decided. A gate the
      // POLICY cleared gets its own chip — a different word, a different
      // colour, and the evidence-stamped card id on hover — never a generic
      // "Approved", which reads as a person having looked at it.
      DashboardStepState.approved ||
      DashboardStepState.done =>
        step.isPolicyCleared
            ? (Icons.airplanemode_active, 'Auto-approved', MonokaiTheme.purple)
            : (Icons.verified, 'Approved', MonokaiTheme.green),
      DashboardStepState.failed => (
          Icons.gpp_bad,
          'Rejected',
          MonokaiTheme.red
        ),
      _ => (Icons.person, 'Human', MonokaiTheme.comment),
    };
    final lane = _Lane(icon: icon, label: label, color: color);
    // The card id is the EVIDENCE for a policy clearance. It rides on hover
    // rather than in the chip, exactly as the reference does — the operator
    // needs to see WHICH card cleared their gate without the DAG growing a
    // column for it.
    final card = step.approvedBy;
    if (step.isPolicyCleared && card != null) {
      return Tooltip(message: card, child: lane);
    }
    return lane;
  }
}

class _Lane extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Lane({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(label,
              style: MonokaiTheme.labelSmall.copyWith(color: color),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Approval gates
// ---------------------------------------------------------------------------

/// The panel for a step holding the run. A producer-review hold names the user
/// it waits on: only that user's approval clears it, and the card says so
/// rather than offering a button that will be refused without explanation.
class _GateCard extends StatelessWidget {
  final DagStep step;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _GateCard({
    required this.step,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final hold = step.isReviewHold;
    final waitingOn = step.waitingOn;
    // A LENS PARK is not an approval: nothing ran, so there is no AI result to
    // approve or reject. It is a step whose model never arrived, and the way
    // out is the human doing the work themselves and saying so.
    final parked = step.state == DashboardStepState.needsLens;
    // A MANUAL step is a human gate the same way: the resolution is "I did it",
    // not "I approve what the machine did" — so no Reject on either.
    final humanGate = !hold && step.actor == DashboardStepActor.human;
    final override = parked || humanGate;

    final accent = parked
        ? MonokaiTheme.orange
        : (hold ? MonokaiTheme.cyan : MonokaiTheme.yellow);
    final headline = parked
        ? 'Needs Lens'
        : hold
            ? 'In review — waiting on ${waitingOn ?? "a reviewer"}'
            : (humanGate ? 'Awaiting you' : 'Approval needed');
    final detail = parked
        ? 'No model is bound to run this step. The run has moved past it — '
            'mark it complete once you have done the work yourself.'
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
              parked
                  ? Icons.psychology_alt
                  : (hold ? Icons.how_to_reg : Icons.pan_tool),
              size: 14,
              color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline,
                    style: MonokaiTheme.labelMedium.copyWith(color: accent)),
                const SizedBox(height: 2),
                Text(step.title,
                    style: MonokaiTheme.bodyMedium
                        .copyWith(color: MonokaiTheme.foreground)),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(detail, style: MonokaiTheme.labelSmall),
                ],
              ],
            ),
          ),
          // The human override. Same write as an approve — the step settles —
          // but the word is "Complete", because the human did the work.
          _GateButton(
            label: override ? 'Complete' : 'Approve',
            color: MonokaiTheme.green,
            filled: true,
            onTap: busy ? null : onApprove,
          ),
          if (!override) ...[
            const SizedBox(width: 8),
            _GateButton(
              label: 'Reject',
              color: MonokaiTheme.red,
              filled: false,
              onTap: busy ? null : onReject,
            ),
          ],
        ],
      ),
    );
  }
}

/// A step the ENGINE parked because a required input is not there yet — conform
/// with no confirmed edits is the canonical case, and it sits in the middle of
/// the spine.
///
/// The operator goes and does the thing the ask names (confirms the proposed
/// edit, leaves the comment), then presses Re-run. Before this card existed a
/// parked step drew a yellow dot, the words "Awaiting input" and NO affordance
/// at all: the operator did the work in the NLE and then had no button, so the
/// run simply wedged — in both gate modes.
///
/// Swift reference: `DashboardView.parkedSteps`.
class _ParkedCard extends StatelessWidget {
  final DagStep step;
  final bool busy;
  final VoidCallback? onRerun;

  const _ParkedCard({
    required this.step,
    required this.busy,
    this.onRerun,
  });

  @override
  Widget build(BuildContext context) {
    // What the ask NAMES, when the engine said it — the operator needs to know
    // which input is missing, not merely that one is.
    final detail = step.error ?? step.waitingOn;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MonokaiTheme.yellow.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_empty,
              size: 16, color: MonokaiTheme.yellow),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Awaiting input',
                    style: MonokaiTheme.labelMedium
                        .copyWith(color: MonokaiTheme.yellow)),
                const SizedBox(height: 2),
                Text(step.title,
                    style: MonokaiTheme.bodyMedium
                        .copyWith(color: MonokaiTheme.foreground)),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(detail, style: MonokaiTheme.labelSmall),
                ],
              ],
            ),
          ),
          _GateButton(
            key: ValueKey('dashboard.rerun.${step.id}'),
            label: 'Re-run',
            color: MonokaiTheme.yellow,
            filled: true,
            onTap: busy ? null : onRerun,
          ),
        ],
      ),
    );
  }
}

class _GateButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;
  final VoidCallback? onTap;

  const _GateButton({
    super.key,
    required this.label,
    required this.color,
    required this.filled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dim = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: dim ? 0.4 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: filled ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color),
          ),
          child: Text(label,
              style: MonokaiTheme.labelMedium
                  .copyWith(color: filled ? MonokaiTheme.background : color)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step list
// ---------------------------------------------------------------------------

class _StepRow extends StatelessWidget {
  final DagStep step;
  final VoidCallback? onRetry;

  /// Execute just this step, out of order.
  final VoidCallback? onRunNow;

  /// The step this one is actually waiting for — parks already resolved
  /// through. Null means nothing holds it back.
  final DagStep? blockedBy;

  /// Whether this row reports readiness at all (only a queued step in a live
  /// run does; the pre-run preview is a plan, and nothing there is waiting).
  final bool showReadiness;

  const _StepRow({
    required this.step,
    this.onRetry,
    this.onRunNow,
    this.blockedBy,
    this.showReadiness = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = _stateColor(step.state);
    final progress = step.progressLabel;
    // What this step waits on, said plainly. A step whose only blocker PARKED
    // reads "Ready" — the park passed its dependencies through, so the chain
    // is not wedged and this step can be dispatched right now.
    final readiness = !showReadiness
        ? null
        : (blockedBy == null ? 'Ready' : 'Blocked by ${blockedBy!.title}');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title,
                    style: MonokaiTheme.bodyMedium
                        .copyWith(color: MonokaiTheme.foreground)),
                if (step.currentItem != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(step.currentItem!,
                        style: MonokaiTheme.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                if (readiness != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(readiness,
                        style: MonokaiTheme.labelSmall.copyWith(
                            color: blockedBy == null
                                ? MonokaiTheme.green
                                : MonokaiTheme.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                if (step.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(step.error!,
                        style: MonokaiTheme.labelSmall
                            .copyWith(color: MonokaiTheme.red),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
          if (progress != null) ...[
            const SizedBox(width: 8),
            Text(progress,
                style: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.textSecondary)),
          ],
          const SizedBox(width: 10),
          Text(step.stateLabel,
              style: MonokaiTheme.labelSmall.copyWith(color: color)),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            _GateButton(
              label: 'Retry',
              color: MonokaiTheme.cyan,
              filled: false,
              onTap: onRetry,
            ),
          ],
          if (onRunNow != null) ...[
            const SizedBox(width: 8),
            _GateButton(
              key: ValueKey('run-now-${step.id}'),
              label: 'Run now',
              color: MonokaiTheme.cyan,
              filled: false,
              onTap: onRunNow,
            ),
          ],
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: MonokaiTheme.surface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(step.actor == DashboardStepActor.human ? 'Human' : 'AI',
                style: MonokaiTheme.labelSmall),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Run-level progress + stats
// ---------------------------------------------------------------------------

class _CurrentItem extends StatelessWidget {
  final DashboardState state;
  const _CurrentItem({required this.state});

  @override
  Widget build(BuildContext context) {
    final counts = state.itemsTotal > 0
        ? '${state.itemsProcessed} / ${state.itemsTotal}'
        : '${state.itemsProcessed}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.movie_filter, size: 14, color: MonokaiTheme.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Processing ${state.currentItem}',
                style: MonokaiTheme.bodyMedium
                    .copyWith(color: MonokaiTheme.foreground),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (state.currentStage != null) ...[
            Text(state.currentStage!, style: MonokaiTheme.labelSmall),
            const SizedBox(width: 12),
          ],
          Text(counts,
              style: MonokaiTheme.labelMedium
                  .copyWith(color: MonokaiTheme.textSecondary)),
        ],
      ),
    );
  }
}

/// The run meter, straight off the snapshot — never recomputed here.
class _Totals extends StatelessWidget {
  final DashboardSnapshot snapshot;
  const _Totals({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final t = snapshot.totals;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Totals', style: MonokaiTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              _Meter(
                  label: 'Wall', value: '${t.wallMinutes.toStringAsFixed(1)}m'),
              _Meter(
                  label: 'Human',
                  value: '${t.humanMinutes.toStringAsFixed(1)}m'),
              _Meter(label: 'AI', value: '${t.aiMinutes.toStringAsFixed(1)}m'),
              _Meter(label: 'Files', value: '${t.filesProcessed}'),
              _Meter(
                  label: 'Est. cost',
                  value: '\$${t.estCostUsd.toStringAsFixed(2)}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  final String label;
  final String value;
  const _Meter({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: MonokaiTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value,
              style: MonokaiTheme.titleSmall
                  .copyWith(color: MonokaiTheme.foreground)),
        ],
      ),
    );
  }
}

/// The terminal state, named. `Run done` / `Run failed` / `Run cancelled` —
/// never a run that simply stops updating.
class _DoneSummary extends StatelessWidget {
  final WorkflowRunState? finished;
  const _DoneSummary({required this.finished});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (finished) {
      WorkflowRunState.failed => (
          Icons.error_outline,
          'Run failed',
          MonokaiTheme.red
        ),
      WorkflowRunState.cancelled => (
          Icons.cancel_outlined,
          'Run cancelled',
          MonokaiTheme.comment
        ),
      _ => (Icons.verified, 'Run done', MonokaiTheme.green),
    };
    return _Banner(icon: icon, text: label, color: color);
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Banner({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: MonokaiTheme.bodyMedium.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final Color color;

  const _Placeholder({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: color),
          const SizedBox(height: 14),
          Text(title,
              style: MonokaiTheme.titleSmall
                  .copyWith(color: MonokaiTheme.textMuted)),
          const SizedBox(height: 6),
          Text(detail,
              style: MonokaiTheme.labelMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
