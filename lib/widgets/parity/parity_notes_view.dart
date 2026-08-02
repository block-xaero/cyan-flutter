// widgets/parity/parity_notes_view.dart
//
// PARITY port of the SwiftUI `NotesEditorView` — the Board "Notes" face
// (PARITY_TRACKER row 5): a VSCode-style editor with a toolbar (file type +
// save state), a line-number gutter, a monospaced editor body, the board
// LEDGER as its right column (`ParityNotesLedger` — Swift mounts
// `BoardNotesLedgerView` in exactly that HStack), and a status bar
// (Ln/Col · lines · words · UTF-8). Monokai-styled.
//
// Driven ENTIRELY through the `CyanBackend` seam (via `boardNotesProvider`).
// This widget never touches `CyanFFI` directly — that is the parity rule.
//
// SwiftUI reference (read-only): cyan-iOS-ready/Cyan/Cyan/Views/NotesEditorView.swift

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';
import 'parity_notes_ledger.dart';

/// The ledger column's width — Swift pins its panel to a fixed 260pt beside the
/// editor; the extra room here carries the byline + edit-time row without
/// truncating it.
const double _ledgerWidth = 300;

class ParityNotesView extends ConsumerWidget {
  final String boardId;

  const ParityNotesView({super.key, required this.boardId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(boardNotesProvider(boardId));

    return Material(
      color: MonokaiTheme.background,
      child: notesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MonokaiTheme.cyan),
        ),
        error: (e, _) => Center(
          child: Text('Failed to load notes: $e',
              style:
                  MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.red)),
        ),
        data: (notes) => _Editor(notes: notes, boardId: boardId),
      ),
    );
  }
}

class _Editor extends StatelessWidget {
  final BoardNotes notes;
  final String boardId;
  const _Editor({required this.notes, required this.boardId});

  @override
  Widget build(BuildContext context) {
    final lines = notes.content.split('\n');
    // The last split element is empty when content ends with a newline; the
    // editor still shows that as a final (empty) line.
    final lineCount = lines.length;
    final wordCount = notes.content
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(fileName: notes.fileName),
        const Divider(height: 1, color: MonokaiTheme.divider),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Gutter(lineCount: lineCount),
              const VerticalDivider(width: 1, color: MonokaiTheme.divider),
              Expanded(child: _Body(lines: lines)),
              // The board ledger, as a clearly-labeled right column so the
              // editor keeps its full height — Swift's
              // `HStack { editorContent; BoardNotesLedgerView(...) }`.
              const VerticalDivider(width: 1, color: MonokaiTheme.divider),
              SizedBox(
                width: _ledgerWidth,
                child: ParityNotesLedger(boardId: boardId),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: MonokaiTheme.divider),
        _StatusBar(lineCount: lineCount, wordCount: wordCount),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  final String fileName;
  const _Toolbar({required this.fileName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: MonokaiTheme.surface,
      child: Row(
        children: [
          const Icon(Icons.description, size: 13, color: MonokaiTheme.green),
          const SizedBox(width: 8),
          Text(fileName,
              style: MonokaiTheme.labelMedium
                  .copyWith(color: MonokaiTheme.foreground)),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down,
              size: 12, color: MonokaiTheme.comment),
          const Spacer(),
          // Saved state indicator.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    color: MonokaiTheme.green, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text('Saved', style: MonokaiTheme.labelSmall),
            ],
          ),
          const SizedBox(width: 12),
          const Icon(Icons.save_alt, size: 14, color: MonokaiTheme.comment),
        ],
      ),
    );
  }
}

class _Gutter extends StatelessWidget {
  final int lineCount;
  const _Gutter({required this.lineCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      color: MonokaiTheme.background,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 1; i <= lineCount; i++)
            Padding(
              padding: const EdgeInsets.only(right: 10, bottom: 2),
              child: Text('$i',
                  style: MonokaiTheme.codeSmall
                      .copyWith(color: MonokaiTheme.textDisabled)),
            ),
        ],
      ),
    );
  }
}

/// The editor body, rendered as monospaced lines with light markdown coloring
/// (headings cyan, blockquotes/list markers muted) to match the SwiftUI
/// syntax-highlighted notes editor.
class _Body extends StatelessWidget {
  final List<String> lines;
  const _Body({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MonokaiTheme.surfaceLighter,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                line.isEmpty ? ' ' : line,
                style: MonokaiTheme.codeStyle.copyWith(color: _color(line)),
              ),
            ),
        ],
      ),
    );
  }

  static Color _color(String line) {
    final t = line.trimLeft();
    if (t.startsWith('#')) return MonokaiTheme.cyan; // heading
    if (t.startsWith('>')) return MonokaiTheme.comment; // blockquote
    if (t.startsWith('- ') || RegExp(r'^\d+\.\s').hasMatch(t)) {
      return MonokaiTheme.green; // list item marker tint
    }
    return MonokaiTheme.foreground;
  }
}

class _StatusBar extends StatelessWidget {
  final int lineCount;
  final int wordCount;
  const _StatusBar({required this.lineCount, required this.wordCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: MonokaiTheme.surface,
      child: Row(
        children: [
          Text('Ln 1, Col 1',
              style: MonokaiTheme.codeSmall
                  .copyWith(color: MonokaiTheme.comment)),
          const SizedBox(width: 14),
          Text('$lineCount lines',
              style: MonokaiTheme.codeSmall
                  .copyWith(color: MonokaiTheme.comment)),
          const SizedBox(width: 14),
          Text('$wordCount words',
              style: MonokaiTheme.codeSmall
                  .copyWith(color: MonokaiTheme.comment)),
          const Spacer(),
          Text('UTF-8',
              style: MonokaiTheme.codeSmall
                  .copyWith(color: MonokaiTheme.comment)),
        ],
      ),
    );
  }
}
