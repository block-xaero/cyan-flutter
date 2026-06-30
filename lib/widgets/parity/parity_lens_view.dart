// widgets/parity/parity_lens_view.dart
//
// PARITY port of the SwiftUI `LensAIView` (PARITY_TRACKER row 10): the Lens AI
// intelligence panel — the differentiator surface that sits below the
// operational approvals. A header (title + connection status), an "Intelligence"
// section band, a four-way tab control (Nudges · Asks · Decisions · Graph), and
// the per-tab cards:
//   • Nudges    — proactive focus prompts (icon tile + title + age + detail +
//                 owning board + a green "Resolve" action).
//   • Asks      — open questions (asker → assignee + age + status; answered
//                 asks show the answer + answerer; open asks get Answer/Dismiss).
//   • Decisions — recorded choices (content + rationale + decider + age +
//                 agree/disagree/comment reaction counts).
//   • Graph     — the knowledge-graph viz (a parity placeholder here).
//
// Driven ENTIRELY through the `CyanBackend` seam (via `lensProvider`). This
// widget never touches `CyanFFI` directly — that is the parity rule.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';

enum LensTab { nudges, asks, decisions, graph }

extension LensTabX on LensTab {
  String get label => switch (this) {
        LensTab.nudges => 'Nudges',
        LensTab.asks => 'Asks',
        LensTab.decisions => 'Decisions',
        LensTab.graph => 'Graph',
      };

  IconData get icon => switch (this) {
        LensTab.nudges => Icons.notifications_active,
        LensTab.asks => Icons.help_outline,
        LensTab.decisions => Icons.verified,
        LensTab.graph => Icons.hub,
      };

  Color get color => switch (this) {
        LensTab.nudges => MonokaiTheme.orange,
        LensTab.asks => MonokaiTheme.cyan,
        LensTab.decisions => MonokaiTheme.green,
        LensTab.graph => MonokaiTheme.purple,
      };
}

class ParityLensView extends ConsumerStatefulWidget {
  /// Resolve a nudge — UI-only here; the host wires the graph mutation.
  final void Function(LensNudge)? onResolveNudge;

  /// Answer / dismiss an ask — UI-only here.
  final void Function(LensAsk)? onAnswerAsk;

  /// React to a decision (agree/disagree) — UI-only here.
  final void Function(LensDecision)? onReactDecision;

  const ParityLensView({
    super.key,
    this.onResolveNudge,
    this.onAnswerAsk,
    this.onReactDecision,
  });

  @override
  ConsumerState<ParityLensView> createState() => _ParityLensViewState();
}

class _ParityLensViewState extends ConsumerState<ParityLensView> {
  LensTab _tab = LensTab.nudges;

  @override
  Widget build(BuildContext context) {
    final lensAsync = ref.watch(lensIntelligenceProvider);

    return Material(
      color: MonokaiTheme.background,
      child: lensAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MonokaiTheme.cyan),
        ),
        error: (e, _) => Center(
          child: Text('Failed to load Lens: $e',
              style:
                  MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.red)),
        ),
        data: (lens) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(connected: lens.connected),
            const Divider(height: 1, color: MonokaiTheme.divider),
            _IntelligenceBand(nudgeCount: lens.nudges.length),
            _Tabs(
              selected: _tab,
              nudgeCount: lens.nudges.length,
              onSelect: (t) => setState(() => _tab = t),
            ),
            const Divider(height: 1, color: MonokaiTheme.divider),
            Expanded(child: _body(lens)),
          ],
        ),
      ),
    );
  }

  Widget _body(LensIntelligence lens) {
    switch (_tab) {
      case LensTab.nudges:
        if (lens.nudges.isEmpty) {
          return const _Empty(
              icon: Icons.check_circle,
              title: 'All clear!',
              detail: 'No nudges at the moment');
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final n in lens.nudges)
              _NudgeCard(nudge: n, onResolve: widget.onResolveNudge),
          ],
        );
      case LensTab.asks:
        if (lens.asks.isEmpty) {
          return const _Empty(
              icon: Icons.help_outline,
              title: 'No open questions',
              detail: 'All questions have been answered');
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final a in lens.asks)
              _AskCard(ask: a, onAnswer: widget.onAnswerAsk),
          ],
        );
      case LensTab.decisions:
        if (lens.decisions.isEmpty) {
          return const _Empty(
              icon: Icons.verified,
              title: 'No recent decisions',
              detail: "Decisions will appear here as they're made");
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final d in lens.decisions)
              _DecisionCard(decision: d, onReact: widget.onReactDecision),
          ],
        );
      case LensTab.graph:
        return const _Empty(
            icon: Icons.hub,
            title: 'Knowledge graph',
            detail: 'The graph view renders in the native Lens surface');
    }
  }
}

class _Header extends StatelessWidget {
  final bool connected;
  const _Header({required this.connected});

  @override
  Widget build(BuildContext context) {
    final dot = connected ? MonokaiTheme.green : MonokaiTheme.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 18, color: MonokaiTheme.purple),
          const SizedBox(width: 10),
          Text('Lens AI', style: MonokaiTheme.titleSmall),
          const Spacer(),
          Container(width: 8, height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(connected ? 'Connected' : 'Disconnected',
              style: MonokaiTheme.labelSmall.copyWith(color: dot)),
          const SizedBox(width: 12),
          const Icon(Icons.refresh, size: 16, color: MonokaiTheme.comment),
        ],
      ),
    );
  }
}

/// The "Intelligence" section band — keeps the differentiator distinct from the
/// operational run-approvals surface above it (parity with the SwiftUI header).
class _IntelligenceBand extends StatelessWidget {
  final int nudgeCount;
  const _IntelligenceBand({required this.nudgeCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: MonokaiTheme.surface.withValues(alpha: 0.4),
      child: Row(
        children: [
          const Icon(Icons.psychology, size: 13, color: MonokaiTheme.purple),
          const SizedBox(width: 8),
          Text('Intelligence',
              style: MonokaiTheme.labelMedium
                  .copyWith(color: MonokaiTheme.foreground)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Nudges · Asks · Decisions',
                style: MonokaiTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  final LensTab selected;
  final int nudgeCount;
  final void Function(LensTab) onSelect;

  const _Tabs({
    required this.selected,
    required this.nudgeCount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final t in LensTab.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _TabChip(
                tab: t,
                selected: t == selected,
                badge: t == LensTab.nudges ? nudgeCount : 0,
                onTap: () => onSelect(t),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final LensTab tab;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _TabChip({
    required this.tab,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = tab.color;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        key: ValueKey('lens-tab-${tab.label}'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.5)
                : MonokaiTheme.border.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tab.icon,
                size: 12,
                color: selected ? color : MonokaiTheme.textMuted),
            const SizedBox(width: 6),
            Text(tab.label,
                style: MonokaiTheme.labelMedium.copyWith(
                    color: selected ? color : MonokaiTheme.textMuted)),
            if (badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$badge',
                    style: MonokaiTheme.labelSmall
                        .copyWith(color: MonokaiTheme.background)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NudgeCard extends StatelessWidget {
  final LensNudge nudge;
  final void Function(LensNudge)? onResolve;

  const _NudgeCard({required this.nudge, this.onResolve});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MonokaiTheme.selection,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: MonokaiTheme.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.notifications_active,
                size: 16, color: MonokaiTheme.orange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(nudge.title,
                          style: MonokaiTheme.labelMedium.copyWith(
                              color: MonokaiTheme.foreground,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(nudge.ageLabel, style: MonokaiTheme.labelSmall),
                  ],
                ),
                const SizedBox(height: 4),
                Text(nudge.detail,
                    style: MonokaiTheme.bodySmall, maxLines: 3,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.dashboard_outlined,
                        size: 11, color: MonokaiTheme.comment),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(nudge.boardLabel,
                          style: MonokaiTheme.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const Spacer(),
                    _ResolveButton(onTap: () => onResolve?.call(nudge)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResolveButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ResolveButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: MonokaiTheme.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 10, color: MonokaiTheme.green),
            const SizedBox(width: 4),
            Text('Resolve',
                style: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.green)),
          ],
        ),
      ),
    );
  }
}

class _AskCard extends StatelessWidget {
  final LensAsk ask;
  final void Function(LensAsk)? onAnswer;

  const _AskCard({required this.ask, this.onAnswer});

  @override
  Widget build(BuildContext context) {
    final answered = ask.status == AskStatus.answered;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MonokaiTheme.selection,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ask.question,
              style: MonokaiTheme.bodySmall
                  .copyWith(color: MonokaiTheme.foreground)),
          const SizedBox(height: 8),
          // Asker → assignee · age · status.
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _iconLabel(Icons.person, ask.asker),
              _iconLabel(Icons.arrow_forward, ask.assignee),
              _iconLabel(Icons.schedule, ask.ageLabel),
              _StatusPill(status: ask.status),
            ],
          ),
          if (answered && ask.answer != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: MonokaiTheme.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.chat_bubble,
                      size: 12, color: MonokaiTheme.green),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ask.answer!, style: MonokaiTheme.bodySmall),
                        if (ask.answerer != null) ...[
                          const SizedBox(height: 2),
                          Text('— ${ask.answerer}',
                              style: MonokaiTheme.labelSmall),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else if (!answered) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _pillButton(Icons.chat_bubble_outline, 'Answer',
                    MonokaiTheme.cyan, () => onAnswer?.call(ask)),
                const SizedBox(width: 8),
                _pillButton(Icons.close, 'Dismiss', MonokaiTheme.comment, null),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static Widget _iconLabel(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: MonokaiTheme.comment),
        const SizedBox(width: 4),
        Text(text, style: MonokaiTheme.labelSmall),
      ],
    );
  }

  static Widget _pillButton(
      IconData icon, String label, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: MonokaiTheme.labelSmall.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final AskStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      AskStatus.open => MonokaiTheme.yellow,
      AskStatus.answered => MonokaiTheme.green,
      AskStatus.stale => MonokaiTheme.comment,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(status.label,
          style: MonokaiTheme.labelSmall.copyWith(color: color)),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  final LensDecision decision;
  final void Function(LensDecision)? onReact;

  const _DecisionCard({required this.decision, this.onReact});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MonokaiTheme.selection,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(decision.content,
              style: MonokaiTheme.bodySmall
                  .copyWith(color: MonokaiTheme.foreground)),
          if (decision.rationale != null) ...[
            const SizedBox(height: 4),
            Text(decision.rationale!,
                style: MonokaiTheme.labelSmall, maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person, size: 10, color: MonokaiTheme.comment),
              const SizedBox(width: 4),
              Flexible(
                child: Text(decision.decider,
                    style: MonokaiTheme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const Spacer(),
              Text(decision.ageLabel, style: MonokaiTheme.labelSmall),
            ],
          ),
          if (decision.agreeCount > 0 ||
              decision.disagreeCount > 0 ||
              decision.commentCount > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _react(Icons.thumb_up, '${decision.agreeCount}',
                    MonokaiTheme.green, () => onReact?.call(decision)),
                if (decision.disagreeCount > 0)
                  _react(Icons.thumb_down, '${decision.disagreeCount}',
                      MonokaiTheme.red, () => onReact?.call(decision)),
                if (decision.commentCount > 0)
                  _react(Icons.chat_bubble_outline,
                      '${decision.commentCount}', MonokaiTheme.comment, null),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static Widget _react(
      IconData icon, String count, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(count, style: MonokaiTheme.labelSmall.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _Empty(
      {required this.icon, required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: MonokaiTheme.comment),
          const SizedBox(height: 12),
          Text(title,
              style: MonokaiTheme.titleSmall
                  .copyWith(color: MonokaiTheme.textMuted)),
          const SizedBox(height: 4),
          Text(detail, style: MonokaiTheme.labelMedium),
        ],
      ),
    );
  }
}
