// providers/auth_provider.dart
// Authentication state management with Google OAuth and XaeroID

import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AUTH STATE
// ═══════════════════════════════════════════════════════════════════════════

class AuthState {
  final bool isInitialized;
  final bool isAuthenticated;
  final bool isLoading;
  final XaeroIdentity? identity;
  final String? error;

  const AuthState({
    this.isInitialized = false,
    this.isAuthenticated = false,
    this.isLoading = false,
    this.identity,
    this.error,
  });

  AuthState copyWith({
    bool? isInitialized,
    bool? isAuthenticated,
    bool? isLoading,
    XaeroIdentity? identity,
    String? error,
    bool clearIdentity = false,
    bool clearError = false,
  }) {
    return AuthState(
      isInitialized: isInitialized ?? this.isInitialized,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      identity: clearIdentity ? null : (identity ?? this.identity),
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// Short ID for display (e.g., "abc12345")
  String? get shortId => identity?.shortId;

  /// Display name or email or short ID
  String get displayName {
    if (identity?.displayName != null) return identity!.displayName!;
    if (identity?.email != null) return identity!.email!;
    return shortId ?? 'Anonymous';
  }

  /// Avatar URL if available
  String? get avatarUrl => identity?.avatarUrl;
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTH PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

class AuthNotifier extends StateNotifier<AuthState> {
  static const _identityKey = 'xaero_identity';

  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);
    
    try {
      // Try to load existing identity
      final prefs = await SharedPreferences.getInstance();
      final identityJson = prefs.getString(_identityKey);
      
      if (identityJson != null) {
        final identity = XaeroIdentity.fromJson(jsonDecode(identityJson));
        
        // Initialize backend with identity
        final success = await _initializeBackend(identity);
        
        if (success) {
          state = state.copyWith(
            isInitialized: true,
            isAuthenticated: true,
            isLoading: false,
            identity: identity,
          );
          return;
        }
      }
      
      // No identity found
      state = state.copyWith(
        isInitialized: true,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isInitialized: true,
        isLoading: false,
        error: 'Failed to initialize: $e',
      );
    }
  }

  Future<bool> _initializeBackend(XaeroIdentity identity) async {
    // TODO: Call FFI to initialize backend
    // return cyan_init_with_identity(dbPath, identity.secretKeyHex, relayUrl, discoveryKey);
    return true; // Simulated
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generate a new identity (for new users or test mode)
  Future<bool> generateIdentity({
    String? email,
    String? displayName,
    String? avatarUrl,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // TODO: Call FFI to generate identity
      // final jsonPtr = xaero_generate_json();
      
      // Simulated identity generation
      final now = DateTime.now();
      final identity = XaeroIdentity(
        secretKeyHex: _generateRandomHex(64),
        publicKeyHex: _generateRandomHex(64),
        did: 'did:peer:z${_generateRandomHex(32)}',
        createdAt: now,
        email: email,
        displayName: displayName,
        avatarUrl: avatarUrl,
      );

      // Save to storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_identityKey, jsonEncode(identity.toJson()));

      // Initialize backend
      final success = await _initializeBackend(identity);

      if (success) {
        state = state.copyWith(
          isAuthenticated: true,
          isLoading: false,
          identity: identity,
        );
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to initialize backend',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to generate identity: $e',
      );
      return false;
    }
  }

  /// Sign in with Google OAuth
  Future<bool> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // TODO: Implement actual Google OAuth flow
      // 1. Open browser to Google OAuth URL
      // 2. Wait for callback with code
      // 3. Exchange code for tokens
      // 4. Get user info
      // 5. Generate or restore XaeroID

      // Simulated Google sign-in
      await Future.delayed(const Duration(seconds: 1));

      return await generateIdentity(
        email: 'user@example.com',
        displayName: 'Google User',
        avatarUrl: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Google sign-in failed: $e',
      );
      return false;
    }
  }

  /// Sign in as test user (no persistence)
  Future<bool> signInAsTest() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final now = DateTime.now();
      final identity = XaeroIdentity(
        secretKeyHex: _generateRandomHex(64),
        publicKeyHex: _generateRandomHex(64),
        did: 'did:peer:z${_generateRandomHex(32)}',
        createdAt: now,
        displayName: 'Test User',
      );

      // Don't persist test identity
      final success = await _initializeBackend(identity);

      if (success) {
        state = state.copyWith(
          isAuthenticated: true,
          isLoading: false,
          identity: identity,
        );
        return true;
      }
      
      state = state.copyWith(isLoading: false, error: 'Failed to initialize');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Test sign-in failed: $e');
      return false;
    }
  }

  /// Restore identity from QR code backup
  Future<bool> restoreFromBackup(String secretKeyHex) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // TODO: Call FFI to derive identity from secret key
      // final jsonPtr = xaero_derive_identity(secretKeyHex);

      // Simulated restoration
      final identity = XaeroIdentity(
        secretKeyHex: secretKeyHex,
        publicKeyHex: _generateRandomHex(64), // Would be derived
        did: 'did:peer:z${_generateRandomHex(32)}', // Would be derived
        createdAt: DateTime.now(),
      );

      // Save to storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_identityKey, jsonEncode(identity.toJson()));

      // Initialize backend
      final success = await _initializeBackend(identity);

      if (success) {
        state = state.copyWith(
          isAuthenticated: true,
          isLoading: false,
          identity: identity,
        );
        return true;
      }
      
      state = state.copyWith(isLoading: false, error: 'Failed to initialize');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Restore failed: $e');
      return false;
    }
  }

  /// Update profile metadata
  Future<void> updateProfile({
    String? displayName,
    String? avatarUrl,
  }) async {
    if (state.identity == null) return;

    final updated = XaeroIdentity(
      secretKeyHex: state.identity!.secretKeyHex,
      publicKeyHex: state.identity!.publicKeyHex,
      did: state.identity!.did,
      createdAt: state.identity!.createdAt,
      email: state.identity!.email,
      displayName: displayName ?? state.identity!.displayName,
      avatarUrl: avatarUrl ?? state.identity!.avatarUrl,
    );

    // Save to storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_identityKey, jsonEncode(updated.toJson()));

    state = state.copyWith(identity: updated);
  }

  /// Sign out
  Future<void> signOut() async {
    // Clear stored identity
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_identityKey);

    state = state.copyWith(
      isAuthenticated: false,
      clearIdentity: true,
    );
  }

  // Helper to generate random hex
  String _generateRandomHex(int length) {
    final chars = '0123456789abcdef';
    final buffer = StringBuffer();
    final rng = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < length; i++) {
      buffer.write(chars[(rng + i * 7) % 16]);
    }
    return buffer.toString();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONVENIENCE PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authProvider).identity?.publicKeyHex;
});

final userDisplayNameProvider = Provider<String>((ref) {
  return ref.watch(authProvider).displayName;
});
