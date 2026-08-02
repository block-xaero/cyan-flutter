// widgets/parity/parity_lens_surface.dart
//
// PARITY port of the Lens ASK path — `AIViewModel.lensSearch` driving the
// SwiftUI Lens surface. The shape that matters here is the one the macOS app
// settled on (WorkspaceViewNew: "the always-on Lens chat *dock* stays gone;
// this is the on-demand intelligence surface"):
//
//   • The lens is INVOKED. Until someone asks for it there is no panel in the
//     tree and NOTHING has been read from the engine — a dock would have read
//     on mount. Dismiss and it is gone again.
//   • An ask is a round-trip with a visible PENDING state (`isProcessing` →
//     "Searching…") and then an ANSWER: the ranked hits, the way
//     `LensSearchResult.results` carries name + type + snippet.
//   • A failed ask surfaces the engine's refusal (`errorMessage` /
//     `.lensSearchError`) and offers a retry — it never sits on the spinner.
//
// The answer comes through the `CyanBackend` seam and nowhere else: the boards
// the engine knows (`loadAllBoards`) and the signal it is holding
// (`loadLensIntelligence`). This widget never touches `CyanFFI` directly —
// that is the parity rule.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/cyan_backend.dart';
import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';

// ---------------------------------------------------------------------------
// The answer
// ---------------------------------------------------------------------------

/// The lens could not answer. Carries the engine's own words — the surface
/// never invents a reason and never dresses an outage up as an empty result.
class LensRefused implements Exception {
  final String message;
  const LensRefused(this.message);

  @override
  String toString() => message;
}

/// What a hit IS — a tint + a pill, so a board never reads like a nudge.
enum LensHitKind { board, nudge, ask, decision, note }

extension LensHitKindX on LensHitKind {
  String get label => switch (this) {
        LensHitKind.board => 'board',
        LensHitKind.nudge => 'nudge',
        LensHitKind.ask => 'ask',
        LensHitKind.decision => 'decision',
        LensHitKind.note => 'note',
      };

  Color get color => switch (this) {
        LensHitKind.board => MonokaiTheme.cyan,
        LensHitKind.nudge => MonokaiTheme.orange,
        LensHitKind.ask => MonokaiTheme.yellow,
        LensHitKind.decision => MonokaiTheme.green,
        LensHitKind.note => MonokaiTheme.purple,
      };
}

/// One row of an answer — the shape of a `LensResultItem`.
@immutable
class LensHit {
  final LensHitKind kind;
  final String name;
  final String? snippet;

  const LensHit({required this.kind, required this.name, this.snippet});
}

/// One answer: the headline the lens leads with, and the hits behind it.
@immutable
class LensAnswer {
  final String title;
  final List<LensHit> hits;

  const LensAnswer(this.title, {this.hits = const []});
}

// ---------------------------------------------------------------------------
// The ask
// ---------------------------------------------------------------------------

/// How many hits the panel shows before it says so.
const int _hitLimit = 8;

/// Ask the lens one question. Throws [LensRefused] when the lens cannot
/// answer; any other seam failure propagates as-is so the panel can surface it
/// verbatim rather than swallowing it.
Future<LensAnswer> askLens(CyanBackend backend, String question) async {
  final terms = _terms(question);
  if (terms.isEmpty) {
    throw const LensRefused('ask the lens something it can look for');
  }

  final boards = await backend.loadAllBoards();
  final lens = await backend.loadLensIntelligence();

  // An unreachable lens is an ERROR, never a thin-looking feed. The SwiftUI
  // view-model is explicit about this: no cached samples dressed up as live.
  if (!lens.connected) throw const LensRefused('the lens is offline');

  final ranked = <({int score, LensHit hit})>[];
  void consider(String haystack, LensHit hit) {
    final score = _score(haystack, terms);
    if (score > 0) ranked.add((score: score, hit: hit));
  }

  for (final b in boards) {
    consider(
      '${b.board.name} ${b.workspace.name} ${b.group.name} '
      '${b.board.labels.join(' ')}',
      LensHit(
        kind: LensHitKind.board,
        name: b.board.name,
        snippet: '${b.group.name} › ${b.workspace.name}',
      ),
    );
  }
  for (final n in lens.nudges) {
    consider(
      '${n.title} ${n.detail} ${n.boardLabel}',
      LensHit(
        kind: LensHitKind.nudge,
        name: n.title,
        snippet: '${n.boardLabel} · ${n.ageLabel}',
      ),
    );
  }
  for (final a in lens.asks) {
    consider(
      '${a.question} ${a.asker} ${a.assignee} ${a.answer ?? ''}',
      LensHit(
        kind: LensHitKind.ask,
        name: a.question,
        snippet: '${a.asker} → ${a.assignee} · ${a.status.label}',
      ),
    );
  }
  for (final d in lens.decisions) {
    consider(
      '${d.content} ${d.rationale ?? ''} ${d.decider}',
      LensHit(
        kind: LensHitKind.decision,
        name: d.content,
        snippet: '${d.decider} · ${d.ageLabel}',
      ),
    );
  }

  ranked.sort((a, b) => b.score.compareTo(a.score));
  final shown = [for (final r in ranked.take(_hitLimit)) r.hit];

  if (ranked.isEmpty) {
    return LensAnswer('Nothing matches "${question.trim()}"');
  }
  return LensAnswer(
    '${ranked.length} match${ranked.length == 1 ? '' : 'es'} for '
    '"${question.trim()}"'
    // Never let a cap read as "that was everything".
    '${ranked.length > shown.length ? ' · showing ${shown.length}' : ''}',
    hits: shown,
  );
}

/// The words worth matching on. There is no query planner behind this seam, so
/// the search is honest about being a word match over what the engine holds.
const Set<String> _stopWords = {
  'the', 'and', 'for', 'with', 'what', 'whats', 'who', 'how', 'why', 'are',
  'was', 'has', 'have', 'does', 'did', 'can', 'you', 'our', 'any', 'all',
  'from', 'that', 'this', 'there', 'when', 'where', 'which', 'into', 'about',
  'not', 'but', 'its', 'his', 'her', 'them', 'they', 'still', 'been', 'get',
};

List<String> _terms(String query) => [
      for (final word in query.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
        if (word.length > 2 && !_stopWords.contains(word)) word
    ];

int _score(String haystack, List<String> terms) {
  final hay = haystack.toLowerCase();
  var score = 0;
  for (final term in terms) {
    if (hay.contains(term)) score++;
  }
  return score;
}

// ---------------------------------------------------------------------------
// The surface — a host with NO lens in it until one is asked for
// ---------------------------------------------------------------------------

/// Wraps a workspace surface with the on-demand lens: a single invoke
/// affordance, and — only once it is used — the ask panel over the content.
class ParityLensSurface extends StatefulWidget {
  final Widget child;

  /// Start invoked (a rail door that lands straight on the lens).
  final bool invoked;

  const ParityLensSurface({
    super.key,
    required this.child,
    this.invoked = false,
  });

  @override
  State<ParityLensSurface> createState() => _ParityLensSurfaceState();
}

class _ParityLensSurfaceState extends State<ParityLensSurface> {
  late bool _invoked = widget.invoked;

  void _invoke() => setState(() => _invoked = true);
  void _dismiss() => setState(() => _invoked = false);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (!_invoked)
          Positioned(top: 12, right: 16, child: _InvokeButton(onTap: _invoke)),
        if (_invoked) ...[
          // Anywhere off the panel dismisses it — the lens is a visit, not a
          // wall of the room.
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('lens-scrim'),
              behavior: HitTestBehavior.opaque,
              onTap: _dismiss,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
            ),
          ),
          Positioned(
            top: 12,
            right: 16,
            bottom: 12,
            width: 520,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _dismiss,
              },
              child: LensAskPanel(onDismiss: _dismiss),
            ),
          ),
        ],
      ],
    );
  }
}

class _InvokeButton extends StatelessWidget {
  final VoidCallback onTap;
  const _InvokeButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('lens-invoke'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: MonokaiTheme.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(6),
          border:
              Border.all(color: MonokaiTheme.purple.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 13, color: MonokaiTheme.purple),
            const SizedBox(width: 6),
            Text('Ask Lens',
                style: MonokaiTheme.labelMedium
                    .copyWith(color: MonokaiTheme.foreground)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The panel — one ask at a time, each with its own pending/answer/error
// ---------------------------------------------------------------------------

class _LensTurn {
  final int id;
  final String question;
  bool pending = false;
  LensAnswer? answer;
  String? error;

  _LensTurn({required this.id, required this.question});
}

class LensAskPanel extends ConsumerStatefulWidget {
  final VoidCallback? onDismiss;
  const LensAskPanel({super.key, this.onDismiss});

  @override
  ConsumerState<LensAskPanel> createState() => _LensAskPanelState();
}

class _LensAskPanelState extends ConsumerState<LensAskPanel> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_LensTurn> _turns = [];
  int _seq = 0;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _submit([String? raw]) {
    final question = (raw ?? _input.text).trim();
    if (question.isEmpty) return;
    final turn = _LensTurn(id: _seq++, question: question);
    setState(() {
      _turns.add(turn);
      _input.clear();
    });
    _ask(turn);
  }

  Future<void> _ask(_LensTurn turn) async {
    setState(() {
      turn.pending = true;
      turn.answer = null;
      turn.error = null;
    });
    _scrollToLatest();

    final backend = ref.read(cyanBackendProvider);
    try {
      final answer = await askLens(backend, turn.question);
      if (!mounted) return;
      setState(() {
        turn.pending = false;
        turn.answer = answer;
      });
    } catch (e) {
      // The ask NEVER parks on the spinner: whatever the seam threw becomes a
      // visible refusal with a retry.
      if (!mounted) return;
      setState(() {
        turn.pending = false;
        turn.error = e is LensRefused ? e.message : '$e';
      });
    }
    _scrollToLatest();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MonokaiTheme.background,
      elevation: 12,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MonokaiTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const Divider(height: 1, color: MonokaiTheme.divider),
            Expanded(
              child: _turns.isEmpty
                  ? const _AskHint()
                  : ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      children: [for (final t in _turns) _turnBlock(t)],
                    ),
            ),
            const Divider(height: 1, color: MonokaiTheme.divider),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 16, color: MonokaiTheme.purple),
          const SizedBox(width: 10),
          Text('Lens', style: MonokaiTheme.titleSmall),
          const Spacer(),
          Text('esc to close', style: MonokaiTheme.labelSmall),
          const SizedBox(width: 10),
          GestureDetector(
            key: const ValueKey('lens-dismiss'),
            onTap: widget.onDismiss,
            child:
                const Icon(Icons.close, size: 16, color: MonokaiTheme.comment),
          ),
        ],
      ),
    );
  }

  Widget _turnBlock(_LensTurn turn) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.chevron_right,
                  size: 14, color: MonokaiTheme.cyan),
              const SizedBox(width: 6),
              Expanded(
                child: Text(turn.question,
                    style: MonokaiTheme.codeSmall
                        .copyWith(color: MonokaiTheme.cyan)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (turn.pending) const _Pending(),
          if (turn.error != null)
            _Refusal(message: turn.error!, onRetry: () => _ask(turn)),
          if (turn.answer != null) _AnswerBlock(answer: turn.answer!),
        ],
      ),
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('lens-input'),
              controller: _input,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              onSubmitted: _submit,
              style: MonokaiTheme.codeSmall
                  .copyWith(color: MonokaiTheme.foreground),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: 'Ask the lens…',
                hintStyle: MonokaiTheme.codeSmall
                    .copyWith(color: MonokaiTheme.comment),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            key: const ValueKey('lens-send'),
            onTap: _submit,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: MonokaiTheme.purple.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.arrow_upward,
                  size: 14, color: MonokaiTheme.purple),
            ),
          ),
        ],
      ),
    );
  }
}

class _AskHint extends StatelessWidget {
  const _AskHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome,
                size: 30, color: MonokaiTheme.comment),
            const SizedBox(height: 12),
            Text('Ask the lens',
                style: MonokaiTheme.titleSmall
                    .copyWith(color: MonokaiTheme.textMuted)),
            const SizedBox(height: 6),
            Text(
              'Plain language, across the boards you can see and the nudges, '
              'asks and decisions the lens is holding.',
              textAlign: TextAlign.center,
              style: MonokaiTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _Pending extends StatelessWidget {
  const _Pending();

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('lens-pending'),
      children: [
        const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: MonokaiTheme.purple),
        ),
        const SizedBox(width: 10),
        Text('Asking Lens…', style: MonokaiTheme.labelMedium),
      ],
    );
  }
}

class _Refusal extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _Refusal({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('lens-error'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MonokaiTheme.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 14, color: MonokaiTheme.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Lens failed — $message',
                style: MonokaiTheme.bodySmall
                    .copyWith(color: MonokaiTheme.foreground)),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            key: const ValueKey('lens-retry'),
            onTap: onRetry,
            child: Text('Retry',
                style: MonokaiTheme.labelMedium
                    .copyWith(color: MonokaiTheme.cyan)),
          ),
        ],
      ),
    );
  }
}

class _AnswerBlock extends StatelessWidget {
  final LensAnswer answer;
  const _AnswerBlock({required this.answer});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('lens-answer'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MonokaiTheme.selection,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(answer.title,
              style: MonokaiTheme.labelMedium.copyWith(
                  color: MonokaiTheme.foreground,
                  fontWeight: FontWeight.w600)),
          for (final hit in answer.hits) ...[
            const SizedBox(height: 8),
            _HitRow(hit: hit),
          ],
        ],
      ),
    );
  }
}

class _HitRow extends StatelessWidget {
  final LensHit hit;
  const _HitRow({required this.hit});

  @override
  Widget build(BuildContext context) {
    final snippet = hit.snippet;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: hit.kind.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(hit.kind.label,
              style: MonokaiTheme.labelSmall.copyWith(color: hit.kind.color)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hit.name,
                  style: MonokaiTheme.bodySmall
                      .copyWith(color: MonokaiTheme.foreground)),
              if (snippet != null && snippet.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(snippet, style: MonokaiTheme.labelSmall),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
