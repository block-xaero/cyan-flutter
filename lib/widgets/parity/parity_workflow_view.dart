// widgets/parity/parity_workflow_view.dart
//
// PARITY port of the SwiftUI `WorkflowView` — the Board "Workflow (author)"
// face (PARITY_TRACKER row 3). The only authorable unit is the plain-English
// step: no cell-type picker, no markdown/mermaid/canvas affordances. The DAG is
// OUTPUT (the compile's preview), never an input.
//
// Four things live here:
//   • AUTHOR   — a composer that files a step through the seam, with the
//     `@ plugin · # file · / action` picker following the token at the caret.
//   • REVIEW   — the compile, which turns the authored English into a plan and
//     stamps each step's inference chips.
//   • PREVIEW  — the compiled DAG, laid out in dependency layers (the
//     `PipelinePreviewView` port), read back off the engine.
//   • PROMPT   — a step the compile could not resolve ASKS for a plugin rather
//     than having one guessed onto it.
//
// Driven ENTIRELY through the `CyanBackend` seam (via `boardWorkflowProvider` /
// `boardPipelineProvider`). This widget never touches `CyanFFI` directly — that
// is the parity rule.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Views/WorkflowView.swift
//   cyan-iOS/Cyan/Cyan/Views/PipelinePreviewView.swift
//   cyan-iOS/Cyan/Cyan/ViewModels/WorkflowViewModel.swift
//   cyan-iOS/Cyan/Cyan/ViewModels/NotebookViewModel+Pipeline.swift

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../providers/workflow_authoring_provider.dart';
import '../../theme/monokai_theme.dart';
import 'parity_sources_sheet.dart';
import 'parity_template_picker.dart';

/// The composer's own picker. Step rows key theirs by step id, so one field can
/// never steal another's dropdown.
const String _composerField = 'composer';

class ParityWorkflowView extends ConsumerStatefulWidget {
  final String boardId;

  /// Tapping Run. The run itself goes through the seam; this fires alongside so
  /// a host can follow the board to its Dashboard face.
  final VoidCallback? onRun;

  /// Tapping Review. The compile goes through the seam; this fires alongside.
  final VoidCallback? onReview;

  const ParityWorkflowView({
    super.key,
    required this.boardId,
    this.onRun,
    this.onReview,
  });

  @override
  ConsumerState<ParityWorkflowView> createState() => _ParityWorkflowViewState();
}

class _ParityWorkflowViewState extends ConsumerState<ParityWorkflowView> {
  final TextEditingController _draft = TextEditingController();

  /// The open autocomplete, or null when no trigger is active.
  _Picker? _picker;

  /// Guards the per-keystroke index read: a slow answer for an older keystroke
  /// must never replace the suggestions for the one the operator is on.
  int _pickerSeq = 0;

  /// The compile's preview is shown once a compile lands, and stays until the
  /// operator closes it.
  bool _showPlan = false;

  String? _status;
  String? _error;
  bool _busy = false;

  /// The board's autopilot mode as the ENGINE holds it. Starts at `off`, which
  /// is both the engine's default and the safe reading of "not yet asked" —
  /// every gate is still the operator's until something says otherwise.
  String _autopilot = 'off';

  @override
  void initState() {
    super.initState();
    _readAutopilot();
  }

  @override
  void didUpdateWidget(covariant ParityWorkflowView old) {
    super.didUpdateWidget(old);
    // Re-pointing the face at another board must not leave the previous
    // board's mode on the toolbar — the same keying bug row 16 found on Notes.
    if (old.boardId != widget.boardId) {
      setState(() => _autopilot = 'off');
      _readAutopilot();
    }
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _readAutopilot() async {
    final board = widget.boardId;
    final mode = await ref.read(cyanBackendProvider).autopilotMode(board);
    if (!mounted || board != widget.boardId) return;
    setState(() => _autopilot = mode);
  }

  /// Flip the mode, and show what the ENGINE answered rather than what was
  /// asked for. `setAutopilotMode` reads back, so a refused write leaves the
  /// toolbar telling the truth instead of claiming a delegation that never
  /// happened.
  Future<void> _setAutopilot(String mode) async {
    final board = widget.boardId;
    final settled =
        await ref.read(cyanBackendProvider).setAutopilotMode(board, mode);
    if (!mounted || board != widget.boardId) return;
    setState(() {
      _autopilot = settled;
      _error = settled == mode
          ? null
          : 'The engine kept autopilot on ${settled.toUpperCase()}.';
    });
  }

  // ---- authoring -----------------------------------------------------------

  Future<void> _addStep() async {
    if (_busy) return;
    final text = _draft.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Nothing to add — write the step first.');
      return;
    }
    setState(() => _busy = true);

    final backend = ref.read(cyanBackendProvider);
    final step = await backend.addWorkflowStep(widget.boardId, text);
    if (!mounted) return;
    // Read the step back off the seam rather than trusting the draft: what
    // lands on screen is what the engine kept.
    ref.invalidate(boardWorkflowProvider(widget.boardId));

    if (step == null) {
      setState(() {
        _busy = false;
        _error = 'The step was refused — nothing was filed.';
      });
      return;
    }
    _draft.clear();
    setState(() {
      _busy = false;
      _picker = null;
      _error = null;
      _status = 'Step added. Review to compile it into the plan.';
    });
  }

  /// Bind a plugin to an ambiguous step: the mention goes into the step's own
  /// English (that IS the binding — there is no side-channel), and the rewrite
  /// goes through the seam.
  Future<void> _bindStep(WorkflowStep step, AutocompleteEntry entry) async {
    final text = '${step.text.trimRight()} ${entry.trigger}${entry.value}';
    final backend = ref.read(cyanBackendProvider);
    final ok = await backend.updateWorkflowStep(widget.boardId, step.id, text);
    if (!mounted) return;
    ref.invalidate(boardWorkflowProvider(widget.boardId));
    setState(() {
      _picker = null;
      _error = ok ? null : 'That step could not be rewritten.';
      _status = ok ? 'Bound ${entry.trigger}${entry.value} to the step.' : null;
    });
  }

  // ---- compile / run -------------------------------------------------------

  Future<void> _review() async {
    widget.onReview?.call();
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Reviewing…';
    });

    final backend = ref.read(cyanBackendProvider);
    final ack = await backend.pipelineCompile(widget.boardId);
    if (!mounted) return;
    // The compile stamps each step's plan into its cell — re-read both the
    // steps and the DAG rather than drawing a plan this side invented.
    ref.invalidate(boardWorkflowProvider(widget.boardId));
    ref.invalidate(boardPipelineProvider(widget.boardId));
    setState(() {
      _busy = false;
      _showPlan = ack.accepted;
      _status = ack.accepted
          ? 'Compiled — the plan below is what a run would walk.'
          : null;
      _error = ack.accepted ? null : (ack.error ?? 'The compile was refused.');
    });
  }

  Future<void> _run() async {
    widget.onRun?.call();
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Running…';
    });

    final backend = ref.read(cyanBackendProvider);
    final ack = await backend.runPipeline(widget.boardId);
    if (!mounted) return;
    ref.invalidate(boardPipelineProvider(widget.boardId));
    setState(() {
      _busy = false;
      _status = ack.accepted ? 'Running — approve each gate to advance.' : null;
      _error = ack.accepted ? null : (ack.error ?? 'The run was refused.');
    });
  }

  // ---- templates -----------------------------------------------------------

  /// The template picker, presented the way Swift presents `TemplatePickerSheet`
  /// — from the Workflow face, over the board it clones onto. The board is
  /// re-read on dismissal because a clone materializes real step cells.
  Future<void> _openTemplates() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: MonokaiTheme.background,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        child: SizedBox(
          width: 560,
          height: 520,
          child: ParityTemplatePicker(
            boardId: widget.boardId,
            onCloned: () => setState(() {
              _status = 'Cloned — the template\'s steps are on this board.';
              _error = null;
            }),
            onClose: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      ),
    );
    if (!mounted) return;
    ref.invalidate(boardWorkflowProvider(widget.boardId));
  }

  // ---- sources (ingest) ----------------------------------------------------

  /// The watched-folder / S3 / Frame.io C2C sensors, presented the way Swift
  /// presents `SourcesSheet` — from the Workflow face, over the board whose
  /// template every ingested asset materializes a run of.
  ///
  /// This is the FIRST station of the spine: until a source is pointed at and
  /// scanned, no master is addressable and conform / colour / delivery have
  /// nothing to work on.
  ///
  /// The tenant is RESOLVED, never assumed. Every ingest verb carries the group
  /// boundary, so a board whose group cannot be read gets an error rather than
  /// a default tenant — pointing a sensor at the wrong group is worse than not
  /// opening the sheet.
  Future<void> _openSources() async {
    final boards = await ref.read(allBoardsProvider.future);
    if (!mounted) return;

    final entry = boards.where((b) => b.board.id == widget.boardId).firstOrNull;
    if (entry == null) {
      setState(() {
        _error = 'Cannot open Sources: this board has no group on the seam, '
            'and every ingest verb carries the tenant boundary.';
        _status = null;
      });
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: MonokaiTheme.background,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        child: SizedBox(
          width: 620,
          height: 560,
          child: ParitySourcesSheet(
            boardId: widget.boardId,
            tenantId: entry.group.id,
            onClose: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      ),
    );
  }

  Future<void> _reset() async {
    if (_busy) return;
    setState(() => _busy = true);
    final backend = ref.read(cyanBackendProvider);
    final ok = await backend.pipelineReset(widget.boardId);
    if (!mounted) return;
    ref.invalidate(boardPipelineProvider(widget.boardId));
    setState(() {
      _busy = false;
      _status = ok ? 'Reset — every step back to pending.' : null;
      _error = ok ? null : 'Reset was refused — nothing to rewind.';
    });
  }

  // ---- autocomplete (@ plugins · # artifacts · / actions) -------------------

  /// Recompute the composer's picker from the token AT THE CARET. Typing `@fra`
  /// in the middle of a pasted sentence must summon the picker for `@fra`, not
  /// for whatever token happens to sit at the end of the line.
  Future<void> _draftChanged(String text) async {
    final selection = _draft.selection;
    final cursor = selection.isValid ? selection.baseOffset : text.length;
    await _openPicker(field: _composerField, text: text, cursor: cursor);
  }

  Future<void> _openPicker({
    required String field,
    required String text,
    required int cursor,
  }) async {
    final token = _tokenAt(text, cursor);
    if (token == null) {
      if (_picker != null) setState(() => _picker = null);
      return;
    }
    final seq = ++_pickerSeq;
    final backend = ref.read(cyanBackendProvider);
    // The seam takes the text UP TO THE CARET — the engine owns which token is
    // active and what the vocabulary for it is; this side never filters.
    final index = await backend.workflowAutocomplete(
        widget.boardId, text.substring(0, token.cursor));
    if (!mounted || seq != _pickerSeq) return;
    setState(() {
      _picker = _Picker(
        field: field,
        trigger: token.trigger,
        tokenStart: token.start,
        cursor: token.cursor,
        // Exactly one list is populated for an active trigger; an empty one
        // means "nothing to offer for this trigger", not "nothing installed".
        suggestions: [
          ...index.plugins,
          ...index.artifacts,
          ...index.actions,
        ],
      );
    });
  }

  /// Arm a step row's picker with the whole `@` vocabulary — the ambiguity
  /// prompt's "pick a plugin", which is the same index the composer offers.
  Future<void> _pickPluginFor(WorkflowStep step) async {
    if (_picker?.field == step.id) {
      setState(() => _picker = null);
      return;
    }
    await _openPicker(field: step.id, text: '@', cursor: 1);
  }

  /// Splice `@value ` over the token being typed, at the caret. Mid-text
  /// acceptance must not jump the caret to the end of the field.
  void _acceptIntoComposer(AutocompleteEntry entry) {
    final picker = _picker;
    if (picker == null) return;
    final token = '${entry.trigger}${entry.value} ';
    final text = _draft.text;
    final start = picker.tokenStart.clamp(0, text.length);
    final end = picker.cursor.clamp(start, text.length);
    final spliced = text.replaceRange(start, end, token);
    _draft.value = TextEditingValue(
      text: spliced,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    setState(() => _picker = null);
  }

  /// The trigger token ending at [cursor]: the maximal non-whitespace run whose
  /// first character is a trigger. Port of Swift `detectToken(in:cursorUTF16:)`.
  static _Token? _tokenAt(String text, int cursor) {
    final end = cursor.clamp(0, text.length);
    var start = end;
    while (start > 0 && !_isSpace(text[start - 1])) {
      start--;
    }
    if (start >= end) return null;
    final trigger = text[start];
    if (trigger != '@' && trigger != '#' && trigger != '/') return null;
    return _Token(trigger: trigger, start: start, cursor: end);
  }

  static bool _isSpace(String ch) => ch.trim().isEmpty;

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final workflowAsync = ref.watch(boardWorkflowProvider(widget.boardId));

    return Material(
      color: MonokaiTheme.background,
      child: workflowAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MonokaiTheme.cyan),
        ),
        error: (e, _) => Center(
          child: Text('Failed to load workflow: $e',
              style: MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.red)),
        ),
        data: (wf) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Toolbar(
              workflow: wf,
              onRun: _run,
              onReview: _review,
              onReset: _reset,
              onTemplates: _openTemplates,
              onSources: _openSources,
              autopilotMode: _autopilot,
              onSetAutopilot: _setAutopilot,
            ),
            if (wf.isDeployed) const _LockedBanner(),
            if (_error != null)
              _StatusStrip(text: _error!, tint: MonokaiTheme.red)
            else if (_status != null)
              _StatusStrip(text: _status!, tint: MonokaiTheme.comment),
            if (_showPlan) _planPanel(),
            const Divider(height: 1, color: MonokaiTheme.divider),
            Expanded(
              child: wf.steps.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      itemCount: wf.steps.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final step = wf.steps[i];
                        return _StepRow(
                          index: i + 1,
                          step: step,
                          picker: _picker?.field == step.id ? _picker : null,
                          onPickPlugin: () => _pickPluginFor(step),
                          onAccept: (entry) => _bindStep(step, entry),
                        );
                      },
                    ),
            ),
            const Divider(height: 1, color: MonokaiTheme.divider),
            _composer(),
          ],
        ),
      ),
    );
  }

  /// The compiled plan, read back off the engine. Height-capped: the plan is a
  /// reference while authoring, not the face.
  Widget _planPanel() {
    final planAsync = ref.watch(boardPipelineProvider(widget.boardId));
    return SizedBox(
      height: 260,
      child: planAsync.when(
        loading: () => const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: MonokaiTheme.cyan),
          ),
        ),
        error: (e, _) => Center(
          child: Text('Failed to read the plan: $e',
              style:
                  MonokaiTheme.labelMedium.copyWith(color: MonokaiTheme.red)),
        ),
        data: (plan) => _PlanPreview(
          plan: plan,
          onClose: () => setState(() => _showPlan = false),
        ),
      ),
    );
  }

  Widget _composer() {
    final picker = _picker?.field == _composerField ? _picker : null;
    return Container(
      color: MonokaiTheme.surface.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (picker != null)
            _AutocompletePanel(picker: picker, onAccept: _acceptIntoComposer),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Icon(Icons.add_circle,
                      size: 18, color: MonokaiTheme.cyan),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        key: const ValueKey('workflow.composer.field'),
                        controller: _draft,
                        maxLines: 3,
                        minLines: 1,
                        onChanged: _draftChanged,
                        onSubmitted: (_) => _addStep(),
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
                GestureDetector(
                  key: const ValueKey('workflow.composer.add'),
                  onTap: _addStep,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: MonokaiTheme.cyan,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Add step',
                        style: MonokaiTheme.labelMedium
                            .copyWith(color: MonokaiTheme.background)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A trigger token at the caret.
class _Token {
  final String trigger;
  final int start;
  final int cursor;

  const _Token({
    required this.trigger,
    required this.start,
    required this.cursor,
  });
}

/// The open autocomplete, scoped to the field that owns it.
class _Picker {
  /// `_composerField`, or the id of the step row that armed it.
  final String field;
  final String trigger;
  final int tokenStart;
  final int cursor;
  final List<AutocompleteEntry> suggestions;

  const _Picker({
    required this.field,
    required this.trigger,
    required this.tokenStart,
    required this.cursor,
    required this.suggestions,
  });
}

/// The dropdown. Renders even when the index answers with NOTHING: a silent
/// popover makes a dead plugin index look like broken autocomplete.
class _AutocompletePanel extends StatelessWidget {
  final _Picker picker;
  final void Function(AutocompleteEntry) onAccept;

  const _AutocompletePanel({required this.picker, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    final rows = picker.suggestions.take(6).toList();
    return Container(
      decoration: BoxDecoration(
        color: MonokaiTheme.surfaceLight,
        border: const Border(
          top: BorderSide(color: MonokaiTheme.divider),
          bottom: BorderSide(color: MonokaiTheme.divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rows.isEmpty) _empty(),
          for (final entry in rows)
            GestureDetector(
              key: ValueKey('workflow.autocomplete.row.${entry.value}'),
              onTap: () => onAccept(entry),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                child: Row(
                  children: [
                    Text(entry.trigger,
                        style: MonokaiTheme.codeSmall
                            .copyWith(color: MonokaiTheme.cyan)),
                    const SizedBox(width: 8),
                    Text(entry.value,
                        style: MonokaiTheme.labelMedium
                            .copyWith(color: MonokaiTheme.foreground)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(entry.label,
                          overflow: TextOverflow.ellipsis,
                          style: MonokaiTheme.labelSmall),
                    ),
                    Text(entry.kind,
                        style: MonokaiTheme.labelSmall
                            .copyWith(color: MonokaiTheme.textMuted)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty() {
    final text = switch (picker.trigger) {
      '@' =>
        'No plugins installed in this group — install one from the Market face.',
      '#' =>
        'No files on this board yet — attach one, or run a step that makes one.',
      _ => 'No matching /action.',
    };
    return Padding(
      key: const ValueKey('workflow.autocomplete.empty'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 12, color: MonokaiTheme.comment),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: MonokaiTheme.labelSmall)),
        ],
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  final String text;
  final Color tint;

  const _StatusStrip({required this.text, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      color: tint.withValues(alpha: 0.10),
      child: Row(
        children: [
          Icon(
              tint == MonokaiTheme.red
                  ? Icons.error_outline
                  : Icons.info_outline,
              size: 12,
              color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: MonokaiTheme.labelMedium.copyWith(color: tint)),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final Workflow workflow;
  final VoidCallback? onRun;
  final VoidCallback? onReview;
  final VoidCallback? onReset;

  /// Opens the template picker. Always enabled: a board with NO steps is
  /// exactly the board a template is for.
  final VoidCallback? onTemplates;

  /// The board's autopilot mode as the ENGINE holds it, and the setter.
  final String autopilotMode;
  final void Function(String mode)? onSetAutopilot;

  /// Opening the ingest sensors — the spine's first station.
  final VoidCallback? onSources;

  const _Toolbar({
    required this.workflow,
    this.onRun,
    this.onReview,
    this.onReset,
    this.onTemplates,
    this.onSources,
    this.autopilotMode = 'off',
    this.onSetAutopilot,
  });

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
          const SizedBox(width: 16),
          // The action cluster SCROLLS rather than clips. Seven controls do not
          // fit a narrow window, and a toolbar that throws a RenderFlex — or
          // silently hides Deploy behind the edge — is worse than one the
          // operator can nudge. `reverse` keeps it right-aligned like the
          // Spacer it replaced, so the rightmost actions are the ones always in
          // view.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _ToolButton(
                  key: const ValueKey('workflow.sources'),
                  icon: Icons.sensors,
                  label: 'Sources',
                  tint: MonokaiTheme.orange,
                  // Ingest is how work ARRIVES, so it stays reachable on a board with
                  // no steps yet — and on a deployed one, where new media still has
                  // to materialize runs.
                  enabled: true,
                  onTap: onSources,
                ),
                const SizedBox(width: 8),
                _ToolButton(
                  key: const ValueKey('workflow.templates'),
                  icon: Icons.grid_view,
                  label: 'Templates',
                  tint: MonokaiTheme.purple,
                  enabled: !locked,
                  onTap: onTemplates,
                ),
                const SizedBox(width: 8),
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
                _AutopilotControl(mode: autopilotMode, onSet: onSetAutopilot),
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
                  onTap: onReset,
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// AUTOPILOT (design §1) — the per-board mode, beside Run.
///
/// Flipping to AUTOPILOT is the human ADOPTION act: the policy card starts
/// clearing gates, and every clearance is stamped `policy:<card>` so the
/// Dashboard can say who really decided. Flipping back is the KILL SWITCH.
/// The label always shows the mode the ENGINE holds — never the one that was
/// tapped — because a toolbar reading AUTOPILOT over a board still gating on
/// humans is precisely the lie this control exists to prevent.
class _AutopilotControl extends StatelessWidget {
  final String mode;
  final void Function(String mode)? onSet;

  const _AutopilotControl({required this.mode, this.onSet});

  /// The engine's vocabulary (`autopilot::set_mode`), in escalation order.
  static const List<String> modes = ['off', 'assist', 'autopilot'];

  static const String help = 'Autopilot: OFF = every gate human · '
      'ASSIST = earned classes only · '
      'AUTOPILOT = policy clears gates, you get digests + this kill switch';

  Color get _tint => switch (mode) {
        'autopilot' => MonokaiTheme.purple,
        'assist' => MonokaiTheme.orange,
        _ => MonokaiTheme.comment,
      };

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: help,
      child: PopupMenuButton<String>(
        key: const ValueKey('workflow.autopilot'),
        tooltip: '',
        enabled: onSet != null,
        onSelected: (m) => onSet?.call(m),
        color: MonokaiTheme.surfaceLighter,
        itemBuilder: (_) => [
          for (final m in modes)
            PopupMenuItem<String>(
              key: ValueKey('workflow.autopilot.$m'),
              value: m,
              child: Row(
                children: [
                  Text(m.toUpperCase(), style: MonokaiTheme.labelMedium),
                  const Spacer(),
                  if (m == mode)
                    const Icon(Icons.check,
                        size: 12, color: MonokaiTheme.green),
                ],
              ),
            ),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                mode == 'autopilot'
                    ? Icons.airplanemode_active
                    : Icons.airplanemode_inactive,
                size: 14,
                color: _tint),
            const SizedBox(width: 4),
            Text(mode == 'off' ? 'Autopilot' : mode.toUpperCase(),
                style: MonokaiTheme.labelMedium.copyWith(color: _tint)),
          ],
        ),
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
    super.key,
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

  /// This row's own picker (the ambiguity prompt's plugin list), or null.
  final _Picker? picker;
  final VoidCallback onPickPlugin;
  final void Function(AutocompleteEntry) onAccept;

  const _StepRow({
    required this.index,
    required this.step,
    required this.picker,
    required this.onPickPlugin,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('workflow.step.${step.id}'),
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
            _AmbiguityPrompt(
              step: step,
              picker: picker,
              onPickPlugin: onPickPlugin,
              onAccept: onAccept,
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
      out.add(_chip(Icons.extension, s.tool!, MonokaiTheme.cyan,
          key: ValueKey('workflow.step.tool.${s.id}')));
    }
    for (final b in s.boundInputs) {
      out.add(_chip(Icons.tag, b, MonokaiTheme.green));
    }
    if (s.destination != null) {
      out.add(
          _chip(Icons.send, 'send to ${s.destination}', MonokaiTheme.purple));
    }
    switch (s.gate) {
      case StepGate.needsApproval:
        out.add(
            _chip(Icons.pan_tool, 'Awaiting approval', MonokaiTheme.yellow));
      case StepGate.noApproval:
        out.add(_chip(Icons.bolt, 'No approval needed', MonokaiTheme.green));
      case null:
        break;
    }
    return out;
  }

  static Widget _chip(IconData icon, String text, Color tint, {Key? key}) {
    return Container(
      key: key,
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

/// A step the compile could not resolve. It ASKS — it never has a tool guessed
/// onto it, because a wrong tool runs and a missing one only waits.
class _AmbiguityPrompt extends StatelessWidget {
  final WorkflowStep step;
  final _Picker? picker;
  final VoidCallback onPickPlugin;
  final void Function(AutocompleteEntry) onAccept;

  const _AmbiguityPrompt({
    required this.step,
    required this.picker,
    required this.onPickPlugin,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 12, color: MonokaiTheme.orange),
              const SizedBox(width: 6),
              Text('Ambiguous — nothing was inferred for this step',
                  style: MonokaiTheme.labelSmall
                      .copyWith(color: MonokaiTheme.orange)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "Couldn't infer a tool for this step — add detail, or pick a "
            'plugin with @.',
            style: MonokaiTheme.labelSmall
                .copyWith(color: MonokaiTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            key: ValueKey('workflow.step.pickPlugin.${step.id}'),
            onTap: onPickPlugin,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: MonokaiTheme.orange.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: MonokaiTheme.orange.withValues(alpha: 0.4)),
              ),
              child: Text('Pick a plugin',
                  style: MonokaiTheme.labelMedium
                      .copyWith(color: MonokaiTheme.orange)),
            ),
          ),
          if (picker != null) ...[
            const SizedBox(height: 6),
            _AutocompletePanel(picker: picker!, onAccept: onAccept),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The compiled plan — SwiftUI `PipelinePreviewView` parity
// ---------------------------------------------------------------------------

/// The compiled DAG in dependency layers: layer 0 is everything that depends on
/// nothing, and each layer after it is everything whose dependencies have all
/// landed. Port of `PipelinePreviewView.computeLayers()`.
class _PlanPreview extends StatelessWidget {
  final PipelineStatus plan;
  final VoidCallback onClose;

  const _PlanPreview({required this.plan, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final steps = plan.steps;
    final ordinal = <String, int>{
      for (var i = 0; i < steps.length; i++) steps[i].stepId: i + 1,
    };
    final layers = _layers(steps);

    return Container(
      color: MonokaiTheme.surface.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.hub, size: 14, color: MonokaiTheme.cyan),
                const SizedBox(width: 8),
                Text('Compiled plan',
                    style: MonokaiTheme.labelLarge
                        .copyWith(color: MonokaiTheme.foreground)),
                const SizedBox(width: 10),
                Text('${steps.length} steps · ${layers.length} stages',
                    style: MonokaiTheme.labelSmall),
                const Spacer(),
                GestureDetector(
                  key: const ValueKey('workflow.dag.close'),
                  onTap: onClose,
                  child: const Icon(Icons.close,
                      size: 14, color: MonokaiTheme.textMuted),
                ),
              ],
            ),
          ),
          Expanded(
            child: steps.isEmpty
                ? Center(
                    child: Text('Nothing compiled yet',
                        style: MonokaiTheme.labelMedium),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Column(
                      children: [
                        for (var i = 0; i < layers.length; i++) ...[
                          if (i > 0)
                            _Connectors(from: layers[i - 1], to: layers[i]),
                          Row(
                            key: ValueKey('workflow.dag.layer.$i'),
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final step in layers[i])
                                Flexible(
                                  child: _PlanNode(
                                    step: step,
                                    ordinal: ordinal[step.stepId] ?? 0,
                                    dependsOn: [
                                      for (final d in step.dependsOn)
                                        ordinal[d] ?? 0,
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static List<List<PipelineStep>> _layers(List<PipelineStep> steps) {
    final layers = <List<PipelineStep>>[];
    final assigned = <String>{};
    var current = [
      for (final s in steps)
        if (s.dependsOn.isEmpty) s
    ];

    while (current.isNotEmpty) {
      layers.add(current);
      assigned.addAll(current.map((s) => s.stepId));
      current = [
        for (final s in steps)
          if (!assigned.contains(s.stepId) &&
              s.dependsOn.every(assigned.contains))
            s,
      ];
    }
    // Anything left is a cycle or an orphan — shown, never dropped.
    final remaining = [
      for (final s in steps)
        if (!assigned.contains(s.stepId)) s,
    ];
    if (remaining.isNotEmpty) layers.add(remaining);
    return layers;
  }
}

class _PlanNode extends StatelessWidget {
  final PipelineStep step;
  final int ordinal;
  final List<int> dependsOn;

  const _PlanNode({
    required this.step,
    required this.ordinal,
    required this.dependsOn,
  });

  @override
  Widget build(BuildContext context) {
    final tint = switch (step.executor) {
      'local' => MonokaiTheme.cyan,
      'cloud' => MonokaiTheme.purple,
      'manual' => MonokaiTheme.orange,
      _ => MonokaiTheme.green,
    };
    return Container(
      key: ValueKey('workflow.dag.node.${step.stepId}'),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tint.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$ordinal',
                  style: MonokaiTheme.codeSmall.copyWith(color: tint)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(step.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MonokaiTheme.labelMedium
                        .copyWith(color: MonokaiTheme.foreground)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            dependsOn.isEmpty
                ? '${step.executor} · starts the run'
                : '${step.executor} · after step ${dependsOn.join(", ")}',
            style: MonokaiTheme.labelSmall.copyWith(color: tint),
          ),
        ],
      ),
    );
  }
}

/// The dashed edges between two layers, drawn from each dependent back to the
/// step it waits on — the same curve `PipelinePreviewView.connectorLines` draws.
class _Connectors extends StatelessWidget {
  final List<PipelineStep> from;
  final List<PipelineStep> to;

  const _Connectors({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: CustomPaint(
        painter: _ConnectorPainter(from: from, to: to),
        size: Size.infinite,
      ),
    );
  }
}

class _ConnectorPainter extends CustomPainter {
  final List<PipelineStep> from;
  final List<PipelineStep> to;

  const _ConnectorPainter({required this.from, required this.to});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MonokaiTheme.comment
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (var t = 0; t < to.length; t++) {
      for (final dep in to[t].dependsOn) {
        final f = from.indexWhere((s) => s.stepId == dep);
        if (f < 0) continue;
        final fromX = size.width / (from.length + 1) * (f + 1);
        final toX = size.width / (to.length + 1) * (t + 1);
        final path = Path()
          ..moveTo(fromX, 0)
          ..cubicTo(fromX, size.height * 0.5, toX, size.height * 0.5, toX,
              size.height);
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ConnectorPainter old) => old.from != from || old.to != to;
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
