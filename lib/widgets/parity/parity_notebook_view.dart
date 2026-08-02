// widgets/parity/parity_notebook_view.dart
//
// PARITY port of the SwiftUI notebook document — the cell ledger a board keeps
// (`cyan_load_notebook_cells`) and the cell renderers that draw it.
//
// The board's cells are ONE ledger read two ways: the Workflow face takes its
// authored steps out of it, and this face draws the whole document — the step
// cells with the tool a compile bound to them, the markdown around them, the
// code that ran, the images it produced, and the compiled DAG as a diagram.
//
// Four things live here:
//   • STEP CELLS — authored English plus its BOUND tool. A step nothing has
//     compiled shows no tool, because naming a plugin with `@` is a request and
//     binding one is the compile's answer.
//   • THE PICKER — `@` offers the group's plugins, `#` the board's artifacts,
//     `/` the controlled verbs. The vocabulary is the ENGINE's
//     (`cyan_workflow_autocomplete`); this side never invents an entry.
//   • THE DIAGRAM — a mermaid cell is drawn as a DIAGRAM (nodes in dependency
//     layers, edges between them), not as its source. The compile writes one
//     from the plan it kept, so the picture and the run can never disagree.
//   • CODE + IMAGE cells — a code cell shows its source and what the last run
//     printed; an image cell shows its pixels, or names the file when the bytes
//     are not here.
//
// Driven ENTIRELY through the `CyanBackend` seam (`boardNotebookProvider`).
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Views/Components/NotebookCellContainer.swift
//   cyan-iOS/Cyan/Cyan/Views/MarkdownCellView.swift
//   cyan-iOS/Cyan/Cyan/Views/Components/CodeCellView.swift
//   cyan-iOS/Cyan/Cyan/Views/Components/ImageCellView.swift
//   cyan-iOS/Cyan/Cyan/Views/Components/MermaidCellView.swift
//   cyan-iOS/Cyan/Cyan/ViewModels/NotebookViewModel.swift

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../providers/notebook_provider.dart';
import '../../providers/workflow_authoring_provider.dart';
import '../../theme/monokai_theme.dart';

class ParityNotebookView extends ConsumerStatefulWidget {
  final String boardId;

  const ParityNotebookView({super.key, required this.boardId});

  @override
  ConsumerState<ParityNotebookView> createState() => _ParityNotebookViewState();
}

class _ParityNotebookViewState extends ConsumerState<ParityNotebookView> {
  final TextEditingController _draft = TextEditingController();

  /// The open autocomplete, or null when no trigger is active at the caret.
  _Picker? _picker;

  /// Guards the per-keystroke index read: a slow answer for an older keystroke
  /// must never replace the suggestions for the one being typed.
  int _pickerSeq = 0;

  /// Cells the operator has folded away, by id.
  final Set<String> _collapsed = {};

  String? _status;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  // ---- authoring -----------------------------------------------------------

  /// File a step cell into the document. It goes through the SAME seam verb the
  /// Workflow face authors with — one ledger, so a step filed here is a step
  /// there — and the document is then re-READ rather than patched locally.
  Future<void> _addStep() async {
    if (_busy) return;
    final text = _draft.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Nothing to add — write the step first.');
      return;
    }
    setState(() => _busy = true);

    final backend = ref.read(cyanBackendProvider);
    final cell = await backend.addWorkflowStep(widget.boardId, text);
    if (!mounted) return;
    _reload();

    if (cell == null) {
      setState(() {
        _busy = false;
        _error = 'The cell was refused — nothing was filed.';
      });
      return;
    }
    _draft.clear();
    setState(() {
      _busy = false;
      _picker = null;
      _error = null;
      _status = 'Step cell added. Compile to bind it to a tool.';
    });
  }

  /// Compile the document's step cells. The diagram cell that appears after is
  /// the ENGINE's plan, read back — not a picture drawn from the English here.
  Future<void> _compile() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Compiling…';
    });

    final backend = ref.read(cyanBackendProvider);
    final ack = await backend.pipelineCompile(widget.boardId);
    if (!mounted) return;
    _reload();
    setState(() {
      _busy = false;
      _status = ack.accepted
          ? 'Compiled — the diagram below is the plan a run would walk.'
          : null;
      _error = ack.accepted ? null : (ack.error ?? 'The compile was refused.');
    });
  }

  /// Both readings of the one ledger, so the document and the Workflow face
  /// can never drift apart.
  void _reload() {
    ref.invalidate(boardNotebookProvider(widget.boardId));
    ref.invalidate(boardWorkflowProvider(widget.boardId));
    ref.invalidate(boardPipelineProvider(widget.boardId));
  }

  // ---- the picker (@ plugins · # artifacts · / actions) ---------------------

  /// Recompute the picker from the token AT THE CARET: typing `@fra` in the
  /// middle of a pasted sentence summons the picker for `@fra`, not for
  /// whatever token happens to end the line.
  Future<void> _draftChanged(String text) async {
    final selection = _draft.selection;
    final cursor = selection.isValid ? selection.baseOffset : text.length;
    final token = _tokenAt(text, cursor);
    if (token == null) {
      if (_picker != null) setState(() => _picker = null);
      return;
    }
    final seq = ++_pickerSeq;
    final backend = ref.read(cyanBackendProvider);
    // The seam takes the text UP TO THE CARET — the engine owns which trigger
    // is active and what the vocabulary behind it is; this side never filters.
    final index = await backend.workflowAutocomplete(
        widget.boardId, text.substring(0, token.cursor));
    if (!mounted || seq != _pickerSeq) return;
    setState(() {
      _picker = _Picker(
        trigger: token.trigger,
        tokenStart: token.start,
        cursor: token.cursor,
        // Exactly one lane is populated for an active trigger; an empty one
        // means "nothing to offer for this trigger", not "nothing installed".
        suggestions: [
          ...index.plugins,
          ...index.artifacts,
          ...index.actions,
        ],
      );
    });
  }

  /// Splice `@value ` over the token being typed, at the caret. Accepting
  /// mid-text must not jump the caret to the end of the field.
  void _accept(AutocompleteEntry entry) {
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
    final cellsAsync = ref.watch(boardNotebookProvider(widget.boardId));

    return Material(
      color: MonokaiTheme.background,
      child: cellsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MonokaiTheme.cyan),
        ),
        error: (e, _) => Center(
          child: Text('Failed to load the notebook: $e',
              style:
                  MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.red)),
        ),
        data: (cells) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(cells),
            if (_error != null)
              _StatusStrip(text: _error!, tint: MonokaiTheme.red)
            else if (_status != null)
              _StatusStrip(text: _status!, tint: MonokaiTheme.comment),
            const Divider(height: 1, color: MonokaiTheme.divider),
            Expanded(
              child: cells.isEmpty
                  ? const _EmptyState()
                  : _document(cells),
            ),
            const Divider(height: 1, color: MonokaiTheme.divider),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(List<NotebookCell> cells) {
    final steps =
        cells.where((c) => c.kind == NotebookCellKind.step).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.menu_book, size: 18, color: MonokaiTheme.cyan),
          const SizedBox(width: 10),
          Text('Notebook', style: MonokaiTheme.titleSmall),
          const SizedBox(width: 10),
          Text('${cells.length} cells · $steps steps',
              style: MonokaiTheme.labelSmall),
          const Spacer(),
          _ToolButton(
            key: const ValueKey('notebook.compile'),
            icon: Icons.auto_fix_high,
            label: 'Compile',
            tint: MonokaiTheme.cyan,
            enabled: steps > 0 && !_busy,
            onTap: _compile,
          ),
        ],
      ),
    );
  }

  Widget _document(List<NotebookCell> cells) {
    // Step cells carry their own running number — the document numbers the
    // steps, not the prose between them.
    final ordinals = <String, int>{};
    for (final cell in cells) {
      if (cell.kind == NotebookCellKind.step) {
        ordinals[cell.id] = ordinals.length + 1;
      }
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: cells.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final cell = cells[i];
        return _CellContainer(
          cell: cell,
          ordinal: ordinals[cell.id],
          collapsed: _collapsed.contains(cell.id),
          onToggleCollapse: () => setState(() {
            if (!_collapsed.remove(cell.id)) _collapsed.add(cell.id);
          }),
        );
      },
    );
  }

  Widget _composer() {
    final picker = _picker;
    return Container(
      color: MonokaiTheme.surface.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (picker != null)
            _AutocompletePanel(picker: picker, onAccept: _accept),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child:
                      Icon(Icons.add_circle, size: 18, color: MonokaiTheme.cyan),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        key: const ValueKey('notebook.composer.field'),
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
                          hintText: 'Add a step cell — e.g. "Transcode the '
                              'master…"',
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
                  key: const ValueKey('notebook.composer.add'),
                  onTap: _addStep,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: MonokaiTheme.cyan,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Add cell',
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

/// The open autocomplete.
class _Picker {
  final String trigger;
  final int tokenStart;
  final int cursor;
  final List<AutocompleteEntry> suggestions;

  const _Picker({
    required this.trigger,
    required this.tokenStart,
    required this.cursor,
    required this.suggestions,
  });
}

/// The dropdown. Renders even when the index answers with NOTHING: a silent
/// popover makes a dead index look like broken autocomplete.
class _AutocompletePanel extends StatelessWidget {
  final _Picker picker;
  final void Function(AutocompleteEntry) onAccept;

  const _AutocompletePanel({required this.picker, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    final rows = picker.suggestions.take(6).toList();
    return Container(
      decoration: const BoxDecoration(
        color: MonokaiTheme.surfaceLight,
        border: Border(
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
              key: ValueKey('notebook.autocomplete.row.${entry.value}'),
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
      key: const ValueKey('notebook.autocomplete.empty'),
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

// ---------------------------------------------------------------------------
// The cell container — SwiftUI `NotebookCellContainer` parity
// ---------------------------------------------------------------------------

class _CellContainer extends StatelessWidget {
  final NotebookCell cell;

  /// A step cell's number in the document; null for every other kind.
  final int? ordinal;
  final bool collapsed;
  final VoidCallback onToggleCollapse;

  const _CellContainer({
    required this.cell,
    required this.ordinal,
    required this.collapsed,
    required this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final tint = _tint(cell.kind);
    return Container(
      key: ValueKey('notebook.cell.${cell.id}'),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MonokaiTheme.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(tint),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: _body(),
            ),
        ],
      ),
    );
  }

  Widget _header(Color tint) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Row(
          children: [
            Icon(_icon(cell.kind), size: 13, color: tint),
            const SizedBox(width: 8),
            Text(
              ordinal == null ? cell.kind.label : '${cell.kind.label} $ordinal',
              style: MonokaiTheme.labelMedium.copyWith(color: tint),
            ),
            if (cell.generatedFrom != null) ...[
              const SizedBox(width: 8),
              Text('generated from the ${cell.generatedFrom}',
                  key: ValueKey('notebook.generated.${cell.id}'),
                  style: MonokaiTheme.labelSmall),
            ],
            const Spacer(),
            GestureDetector(
              key: ValueKey('notebook.collapse.${cell.id}'),
              onTap: onToggleCollapse,
              child: Icon(
                collapsed ? Icons.chevron_right : Icons.expand_more,
                size: 16,
                color: MonokaiTheme.textMuted,
              ),
            ),
          ],
        ),
      );

  Widget _body() => switch (cell.kind) {
        NotebookCellKind.step => _StepCellBody(cell: cell),
        NotebookCellKind.markdown => _MarkdownBody(source: cell.content),
        NotebookCellKind.code => _CodeCellBody(cell: cell),
        NotebookCellKind.image => _ImageCellBody(cell: cell),
        NotebookCellKind.mermaid => _MermaidCellBody(cell: cell),
        // A kind this build cannot draw is REPORTED, never dropped: the cell is
        // the operator's work and the document must not pretend it is absent.
        _ => _UnrenderableBody(cell: cell),
      };

  static IconData _icon(NotebookCellKind kind) => switch (kind) {
        NotebookCellKind.step => Icons.list_alt,
        NotebookCellKind.markdown => Icons.notes,
        NotebookCellKind.code => Icons.code,
        NotebookCellKind.image => Icons.image_outlined,
        NotebookCellKind.mermaid => Icons.account_tree,
        NotebookCellKind.canvas => Icons.gesture,
        NotebookCellKind.model => Icons.view_in_ar,
        NotebookCellKind.unknown => Icons.help_outline,
      };

  /// Swift `NotebookCellContainer.accentColor`.
  static Color _tint(NotebookCellKind kind) => switch (kind) {
        NotebookCellKind.step => MonokaiTheme.cyan,
        NotebookCellKind.markdown => MonokaiTheme.cyan,
        NotebookCellKind.code => MonokaiTheme.yellow,
        NotebookCellKind.image => MonokaiTheme.green,
        NotebookCellKind.mermaid => MonokaiTheme.purple,
        NotebookCellKind.canvas => MonokaiTheme.orange,
        NotebookCellKind.model => MonokaiTheme.red,
        NotebookCellKind.unknown => MonokaiTheme.textMuted,
      };
}

// ---------------------------------------------------------------------------
// Step cell
// ---------------------------------------------------------------------------

/// The authored English, and the tool the COMPILE bound to it. An uncompiled
/// step says nothing is bound rather than showing the plugin its text names:
/// a mention is what the author asked for, a bind is what the engine answered.
class _StepCellBody extends StatelessWidget {
  final NotebookCell cell;

  const _StepCellBody({required this.cell});

  @override
  Widget build(BuildContext context) {
    final tool = cell.tool;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cell.content,
          key: ValueKey('notebook.step.text.${cell.id}'),
          style: MonokaiTheme.bodyMedium.copyWith(
              color: MonokaiTheme.foreground, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (tool != null)
          _Chip(
            key: ValueKey('notebook.step.tool.${cell.id}'),
            icon: Icons.extension,
            text: tool,
            tint: MonokaiTheme.cyan,
          )
        else
          Row(
            key: ValueKey('notebook.step.unbound.${cell.id}'),
            children: [
              const Icon(Icons.link_off, size: 11, color: MonokaiTheme.comment),
              const SizedBox(width: 6),
              Text('No tool bound yet — compile to resolve this step',
                  style: MonokaiTheme.labelSmall),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Code cell
// ---------------------------------------------------------------------------

/// Source, and what the LAST execution printed. No output at all is a cell that
/// has never run — distinct from a run that printed nothing, which shows an
/// empty output block rather than none.
class _CodeCellBody extends StatelessWidget {
  final NotebookCell cell;

  const _CodeCellBody({required this.cell});

  @override
  Widget build(BuildContext context) {
    final output = cell.output;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cell.language != null)
          Align(
            alignment: Alignment.centerLeft,
            child: _Chip(
              icon: Icons.terminal,
              text: cell.language!,
              tint: MonokaiTheme.yellow,
            ),
          ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: MonokaiTheme.background,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            cell.content,
            key: ValueKey('notebook.code.${cell.id}'),
            style: MonokaiTheme.codeSmall
                .copyWith(color: MonokaiTheme.foreground),
          ),
        ),
        if (output != null) ...[
          const SizedBox(height: 8),
          Text('Output', style: MonokaiTheme.labelSmall),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MonokaiTheme.green.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              output,
              key: ValueKey('notebook.code.output.${cell.id}'),
              style:
                  MonokaiTheme.codeSmall.copyWith(color: MonokaiTheme.green),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Image cell
// ---------------------------------------------------------------------------

/// The cell's pixels when it carries them, its NAME when it does not. Swift's
/// `ImageCellView` falls back the same way — an image whose bytes are still on
/// a peer is a reference, and saying so beats a broken frame.
class _ImageCellBody extends StatelessWidget {
  final NotebookCell cell;

  const _ImageCellBody({required this.cell});

  @override
  Widget build(BuildContext context) {
    final bytes = cell.inlineImageBytes;
    final reference = cell.imageReference;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              bytes,
              key: ValueKey('notebook.image.${cell.id}'),
              height: 140,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              // A decode that fails is REPORTED as the reference treatment
              // rather than throwing inside a paint.
              errorBuilder: (_, __, ___) =>
                  _reference(cell.caption ?? 'Image'),
            ),
          )
        else
          _reference(reference ?? 'Image'),
        if (cell.caption != null) ...[
          const SizedBox(height: 6),
          Text(cell.caption!,
              key: ValueKey('notebook.image.caption.${cell.id}'),
              style: MonokaiTheme.labelSmall
                  .copyWith(fontStyle: FontStyle.italic)),
        ],
      ],
    );
  }

  Widget _reference(String name) => Container(
        key: ValueKey('notebook.image.reference.${cell.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: MonokaiTheme.surfaceLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo, size: 13, color: MonokaiTheme.comment),
            const SizedBox(width: 8),
            Flexible(
              child: Text(name,
                  overflow: TextOverflow.ellipsis,
                  style: MonokaiTheme.labelMedium
                      .copyWith(color: MonokaiTheme.textSecondary)),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// A cell this build cannot draw
// ---------------------------------------------------------------------------

class _UnrenderableBody extends StatelessWidget {
  final NotebookCell cell;

  const _UnrenderableBody({required this.cell});

  @override
  Widget build(BuildContext context) {
    return Row(
      key: ValueKey('notebook.unrenderable.${cell.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 12, color: MonokaiTheme.orange),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'This build cannot draw a ${cell.kind.rawValue} cell — it is kept, '
            'not dropped.',
            style:
                MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.orange),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Markdown cell — SwiftUI `NotebookMarkdownRenderer` parity
// ---------------------------------------------------------------------------

/// Renders markdown as ELEMENTS: headings, bullets, checkboxes, quotes, rules
/// and fenced code. Inline `**bold**` / `` `code` `` are spans, so the source
/// markers never reach the screen.
class _MarkdownBody extends StatelessWidget {
  final String source;

  const _MarkdownBody({required this.source});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _elements(source),
    );
  }

  static List<Widget> _elements(String source) {
    final out = <Widget>[];
    final fence = <String>[];
    var inFence = false;

    for (final line in source.split('\n')) {
      final trimmed = line.trim();

      if (trimmed.startsWith('```')) {
        if (inFence) {
          out.add(_fenced(fence.join('\n')));
          fence.clear();
        }
        inFence = !inFence;
        continue;
      }
      if (inFence) {
        fence.add(line);
        continue;
      }

      if (trimmed.startsWith('#### ')) {
        out.add(_heading(trimmed.substring(5), 13));
      } else if (trimmed.startsWith('### ')) {
        out.add(_heading(trimmed.substring(4), 14));
      } else if (trimmed.startsWith('## ')) {
        out.add(_heading(trimmed.substring(3), 16));
      } else if (trimmed.startsWith('# ')) {
        out.add(_heading(trimmed.substring(2), 18));
      } else if (_checked(trimmed) != null) {
        final done = _checked(trimmed)!;
        out.add(_checkbox(trimmed.substring(6), done));
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        out.add(_bullet(trimmed.substring(2)));
      } else if (trimmed.startsWith('> ')) {
        out.add(_quote(trimmed.substring(2)));
      } else if (trimmed == '---' || trimmed == '***') {
        out.add(const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, color: MonokaiTheme.divider),
        ));
      } else if (trimmed.isEmpty) {
        out.add(const SizedBox(height: 6));
      } else {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text.rich(_inline(line,
              MonokaiTheme.bodyMedium
                  .copyWith(color: MonokaiTheme.foreground))),
        ));
      }
    }
    if (fence.isNotEmpty) out.add(_fenced(fence.join('\n')));
    return out;
  }

  /// `- [x]` / `- [ ]`, or null when the line is not a checkbox at all.
  static bool? _checked(String line) {
    final lower = line.toLowerCase();
    if (lower.startsWith('- [x]')) return true;
    if (lower.startsWith('- [ ]')) return false;
    return null;
  }

  static Widget _heading(String text, double size) => Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 4),
        child: Text.rich(_inline(
          text,
          MonokaiTheme.titleSmall.copyWith(
              color: MonokaiTheme.foreground,
              fontSize: size,
              fontWeight: FontWeight.w700),
        )),
      );

  static Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('•', style: MonokaiTheme.bodyMedium),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(_inline(
                  text,
                  MonokaiTheme.bodyMedium
                      .copyWith(color: MonokaiTheme.foreground))),
            ),
          ],
        ),
      );

  static Widget _checkbox(String text, bool done) => Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(done ? Icons.check_box : Icons.check_box_outline_blank,
                size: 14,
                color: done ? MonokaiTheme.green : MonokaiTheme.comment),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(_inline(
                text,
                MonokaiTheme.bodyMedium.copyWith(
                  color: done ? MonokaiTheme.comment : MonokaiTheme.foreground,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              )),
            ),
          ],
        ),
      );

  static Widget _quote(String text) => Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.only(left: 10),
        decoration: const BoxDecoration(
          border: Border(
              left: BorderSide(color: MonokaiTheme.comment, width: 3)),
        ),
        child: Text.rich(_inline(
            text,
            MonokaiTheme.bodyMedium.copyWith(
                color: MonokaiTheme.comment, fontStyle: FontStyle.italic))),
      );

  static Widget _fenced(String code) => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: MonokaiTheme.background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(code,
            style:
                MonokaiTheme.codeSmall.copyWith(color: MonokaiTheme.green)),
      );

  /// `**bold**` and `` `code` `` as spans over [base].
  static TextSpan _inline(String text, TextStyle base) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|`(.+?)`');
    var index = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > index) {
        spans.add(TextSpan(text: text.substring(index, m.start), style: base));
      }
      if (m.group(1) != null) {
        spans.add(TextSpan(
            text: m.group(1),
            style: base.copyWith(fontWeight: FontWeight.w700)));
      } else {
        spans.add(TextSpan(
            text: m.group(2),
            style: base.copyWith(
                fontFamily: 'monospace', color: MonokaiTheme.green)));
      }
      index = m.end;
    }
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index), style: base));
    }
    return TextSpan(children: spans, style: base);
  }
}

// ---------------------------------------------------------------------------
// Mermaid cell — the compiled DAG, drawn
// ---------------------------------------------------------------------------

/// A mermaid cell is a DIAGRAM, not its source: nodes laid out in dependency
/// layers with the edges drawn between them. Source that parses to nothing
/// falls back to showing the source, because an empty frame would read as a
/// broken diagram rather than as one this build could not lay out.
class _MermaidCellBody extends StatelessWidget {
  final NotebookCell cell;

  const _MermaidCellBody({required this.cell});

  @override
  Widget build(BuildContext context) {
    final graph = _MermaidGraph.parse(cell.content);
    if (graph.nodes.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline,
                  size: 12, color: MonokaiTheme.orange),
              const SizedBox(width: 8),
              Text('No diagram in this cell yet',
                  key: ValueKey('notebook.dag.empty.${cell.id}'),
                  style: MonokaiTheme.labelSmall
                      .copyWith(color: MonokaiTheme.orange)),
            ],
          ),
          const SizedBox(height: 6),
          _MarkdownBody._fenced(cell.content),
        ],
      );
    }

    final layers = graph.layers();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(graph.kind, style: MonokaiTheme.labelSmall),
            const SizedBox(width: 10),
            Text(
                '${graph.nodes.length} nodes · ${graph.edges.length} edges',
                style: MonokaiTheme.labelSmall),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < layers.length; i++) ...[
          if (i > 0)
            _MermaidConnectors(
                from: layers[i - 1], to: layers[i], edges: graph.edges),
          Row(
            key: ValueKey('notebook.dag.layer.$i'),
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final id in layers[i])
                Flexible(
                  child: _MermaidNode(id: id, label: graph.nodes[id] ?? id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MermaidNode extends StatelessWidget {
  final String id;
  final String label;

  const _MermaidNode({required this.id, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('notebook.dag.node.$id'),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: MonokaiTheme.purple.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MonokaiTheme.purple.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style:
            MonokaiTheme.labelMedium.copyWith(color: MonokaiTheme.foreground),
      ),
    );
  }
}

/// The edges between two layers, drawn from each dependent back to what it
/// waits on — the same curve the compiled-plan preview draws.
class _MermaidConnectors extends StatelessWidget {
  final List<String> from;
  final List<String> to;
  final List<_MermaidEdge> edges;

  const _MermaidConnectors({
    required this.from,
    required this.to,
    required this.edges,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: CustomPaint(
        painter: _MermaidConnectorPainter(from: from, to: to, edges: edges),
        size: Size.infinite,
      ),
    );
  }
}

class _MermaidConnectorPainter extends CustomPainter {
  final List<String> from;
  final List<String> to;
  final List<_MermaidEdge> edges;

  const _MermaidConnectorPainter({
    required this.from,
    required this.to,
    required this.edges,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MonokaiTheme.comment
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (var t = 0; t < to.length; t++) {
      for (final edge in edges.where((e) => e.to == to[t])) {
        final f = from.indexOf(edge.from);
        if (f < 0) continue;
        final fromX = size.width / (from.length + 1) * (f + 1);
        final toX = size.width / (to.length + 1) * (t + 1);
        canvas.drawPath(
          Path()
            ..moveTo(fromX, 0)
            ..cubicTo(fromX, size.height * 0.5, toX, size.height * 0.5, toX,
                size.height),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MermaidConnectorPainter old) =>
      old.from != from || old.to != to || old.edges != edges;
}

/// One `A --> B` edge.
@immutable
class _MermaidEdge {
  final String from;
  final String to;

  const _MermaidEdge(this.from, this.to);

  @override
  bool operator ==(Object other) =>
      other is _MermaidEdge && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// A parsed mermaid flowchart: the nodes it declares and the edges between
/// them. Only the flowchart grammar the engine WRITES is read — a diagram this
/// build does not understand parses to nothing and is shown as source.
class _MermaidGraph {
  _MermaidGraph({required this.kind, required this.nodes, required this.edges});

  final String kind;

  /// Node id → its label, in declaration order.
  final Map<String, String> nodes;
  final List<_MermaidEdge> edges;

  static final RegExp _decl =
      RegExp(r'^([A-Za-z0-9_.\-]+)\s*(?:\["([^"]*)"\]|\[([^\]]*)\]|\{([^}]*)\}|\(([^)]*)\))$');
  static final RegExp _edge = RegExp(
      r'^([A-Za-z0-9_.\-]+)\s*(?:\["[^"]*"\]|\[[^\]]*\]|\{[^}]*\}|\([^)]*\))?'
      r'\s*(?:-->|---|==>|-\.->)\s*(?:\|[^|]*\|\s*)?'
      r'([A-Za-z0-9_.\-]+)\s*(?:\["[^"]*"\]|\[[^\]]*\]|\{[^}]*\}|\([^)]*\))?$');

  static _MermaidGraph parse(String source) {
    final nodes = <String, String>{};
    final edges = <_MermaidEdge>[];
    var kind = 'Diagram';

    void declare(String id, String? label) {
      final existing = nodes[id];
      if (label != null && label.isNotEmpty) {
        nodes[id] = label;
      } else if (existing == null) {
        nodes[id] = id;
      }
    }

    for (final raw in source.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('%%')) continue;

      if (line.startsWith('graph ') || line.startsWith('flowchart ')) {
        kind = 'Flowchart';
        continue;
      }
      // Anything that is not a flowchart is not laid out here.
      if (RegExp(r'^[A-Za-z]+Diagram\b').hasMatch(line) ||
          line.startsWith('gantt') ||
          line.startsWith('pie') ||
          line.startsWith('mindmap')) {
        return _MermaidGraph(kind: kind, nodes: const {}, edges: const []);
      }

      final edge = _edge.firstMatch(line);
      if (edge != null) {
        // Both ends may carry their label inline — declare them, then wire.
        for (final m in RegExp(
                r'([A-Za-z0-9_.\-]+)\s*(?:\["([^"]*)"\]|\[([^\]]*)\]|\{([^}]*)\}|\(([^)]*)\))')
            .allMatches(line)) {
          declare(m.group(1)!,
              m.group(2) ?? m.group(3) ?? m.group(4) ?? m.group(5));
        }
        declare(edge.group(1)!, null);
        declare(edge.group(2)!, null);
        edges.add(_MermaidEdge(edge.group(1)!, edge.group(2)!));
        continue;
      }

      final decl = _decl.firstMatch(line);
      if (decl != null) {
        declare(decl.group(1)!,
            decl.group(2) ?? decl.group(3) ?? decl.group(4) ?? decl.group(5));
      }
    }
    return _MermaidGraph(kind: kind, nodes: nodes, edges: edges);
  }

  /// Nodes in dependency layers: layer 0 depends on nothing, and each layer
  /// after it is everything whose sources have all landed. A cycle or an orphan
  /// is placed in a final layer — shown, never dropped.
  List<List<String>> layers() {
    final all = nodes.keys.toList();
    final incoming = {
      for (final id in all) id: edges.where((e) => e.to == id).toList(),
    };
    final placed = <String>{};
    final out = <List<String>>[];
    var current = [for (final id in all) if (incoming[id]!.isEmpty) id];

    while (current.isNotEmpty) {
      out.add(current);
      placed.addAll(current);
      current = [
        for (final id in all)
          if (!placed.contains(id) &&
              incoming[id]!.every((e) => placed.contains(e.from)))
            id,
      ];
    }
    final remaining = [
      for (final id in all)
        if (!placed.contains(id)) id,
    ];
    if (remaining.isNotEmpty) out.add(remaining);
    return out;
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color tint;

  const _Chip({
    super.key,
    required this.icon,
    required this.text,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.menu_book,
              size: 56, color: MonokaiTheme.textDisabled),
          const SizedBox(height: 14),
          Text('This notebook is empty',
              style: MonokaiTheme.titleSmall
                  .copyWith(color: MonokaiTheme.textMuted)),
          const SizedBox(height: 6),
          Text('Add a step cell below to start this board off',
              style: MonokaiTheme.labelMedium),
        ],
      ),
    );
  }
}
