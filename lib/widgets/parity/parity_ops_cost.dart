// widgets/parity/parity_ops_cost.dart
//
// PARITY port of the SwiftUI `OperationsConsoleView` Cost face (PARITY_TRACKER
// row 7): the asset-minute meter. A five-stat headline (billed-min · billed $ ·
// retry-min · saved-min · runs), the internal-COGS footnote (GPU = COGS:
// margin, not billed), and the per-workflow reconcile table.
//
// Driven ENTIRELY through the `LensApi` seam (via `costMeterProvider`, which is
// a §4 rollup over the ONE `/api/v1/runs` feed the Runs face already reads).
// This widget never touches HTTP or `CyanFFI` directly — that is the parity
// rule, and D4 keeps the two seams apart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/lens_console_provider.dart';
import '../../theme/monokai_theme.dart';
import 'parity_ops_scaffold.dart';

class ParityOpsCost extends ConsumerWidget {
  /// Turning the console's segmented control. Null leaves the header inert,
  /// which is right when this face is mounted on its own.
  final void Function(OpsFace)? onSelectFace;

  const ParityOpsCost({super.key, this.onSelectFace});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meterAsync = ref.watch(costMeterProvider);

    return OpsScaffold(
      face: OpsFace.cost,
      onSelectFace: onSelectFace,
      child: meterAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MonokaiTheme.cyan),
        ),
        error: (e, _) => Center(
          child: Text('Failed to load cost meter: $e',
              style: MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.red)),
        ),
        data: (meter) => _Body(meter: meter),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final CostMeter meter;
  const _Body({required this.meter});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Scope header.
        Row(
          children: [
            const Icon(Icons.timer, size: 14, color: MonokaiTheme.cyan),
            const SizedBox(width: 8),
            Text('Asset-minute meter — all boards (tenant)',
                style: MonokaiTheme.labelLarge),
            const Spacer(),
            if (!meter.hasMeter)
              Text('awaiting lens meter',
                  style: MonokaiTheme.labelMedium
                      .copyWith(color: MonokaiTheme.yellow)),
          ],
        ),
        const SizedBox(height: 14),
        // Five-stat headline.
        Row(
          children: [
            _stat('billed-min', meter.billedMinutes.toStringAsFixed(1),
                MonokaiTheme.cyan),
            _stat('billed \$', '\$${meter.billedDollars.toStringAsFixed(2)}',
                MonokaiTheme.green),
            _stat('retry-min', meter.retryMinutes.toStringAsFixed(1),
                MonokaiTheme.orange),
            _stat('saved-min', meter.savedMinutes.toStringAsFixed(1),
                MonokaiTheme.purple),
            _stat('runs', '${meter.runs}', MonokaiTheme.foreground),
          ],
        ),
        const SizedBox(height: 10),
        // COGS footnote — GPU = COGS, margin not billed.
        Row(
          children: [
            const Icon(Icons.memory, size: 11, color: MonokaiTheme.comment),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'internal COGS (margin, not billed): '
                '${meter.computeMinutes.toStringAsFixed(1)} compute-min · '
                '${meter.gpuSeconds.toStringAsFixed(0)} gpu-sec',
                style: MonokaiTheme.labelSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        // Per-workflow reconcile table.
        Text('Per-workflow', style: MonokaiTheme.labelLarge),
        const SizedBox(height: 8),
        _TableHeader(),
        const Divider(height: 12, color: MonokaiTheme.divider),
        for (final w in meter.perWorkflow) _WorkflowRow(cost: w),
      ],
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: MonokaiTheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: MonokaiTheme.titleMedium.copyWith(color: color)),
            const SizedBox(height: 2),
            Text(label, style: MonokaiTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _cell('workflow', 160, MonokaiTheme.comment, align: TextAlign.left),
        _cell('runs', 48, MonokaiTheme.comment),
        _cell('assets', 56, MonokaiTheme.comment),
        _cell('billed-min', 80, MonokaiTheme.comment),
        _cell('billed \$', 70, MonokaiTheme.comment),
        _cell('retry-min', 72, MonokaiTheme.comment),
      ],
    );
  }

  static Widget _cell(String text, double width, Color color,
      {TextAlign align = TextAlign.right}) {
    return SizedBox(
      width: width,
      child: Text(text,
          textAlign: align,
          style: MonokaiTheme.codeSmall.copyWith(color: color)),
    );
  }
}

class _WorkflowRow extends StatelessWidget {
  final WorkflowCost cost;
  const _WorkflowRow({required this.cost});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(cost.workflow,
                style: MonokaiTheme.codeSmall
                    .copyWith(color: MonokaiTheme.foreground),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          _num('${cost.runs}', 48, MonokaiTheme.foreground),
          _num('${cost.assets}', 56, MonokaiTheme.foreground),
          _num(cost.billedMinutes.toStringAsFixed(1), 80, MonokaiTheme.cyan),
          _num('\$${cost.billedDollars.toStringAsFixed(2)}', 70,
              MonokaiTheme.green),
          _num(
              cost.retryMinutes.toStringAsFixed(1),
              72,
              cost.retryMinutes > 0
                  ? MonokaiTheme.orange
                  : MonokaiTheme.comment),
        ],
      ),
    );
  }

  static Widget _num(String text, double width, Color color) {
    return SizedBox(
      width: width,
      child: Text(text,
          textAlign: TextAlign.right,
          style: MonokaiTheme.codeSmall.copyWith(color: color)),
    );
  }
}
