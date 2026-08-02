// widgets/parity/parity_run_audit.dart
//
// PARITY port of the SwiftUI `RunAuditView` (the run drill-down "audit on
// screen") and the `UsageCostPanel` (cost & usage), both scoped to ONE run.
//
// The point of the audit is EXPLAINABILITY: a figure like "$0.22" on a run card
// has to be attributable to the steps that burned it. So the reconciled totals
// at the top are summed from the per-step rows underneath them — the rollups
// read `RunTrace.billedMinutesRollup` / `billedCentsRollup`, which sum the step
// records whenever the lens has not served a run-level total. The BILL is
// asset-minutes; GPU, wall and tokens are internal COGS and are labelled `·int`
// so they can never be misread as the customer's bill.
//
// Driven ENTIRELY through the `CyanBackend` seam (via `runTraceProvider`) —
// these widgets never touch `CyanFFI` directly.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';

// ---------------------------------------------------------------------------
// Formatting — shared by the audit rails and the cost panel
// ---------------------------------------------------------------------------

/// Milliseconds → a compact `1.2s` / `820ms` label.
String fmtWallMs(int ms) =>
    ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)}s' : '${ms}ms';

/// Cents → `$0.22`.
String fmtCents(double cents) => '\$${(cents / 100.0).toStringAsFixed(2)}';

/// Billed media-minutes — whole once the figure is big enough to not need the
/// decimal, exactly as the SwiftUI meter reads it.
String fmtBilledMinutes(double minutes) =>
    minutes >= 10 ? minutes.toStringAsFixed(0) : minutes.toStringAsFixed(1);

Color stepStatusColor(String status) => switch (status) {
      'Done' => MonokaiTheme.green,
      'Running' => MonokaiTheme.cyan,
      'Failed' => MonokaiTheme.red,
      'Skipped' => MonokaiTheme.comment,
      _ => MonokaiTheme.comment,
    };

// ---------------------------------------------------------------------------
// Run audit — the per-step provenance
// ---------------------------------------------------------------------------

class ParityRunAudit extends ConsumerWidget {
  final String runId;

  /// Dismiss the drill-down — UI-only here; the host owns the sheet.
  final VoidCallback? onClose;

  const ParityRunAudit({super.key, required this.runId, this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traceAsync = ref.watch(runTraceProvider(runId));

    return Container(
      color: MonokaiTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AuditHeader(runId: runId, onClose: onClose),
          const Divider(height: 1, color: MonokaiTheme.divider),
          Expanded(
            child: traceAsync.when(
              loading: () => const _AuditMessage(
                icon: Icons.hourglass_empty,
                title: 'Loading run audit…',
                tint: MonokaiTheme.comment,
              ),
              error: (e, _) => _AuditMessage(
                icon: Icons.warning_amber,
                title: "Couldn't load run audit",
                detail: '$e',
                tint: MonokaiTheme.yellow,
              ),
              data: (trace) => trace == null
                  ? const _AuditMessage(
                      icon: Icons.warning_amber,
                      title: "Couldn't load run audit",
                      detail: 'The lens has no trace for this run yet.',
                      tint: MonokaiTheme.yellow,
                    )
                  : _AuditBody(trace: trace),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditHeader extends StatelessWidget {
  final String runId;
  final VoidCallback? onClose;

  const _AuditHeader({required this.runId, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Run audit', style: MonokaiTheme.titleSmall),
                const SizedBox(height: 2),
                Text(runId,
                    style: MonokaiTheme.codeSmall
                        .copyWith(color: MonokaiTheme.comment),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (onClose != null)
            GestureDetector(
              key: const ValueKey('audit-close'),
              onTap: onClose,
              child: Text('Close',
                  style: MonokaiTheme.labelMedium
                      .copyWith(color: MonokaiTheme.cyan)),
            ),
        ],
      ),
    );
  }
}

class _AuditMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? detail;
  final Color tint;

  const _AuditMessage({
    required this.icon,
    required this.title,
    required this.tint,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: tint),
          const SizedBox(height: 10),
          Text(title, style: MonokaiTheme.titleSmall),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(detail!,
                style: MonokaiTheme.labelSmall, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

class _AuditBody extends StatelessWidget {
  final RunTrace trace;
  const _AuditBody({required this.trace});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Totals(trace: trace),
        const SizedBox(height: 14),
        Text('Step audit',
            style:
                MonokaiTheme.labelLarge.copyWith(color: MonokaiTheme.comment)),
        const SizedBox(height: 6),
        for (final step in trace.steps)
          _StepRail(
            step: step,
            bottleneck: trace.bottleneckStepIndex == step.stepIndex,
          ),
      ],
    );
  }
}

/// The reconciled totals: the BILL first (asset-minute meter), then the
/// internal cost-of-goods, then the line that says which is which.
class _Totals extends StatelessWidget {
  final RunTrace trace;
  const _Totals({required this.trace});

  @override
  Widget build(BuildContext context) {
    final billedMin = trace.billedMinutesRollup;
    final billedCents = trace.billedCentsRollup;
    final wallMs = trace.wallMsRollup;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _metric('Billed-min',
                  billedMin == null ? '—' : fmtBilledMinutes(billedMin),
                  accent: MonokaiTheme.cyan),
              _metric('Billed \$',
                  billedCents == null ? '—' : fmtCents(billedCents),
                  accent: MonokaiTheme.green),
              _metric('Status', trace.status ?? '—'),
              _metric('Steps', '${trace.stepCount}'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _metric('Wall·int', wallMs > 0 ? fmtWallMs(wallMs) : '—'),
              _metric(
                  'GPU·int', '${trace.totalGpuSeconds.toStringAsFixed(2)}s'),
              _metric('Tokens·int', '${trace.tokensRollup}'),
              _metric('GPU \$·int', fmtCents(trace.totalPriceCents)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Bill = asset-minutes (top). GPU/tokens are internal COGS, never '
            'billed. Every figure sums from the per-step rows below.',
            style: MonokaiTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  static Widget _metric(String label, String value, {Color? accent}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: MonokaiTheme.codeStyle
                  .copyWith(color: accent ?? MonokaiTheme.foreground)),
          const SizedBox(height: 2),
          Text(label, style: MonokaiTheme.labelSmall),
        ],
      ),
    );
  }
}

/// One step rail — the provenance for a single step: what it did, what it
/// billed, what it burned internally, and the operational flags.
class _StepRail extends StatelessWidget {
  final RunStepDetail step;
  final bool bottleneck;

  const _StepRail({required this.step, required this.bottleneck});

  @override
  Widget build(BuildContext context) {
    final color = stepStatusColor(step.displayStatus);
    final exec = step.execMsComputed;
    final tokens = step.tokensTotal;
    final billed = _billedOf(step);

    return Container(
      key: ValueKey('audit-step-${step.stepIndex}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: MonokaiTheme.divider, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 22,
                child: Text('${step.stepIndex}',
                    textAlign: TextAlign.right,
                    style: MonokaiTheme.codeSmall
                        .copyWith(color: MonokaiTheme.comment)),
              ),
              const SizedBox(width: 10),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(step.action ?? step.stepId,
                    style: MonokaiTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (step.actor != null) ...[
                const SizedBox(width: 8),
                Text(step.actor!,
                    style: MonokaiTheme.labelSmall
                        .copyWith(color: MonokaiTheme.comment)),
              ],
              if (bottleneck) ...[
                const SizedBox(width: 8),
                const Icon(Icons.local_fire_department,
                    size: 11, color: MonokaiTheme.orange),
                const SizedBox(width: 3),
                Text('bottleneck',
                    style: MonokaiTheme.labelSmall
                        .copyWith(color: MonokaiTheme.orange)),
              ],
              const Spacer(),
              Text(step.displayStatus,
                  style: MonokaiTheme.labelSmall.copyWith(color: color)),
            ],
          ),
          const SizedBox(height: 4),
          // The audit columns: the BILL first, then internal COGS, then the
          // operational flags — so a billed minute is explainable per step.
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                _col(
                    'asset-min',
                    step.assetMinutes == null
                        ? '—'
                        : step.assetMinutes!.toStringAsFixed(1),
                    accent: MonokaiTheme.cyan),
                _col('billed', billed, accent: MonokaiTheme.green),
                _col('exec', exec == null ? '—' : fmtWallMs(exec)),
                _col(
                    'gpu·int',
                    step.gpuMs == null
                        ? '—'
                        : '${(step.gpuMs! / 1000.0).toStringAsFixed(2)}s'),
                _col('tokens·int',
                    tokens == null || tokens == 0 ? '—' : '$tokens'),
                _flags(step),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The asset-minute meter bill for a step: `$0.00` on a cache hit (billed 0),
  /// "—" when the lens has not metered it. NEVER the GPU cost.
  static String _billedOf(RunStepDetail step) {
    final cents = step.billedCents;
    if (cents != null) return fmtCents(cents);
    if (step.isCacheHit) return '\$0.00';
    return '—';
  }

  static Widget _col(String label, String value, {Color? accent}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: MonokaiTheme.codeSmall
                .copyWith(color: accent ?? MonokaiTheme.textSecondary)),
        Text(label, style: MonokaiTheme.labelSmall),
      ],
    );
  }

  /// cache ♻ (reused, billed 0) · retry ⟳ (re-processed, flagged) ·
  /// idempotent-skipped · the error class.
  static Widget _flags(RunStepDetail step) {
    final chips = <Widget>[
      if (step.isCacheHit) _chip('cache', MonokaiTheme.purple, Icons.cached),
      if (step.isRetry) _chip('retry', MonokaiTheme.orange, Icons.refresh),
      if (step.idempotentSkipped == true && !step.isCacheHit)
        _chip('idempotent-skipped', MonokaiTheme.purple, Icons.block),
      if (step.errorClass != null)
        _chip(step.errorClass!, MonokaiTheme.red, Icons.error_outline),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 2, children: chips);
  }

  static Widget _chip(String label, Color color, IconData icon) {
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

// ---------------------------------------------------------------------------
// Cost & usage — the run-scoped usage panel
// ---------------------------------------------------------------------------

/// What this run cost and what it consumed: spend (the asset-minute bill),
/// tokens in/out (internal COGS), what a cache hit saved, and the spend split
/// across the steps. Same records as the audit, so the two always agree.
class ParityUsageCostPanel extends ConsumerWidget {
  final String runId;

  const ParityUsageCostPanel({super.key, required this.runId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traceAsync = ref.watch(runTraceProvider(runId));

    return Container(
      key: const ValueKey('usage-cost-panel'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart,
                  size: 13, color: MonokaiTheme.comment),
              const SizedBox(width: 6),
              Text('Cost & usage',
                  style: MonokaiTheme.labelLarge
                      .copyWith(color: MonokaiTheme.comment)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: MonokaiTheme.cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('Run',
                    style: MonokaiTheme.labelSmall
                        .copyWith(color: MonokaiTheme.cyan)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          traceAsync.when(
            loading: () =>
                Text('Loading usage…', style: MonokaiTheme.labelSmall),
            error: (e, _) => Text('Usage unavailable: $e',
                style:
                    MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.red)),
            data: (trace) => trace == null
                ? Text('No usage recorded for this run yet.',
                    style: MonokaiTheme.labelSmall)
                : _UsageBody(trace: trace),
          ),
        ],
      ),
    );
  }
}

class _UsageBody extends StatelessWidget {
  final RunTrace trace;
  const _UsageBody({required this.trace});

  @override
  Widget build(BuildContext context) {
    final billedCents = trace.billedCentsRollup;
    final billedMin = trace.billedMinutesRollup;
    final saved = trace.savedMinutesRollup;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Spend — the bill, and only the bill.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _metric('Spend this run',
                billedCents == null ? '—' : fmtCents(billedCents),
                color: MonokaiTheme.green),
            _metric('Billed min',
                billedMin == null ? '—' : fmtBilledMinutes(billedMin),
                color: MonokaiTheme.cyan),
            // Rendered only when a step actually reused a result — never a
            // fabricated $0.00 saving.
            if (saved != null)
              _metric('Saved via cache', '${saved.toStringAsFixed(1)} min',
                  color: MonokaiTheme.purple,
                  detail: 'cached steps re-used a result — not billed'),
          ],
        ),
        const SizedBox(height: 12),
        // Tokens — internal COGS, labelled as such.
        Row(
          children: [
            _metric('Tokens in', '${trace.totalTokensIn}'),
            _metric('Tokens out', '${trace.totalTokensOut}'),
            _metric('Tokens total', '${trace.tokensRollup}'),
            _metric('GPU·int', '${trace.totalGpuSeconds.toStringAsFixed(2)}s'),
          ],
        ),
        const SizedBox(height: 12),
        Text('Spend by step', style: MonokaiTheme.labelSmall),
        const SizedBox(height: 6),
        _SpendBars(trace: trace),
      ],
    );
  }

  static Widget _metric(String label, String value,
      {Color? color, String? detail}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: MonokaiTheme.codeStyle
                  .copyWith(color: color ?? MonokaiTheme.foreground)),
          const SizedBox(height: 2),
          Text(label, style: MonokaiTheme.labelSmall),
          if (detail != null)
            Text(detail,
                style: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.comment)),
        ],
      ),
    );
  }
}

/// Per-step spend, scaled to the biggest billed step. A step that billed
/// nothing still gets a baseline bar so the rail reads as a full step list.
class _SpendBars extends StatelessWidget {
  final RunTrace trace;
  const _SpendBars({required this.trace});

  @override
  Widget build(BuildContext context) {
    final peak = trace.steps
        .map((s) => s.billedCents ?? 0)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final step in trace.steps)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 18,
                  height: peak <= 0
                      ? 2
                      : ((step.billedCents ?? 0) / peak * 40).clamp(2, 40),
                  decoration: BoxDecoration(
                    color: MonokaiTheme.cyan.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: 18,
                  child: Text('${step.stepIndex}',
                      textAlign: TextAlign.center,
                      style: MonokaiTheme.labelSmall
                          .copyWith(color: MonokaiTheme.comment)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
