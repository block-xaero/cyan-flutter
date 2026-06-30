// widgets/parity/parity_workflow_view.dart
//
// PARITY port of the SwiftUI `WorkflowView` — the Board "Workflow (author)"
// face (PARITY_TRACKER row 3). A toolbar (Review/Run/Deploy/Reset), a list of
// numbered step cells with their compiled "inference" chips (tool / send-to /
// bound inputs / gate), and a composer to add a step.
//
// Driven ENTIRELY through the `CyanBackend` seam (via `boardWorkflowProvider`).
// This widget never touches `CyanFFI` directly — that is the parity rule.
//
// SwiftUI reference (read-only): cyan-iOS-ready/Cyan/Cyan/Views/WorkflowView.swift
//   - toolbar: Review (cyan wand) · Run (green play) · Deploy/Unlock (purple lock)
//     · Reset (muted)
//   - deployed boards show a purple "Deployed & locked" banner
//   - StepRow: numbered circle badge · step text · inference chips · gate chip
//   - composer: + icon · multiline field · "Add step" pill (cyan)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';

class ParityWorkflowView extends ConsumerWidget {
  final String boardId;

  /// Tapping Run — UI-only here; the execute path lands with Tier-2.
  final VoidCallback? onRun;

  /// Tapping Review/compile — UI-only here.
  final VoidCallback? onReview;

  const ParityWorkflowView({
    super.key,
    required this.boardId,
    this.onRun,
    this.onReview,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflowAsync = ref.watch(boardWorkflowProvider(boardId));

    return Material(
      color: MonokaiTheme.background,
      child: workflowAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MonokaiTheme.cyan),
        ),
        error: (e, _) => Center(
          child: Text('Failed to load workflow: $e',
              style:
                  MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.red)),
        ),
        data: (wf) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Toolbar(workflow: wf, onRun: onRun, onReview: onReview),
            if (wf.isDeployed) const _LockedBanner(),
            const Divider(height: 1, color: MonokaiTheme.divider),
            Expanded(
              child: wf.steps.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      itemCount: wf.steps.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) =>
                          _StepRow(index: i + 1, step: wf.steps[i]),
                    ),
            ),
            const Divider(height: 1, color: MonokaiTheme.divider),
            const _Composer(),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final Workflow workflow;
  final VoidCallback? onRun;
  final VoidCallback? onReview;

  const _Toolbar({required this.workflow, this.onRun, this.onReview});

  @override
  Widget build(BuildContext context) {
    final hasSteps = workflow.steps.isNotEmpty;
    final locked = workflow.isDeployed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.account_tree, size: 18, color: MonokaiTheme.cyan),
          const SizedBox(width: 10),
          Text('Workflow', style: MonokaiTheme.titleSmall),
          const Spacer(),
          _ToolButton(
            icon: Icons.auto_fix_high,
            label: 'Review',
            tint: MonokaiTheme.cyan,
            enabled: hasSteps && !locked,
            onTap: onReview,
          ),
          const SizedBox(width: 8),
          _ToolButton(
            icon: Icons.play_arrow,
            label: 'Run',
            tint: MonokaiTheme.green,
            enabled: hasSteps,
            onTap: onRun,
          ),
          const SizedBox(width: 8),
          _ToolButton(
            icon: locked ? Icons.lock_open : Icons.lock,
            label: locked ? 'Unlock' : 'Deploy',
            tint: MonokaiTheme.purple,
            enabled: hasSteps,
            onTap: null,
          ),
          const SizedBox(width: 8),
          _ToolButton(
            icon: Icons.refresh,
            label: 'Reset',
            tint: MonokaiTheme.textMuted,
            enabled: hasSteps && !locked,
            onTap: null,
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tint;
  final bool enabled;
  final VoidCallback? onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.tint,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? tint : MonokaiTheme.textDisabled;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(label,
                  style: MonokaiTheme.labelMedium.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedBanner extends StatelessWidget {
  const _LockedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: MonokaiTheme.purple.withValues(alpha: 0.1),
      child: Row(
        children: [
          const Icon(Icons.lock, size: 13, color: MonokaiTheme.purple),
          const SizedBox(width: 8),
          Text('Deployed & locked — unlock to edit steps',
              style: MonokaiTheme.labelMedium
                  .copyWith(color: MonokaiTheme.purple)),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int index;
  final WorkflowStep step;

  const _StepRow({required this.index, required this.step});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: step.isAmbiguous
              ? MonokaiTheme.orange.withValues(alpha: 0.6)
              : MonokaiTheme.border.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Numbered circle badge.
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: MonokaiTheme.selection,
                  shape: BoxShape.circle,
                ),
                child: Text('$index',
                    style: MonokaiTheme.codeSmall
                        .copyWith(color: MonokaiTheme.foreground)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(step.text,
                    style: MonokaiTheme.bodyMedium.copyWith(
                        color: MonokaiTheme.foreground,
                        fontWeight: FontWeight.w600)),
              ),
              const Icon(Icons.more_horiz,
                  size: 16, color: MonokaiTheme.textMuted),
            ],
          ),
          if (step.isAmbiguous) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 12, color: MonokaiTheme.orange),
                  const SizedBox(width: 6),
                  Text('Ambiguous — needs more detail to compile',
                      style: MonokaiTheme.labelSmall
                          .copyWith(color: MonokaiTheme.orange)),
                ],
              ),
            ),
          ],
          if (_hasChips(step)) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _chips(step),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static bool _hasChips(WorkflowStep s) =>
      s.tool != null ||
      s.destination != null ||
      s.boundInputs.isNotEmpty ||
      s.gate != null;

  static List<Widget> _chips(WorkflowStep s) {
    final out = <Widget>[];
    if (s.tool != null) {
      out.add(_chip(Icons.extension, s.tool!, MonokaiTheme.cyan));
    }
    for (final b in s.boundInputs) {
      out.add(_chip(Icons.tag, b, MonokaiTheme.green));
    }
    if (s.destination != null) {
      out.add(_chip(Icons.send, 'send to ${s.destination}', MonokaiTheme.purple));
    }
    switch (s.gate) {
      case StepGate.needsApproval:
        out.add(_chip(Icons.pan_tool, 'Awaiting approval', MonokaiTheme.yellow));
      case StepGate.noApproval:
        out.add(_chip(Icons.bolt, 'No approval needed', MonokaiTheme.green));
      case null:
        break;
    }
    return out;
  }

  static Widget _chip(IconData icon, String text, Color tint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: tint),
          const SizedBox(width: 4),
          Text(text, style: MonokaiTheme.labelSmall.copyWith(color: tint)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.list_alt,
              size: 56, color: MonokaiTheme.textDisabled),
          const SizedBox(height: 14),
          Text('No steps yet',
              style: MonokaiTheme.titleSmall
                  .copyWith(color: MonokaiTheme.textMuted)),
          const SizedBox(height: 6),
          Text('Add a step below to start authoring this workflow',
              style: MonokaiTheme.labelMedium),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MonokaiTheme.surface.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Icon(Icons.add_circle, size: 18, color: MonokaiTheme.cyan),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  maxLines: 3,
                  minLines: 1,
                  style: MonokaiTheme.bodyMedium
                      .copyWith(color: MonokaiTheme.foreground),
                  cursorColor: MonokaiTheme.cyan,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: MonokaiTheme.background,
                    hintText: 'Add step — e.g. "Transcode the master…"',
                    hintStyle: MonokaiTheme.bodyMedium
                        .copyWith(color: MonokaiTheme.textMuted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: MonokaiTheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: MonokaiTheme.border),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('@ plugin · # file · / action',
                    style: MonokaiTheme.labelSmall),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: MonokaiTheme.cyan,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Add step',
                style: MonokaiTheme.labelMedium
                    .copyWith(color: MonokaiTheme.background)),
          ),
        ],
      ),
    );
  }
}
