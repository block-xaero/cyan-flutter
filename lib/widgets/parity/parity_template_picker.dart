// widgets/parity/parity_template_picker.dart
//
// PARITY port of the SwiftUI `TemplatePickerSheet` — the Workflow face's
// template surface (STAGE face_templates_picker). Two sources, exactly as the
// engine keeps them: the tenant-agnostic BUILT-IN seeds and this tenant's own
// save-as-template results. Cloning one materializes real authorable step cells
// on THIS board; saving carries the board's current steps (and its standing
// notes) back out for reuse.
//
// Four things live here:
//   • LIST    — the catalog, sectioned by source, each row previewing the
//     pre-written English and the plugins the workflow names.
//   • CLONE   — through the seam, then the outcome POLLED back: how many step
//     cells landed and what the declared auto-install set did.
//   • REPORT  — the per-plugin auto-install outcome, with a FAILED plugin named
//     and the engine's reason quoted. A step bound to a plugin that never
//     landed only pends, so a silent failure would be a lie.
//   • SAVE    — the board's current workflow, saved as a tenant-scoped user
//     template through the FROM-BOARD verb so its standing notes travel too.
//
// Deliberate deviation from the Swift sheet: it offers Replace / Append /
// Cancel when the board already has steps. The `CyanBackend` seam carries no
// verb that REMOVES an authored step, so Replace cannot be honoured here — the
// clone appends and says so, rather than offering a choice it cannot keep.
//
// Driven ENTIRELY through the seam (via `templatesProvider` /
// `boardWorkflowProvider`); this widget never touches `CyanFFI` directly.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Views/TemplatePickerSheet.swift
//   cyan-iOS/Cyan/Cyan/ViewModels/TemplatesViewModel.swift

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../providers/templates_provider.dart';
import '../../theme/monokai_theme.dart';

class ParityTemplatePicker extends ConsumerStatefulWidget {
  /// The board a clone lands on — the whole address of this picker.
  final String boardId;

  /// The tenant whose saves list beside the seeds. Empty lets the picker derive
  /// it from the board's group through the seam, the way the engine does.
  final String tenantId;

  /// Fired after a clone reported back, so the host face re-reads its steps.
  final VoidCallback? onCloned;

  /// Tapping Done. The picker is a sheet on the Workflow face; the host owns
  /// dismissal.
  final VoidCallback? onClose;

  const ParityTemplatePicker({
    super.key,
    required this.boardId,
    this.tenantId = '',
    this.onCloned,
    this.onClose,
  });

  @override
  ConsumerState<ParityTemplatePicker> createState() =>
      _ParityTemplatePickerState();
}

class _ParityTemplatePickerState extends ConsumerState<ParityTemplatePicker> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();

  /// The row the operator has selected. Selection is cosmetic until Clone —
  /// nothing is cloned by merely landing on a row.
  String? _selectedId;

  TemplatesScope get _scope =>
      (boardId: widget.boardId, tenantId: widget.tenantId);

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _clone(CyanTemplate template) async {
    setState(() => _selectedId = template.id);
    final ok = await ref.read(templatesProvider(_scope).notifier).clone(
          template.id,
        );
    if (!mounted) return;
    // The clone materialized real cells on the board — re-read them off the
    // seam rather than assuming what landed.
    ref.invalidate(boardWorkflowProvider(widget.boardId));
    if (ok) widget.onCloned?.call();
  }

  Future<void> _save() async {
    final ok = await ref
        .read(templatesProvider(_scope).notifier)
        .saveBoardAsTemplate(_name.text, _description.text);
    if (!mounted || !ok) return;
    _name.clear();
    _description.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(templatesProvider(_scope));
    final workflowAsync = ref.watch(boardWorkflowProvider(widget.boardId));
    final boardSteps = workflowAsync.valueOrNull?.steps.length ?? 0;

    return Material(
      color: MonokaiTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          if (state.error != null) _errorBanner(state.error!),
          if (state.outcome != null)
            _CloneReport(
              templateName: state.clonedName,
              outcome: state.outcome!,
            ),
          const Divider(height: 1, color: MonokaiTheme.divider),
          Expanded(
            child: state.loading
                ? const Center(
                    child: CircularProgressIndicator(color: MonokaiTheme.cyan))
                : state.isEmpty
                    ? const _EmptyState()
                    : _list(state),
          ),
          const Divider(height: 1, color: MonokaiTheme.divider),
          _saveForm(state, boardSteps),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.grid_view, size: 18, color: MonokaiTheme.purple),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Workflow Templates', style: MonokaiTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'Clone a pre-written workflow into this board — its steps '
                  'land as real, editable step cells.',
                  style: MonokaiTheme.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            key: const ValueKey('templates.done'),
            onTap: widget.onClose,
            child: Text('Done',
                style: MonokaiTheme.labelMedium
                    .copyWith(color: MonokaiTheme.cyan)),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(String text) {
    return Container(
      key: const ValueKey('templates.error'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: MonokaiTheme.red.withValues(alpha: 0.10),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 12, color: MonokaiTheme.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style:
                    MonokaiTheme.labelMedium.copyWith(color: MonokaiTheme.red)),
          ),
          GestureDetector(
            key: const ValueKey('templates.error.dismiss'),
            onTap: () =>
                ref.read(templatesProvider(_scope).notifier).clearError(),
            child: const Icon(Icons.close,
                size: 12, color: MonokaiTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _list(TemplatesState state) {
    return ListView(
      key: const ValueKey('templates.list'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        if (state.builtins.isNotEmpty) ...[
          _sectionLabel('Built-in', const ValueKey('templates.section.builtin')),
          for (final t in state.builtins) _row(t),
        ],
        if (state.userTemplates.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionLabel(
              'Your templates', const ValueKey('templates.section.user')),
          for (final t in state.userTemplates) _row(t),
        ],
      ],
    );
  }

  Widget _sectionLabel(String text, Key key) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: MonokaiTheme.labelSmall
              .copyWith(color: MonokaiTheme.comment, letterSpacing: 0.6)),
    );
  }

  Widget _row(CyanTemplate template) {
    final selected = _selectedId == template.id;
    final cloning =
        ref.watch(templatesProvider(_scope)).cloningId == template.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setState(() => _selectedId = template.id),
        behavior: HitTestBehavior.opaque,
        child: Container(
          key: ValueKey('templates.row.${template.id}'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected
                ? MonokaiTheme.cyan.withValues(alpha: 0.10)
                : MonokaiTheme.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? MonokaiTheme.cyan.withValues(alpha: 0.5)
                  : MonokaiTheme.border.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    template.isBuiltin ? Icons.inventory_2 : Icons.person,
                    size: 13,
                    color: template.isBuiltin
                        ? MonokaiTheme.purple
                        : MonokaiTheme.green,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(template.name,
                            style: MonokaiTheme.labelLarge
                                .copyWith(color: MonokaiTheme.foreground)),
                        if (template.description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(template.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: MonokaiTheme.labelSmall),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _badge(
                    template.isBuiltin ? 'builtin' : 'yours',
                    template.isBuiltin
                        ? MonokaiTheme.purple
                        : MonokaiTheme.green,
                  ),
                  const SizedBox(width: 6),
                  _badge(
                    '${template.steps.length} step'
                    '${template.steps.length == 1 ? "" : "s"}',
                    MonokaiTheme.comment,
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    key: ValueKey('templates.clone.${template.id}'),
                    onTap: cloning ? null : () => _clone(template),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: MonokaiTheme.cyan.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.content_copy,
                              size: 11, color: MonokaiTheme.cyan),
                          const SizedBox(width: 5),
                          Text(cloning ? 'Cloning…' : 'Clone into this board',
                              style: MonokaiTheme.labelMedium
                                  .copyWith(color: MonokaiTheme.cyan)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 21),
                child: _stepPreview(template),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The pre-written English at a glance — the first three steps and the tools
  /// they bind, then a count of what is below the fold.
  Widget _stepPreview(CyanTemplate template) {
    final shown = template.steps.take(3).toList();
    final roadmap = [
      for (final p in template.plugins) if (p.status == 'roadmap') p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Text('${i + 1}.',
                    style: MonokaiTheme.codeSmall
                        .copyWith(color: MonokaiTheme.textMuted)),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(shown[i].text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MonokaiTheme.codeSmall
                          .copyWith(color: MonokaiTheme.comment)),
                ),
                if (shown[i].plugin != null) ...[
                  const SizedBox(width: 6),
                  Text('@${shown[i].plugin}',
                      style: MonokaiTheme.codeSmall
                          .copyWith(color: MonokaiTheme.orange)),
                ],
              ],
            ),
          ),
        if (template.steps.length > shown.length)
          Text('+ ${template.steps.length - shown.length} more',
              style: MonokaiTheme.labelSmall
                  .copyWith(color: MonokaiTheme.textMuted)),
        // Roadmap tools are DISPLAY only — visibly inactive, and nothing here
        // wires them to run. The engine's selector skips them at execution.
        if (roadmap.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final p in roadmap)
                Container(
                  key: ValueKey('templates.roadmap.${template.id}.${p.id}'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: MonokaiTheme.textMuted.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('@${p.id} · coming',
                      style: MonokaiTheme.labelSmall
                          .copyWith(color: MonokaiTheme.textMuted)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _badge(String text, Color tint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: MonokaiTheme.labelSmall.copyWith(color: tint)),
    );
  }

  Widget _saveForm(TemplatesState state, int boardSteps) {
    return Container(
      color: MonokaiTheme.surface.withValues(alpha: 0.4),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Save this workflow as a template',
              style: MonokaiTheme.labelLarge
                  .copyWith(color: MonokaiTheme.foreground)),
          if (state.saveConfirmation != null) ...[
            const SizedBox(height: 6),
            Row(
              key: const ValueKey('templates.save.confirmation'),
              children: [
                const Icon(Icons.check_circle,
                    size: 12, color: MonokaiTheme.green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(state.saveConfirmation!,
                      style: MonokaiTheme.labelMedium
                          .copyWith(color: MonokaiTheme.green)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _field(
                  key: const ValueKey('templates.save.name'),
                  controller: _name,
                  hint: 'Template name',
                  onSubmitted: (_) => _save(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _field(
                  key: const ValueKey('templates.save.description'),
                  controller: _description,
                  hint: 'Description (optional)',
                  onSubmitted: (_) => _save(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  boardSteps == 0
                      ? 'This board has no steps yet — author some first.'
                      : 'Saves this board\'s current $boardSteps step'
                          '${boardSteps == 1 ? "" : "s"} and its standing '
                          'notes for reuse in this group.',
                  style: MonokaiTheme.labelSmall,
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                key: const ValueKey('templates.save.confirm'),
                onTap: _save,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: MonokaiTheme.purple,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Save as template',
                      style: MonokaiTheme.labelMedium
                          .copyWith(color: MonokaiTheme.background)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onSubmitted,
  }) {
    return TextField(
      key: key,
      controller: controller,
      onSubmitted: onSubmitted,
      style: MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.foreground),
      cursorColor: MonokaiTheme.cyan,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: MonokaiTheme.background,
        hintText: hint,
        hintStyle:
            MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MonokaiTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MonokaiTheme.border),
        ),
      ),
    );
  }
}

/// What the clone did, as the ENGINE reported it: the step cells that landed,
/// and one row per declared plugin the auto-install touched. A failed plugin is
/// named with its reason — the steps bound to it will only PEND until it lands,
/// so pretending otherwise would strand the operator.
class _CloneReport extends StatelessWidget {
  final String? templateName;
  final TemplateCloneOutcome outcome;

  const _CloneReport({required this.templateName, required this.outcome});

  @override
  Widget build(BuildContext context) {
    final tint =
        outcome.hasFailedInstall ? MonokaiTheme.orange : MonokaiTheme.green;
    return Container(
      key: const ValueKey('templates.outcome'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      color: tint.withValues(alpha: 0.10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  outcome.hasFailedInstall
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle,
                  size: 12,
                  color: tint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(cloneReportLine(templateName, outcome),
                    style: MonokaiTheme.labelMedium.copyWith(color: tint)),
              ),
            ],
          ),
          if (outcome.pluginInstalls.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Plugin auto install', style: MonokaiTheme.labelSmall),
            const SizedBox(height: 3),
            for (final install in outcome.pluginInstalls)
              _installRow(install),
          ],
        ],
      ),
    );
  }

  Widget _installRow(TemplatePluginInstall install) {
    final failed = install.outcome == TemplatePluginInstallOutcome.failed;
    final tint = failed ? MonokaiTheme.red : MonokaiTheme.green;
    return Padding(
      key: ValueKey('templates.outcome.plugin.${install.pluginId}'),
      padding: const EdgeInsets.only(left: 20, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(failed ? Icons.close : Icons.done, size: 10, color: tint),
          const SizedBox(width: 6),
          Text('@${install.pluginId}',
              style: MonokaiTheme.codeSmall.copyWith(color: tint)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              install.reason == null
                  ? install.outcome.label
                  : '${install.outcome.label} — ${install.reason}',
              style: MonokaiTheme.labelSmall.copyWith(color: tint),
            ),
          ),
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
      key: const ValueKey('templates.empty'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.grid_view,
              size: 44, color: MonokaiTheme.textDisabled),
          const SizedBox(height: 12),
          Text('No templates',
              style: MonokaiTheme.titleSmall
                  .copyWith(color: MonokaiTheme.textMuted)),
          const SizedBox(height: 6),
          Text(
            'The built-in seeds surface here once the engine is ready — save '
            'this board\'s workflow below to make your own.',
            textAlign: TextAlign.center,
            style: MonokaiTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}
