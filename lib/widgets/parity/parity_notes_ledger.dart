// widgets/parity/parity_notes_ledger.dart
//
// PARITY port of the SwiftUI `BoardNotesLedgerView` — the board ledger panel
// that mounts as the right column of the Notes face (Swift: NotesEditorView's
// `HStack { editorContent; BoardNotesLedgerView(...).frame(width: 260) }`).
//
// The ledger is what the board RECORDED: decisions, standing house rules, and
// authored notes — each row carrying its kind chip, its author byline (a
// resolved name · craft-role, NEVER a raw node id) and the time it was last
// edited. Rows are authored, edited and deleted here; the write goes through
// the `CyanBackend` seam and the panel then re-reads the ledger off the engine,
// so a row on screen is a row the engine kept.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Views/BoardNotesLedgerView.swift

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/notes_ledger_provider.dart';
import '../../theme/monokai_theme.dart';

class ParityNotesLedger extends ConsumerStatefulWidget {
  final String boardId;

  const ParityNotesLedger({super.key, required this.boardId});

  @override
  ConsumerState<ParityNotesLedger> createState() => _ParityNotesLedgerState();
}

class _ParityNotesLedgerState extends ConsumerState<ParityNotesLedger> {
  final TextEditingController _compose = TextEditingController();
  final TextEditingController _edit = TextEditingController();

  /// The note whose row is currently open for editing, if any.
  String? _editingId;
  bool _busy = false;

  @override
  void dispose() {
    _compose.dispose();
    _edit.dispose();
    super.dispose();
  }

  NotesLedgerController get _controller =>
      ref.read(notesLedgerProvider(widget.boardId).notifier);

  Future<void> _add() async {
    if (_busy || _compose.text.trim().isEmpty) return;
    setState(() => _busy = true);
    await _controller.addNote(_compose.text);
    if (!mounted) return;
    _compose.clear();
    setState(() => _busy = false);
  }

  void _openEditor(CyanNote note) {
    setState(() {
      _editingId = note.id;
      _edit.text = note.text;
    });
  }

  Future<void> _saveEdit(String id) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _controller.editNote(id, _edit.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _editingId = null;
    });
  }

  Future<void> _delete(String id) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _controller.deleteNote(id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (_editingId == id) _editingId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notesLedgerProvider(widget.boardId));

    return Container(
      color: MonokaiTheme.surface.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(count: state.notes.length),
          _Composer(
            controller: _compose,
            enabled: !_busy,
            onAdd: _add,
          ),
          const Divider(height: 1, color: MonokaiTheme.divider),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                state.error!,
                key: const ValueKey('notes-ledger-error'),
                style: MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.red),
              ),
            )
          else if (state.loading)
            const Expanded(
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: MonokaiTheme.cyan),
                ),
              ),
            )
          else if (state.isEmpty)
            const Expanded(child: _EmptyState())
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(10),
                children: [
                  _section('DECISIONS', state.decisions, state),
                  _section('HOUSE RULES', state.houseRules, state),
                  _section('NOTES', state.editorNotes, state),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(String title, List<CyanNote> notes, NotesLedgerState state) {
    if (notes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: MonokaiTheme.labelSmall.copyWith(
              color: MonokaiTheme.comment,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _LedgerRow(
                note: note,
                myNodeId: state.myNodeId,
                editing: _editingId == note.id,
                editController: _edit,
                busy: _busy,
                onEdit: () => _openEditor(note),
                onSave: () => _saveEdit(note.id),
                onCancel: () => setState(() => _editingId = null),
                onDelete: () => _delete(note.id),
              ),
            ),
        ],
      ),
    );
  }
}

// MARK: - Chrome

class _Header extends StatelessWidget {
  final int count;
  const _Header({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          const Icon(Icons.list_alt, size: 11, color: MonokaiTheme.textSecondary),
          const SizedBox(width: 6),
          Text('Board ledger',
              style: MonokaiTheme.labelSmall.copyWith(
                color: MonokaiTheme.textSecondary,
                fontWeight: FontWeight.w600,
              )),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: MonokaiTheme.border,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('$count',
                  key: const ValueKey('notes-ledger-count'),
                  style: MonokaiTheme.labelSmall.copyWith(
                    color: MonokaiTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  )),
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onAdd;

  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: MonokaiTheme.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: MonokaiTheme.comment.withValues(alpha: 0.3)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextField(
              key: const ValueKey('notes-ledger-field'),
              controller: controller,
              minLines: 1,
              maxLines: 3,
              enabled: enabled,
              style:
                  MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.foreground),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                hintText: 'Record a note…',
                hintStyle:
                    MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.comment),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: _Pill(
              key: const ValueKey('notes-ledger-add'),
              label: 'Add note',
              tint: MonokaiTheme.green,
              onTap: enabled ? onAdd : null,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.sticky_note_2_outlined,
              size: 20, color: MonokaiTheme.comment),
          const SizedBox(height: 8),
          Text('No decisions or notes yet',
              textAlign: TextAlign.center,
              style: MonokaiTheme.labelSmall
                  .copyWith(color: MonokaiTheme.textSecondary)),
          const SizedBox(height: 3),
          Text('Anything recorded here is kept on the board.',
              textAlign: TextAlign.center,
              style:
                  MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.comment)),
        ],
      ),
    );
  }
}

// MARK: - One ledger row

class _LedgerRow extends StatelessWidget {
  final CyanNote note;
  final String myNodeId;
  final bool editing;
  final TextEditingController editController;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  const _LedgerRow({
    required this.note,
    required this.myNodeId,
    required this.editing,
    required this.editController,
    required this.busy,
    required this.onEdit,
    required this.onSave,
    required this.onCancel,
    required this.onDelete,
  });

  Color get _chipColor => switch (note.kind) {
        'decision' => MonokaiTheme.cyan,
        'constitution' || 'preference' || 'creative-dna' => MonokaiTheme.yellow,
        _ => MonokaiTheme.comment,
      };

  @override
  Widget build(BuildContext context) {
    final byline = noteByline(note, myNodeId: myNodeId);
    final stamp = noteStampLabel(note.updatedAt);

    return Container(
      key: ValueKey('notes-ledger-row-${note.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (editing)
            _EditField(
              noteId: note.id,
              controller: editController,
              busy: busy,
              onSave: onSave,
              onCancel: onCancel,
            )
          else
            Text(note.text,
                style: MonokaiTheme.bodySmall
                    .copyWith(color: MonokaiTheme.foreground)),
          const SizedBox(height: 5),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: _chipColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(noteKindLabel(note.kind),
                    style: MonokaiTheme.labelSmall.copyWith(
                      color: _chipColor,
                      fontWeight: FontWeight.w600,
                    )),
              ),
              const Spacer(),
              if (!editing) ...[
                _RowAction(
                  key: ValueKey('notes-ledger-edit-${note.id}'),
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit this note',
                  onTap: busy ? null : onEdit,
                ),
                const SizedBox(width: 4),
                _RowAction(
                  key: ValueKey('notes-ledger-delete-${note.id}'),
                  icon: Icons.delete_outline,
                  tooltip: 'Remove this note from the ledger',
                  tint: MonokaiTheme.red,
                  onTap: busy ? null : onDelete,
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          // Authorship + edit time: WHO recorded it and WHEN it last changed.
          Row(
            children: [
              Expanded(
                child: Text(
                  byline ?? 'unattributed',
                  key: ValueKey('notes-ledger-author-${note.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MonokaiTheme.labelSmall
                      .copyWith(color: MonokaiTheme.comment),
                ),
              ),
              if (stamp != null) ...[
                const SizedBox(width: 6),
                Text(
                  stamp,
                  key: ValueKey('notes-ledger-stamp-${note.id}'),
                  style: MonokaiTheme.labelSmall
                      .copyWith(color: MonokaiTheme.comment),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  final String noteId;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const _EditField({
    required this.noteId,
    required this.controller,
    required this.busy,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: MonokaiTheme.background,
            borderRadius: BorderRadius.circular(4),
            border:
                Border.all(color: MonokaiTheme.cyan.withValues(alpha: 0.45)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: TextField(
            key: ValueKey('notes-ledger-edit-field-$noteId'),
            controller: controller,
            minLines: 1,
            maxLines: 4,
            style:
                MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.foreground),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 7),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _Pill(
              key: ValueKey('notes-ledger-edit-cancel-$noteId'),
              label: 'Cancel',
              tint: MonokaiTheme.surfaceLight,
              onTap: busy ? null : onCancel,
            ),
            const SizedBox(width: 6),
            _Pill(
              key: ValueKey('notes-ledger-edit-save-$noteId'),
              label: 'Save',
              tint: MonokaiTheme.cyan,
              onTap: busy ? null : onSave,
            ),
          ],
        ),
      ],
    );
  }
}

// MARK: - Shared pieces

class _RowAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? tint;
  final VoidCallback? onTap;

  const _RowAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.tint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            icon,
            size: 13,
            color: onTap == null
                ? MonokaiTheme.textDisabled
                : (tint ?? MonokaiTheme.comment),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color tint;
  final VoidCallback? onTap;

  const _Pill({super.key, required this.label, required this.tint, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:
              enabled ? tint.withValues(alpha: 0.9) : MonokaiTheme.surfaceLight,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: MonokaiTheme.labelSmall.copyWith(
            color: enabled ? MonokaiTheme.background : MonokaiTheme.comment,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
