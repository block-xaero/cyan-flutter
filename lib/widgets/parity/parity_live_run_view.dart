// widgets/parity/parity_live_run_view.dart
//
// PARITY port of the SwiftUI live run surface — `DashboardView`'s running
// phase driven by `DashboardViewModel.apply/reconstruct`, with the connection
// strip `SyncStatusMachine` feeds above it.
//
// The Dashboard face (parity_dashboard_view.dart) renders a run the engine
// already settled. THIS face renders one while it is still moving, which means
// it renders the engine misbehaving too: the strip is a first-class row, not an
// error dialog, because "the buffer is ahead of us" and "the engine just died"
// are states an operator watching a render run needs to SEE.
//
// Everything comes off `LiveRunController` (the `CyanBackend` seam) — no FFI.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/dashboard_event.dart';
import '../../providers/live_run_controller.dart';
import '../../providers/live_run_provider.dart';
import '../../theme/monokai_theme.dart';

class ParityLiveRunView extends ConsumerWidget {
  final String boardId;

  /// An explicit pump, for callers that drive their own cycles (Tier-1 tests
  /// step [LiveRunController.tick] one cycle at a time). Null uses the app's
  /// own per-board pump.
  final LiveRunController? controller;

  const ParityLiveRunView({
    super.key,
    required this.boardId,
    this.controller,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LiveRunController pump =
        controller ?? ref.watch(liveRunProvider(boardId).notifier);
    return _Surface(key: ObjectKey(pump), controller: pump);
  }
}

/// Subscribes to the pump and rebuilds on every published state.
class _Surface extends StatefulWidget {
  final LiveRunController controller;

  const _Surface({super.key, required this.controller});

  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  late LiveRunState _state;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LinkStrip(state: _state, onRetry: widget.controller.retry),
          const Divider(height: 1, color: MonokaiTheme.divider),
          Expanded(child: _Body(state: _state)),
        ],
      ),
    );
  }
}

/// The connection strip. Always present — an operator should never have to
/// infer whether what they are looking at is current.
class _LinkStrip extends StatelessWidget {
  final LiveRunState state;
  final Future<void> Function() onRetry;

  const _LinkStrip({required this.state, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (state.link) {
      LiveRunLink.live => (Icons.sensors, 'Live', MonokaiTheme.green),
      LiveRunLink.catchingUp => (
          Icons.history_toggle_off,
          'Catching up…',
          MonokaiTheme.cyan
        ),
      LiveRunLink.degraded => (
          Icons.warning_amber_rounded,
          'Reconnecting…',
          MonokaiTheme.orange
        ),
      LiveRunLink.unreachable => (
          Icons.cloud_off,
          'Cannot reach the engine',
          MonokaiTheme.red
        ),
    };
    final broken = state.link == LiveRunLink.degraded ||
        state.link == LiveRunLink.unreachable;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: broken ? color.withValues(alpha: 0.12) : Colors.transparent,
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 7),
          Text(label, style: MonokaiTheme.labelMedium.copyWith(color: color)),
          if (broken && state.lastError != null) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                state.lastError!,
                style: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const Spacer(),
          // Version skew made visible: frames this build could not decode are
          // counted on screen rather than swallowed.
          if (state.droppedFrames > 0)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                '${state.droppedFrames} unreadable',
                style: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.yellow),
              ),
            ),
          if (broken)
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color),
                ),
                child: Text('Retry',
                    style: MonokaiTheme.labelMedium.copyWith(color: color)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final LiveRunState state;
  const _Body({required this.state});

  @override
  Widget build(BuildContext context) {
    // A spinner is honest ONLY before the first read has come back at all.
    if (!state.hydrated) {
      return const Center(
        child: CircularProgressIndicator(color: MonokaiTheme.cyan),
      );
    }
    // Nothing was ever read and the engine is not answering: say so, and offer
    // the way out (the strip's Retry). Never a spinner that spins forever.
    if (!state.hasRun && state.link == LiveRunLink.unreachable) {
      return const _Placeholder(
        icon: Icons.cloud_off,
        title: 'Cannot reach the engine',
        detail: 'The run could not be read. Retry when the engine is back.',
        color: MonokaiTheme.red,
      );
    }
    // A null read is an ANSWER: this board has no run.
    if (!state.hasRun) {
      return const _Placeholder(
        icon: Icons.play_circle_outline,
        title: 'No run yet',
        detail: 'Start this workflow to watch it run here',
        color: MonokaiTheme.textDisabled,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _RunHeader(state: state),
        const SizedBox(height: 16),
        Text('Steps', style: MonokaiTheme.labelLarge),
        const SizedBox(height: 8),
        for (final step in state.steps) _StepRow(step: step),
        if (state.currentItem != null) ...[
          const SizedBox(height: 14),
          _CurrentItem(state: state),
        ],
        if (state.snapshot != null) ...[
          const SizedBox(height: 18),
          _Metering(snapshot: state.snapshot!),
        ],
      ],
    );
  }
}

class _RunHeader extends StatelessWidget {
  final LiveRunState state;
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
                state.title.isEmpty ? 'Untitled run' : state.title,
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _pillColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(state.statusLabel,
              style: MonokaiTheme.labelMedium.copyWith(color: _pillColor)),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final LiveStep step;
  const _StepRow({required this.step});

  Color get _dotColor => switch (step.state) {
        DashboardStepState.pending => MonokaiTheme.comment,
        DashboardStepState.running => MonokaiTheme.cyan,
        DashboardStepState.awaitingApproval => MonokaiTheme.yellow,
        DashboardStepState.awaitingInput => MonokaiTheme.yellow,
        DashboardStepState.needsLens => MonokaiTheme.orange,
        DashboardStepState.approved => MonokaiTheme.green,
        DashboardStepState.done => MonokaiTheme.green,
        DashboardStepState.failed => MonokaiTheme.red,
      };

  String get _stateLabel => switch (step.state) {
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
  Widget build(BuildContext context) {
    final progress = step.progressLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: _dotColor, shape: BoxShape.circle),
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
          Text(_stateLabel,
              style: MonokaiTheme.labelSmall.copyWith(color: _dotColor)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: MonokaiTheme.surface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
                step.actor == DashboardStepActor.human ? 'Human' : 'AI',
                style: MonokaiTheme.labelSmall),
          ),
        ],
      ),
    );
  }
}

/// The run-level progress line. Sticky: the last item we were told about stays
/// on screen when the engine goes quiet, because it is still the last true
/// thing we know.
class _CurrentItem extends StatelessWidget {
  final LiveRunState state;
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
          Text(counts,
              style: MonokaiTheme.labelMedium
                  .copyWith(color: MonokaiTheme.textSecondary)),
        ],
      ),
    );
  }
}

/// The run meter, straight off `WorkflowStatsUpdated` — never recomputed here.
class _Metering extends StatelessWidget {
  final DashboardSnapshot snapshot;
  const _Metering({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final t = snapshot.totals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Totals', style: MonokaiTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            _Meter(label: 'Wall', value: '${t.wallMinutes.toStringAsFixed(1)}m'),
            _Meter(label: 'AI', value: '${t.aiMinutes.toStringAsFixed(1)}m'),
            _Meter(label: 'Files', value: '${t.filesProcessed}'),
            _Meter(
                label: 'Est. cost',
                value: '\$${t.estCostUsd.toStringAsFixed(2)}'),
          ],
        ),
      ],
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
              style:
                  MonokaiTheme.titleSmall.copyWith(color: MonokaiTheme.textMuted)),
          const SizedBox(height: 6),
          Text(detail, style: MonokaiTheme.labelMedium),
        ],
      ),
    );
  }
}
