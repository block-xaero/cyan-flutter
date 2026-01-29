// widgets/vscode_markdown.dart
// VSCode-style markdown renderer with syntax highlighting and line numbers
// Supports: SQL, JSON, TOML, YAML, Rust, Python, JavaScript, TypeScript, etc.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/monokai_theme.dart';

// ============================================================================
// SYNTAX HIGHLIGHTING RULES (Monokai-inspired)
// ============================================================================

class SyntaxTheme {
  static const keyword = Color(0xFFF92672);      // Pink
  static const string = Color(0xFFE6DB74);       // Yellow
  static const number = Color(0xFFAE81FF);       // Purple
  static const comment = Color(0xFF75715E);      // Gray
  static const function_ = Color(0xFFA6E22E);    // Green
  static const type = Color(0xFF66D9EF);         // Cyan
  static const variable = Color(0xFFF8F8F2);     // White
  static const operator_ = Color(0xFFF92672);    // Pink
  static const punctuation = Color(0xFFF8F8F2);  // White
  static const property = Color(0xFFFD971F);     // Orange
}

enum Language {
  plaintext,
  json,
  yaml,
  toml,
  sql,
  rust,
  python,
  javascript,
  typescript,
  dart,
  markdown,
  shell,
}

Language detectLanguage(String code, {String? hint}) {
  if (hint != null) {
    final h = hint.toLowerCase();
    if (h == 'json') return Language.json;
    if (h == 'yaml' || h == 'yml') return Language.yaml;
    if (h == 'toml') return Language.toml;
    if (h == 'sql') return Language.sql;
    if (h == 'rust' || h == 'rs') return Language.rust;
    if (h == 'python' || h == 'py') return Language.python;
    if (h == 'javascript' || h == 'js') return Language.javascript;
    if (h == 'typescript' || h == 'ts') return Language.typescript;
    if (h == 'dart') return Language.dart;
    if (h == 'markdown' || h == 'md') return Language.markdown;
    if (h == 'shell' || h == 'bash' || h == 'sh') return Language.shell;
  }
  
  // Auto-detect
  if (code.trimLeft().startsWith('{') || code.trimLeft().startsWith('[')) {
    return Language.json;
  }
  if (code.contains('SELECT ') || code.contains('INSERT ') || code.contains('CREATE TABLE')) {
    return Language.sql;
  }
  if (code.contains('fn ') && code.contains('->')) {
    return Language.rust;
  }
  if (code.contains('def ') || code.contains('import ')) {
    return Language.python;
  }
  if (code.contains('function ') || code.contains('const ') || code.contains('=>')) {
    return Language.javascript;
  }
  
  return Language.plaintext;
}

// ============================================================================
// SYNTAX HIGHLIGHTER
// ============================================================================

class SyntaxHighlighter {
  final Language language;
  
  SyntaxHighlighter(this.language);
  
  List<TextSpan> highlight(String code) {
    switch (language) {
      case Language.json:
        return _highlightJson(code);
      case Language.yaml:
        return _highlightYaml(code);
      case Language.toml:
        return _highlightToml(code);
      case Language.sql:
        return _highlightSql(code);
      case Language.rust:
        return _highlightRust(code);
      case Language.python:
        return _highlightPython(code);
      case Language.javascript:
      case Language.typescript:
        return _highlightJavaScript(code);
      case Language.dart:
        return _highlightDart(code);
      case Language.shell:
        return _highlightShell(code);
      default:
        return [TextSpan(text: code, style: _style(SyntaxTheme.variable))];
    }
  }
  
  TextStyle _style(Color color) => TextStyle(
    color: color,
    fontFamily: 'JetBrains Mono, Menlo, Monaco, monospace',
    fontSize: 13,
    height: 1.5,
  );
  
  List<TextSpan> _highlightJson(String code) {
    final spans = <TextSpan>[];
    final regex = RegExp(
      r'("(?:[^"\\]|\\.)*")\s*(:)?|(-?\d+\.?\d*)|(\btrue\b|\bfalse\b|\bnull\b)|([{}\[\],])|(\s+)',
    );
    
    int lastEnd = 0;
    for (final match in regex.allMatches(code)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: code.substring(lastEnd, match.start), style: _style(SyntaxTheme.variable)));
      }
      
      if (match.group(1) != null) {
        final isKey = match.group(2) != null;
        spans.add(TextSpan(text: match.group(1), style: _style(isKey ? SyntaxTheme.property : SyntaxTheme.string)));
        if (isKey) spans.add(TextSpan(text: ':', style: _style(SyntaxTheme.punctuation)));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(text: match.group(3), style: _style(SyntaxTheme.number)));
      } else if (match.group(4) != null) {
        spans.add(TextSpan(text: match.group(4), style: _style(SyntaxTheme.keyword)));
      } else if (match.group(5) != null) {
        spans.add(TextSpan(text: match.group(5), style: _style(SyntaxTheme.punctuation)));
      } else if (match.group(6) != null) {
        spans.add(TextSpan(text: match.group(6), style: _style(SyntaxTheme.variable)));
      }
      
      lastEnd = match.end;
    }
    
    if (lastEnd < code.length) {
      spans.add(TextSpan(text: code.substring(lastEnd), style: _style(SyntaxTheme.variable)));
    }
    
    return spans;
  }
  
  List<TextSpan> _highlightYaml(String code) {
    final spans = <TextSpan>[];
    final lines = code.split('\n');
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (i > 0) spans.add(TextSpan(text: '\n', style: _style(SyntaxTheme.variable)));
      
      if (line.trimLeft().startsWith('#')) {
        spans.add(TextSpan(text: line, style: _style(SyntaxTheme.comment)));
      } else if (line.contains(':')) {
        final colonIdx = line.indexOf(':');
        spans.add(TextSpan(text: line.substring(0, colonIdx), style: _style(SyntaxTheme.property)));
        spans.add(TextSpan(text: ':', style: _style(SyntaxTheme.punctuation)));
        final value = line.substring(colonIdx + 1);
        if (value.trim().startsWith('"') || value.trim().startsWith("'")) {
          spans.add(TextSpan(text: value, style: _style(SyntaxTheme.string)));
        } else if (RegExp(r'^\s*-?\d+\.?\d*\s*$').hasMatch(value)) {
          spans.add(TextSpan(text: value, style: _style(SyntaxTheme.number)));
        } else if (value.trim() == 'true' || value.trim() == 'false' || value.trim() == 'null') {
          spans.add(TextSpan(text: value, style: _style(SyntaxTheme.keyword)));
        } else {
          spans.add(TextSpan(text: value, style: _style(SyntaxTheme.string)));
        }
      } else if (line.trimLeft().startsWith('-')) {
        spans.add(TextSpan(text: line, style: _style(SyntaxTheme.variable)));
      } else {
        spans.add(TextSpan(text: line, style: _style(SyntaxTheme.variable)));
      }
    }
    
    return spans;
  }
  
  List<TextSpan> _highlightToml(String code) {
    final spans = <TextSpan>[];
    final lines = code.split('\n');
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (i > 0) spans.add(TextSpan(text: '\n', style: _style(SyntaxTheme.variable)));
      
      if (line.trimLeft().startsWith('#')) {
        spans.add(TextSpan(text: line, style: _style(SyntaxTheme.comment)));
      } else if (line.trimLeft().startsWith('[')) {
        spans.add(TextSpan(text: line, style: _style(SyntaxTheme.type)));
      } else if (line.contains('=')) {
        final eqIdx = line.indexOf('=');
        spans.add(TextSpan(text: line.substring(0, eqIdx), style: _style(SyntaxTheme.property)));
        spans.add(TextSpan(text: '=', style: _style(SyntaxTheme.operator_)));
        spans.add(TextSpan(text: line.substring(eqIdx + 1), style: _style(SyntaxTheme.string)));
      } else {
        spans.add(TextSpan(text: line, style: _style(SyntaxTheme.variable)));
      }
    }
    
    return spans;
  }
  
  List<TextSpan> _highlightSql(String code) {
    final keywords = ['SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET', 
                      'DELETE', 'CREATE', 'TABLE', 'DROP', 'ALTER', 'INDEX', 'JOIN', 'LEFT',
                      'RIGHT', 'INNER', 'OUTER', 'ON', 'AND', 'OR', 'NOT', 'NULL', 'IS',
                      'IN', 'LIKE', 'BETWEEN', 'ORDER', 'BY', 'GROUP', 'HAVING', 'LIMIT',
                      'OFFSET', 'AS', 'DISTINCT', 'COUNT', 'SUM', 'AVG', 'MAX', 'MIN',
                      'PRIMARY', 'KEY', 'FOREIGN', 'REFERENCES', 'CASCADE', 'CONSTRAINT'];
    
    final spans = <TextSpan>[];
    final regex = RegExp(
      r"('(?:[^'\\]|\\.)*')|" +
      r'("(?:[^"\\]|\\.)*")|' +
      r'(--[^\n]*)|' +
      r'(\b(?:' + keywords.join('|') + r')\b)|' +
      r'(\b\d+\.?\d*\b)|' +
      r'(\b\w+\b)|' +
      r'([,;().*=<>])|' +
      r'(\s+)',
      caseSensitive: false,
    );
    
    for (final match in regex.allMatches(code)) {
      if (match.group(1) != null || match.group(2) != null) {
        spans.add(TextSpan(text: match.group(0), style: _style(SyntaxTheme.string)));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(text: match.group(3), style: _style(SyntaxTheme.comment)));
      } else if (match.group(4) != null) {
        spans.add(TextSpan(text: match.group(4), style: _style(SyntaxTheme.keyword)));
      } else if (match.group(5) != null) {
        spans.add(TextSpan(text: match.group(5), style: _style(SyntaxTheme.number)));
      } else if (match.group(6) != null) {
        spans.add(TextSpan(text: match.group(6), style: _style(SyntaxTheme.variable)));
      } else {
        spans.add(TextSpan(text: match.group(0), style: _style(SyntaxTheme.punctuation)));
      }
    }
    
    return spans;
  }
  
  List<TextSpan> _highlightRust(String code) {
    final keywords = ['fn', 'let', 'mut', 'const', 'if', 'else', 'match', 'while', 'for', 'loop',
                      'return', 'struct', 'enum', 'impl', 'trait', 'pub', 'use', 'mod', 'crate',
                      'self', 'Self', 'super', 'where', 'async', 'await', 'move', 'ref', 'static',
                      'unsafe', 'extern', 'type', 'dyn', 'as', 'in', 'break', 'continue'];
    final types = ['i8', 'i16', 'i32', 'i64', 'i128', 'isize', 'u8', 'u16', 'u32', 'u64', 'u128',
                   'usize', 'f32', 'f64', 'bool', 'char', 'str', 'String', 'Vec', 'Option', 'Result',
                   'Box', 'Rc', 'Arc', 'Cell', 'RefCell', 'HashMap', 'HashSet', 'BTreeMap'];
    
    return _highlightGeneric(code, keywords, types);
  }
  
  List<TextSpan> _highlightPython(String code) {
    final keywords = ['def', 'class', 'if', 'elif', 'else', 'for', 'while', 'return', 'import',
                      'from', 'as', 'try', 'except', 'finally', 'with', 'lambda', 'yield', 'raise',
                      'pass', 'break', 'continue', 'and', 'or', 'not', 'in', 'is', 'None', 'True', 'False',
                      'global', 'nonlocal', 'assert', 'del', 'async', 'await'];
    final types = ['int', 'float', 'str', 'bool', 'list', 'dict', 'tuple', 'set', 'bytes', 'type',
                   'object', 'Exception', 'List', 'Dict', 'Tuple', 'Set', 'Optional', 'Union', 'Any'];
    
    return _highlightGeneric(code, keywords, types, commentChar: '#');
  }
  
  List<TextSpan> _highlightJavaScript(String code) {
    final keywords = ['function', 'const', 'let', 'var', 'if', 'else', 'for', 'while', 'do', 'switch',
                      'case', 'break', 'continue', 'return', 'throw', 'try', 'catch', 'finally',
                      'class', 'extends', 'new', 'this', 'super', 'import', 'export', 'default',
                      'async', 'await', 'yield', 'typeof', 'instanceof', 'in', 'of', 'delete',
                      'void', 'null', 'undefined', 'true', 'false', 'NaN', 'Infinity'];
    final types = ['Array', 'Object', 'String', 'Number', 'Boolean', 'Function', 'Symbol', 'BigInt',
                   'Promise', 'Map', 'Set', 'WeakMap', 'WeakSet', 'Date', 'RegExp', 'Error'];
    
    return _highlightGeneric(code, keywords, types);
  }
  
  List<TextSpan> _highlightDart(String code) {
    final keywords = ['abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch',
                      'class', 'const', 'continue', 'covariant', 'default', 'deferred', 'do',
                      'dynamic', 'else', 'enum', 'export', 'extends', 'extension', 'external',
                      'factory', 'false', 'final', 'finally', 'for', 'Function', 'get', 'hide',
                      'if', 'implements', 'import', 'in', 'interface', 'is', 'late', 'library',
                      'mixin', 'new', 'null', 'on', 'operator', 'part', 'required', 'rethrow',
                      'return', 'set', 'show', 'static', 'super', 'switch', 'sync', 'this',
                      'throw', 'true', 'try', 'typedef', 'var', 'void', 'while', 'with', 'yield'];
    final types = ['int', 'double', 'num', 'String', 'bool', 'List', 'Map', 'Set', 'Iterable',
                   'Future', 'Stream', 'Object', 'dynamic', 'void', 'Never', 'Null'];
    
    return _highlightGeneric(code, keywords, types);
  }
  
  List<TextSpan> _highlightShell(String code) {
    final keywords = ['if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'do', 'done', 'case',
                      'esac', 'function', 'return', 'exit', 'export', 'source', 'alias', 'unset',
                      'local', 'readonly', 'declare', 'typeset', 'echo', 'printf', 'read', 'cd',
                      'pwd', 'ls', 'cp', 'mv', 'rm', 'mkdir', 'chmod', 'chown', 'grep', 'sed',
                      'awk', 'cat', 'head', 'tail', 'find', 'xargs', 'sort', 'uniq', 'wc'];
    
    return _highlightGeneric(code, keywords, [], commentChar: '#');
  }
  
  List<TextSpan> _highlightGeneric(String code, List<String> keywords, List<String> types, {String commentChar = '//'}) {
    final spans = <TextSpan>[];
    final keywordPattern = keywords.map((k) => '\\b$k\\b').join('|');
    final typePattern = types.isNotEmpty ? types.map((t) => '\\b$t\\b').join('|') : '';
    
    final commentPattern = commentChar == '#' ? r'#[^\n]*' : r'//[^\n]*|/\*[\s\S]*?\*/';
    
    String pattern = 
      r"('(?:[^'\\]|\\.)*')|" +
      r'("(?:[^"\\]|\\.)*")|' +
      r'(`(?:[^`\\]|\\.)*`)|' +
      '($commentPattern)|';
    
    if (keywordPattern.isNotEmpty) {
      pattern += '($keywordPattern)|';
    }
    if (typePattern.isNotEmpty) {
      pattern += '($typePattern)|';
    }
    
    pattern += r'(\b\d+\.?\d*\b)|' +
               r'(\b\w+\s*(?=\())|' +
               r'(\b\w+\b)|' +
               r'([^\w\s])|' +
               r'(\s+)';
    
    final regex = RegExp(pattern);
    
    for (final match in regex.allMatches(code)) {
      final text = match.group(0) ?? '';
      Color color = SyntaxTheme.variable;
      
      if (match.group(1) != null || match.group(2) != null || match.group(3) != null) {
        color = SyntaxTheme.string;
      } else if (match.group(4) != null) {
        color = SyntaxTheme.comment;
      } else if (keywordPattern.isNotEmpty && match.group(5) != null) {
        color = SyntaxTheme.keyword;
      } else if (typePattern.isNotEmpty && match.group(6) != null) {
        color = SyntaxTheme.type;
      } else if (match.group(keywordPattern.isNotEmpty && typePattern.isNotEmpty ? 7 : 
                             keywordPattern.isNotEmpty ? 6 : 5) != null) {
        color = SyntaxTheme.number;
      } else if (text.contains('(')) {
        color = SyntaxTheme.function_;
      }
      
      spans.add(TextSpan(text: text, style: _style(color)));
    }
    
    return spans.isEmpty ? [TextSpan(text: code, style: _style(SyntaxTheme.variable))] : spans;
  }
}

// ============================================================================
// VSCODE-STYLE CODE BLOCK WIDGET
// ============================================================================

class VSCodeBlock extends StatelessWidget {
  final String code;
  final String? language;
  final bool showLineNumbers;
  final bool showCopyButton;
  final double? maxHeight;
  
  const VSCodeBlock({
    super.key,
    required this.code,
    this.language,
    this.showLineNumbers = true,
    this.showCopyButton = true,
    this.maxHeight,
  });
  
  @override
  Widget build(BuildContext context) {
    final lang = detectLanguage(code, hint: language);
    final highlighter = SyntaxHighlighter(lang);
    final spans = highlighter.highlight(code);
    final lines = code.split('\n');
    
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3E3D32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with language badge and copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D2D),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3E3D32),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    lang.name.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF808080),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Spacer(),
                if (showCopyButton)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    color: const Color(0xFF808080),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied to clipboard'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    tooltip: 'Copy code',
                  ),
              ],
            ),
          ),
          
          // Code content
          Container(
            constraints: maxHeight != null ? BoxConstraints(maxHeight: maxHeight!) : null,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Line numbers
                      if (showLineNumbers)
                        Container(
                          padding: const EdgeInsets.only(right: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: List.generate(lines.length, (i) => Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontFamily: 'JetBrains Mono, Menlo, Monaco, monospace',
                                fontSize: 13,
                                height: 1.5,
                                color: Color(0xFF5A5A5A),
                              ),
                            )),
                          ),
                        ),
                      
                      // Code with syntax highlighting
                      SelectableText.rich(
                        TextSpan(children: spans),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// VSCODE-STYLE NOTES EDITOR
// ============================================================================

class VSCodeNotesEditor extends StatefulWidget {
  final String initialContent;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  
  const VSCodeNotesEditor({
    super.key,
    this.initialContent = '',
    this.onChanged,
    this.readOnly = false,
  });
  
  @override
  State<VSCodeNotesEditor> createState() => _VSCodeNotesEditorState();
}

class _VSCodeNotesEditorState extends State<VSCodeNotesEditor> {
  late TextEditingController _controller;
  late ScrollController _scrollController;
  
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _scrollController = ScrollController();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final lines = _controller.text.split('\n');
    
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line numbers gutter
          Container(
            width: 50,
            color: const Color(0xFF252526),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: List.generate(
                lines.length.clamp(1, 1000),
                (i) => Container(
                  height: 21, // Match line height
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono, Menlo, Monaco, monospace',
                      fontSize: 13,
                      color: Color(0xFF5A5A5A),
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // Editor area
          Expanded(
            child: TextField(
              controller: _controller,
              scrollController: _scrollController,
              readOnly: widget.readOnly,
              maxLines: null,
              expands: true,
              style: const TextStyle(
                fontFamily: 'JetBrains Mono, Menlo, Monaco, monospace',
                fontSize: 13,
                height: 1.615, // 21px line height / 13px font
                color: Color(0xFFF8F8F2),
              ),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.all(12),
                border: InputBorder.none,
                hintText: 'Start typing...',
                hintStyle: TextStyle(color: Color(0xFF5A5A5A)),
              ),
              onChanged: (text) {
                setState(() {}); // Rebuild line numbers
                widget.onChanged?.call(text);
              },
            ),
          ),
        ],
      ),
    );
  }
}
