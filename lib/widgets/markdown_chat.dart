// widgets/markdown_chat.dart
// Real-time markdown chat input and message display

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MARKDOWN CHAT INPUT
// ═══════════════════════════════════════════════════════════════════════════

class MarkdownChatInput extends StatefulWidget {
  final ValueChanged<String> onSend;
  final String hintText;
  final List<String> attachments;
  final VoidCallback? onAttach;

  const MarkdownChatInput({
    super.key,
    required this.onSend,
    this.hintText = 'Type a message... (Markdown supported)',
    this.attachments = const [],
    this.onAttach,
  });

  @override
  State<MarkdownChatInput> createState() => _MarkdownChatInputState();
}

class _MarkdownChatInputState extends State<MarkdownChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isNotEmpty || widget.attachments.isNotEmpty) {
      widget.onSend(text);
      _controller.clear();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(top: BorderSide(color: Color(0xFF3E3D32))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Attach button
          if (widget.onAttach != null)
            IconButton(
              icon: const Icon(Icons.attach_file, size: 20),
              color: const Color(0xFF808080),
              onPressed: widget.onAttach,
              tooltip: 'Attach file',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          
          const SizedBox(width: 8),
          
          // Text input
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF3E3D32)),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: null,
                style: const TextStyle(color: Color(0xFFF8F8F2), fontSize: 14),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: const TextStyle(color: Color(0xFF808080)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Send button
          Container(
            decoration: BoxDecoration(
              color: (_controller.text.trim().isNotEmpty || widget.attachments.isNotEmpty)
                  ? const Color(0xFF66D9EF)
                  : const Color(0xFF3E3D32),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.send, size: 18),
              color: (_controller.text.trim().isNotEmpty || widget.attachments.isNotEmpty)
                  ? const Color(0xFF1E1E1E)
                  : const Color(0xFF606060),
              onPressed: (_controller.text.trim().isNotEmpty || widget.attachments.isNotEmpty) ? _send : null,
              padding: const EdgeInsets.all(10),
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MARKDOWN RENDERER
// ═══════════════════════════════════════════════════════════════════════════

class MarkdownRenderer extends StatelessWidget {
  final String markdown;
  final double fontSize;

  const MarkdownRenderer({super.key, required this.markdown, this.fontSize = 14});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _parseBlocks(markdown).map(_buildBlock).toList(),
    );
  }

  List<_Block> _parseBlocks(String text) {
    final blocks = <_Block>[];
    final lines = text.split('\n');
    bool inCode = false;
    String codeLang = '';
    List<String> codeLines = [];

    for (final line in lines) {
      if (line.startsWith('```')) {
        if (inCode) {
          blocks.add(_Block.code(codeLines.join('\n'), codeLang));
          codeLines = [];
          codeLang = '';
          inCode = false;
        } else {
          inCode = true;
          codeLang = line.length > 3 ? line.substring(3).trim() : '';
        }
        continue;
      }
      if (inCode) { codeLines.add(line); continue; }
      if (line.startsWith('### ')) { blocks.add(_Block.h3(line.substring(4))); }
      else if (line.startsWith('## ')) { blocks.add(_Block.h2(line.substring(3))); }
      else if (line.startsWith('# ')) { blocks.add(_Block.h1(line.substring(2))); }
      else if (line.startsWith('- ') || line.startsWith('* ')) { blocks.add(_Block.bullet(line.substring(2))); }
      else if (line.startsWith('> ')) { blocks.add(_Block.quote(line.substring(2))); }
      else if (line.trim().isEmpty) { blocks.add(_Block.empty()); }
      else { blocks.add(_Block.para(line)); }
    }
    if (inCode && codeLines.isNotEmpty) { blocks.add(_Block.code(codeLines.join('\n'), codeLang)); }
    return blocks;
  }

  Widget _buildBlock(_Block b) {
    switch (b.type) {
      case _BType.h1:
        return Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: _InlineText(b.content, TextStyle(fontSize: fontSize + 6, fontWeight: FontWeight.bold, color: const Color(0xFFF8F8F2))));
      case _BType.h2:
        return Padding(padding: const EdgeInsets.only(top: 6, bottom: 3), child: _InlineText(b.content, TextStyle(fontSize: fontSize + 3, fontWeight: FontWeight.bold, color: const Color(0xFFF8F8F2))));
      case _BType.h3:
        return Padding(padding: const EdgeInsets.only(top: 4, bottom: 2), child: _InlineText(b.content, TextStyle(fontSize: fontSize + 1, fontWeight: FontWeight.bold, color: const Color(0xFFF8F8F2))));
      case _BType.para:
        return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: _InlineText(b.content, TextStyle(fontSize: fontSize, color: const Color(0xFFF8F8F2))));
      case _BType.bullet:
        return Padding(
          padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('•  ', style: TextStyle(fontSize: fontSize, color: const Color(0xFF66D9EF))),
            Expanded(child: _InlineText(b.content, TextStyle(fontSize: fontSize, color: const Color(0xFFF8F8F2)))),
          ]),
        );
      case _BType.quote:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.only(left: 10),
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFF808080), width: 3))),
          child: _InlineText(b.content, TextStyle(fontSize: fontSize, fontStyle: FontStyle.italic, color: const Color(0xFFAAAAAA))),
        );
      case _BType.code:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF3E3D32))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (b.lang.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: const BoxDecoration(color: Color(0xFF2D2D2D), borderRadius: BorderRadius.vertical(top: Radius.circular(5))),
                child: Row(children: [
                  Text(b.lang, style: const TextStyle(fontSize: 10, color: Color(0xFF808080), fontFamily: 'monospace')),
                  const Spacer(),
                  GestureDetector(onTap: () => Clipboard.setData(ClipboardData(text: b.content)), child: const Icon(Icons.copy, size: 12, color: Color(0xFF808080))),
                ]),
              ),
            Padding(padding: const EdgeInsets.all(10), child: SelectableText(b.content, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Color(0xFFA6E22E), height: 1.4))),
          ]),
        );
      case _BType.empty:
        return const SizedBox(height: 6);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INLINE TEXT PARSER
// ═══════════════════════════════════════════════════════════════════════════

class _InlineText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const _InlineText(this.text, this.style);

  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(children: _parse(text, style)), style: style);

  List<InlineSpan> _parse(String t, TextStyle base) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'`([^`]+)`|\*\*([^*]+)\*\*|\*([^*]+)\*|_([^_]+)_|([^`*_]+)');
    for (final m in re.allMatches(t)) {
      if (m.group(1) != null) {
        spans.add(TextSpan(text: m.group(1), style: base.copyWith(fontFamily: 'monospace', backgroundColor: const Color(0xFF3E3D32), color: const Color(0xFFA6E22E), fontSize: (base.fontSize ?? 14) - 1)));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(text: m.group(2), style: base.copyWith(fontWeight: FontWeight.bold)));
      } else if (m.group(3) != null || m.group(4) != null) {
        spans.add(TextSpan(text: m.group(3) ?? m.group(4), style: base.copyWith(fontStyle: FontStyle.italic)));
      } else if (m.group(5) != null) {
        spans.add(TextSpan(text: m.group(5), style: base));
      }
    }
    return spans;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BLOCK TYPES
// ═══════════════════════════════════════════════════════════════════════════

enum _BType { h1, h2, h3, para, bullet, quote, code, empty }

class _Block {
  final _BType type; 
  final String content; 
  final String lang;
  
  _Block._(this.type, this.content, [this.lang = '']);
  
  factory _Block.h1(String c) => _Block._(_BType.h1, c);
  factory _Block.h2(String c) => _Block._(_BType.h2, c);
  factory _Block.h3(String c) => _Block._(_BType.h3, c);
  factory _Block.para(String c) => _Block._(_BType.para, c);
  factory _Block.bullet(String c) => _Block._(_BType.bullet, c);
  factory _Block.quote(String c) => _Block._(_BType.quote, c);
  factory _Block.code(String c, String l) => _Block._(_BType.code, c, l);
  factory _Block.empty() => _Block._(_BType.empty, '');
}

// ═══════════════════════════════════════════════════════════════════════════
// CHAT MESSAGE WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class ChatMessageWidget extends StatelessWidget {
  final String sender;
  final String content;
  final DateTime timestamp;
  final bool isMe;
  final List<String> attachments;

  const ChatMessageWidget({
    super.key,
    required this.sender,
    required this.content,
    required this.timestamp,
    this.isMe = false,
    this.attachments = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: isMe ? const Color(0xFF66D9EF) : const Color(0xFFA6E22E),
            child: Text(
              sender[0].toUpperCase(),
              style: const TextStyle(color: Color(0xFF1E1E1E), fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      sender,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isMe ? const Color(0xFF66D9EF) : const Color(0xFFA6E22E),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF808080)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                
                // Message content
                if (content.isNotEmpty)
                  MarkdownRenderer(markdown: content, fontSize: 13),
                
                // Attachments
                if (attachments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: attachments.map((f) => _AttachmentChip(filename: f)).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ATTACHMENT CHIP
// ═══════════════════════════════════════════════════════════════════════════

class _AttachmentChip extends StatelessWidget {
  final String filename;
  const _AttachmentChip({required this.filename});

  IconData get _icon {
    final ext = filename.split('.').last.toLowerCase();
    if (['png', 'jpg', 'jpeg', 'gif', 'webp'].contains(ext)) return Icons.image;
    if (ext == 'pdf') return Icons.picture_as_pdf;
    if (['dart', 'py', 'js', 'ts', 'rs'].contains(ext)) return Icons.code;
    return Icons.attach_file;
  }

  Color get _color {
    final ext = filename.split('.').last.toLowerCase();
    if (['png', 'jpg', 'jpeg', 'gif', 'webp'].contains(ext)) return const Color(0xFFF92672);
    if (ext == 'pdf') return const Color(0xFFE74C3C);
    if (['dart', 'py', 'js', 'ts', 'rs'].contains(ext)) return const Color(0xFFA6E22E);
    return const Color(0xFF808080);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF3E3D32),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 14, color: _color),
          const SizedBox(width: 6),
          Text(filename, style: const TextStyle(fontSize: 12, color: Color(0xFFF8F8F2))),
        ],
      ),
    );
  }
}
