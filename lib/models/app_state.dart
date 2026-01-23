// models/app_state.dart
// Global app state - matches Swift AppState

import 'package:equatable/equatable.dart';

/// Authentication and user profile state
class AppState extends Equatable {
  final bool isAuthenticated;
  final bool isTestAccount;
  final String? displayName;
  final String? avatarUrl;
  final String? xaeroShortId;
  final String? nodeId;
  
  const AppState({
    this.isAuthenticated = false,
    this.isTestAccount = false,
    this.displayName,
    this.avatarUrl,
    this.xaeroShortId,
    this.nodeId,
  });
  
  /// Create authenticated state from identity
  factory AppState.authenticated({
    required String shortId,
    required String nodeId,
    String? displayName,
    String? avatarUrl,
    bool isTest = false,
  }) {
    return AppState(
      isAuthenticated: true,
      isTestAccount: isTest,
      displayName: displayName ?? (isTest ? 'Test User ($shortId)' : null),
      avatarUrl: avatarUrl,
      xaeroShortId: shortId,
      nodeId: nodeId,
    );
  }
  
  /// Sign out - return to initial state
  AppState signOut() {
    return const AppState();
  }
  
  /// Update profile info
  AppState copyWith({
    bool? isAuthenticated,
    bool? isTestAccount,
    String? displayName,
    String? avatarUrl,
    String? xaeroShortId,
    String? nodeId,
  }) {
    return AppState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isTestAccount: isTestAccount ?? this.isTestAccount,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      xaeroShortId: xaeroShortId ?? this.xaeroShortId,
      nodeId: nodeId ?? this.nodeId,
    );
  }
  
  @override
  List<Object?> get props => [
    isAuthenticated,
    isTestAccount,
    displayName,
    avatarUrl,
    xaeroShortId,
    nodeId,
  ];
}

/// XaeroIdentity - matches Swift XaeroIdentity
class XaeroIdentity {
  final String secretKeyHex;
  final String publicKeyHex;
  final String shortId;
  final String? displayName;
  final String? avatarUrl;
  
  const XaeroIdentity({
    required this.secretKeyHex,
    required this.publicKeyHex,
    required this.shortId,
    this.displayName,
    this.avatarUrl,
  });
  
  /// Create from JSON (e.g., from secure storage)
  factory XaeroIdentity.fromJson(Map<String, dynamic> json) {
    return XaeroIdentity(
      secretKeyHex: json['secret_key_hex'] as String,
      publicKeyHex: json['public_key_hex'] as String,
      shortId: json['short_id'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
  
  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'secret_key_hex': secretKeyHex,
      'public_key_hex': publicKeyHex,
      'short_id': shortId,
      if (displayName != null) 'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    };
  }
}
