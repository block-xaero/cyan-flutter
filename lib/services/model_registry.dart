// services/model_registry.dart
// Model cell backend - handles GGUF, ONNX, HuggingFace, Claude inference
// Models belong to boards → sync via board sync → discoverable by peers
// Matches Swift NotebookModelCell.swift pattern

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'python_executor.dart';

// ============================================================================
// MODEL TYPES
// ============================================================================

enum ModelKind {
  gguf('GGUF', 'Local LLM (llama.cpp)'),
  onnx('ONNX', 'ONNX Runtime model'),
  huggingface('HF', 'HuggingFace Transformers'),
  claude('Claude', 'Anthropic Claude API'),
  custom('Custom', 'Custom inference script');

  final String badge;
  final String description;
  const ModelKind(this.badge, this.description);

  static ModelKind fromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'gguf':
        return ModelKind.gguf;
      case 'onnx':
        return ModelKind.onnx;
      default:
        return ModelKind.custom;
    }
  }
}

class ModelInfo {
  final String id;
  final String name;
  final ModelKind kind;
  final String? filePath;
  final String? hfModelId; // e.g. "meta-llama/Llama-2-7b"
  final String? apiKey; // For Claude
  final String boardId;
  final int fileSizeMB;
  final List<String> capabilities; // text-generation, classification, etc.
  final DateTime addedAt;
  bool isLoaded;

  ModelInfo({
    required this.id,
    required this.name,
    required this.kind,
    this.filePath,
    this.hfModelId,
    this.apiKey,
    required this.boardId,
    this.fileSizeMB = 0,
    this.capabilities = const ['text-generation'],
    DateTime? addedAt,
    this.isLoaded = false,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'filePath': filePath,
        'hfModelId': hfModelId,
        'boardId': boardId,
        'fileSizeMB': fileSizeMB,
        'capabilities': capabilities,
        'addedAt': addedAt.toIso8601String(),
      };

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      kind: ModelKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => ModelKind.custom,
      ),
      filePath: json['filePath'] as String?,
      hfModelId: json['hfModelId'] as String?,
      boardId: json['boardId'] as String? ?? '',
      fileSizeMB: json['fileSizeMB'] as int? ?? 0,
      capabilities: (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ['text-generation'],
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class InferenceResult {
  final bool success;
  final String output;
  final String? error;
  final int? timingMs;
  final Map<String, dynamic>? metadata;

  InferenceResult({
    required this.success,
    this.output = '',
    this.error,
    this.timingMs,
    this.metadata,
  });
}

// ============================================================================
// MODEL REGISTRY
// ============================================================================

class ModelRegistry {
  static final ModelRegistry instance = ModelRegistry._();
  ModelRegistry._();

  final Map<String, ModelInfo> _models = {};
  String? _registryDir;

  List<ModelInfo> get models => _models.values.toList();

  /// Models for a specific board
  List<ModelInfo> modelsForBoard(String boardId) =>
      _models.values.where((m) => m.boardId == boardId).toList();

  /// All unique model names (for peer discovery)
  List<String> get modelNames => _models.values.map((m) => m.name).toSet().toList();

  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    _registryDir = '${dir.path}/cyan_models';
    await Directory(_registryDir!).create(recursive: true);
    await _loadRegistry();
  }

  // ---- IMPORT ----

  /// Import a local model file (GGUF/ONNX)
  Future<ModelInfo?> importLocalModel({
    required String filePath,
    required String boardId,
    String? name,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final ext = filePath.split('.').last.toLowerCase();
    final kind = ModelKind.fromExtension(ext);
    final fileName = filePath.split('/').last;
    final modelName = name ?? fileName.replaceAll(RegExp(r'\.(gguf|onnx)$'), '');
    final fileSize = (await file.length()) ~/ (1024 * 1024);

    // Copy to registry dir
    final destPath = '$_registryDir/$fileName';
    await file.copy(destPath);

    final model = ModelInfo(
      id: 'model_${DateTime.now().millisecondsSinceEpoch}',
      name: modelName,
      kind: kind,
      filePath: destPath,
      boardId: boardId,
      fileSizeMB: fileSize,
      capabilities: _detectCapabilities(kind),
    );

    _models[model.id] = model;
    await _saveRegistry();

    debugPrint('📦 Model imported: ${model.name} (${model.kind.badge}, ${model.fileSizeMB}MB)');
    return model;
  }

  /// Register a HuggingFace model (will download on first use)
  Future<ModelInfo> registerHuggingFaceModel({
    required String modelId,
    required String boardId,
  }) async {
    final model = ModelInfo(
      id: 'hf_${DateTime.now().millisecondsSinceEpoch}',
      name: modelId.split('/').last,
      kind: ModelKind.huggingface,
      hfModelId: modelId,
      boardId: boardId,
      capabilities: ['text-generation'],
    );

    _models[model.id] = model;
    await _saveRegistry();
    return model;
  }

  /// Register Claude API as a model
  ModelInfo registerClaudeModel({
    required String boardId,
    String? apiKey,
  }) {
    final model = ModelInfo(
      id: 'claude_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Claude Sonnet 4',
      kind: ModelKind.claude,
      apiKey: apiKey,
      boardId: boardId,
      capabilities: ['text-generation', 'code', 'analysis', 'vision'],
    );

    _models[model.id] = model;
    _saveRegistry();
    return model;
  }

  /// Remove a model
  Future<void> removeModel(String modelId) async {
    final model = _models.remove(modelId);
    if (model?.filePath != null) {
      try {
        await File(model!.filePath!).delete();
      } catch (_) {}
    }
    await _saveRegistry();
  }

  // ---- INFERENCE ----

  /// Run inference on a model
  Future<InferenceResult> runInference({
    required String modelId,
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.7,
  }) async {
    final model = _models[modelId];
    if (model == null) {
      return InferenceResult(success: false, error: 'Model not found');
    }

    final stopwatch = Stopwatch()..start();

    try {
      switch (model.kind) {
        case ModelKind.gguf:
          return await _inferGguf(model, prompt, maxTokens, temperature);
        case ModelKind.onnx:
          return await _inferOnnx(model, prompt);
        case ModelKind.huggingface:
          return await _inferHuggingFace(model, prompt, maxTokens);
        case ModelKind.claude:
          return await _inferClaude(model, prompt, maxTokens);
        case ModelKind.custom:
          return InferenceResult(success: false, error: 'Custom inference not configured');
      }
    } catch (e) {
      return InferenceResult(success: false, error: e.toString());
    } finally {
      stopwatch.stop();
    }
  }

  Future<InferenceResult> _inferGguf(
    ModelInfo model, String prompt, int maxTokens, double temperature,
  ) async {
    final env = PythonEnvironment.instance;
    if (!env.isReady) {
      return InferenceResult(success: false, error: 'Python not ready');
    }

    // Use llama-cpp-python
    final code = '''
import sys
import time

try:
    from llama_cpp import Llama
except ImportError:
    print("ERROR: llama-cpp-python not installed", file=sys.stderr)
    print("Install with: pip install llama-cpp-python", file=sys.stderr)
    sys.exit(1)

start = time.time()
llm = Llama(model_path="${model.filePath}", n_ctx=2048, verbose=False)
output = llm("${prompt.replaceAll('"', '\\"').replaceAll('\n', '\\n')}", max_tokens=$maxTokens, temperature=$temperature)
elapsed = int((time.time() - start) * 1000)

text = output["choices"][0]["text"]
print(text)
print(f"\\n[TIMING:{elapsed}ms]")
''';

    final executor = PythonExecutor();
    final result = await executor.execute(code, timeoutSeconds: 120);

    if (result.success) {
      final output = result.cleanOutput;
      int? timing;
      final timingMatch = RegExp(r'\[TIMING:(\d+)ms\]').firstMatch(output);
      if (timingMatch != null) {
        timing = int.tryParse(timingMatch.group(1)!);
      }
      final cleanOutput = output.replaceAll(RegExp(r'\[TIMING:\d+ms\]'), '').trim();
      return InferenceResult(success: true, output: cleanOutput, timingMs: timing);
    }

    return InferenceResult(success: false, error: result.stderr);
  }

  Future<InferenceResult> _inferOnnx(ModelInfo model, String prompt) async {
    final code = '''
import sys
try:
    import onnxruntime as ort
except ImportError:
    print("ERROR: onnxruntime not installed", file=sys.stderr)
    print("Install with: pip install onnxruntime", file=sys.stderr)
    sys.exit(1)

session = ort.InferenceSession("${model.filePath}")
input_names = [inp.name for inp in session.get_inputs()]
output_names = [out.name for out in session.get_outputs()]
print(f"Model loaded: {len(input_names)} inputs, {len(output_names)} outputs")
print(f"Input names: {input_names}")
print(f"Output names: {output_names}")
# Note: ONNX inference requires proper tokenization based on model type
print("ONNX model loaded successfully. Full inference requires model-specific tokenization.")
''';

    final executor = PythonExecutor();
    final result = await executor.execute(code, timeoutSeconds: 30);
    return InferenceResult(
      success: result.success,
      output: result.cleanOutput,
      error: result.success ? null : result.stderr,
    );
  }

  Future<InferenceResult> _inferHuggingFace(
    ModelInfo model, String prompt, int maxTokens,
  ) async {
    final code = '''
import sys
import time

try:
    from transformers import pipeline
except ImportError:
    print("ERROR: transformers not installed", file=sys.stderr)
    print("Install with: pip install transformers torch", file=sys.stderr)
    sys.exit(1)

start = time.time()
gen = pipeline("text-generation", model="${model.hfModelId}", device_map="auto")
result = gen("${prompt.replaceAll('"', '\\"')}", max_new_tokens=$maxTokens, do_sample=True)
elapsed = int((time.time() - start) * 1000)

text = result[0]["generated_text"]
print(text)
print(f"\\n[TIMING:{elapsed}ms]")
''';

    final executor = PythonExecutor();
    final result = await executor.execute(code, timeoutSeconds: 300);

    if (result.success) {
      final output = result.cleanOutput;
      int? timing;
      final timingMatch = RegExp(r'\[TIMING:(\d+)ms\]').firstMatch(output);
      if (timingMatch != null) timing = int.tryParse(timingMatch.group(1)!);
      return InferenceResult(
        success: true,
        output: output.replaceAll(RegExp(r'\[TIMING:\d+ms\]'), '').trim(),
        timingMs: timing,
      );
    }

    return InferenceResult(success: false, error: result.stderr);
  }

  Future<InferenceResult> _inferClaude(
    ModelInfo model, String prompt, int maxTokens,
  ) async {
    final apiKey = model.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      return InferenceResult(
        success: false,
        error: 'Claude API key not set. Configure in model settings.',
      );
    }

    final code = '''
import sys, json, time
try:
    import anthropic
except ImportError:
    # Fallback: use requests
    import requests
    start = time.time()
    resp = requests.post(
        "https://api.anthropic.com/v1/messages",
        headers={
            "x-api-key": "$apiKey",
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
        json={
            "model": "claude-sonnet-4-20250514",
            "max_tokens": $maxTokens,
            "messages": [{"role": "user", "content": "${prompt.replaceAll('"', '\\"').replaceAll('\n', '\\n')}"}],
        },
    )
    elapsed = int((time.time() - start) * 1000)
    data = resp.json()
    if "content" in data:
        text = data["content"][0]["text"]
        print(text)
        print(f"\\n[TIMING:{elapsed}ms]")
    else:
        print(json.dumps(data), file=sys.stderr)
        sys.exit(1)
    sys.exit(0)

start = time.time()
client = anthropic.Anthropic(api_key="$apiKey")
msg = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=$maxTokens,
    messages=[{"role": "user", "content": "${prompt.replaceAll('"', '\\"').replaceAll('\n', '\\n')}"}],
)
elapsed = int((time.time() - start) * 1000)
print(msg.content[0].text)
print(f"\\n[TIMING:{elapsed}ms]")
''';

    final executor = PythonExecutor();
    final result = await executor.execute(code, timeoutSeconds: 60);

    if (result.success) {
      final output = result.cleanOutput;
      int? timing;
      final timingMatch = RegExp(r'\[TIMING:(\d+)ms\]').firstMatch(output);
      if (timingMatch != null) timing = int.tryParse(timingMatch.group(1)!);
      return InferenceResult(
        success: true,
        output: output.replaceAll(RegExp(r'\[TIMING:\d+ms\]'), '').trim(),
        timingMs: timing,
      );
    }

    return InferenceResult(success: false, error: result.stderr);
  }

  List<String> _detectCapabilities(ModelKind kind) {
    switch (kind) {
      case ModelKind.gguf:
        return ['text-generation'];
      case ModelKind.onnx:
        return ['inference'];
      case ModelKind.huggingface:
        return ['text-generation'];
      case ModelKind.claude:
        return ['text-generation', 'code', 'analysis', 'vision'];
      case ModelKind.custom:
        return [];
    }
  }

  // ---- PERSISTENCE ----

  Future<void> _loadRegistry() async {
    try {
      final file = File('$_registryDir/registry.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List<dynamic>;
        for (final item in list) {
          final model = ModelInfo.fromJson(item as Map<String, dynamic>);
          _models[model.id] = model;
        }
        debugPrint('📦 Loaded ${_models.length} models from registry');
      }
    } catch (e) {
      debugPrint('📦 Registry load error: $e');
    }
  }

  Future<void> _saveRegistry() async {
    try {
      final file = File('$_registryDir/registry.json');
      final json = _models.values.map((m) => m.toJson()).toList();
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
    } catch (e) {
      debugPrint('📦 Registry save error: $e');
    }
  }
}
