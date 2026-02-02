// models/xaero_identity.dart
// XaeroIdentity - Matches Swift XaeroIdentity.swift exactly
// Ed25519 secret key, derived public key, DID
// Stored in flutter_secure_storage (equiv of Keychain)

import 'dart:convert';

class XaeroIdentity {
  final String secretKeyHex;  // 64 hex chars = 32 bytes - THE secret
  final String publicKeyHex;  // 64 hex chars = 32 bytes - derived from secret
  final String did;           // did:peer:z{base58(blake3(pubkey))}
  final DateTime createdAt;

  // Optional metadata from OAuth
  String? email;
  String? displayName;
  String? avatarUrl;

  XaeroIdentity({
    required this.secretKeyHex,
    required this.publicKeyHex,
    required this.did,
    required this.createdAt,
    this.email,
    this.displayName,
    this.avatarUrl,
  });

  /// Short display ID (first 8 chars of DID suffix) - matches Swift
  String get shortId {
    final suffix = did.replaceFirst('did:peer:z', '');
    return suffix.length > 8 ? suffix.substring(0, 8) : suffix;
  }

  /// Is this a test/ephemeral identity
  bool get isTest => secretKeyHex == 'ephemeral' || secretKeyHex.startsWith('0000');

  /// Full DID string
  String get fullDid => did;

  factory XaeroIdentity.fromJson(Map<String, dynamic> json) {
    return XaeroIdentity(
      secretKeyHex: json['secret_key'] as String? ?? json['secret_key_hex'] as String? ?? json['secretKeyHex'] as String? ?? '',
      publicKeyHex: json['pubkey'] as String? ?? json['public_key'] as String? ?? json['publicKeyHex'] as String? ?? '',
      did: json['did'] as String? ?? '',
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
      email: json['email'] as String?,
      displayName: json['display_name'] as String? ?? json['displayName'] as String?,
      avatarUrl: json['avatar_url'] as String? ?? json['avatarUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'secret_key': secretKeyHex,
    'pubkey': publicKeyHex,
    'did': did,
    'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
    'email': email,
    'display_name': displayName,
    'avatar_url': avatarUrl,
  };

  XaeroIdentity copyWith({
    String? secretKeyHex,
    String? publicKeyHex,
    String? did,
    DateTime? createdAt,
    String? email,
    String? displayName,
    String? avatarUrl,
  }) {
    return XaeroIdentity(
      secretKeyHex: secretKeyHex ?? this.secretKeyHex,
      publicKeyHex: publicKeyHex ?? this.publicKeyHex,
      did: did ?? this.did,
      createdAt: createdAt ?? this.createdAt,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  static DateTime _parseDate(dynamic val) {
    if (val == null) return DateTime.now();
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val * 1000);
    if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
    if (val is num) return DateTime.fromMillisecondsSinceEpoch(val.toInt() * 1000);
    return DateTime.now();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is XaeroIdentity && other.did == did;

  @override
  int get hashCode => did.hashCode;

  @override
  String toString() => 'XaeroIdentity(${shortId}, ${displayName ?? email ?? "anon"})';
}
