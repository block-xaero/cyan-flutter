// services/identity_service.dart
// Identity management - create, store, load XaeroID identities

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import '../ffi/ffi_helpers.dart';
import '../models/xaero_identity.dart';

final identityServiceProvider = Provider<IdentityService>((ref) {
  return IdentityService();
});

class IdentityService {
  static const _identityKey = 'cyan_identity';
  final _storage = const FlutterSecureStorage();
  
  XaeroIdentity? _currentIdentity;
  XaeroIdentity? get currentIdentity => _currentIdentity;
  
  /// Check if there's a stored identity
  Future<bool> hasStoredIdentity() async {
    final json = await _storage.read(key: _identityKey);
    return json != null;
  }
  
  /// Load stored identity
  Future<XaeroIdentity?> loadIdentity() async {
    try {
      final json = await _storage.read(key: _identityKey);
      if (json == null) return null;
      
      final data = jsonDecode(json) as Map<String, dynamic>;
      _currentIdentity = XaeroIdentity.fromJson(data);
      return _currentIdentity;
    } catch (e) {
      debugPrint('Failed to load identity: $e');
      return null;
    }
  }
  
  /// Create a new identity
  Future<XaeroIdentity> createIdentity({required String displayName}) async {
    // Generate a random secret key (64 hex chars = 32 bytes)
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final secretKeyHex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    
    final identity = XaeroIdentity(
      secretKeyHex: secretKeyHex,
      shortId: _generateShortId(),
      displayName: displayName,
      isTest: false,
    );
    
    // Store identity
    await _storage.write(key: _identityKey, value: jsonEncode(identity.toJson()));
    _currentIdentity = identity;
    
    return identity;
  }
  
  /// Create test identity with seeded demo data
  Future<XaeroIdentity> createTestIdentity() async {
    // Use a fixed test key for reproducibility
    const testSecretKey = '0000000000000000000000000000000000000000000000000000000000000000';
    
    final identity = XaeroIdentity(
      secretKeyHex: testSecretKey,
      shortId: 'TEST0001',
      displayName: 'Test User',
      isTest: true,
    );
    
    await _storage.write(key: _identityKey, value: jsonEncode(identity.toJson()));
    _currentIdentity = identity;
    
    return identity;
  }
  
  /// Initialize backend with identity
  Future<bool> initializeBackend(XaeroIdentity identity) async {
    try {
      // Get documents directory (matches Swift's documentDirectory)
      final docsDir = await getApplicationDocumentsDirectory();
      final dbPath = '${docsDir.path}/cyan.db';
      final dataDir = '${docsDir.path}/cyan_data';
      
      // Create data directory if needed
      final dataDirObj = Directory(dataDir);
      if (!await dataDirObj.exists()) {
        await dataDirObj.create(recursive: true);
      }
      
      print('📁 Initializing backend...');
      print('   DB path: $dbPath');
      print('   Data dir: $dataDir');
      
      // Initialize backend with db path (matches Swift)
      final success = CyanFFI.initWithIdentity(
        dbPath: dbPath,
        secretKeyHex: identity.secretKeyHex,
        relayUrl: 'https://quic.dev.cyan.blockxaero.io',
        discoveryKey: 'cyan-dev',
      );
      
      if (success) {
        // Set data directory AFTER init (matches Swift pattern)
        CyanFFI.setDataDir(docsDir.path);
        
        // Get node ID from backend
        final nodeId = CyanFFI.getNodeId();
        _currentIdentity = identity.copyWith(
          nodeId: (nodeId?.isNotEmpty ?? false) ? nodeId : null,
        );
        
        // Update stored identity with node ID
        await _storage.write(
          key: _identityKey,
          value: jsonEncode(_currentIdentity!.toJson()),
        );
      }
      
      return success;
    } catch (e) {
      debugPrint('Failed to initialize backend: $e');
      return false;
    }
  }
  
  /// Seed demo data - uses command pattern
  void seedDemoData() {
    CyanFFI.sendCommand('file_tree', '{"type":"SeedDemoIfEmpty"}');
  }
  
  /// Clear stored identity
  Future<void> clearIdentity() async {
    await _storage.delete(key: _identityKey);
    _currentIdentity = null;
  }
  
  String _generateShortId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
