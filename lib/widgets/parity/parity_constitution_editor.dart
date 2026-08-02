// widgets/parity/parity_constitution_editor.dart
//
// PARITY port of the SwiftUI `ConstitutionEditorView` — the scoped constitution
// editor + authorship surface. Two jobs on one face:
//
//   • READ  — the board's EFFECTIVE constitution: the merged markdown the Lens
//     runs steer by, its chain hash, the preference rows kept apart from it,
//     the contributing count, and the HARD rules the engine classified off the
//     chain (each carrying its note text verbatim).
//   • WRITE — add a scoped house rule: a `constitution` or `preference` note at
//     board or group scope, through the same `notePutScoped` door the
//     structuring surface uses. The ENGINE re-checks authority at the write
//     door — the UI is convenience, the engine gate is truth — so a refusal
//     surfaces here rather than being pre-judged.
//
// Driven ENTIRELY through the `CyanBackend` seam. A write invalidates the
// providers that read it, so what lands on screen is what the engine persisted,
// never a shadow copy of the draft.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Views/ConstitutionEditorView.swift

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../providers/settings_identity_provider.dart';
import '../../theme/monokai_theme.dart';

/// Where a rule is anchored: on this board alone, or on the whole group it
/// sits in (where every board of the group inherits it).
enum RuleScope {
  board('board'),
  group('group');

  const RuleScope(this.slug);
  final String slug;
}

/// Which ledger a rule lands in: a HARD constitution rule, or a soft
/// preference the resolve keeps apart from the constitution.
enum RuleKind {
  constitution('constitution'),
  preference('preference');

  const RuleKind(this.slug);
  final String slug;
}

class ParityConstitutionEditor extends ConsumerStatefulWidget {
  final String boardId;

  const ParityConstitutionEditor({super.key, required this.boardId});

  @override
  ConsumerState<ParityConstitutionEditor> createState() =>
      _ParityConstitutionEditorState();
}

class _ParityConstitutionEditorState
    extends ConsumerState<ParityConstitutionEditor> {
  final TextEditingController _draft = TextEditingController();
  RuleScope _scope = RuleScope.board;
  RuleKind _kind = RuleKind.constitution;
  bool _saving = false;
  String? _savedNotice;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _addRule() async {
    final text = _draft.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);

    final backend = ref.read(cyanBackendProvider);
    // A group rule is anchored on the GROUP, a board rule on the board — write
    // it where the resolve will look for it.
    final anchor = _scope == RuleScope.group
        ? (await ref.read(boardGroupIdProvider(widget.boardId).future) ??
            widget.boardId)
        : widget.boardId;
    await backend.notePutScoped(
      anchor,
      text,
      scope: _scope.slug,
      kind: _kind.slug,
    );

    // Read the rule back off the ENGINE rather than trusting the draft.
    ref.invalidate(constitutionPreviewProvider(widget.boardId));
    ref.invalidate(constitutionHardRulesProvider(widget.boardId));
    ref.invalidate(boardAuthorshipProvider(widget.boardId));

    if (!mounted) return;
    _draft.clear();
    setState(() {
      _saving = false;
      _savedNotice = 'Saved to the ${_scope.slug} ${_kind.slug}.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final previewAsync = ref.watch(constitutionPreviewProvider(widget.boardId));
    final hardAsync = ref.watch(constitutionHardRulesProvider(widget.boardId));
    final authoredAsync = ref.watch(boardAuthorshipProvider(widget.boardId));

    return Material(
      color: MonokaiTheme.background,
      child: previewAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MonokaiTheme.cyan),
        ),
        error: (e, _) => Center(
          child: Text('Failed to resolve the constitution: $e',
              style:
                  MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.red)),
        ),
        data: (resolved) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _EffectiveSection(resolved: resolved),
            const SizedBox(height: 16),
            _HardRules(
              rules: hardAsync.asData?.value.hard ?? const <HardRule>[],
            ),
            const SizedBox(height: 16),
            _RuleEditor(
              controller: _draft,
              scope: _scope,
              kind: _kind,
              saving: _saving,
              savedNotice: _savedNotice,
              onScope: (s) => setState(() => _scope = s),
              onKind: (k) => setState(() => _kind = k),
              onAdd: _addRule,
            ),
            const SizedBox(height: 16),
            _Authorship(
              notes: authoredAsync.asData?.value ?? const <CyanNote>[],
            ),
          ],
        ),
      ),
    );
  }
}

// MARK: - Effective constitution

class _EffectiveSection extends StatelessWidget {
  final ResolvedConstitution resolved;
  const _EffectiveSection({required this.resolved});

  @override
  Widget build(BuildContext context) {
    final empty = resolved.markdown.isEmpty && resolved.preferences.isEmpty;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Effective constitution',
                  style: MonokaiTheme.titleSmall
                      .copyWith(color: MonokaiTheme.foreground)),
              const Spacer(),
              if (resolved.hash.isNotEmpty)
                Text(
                  '#${resolved.hash.substring(0, resolved.hash.length.clamp(0, 8))}',
                  key: const ValueKey('constitution-hash'),
                  style: MonokaiTheme.codeSmall
                      .copyWith(color: MonokaiTheme.comment),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (resolved.error != null)
            Text(resolved.error!,
                style:
                    MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.red))
          else if (empty)
            Text('No rules yet — the board runs on the plugin defaults.',
                style: MonokaiTheme.bodySmall
                    .copyWith(color: MonokaiTheme.comment))
          else ...[
            if (resolved.markdown.isNotEmpty)
              _Markdown(
                key: const ValueKey('constitution-markdown'),
                text: resolved.markdown,
              ),
            if (resolved.preferences.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Preferences (soft)',
                  style: MonokaiTheme.labelMedium
                      .copyWith(color: MonokaiTheme.comment)),
              const SizedBox(height: 4),
              _Markdown(
                key: const ValueKey('constitution-preferences'),
                text: resolved.preferences,
                muted: true,
              ),
            ],
          ],
          if (resolved.contributing.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('${resolved.contributing.length} contributing note(s)',
                style: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.comment)),
          ],
        ],
      ),
    );
  }
}

/// The merged markdown, line by line: `##` sections cyan, the precedence header
/// muted, everything else the rule text as the engine merged it.
class _Markdown extends StatelessWidget {
  final String text;
  final bool muted;

  const _Markdown({super.key, required this.text, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              line,
              style: MonokaiTheme.bodySmall.copyWith(color: _color(line)),
            ),
          ),
      ],
    );
  }

  Color _color(String line) {
    final t = line.trimLeft();
    if (t.startsWith('#')) return MonokaiTheme.cyan;
    if (t.startsWith('Precedence:')) return MonokaiTheme.comment;
    return muted ? MonokaiTheme.textSecondary : MonokaiTheme.foreground;
  }
}

// MARK: - Hard rules

class _HardRules extends StatelessWidget {
  final List<HardRule> rules;
  const _HardRules({required this.rules});

  @override
  Widget build(BuildContext context) {
    if (rules.isEmpty) return const SizedBox.shrink();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel, size: 13, color: MonokaiTheme.red),
              const SizedBox(width: 6),
              Flexible(
                child: Text('Hard rules — a run may not trade these away',
                    style: MonokaiTheme.labelMedium
                        .copyWith(color: MonokaiTheme.foreground)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final rule in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: MonokaiTheme.red.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      rule.category.isEmpty ? 'hard' : rule.category,
                      style: MonokaiTheme.labelSmall
                          .copyWith(color: MonokaiTheme.red),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(rule.text,
                        style: MonokaiTheme.bodySmall
                            .copyWith(color: MonokaiTheme.foreground)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// MARK: - Write a rule

class _RuleEditor extends StatelessWidget {
  final TextEditingController controller;
  final RuleScope scope;
  final RuleKind kind;
  final bool saving;
  final String? savedNotice;
  final ValueChanged<RuleScope> onScope;
  final ValueChanged<RuleKind> onKind;
  final VoidCallback onAdd;

  const _RuleEditor({
    required this.controller,
    required this.scope,
    required this.kind,
    required this.saving,
    required this.savedNotice,
    required this.onScope,
    required this.onKind,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      tint: MonokaiTheme.surface.withValues(alpha: 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add a house rule',
              style: MonokaiTheme.labelMedium
                  .copyWith(color: MonokaiTheme.foreground)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: MonokaiTheme.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: MonokaiTheme.comment.withValues(alpha: 0.3)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: TextField(
              key: const ValueKey('constitution-rule-field'),
              controller: controller,
              minLines: 2,
              maxLines: 4,
              style: MonokaiTheme.bodySmall
                  .copyWith(color: MonokaiTheme.foreground),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: 'e.g. Deliver every master at 24 fps.',
                hintStyle: MonokaiTheme.bodySmall
                    .copyWith(color: MonokaiTheme.comment),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Segments<RuleScope>(
                values: RuleScope.values,
                selected: scope,
                label: (s) => s.slug,
                keyFor: (s) => ValueKey('constitution-scope-${s.slug}'),
                onChanged: onScope,
              ),
              const SizedBox(width: 10),
              _Segments<RuleKind>(
                values: RuleKind.values,
                selected: kind,
                label: (k) => k.slug,
                keyFor: (k) => ValueKey('constitution-kind-${k.slug}'),
                onChanged: onKind,
              ),
              const Spacer(),
              _PillButton(
                key: const ValueKey('constitution-add-rule'),
                label: saving ? 'Saving…' : 'Add rule',
                tint: MonokaiTheme.green,
                onTap: saving ? null : onAdd,
              ),
            ],
          ),
          if (savedNotice != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.check_circle,
                    size: 12, color: MonokaiTheme.green),
                const SizedBox(width: 6),
                Text(savedNotice!,
                    key: const ValueKey('constitution-saved'),
                    style: MonokaiTheme.labelSmall
                        .copyWith(color: MonokaiTheme.green)),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'The engine re-checks who may write at the door — a refusal comes '
            'back from it, not from this screen.',
            style:
                MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.comment),
          ),
        ],
      ),
    );
  }
}

// MARK: - Authorship

class _Authorship extends StatelessWidget {
  final List<CyanNote> notes;
  const _Authorship({required this.notes});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Board notes — authorship',
              style: MonokaiTheme.labelMedium
                  .copyWith(color: MonokaiTheme.foreground)),
          const SizedBox(height: 8),
          if (notes.isEmpty)
            Text('No notes yet.',
                style: MonokaiTheme.bodySmall
                    .copyWith(color: MonokaiTheme.comment)),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: MonokaiTheme.cyan.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(note.kind,
                            style: MonokaiTheme.labelSmall
                                .copyWith(color: MonokaiTheme.cyan)),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        note.authorName.isEmpty ? '—' : note.authorName,
                        style: MonokaiTheme.labelSmall
                            .copyWith(color: MonokaiTheme.foreground),
                      ),
                      if ((note.authorRole ?? '').isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text('· ${note.authorRole}',
                            style: MonokaiTheme.labelSmall
                                .copyWith(color: MonokaiTheme.yellow)),
                      ],
                      const Spacer(),
                      Text(note.scope,
                          style: MonokaiTheme.labelSmall
                              .copyWith(color: MonokaiTheme.comment)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(note.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MonokaiTheme.bodySmall
                          .copyWith(color: MonokaiTheme.foreground)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// MARK: - Shared pieces

class _Card extends StatelessWidget {
  final Widget child;
  final Color? tint;
  const _Card({required this.child, this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint ?? MonokaiTheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

class _Segments<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final Key Function(T) keyFor;
  final ValueChanged<T> onChanged;

  const _Segments({
    required this.values,
    required this.selected,
    required this.label,
    required this.keyFor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: MonokaiTheme.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in values)
            GestureDetector(
              key: keyFor(v),
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(v),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: v == selected
                      ? MonokaiTheme.cyan.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  label(v),
                  style: MonokaiTheme.labelSmall.copyWith(
                    color:
                        v == selected ? MonokaiTheme.cyan : MonokaiTheme.comment,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final Color tint;
  final VoidCallback? onTap;

  const _PillButton({
    super.key,
    required this.label,
    required this.tint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color:
              enabled ? tint.withValues(alpha: 0.9) : MonokaiTheme.surfaceLight,
          borderRadius: BorderRadius.circular(6),
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
