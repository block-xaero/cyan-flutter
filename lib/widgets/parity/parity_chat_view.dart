// widgets/parity/parity_chat_view.dart
//
// PARITY port of the SwiftUI `ChatPanel` / `ChatMessageView` (PARITY_TRACKER
// row 11): the board chat transcript. The SwiftUI app renders a clean,
// "Claude-style" transcript — no avatars, no left/right bubbles; every message
// is left-aligned with a colored author (own = cyan, others = green), a faint
// timestamp, and a markdown-rendered body — over a composer.
//
// Driven ENTIRELY through the `CyanBackend` seam (via `boardChatProvider`). This
// widget never touches `CyanFFI` directly — that is the parity rule.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';

class ParityChatView extends ConsumerWidget {
  /// The board whose transcript to show.
  final String boardId;

  /// The chat's title (board / workspace name).
  final String title;

  /// Sending a composed message — UI-only here; the host wires the relay.
  final void Function(String)? onSend;

  const ParityChatView({
    super.key,
    this.boardId = 'b-eng-1',
    this.title = 'Render + Review Pipeline',
    this.onSend,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatAsync = ref.watch(boardChatProvider(boardId));

    return Material(
      color: MonokaiTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(title: title),
          const Divider(height: 1, color: MonokaiTheme.divider),
          Expanded(
            child: chatAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: MonokaiTheme.cyan),
              ),
              error: (e, _) => Center(
                child: Text('Failed to load chat: $e',
                    style: MonokaiTheme.bodyMedium
                        .copyWith(color: MonokaiTheme.red)),
              ),
              data: (messages) => messages.isEmpty
                  ? const _Empty()
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      children: [
                        for (final m in messages) _MessageRow(message: m),
                      ],
                    ),
            ),
          ),
          const Divider(height: 1, color: MonokaiTheme.divider),
          _Composer(onSend: onSend),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  const _Header({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.forum, size: 18, color: MonokaiTheme.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: MonokaiTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text('Board chat', style: MonokaiTheme.labelSmall),
              ],
            ),
          ),
          // Peer presence pill.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: MonokaiTheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 7, height: 7,
                    decoration: const BoxDecoration(
                        color: MonokaiTheme.green, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('online', style: MonokaiTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final ChatMessage message;
  const _MessageRow({required this.message});

  @override
  Widget build(BuildContext context) {
    final authorColor =
        message.isOwn ? MonokaiTheme.cyan : MonokaiTheme.green;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(message.author,
                  style: MonokaiTheme.labelMedium.copyWith(
                      color: authorColor, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text(message.timeLabel, style: MonokaiTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 4),
          _MarkdownBody(text: message.body),
        ],
      ),
    );
  }
}

/// Light inline markdown: **bold** + `code`. Mirrors the SwiftUI transcript's
/// rendered body without pulling in a full markdown engine.
class _MarkdownBody extends StatelessWidget {
  final String text;
  const _MarkdownBody({required this.text});

  @override
  Widget build(BuildContext context) {
    final base =
        MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.foreground);
    return RichText(
      text: TextSpan(style: base, children: _spans(base)),
    );
  }

  List<InlineSpan> _spans(TextStyle base) {
    final spans = <InlineSpan>[];
    // Tokenize on ** (bold) and ` (code) delimiters.
    final pattern = RegExp(r'(\*\*[^*]+\*\*|`[^`]+`)');
    int last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final tok = m.group(0)!;
      if (tok.startsWith('**')) {
        spans.add(TextSpan(
          text: tok.substring(2, tok.length - 2),
          style: base.copyWith(fontWeight: FontWeight.bold),
        ));
      } else {
        spans.add(TextSpan(
          text: tok.substring(1, tok.length - 1),
          style: MonokaiTheme.codeSmall.copyWith(color: MonokaiTheme.orange),
        ));
      }
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return spans;
  }
}

class _Composer extends StatelessWidget {
  final void Function(String)? onSend;
  const _Composer({this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: MonokaiTheme.selection,
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: MonokaiTheme.border.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Message…',
                        style: MonokaiTheme.bodySmall
                            .copyWith(color: MonokaiTheme.comment)),
                  ),
                  const Icon(Icons.alternate_email,
                      size: 14, color: MonokaiTheme.comment),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => onSend?.call(''),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MonokaiTheme.cyan,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.send,
                  size: 16, color: MonokaiTheme.background),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.forum_outlined,
              size: 40, color: MonokaiTheme.comment),
          const SizedBox(height: 12),
          Text('No messages yet',
              style: MonokaiTheme.titleSmall
                  .copyWith(color: MonokaiTheme.textMuted)),
          const SizedBox(height: 4),
          Text('Start the conversation', style: MonokaiTheme.labelMedium),
        ],
      ),
    );
  }
}
