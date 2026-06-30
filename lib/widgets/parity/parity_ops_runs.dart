// widgets/parity/parity_ops_runs.dart
//
// PARITY port of the SwiftUI `OperationsConsoleView` Runs face (PARITY_TRACKER
// row 6): the run feed. The SwiftUI app distinguishes "action needed"
// (approval / stuck / failed) from "done", and lays runs out as cinematic
// cards with a status badge, a stage/duration strip, a monospaced meta row
// (steps · cost · dur), and inline action buttons (Retry / Approve+Reject).
//
// Here the feed is laid out as four lanes — Queued · Running · Action needed ·
// Done — the operator's mental model of the run pipeline. A header segmented
// control (Runs · Cost · Efficiency) selects the console face; this widget owns
// the Runs face.
//
// Driven ENTIRELY through the `CyanBackend` seam (via `opsRunsProvider`). This
// widget never touches `CyanFFI` directly — that is the parity rule.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';
import 'parity_ops_scaffold.dart';

class ParityOpsRuns extends ConsumerWidget {
  /// Retry a failed run — UI-only here.
  final void Function(OpsRun run)? onRetry;

  /// Approve a run awaiting sign-off — UI-only here.
  final void Function(OpsRun run)? onApprove;

  const ParityOpsRuns({super.key, this.onRetry, this.onApprove});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runsAsync = ref.watch(opsRunsProvider);

    return OpsScaffold(
      face: OpsFace.runs,
      child: runsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MonokaiTheme.cyan),
        ),
        error: (e, _) => Center(
          child: Text('Failed to load runs: $e',
              style:
                  MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.red)),
        ),
        data: (runs) => _Lanes(runs: runs, onRetry: onRetry, onApprove: onApprove),
      ),
    );
  }
}

class _Lanes extends StatelessWidget {
  final List<OpsRun> runs;
  final void Function(OpsRun run)? onRetry;
  final void Function(OpsRun run)? onApprove;

  const _Lanes({required this.runs, this.onRetry, this.onApprove});

  @override
  Widget build(BuildContext context) {
    final queued = runs.where((r) => r.status == RunStatus.queued).toList();
    final running = runs.where((r) => r.status == RunStatus.running).toList();
    final actionNeeded = runs.where((r) => r.status.needsAction).toList();
    final done = runs.where((r) => r.status == RunStatus.done).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Lane(
          title: 'Queued',
          accent: MonokaiTheme.textMuted,
          runs: queued,
          onRetry: onRetry,
          onApprove: onApprove,
        ),
        _Lane(
          title: 'Running',
          accent: MonokaiTheme.cyan,
          runs: running,
          onRetry: onRetry,
          onApprove: onApprove,
        ),
        _Lane(
          title: 'Action needed',
          accent: MonokaiTheme.yellow,
          runs: actionNeeded,
          onRetry: onRetry,
          onApprove: onApprove,
        ),
        _Lane(
          title: 'Done',
          accent: MonokaiTheme.green,
          runs: done,
          onRetry: onRetry,
          onApprove: onApprove,
        ),
      ],
    );
  }
}

class _Lane extends StatelessWidget {
  final String title;
  final Color accent;
  final List<OpsRun> runs;
  final void Function(OpsRun run)? onRetry;
  final void Function(OpsRun run)? onApprove;

  const _Lane({
    required this.title,
    required this.accent,
    required this.runs,
    this.onRetry,
    this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(title,
                  key: ValueKey('ops-lane-$title'),
                  style: MonokaiTheme.labelLarge),
              const SizedBox(width: 6),
              Text('(${runs.length})', style: MonokaiTheme.labelMedium),
            ],
          ),
        ),
        if (runs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text('—', style: MonokaiTheme.labelMedium),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: runs
                .map((r) => SizedBox(
                      width: 300,
                      child: _RunCard(
                        run: r,
                        onRetry: onRetry,
                        onApprove: onApprove,
                      ),
                    ))
                .toList(),
          ),
      ],
    );
  }
}

class _RunCard extends StatelessWidget {
  final OpsRun run;
  final void Function(OpsRun run)? onRetry;
  final void Function(OpsRun run)? onApprove;

  const _RunCard({required this.run, this.onRetry, this.onApprove});

  String get _stripText => switch (run.status) {
        RunStatus.done || RunStatus.failed => run.durationLabel,
        RunStatus.running => run.stageLabel ?? '',
        _ => '',
      };

  Color get _statusColor => switch (run.status) {
        RunStatus.queued => MonokaiTheme.comment,
        RunStatus.running => MonokaiTheme.cyan,
        RunStatus.awaitingApproval => MonokaiTheme.yellow,
        RunStatus.stuck => MonokaiTheme.orange,
        RunStatus.done => MonokaiTheme.green,
        RunStatus.failed => MonokaiTheme.red,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MonokaiTheme.surfaceLighter,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MonokaiTheme.border.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cinematic 16:9 thumbnail strip.
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          MonokaiTheme.surface,
                          MonokaiTheme.background,
                        ],
                      ),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(9)),
                    ),
                    child: const Center(
                      child: Icon(Icons.movie,
                          size: 28, color: MonokaiTheme.comment),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: _Badge(label: run.status.label, color: _statusColor),
                ),
                // Stage/duration strip — only for in-flight (running) or
                // terminal (done/failed) runs, matching the SwiftUI reference;
                // a queued run carries no stage yet.
                if (_stripText.isNotEmpty)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: MonokaiTheme.background.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _stripText,
                        style: MonokaiTheme.codeSmall
                            .copyWith(color: MonokaiTheme.foreground),
                      ),
                    ),
                  ),
                // In-flight progress under the stage strip.
                if (run.status == RunStatus.running && run.stepCount > 0)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      value: run.currentStep / run.stepCount,
                      minHeight: 3,
                      backgroundColor: MonokaiTheme.border,
                      color: MonokaiTheme.cyan,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(run.asset,
                    style: MonokaiTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                // Monospaced meta row — wraps so the card never overflows.
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _meta('steps', '${run.currentStep}/${run.stepCount}'),
                    _meta('cost', '\$${run.costDollars.toStringAsFixed(2)}'),
                    _meta('dur', run.durationLabel.isEmpty ? '—' : run.durationLabel),
                  ],
                ),
                if (run.status == RunStatus.failed ||
                    run.status == RunStatus.awaitingApproval) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (run.status == RunStatus.failed)
                        _action('Retry', MonokaiTheme.orange, false,
                            () => onRetry?.call(run)),
                      if (run.status == RunStatus.awaitingApproval) ...[
                        _action('Approve', MonokaiTheme.green, true,
                            () => onApprove?.call(run)),
                        const SizedBox(width: 8),
                        _action('Reject', MonokaiTheme.red, false, null),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _meta(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ',
            style: MonokaiTheme.codeSmall
                .copyWith(color: MonokaiTheme.comment)),
        Text(value,
            style: MonokaiTheme.codeSmall
                .copyWith(color: MonokaiTheme.foreground)),
      ],
    );
  }

  static Widget _action(
      String label, Color color, bool filled, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.background)),
    );
  }
}
