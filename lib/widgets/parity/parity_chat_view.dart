// widgets/parity/parity_chat_view.dart
//
// PARITY port of the SwiftUI `ChatPanel` / `ChatMessageView` (PARITY_TRACKER
// row 11): the board chat transcript. The SwiftUI app renders a clean,
// "Claude-style" transcript — no avatars, no left/right bubbles; every message
// is left-aligned with a colored author (own = cyan, others = green), a faint
// timestamp, and a markdown-rendered body — over a composer.
//
// Driven ENTIRELY through the `CyanBackend` seam (via `boardChatControllerProvider`,
// which reads `loadChat` and writes `sendChat` / `deleteChat`). This widget
// never touches `CyanFFI` directly — that is the parity rule.
//
// The lane is BOARD-SCOPED: [boardId] is the whole chat address, so the
// composer sends to this board and to no other, and a view with no board id
// cannot send at all.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/board_chat_controller.dart';
import '../../theme/monokai_theme.dart';

class ParityChatView extends ConsumerWidget {
  /// The board whose transcript to show — and the scope every send addresses.
  final String boardId;

  /// The chat's title (board / workspace name).
  final String title;

  /// Fired after a message is SENT (the engine took it), so a host can react.
  /// The transcript itself does not need this — it re-reads the engine.
  final void Function(String)? onSend;

  const ParityChatView({
    super.key,
    this.boardId = 'b-eng-1',
    this.title = 'Render + Review Pipeline',
    this.onSend,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(boardChatControllerProvider(boardId));
    final controller = ref.read(boardChatControllerProvider(boardId).notifier);

    return Material(
      color: MonokaiTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(title: title),
          const Divider(height: 1, color: MonokaiTheme.divider),
          Expanded(
            child: switch (chat) {
              BoardChatState(loading: true) => const Center(
                  child: CircularProgressIndicator(color: MonokaiTheme.cyan),
                ),
              BoardChatState(error: final String e) => Center(
                  child: Text(e,
                      style: MonokaiTheme.bodyMedium
                          .copyWith(color: MonokaiTheme.red)),
                ),
              BoardChatState(isEmpty: true) => const _Empty(),
              _ => ListView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  children: [
                    for (final m in chat.messages)
                      _MessageRow(
                        message: m,
                        // Your own message is yours to remove. The engine
                        // soft-deletes and gossips a tombstone, so the row goes
                        // everywhere it went, not just here.
                        onDelete: m.isOwn && m.id.isNotEmpty
                            ? () => controller.delete(m.id)
                            : null,
                      ),
                  ],
                ),
            },
          ),
          const Divider(height: 1, color: MonokaiTheme.divider),
          _Composer(
            enabled: controller.hasScope,
            onSubmit: (text) async {
              final sent = await controller.send(text);
              if (sent) onSend?.call(text.trim());
              return sent;
            },
          ),
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

  /// Removing this message. Null when it is not this operator's to remove.
  final VoidCallback? onDelete;

  const _MessageRow({required this.message, this.onDelete});

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
              if (onDelete != null) ...[
                const Spacer(),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 14),
                  color: MonokaiTheme.comment,
                  hoverColor: MonokaiTheme.red.withValues(alpha: 0.15),
                  splashRadius: 14,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 22, height: 22),
                  tooltip: 'Delete message',
                ),
              ],
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

/// The composer. A REAL text field — what is typed here is what is sent, and
/// the field only clears once the engine has taken the message.
class _Composer extends StatefulWidget {
  /// Sends [text]; answers whether it was taken. False leaves the draft in
  /// place so a refused send never silently eats what was typed.
  final Future<bool> Function(String text) onSubmit;

  /// False when the lane has no board to send to — the composer says so rather
  /// than accepting text that has nowhere to go.
  final bool enabled;

  const _Composer({required this.onSubmit, this.enabled = true});

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!widget.enabled || _sending) return;
    final text = _controller.text;
    // Whitespace-only is not a message. The seam refuses it too; refusing here
    // as well keeps the composer from clearing a draft that was never sent.
    if (text.trim().isEmpty) return;

    setState(() => _sending = true);
    final sent = await widget.onSubmit(text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (sent) {
      _controller.clear();
      // Keep the caret in the composer — a sent message should not cost focus.
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: MonokaiTheme.selection,
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: MonokaiTheme.border.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      enabled: widget.enabled,
                      style: MonokaiTheme.bodySmall
                          .copyWith(color: MonokaiTheme.foreground),
                      cursorColor: MonokaiTheme.cyan,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText:
                            widget.enabled ? 'Message…' : 'No board selected',
                        hintStyle: MonokaiTheme.bodySmall
                            .copyWith(color: MonokaiTheme.comment),
                      ),
                    ),
                  ),
                  const Icon(Icons.alternate_email,
                      size: 14, color: MonokaiTheme.comment),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Rebuilds with the field so Send reads as live only once there is
          // something to send.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              final live = widget.enabled &&
                  !_sending &&
                  value.text.trim().isNotEmpty;
              return Semantics(
                button: true,
                enabled: live,
                label: 'Send message',
                child: GestureDetector(
                  onTap: _submit,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: live
                          ? MonokaiTheme.cyan
                          : MonokaiTheme.cyan.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.send,
                        size: 16, color: MonokaiTheme.background),
                  ),
                ),
              );
            },
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
