// providers/auth_provider.dart
// Authentication state management
// Uses IdentityService (secure storage) + GoogleAuthManager (real OAuth)

import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/xaero_identity.dart';
import '../services/identity_service.dart';
import '../services/google_oauth.dart';

// ============================================================================
// AUTH STATE
// ============================================================================

class AuthState {
  final bool isInitialized;
  final bool isAuthenticated;
  final bool isLoading;
  final bool isTestAccount;
  final XaeroIdentity? identity;
  final String? error;

  const AuthState({
    this.isInitialized = false,
    this.isAuthenticated = false,
    this.isLoading = false,
    this.isTestAccount = false,
    this.identity,
    this.error,
  });

  AuthState copyWith({
    bool? isInitialized,
    bool? isAuthenticated,
    bool? isLoading,
    bool? isTestAccount,
    XaeroIdentity? identity,
    String? error,
    bool clearIdentity = false,
    bool clearError = false,
  }) {
    return AuthState(
      isInitialized: isInitialized ?? this.isInitialized,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      isTestAccount: isTestAccount ?? this.isTestAccount,
      identity: clearIdentity ? null : (identity ?? this.identity),
      error: clearError ? null : (error ?? this.error),
    );
  }

  String? get shortId => identity?.shortId;
  String? get avatarUrl => identity?.avatarUrl;
  String? get xaeroShortId => identity?.shortId;

  String get displayName {
    if (identity?.displayName != null && identity!.displayName!.isNotEmpty) {
      return identity!.displayName!;
    }
    if (identity?.email != null) return identity!.email!;
    if (isTestAccount) return 'Test User (${shortId ?? "?"})';
    return shortId ?? 'Anonymous';
  }
}

// ============================================================================
// AUTH PROVIDER
// ============================================================================

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref _ref;
  final _identityService = IdentityService();
  final _googleAuth = GoogleAuthManager();

  AuthNotifier(this._ref) : super(const AuthState()) {
    _init();
  }

  IdentityService get identityService => _identityService;

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);

    try {
      // Try to load existing identity from secure storage
      final identity = await _identityService.loadIdentity();

      if (identity != null) {
        // Initialize backend with stored identity
        final success = await _identityService.initializeBackend(identity);

        state = state.copyWith(
          isInitialized: true,
          isAuthenticated: success,
          isLoading: false,
          isTestAccount: identity.isTest,
          identity: identity,
          error: success ? null : 'Backend initialization failed',
        );

        if (success) {
          _identityService.seedDemoData();
        }
        return;
      }

      // No stored identity
      state = state.copyWith(isInitialized: true, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isInitialized: true,
        isLoading: false,
        error: 'Failed to initialize: $e',
      );
    }
  }

  // ---- GOOGLE SIGN UP ----

  /// Returns the identity + Google profile for BackupQR display
  /// Does NOT set authenticated yet - caller shows BackupQR first
  Future<({XaeroIdentity identity, String? displayName, String? avatarUrl})?> signUpWithGoogle() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Real Google OAuth
      final credential = await _googleAuth.authenticate();

      // Generate a new 32-byte random seed
      final rng = Random.secure();
      final seed = List.generate(32, (_) => rng.nextInt(256));
      final seedHex = seed.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      // Create XaeroID from seed + Google profile
      final identity = await _identityService.generateFromSecret(
        secretKeyHex: seedHex,
        email: credential.email,
        displayName: credential.name,
        avatarUrl: credential.picture,
      );

      if (identity == null) {
        state = state.copyWith(isLoading: false, error: 'Failed to create identity');
        return null;
      }

      state = state.copyWith(isLoading: false);

      // Return for BackupQR display - don't authenticate yet
      return (
        identity: identity,
        displayName: credential.name,
        avatarUrl: credential.picture,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Google sign-up failed: $e',
      );
      return null;
    }
  }

  /// Called after user confirms they saved backup key
  Future<bool> confirmGoogleSignUp(
    XaeroIdentity identity, {
    String? displayName,
    String? avatarUrl,
  }) async {
    state = state.copyWith(isLoading: true);

    final success = await _identityService.initializeBackend(identity);

    if (success) {
      _identityService.seedDemoData();
      state = state.copyWith(
        isAuthenticated: true,
        isLoading: false,
        isTestAccount: false,
        identity: identity.copyWith(
          displayName: displayName ?? identity.displayName,
          avatarUrl: avatarUrl ?? identity.avatarUrl,
        ),
      );
      return true;
    }

    state = state.copyWith(isLoading: false, error: 'Backend init failed');
    return false;
  }

  // ---- TEST ACCOUNT ----

  Future<bool> signInAsTest() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final identity = await _identityService.generateTestIdentity();
      final success = await _identityService.initializeBackend(identity);

      if (success) {
        _identityService.seedDemoData();
        state = state.copyWith(
          isAuthenticated: true,
          isLoading: false,
          isTestAccount: true,
          identity: identity,
        );
        return true;
      }

      state = state.copyWith(isLoading: false, error: 'Backend init failed');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Test sign-in failed: $e');
      return false;
    }
  }

  // ---- RESTORE FROM BACKUP ----

  Future<bool> restoreFromBackup(String secretKeyHex) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final identity = await _identityService.restoreFromBackup(secretKeyHex);

      if (identity == null) {
        state = state.copyWith(isLoading: false, error: 'Invalid backup key');
        return false;
      }

      final success = await _identityService.initializeBackend(identity);

      if (success) {
        _identityService.seedDemoData();
        state = state.copyWith(
          isAuthenticated: true,
          isLoading: false,
          isTestAccount: false,
          identity: identity,
        );
        return true;
      }

      state = state.copyWith(isLoading: false, error: 'Backend init failed');
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Restore failed: $e');
      return false;
    }
  }

  // ---- PROFILE UPDATE ----

  Future<void> updateProfile({String? displayName, String? avatarUrl}) async {
    if (state.identity == null) return;

    await _identityService.updateProfile(
      displayName: displayName,
      avatarUrl: avatarUrl,
    );

    state = state.copyWith(
      identity: state.identity!.copyWith(
        displayName: displayName ?? state.identity!.displayName,
        avatarUrl: avatarUrl ?? state.identity!.avatarUrl,
      ),
    );
  }

  // ---- SIGN OUT ----

  Future<void> signOut() async {
    await _identityService.clearIdentity();
    state = state.copyWith(
      isAuthenticated: false,
      isTestAccount: false,
      clearIdentity: true,
    );
  }
}

// ============================================================================
// CONVENIENCE PROVIDERS
// ============================================================================

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authProvider).identity?.publicKeyHex;
});

final userDisplayNameProvider = Provider<String>((ref) {
  return ref.watch(authProvider).displayName;
});
