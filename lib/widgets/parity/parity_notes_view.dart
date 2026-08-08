// widgets/parity/parity_notes_view.dart
//
// PARITY face_notes · LAYER 3 (the pure view) — the board "Notes" face.
//
// SwiftUI reference (READ-ONLY):
//   Views/NotesEditorView.swift       — the VSCode-style editor: the toolbar
//        with the detected file type and the save state, the line-number
//        gutter, the editable body, the A2 review rail, the status bar
//   Views/BoardNotesLedgerView.swift  — the ledger, mounted as the right column
//        (Swift: `HStack { editorContent; BoardNotesLedgerView(...) }`)
//
// The document is EDITABLE and it autosaves, and the toolbar reports what the
// engine actually did with the write rather than a green dot that is always on.
// All data flows through `NotesEditorController` (the one `CyanBackend` seam).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/notes_face_mode.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../providers/notes_editor_controller.dart';
import '../../theme/monokai_theme.dart';
import 'parity_constitution_editor.dart';
import 'parity_notes_ledger.dart';
import 'parity_notes_structuring.dart';

/// The ledger column's width — Swift pins its panel to a fixed 260pt beside the
/// editor; the extra room here carries the byline + edit-time row without
/// truncating it.
const double _ledgerWidth = 300;

class ParityNotesView extends StatelessWidget {
  final String boardId;

  /// An explicit controller, for callers driving their own reads.
  final NotesEditorController? controller;

  const ParityNotesView({super.key, required this.boardId, this.controller});

  @override
  Widget build(BuildContext context) {
    // A different board is a different DOCUMENT. Without this key Flutter
    // reuses the State when the face is re-pointed at another board, and the
    // editor keeps the previous board's buffer, ledger and reviewer rail.
    return _NotesSurface(
      key: ValueKey('notes.face.$boardId'),
      boardId: boardId,
      controller: controller,
    );
  }
}

class _NotesSurface extends ConsumerStatefulWidget {
  final String boardId;
  final NotesEditorController? controller;

  const _NotesSurface({super.key, required this.boardId, this.controller});

  @override
  ConsumerState<_NotesSurface> createState() => _ParityNotesViewState();
}

class _ParityNotesViewState extends ConsumerState<_NotesSurface> {
  late final NotesEditorController _editor;
  late final VoidCallback _unsubscribe;
  late final TextEditingController _text;

  bool _ownsEditor = false;
  bool _mountedOnce = false;
  NotesEditorState _state = const NotesEditorState();

  /// Which mode the face is in. Opens on the document, like Swift's
  /// `@State private var notesMode: NotesFaceMode = .editor`.
  NotesFaceMode _mode = NotesFaceMode.editor;

  @override
  void initState() {
    super.initState();
    final injected = widget.controller;
    if (injected != null) {
      _editor = injected;
    } else {
      _ownsEditor = true;
      _editor = NotesEditorController(
        backend: ref.read(cyanBackendProvider),
        boardId: widget.boardId,
      );
    }
    _text = TextEditingController(text: _editor.state.content);
    _text.addListener(_onCaret);
    _state = _editor.state;
    _unsubscribe = _editor.addListener(_onEditor);
    _mountedOnce = true;
    _editor.load();
  }

  @override
  void dispose() {
    _unsubscribe();
    _text.removeListener(_onCaret);
    _text.dispose();
    if (_ownsEditor) _editor.dispose();
    super.dispose();
  }

  /// The load revision the field was last seeded from.
  int _seededRevision = 0;

  void _onEditor(NotesEditorState s) {
    // The buffer belongs to the FIELD. The controller re-seeds it only on a
    // LOAD — a caret move or a save verdict publishing mid-keystroke must never
    // reach in and rewrite what the operator is typing.
    if (s.revision != _seededRevision) {
      _seededRevision = s.revision;
      if (s.content != _text.text) {
        _text.value = TextEditingValue(
          text: s.content,
          selection: TextSelection.collapsed(offset: s.content.length),
        );
      }
    }
    if (_mountedOnce && mounted) {
      setState(() => _state = s);
    } else {
      _state = s;
    }
  }

  void _onCaret() => _editor.cursorMovedTo(_text.selection.baseOffset);

  @override
  Widget build(BuildContext context) {
    if (!_state.hydrated) {
      return const Material(
        color: MonokaiTheme.background,
        child:
            Center(child: CircularProgressIndicator(color: MonokaiTheme.cyan)),
      );
    }
    return Material(
      color: MonokaiTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(),
          const Divider(height: 1, color: MonokaiTheme.divider),
          if (_state.lastError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Text(_state.lastError!,
                  key: const ValueKey('notes-error'),
                  style: MonokaiTheme.labelSmall
                      .copyWith(color: MonokaiTheme.red)),
            ),
          Expanded(
            // The CONSTITUTION replaces the editor body, exactly as Swift's
            // `notesMode == .constitution` branch does — the house rules are a
            // mode of the notes face, not a separate screen, because they are
            // the other half of the same question: where does this board get
            // its arguments when the reviewer left nothing?
            child: _mode == NotesFaceMode.constitution
                ? ParityConstitutionEditor(boardId: widget.boardId)
                : _mode == NotesFaceMode.structure
                    ? ParityNotesStructuring(boardId: widget.boardId)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // A2: the review conversation the board already
                                // has, above the document. It exists only when a
                                // reviewer has actually left something.
                                if (_state.reviewNotes.isNotEmpty)
                                  _reviewRail(),
                                Expanded(child: _editorBody()),
                              ],
                            ),
                          ),
                          const VerticalDivider(
                              width: 1, color: MonokaiTheme.divider),
                          SizedBox(
                            width: _ledgerWidth,
                            child: ParityNotesLedger(boardId: widget.boardId),
                          ),
                        ],
                      ),
          ),
          const Divider(height: 1, color: MonokaiTheme.divider),
          // The status bar reports the DOCUMENT (line, column, word count), so
          // it belongs to the editor mode and would be meaningless over the
          // constitution.
          if (_mode == NotesFaceMode.editor) _statusBar(),
        ],
      ),
    );
  }

  // ---- toolbar -------------------------------------------------------------

  Widget _toolbar() {
    final problem = _state.saveProblem;
    final durable = problem == null && !_state.dirty && !_state.saving;
    final dotColor = _state.dirty
        ? MonokaiTheme.yellow
        : (problem == null ? MonokaiTheme.green : MonokaiTheme.red);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: MonokaiTheme.surface,
      child: Row(
        children: [
          // The mode picker — Swift's `notes.mode.picker`. Every route to the
          // house rules goes through it.
          _ModePicker(
            mode: _mode,
            onSelect: (m) => setState(() => _mode = m),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.description, size: 13, color: MonokaiTheme.green),
          const SizedBox(width: 8),
          Text(_state.fileName,
              key: const ValueKey('notes-filename'),
              style: MonokaiTheme.labelMedium
                  .copyWith(color: MonokaiTheme.foreground)),
          const SizedBox(width: 8),
          // The DETECTED language — the reference labels the buffer by what it
          // reads like, not by the file name it was opened under.
          Container(
            key: const ValueKey('notes-filetype'),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: MonokaiTheme.cyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(_state.detectedType.displayName,
                style:
                    MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.cyan)),
          ),
          const Spacer(),
          if (problem != null)
            Flexible(
              child: Tooltip(
                message: problem,
                child: Text(problem,
                    key: const ValueKey('notes-save-problem'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MonokaiTheme.labelSmall
                        .copyWith(color: MonokaiTheme.red)),
              ),
            ),
          const SizedBox(width: 8),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(_state.saveLabel,
              key: const ValueKey('notes-save-state'),
              style: MonokaiTheme.labelSmall.copyWith(color: dotColor)),
          const SizedBox(width: 12),
          Tooltip(
            message: durable ? 'Nothing to save' : 'Save now',
            child: GestureDetector(
              key: const ValueKey('notes-save'),
              onTap: _state.dirty ? _editor.save : null,
              child: Icon(Icons.save_alt,
                  size: 14,
                  color:
                      _state.dirty ? MonokaiTheme.cyan : MonokaiTheme.comment),
            ),
          ),
        ],
      ),
    );
  }

  // ---- the A2 review rail --------------------------------------------------

  Widget _reviewRail() {
    return Container(
      key: const ValueKey('notes-review-rail'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: MonokaiTheme.surface.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rate_review_outlined,
                  size: 11, color: MonokaiTheme.orange),
              const SizedBox(width: 6),
              Text('Reviewer notes',
                  style: MonokaiTheme.labelSmall
                      .copyWith(color: MonokaiTheme.orange)),
              const SizedBox(width: 6),
              Text('${_state.reviewNotes.length}',
                  key: const ValueKey('notes-review-count'),
                  style: MonokaiTheme.labelSmall
                      .copyWith(color: MonokaiTheme.comment)),
            ],
          ),
          const SizedBox(height: 4),
          for (final n in _state.reviewNotes)
            Padding(
              key: ValueKey('notes-review-${n.id}'),
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(n.timecodeLabel,
                        style: MonokaiTheme.codeSmall
                            .copyWith(color: MonokaiTheme.cyan)),
                  ),
                  Expanded(
                    child: Text(n.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MonokaiTheme.bodySmall
                            .copyWith(color: MonokaiTheme.foreground)),
                  ),
                  const SizedBox(width: 6),
                  Text(n.author,
                      style: MonokaiTheme.labelSmall
                          .copyWith(color: MonokaiTheme.comment)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---- the editor ----------------------------------------------------------

  Widget _editorBody() {
    final lineCount = _state.lineCount;
    return Container(
      color: MonokaiTheme.surfaceLighter,
      child: SingleChildScrollView(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The gutter counts the BUFFER's lines, so it tracks typing rather
            // than the document as it was loaded.
            Container(
              width: 50,
              color: MonokaiTheme.background,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 1; i <= lineCount; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Text('$i',
                          style: MonokaiTheme.codeStyle
                              .copyWith(color: MonokaiTheme.textDisabled)),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1, color: MonokaiTheme.divider),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: TextField(
                  key: const ValueKey('notes-editor'),
                  controller: _text,
                  maxLines: null,
                  expands: false,
                  style: MonokaiTheme.codeStyle
                      .copyWith(color: MonokaiTheme.foreground),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
                  onChanged: _editor.contentDidChange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- status bar ----------------------------------------------------------

  Widget _statusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: MonokaiTheme.surface,
      child: Row(
        children: [
          Text('Ln ${_state.line}, Col ${_state.column}',
              key: const ValueKey('notes-caret'),
              style:
                  MonokaiTheme.codeSmall.copyWith(color: MonokaiTheme.comment)),
          const SizedBox(width: 14),
          Text('${_state.lineCount} lines',
              key: const ValueKey('notes-lines'),
              style:
                  MonokaiTheme.codeSmall.copyWith(color: MonokaiTheme.comment)),
          const SizedBox(width: 14),
          Text('${_state.wordCount} words',
              key: const ValueKey('notes-words'),
              style:
                  MonokaiTheme.codeSmall.copyWith(color: MonokaiTheme.comment)),
          const Spacer(),
          Text('UTF-8',
              style:
                  MonokaiTheme.codeSmall.copyWith(color: MonokaiTheme.comment)),
        ],
      ),
    );
  }
}

/// The Notes face's mode picker — Swift's segmented `notes.mode.picker`.
///
/// Only the modes that have a lane behind them are offered. `Structure` is a
/// real Swift segment but its surface is lens HTTP (`POST /api/v1/notes/
/// structure`) and the `LensApi` seam carries no such method yet, so drawing it
/// would be a control that does nothing — which this port has already decided
/// in writing is worse than no control.
class _ModePicker extends StatelessWidget {
  final NotesFaceMode mode;
  final ValueChanged<NotesFaceMode> onSelect;

  const _ModePicker({required this.mode, required this.onSelect});

  /// All three now: `Structure` was withheld only while the `LensApi` seam had
  /// no `structureNote`, because a control with no lane behind it is worse than
  /// no control. The lane exists, so the segment is drawn.
  static const List<NotesFaceMode> _offered = NotesFaceMode.values;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('notes.mode.picker'),
      decoration: BoxDecoration(
        color: MonokaiTheme.background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: MonokaiTheme.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in _offered)
            GestureDetector(
              key: ValueKey(m.segmentKey),
              onTap: () => onSelect(m),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: m == mode
                      ? MonokaiTheme.cyan.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  m.label,
                  style: MonokaiTheme.labelSmall.copyWith(
                    color:
                        m == mode ? MonokaiTheme.cyan : MonokaiTheme.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
