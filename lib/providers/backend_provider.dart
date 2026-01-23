// providers/backend_provider.dart
// Backend initialization and status
// Lifecycle uses direct FFI, status uses ComponentBridge pattern

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../ffi/ffi_helpers.dart';
import '../ffi/component_bridge.dart';

// ═══════════════════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════════════════

enum BackendStatus {
  uninitialized,
  initializing,
  ready,
  error,
}

class BackendState {
  final BackendStatus status;
  final String? nodeId;
  final String? errorMessage;
  final int objectCount;
  final int peerCount;
  
  const BackendState({
    this.status = BackendStatus.uninitialized,
    this.nodeId,
    this.errorMessage,
    this.objectCount = 0,
    this.peerCount = 0,
  });
  
  BackendState copyWith({
    BackendStatus? status,
    String? nodeId,
    String? errorMessage,
    int? objectCount,
    int? peerCount,
  }) {
    return BackendState(
      status: status ?? this.status,
      nodeId: nodeId ?? this.nodeId,
      errorMessage: errorMessage ?? this.errorMessage,
      objectCount: objectCount ?? this.objectCount,
      peerCount: peerCount ?? this.peerCount,
    );
  }
  
  bool get isReady => status == BackendStatus.ready;
}

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

final backendProvider = StateNotifierProvider<BackendNotifier, BackendState>((ref) {
  return BackendNotifier();
});

// ═══════════════════════════════════════════════════════════════════════════
// NOTIFIER
// ═══════════════════════════════════════════════════════════════════════════

class BackendNotifier extends StateNotifier<BackendState> {
  final _networkBridge = NetworkStatusBridge();
  StreamSubscription<NetworkStatusEvent>? _subscription;
  Timer? _statusTimer;
  
  BackendNotifier() : super(const BackendState());
  
  /// Initialize backend with identity
  /// This uses direct FFI since it's initialization, not command/event
  Future<bool> initialize({
    required String secretKeyHex,
    String relayUrl = 'https://quic.dev.cyan.blockxaero.io',
    String discoveryKey = 'cyan-dev',
  }) async {
    if (state.status == BackendStatus.initializing) {
      return false;
    }
    
    state = state.copyWith(status: BackendStatus.initializing);
    
    try {
      // Get documents directory (matches Swift's documentDirectory)
      final docsDir = await getApplicationDocumentsDirectory();
      final dbPath = '${docsDir.path}/cyan.db';
      final dataDir = '${docsDir.path}/cyan_data';
      
      print('📁 Backend: Initializing...');
      print('   DB path: $dbPath');
      print('   Data dir: $dataDir');
      
      // Initialize with identity (direct FFI - not command based)
      final success = CyanFFI.initWithIdentity(
        dbPath: dbPath,
        secretKeyHex: secretKeyHex,
        relayUrl: relayUrl,
        discoveryKey: discoveryKey,
      );
      
      if (!success) {
        state = state.copyWith(
          status: BackendStatus.error,
          errorMessage: 'Failed to initialize backend',
        );
        return false;
      }
      
      // Set data directory AFTER init (matches Swift pattern)
      CyanFFI.setDataDir(docsDir.path);
      
      // Wait for backend to be ready
      var attempts = 0;
      while (!CyanFFI.isReady() && attempts < 50) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
      
      if (!CyanFFI.isReady()) {
        state = state.copyWith(
          status: BackendStatus.error,
          errorMessage: 'Backend timeout',
        );
        return false;
      }
      
      // Get node ID
      final nodeId = CyanFFI.getNodeId();
      
      state = state.copyWith(
        status: BackendStatus.ready,
        nodeId: nodeId,
      );
      
      // Start network status bridge for events
      _startNetworkBridge();
      
      // Start status polling for stats
      _startStatusPolling();
      
      print('✅ Backend ready, node ID: ${nodeId?.substring(0, 16)}...');
      return true;
      
    } catch (e) {
      state = state.copyWith(
        status: BackendStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }
  
  void _startNetworkBridge() {
    _networkBridge.start();
    _subscription = _networkBridge.events.listen(_handleNetworkEvent);
  }
  
  void _handleNetworkEvent(NetworkStatusEvent event) {
    print('🌐 Network event: ${event.type}');
    
    if (event.isPeerConnected) {
      // Could update peer list here
    } else if (event.isPeerDisconnected) {
      // Could update peer list here
    }
  }
  
  /// Update status (called periodically for stats)
  void _updateStatus() {
    if (!CyanFFI.isReady()) return;
    
    final objectCount = CyanFFI.getObjectCount();
    final peerCount = CyanFFI.getTotalPeerCount();
    
    if (objectCount != state.objectCount || peerCount != state.peerCount) {
      state = state.copyWith(
        objectCount: objectCount,
        peerCount: peerCount,
      );
    }
  }
  
  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _updateStatus(),
    );
  }
  
  /// Check if backend is ready
  bool checkReady() {
    return CyanFFI.isReady();
  }
  
  /// Shutdown backend
  void shutdown() {
    _statusTimer?.cancel();
    _subscription?.cancel();
    _networkBridge.dispose();
    state = const BackendState();
  }
  
  @override
  void dispose() {
    _statusTimer?.cancel();
    _subscription?.cancel();
    _networkBridge.dispose();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONVENIENCE PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

final backendReadyProvider = Provider<bool>((ref) {
  return ref.watch(backendProvider).isReady;
});

final backendNodeIdProvider = Provider<String?>((ref) {
  return ref.watch(backendProvider).nodeId;
});

final objectCountProvider = Provider<int>((ref) {
  return ref.watch(backendProvider).objectCount;
});

final peerCountProvider = Provider<int>((ref) {
  return ref.watch(backendProvider).peerCount;
});
