// widgets/parity/parity_ops_efficiency.dart
//
// PARITY port of the SwiftUI `OperationsConsoleView` Efficiency face
// (PARITY_TRACKER row 8): five insight cards (gate bottleneck · failure
// hotspot · step speed · cache efficiency · retry burden) over a per-step
// table (runs · gate-p95 · fail · top error · exec-p95 · cache · saved ·
// retry).
//
// Driven ENTIRELY through the `CyanBackend` seam (via `efficiencyProvider`).
// This widget never touches `CyanFFI` directly — that is the parity rule.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';
import 'parity_ops_scaffold.dart';

class ParityOpsEfficiency extends ConsumerWidget {
  const ParityOpsEfficiency({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effAsync = ref.watch(efficiencyProvider);

    return OpsScaffold(
      face: OpsFace.efficiency,
      child: effAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MonokaiTheme.cyan),
        ),
        error: (e, _) => Center(
          child: Text('Failed to load efficiency: $e',
              style:
                  MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.red)),
        ),
        data: (eff) => _Body(eff: eff),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final EfficiencyReport eff;
  const _Body({required this.eff});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Icon(Icons.speed, size: 14, color: MonokaiTheme.cyan),
            const SizedBox(width: 8),
            Text('Efficiency — all boards (tenant)',
                style: MonokaiTheme.labelLarge),
          ],
        ),
        const SizedBox(height: 14),
        // Five insight cards.
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _InsightCard(
              icon: Icons.pan_tool,
              title: 'Gate bottleneck',
              value: _ms(eff.gateWaitP95Ms),
              detail: '${eff.gateBottleneckStep} · p95 wait',
              color: MonokaiTheme.yellow,
            ),
            _InsightCard(
              icon: Icons.warning_amber_rounded,
              title: 'Failure hotspot',
              value: '${eff.failureRatePct.toStringAsFixed(1)}%',
              detail:
                  '${eff.failureHotspotStep}${eff.topErrorClass != null ? ' · ${eff.topErrorClass}' : ''}',
              color:
                  eff.failureRatePct > 0 ? MonokaiTheme.red : MonokaiTheme.green,
            ),
            _InsightCard(
              icon: Icons.timer,
              title: 'Step speed (p95)',
              value: _ms(eff.slowestExecP95Ms),
              detail: 'slowest: ${eff.slowestStep}',
              color: MonokaiTheme.orange,
            ),
            _InsightCard(
              icon: Icons.cached,
              title: 'Cache efficiency',
              value: '${eff.cacheHitRatePct.toStringAsFixed(0)}%',
              detail: '${eff.minutesSaved.toStringAsFixed(1)} min saved',
              color: MonokaiTheme.purple,
            ),
            _InsightCard(
              icon: Icons.refresh,
              title: 'Retry burden',
              value: '${eff.retryRatePct.toStringAsFixed(1)}%',
              detail: 'of step-executions re-ran',
              color: MonokaiTheme.cyan,
            ),
          ],
        ),
        const SizedBox(height: 24),
        // Per-step table.
        Text('Per-step', style: MonokaiTheme.labelLarge),
        const SizedBox(height: 8),
        _StepTableHeader(),
        const Divider(height: 12, color: MonokaiTheme.divider),
        for (final s in eff.steps) _StepRow(step: s),
      ],
    );
  }

  static String _ms(double ms) =>
      ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)}s' : '${ms.toStringAsFixed(0)}ms';
}

class _InsightCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final Color color;

  const _InsightCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
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
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(title,
                    style: MonokaiTheme.labelMedium,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: MonokaiTheme.titleMedium.copyWith(color: color)),
          const SizedBox(height: 2),
          Text(detail,
              style: MonokaiTheme.labelSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _StepTableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _h('step', 140, TextAlign.left),
        _h('runs', 44, TextAlign.right),
        _h('gate-p95', 64, TextAlign.right),
        _h('fail', 44, TextAlign.right),
        _h('top error', 84, TextAlign.left),
        _h('exec-p95', 64, TextAlign.right),
        _h('cache', 48, TextAlign.right),
        _h('retry', 48, TextAlign.right),
      ],
    );
  }

  static Widget _h(String text, double width, TextAlign align) {
    return SizedBox(
      width: width,
      child: Text(text,
          textAlign: align,
          style: MonokaiTheme.codeSmall.copyWith(color: MonokaiTheme.comment)),
    );
  }
}

class _StepRow extends StatelessWidget {
  final StepEfficiency step;
  const _StepRow({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(step.step,
                style: MonokaiTheme.codeSmall
                    .copyWith(color: MonokaiTheme.foreground),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          _num('${step.runs}', 44, MonokaiTheme.foreground),
          _num(_ms(step.gateP95Ms), 64,
              step.gateP95Ms > 0 ? MonokaiTheme.yellow : MonokaiTheme.comment),
          _num('${step.failPct.toStringAsFixed(1)}%', 44,
              step.failPct > 0 ? MonokaiTheme.red : MonokaiTheme.comment),
          SizedBox(
            width: 84,
            child: Text(step.topError ?? '—',
                style: MonokaiTheme.codeSmall.copyWith(
                    color: step.topError != null
                        ? MonokaiTheme.red
                        : MonokaiTheme.comment),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          _num(_ms(step.execP95Ms), 64, MonokaiTheme.orange),
          _num('${step.cachePct.toStringAsFixed(0)}%', 48,
              step.cachePct > 0 ? MonokaiTheme.purple : MonokaiTheme.comment),
          _num('${step.retryPct.toStringAsFixed(1)}%', 48,
              step.retryPct > 0 ? MonokaiTheme.cyan : MonokaiTheme.comment),
        ],
      ),
    );
  }

  static String _ms(double ms) => ms <= 0
      ? '—'
      : ms >= 1000
          ? '${(ms / 1000).toStringAsFixed(1)}s'
          : '${ms.toStringAsFixed(0)}ms';

  static Widget _num(String text, double width, Color color) {
    return SizedBox(
      width: width,
      child: Text(text,
          textAlign: TextAlign.right,
          style: MonokaiTheme.codeSmall.copyWith(color: color)),
    );
  }
}
