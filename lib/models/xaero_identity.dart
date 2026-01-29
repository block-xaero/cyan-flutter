// models/xaero_identity.dart
// Identity model for XaeroID (Falcon-512 keypair)

import 'dart:convert';

class XaeroIdentity {
  final String secretKeyHex;
  final String shortId;
  final String displayName;
  final bool isTest;
  final String? nodeId;
  final DateTime createdAt;
  
  XaeroIdentity({
    required this.secretKeyHex,
    required this.shortId,
    required this.displayName,
    this.isTest = false,
    this.nodeId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  
  /// Public key is the node ID
  String get publicKey => nodeId ?? shortId;
  
  factory XaeroIdentity.fromJson(Map<String, dynamic> json) {
    return XaeroIdentity(
      secretKeyHex: json['secret_key_hex'] as String? ?? json['secretKeyHex'] as String? ?? '',
      shortId: json['short_id'] as String? ?? json['shortId'] as String? ?? '',
      displayName: json['display_name'] as String? ?? json['displayName'] as String? ?? 'Anonymous',
      isTest: json['is_test'] as bool? ?? json['isTest'] as bool? ?? false,
      nodeId: json['node_id'] as String? ?? json['nodeId'] as String?,
      createdAt: json['created_at'] != null 
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'secret_key_hex': secretKeyHex,
      'short_id': shortId,
      'display_name': displayName,
      'is_test': isTest,
      'node_id': nodeId,
      'created_at': createdAt.toIso8601String(),
    };
  }
  
  String toJsonString() => jsonEncode(toJson());
  
  static XaeroIdentity? fromJsonString(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return XaeroIdentity.fromJson(data);
    } catch (_) {
      return null;
    }
  }
  
  XaeroIdentity copyWith({
    String? secretKeyHex,
    String? shortId,
    String? displayName,
    bool? isTest,
    String? nodeId,
    DateTime? createdAt,
  }) {
    return XaeroIdentity(
      secretKeyHex: secretKeyHex ?? this.secretKeyHex,
      shortId: shortId ?? this.shortId,
      displayName: displayName ?? this.displayName,
      isTest: isTest ?? this.isTest,
      nodeId: nodeId ?? this.nodeId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is XaeroIdentity && other.shortId == shortId;
  }
  
  @override
  int get hashCode => shortId.hashCode;
  
  @override
  String toString() => 'XaeroIdentity($shortId, $displayName)';
}
