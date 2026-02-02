// services/python_executor.dart
// Python code execution engine - uses system Python3
// Matches Swift PythonExecutor pattern:
//   - Detects system Python
//   - Wraps code with matplotlib/plotly chart capture
//   - pip install support
//   - Timeout + cancel

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// ============================================================================
// EXECUTION RESULT
// ============================================================================

class ExecutionResult {
  final bool success;
  final String stdout;
  final String stderr;
  final List<String> imagePaths; // Captured chart images
  final Duration executionTime;

  ExecutionResult({
    required this.success,
    this.stdout = '',
    this.stderr = '',
    this.imagePaths = const [],
    this.executionTime = Duration.zero,
  });

  /// Clean stdout without chart markers
  String get cleanOutput => stdout
      .split('\n')
      .where((l) => !l.startsWith('[CYAN_CHART:'))
      .join('\n')
      .trim();

  bool get hasOutput =>
      cleanOutput.isNotEmpty || imagePaths.isNotEmpty || stderr.isNotEmpty;

  String get formattedTime =>
      '${(executionTime.inMilliseconds / 1000).toStringAsFixed(2)}s';
}

// ============================================================================
// PYTHON ENVIRONMENT
// ============================================================================

class PythonEnvironment {
  static final PythonEnvironment instance = PythonEnvironment._();
  PythonEnvironment._();

  String? _pythonPath;
  String? _pipPath;
  bool _ready = false;
  List<String> _installedPackages = [];
  final ValueNotifier<String> statusMessage = ValueNotifier('');

  bool get isReady => _ready;
  String get pythonPath => _pythonPath ?? '/usr/bin/python3';
  List<String> get installedPackages => _installedPackages;

  static const _pythonSearchPaths = [
    '/opt/homebrew/bin/python3',
    '/usr/local/bin/python3',
    '/usr/bin/python3',
    '/Library/Frameworks/Python.framework/Versions/Current/bin/python3',
    '/Library/Frameworks/Python.framework/Versions/3.12/bin/python3',
    '/Library/Frameworks/Python.framework/Versions/3.11/bin/python3',
  ];

  /// Detect system Python3
  Future<void> initialize() async {
    statusMessage.value = 'Detecting Python...';

    for (final path in _pythonSearchPaths) {
      if (await File(path).exists()) {
        try {
          final result = await Process.run(path, ['--version']);
          if (result.exitCode == 0) {
            _pythonPath = path;
            _ready = true;
            statusMessage.value = 'Python ready: ${result.stdout.toString().trim()}';
            debugPrint('🐍 Python found at: $path');
            
            // Detect pip
            final pipResult = await Process.run(path, ['-m', 'pip', '--version']);
            if (pipResult.exitCode == 0) {
              _pipPath = path;
              debugPrint('🐍 pip available');
            }
            
            _loadInstalledPackages();
            return;
          }
        } catch (e) {
          continue;
        }
      }
    }

    statusMessage.value = 'Python3 not found. Install via Homebrew or python.org';
    _ready = false;
  }

  Future<void> _loadInstalledPackages() async {
    if (!_ready) return;
    try {
      final result = await Process.run(
        pythonPath,
        ['-m', 'pip', 'list', '--format=freeze'],
        environment: environment,
      );
      if (result.exitCode == 0) {
        _installedPackages = (result.stdout?.toString() ?? '')
            .split('\n')
            .where((l) => l.contains('=='))
            .map((l) => l.split('==').first!)
            .toList();
        debugPrint('🐍 Loaded ${_installedPackages.length} packages');
      }
    } catch (e) {
      debugPrint('🐍 Failed to list packages: $e');
    }
  }

  /// Install a pip package
  Future<ExecutionResult> installPackage(String packageName) async {
    if (!_ready) {
      return ExecutionResult(
        success: false,
        stderr: 'Python not ready',
      );
    }

    statusMessage.value = 'Installing $packageName...';

    try {
      final result = await Process.run(
        pythonPath,
        ['-m', 'pip', 'install', packageName],
        environment: environment,
      );

      final stdout = result.stdout?.toString() ?? '';
      final stderr = result.stderr?.toString() ?? '';

      if (result.exitCode == 0) {
        if (!_installedPackages.contains(packageName)) {
          _installedPackages.add(packageName);
        }
        statusMessage.value = '$packageName installed!';
        return ExecutionResult(success: true, stdout: stdout);
      } else {
        statusMessage.value = 'Install failed';
        return ExecutionResult(success: false, stderr: stderr);
      }
    } catch (e) {
      statusMessage.value = 'Install error: $e';
      return ExecutionResult(success: false, stderr: e.toString());
    }
  }

  /// Public environment vars for executor
  Map<String, String> get environment => {
        'PYTHONIOENCODING': 'utf-8',
        'PYTHONUNBUFFERED': '1',
        'PATH':
            '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${Platform.environment['PATH'] ?? ''}',
      };
}

// ============================================================================
// PYTHON EXECUTOR
// ============================================================================

class PythonExecutor {
  Process? _currentProcess;
  bool _isRunning = false;

  bool get isRunning => _isRunning;
  final env = PythonEnvironment.instance;

  /// Execute Python code, capturing stdout/stderr/images
  Future<ExecutionResult> execute(String code, {int timeoutSeconds = 60}) async {
    if (!env.isReady) {
      return ExecutionResult(
        success: false,
        stderr: 'Python not ready. Click "Verify Python" first.',
      );
    }

    _isRunning = true;
    final startTime = DateTime.now();

    // Create temp directory
    final tempDir = await _createTempDir();

    try {
      // Write wrapped code
      final wrappedCode = _wrapCode(code, tempDir.path);
      final scriptFile = File('${tempDir.path}/script.py');
      await scriptFile.writeAsString(wrappedCode);

      // Execute
      _currentProcess = await Process.start(
        env.pythonPath,
        ['-u', scriptFile.path],
        environment: env.environment,
      );

      final stdoutBuf = StringBuffer();
      final stderrBuf = StringBuffer();

      // Timeout
      final timer = Timer(Duration(seconds: timeoutSeconds), () {
        debugPrint('🐍 Timeout - killing process');
        _currentProcess?.kill();
      });

      _currentProcess!.stdout.transform(utf8.decoder).listen((data) {
        stdoutBuf.write(data);
      });
      _currentProcess!.stderr.transform(utf8.decoder).listen((data) {
        stderrBuf.write(data);
      });

      final exitCode = await _currentProcess!.exitCode;
      timer.cancel();

      // Collect generated images
      final images = await _collectImages(tempDir);

      final elapsed = DateTime.now().difference(startTime);

      return ExecutionResult(
        success: exitCode == 0,
        stdout: stdoutBuf.toString(),
        stderr: stderrBuf.toString(),
        imagePaths: images,
        executionTime: elapsed,
      );
    } catch (e) {
      return ExecutionResult(
        success: false,
        stderr: e.toString(),
        executionTime: DateTime.now().difference(startTime),
      );
    } finally {
      _isRunning = false;
      _currentProcess = null;
      // Cleanup temp dir after a delay (let images be read first)
      Future.delayed(const Duration(seconds: 5), () {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });
    }
  }

  void cancel() {
    _currentProcess?.kill();
    _currentProcess = null;
    _isRunning = false;
  }

  Future<Directory> _createTempDir() async {
    final appDir = await getTemporaryDirectory();
    final execId = DateTime.now().millisecondsSinceEpoch;
    final dir = Directory('${appDir.path}/cyan_exec_$execId');
    await dir.create(recursive: true);
    return dir;
  }

  String _wrapCode(String code, String outputDir) {
    return '''
# === Cyan Runtime Wrapper ===
import sys
import os

_CYAN_OUTPUT_DIR = "$outputDir"

# Configure matplotlib for non-interactive use
try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    
    _cyan_chart_counter = [0]
    _original_show = plt.show
    
    def _cyan_show(*args, **kwargs):
        _cyan_chart_counter[0] += 1
        fig = plt.gcf()
        path = os.path.join(_CYAN_OUTPUT_DIR, f"chart_{_cyan_chart_counter[0]}.png")
        fig.savefig(path, dpi=150, bbox_inches='tight', facecolor='#1e1e1e', edgecolor='none')
        plt.close(fig)
        print(f"[CYAN_CHART:{path}]")
    plt.show = _cyan_show
except ImportError:
    pass

# Also handle plotly
try:
    import plotly.io as pio
    pio.renderers.default = 'png'
    import plotly.graph_objects as go
    
    def _cyan_plotly_show(self, *args, **kwargs):
        _cyan_chart_counter[0] += 1
        path = os.path.join(_CYAN_OUTPUT_DIR, f"chart_{_cyan_chart_counter[0]}.png")
        self.write_image(path, width=800, height=500)
        print(f"[CYAN_CHART:{path}]")
    go.Figure.show = _cyan_plotly_show
except ImportError:
    pass

# === User Code ===

$code

# === Auto-save remaining figures ===
try:
    for i, fig_num in enumerate(plt.get_fignums()):
        _cyan_chart_counter[0] += 1
        fig = plt.figure(fig_num)
        path = os.path.join(_CYAN_OUTPUT_DIR, f"chart_{_cyan_chart_counter[0]}.png")
        fig.savefig(path, dpi=150, bbox_inches='tight', facecolor='#1e1e1e', edgecolor='none')
        print(f"[CYAN_CHART:{path}]")
        plt.close(fig)
except:
    pass
''';
  }

  Future<List<String>> _collectImages(Directory dir) async {
    final images = <String>[];
    try {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.png')) {
          images.add(entity.path);
        }
      }
    } catch (_) {}
    images.sort();
    return images;
  }
}

// ============================================================================
// SQL EXECUTOR
// ============================================================================

class SqlExecutor {
  final Map<String, _DbConnection> _connections = {};
  
  /// Add a database connection
  Future<bool> addConnection({
    required String name,
    required String type, // sqlite, postgres, mysql
    required String connectionString,
  }) async {
    try {
      if (type == 'sqlite') {
        // SQLite - connectionString is the file path
        _connections[name] = _DbConnection(
          name: name,
          type: type,
          connectionString: connectionString,
        );
        debugPrint('🗄️ SQLite connection added: $name -> $connectionString');
        return true;
      } else {
        // For Postgres/MySQL, we use Python with appropriate driver
        _connections[name] = _DbConnection(
          name: name,
          type: type,
          connectionString: connectionString,
        );
        debugPrint('🗄️ $type connection added: $name');
        return true;
      }
    } catch (e) {
      debugPrint('🗄️ Connection error: $e');
      return false;
    }
  }
  
  List<String> get connectionNames => _connections.keys.toList();
  
  /// Execute SQL via Python (supports SQLite, Postgres, MySQL)
  Future<SqlResult> execute(String query, {String? connectionName}) async {
    final env = PythonEnvironment.instance;
    if (!env.isReady) {
      return SqlResult(error: 'Python not ready');
    }
    
    final conn = connectionName != null 
        ? _connections[connectionName] 
        : _connections.values.firstOrNull;
    
    if (conn == null) {
      return SqlResult(error: 'No database connection. Add one first.');
    }
    
    final code = _buildSqlCode(query, conn);
    final executor = PythonExecutor();
    final result = await executor.execute(code, timeoutSeconds: 30);
    
    if (!result.success) {
      return SqlResult(error: result.stderr);
    }
    
    return _parseSqlOutput(result.cleanOutput);
  }
  
  String _buildSqlCode(String query, _DbConnection conn) {
    switch (conn.type) {
      case 'sqlite':
        return '''
import sqlite3
import json

conn = sqlite3.connect("${conn.connectionString}")
conn.row_factory = sqlite3.Row
cursor = conn.cursor()
cursor.execute("""${query.replaceAll('"', '\\"')}""")

if cursor.description:
    columns = [d[0] for d in cursor.description]
    rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
    print(json.dumps({"columns": columns, "rows": rows, "rowcount": len(rows)}))
else:
    print(json.dumps({"message": f"Query OK, {cursor.rowcount} rows affected"}))

conn.commit()
conn.close()
''';
      case 'postgres':
        return '''
import psycopg2
import json

conn = psycopg2.connect("${conn.connectionString}")
cursor = conn.cursor()
cursor.execute("""${query.replaceAll('"', '\\"')}""")

if cursor.description:
    columns = [d.name for d in cursor.description]
    rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
    print(json.dumps({"columns": columns, "rows": rows, "rowcount": len(rows)}, default=str))
else:
    print(json.dumps({"message": f"Query OK, {cursor.rowcount} rows affected"}))

conn.commit()
conn.close()
''';
      case 'mysql':
        return '''
import mysql.connector
import json

conn = mysql.connector.connect(${_buildMysqlConnect(conn.connectionString)})
cursor = conn.cursor(dictionary=True)
cursor.execute("""${query.replaceAll('"', '\\"')}""")

if cursor.description:
    columns = [d[0] for d in cursor.description]
    rows = cursor.fetchall()
    print(json.dumps({"columns": columns, "rows": rows, "rowcount": len(rows)}, default=str))
else:
    print(json.dumps({"message": f"Query OK, {cursor.rowcount} rows affected"}))

conn.commit()
conn.close()
''';
      default:
        return 'print("Unsupported database type: ${conn.type}")';
    }
  }
  
  String _buildMysqlConnect(String connStr) {
    // Parse connection string like: host=localhost;port=3306;user=root;password=pass;database=mydb
    final parts = connStr.split(';');
    return parts.map((p) {
      final kv = p.split('=');
      if (kv.length == 2) return '${kv[0]}="${kv[1]}"';
      return '';
    }).where((s) => s.isNotEmpty).join(', ');
  }
  
  SqlResult _parseSqlOutput(String output) {
    try {
      final data = jsonDecode(output) as Map<String, dynamic>;
      if (data.containsKey('columns')) {
        return SqlResult(
          columns: (data['columns'] as List).cast<String>(),
          rows: (data['rows'] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList(),
          rowCount: data['rowcount'] as int? ?? 0,
        );
      } else {
        return SqlResult(message: data['message'] as String? ?? 'OK');
      }
    } catch (e) {
      // Non-JSON output - just show as text
      if (output.isNotEmpty) {
        return SqlResult(message: output);
      }
      return SqlResult(error: 'Failed to parse result: $e');
    }
  }
}

class SqlResult {
  final List<String>? columns;
  final List<Map<String, dynamic>>? rows;
  final int rowCount;
  final String? message;
  final String? error;
  
  SqlResult({
    this.columns,
    this.rows,
    this.rowCount = 0,
    this.message,
    this.error,
  });
  
  bool get isError => error != null;
  bool get hasTable => columns != null && rows != null;
}

class _DbConnection {
  final String name;
  final String type;
  final String connectionString;
  
  _DbConnection({
    required this.name,
    required this.type,
    required this.connectionString,
  });
}
