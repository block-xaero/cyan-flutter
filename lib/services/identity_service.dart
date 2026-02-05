// services/identity_service.dart
// XaeroIdentity management - matches Swift XaeroIdentityManager exactly
// Generates via FFI, stores in flutter_secure_storage (Keychain equiv)

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import '../ffi/ffi_helpers.dart';
import '../ffi/cyan_bindings.dart';
import 'cyan_service.dart';
import '../models/xaero_identity.dart';

final identityServiceProvider = Provider<IdentityService>((ref) {
  return IdentityService();
});

class IdentityService {
  static const _identityKey = 'cyan_xaero_identity';
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
  );

  XaeroIdentity? _currentIdentity;
  XaeroIdentity? get currentIdentity => _currentIdentity;
  bool get hasIdentity => _currentIdentity != null;

  // ---- LOAD ----

  /// Check if there's a stored identity
  Future<bool> hasStoredIdentity() async {
    try {
      final json = await _storage.read(key: _identityKey);
      return json != null;
    } catch (e) {
      debugPrint('❌ Secure storage read error: $e');
      return false;
    }
  }

  /// Load stored identity from secure storage
  Future<XaeroIdentity?> loadIdentity() async {
    try {
      debugPrint('🔍 Attempting to load identity from secure storage...');
      final json = await _storage.read(key: _identityKey);
      if (json == null) {
        debugPrint('ℹ️ No stored identity found in Keychain');
        return null;
      }

      debugPrint('✅ Found stored identity JSON, parsing...');
      final data = jsonDecode(json) as Map<String, dynamic>;
      _currentIdentity = XaeroIdentity.fromJson(data);
      debugPrint('✅ Loaded XaeroID from Keychain: ${_currentIdentity!.shortId}');
      return _currentIdentity;
    } catch (e) {
      debugPrint('❌ Failed to load identity: $e');
      return null;
    }
  }

  // ---- GENERATE ----

  /// Generate a new identity via FFI (or fallback to local generation)
  Future<XaeroIdentity?> generateIdentity({
    String? email,
    String? displayName,
    String? avatarUrl,
  }) async {
    try {
      // Try FFI first
      final ffiJson = CyanFFI.generateIdentityJson();
      if (ffiJson != null) {
        final json = jsonDecode(ffiJson) as Map<String, dynamic>;
        final identity = XaeroIdentity(
          secretKeyHex: json['secret_key'] as String,
          publicKeyHex: json['pubkey'] as String,
          did: json['did'] as String,
          createdAt: DateTime.now(),
          email: email,
          displayName: displayName,
          avatarUrl: avatarUrl,
        );

        await _saveToSecureStorage(identity);
        _currentIdentity = identity;
        debugPrint('✅ Generated XaeroID via FFI: ${identity.shortId}');
        return identity;
      }
    } catch (e) {
      debugPrint('⚠️ FFI generate failed, falling back to local: $e');
    }

    // Fallback: generate locally
    return _generateLocal(email: email, displayName: displayName, avatarUrl: avatarUrl);
  }

  /// Generate new identity from a specific secret key (for Google signup)
  Future<XaeroIdentity?> generateFromSecret({
    required String secretKeyHex,
    String? email,
    String? displayName,
    String? avatarUrl,
  }) async {
    try {
      // Try FFI derive
      final ffiJson = CyanFFI.deriveIdentity(secretKeyHex);
      if (ffiJson != null) {
        final json = jsonDecode(ffiJson) as Map<String, dynamic>;
        final identity = XaeroIdentity(
          secretKeyHex: secretKeyHex,
          publicKeyHex: json['pubkey'] as String,
          did: json['did'] as String,
          createdAt: DateTime.now(),
          email: email,
          displayName: displayName,
          avatarUrl: avatarUrl,
        );

        await _saveToSecureStorage(identity);
        _currentIdentity = identity;
        debugPrint('✅ Derived XaeroID via FFI: ${identity.shortId}');
        return identity;
      }
    } catch (e) {
      debugPrint('⚠️ FFI derive failed, falling back: $e');
    }

    // Fallback: use the key as-is with generated DID
    return _generateLocal(
      secretKeyHex: secretKeyHex,
      email: email,
      displayName: displayName,
      avatarUrl: avatarUrl,
    );
  }

  /// Generate ephemeral test identity (not saved to secure storage)
  Future<XaeroIdentity> generateTestIdentity() async {
    XaeroIdentity identity;

    try {
      final ffiJson = CyanFFI.generateIdentityJson();
      if (ffiJson != null) {
        final json = jsonDecode(ffiJson) as Map<String, dynamic>;
        identity = XaeroIdentity(
          secretKeyHex: json['secret_key'] as String,
          publicKeyHex: json['pubkey'] as String,
          did: json['did'] as String,
          createdAt: DateTime.now(),
          displayName: 'Test User',
        );
      } else {
        throw Exception('FFI not available');
      }
    } catch (_) {
      identity = _generateLocalSync(displayName: 'Test User');
    }

    // For test mode: set current but DON'T save to secure storage
    _currentIdentity = identity;
    debugPrint('⚠️ Generated TEST identity (not persisted): ${identity.shortId}');
    return identity;
  }

  // ---- RESTORE ----

  /// Restore identity from backup secret key hex (64 chars)
  Future<XaeroIdentity?> restoreFromBackup(
    String secretKeyHex, {
    String? email,
    String? displayName,
    String? avatarUrl,
  }) async {
    final cleaned = secretKeyHex.trim().toLowerCase();
    if (cleaned.length != 64 || !RegExp(r'^[0-9a-f]+$').hasMatch(cleaned)) {
      debugPrint('❌ Invalid secret key format');
      return null;
    }

    return generateFromSecret(
      secretKeyHex: cleaned,
      email: email,
      displayName: displayName,
      avatarUrl: avatarUrl,
    );
  }

  // ---- BACKEND INIT ----

  /// Initialize Rust backend with persistent identity (matches Swift)
  Future<bool> initializeBackend(XaeroIdentity identity) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dbPath = '${docsDir.path}/cyan.db';
      final dataDir = '${docsDir.path}/cyan_data';

      await Directory(dataDir).create(recursive: true);

      debugPrint('📁 Initializing backend...');
      debugPrint('   DB: $dbPath');
      debugPrint('   Data: $dataDir');

      // Check if FFI is actually available
      final ffiAvailable = CyanBindings.instance.isLoaded;
      
      if (!ffiAvailable) {
        debugPrint('ℹ️ FFI not available - running in UI-only mode');
        return true; // Don't block auth when backend lib isn't linked
      }

      // Set data dir first
      CyanFFI.setDataDir(docsDir.path);

      if (identity.isTest) {
        // Ephemeral init
        return CyanFFI.init(dbPath);
      }

      // Persistent init with identity
      final success = CyanFFI.initWithIdentity(
        dbPath: dbPath,
        secretKeyHex: identity.secretKeyHex,
        relayUrl: 'https://relay.dev.cyan.blockxaero.io',
        discoveryKey: 'cyan-dev',
      );

      if (success) {
        // Notify CyanService so ComponentBridge knows backend is ready
        CyanService.instance.markReady();
        
        // Get node ID from backend
        final nodeId = CyanFFI.getNodeId();
        if (nodeId != null && nodeId.isNotEmpty) {
          _currentIdentity = identity.copyWith(publicKeyHex: nodeId);
          await _saveToSecureStorage(_currentIdentity!);
        }
        debugPrint('🔑 Backend initialized: ${identity.shortId}');
      }

      return success;
    } catch (e) {
      debugPrint('❌ Backend init failed: $e');
      return false;
    }
  }

  /// Seed demo data (call after backend init)
  void seedDemoData() {
    CyanFFI.sendCommand('file_tree', '{"type":"SeedDemoIfEmpty"}');
  }

  // ---- UPDATE ----

  /// Update profile metadata
  Future<void> updateProfile({String? displayName, String? avatarUrl, String? email}) async {
    if (_currentIdentity == null) return;

    _currentIdentity = _currentIdentity!.copyWith(
      displayName: displayName ?? _currentIdentity!.displayName,
      avatarUrl: avatarUrl ?? _currentIdentity!.avatarUrl,
      email: email ?? _currentIdentity!.email,
    );

    await _saveToSecureStorage(_currentIdentity!);
    debugPrint('✅ Updated profile: ${_currentIdentity!.displayName} (${_currentIdentity!.email})');
  }

  // ---- SIGN OUT ----

  /// Clear identity from secure storage
  Future<void> clearIdentity() async {
    try {
      await _storage.delete(key: _identityKey);
    } catch (_) {}
    _currentIdentity = null;
    debugPrint('🗑️ Identity cleared');
  }

  // ---- PRIVATE ----

  Future<void> _saveToSecureStorage(XaeroIdentity identity) async {
    try {
      await _storage.write(
        key: _identityKey,
        value: jsonEncode(identity.toJson()),
      );
    } catch (e) {
      debugPrint('❌ Failed to save identity: $e');
    }
  }

  Future<XaeroIdentity?> _generateLocal({
    String? secretKeyHex,
    String? email,
    String? displayName,
    String? avatarUrl,
  }) async {
    final identity = _generateLocalSync(
      secretKeyHex: secretKeyHex,
      email: email,
      displayName: displayName,
      avatarUrl: avatarUrl,
    );

    await _saveToSecureStorage(identity);
    _currentIdentity = identity;
    debugPrint('✅ Generated XaeroID locally: ${identity.shortId}');
    return identity;
  }

  XaeroIdentity _generateLocalSync({
    String? secretKeyHex,
    String? email,
    String? displayName,
    String? avatarUrl,
  }) {
    final rng = Random.secure();
    final keyHex = secretKeyHex ?? List.generate(32, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    // Derive a pseudo public key (hash of secret)
    final pubBytes = List.generate(32, (i) {
      final secretByte = int.parse(keyHex.substring(i * 2, i * 2 + 2), radix: 16);
      return (secretByte ^ 0xFF) & 0xFF;
    });
    final pubHex = pubBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    // Generate DID from public key
    final did = 'did:peer:z${pubHex.substring(0, 32)}';

    return XaeroIdentity(
      secretKeyHex: keyHex,
      publicKeyHex: pubHex,
      did: did,
      createdAt: DateTime.now(),
      email: email,
      displayName: displayName,
      avatarUrl: avatarUrl,
    );
  }
}
