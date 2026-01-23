// models/xaero_identity.dart
// XaeroID identity model

class XaeroIdentity {
  final String secretKeyHex;
  final String shortId;
  final String displayName;
  final String? avatarUrl;
  final String? nodeId;
  final bool isTest;
  
  const XaeroIdentity({
    required this.secretKeyHex,
    required this.shortId,
    required this.displayName,
    this.avatarUrl,
    this.nodeId,
    this.isTest = false,
  });
  
  factory XaeroIdentity.fromJson(Map<String, dynamic> json) {
    return XaeroIdentity(
      secretKeyHex: json['secret_key_hex'] as String? ?? '',
      shortId: json['short_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      nodeId: json['node_id'] as String?,
      isTest: json['is_test'] as bool? ?? false,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'secret_key_hex': secretKeyHex,
      'short_id': shortId,
      'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (nodeId != null) 'node_id': nodeId,
      'is_test': isTest,
    };
  }
  
  XaeroIdentity copyWith({
    String? secretKeyHex,
    String? shortId,
    String? displayName,
    String? avatarUrl,
    String? nodeId,
    bool? isTest,
  }) {
    return XaeroIdentity(
      secretKeyHex: secretKeyHex ?? this.secretKeyHex,
      shortId: shortId ?? this.shortId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      nodeId: nodeId ?? this.nodeId,
      isTest: isTest ?? this.isTest,
    );
  }
}
