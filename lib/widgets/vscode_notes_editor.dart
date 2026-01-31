// widgets/vscode_notes_editor.dart
// VSCode-style text editor with syntax highlighting
// Robust implementation matching Swift NotesEditorView

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================================
// VSCODE DARK+ COLOR SCHEME
// ============================================================================

class VSCodeColors {
  static const background = Color(0xFF1E1E1E);
  static const toolbar = Color(0xFF252525);
  static const toolbarButton = Color(0xFF333333);
  static const toolbarText = Color(0xFFCCCCCC);
  static const toolbarMuted = Color(0xFF808080);
  static const gutter = Color(0xFF1E1E1E);
  static const gutterBorder = Color(0xFF404040);
  static const lineNumber = Color(0xFF858585);
  static const lineNumberActive = Color(0xFFC6C6C6);
  static const text = Color(0xFFD4D4D4);
  static const cursor = Color(0xFFAEAFAD);
  static const selection = Color(0xFF264F78);
  static const currentLine = Color(0xFF2A2D2E);
  static const statusBar = Color(0xFF007ACC);
  static const statusText = Color(0xFFFFFFFF);
  static const accent = Color(0xFF66D9EF);
  static const unsaved = Color(0xFFE5C07B);
  
  // Syntax (VSCode Dark+)
  static const keyword = Color(0xFFC586C0);
  static const string = Color(0xFFCE9178);
  static const number = Color(0xFFB5CEA8);
  static const comment = Color(0xFF6A9955);
  static const type = Color(0xFF4EC9B0);
  static const function_ = Color(0xFFDCDCAA);
  static const variable = Color(0xFF9CDCFE);
  static const operator_ = Color(0xFFD4D4D4);
  static const heading = Color(0xFF569CD6);
  static const link = Color(0xFF4FC1FF);
  static const decorator = Color(0xFFDCDCAA);
}

// ============================================================================
// FILE TYPE
// ============================================================================

enum FileType {
  plaintext('Plain Text', Icons.description),
  markdown('Markdown', Icons.article),
  json('JSON', Icons.data_object),
  yaml('YAML', Icons.settings),
  rust('Rust', Icons.memory),
  python('Python', Icons.code),
  javascript('JavaScript', Icons.javascript),
  typescript('TypeScript', Icons.code),
  sql('SQL', Icons.table_chart),
  swift('Swift', Icons.phone_iphone),
  dart('Dart', Icons.flutter_dash),
  shell('Shell', Icons.terminal);

  final String label;
  final IconData icon;
  const FileType(this.label, this.icon);
  
  static FileType detect(String content) {
    final t = content.trim();
    if (t.isEmpty) return plaintext;
    
    // JSON
    if (t.startsWith('{') || t.startsWith('[')) return json;
    
    // YAML
    if (t.startsWith('---') || RegExp(r'^\w+:', multiLine: true).hasMatch(t)) {
      if (['apiVersion:', 'kind:', 'metadata:'].any((p) => t.contains(p))) return yaml;
    }
    
    // Markdown
    if (['# ', '## ', '```', '- [ ]', '**', ']('].any((p) => t.contains(p))) return markdown;
    
    // Code
    if (t.contains('fn ') && t.contains('->')) return rust;
    if (t.contains('def ') || t.contains('import ') && t.contains(':')) return python;
    if (RegExp(r'\b(SELECT|INSERT|CREATE)\b', caseSensitive: false).hasMatch(t)) return sql;
    if (t.contains('function ') || t.contains('const ') || t.contains('=>')) {
      return t.contains(': string') || t.contains('interface ') ? typescript : javascript;
    }
    if (t.contains('func ') && t.contains('->')) return swift;
    if (t.contains('@override') || t.contains('Widget ')) return dart;
    if (t.startsWith('#!/') || t.contains('echo ')) return shell;
    
    return plaintext;
  }
}

// ============================================================================
// VSCODE NOTES EDITOR
// ============================================================================

class VSCodeNotesEditor extends StatefulWidget {
  final String initialContent;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSave;
  final bool readOnly;
  
  const VSCodeNotesEditor({
    super.key,
    this.initialContent = '',
    this.onChanged,
    this.onSave,
    this.readOnly = false,
  });
  
  @override
  State<VSCodeNotesEditor> createState() => _VSCodeNotesEditorState();
}

class _VSCodeNotesEditorState extends State<VSCodeNotesEditor> {
  late TextEditingController _controller;
  late ScrollController _scrollController;
  
  FileType _fileType = FileType.plaintext;
  bool _hasChanges = false;
  int _cursorLine = 1;
  int _cursorCol = 1;
  String _original = '';
  bool _showPreview = false; // Preview mode for markdown
  
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _scrollController = ScrollController();
    _original = widget.initialContent;
    _fileType = FileType.detect(widget.initialContent);
    
    _controller.addListener(_onTextChange);
  }
  
  @override
  void dispose() {
    _controller.removeListener(_onTextChange);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  
  void _onTextChange() {
    final text = _controller.text;
    final changed = text != _original;
    final type = FileType.detect(text);
    
    // Cursor position
    final sel = _controller.selection;
    if (sel.isValid && sel.baseOffset <= text.length) {
      final before = text.substring(0, sel.baseOffset);
      final lines = before.split('\n');
      _cursorLine = lines.length;
      _cursorCol = lines.last.length + 1;
    }
    
    if (changed != _hasChanges || type != _fileType) {
      setState(() {
        _hasChanges = changed;
        _fileType = type;
      });
    }
    
    widget.onChanged?.call(text);
  }
  
  void _save() {
    widget.onSave?.call();
    setState(() {
      _original = _controller.text;
      _hasChanges = false;
    });
  }
  
  int get _lineCount => _controller.text.split('\n').length;
  int get _wordCount => _controller.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  
  bool get _canPreview => _fileType == FileType.markdown;
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: _showPreview && _canPreview 
              ? _buildSplitView() 
              : _buildEditorArea(),
        ),
        _buildStatusBar(),
      ],
    );
  }
  
  // ========== TOOLBAR ==========
  
  Widget _buildToolbar() {
    return Container(
      height: 35,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: VSCodeColors.toolbar,
        border: Border(bottom: BorderSide(color: VSCodeColors.gutterBorder)),
      ),
      child: Row(
        children: [
          // File type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: VSCodeColors.toolbarButton,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_fileType.icon, size: 14, color: VSCodeColors.toolbarText),
                const SizedBox(width: 6),
                Text(_fileType.label, style: const TextStyle(fontSize: 12, color: VSCodeColors.toolbarText)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          
          // Unsaved dot
          if (_hasChanges)
            Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(color: VSCodeColors.unsaved, shape: BoxShape.circle),
            ),
          
          const Spacer(),
          
          // Preview toggle (for markdown)
          if (_canPreview)
            Tooltip(
              message: _showPreview ? 'Hide Preview' : 'Show Preview',
              child: InkWell(
                onTap: () => setState(() => _showPreview = !_showPreview),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _showPreview ? VSCodeColors.accent.withOpacity(0.2) : VSCodeColors.toolbarButton,
                    borderRadius: BorderRadius.circular(4),
                    border: _showPreview ? Border.all(color: VSCodeColors.accent) : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showPreview ? Icons.visibility : Icons.visibility_outlined,
                        size: 14,
                        color: _showPreview ? VSCodeColors.accent : VSCodeColors.toolbarText,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Preview',
                        style: TextStyle(
                          fontSize: 11,
                          color: _showPreview ? VSCodeColors.accent : VSCodeColors.toolbarText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          const SizedBox(width: 8),
          
          // Save button
          if (!widget.readOnly && widget.onSave != null)
            TextButton.icon(
              onPressed: _hasChanges ? _save : null,
              icon: Icon(Icons.save, size: 16, color: _hasChanges ? VSCodeColors.accent : VSCodeColors.toolbarMuted),
              label: Text('Save', style: TextStyle(fontSize: 12, color: _hasChanges ? VSCodeColors.accent : VSCodeColors.toolbarMuted)),
            ),
        ],
      ),
    );
  }
  
  // ========== EDITOR AREA ==========
  
  Widget _buildEditorArea() {
    final lines = _controller.text.split('\n');
    final lineCount = lines.length;
    
    return Container(
      color: VSCodeColors.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Line numbers gutter - simple Column in a scroll view synced with editor
              Container(
                width: 50,
                color: VSCodeColors.gutter,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 12, bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(lineCount, (i) {
                      final isActive = i + 1 == _cursorLine;
                      return Container(
                        height: 20, // Must match editor line height
                        padding: const EdgeInsets.only(right: 12),
                        alignment: Alignment.centerRight,
                        color: isActive ? VSCodeColors.currentLine : null,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontFamily: 'SF Mono, Menlo, Monaco, monospace',
                            fontSize: 13,
                            height: 1.0,
                            color: isActive ? VSCodeColors.lineNumberActive : VSCodeColors.lineNumber,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              
              // Divider
              Container(width: 1, color: VSCodeColors.gutterBorder),
              
              // Editor - uses NotificationListener to sync scroll with gutter
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification) {
                      _scrollController.jumpTo(notification.metrics.pixels);
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _controller,
                      readOnly: widget.readOnly,
                      maxLines: null,
                      style: const TextStyle(
                        fontFamily: 'SF Mono, Menlo, Monaco, monospace',
                        fontSize: 13,
                        height: 1.538, // 20px / 13px = 1.538
                        color: VSCodeColors.text,
                      ),
                      cursorColor: VSCodeColors.cursor,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}), // Rebuild line numbers
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
  
  // ========== STATUS BAR ==========
  
  Widget _buildStatusBar() {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: VSCodeColors.statusBar,
      child: Row(
        children: [
          Text('Ln $_cursorLine, Col $_cursorCol', style: const TextStyle(fontSize: 12, color: VSCodeColors.statusText)),
          const SizedBox(width: 16),
          Text('$_wordCount words', style: const TextStyle(fontSize: 12, color: VSCodeColors.statusText)),
          const SizedBox(width: 16),
          Text('$_lineCount lines', style: const TextStyle(fontSize: 12, color: VSCodeColors.statusText)),
          const Spacer(),
          if (_showPreview && _canPreview)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text('Split View', style: TextStyle(fontSize: 12, color: VSCodeColors.statusText)),
            ),
          Text(_fileType.label, style: const TextStyle(fontSize: 12, color: VSCodeColors.statusText)),
          const SizedBox(width: 16),
          const Text('UTF-8', style: TextStyle(fontSize: 12, color: VSCodeColors.statusText)),
        ],
      ),
    );
  }
  
  // ========== SPLIT VIEW (Editor + Preview) ==========
  
  Widget _buildSplitView() {
    return Row(
      children: [
        // Editor (left half)
        Expanded(child: _buildEditorArea()),
        
        // Divider
        Container(width: 1, color: VSCodeColors.gutterBorder),
        
        // Preview (right half)
        Expanded(child: _buildMarkdownPreview()),
      ],
    );
  }
  
  // ========== MARKDOWN PREVIEW ==========
  
  Widget _buildMarkdownPreview() {
    return Container(
      color: VSCodeColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Preview header
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: VSCodeColors.toolbar,
              border: Border(bottom: BorderSide(color: VSCodeColors.gutterBorder)),
            ),
            child: const Row(
              children: [
                Icon(Icons.preview, size: 14, color: VSCodeColors.toolbarMuted),
                SizedBox(width: 6),
                Text('Preview', style: TextStyle(fontSize: 11, color: VSCodeColors.toolbarMuted)),
              ],
            ),
          ),
          
          // Rendered markdown
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _MarkdownRenderer(content: _controller.text),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SIMPLE MARKDOWN RENDERER
// ============================================================================

class _MarkdownRenderer extends StatelessWidget {
  final String content;
  
  const _MarkdownRenderer({required this.content});
  
  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    final widgets = <Widget>[];
    
    bool inCodeBlock = false;
    String codeBuffer = '';
    String codeLang = '';
    
    for (final line in lines) {
      // Code block toggle
      if (line.trimLeft().startsWith('```')) {
        if (inCodeBlock) {
          // End code block
          widgets.add(_buildCodeBlock(codeBuffer.trimRight(), codeLang));
          widgets.add(const SizedBox(height: 12));
          codeBuffer = '';
          codeLang = '';
          inCodeBlock = false;
        } else {
          // Start code block
          inCodeBlock = true;
          codeLang = line.trim().substring(3);
        }
        continue;
      }
      
      if (inCodeBlock) {
        codeBuffer += '$line\n';
        continue;
      }
      
      // Headers
      if (line.startsWith('# ')) {
        widgets.add(_buildHeader(line.substring(2), 1));
      } else if (line.startsWith('## ')) {
        widgets.add(_buildHeader(line.substring(3), 2));
      } else if (line.startsWith('### ')) {
        widgets.add(_buildHeader(line.substring(4), 3));
      } else if (line.startsWith('#### ')) {
        widgets.add(_buildHeader(line.substring(5), 4));
      }
      // List items
      else if (line.trimLeft().startsWith('- ') || line.trimLeft().startsWith('* ')) {
        widgets.add(_buildListItem(line.trimLeft().substring(2)));
      }
      // Checkbox
      else if (line.contains('- [ ]') || line.contains('- [x]')) {
        final checked = line.contains('- [x]');
        final text = line.replaceAll(RegExp(r'- \[[x ]\] '), '');
        widgets.add(_buildCheckbox(text, checked));
      }
      // Blockquote
      else if (line.trimLeft().startsWith('> ')) {
        widgets.add(_buildBlockquote(line.trimLeft().substring(2)));
      }
      // Horizontal rule
      else if (line.trim() == '---' || line.trim() == '***') {
        widgets.add(Container(height: 1, color: VSCodeColors.gutterBorder, margin: const EdgeInsets.symmetric(vertical: 12)));
      }
      // Empty line
      else if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 8));
      }
      // Regular paragraph
      else {
        widgets.add(_buildParagraph(line));
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
  
  Widget _buildHeader(String text, int level) {
    final sizes = [28.0, 24.0, 20.0, 18.0, 16.0, 14.0];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: sizes[level - 1],
          fontWeight: FontWeight.bold,
          color: VSCodeColors.heading,
        ),
      ),
    );
  }
  
  Widget _buildParagraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _buildRichText(text),
    );
  }
  
  Widget _buildRichText(String text) {
    // Simple inline parsing for **bold**, *italic*, `code`, [link](url)
    final spans = <TextSpan>[];
    final pattern = RegExp(r'(\*\*[^*]+\*\*)|(\*[^*]+\*)|(`[^`]+`)|(\[[^\]]+\]\([^)]+\))');
    
    int lastEnd = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      
      final m = match.group(0)!;
      if (m.startsWith('**')) {
        spans.add(TextSpan(
          text: m.substring(2, m.length - 2),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ));
      } else if (m.startsWith('*')) {
        spans.add(TextSpan(
          text: m.substring(1, m.length - 1),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else if (m.startsWith('`')) {
        spans.add(TextSpan(
          text: m.substring(1, m.length - 1),
          style: TextStyle(
            fontFamily: 'SF Mono, Menlo, monospace',
            backgroundColor: VSCodeColors.toolbarButton,
            color: VSCodeColors.string,
          ),
        ));
      } else if (m.startsWith('[')) {
        final linkMatch = RegExp(r'\[([^\]]+)\]\(([^)]+)\)').firstMatch(m);
        if (linkMatch != null) {
          spans.add(TextSpan(
            text: linkMatch.group(1),
            style: const TextStyle(color: VSCodeColors.link, decoration: TextDecoration.underline),
          ));
        }
      }
      lastEnd = match.end;
    }
    
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 14, color: VSCodeColors.text, height: 1.5),
        children: spans.isEmpty ? [TextSpan(text: text)] : spans,
      ),
    );
  }
  
  Widget _buildListItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: VSCodeColors.accent)),
          Expanded(child: _buildRichText(text)),
        ],
      ),
    );
  }
  
  Widget _buildCheckbox(String text, bool checked) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        children: [
          Icon(
            checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 18,
            color: checked ? VSCodeColors.accent : VSCodeColors.toolbarMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: VSCodeColors.text,
                decoration: checked ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildBlockquote(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: VSCodeColors.accent, width: 3)),
        color: VSCodeColors.toolbar,
      ),
      child: Text(text, style: TextStyle(color: VSCodeColors.text.withOpacity(0.8), fontStyle: FontStyle.italic)),
    );
  }
  
  Widget _buildCodeBlock(String code, String lang) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: VSCodeColors.gutterBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lang.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(lang, style: const TextStyle(fontSize: 10, color: VSCodeColors.toolbarMuted)),
            ),
          Text(
            code,
            style: const TextStyle(
              fontFamily: 'SF Mono, Menlo, monospace',
              fontSize: 12,
              color: VSCodeColors.text,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
