// providers/app_state_provider.dart
// Riverpod provider for app state management

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_state.dart';

/// Provider for app state
final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier();
});

/// Notifier for app state changes
class AppStateNotifier extends StateNotifier<AppState> {
  AppStateNotifier() : super(const AppState());
  
  /// Set authenticated state from identity
  void setAuthenticated({
    required String shortId,
    required String nodeId,
    String? displayName,
    String? avatarUrl,
    bool isTest = false,
  }) {
    state = AppState.authenticated(
      shortId: shortId,
      nodeId: nodeId,
      displayName: displayName,
      avatarUrl: avatarUrl,
      isTest: isTest,
    );
    print('✅ AppState: authenticated as $shortId');
  }
  
  /// Update profile info
  void updateProfile({
    String? displayName,
    String? avatarUrl,
  }) {
    state = state.copyWith(
      displayName: displayName,
      avatarUrl: avatarUrl,
    );
  }
  
  /// Sign out
  void signOut() {
    state = state.signOut();
    print('🚪 AppState: signed out');
  }
}

/// Convenience providers for specific state slices
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(appStateProvider).isAuthenticated;
});

final displayNameProvider = Provider<String?>((ref) {
  return ref.watch(appStateProvider).displayName;
});

final nodeIdProvider = Provider<String?>((ref) {
  return ref.watch(appStateProvider).nodeId;
});
