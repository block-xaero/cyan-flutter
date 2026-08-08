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
// Driven ENTIRELY through the `LensApi` seam (via `opsRunsProvider`, D3). This
// widget never touches HTTP or `CyanFFI` directly — that is the parity rule.
//
// The three actions are REAL: Retry / Approve / Reject POST to the lens through
// `opsCommandProvider`, which re-reads the feed afterwards and surfaces the
// lens's refusal in the operator's sight. The optional callbacks are an
// OVERRIDE, not the wiring — a host screen that wants to confirm first supplies
// one and the widget defers to it entirely.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/lens_console_provider.dart';
import '../../theme/monokai_theme.dart';
import 'parity_ops_scaffold.dart';

class ParityOpsRuns extends ConsumerWidget {
  /// Intercept Retry. When null the widget POSTs to the lens itself.
  final void Function(OpsRun run)? onRetry;

  /// Intercept Approve. When null the widget POSTs to the lens itself.
  final void Function(OpsRun run)? onApprove;

  /// Intercept Reject. When null the widget POSTs to the lens itself.
  final void Function(OpsRun run)? onReject;

  /// Turning the console's segmented control. Null leaves the header inert,
  /// which is right when this face is mounted on its own.
  final void Function(OpsFace)? onSelectFace;

  const ParityOpsRuns({
    super.key,
    this.onRetry,
    this.onApprove,
    this.onReject,
    this.onSelectFace,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runsAsync = ref.watch(opsRunsProvider);
    final commands = ref.watch(opsCommandProvider);
    final controller = ref.read(opsCommandProvider.notifier);

    void act(void Function(OpsRun)? override, OpsRun run,
        Future<void> Function(String) command) {
      if (override != null) {
        override(run);
        return;
      }
      command(run.runId);
    }

    return OpsScaffold(
      face: OpsFace.runs,
      onSelectFace: onSelectFace,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (commands.lastError != null)
            _RefusalBanner(message: commands.lastError!),
          Expanded(
            child: runsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: MonokaiTheme.cyan),
              ),
              // The lens being unreachable is a NAMED state, not a blank
              // console — an empty board would read as "no runs", which is a
              // claim this face has not earned.
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Failed to load runs: $e',
                      key: const ValueKey('ops-runs-error'),
                      textAlign: TextAlign.center,
                      style: MonokaiTheme.bodyMedium
                          .copyWith(color: MonokaiTheme.red)),
                ),
              ),
              data: (runs) => _Lanes(
                runs: runs,
                busy: commands.busyRunIds,
                onRetry: (r) => act(onRetry, r, controller.retry),
                onApprove: (r) => act(onApprove, r, controller.approve),
                onReject: (r) => act(onReject, r, controller.reject),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The lens's own words when it refused a command (e.g. the CONFLICT "only a
/// Failed run can be retried"). Shown rather than swallowed: a tap that does
/// nothing and says nothing is indistinguishable from a broken button.
class _RefusalBanner extends StatelessWidget {
  final String message;
  const _RefusalBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('ops-command-error'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: MonokaiTheme.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MonokaiTheme.red.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 14, color: MonokaiTheme.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style:
                    MonokaiTheme.labelMedium.copyWith(color: MonokaiTheme.red)),
          ),
        ],
      ),
    );
  }
}

class _Lanes extends StatelessWidget {
  final List<OpsRun> runs;
  final Set<String> busy;
  final void Function(OpsRun run) onRetry;
  final void Function(OpsRun run) onApprove;
  final void Function(OpsRun run) onReject;

  const _Lanes({
    required this.runs,
    required this.busy,
    required this.onRetry,
    required this.onApprove,
    required this.onReject,
  });

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
          busy: busy,
          onRetry: onRetry,
          onApprove: onApprove,
          onReject: onReject,
        ),
        _Lane(
          title: 'Running',
          accent: MonokaiTheme.cyan,
          runs: running,
          busy: busy,
          onRetry: onRetry,
          onApprove: onApprove,
          onReject: onReject,
        ),
        _Lane(
          title: 'Action needed',
          accent: MonokaiTheme.yellow,
          runs: actionNeeded,
          busy: busy,
          onRetry: onRetry,
          onApprove: onApprove,
          onReject: onReject,
        ),
        _Lane(
          title: 'Done',
          accent: MonokaiTheme.green,
          runs: done,
          busy: busy,
          onRetry: onRetry,
          onApprove: onApprove,
          onReject: onReject,
        ),
      ],
    );
  }
}

class _Lane extends StatelessWidget {
  final String title;
  final Color accent;
  final List<OpsRun> runs;
  final Set<String> busy;
  final void Function(OpsRun run) onRetry;
  final void Function(OpsRun run) onApprove;
  final void Function(OpsRun run) onReject;

  const _Lane({
    required this.title,
    required this.accent,
    required this.runs,
    required this.busy,
    required this.onRetry,
    required this.onApprove,
    required this.onReject,
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
                        isBusy: busy.contains(r.runId),
                        onRetry: onRetry,
                        onApprove: onApprove,
                        onReject: onReject,
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

  /// A command is round-tripping for this run: the actions disable so a tap can
  /// neither look like a no-op nor be double-fired.
  final bool isBusy;
  final void Function(OpsRun run) onRetry;
  final void Function(OpsRun run) onApprove;
  final void Function(OpsRun run) onReject;

  const _RunCard({
    required this.run,
    required this.isBusy,
    required this.onRetry,
    required this.onApprove,
    required this.onReject,
  });

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
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(9)),
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
                    _meta('dur',
                        run.durationLabel.isEmpty ? '—' : run.durationLabel),
                  ],
                ),
                if (run.status == RunStatus.failed ||
                    run.status == RunStatus.awaitingApproval) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (run.status == RunStatus.failed)
                        _action('Retry', MonokaiTheme.orange, false,
                            isBusy ? null : () => onRetry(run)),
                      if (run.status == RunStatus.awaitingApproval) ...[
                        _action('Approve', MonokaiTheme.green, true,
                            isBusy ? null : () => onApprove(run)),
                        const SizedBox(width: 8),
                        _action('Reject', MonokaiTheme.red, false,
                            isBusy ? null : () => onReject(run)),
                      ],
                      if (isBusy) ...[
                        const SizedBox(width: 10),
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: MonokaiTheme.cyan),
                        ),
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
            style:
                MonokaiTheme.codeSmall.copyWith(color: MonokaiTheme.comment)),
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
            style: MonokaiTheme.labelMedium
                .copyWith(color: filled ? MonokaiTheme.background : color)),
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
          style:
              MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.background)),
    );
  }
}
