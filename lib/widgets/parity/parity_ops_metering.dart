// widgets/parity/parity_ops_metering.dart
//
// PARITY port of the SwiftUI operations console's METERING spine — the
// `OperationsConsoleView` run board reduced to what an operator meters on, with
// the `RunAuditView` drill-down and the `UsageCostPanel` riding alongside it,
// under the W11 `TrialBanner` / locked-surface states.
//
// The face is one loop: LIST the tenant's runs with their terminal state →
// select one → read its per-step audit and its cost & usage. Because the audit
// and the cost panel are the lens's METERED surface, they sit behind the
// entitlement gate: once the trial's clock runs out they lock and the run list
// (a local read) keeps working — graceful expiry, exactly as the shipping app
// does it.
//
// Driven ENTIRELY through the `CyanBackend` seam (`engineOpsRunsProvider`,
// `runTraceProvider`, `entitlementProvider`). Note the lane: this spine's list
// and its drill-down are the SAME source — the engine — so a run in the list
// always has an audit behind it. The Ops console's own Runs face is on the
// lens lane (D3); the two are different questions and are not mixed. Row 26
// moves this spine's audit to `GET /runs/{id}`, and the list moves with it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';
import 'parity_run_audit.dart';
import 'parity_trial_banner.dart';

class ParityOpsMetering extends ConsumerStatefulWidget {
  /// The session tenant the grant must match; null ⇒ the grant's own.
  final String? tenant;

  /// Admin/Owner see the upgrade path on a lock.
  final bool isAdmin;

  /// Injected unix-seconds clock (tests); null ⇒ the wall clock.
  final int? nowSecs;

  /// The run selected on first build; null ⇒ the first run in the feed.
  final String? initialRunId;

  const ParityOpsMetering({
    super.key,
    this.tenant,
    this.isAdmin = false,
    this.nowSecs,
    this.initialRunId,
  });

  @override
  ConsumerState<ParityOpsMetering> createState() => _ParityOpsMeteringState();
}

class _ParityOpsMeteringState extends ConsumerState<ParityOpsMetering> {
  String? _selectedRunId;

  @override
  void initState() {
    super.initState();
    _selectedRunId = widget.initialRunId;
  }

  @override
  Widget build(BuildContext context) {
    final runsAsync = ref.watch(engineOpsRunsProvider);
    final entitlementAsync = ref.watch(entitlementProvider);

    // The gate is receive-only: until the cached grant resolves, nothing is
    // claimed to be locked (the metered panes simply have not loaded yet).
    final license = entitlementAsync.maybeWhen(
      data: (e) => buildLicense(e,
          tenant: widget.tenant,
          isAdmin: widget.isAdmin,
          nowSecs: widget.nowSecs),
      orElse: () => null,
    );
    final gate = license?.gate(PaidSurface.lensRun) ?? SurfaceGate.unlocked;

    return Material(
      color: MonokaiTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const Divider(height: 1, color: MonokaiTheme.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ParityTrialBanner(
              tenant: widget.tenant,
              isAdmin: widget.isAdmin,
              nowSecs: widget.nowSecs,
            ),
          ),
          Expanded(
            child: runsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: MonokaiTheme.cyan),
              ),
              error: (e, _) => Center(
                child: Text('Failed to load runs: $e',
                    style: MonokaiTheme.bodyMedium
                        .copyWith(color: MonokaiTheme.red)),
              ),
              data: (runs) => _body(runs, license, gate),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.speed, size: 18, color: MonokaiTheme.cyan),
          const SizedBox(width: 10),
          Text('Ops console', style: MonokaiTheme.titleSmall),
          const SizedBox(width: 8),
          Text('Metering',
              style:
                  MonokaiTheme.labelMedium.copyWith(color: MonokaiTheme.cyan)),
        ],
      ),
    );
  }

  Widget _body(List<OpsRun> runs, LicenseModel? license, SurfaceGate gate) {
    final selected = _resolveSelection(runs);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 340,
          child: _RunList(
            runs: runs,
            selectedRunId: selected,
            onSelect: (r) => setState(() => _selectedRunId = r.runId),
          ),
        ),
        const VerticalDivider(width: 1, color: MonokaiTheme.divider),
        Expanded(
          child: gate.locked
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ParityLockedSurfaceCard(
                      gate: gate,
                      seatSummary: license == null
                          ? null
                          : '${license.planName} · ${license.seatCap} seats',
                      onUpgrade: gate.showsUpgrade ? () {} : null,
                    ),
                  ),
                )
              : selected == null
                  ? Center(
                      child: Text('Select a run to audit it',
                          style: MonokaiTheme.labelMedium))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: ParityUsageCostPanel(runId: selected),
                        ),
                        Expanded(child: ParityRunAudit(runId: selected)),
                      ],
                    ),
        ),
      ],
    );
  }

  /// The selected run, falling back to the first in the feed. A selection that
  /// no longer exists in the feed falls back too, rather than blanking.
  String? _resolveSelection(List<OpsRun> runs) {
    if (runs.isEmpty) return null;
    final wanted = _selectedRunId;
    if (wanted != null && runs.any((r) => r.runId == wanted)) return wanted;
    return runs.first.runId;
  }
}

/// The run list: every run in the tenant with the state it settled in. A
/// TERMINAL run (Done / Failed) is the unit the lens invoices on, so the rail
/// says so explicitly instead of leaving the reader to infer it from a badge.
class _RunList extends StatelessWidget {
  final List<OpsRun> runs;
  final String? selectedRunId;
  final void Function(OpsRun run) onSelect;

  const _RunList({
    required this.runs,
    required this.selectedRunId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final terminal = runs.where((r) => r.status.isTerminal).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text('Runs', style: MonokaiTheme.labelLarge),
              const SizedBox(width: 6),
              Text('(${runs.length})',
                  style: MonokaiTheme.labelMedium
                      .copyWith(color: MonokaiTheme.comment)),
              const Spacer(),
              Text('$terminal terminal',
                  key: const ValueKey('ops-terminal-count'),
                  style: MonokaiTheme.labelSmall
                      .copyWith(color: MonokaiTheme.green)),
            ],
          ),
        ),
        Expanded(
          child: runs.isEmpty
              ? Center(
                  child: Text('No runs yet', style: MonokaiTheme.labelMedium))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: runs.length,
                  itemBuilder: (context, i) => _RunRow(
                    run: runs[i],
                    selected: runs[i].runId == selectedRunId,
                    onTap: () => onSelect(runs[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _RunRow extends StatelessWidget {
  final OpsRun run;
  final bool selected;
  final VoidCallback onTap;

  const _RunRow({
    required this.run,
    required this.selected,
    required this.onTap,
  });

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
    final terminalLabel = run.status.terminalLabel;

    return GestureDetector(
      key: ValueKey('ops-run-${run.runId}'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? MonokaiTheme.selection : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: _statusColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(run.asset,
                      style: MonokaiTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Text(run.status.label,
                    style:
                        MonokaiTheme.labelSmall.copyWith(color: _statusColor)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Text(run.workflow,
                      style: MonokaiTheme.labelSmall
                          .copyWith(color: MonokaiTheme.comment),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                // The terminal state: a settled run names the state it ended
                // in; a live one is explicitly still in flight, so nothing here
                // reads as a final outcome before it is one.
                if (terminalLabel != null)
                  Container(
                    key: ValueKey('ops-run-terminal-${run.runId}'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('terminal · $terminalLabel',
                        style: MonokaiTheme.labelSmall
                            .copyWith(color: _statusColor)),
                  )
                else
                  Text('in flight',
                      key: ValueKey('ops-run-live-${run.runId}'),
                      style: MonokaiTheme.labelSmall
                          .copyWith(color: MonokaiTheme.comment)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
