// screens/debug_screen.dart
// Debug screen for testing FFI integration

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/monokai_theme.dart';
import '../providers/backend_provider.dart';
import '../ffi/ffi_helpers.dart';
import '../ffi/component_bridge.dart';

class DebugScreen extends ConsumerStatefulWidget {
  const DebugScreen({super.key});

  @override
  ConsumerState<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends ConsumerState<DebugScreen> {
  final List<String> _logs = [];
  bool _isInitializing = false;
  String? _lastEventJson;
  
  final _testSecretKey = '0' * 64;
  
  @override
  void initState() {
    super.initState();
    _log('🚀 Debug screen loaded');
    _log('Platform: ${Platform.operatingSystem}');
  }
  
  void _log(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
      if (_logs.length > 100) {
        _logs.removeAt(0);
      }
    });
  }
  
  Future<void> _initBackend() async {
    if (_isInitializing) return;
    
    setState(() => _isInitializing = true);
    _log('🔄 Initializing backend...');
    
    try {
      final backend = ref.read(backendProvider.notifier);
      final success = await backend.initialize(
        secretKeyHex: _testSecretKey,
      );
      
      if (success) {
        _log('✅ Backend initialized!');
        final state = ref.read(backendProvider);
        _log('   Node ID: ${state.nodeId?.substring(0, 16)}...');
      } else {
        final state = ref.read(backendProvider);
        _log('❌ Backend init failed: ${state.errorMessage}');
      }
    } catch (e) {
      _log('❌ Exception: $e');
    } finally {
      setState(() => _isInitializing = false);
    }
  }
  
  void _checkReady() {
    final ready = CyanFFI.isReady();
    _log('Backend ready: ${ready ? '✅ Yes' : '❌ No'}');
  }
  
  void _getNodeId() {
    final nodeId = CyanFFI.getNodeId();
    if (nodeId != null) {
      _log('Node ID: ${nodeId.substring(0, 32)}...');
    } else {
      _log('Node ID: null (not initialized)');
    }
  }
  
  void _seedDemo() {
    _log('🌱 Seeding demo data...');
    final success = CyanFFI.seedDemoIfEmpty();
    _log('Seed result: ${success ? '✅' : '❌'}');
  }
  
  void _sendSnapshotCommand() {
    _log('📤 Sending snapshot command...');
    final command = FileTreeCommand.snapshot();
    final success = CyanFFI.sendCommand('file_tree', command.toJson());
    _log('Send result: ${success ? '✅' : '❌'}');
  }
  
  void _pollEvents() {
    _log('📥 Polling file_tree events...');
    final json = CyanFFI.pollEvents('file_tree');
    if (json != null && json.isNotEmpty) {
      _log('Got event: ${json.length} chars');
      setState(() => _lastEventJson = json);
      
      try {
        final data = jsonDecode(json);
        final type = data['type'];
        _log('   Type: $type');
        
        if (type == 'TreeLoaded' && data['snapshot'] != null) {
          final snapshot = data['snapshot'];
          final groups = (snapshot['groups'] as List?)?.length ?? 0;
          final workspaces = (snapshot['workspaces'] as List?)?.length ?? 0;
          final boards = (snapshot['whiteboards'] as List?)?.length ?? 0;
          _log('   Groups: $groups, Workspaces: $workspaces, Boards: $boards');
        }
      } catch (e) {
        _log('   Parse error: $e');
      }
    } else {
      _log('No events');
    }
  }
  
  void _getStats() {
    final objects = CyanFFI.getObjectCount();
    final peers = CyanFFI.getTotalPeerCount();
    _log('📊 Stats: $objects objects, $peers peers');
  }
  
  void _copyNodeId() {
    final nodeId = CyanFFI.getNodeId();
    if (nodeId != null) {
      Clipboard.setData(ClipboardData(text: nodeId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Node ID copied')),
      );
    }
  }
  
  void _copyLastEvent() {
    if (_lastEventJson != null) {
      Clipboard.setData(ClipboardData(text: _lastEventJson!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event JSON copied')),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final backendState = ref.watch(backendProvider);
    
    return Scaffold(
      backgroundColor: MonokaiTheme.background,
      appBar: AppBar(
        title: const Text('Cyan FFI Debug'),
        backgroundColor: MonokaiTheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () => setState(() => _logs.clear()),
            tooltip: 'Clear logs',
          ),
        ],
      ),
      body: Row(
        children: [
          // Left: Controls
          Container(
            width: 280,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: MonokaiTheme.surface,
              border: Border(
                right: BorderSide(color: MonokaiTheme.divider),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusCard(backendState),
                const SizedBox(height: 24),
                
                const Text(
                  'LIFECYCLE',
                  style: TextStyle(
                    color: MonokaiTheme.comment,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                _buildButton(
                  'Initialize Backend',
                  Icons.play_arrow,
                  _isInitializing ? null : _initBackend,
                  color: MonokaiTheme.green,
                ),
                _buildButton('Check Ready', Icons.check_circle, _checkReady),
                _buildButton('Get Node ID', Icons.fingerprint, _getNodeId),
                
                const SizedBox(height: 16),
                const Text(
                  'COMMANDS',
                  style: TextStyle(
                    color: MonokaiTheme.comment,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                _buildButton('Seed Demo Data', Icons.auto_fix_high, _seedDemo),
                _buildButton(
                  'Send Snapshot Cmd',
                  Icons.upload,
                  _sendSnapshotCommand,
                  color: MonokaiTheme.cyan,
                ),
                _buildButton(
                  'Poll Events',
                  Icons.download,
                  _pollEvents,
                  color: MonokaiTheme.purple,
                ),
                _buildButton('Get Stats', Icons.analytics, _getStats),
                
                const Spacer(),
                
                if (backendState.nodeId != null)
                  _buildButton(
                    'Copy Node ID',
                    Icons.copy,
                    _copyNodeId,
                    small: true,
                  ),
                if (_lastEventJson != null)
                  _buildButton(
                    'Copy Last Event',
                    Icons.copy_all,
                    _copyLastEvent,
                    small: true,
                  ),
              ],
            ),
          ),
          
          // Right: Logs
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: MonokaiTheme.surfaceLight,
                  child: Row(
                    children: [
                      const Icon(Icons.terminal, size: 16, color: MonokaiTheme.cyan),
                      const SizedBox(width: 8),
                      const Text(
                        'Console',
                        style: TextStyle(
                          color: MonokaiTheme.foreground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_logs.length} lines',
                        style: const TextStyle(
                          color: MonokaiTheme.comment,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: MonokaiTheme.background,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            log,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: _getLogColor(log),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatusCard(BackendState state) {
    final statusColor = switch (state.status) {
      BackendStatus.ready => MonokaiTheme.green,
      BackendStatus.error => MonokaiTheme.red,
      BackendStatus.initializing => MonokaiTheme.yellow,
      BackendStatus.uninitialized => MonokaiTheme.comment,
    };
    
    final statusText = switch (state.status) {
      BackendStatus.ready => 'Ready',
      BackendStatus.error => 'Error',
      BackendStatus.initializing => 'Initializing...',
      BackendStatus.uninitialized => 'Not Initialized',
    };
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MonokaiTheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MonokaiTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Backend: $statusText',
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (state.nodeId != null) ...[
            const SizedBox(height: 12),
            const Text(
              'Node ID',
              style: TextStyle(
                color: MonokaiTheme.comment,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${state.nodeId!.substring(0, 16)}...',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: MonokaiTheme.cyan,
              ),
            ),
          ],
          if (state.status == BackendStatus.ready) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatChip('Objects', state.objectCount),
                const SizedBox(width: 8),
                _buildStatChip('Peers', state.peerCount),
              ],
            ),
          ],
          if (state.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              state.errorMessage!,
              style: const TextStyle(
                color: MonokaiTheme.red,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildStatChip(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: MonokaiTheme.surfaceLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontSize: 11,
          color: MonokaiTheme.foreground,
        ),
      ),
    );
  }
  
  Widget _buildButton(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    Color? color,
    bool small = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: small ? 4 : 8),
      child: SizedBox(
        height: small ? 32 : 40,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: small ? 14 : 18),
          label: Text(
            label,
            style: TextStyle(fontSize: small ? 11 : 13),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? MonokaiTheme.surfaceLight,
            foregroundColor: color != null ? MonokaiTheme.background : MonokaiTheme.foreground,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
          ),
        ),
      ),
    );
  }
  
  Color _getLogColor(String log) {
    if (log.contains('✅')) return MonokaiTheme.green;
    if (log.contains('❌')) return MonokaiTheme.red;
    if (log.contains('⚠️')) return MonokaiTheme.yellow;
    if (log.contains('🔄')) return MonokaiTheme.cyan;
    if (log.contains('📤') || log.contains('📥')) return MonokaiTheme.purple;
    return MonokaiTheme.foreground;
  }
}
