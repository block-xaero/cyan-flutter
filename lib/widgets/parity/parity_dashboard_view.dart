// widgets/parity/parity_dashboard_view.dart
//
// PARITY port of the SwiftUI `DashboardView` — the Board "Dashboard" face
// (PARITY_TRACKER row 4): a run header with a status pill, a horizontal DAG of
// pipeline step boxes (each with an AI lane + a human lane signal), an approval
// gate panel for the step awaiting sign-off (AI → Approve/Reject, human →
// Complete), and a compact collapsed pipeline step list.
//
// Driven ENTIRELY through the `CyanBackend` seam (via `boardRunProvider`). This
// widget never touches `CyanFFI` directly — that is the parity rule.
//
// SwiftUI reference (read-only): cyan-iOS-ready/Cyan/Cyan/Views/DashboardView.swift
//   + PipelinePreviewView.swift (the DAG step boxes + connectors).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';

class ParityDashboardView extends ConsumerWidget {
  final String boardId;

  /// Approve / Complete a step that is awaiting sign-off — UI-only here.
  final void Function(RunStep step)? onApprove;

  /// Reject an AI step awaiting approval — UI-only here.
  final void Function(RunStep step)? onReject;

  const ParityDashboardView({
    super.key,
    required this.boardId,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runAsync = ref.watch(boardRunProvider(boardId));

    return Material(
      color: MonokaiTheme.background,
      child: runAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MonokaiTheme.cyan),
        ),
        error: (e, _) => Center(
          child: Text('Failed to load run: $e',
              style:
                  MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.red)),
        ),
        data: (run) => run == null
            ? const _NoRun()
            : _RunBody(run: run, onApprove: onApprove, onReject: onReject),
      ),
    );
  }
}

class _RunBody extends StatelessWidget {
  final WorkflowRun run;
  final void Function(RunStep step)? onApprove;
  final void Function(RunStep step)? onReject;

  const _RunBody({required this.run, this.onApprove, this.onReject});

  @override
  Widget build(BuildContext context) {
    final pending = run.steps
        .where((s) => s.status == RunStepStatus.awaitingApproval)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _RunHeader(run: run),
        const SizedBox(height: 16),
        Text('Workflow', style: MonokaiTheme.labelLarge),
        const SizedBox(height: 8),
        _Dag(steps: run.steps),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 20),
          for (final s in pending)
            _ApprovalGate(
              step: s,
              onApprove: () => onApprove?.call(s),
              onReject: () => onReject?.call(s),
            ),
        ],
        const SizedBox(height: 20),
        Text('Steps', style: MonokaiTheme.labelLarge),
        const SizedBox(height: 8),
        for (final s in run.steps) _StepListRow(step: s),
      ],
    );
  }
}

class _RunHeader extends StatelessWidget {
  final WorkflowRun run;
  const _RunHeader({required this.run});

  @override
  Widget build(BuildContext context) {
    final running =
        run.steps.any((s) => s.status == RunStepStatus.running) ||
            run.steps.any((s) => s.status == RunStepStatus.awaitingApproval);
    final done = run.steps.every((s) => s.status == RunStepStatus.done);
    final (label, color) = done
        ? ('Done', MonokaiTheme.green)
        : running
            ? ('Running', MonokaiTheme.cyan)
            : ('Queued', MonokaiTheme.textMuted);
    final completed =
        run.steps.where((s) => s.status == RunStepStatus.done).length;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(run.title, style: MonokaiTheme.titleMedium),
              const SizedBox(height: 4),
              Text('$completed / ${run.steps.length} steps complete',
                  style: MonokaiTheme.labelMedium),
            ],
          ),
        ),
        _StatusPill(label: label, color: color),
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
      child: Text(label,
          style: MonokaiTheme.labelMedium.copyWith(color: color)),
    );
  }
}

/// Horizontal scroll of step boxes connected by arrows (the DAG).
class _Dag extends StatelessWidget {
  final List<RunStep> steps;
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward,
                    size: 14, color: MonokaiTheme.comment),
              ),
          ],
        ],
      ),
    );
  }
}

class _StepBox extends StatelessWidget {
  final RunStep step;
  const _StepBox({required this.step});

  Color get _stateColor => switch (step.status) {
        RunStepStatus.pending => MonokaiTheme.comment,
        RunStepStatus.running => MonokaiTheme.cyan,
        RunStepStatus.awaitingApproval => MonokaiTheme.yellow,
        RunStepStatus.done => MonokaiTheme.green,
        RunStepStatus.failed => MonokaiTheme.red,
      };

  @override
  Widget build(BuildContext context) {
    final color = _stateColor;
    return Container(
      width: 142,
      height: 84,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AiSignal(step: step),
              const SizedBox(width: 6),
              _HumanSignal(step: step),
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
        ],
      ),
    );
  }
}

/// The AI (machine) lane signal — present for AI steps.
class _AiSignal extends StatelessWidget {
  final RunStep step;
  const _AiSignal({required this.step});

  @override
  Widget build(BuildContext context) {
    if (step.kind != RunStepKind.ai) {
      return Text('·',
          style: MonokaiTheme.labelSmall
              .copyWith(color: MonokaiTheme.comment.withValues(alpha: 0.5)));
    }
    final (icon, label, color) = switch (step.status) {
      RunStepStatus.pending => (Icons.circle_outlined, 'AI queued', MonokaiTheme.comment),
      RunStepStatus.running => (Icons.settings, 'AI running', MonokaiTheme.cyan),
      RunStepStatus.done => (Icons.check_circle, 'AI done', MonokaiTheme.cyan),
      RunStepStatus.failed => (Icons.cancel, 'AI failed', MonokaiTheme.red),
      RunStepStatus.awaitingApproval => (Icons.settings, 'AI done', MonokaiTheme.cyan),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 3),
        Text(label, style: MonokaiTheme.labelSmall.copyWith(color: color)),
      ],
    );
  }
}

/// The human (gate) lane signal.
class _HumanSignal extends StatelessWidget {
  final RunStep step;
  const _HumanSignal({required this.step});

  @override
  Widget build(BuildContext context) {
    if (step.kind != RunStepKind.human &&
        step.status != RunStepStatus.awaitingApproval) {
      return const SizedBox.shrink();
    }
    final (icon, label, color) = switch (step.status) {
      RunStepStatus.awaitingApproval => (
          Icons.pending_actions,
          'Awaiting you',
          MonokaiTheme.yellow
        ),
      RunStepStatus.done => (Icons.verified, 'Approved', MonokaiTheme.green),
      RunStepStatus.failed => (Icons.gpp_bad, 'Rejected', MonokaiTheme.red),
      _ => (Icons.person, 'Human', MonokaiTheme.comment),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 3),
        Text(label, style: MonokaiTheme.labelSmall.copyWith(color: color)),
      ],
    );
  }
}

/// The yellow gate panel for a step awaiting sign-off.
class _ApprovalGate extends StatelessWidget {
  final RunStep step;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _ApprovalGate({required this.step, this.onApprove, this.onReject});

  @override
  Widget build(BuildContext context) {
    final isHuman = step.kind == RunStepKind.human;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MonokaiTheme.yellow.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.pan_tool, size: 14, color: MonokaiTheme.yellow),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isHuman ? 'Awaiting you' : 'Approval needed',
                    style: MonokaiTheme.labelMedium
                        .copyWith(color: MonokaiTheme.yellow)),
                const SizedBox(height: 2),
                Text(step.title,
                    style: MonokaiTheme.bodyMedium
                        .copyWith(color: MonokaiTheme.foreground)),
              ],
            ),
          ),
          _GateButton(
            label: isHuman ? 'Complete' : 'Approve',
            color: MonokaiTheme.green,
            filled: true,
            onTap: onApprove,
          ),
          if (!isHuman) ...[
            const SizedBox(width: 8),
            _GateButton(
              label: 'Reject',
              color: MonokaiTheme.red,
              filled: false,
              onTap: onReject,
            ),
          ],
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
    required this.label,
    required this.color,
    required this.filled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color),
        ),
        child: Text(label,
            style: MonokaiTheme.labelMedium.copyWith(
                color: filled ? MonokaiTheme.background : color)),
      ),
    );
  }
}

/// Collapsed pipeline step row (the compact step list under the DAG).
class _StepListRow extends StatelessWidget {
  final RunStep step;
  const _StepListRow({required this.step});

  Color get _dotColor => switch (step.status) {
        RunStepStatus.pending => MonokaiTheme.comment,
        RunStepStatus.running => MonokaiTheme.cyan,
        RunStepStatus.awaitingApproval => MonokaiTheme.yellow,
        RunStepStatus.done => MonokaiTheme.green,
        RunStepStatus.failed => MonokaiTheme.red,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(step.title,
                style: MonokaiTheme.bodyMedium
                    .copyWith(color: MonokaiTheme.foreground)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: MonokaiTheme.surface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
                step.kind == RunStepKind.ai ? 'AI' : 'Human',
                style: MonokaiTheme.labelSmall),
          ),
        ],
      ),
    );
  }
}

class _NoRun extends StatelessWidget {
  const _NoRun();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.play_circle_outline,
              size: 56, color: MonokaiTheme.textDisabled),
          const SizedBox(height: 14),
          Text('No run yet',
              style: MonokaiTheme.titleSmall
                  .copyWith(color: MonokaiTheme.textMuted)),
          const SizedBox(height: 6),
          Text('Compile and run this workflow to see the dashboard',
              style: MonokaiTheme.labelMedium),
        ],
      ),
    );
  }
}
