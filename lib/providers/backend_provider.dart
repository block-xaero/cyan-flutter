// providers/backend_provider.dart
// Provides backend state and status

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/cyan_service.dart';

/// Backend connection state
enum BackendStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class BackendState {
  final BackendStatus status;
  final String? nodeId;
  final int objectCount;
  final int peerCount;
  final String? errorMessage;
  
  const BackendState({
    this.status = BackendStatus.disconnected,
    this.nodeId,
    this.objectCount = 0,
    this.peerCount = 0,
    this.errorMessage,
  });
  
  bool get isConnected => status == BackendStatus.connected;
  bool get isConnecting => status == BackendStatus.connecting;
  bool get hasError => status == BackendStatus.error;
  
  String get shortNodeId {
    if (nodeId == null || nodeId!.length < 8) return '...';
    return nodeId!.substring(0, 8);
  }
  
  BackendState copyWith({
    BackendStatus? status,
    String? nodeId,
    int? objectCount,
    int? peerCount,
    String? errorMessage,
  }) {
    return BackendState(
      status: status ?? this.status,
      nodeId: nodeId ?? this.nodeId,
      objectCount: objectCount ?? this.objectCount,
      peerCount: peerCount ?? this.peerCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class BackendNotifier extends StateNotifier<BackendState> {
  BackendNotifier() : super(const BackendState()) {
    _checkInitialStatus();
  }
  
  void _checkInitialStatus() {
    final service = CyanService.instance;
    if (service.isReady) {
      state = BackendState(
        status: BackendStatus.connected,
        nodeId: service.nodeId,
        objectCount: service.objectCount,
        peerCount: service.peerCount,
      );
    }
  }
  
  void setConnecting() {
    state = state.copyWith(status: BackendStatus.connecting);
  }
  
  void setConnected({
    required String nodeId,
    int objectCount = 0,
    int peerCount = 0,
  }) {
    state = BackendState(
      status: BackendStatus.connected,
      nodeId: nodeId,
      objectCount: objectCount,
      peerCount: peerCount,
    );
  }
  
  void setError(String message) {
    state = state.copyWith(
      status: BackendStatus.error,
      errorMessage: message,
    );
  }
  
  void setDisconnected() {
    state = const BackendState(status: BackendStatus.disconnected);
  }
  
  void updateStats({int? objectCount, int? peerCount}) {
    state = state.copyWith(
      objectCount: objectCount,
      peerCount: peerCount,
    );
  }
  
  void refresh() {
    final service = CyanService.instance;
    if (service.isReady) {
      state = state.copyWith(
        objectCount: service.objectCount,
        peerCount: service.peerCount,
      );
    }
  }
}

final backendProvider = StateNotifierProvider<BackendNotifier, BackendState>((ref) {
  return BackendNotifier();
});

/// Convenience providers
final isBackendConnectedProvider = Provider<bool>((ref) {
  return ref.watch(backendProvider).isConnected;
});

final nodeIdProvider = Provider<String?>((ref) {
  return ref.watch(backendProvider).nodeId;
});
