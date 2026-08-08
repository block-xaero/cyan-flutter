// widgets/parity/parity_notes_structuring.dart
//
// PARITY face — the STRUCTURED-NOTES lane (A4 §1b).
//
// Type a freeform note ("punchy, warm grade, keep it legal, -14 LUFS"); the lens
// structuring lane turns it into TYPED note proposals, each carrying a VERBATIM
// `source_span` of what you actually wrote. Spans it refused to structure come
// back named, with the reason.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Views/NotesStructuringView.swift
//
// TWO INVARIANTS, both carried over deliberately:
//
//   • AUTO-ACCEPT IS OFF. The lens call persists NOTHING. Every proposal is a
//     suggestion the human confirms one at a time, and confirming writes a real
//     typed note through the ENGINE's own note door — so the engine's RBAC and
//     payload validation still run. A lane that wrote on the model's say-so
//     would be the model authoring your board.
//
//   • REJECTIONS ARE SHOWN. A span the lane dropped is displayed with its
//     reason rather than silently vanishing, because "it ignored half my note"
//     and "it told me it ignored half my note" are very different products.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lens/lens_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../providers/lens_console_provider.dart';
import '../../theme/monokai_theme.dart';

/// What has happened to one proposal in this session.
enum ProposalState { pending, confirmed, discarded }

class ParityNotesStructuring extends ConsumerStatefulWidget {
  final String boardId;

  const ParityNotesStructuring({super.key, required this.boardId});

  @override
  ConsumerState<ParityNotesStructuring> createState() =>
      _ParityNotesStructuringState();
}

class _ParityNotesStructuringState
    extends ConsumerState<ParityNotesStructuring> {
  final TextEditingController _draft = TextEditingController();

  NoteStructureResult _result = const NoteStructureResult();
  final Map<String, ProposalState> _states = {};
  bool _busy = false;
  String? _error;
  String? _status;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _structure() async {
    final text = _draft.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final result = await ref
          .read(lensApiProvider)
          .structureNote(boardId: widget.boardId, text: text);
      if (!mounted) return;
      setState(() {
        _result = result;
        _states.clear();
        _busy = false;
        _status = result.isEmpty
            ? 'The lane found nothing to structure in that.'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      // The lens's own words. A structuring lane that fails silently looks
      // exactly like one that found nothing.
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _confirm(NoteProposal p) async {
    setState(() => _busy = true);
    try {
      await ref.read(cyanBackendProvider).notePutScoped(
            p.scope == 'group' ? p.boardId : widget.boardId,
            p.text,
            scope: p.scope,
            kind: p.kind,
          );
      if (!mounted) return;
      setState(() {
        _states[p.proposalId] = ProposalState.confirmed;
        _busy = false;
        _status = 'Wrote a ${p.kind} note.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'That note was refused: $e';
      });
    }
  }

  void _discard(NoteProposal p) =>
      setState(() => _states[p.proposalId] = ProposalState.discarded);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MonokaiTheme.background,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Structure a note', style: MonokaiTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Write it however you think it. The lane proposes typed notes; '
            'nothing is saved until you confirm each one.',
            style: MonokaiTheme.labelMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('structuring.draft'),
            controller: _draft,
            maxLines: 4,
            style:
                MonokaiTheme.codeSmall.copyWith(color: MonokaiTheme.foreground),
            decoration: InputDecoration(
              hintText: 'warm teal-orange look on the endcard, LUT it. '
                  'House rule: -14 LUFS integrated.',
              hintStyle: MonokaiTheme.labelSmall,
              filled: true,
              fillColor: MonokaiTheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: MonokaiTheme.divider),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              key: const ValueKey('structuring.run'),
              onPressed: _busy ? null : _structure,
              style: ElevatedButton.styleFrom(
                backgroundColor: MonokaiTheme.cyan,
                foregroundColor: MonokaiTheme.background,
              ),
              child: Text(_busy ? 'Structuring…' : 'Structure'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                key: const ValueKey('structuring.error'),
                style:
                    MonokaiTheme.labelMedium.copyWith(color: MonokaiTheme.red)),
          ],
          if (_status != null) ...[
            const SizedBox(height: 10),
            Text(_status!,
                key: const ValueKey('structuring.status'),
                style: MonokaiTheme.labelMedium),
          ],
          if (_result.proposals.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Proposals', style: MonokaiTheme.labelLarge),
            const SizedBox(height: 8),
            for (final p in _result.proposals)
              _ProposalCard(
                proposal: p,
                state: _states[p.proposalId] ?? ProposalState.pending,
                busy: _busy,
                onConfirm: () => _confirm(p),
                onDiscard: () => _discard(p),
              ),
          ],
          if (_result.rejected.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Not structured', style: MonokaiTheme.labelLarge),
            const SizedBox(height: 8),
            for (final r in _result.rejected) _RejectedRow(rejected: r),
          ],
        ],
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  final NoteProposal proposal;
  final ProposalState state;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onDiscard;

  const _ProposalCard({
    required this.proposal,
    required this.state,
    required this.busy,
    required this.onConfirm,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final settled = state != ProposalState.pending;
    return Container(
      key: ValueKey('structuring.proposal.${proposal.proposalId}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: switch (state) {
            ProposalState.confirmed =>
              MonokaiTheme.green.withValues(alpha: 0.6),
            ProposalState.discarded => MonokaiTheme.divider,
            ProposalState.pending => MonokaiTheme.cyan.withValues(alpha: 0.35),
          },
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Chip(text: proposal.kind, color: MonokaiTheme.cyan),
              const SizedBox(width: 6),
              _Chip(text: proposal.scope, color: MonokaiTheme.purple),
              const Spacer(),
              Text('${(proposal.confidence * 100).round()}%',
                  style: MonokaiTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(proposal.text,
              style: MonokaiTheme.bodyMedium
                  .copyWith(color: MonokaiTheme.foreground)),
          // THE QUOTING GATE, shown. The span is a verbatim substring of what
          // the operator wrote, so they can see the lane did not invent it.
          if (proposal.sourceSpan != null) ...[
            const SizedBox(height: 6),
            Text('“${proposal.sourceSpan}”',
                key: ValueKey('structuring.span.${proposal.proposalId}'),
                style: MonokaiTheme.labelSmall
                    .copyWith(fontStyle: FontStyle.italic)),
          ],
          if (proposal.rationale != null) ...[
            const SizedBox(height: 4),
            Text(proposal.rationale!, style: MonokaiTheme.labelSmall),
          ],
          const SizedBox(height: 10),
          if (settled)
            Text(
              state == ProposalState.confirmed ? 'Confirmed' : 'Discarded',
              style: MonokaiTheme.labelMedium.copyWith(
                color: state == ProposalState.confirmed
                    ? MonokaiTheme.green
                    : MonokaiTheme.comment,
              ),
            )
          else
            Row(
              children: [
                ElevatedButton(
                  key: ValueKey('structuring.confirm.${proposal.proposalId}'),
                  onPressed: busy ? null : onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MonokaiTheme.green,
                    foregroundColor: MonokaiTheme.background,
                  ),
                  child: const Text('Confirm'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: ValueKey('structuring.discard.${proposal.proposalId}'),
                  onPressed: busy ? null : onDiscard,
                  child: Text('Discard',
                      style: MonokaiTheme.labelMedium
                          .copyWith(color: MonokaiTheme.comment)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RejectedRow extends StatelessWidget {
  final RejectedSpan rejected;
  const _RejectedRow({required this.rejected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.remove_circle_outline,
              size: 13, color: MonokaiTheme.comment),
          const SizedBox(width: 8),
          Expanded(
            child: Text('“${rejected.span}”', style: MonokaiTheme.labelSmall),
          ),
          const SizedBox(width: 8),
          _Chip(text: rejected.reason, color: MonokaiTheme.textMuted),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text, style: MonokaiTheme.labelSmall.copyWith(color: color)),
    );
  }
}
