// services/notebook_import_export.dart
// Jupyter .ipynb import/export, PDF export, spreadsheet handling
// Matches Swift JupyterImporter.swift pattern

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'python_executor.dart';

// ============================================================================
// NOTEBOOK CELL MODEL (matches Swift NotebookCell)
// ============================================================================

class ImportedCell {
  final String id;
  final String cellType; // markdown, code, sql, mermaid, model
  final String content;
  final String? output;
  final int order;

  ImportedCell({
    required this.id,
    required this.cellType,
    required this.content,
    this.output,
    required this.order,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'cell_type': cellType,
        'content': content,
        if (output != null) 'output': output,
      };
}

// ============================================================================
// JUPYTER IMPORTER
// ============================================================================

class JupyterImporter {
  /// Parse .ipynb file and return list of cells
  static Future<List<ImportedCell>> importFile(String filePath) async {
    try {
      final file = File(filePath);
      final content = await file.readAsString();
      return importFromJson(content);
    } catch (e) {
      debugPrint('📓 Jupyter import error: $e');
      return [];
    }
  }

  /// Parse .ipynb JSON string
  static List<ImportedCell> importFromJson(String jsonStr) {
    try {
      final notebook = jsonDecode(jsonStr) as Map<String, dynamic>;
      final cells = notebook['cells'] as List<dynamic>? ?? [];

      final result = <ImportedCell>[];
      for (var i = 0; i < cells.length; i++) {
        final jCell = cells[i] as Map<String, dynamic>;
        final cellType = _mapCellType(jCell['cell_type'] as String? ?? 'markdown');
        final source = _extractSource(jCell['source']);

        if (source.trim().isEmpty) continue;

        // Extract outputs
        String? output;
        final outputs = jCell['outputs'] as List<dynamic>?;
        if (outputs != null && outputs.isNotEmpty) {
          output = _formatOutputs(outputs);
        }

        result.add(ImportedCell(
          id: DateTime.now().millisecondsSinceEpoch.toString() + '_$i',
          cellType: cellType,
          content: source,
          output: output,
          order: i,
        ));
      }

      debugPrint('📓 Imported ${result.length} cells from Jupyter notebook');
      return result;
    } catch (e) {
      debugPrint('📓 Parse error: $e');
      return [];
    }
  }

  static String _mapCellType(String jupyterType) {
    switch (jupyterType.toLowerCase()) {
      case 'code':
        return 'code';
      case 'markdown':
        return 'markdown';
      case 'raw':
        return 'markdown';
      default:
        return 'markdown';
    }
  }

  static String _extractSource(dynamic source) {
    if (source is String) return source;
    if (source is List) return source.map((s) => s.toString()).join('');
    return '';
  }

  static String _formatOutputs(List<dynamic> outputs) {
    final result = <String>[];

    for (final output in outputs) {
      if (output is! Map<String, dynamic>) continue;
      final outputType = output['output_type'] as String? ?? '';

      switch (outputType) {
        case 'stream':
          final text = _extractSource(output['text']);
          if (text.isNotEmpty) result.add(text);
          break;

        case 'execute_result':
        case 'display_data':
          final data = output['data'] as Map<String, dynamic>?;
          if (data != null) {
            final textPlain = _extractSource(data['text/plain']);
            if (textPlain.isNotEmpty) result.add(textPlain);
          }
          break;

        case 'error':
          final traceback = output['traceback'] as List<dynamic>?;
          if (traceback != null) {
            final clean = traceback.map((l) => _stripAnsi(l.toString())).join('\n');
            result.add(clean);
          } else {
            final ename = output['ename'] ?? '';
            final evalue = output['evalue'] ?? '';
            result.add('$ename: $evalue');
          }
          break;
      }
    }

    return result.join('\n').trim();
  }

  static String _stripAnsi(String text) {
    return text.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
  }
}

// ============================================================================
// JUPYTER EXPORTER
// ============================================================================

class JupyterExporter {
  /// Export cells to .ipynb format
  static String exportToIpynb(List<Map<String, dynamic>> cells) {
    final jupyterCells = cells.map((cell) {
      final type = cell['cell_type'] as String? ?? 'markdown';
      final content = cell['content'] as String? ?? '';
      final output = cell['output'] as String?;

      final jCell = <String, dynamic>{
        'cell_type': type == 'code' || type == 'sql' ? 'code' : 'markdown',
        'source': content.split('\n').map((l) => '$l\n').toList(),
        'metadata': <String, dynamic>{},
      };

      if (type == 'code' || type == 'sql') {
        jCell['outputs'] = output != null
            ? [
                {
                  'output_type': 'stream',
                  'name': 'stdout',
                  'text': output.split('\n').map((l) => '$l\n').toList(),
                }
              ]
            : [];
        jCell['execution_count'] = null;
      }

      return jCell;
    }).toList();

    final notebook = {
      'cells': jupyterCells,
      'metadata': {
        'kernelspec': {
          'display_name': 'Python 3',
          'language': 'python',
          'name': 'python3',
        },
        'language_info': {
          'name': 'python',
          'version': '3.10',
        },
      },
      'nbformat': 4,
      'nbformat_minor': 5,
    };

    return const JsonEncoder.withIndent('  ').convert(notebook);
  }
}

// ============================================================================
// PDF EXPORTER
// ============================================================================

class NotebookPdfExporter {
  /// Export notebook cells (with outputs) to PDF via Python
  static Future<String?> exportToPdf(
    List<Map<String, dynamic>> cells, {
    String? title,
  }) async {
    final env = PythonEnvironment.instance;
    if (!env.isReady) return null;

    try {
      final appDir = await getTemporaryDirectory();
      final outputPath = '${appDir.path}/notebook_export_${DateTime.now().millisecondsSinceEpoch}.pdf';
      
      // Build markdown content from cells
      final mdContent = StringBuffer();
      if (title != null) mdContent.writeln('# $title\n');

      for (final cell in cells) {
        final type = cell['cell_type'] as String? ?? 'markdown';
        final content = cell['content'] as String? ?? '';
        final output = cell['output'] as String?;

        if (type == 'markdown') {
          mdContent.writeln(content);
          mdContent.writeln();
        } else {
          // Code block
          final lang = type == 'sql' ? 'sql' : 'python';
          mdContent.writeln('```$lang');
          mdContent.writeln(content);
          mdContent.writeln('```');
          if (output != null && output.isNotEmpty) {
            mdContent.writeln('\n**Output:**');
            mdContent.writeln('```');
            mdContent.writeln(output);
            mdContent.writeln('```');
          }
          mdContent.writeln();
        }
      }

      // Write markdown to temp file
      final mdPath = '${appDir.path}/notebook_temp.md';
      await File(mdPath).writeAsString(mdContent.toString());

      // Use Python to convert markdown to PDF
      final code = '''
import subprocess, sys, os

md_path = "$mdPath"
pdf_path = "$outputPath"

# Try markdown-pdf packages in order of preference
converters = [
    # 1. mdpdf
    lambda: subprocess.run([sys.executable, "-m", "mdpdf", "-o", pdf_path, md_path], capture_output=True),
    # 2. markdown to HTML then wkhtmltopdf
    lambda: _html_to_pdf(md_path, pdf_path),
    # 3. Simple fpdf fallback
    lambda: _fpdf_fallback(md_path, pdf_path),
]

def _html_to_pdf(md_path, pdf_path):
    import markdown
    html = markdown.markdown(open(md_path).read(), extensions=['fenced_code', 'tables'])
    html_full = f"""<!DOCTYPE html><html><head>
    <style>
        body {{ font-family: monospace; font-size: 12px; margin: 40px; background: #1e1e1e; color: #f8f8f2; }}
        pre {{ background: #272822; padding: 12px; border-radius: 4px; overflow-x: auto; }}
        code {{ background: #272822; padding: 2px 4px; border-radius: 2px; }}
        h1,h2,h3 {{ color: #66d9ef; }}
    </style></head><body>{html}</body></html>"""
    html_path = md_path.replace('.md', '.html')
    open(html_path, 'w').write(html_full)
    # Try pdfkit (wkhtmltopdf wrapper)
    try:
        import pdfkit
        pdfkit.from_file(html_path, pdf_path)
        return type('R', (), {{'returncode': 0}})()
    except:
        # Fallback: just save HTML
        import shutil
        shutil.copy(html_path, pdf_path.replace('.pdf', '.html'))
        return type('R', (), {{'returncode': 1}})()

def _fpdf_fallback(md_path, pdf_path):
    from fpdf import FPDF
    pdf = FPDF()
    pdf.add_page()
    pdf.set_font('Courier', size=10)
    for line in open(md_path).readlines():
        pdf.cell(0, 5, txt=line.rstrip(), ln=True)
    pdf.output(pdf_path)
    return type('R', (), {{'returncode': 0}})()

for converter in converters:
    try:
        r = converter()
        if hasattr(r, 'returncode') and r.returncode == 0 and os.path.exists(pdf_path):
            print(f"PDF exported: {pdf_path}")
            sys.exit(0)
    except Exception as e:
        continue

# If nothing worked, try installing fpdf2 and retry
subprocess.run([sys.executable, "-m", "pip", "install", "fpdf2"], capture_output=True)
try:
    _fpdf_fallback(md_path, pdf_path)
    if os.path.exists(pdf_path):
        print(f"PDF exported: {pdf_path}")
        sys.exit(0)
except:
    pass

print("ERROR: Could not export PDF. Install: pip install fpdf2", file=sys.stderr)
sys.exit(1)
''';

      final executor = PythonExecutor();
      final result = await executor.execute(code, timeoutSeconds: 30);

      if (result.success && await File(outputPath).exists()) {
        debugPrint('📄 PDF exported: $outputPath');
        return outputPath;
      } else {
        debugPrint('📄 PDF export failed: ${result.stderr}');
        return null;
      }
    } catch (e) {
      debugPrint('📄 PDF export error: $e');
      return null;
    }
  }
}

// ============================================================================
// SPREADSHEET HANDLER
// ============================================================================

class SpreadsheetHandler {
  /// Load a spreadsheet into a Python-accessible temp path
  /// Returns the code snippet to load it as a DataFrame
  static Future<SpreadsheetInfo?> importSpreadsheet(String filePath) async {
    final env = PythonEnvironment.instance;
    if (!env.isReady) return null;

    final file = File(filePath);
    if (!await file.exists()) return null;

    final ext = filePath.split('.').last.toLowerCase();
    final fileName = filePath.split('/').last;

    // Copy to a stable temp location
    final appDir = await getTemporaryDirectory();
    final stablePath = '${appDir.path}/data_$fileName';
    await file.copy(stablePath);

    // Determine load code
    String loadCode;
    String requiredPackage;

    switch (ext) {
      case 'csv':
      case 'tsv':
        loadCode = ext == 'tsv'
            ? "df = pd.read_csv('$stablePath', sep='\\t')"
            : "df = pd.read_csv('$stablePath')";
        requiredPackage = 'pandas';
        break;
      case 'xlsx':
      case 'xls':
        loadCode = "df = pd.read_excel('$stablePath')";
        requiredPackage = 'openpyxl';
        break;
      case 'parquet':
        loadCode = "df = pd.read_parquet('$stablePath')";
        requiredPackage = 'pyarrow';
        break;
      case 'json':
        loadCode = "df = pd.read_json('$stablePath')";
        requiredPackage = 'pandas';
        break;
      default:
        return null;
    }

    // Quick preview - get shape and columns
    final previewCode = '''
import pandas as pd
$loadCode
print(f"Shape: {df.shape[0]} rows x {df.shape[1]} columns")
print(f"Columns: {', '.join(df.columns.tolist())}")
print(f"Dtypes:\\n{df.dtypes.to_string()}")
print("---PREVIEW---")
print(df.head(5).to_string())
''';

    final executor = PythonExecutor();
    final result = await executor.execute(previewCode, timeoutSeconds: 15);

    String? preview;
    int? rows;
    int? cols;
    List<String>? columns;

    if (result.success) {
      final lines = result.cleanOutput.split('\n');
      for (final line in lines) {
        if (line.startsWith('Shape: ')) {
          final match = RegExp(r'(\d+) rows x (\d+) columns').firstMatch(line);
          if (match != null) {
            rows = int.tryParse(match.group(1)!);
            cols = int.tryParse(match.group(2)!);
          }
        } else if (line.startsWith('Columns: ')) {
          columns = line.substring(9).split(', ');
        }
      }
      final previewIdx = result.cleanOutput.indexOf('---PREVIEW---');
      if (previewIdx > 0) {
        preview = result.cleanOutput.substring(previewIdx + 14).trim();
      }
    }

    return SpreadsheetInfo(
      filePath: stablePath,
      fileName: fileName,
      loadCode: loadCode,
      requiredPackage: requiredPackage,
      rows: rows ?? 0,
      cols: cols ?? 0,
      columns: columns ?? [],
      preview: preview ?? '',
    );
  }
}

class SpreadsheetInfo {
  final String filePath;
  final String fileName;
  final String loadCode;
  final String requiredPackage;
  final int rows;
  final int cols;
  final List<String> columns;
  final String preview;

  SpreadsheetInfo({
    required this.filePath,
    required this.fileName,
    required this.loadCode,
    required this.requiredPackage,
    required this.rows,
    required this.cols,
    required this.columns,
    required this.preview,
  });

  /// Generate boilerplate code cell for working with this data
  String get boilerplateCode => '''
import pandas as pd

# Load data: $fileName ($rows rows x $cols columns)
$loadCode

# Preview
print(df.head())
print(f"\\nShape: {df.shape}")
print(f"Columns: {list(df.columns)}")
''';
}
