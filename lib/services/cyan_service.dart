// services/cyan_service.dart
// Singleton service that manages Rust backend lifecycle
// Must be initialized before any ComponentBridge operations

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../ffi/ffi_helpers.dart';

/// Global provider for CyanService
final cyanServiceProvider = Provider<CyanService>((ref) => CyanService.instance);

/// Initialization state
enum CyanInitState { uninitialized, initializing, ready, error }

/// Service that manages Rust backend lifecycle
class CyanService {
  static final CyanService _instance = CyanService._();
  static CyanService get instance => _instance;
  
  CyanService._();
  
  CyanInitState _state = CyanInitState.uninitialized;
  CyanInitState get state => _state;
  
  String? _nodeId;
  String? get nodeId => _nodeId;
  
  String? _error;
  String? get error => _error;
  
  String? _dbPath;
  String? get dbPath => _dbPath;
  
  /// Initialize with ephemeral identity (for testing/development)
  Future<bool> initializeEphemeral() async {
    if (_state == CyanInitState.ready) return true;
    
    _state = CyanInitState.initializing;
    
    try {
      final dir = await getApplicationDocumentsDirectory();
      _dbPath = '${dir.path}/cyan.db';
      
      print('🚀 CyanService: Initializing (ephemeral) at $_dbPath');
      
      // Set data directory
      CyanFFI.setDataDir(dir.path);
      
      // Initialize with ephemeral identity
      final ok = CyanFFI.init(_dbPath!);
      
      if (ok) {
        _state = CyanInitState.ready;
        _nodeId = CyanFFI.getNodeId();
        print('✅ CyanService: Ready (ephemeral) - NodeID: ${_nodeId?.substring(0, 16)}...');
        
        // Seed demo data
        CyanFFI.seedDemoIfEmpty();
        
        return true;
      } else {
        _state = CyanInitState.error;
        _error = 'Failed to initialize backend';
        print('❌ CyanService: $_error');
        return false;
      }
    } catch (e) {
      _state = CyanInitState.error;
      _error = e.toString();
      print('❌ CyanService: Exception: $e');
      return false;
    }
  }
  
  /// Initialize with persistent identity from stored key
  Future<bool> initializeWithIdentity({
    required String secretKeyHex,
    String? relayUrl,
    String? discoveryKey,
  }) async {
    if (_state == CyanInitState.ready) return true;
    
    _state = CyanInitState.initializing;
    
    try {
      final dir = await getApplicationDocumentsDirectory();
      _dbPath = '${dir.path}/cyan.db';
      
      print('🚀 CyanService: Initializing (persistent) at $_dbPath');
      
      // Set data directory
      CyanFFI.setDataDir(dir.path);
      
      // Initialize with persistent identity
      final ok = CyanFFI.initWithIdentity(
        dbPath: _dbPath!,
        secretKeyHex: secretKeyHex,
        relayUrl: relayUrl ?? 'https://relay.iroh.network',
        discoveryKey: discoveryKey ?? 'cyan-prod',
      );
      
      if (ok) {
        _state = CyanInitState.ready;
        _nodeId = CyanFFI.getNodeId();
        print('✅ CyanService: Ready (persistent) - NodeID: ${_nodeId?.substring(0, 16)}...');
        return true;
      } else {
        _state = CyanInitState.error;
        _error = 'Failed to initialize backend with identity';
        print('❌ CyanService: $_error');
        return false;
      }
    } catch (e) {
      _state = CyanInitState.error;
      _error = e.toString();
      print('❌ CyanService: Exception: $e');
      return false;
    }
  }
  
  /// Check if backend is ready
  bool get isReady => _state == CyanInitState.ready && CyanFFI.isReady();
  
  /// Mark service as ready (called when backend was initialized externally)
  void markReady() {
    _state = CyanInitState.ready;
    _nodeId = CyanFFI.getNodeId();
    print('✅ CyanService: Marked ready externally - NodeID: ${_nodeId ?? "unknown"}');
  }
  
  /// Get object count from database
  int get objectCount => isReady ? CyanFFI.getObjectCount() : 0;
  
  /// Get connected peer count  
  int get peerCount => isReady ? CyanFFI.getTotalPeerCount() : 0;
  
  /// Get short node ID (first 8 chars)
  String get shortNodeId {
    if (_nodeId == null || _nodeId!.length < 8) return 'Unknown';
    return _nodeId!.substring(0, 8);
  }
  
  /// Get my profile from backend
  Map<String, dynamic>? getMyProfile() {
    if (!isReady) return null;
    final json = CyanFFI.getMyProfile();
    if (json == null) return null;
    try {
      return Map<String, dynamic>.from(
        (json is String) ? {} : json as Map,
      );
    } catch (_) {
      return null;
    }
  }
  
  // ============================================================================
  // BOARD METADATA OPERATIONS
  // ============================================================================
  
  /// Pin a board
  bool pinBoard(String boardId) {
    if (!isReady) return false;
    return CyanFFI.pinBoard(boardId);
  }
  
  /// Unpin a board
  bool unpinBoard(String boardId) {
    if (!isReady) return false;
    return CyanFFI.unpinBoard(boardId);
  }
  
  /// Toggle board pin status
  bool toggleBoardPin(String boardId, bool currentlyPinned) {
    if (currentlyPinned) {
      return unpinBoard(boardId);
    } else {
      return pinBoard(boardId);
    }
  }
  
  /// Set board labels
  bool setBoardLabels(String boardId, List<String> labels) {
    if (!isReady) return false;
    return CyanFFI.setBoardLabels(boardId, labels);
  }
  
  /// Add a label to board
  bool addBoardLabel(String boardId, List<String> currentLabels, String newLabel) {
    if (currentLabels.contains(newLabel)) return true;
    return setBoardLabels(boardId, [...currentLabels, newLabel]);
  }
  
  /// Remove a label from board
  bool removeBoardLabel(String boardId, List<String> currentLabels, String label) {
    return setBoardLabels(boardId, currentLabels.where((l) => l != label).toList());
  }
}
