// providers/settings_identity_provider.dart
//
// Riverpod wiring for the Settings / Identity face — the SwiftUI `SettingsView`,
// `RosterPanel`, `ConstitutionEditorView` and `GrantQRView` quartet.
//
// Every read here goes through the ONE `CyanBackend` seam, so the whole face
// drives off `FakeCyanBackend` in a widget test with no dylib. Writes are made
// by the widgets themselves (`ref.read(cyanBackendProvider)`) and then land on
// screen by INVALIDATING the provider that read them — the engine stays the
// single source of truth, never a shadow copy in widget state.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Views/SettingsView.swift
//   cyan-iOS/Cyan/Cyan/Views/RosterPanel.swift        + ViewModels/RosterViewModel.swift
//   cyan-iOS/Cyan/Cyan/Views/ConstitutionEditorView.swift
//   cyan-iOS/Cyan/Cyan/Views/Auth/GrantQRView.swift   + ViewModels/GrantQRViewModel.swift

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/parity_models.dart';
import '../models/mesh_status.dart';
import 'cyan_backend_provider.dart';

// ---------------------------------------------------------------------------
// Device identity + preferences
// ---------------------------------------------------------------------------

/// Everything the Identity tab states about this device, read in ONE pass so
/// the panel can never show a node id from before a wipe next to a peer count
/// from after it.
@immutable
class DeviceIdentity {
  /// Null after `deleteIdentity` has wiped the vault — which is exactly what
  /// the tab renders as "no identity on this device".
  final DeviceProfile? profile;

  final MeshPresence presence;

  /// This device's X25519 bundle public key — the recipient key an inviter
  /// seals a `.cyangroup` export to.
  final String? bundlePubkey;

  /// The commit the loaded engine was built from, so a bug report names the
  /// exact binary. Null when no engine is loaded.
  final String? buildCommit;

  const DeviceIdentity({
    this.profile,
    this.presence = const MeshPresence.none(),
    this.bundlePubkey,
    this.buildCommit,
  });
}

final deviceIdentityProvider = FutureProvider<DeviceIdentity>((ref) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return DeviceIdentity(
    profile: await backend.myProfile(),
    presence: await backend.meshPresence(),
    bundlePubkey: await backend.bundlePubkey(),
    buildCommit: await backend.buildCommit(),
  );
});

/// The device's craft-role preference (`cyan_get_production_role`), or null
/// when unset. Device-LOCAL by construction — it is never synced.
final productionRoleProvider = FutureProvider<String?>((ref) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.getProductionRole();
});

/// The probe value the vocabulary read below spends. Any token the engine's
/// catalog cannot contain does the job; it is never persisted anywhere.
const String _vocabProbe = '?';

/// The craft-role vocabulary, ASKED OF THE ENGINE rather than hardcoded here.
/// `cyan_selector_resolve` refuses an unknown role with the list of what IS
/// allowed, so probing it is the documented way to read the catalog — the UI
/// never carries its own copy of a vocabulary the engine owns.
final craftRoleVocabProvider = FutureProvider<List<String>>((ref) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  final refusal = await backend.selectorResolve(_vocabProbe, _vocabProbe);
  return refusal.allowed;
});

/// Whether this device is behind a handle in one scope (a board / workspace id).
final anonymousStatusProvider =
    FutureProvider.family<AnonymousStatus, String>((ref, scopeId) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.getAnonymousStatus(scopeId);
});

// ---------------------------------------------------------------------------
// Roster
// ---------------------------------------------------------------------------

/// What a roster read is keyed by: the group whose members are listed, plus the
/// board that is open (its notes carry craft-role provenance — see
/// [RosterEntry.craftRole]). An empty [boardId] reads the group scope only.
@immutable
class RosterScope {
  final String groupId;
  final String boardId;

  const RosterScope(this.groupId, {this.boardId = ''});

  @override
  bool operator ==(Object other) =>
      other is RosterScope &&
      other.groupId == groupId &&
      other.boardId == boardId;

  @override
  int get hashCode => Object.hash(groupId, boardId);
}

/// One roster row: a persistent member of the group, the craft role the mesh
/// has stamped on them, and whether that member is this device.
@immutable
class RosterEntry {
  final GroupMember member;

  /// The member's craft role — `editor`, `producer`, … — or null when nothing
  /// on the mesh has stamped one for them yet. NEVER invented: for this device
  /// it is the `cyan_get_production_role` pref, and for everyone else it is the
  /// `author_role` the engine recorded on a note they authored. It is
  /// provenance, not authorization.
  final String? craftRole;

  final bool isMe;

  const RosterEntry({
    required this.member,
    this.craftRole,
    this.isMe = false,
  });

  /// A short, legible form of a raw node id — used only when no cached name
  /// exists, so the roster never shows a full `b34301…`.
  String get shortId {
    final id = member.peerId;
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}…${id.substring(id.length - 4)}';
  }

  /// The name shown in the roster: the cached profile name, else the short id.
  String get displayName {
    final name = member.name;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return shortId;
  }

  /// First letter for the avatar monogram.
  String get monogram {
    final base = displayName.isEmpty ? member.peerId : displayName;
    return base.isEmpty ? '?' : base.substring(0, 1).toUpperCase();
  }

  /// The presence line under the name. Live members read "Active now"; an
  /// offline member keeps its cached last-seen rather than dropping off.
  String get presenceLabel {
    if (member.online) return 'Active now';
    if (member.lastSeen <= 0) return 'Offline';
    return 'Last seen ${relativeAge(member.lastSeen)}';
  }

  /// The coarse relative-age string the SwiftUI roster shows ("just now",
  /// "5m ago", "2h ago", "3d ago").
  static String relativeAge(int unixSeconds, {DateTime? now}) {
    final nowSecs = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final delta = nowSecs - unixSeconds;
    if (delta < 60) return 'just now';
    if (delta < 3600) return '${delta ~/ 60}m ago';
    if (delta < 86400) return '${delta ~/ 3600}h ago';
    return '${delta ~/ 86400}d ago';
  }
}

/// The group's PERSISTENT roster — online members first, then the offline half
/// with its cached names — each row carrying the craft role the mesh stamped.
final groupRosterProvider =
    FutureProvider.family<List<RosterEntry>, RosterScope>((ref, scope) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();

  final members = await backend.getGroupMembers(scope.groupId);
  final profile = await backend.myProfile();
  final myRole = await backend.getProductionRole();

  // Craft-role provenance: the engine stamps `author_role` on every note it
  // persists, so what lands on screen is a role the mesh actually recorded.
  // Later writes win, the same LWW the ledger itself resolves by.
  final byName = <String, String>{};
  final byAuthorId = <String, String>{};
  // The ENGINE derives the tenant + anchor from what it is handed, so an open
  // board reads its OWN group's notes — reads match writes.
  final groupAnchor = scope.boardId.isNotEmpty ? scope.boardId : scope.groupId;
  final notes = <CyanNote>[
    ...await backend.noteListScoped(groupAnchor, 'group'),
    if (scope.boardId.isNotEmpty)
      ...await backend.noteListScoped(scope.boardId, 'board'),
  ]..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
  for (final note in notes) {
    final role = note.authorRole;
    if (role == null || role.isEmpty) continue;
    if (note.authorName.isNotEmpty) {
      byName[note.authorName.toLowerCase()] = role;
    }
    if (note.authorId.isNotEmpty) byAuthorId[note.authorId] = role;
  }

  final entries = <RosterEntry>[];
  for (final member in members) {
    final isMe = profile != null && member.peerId == profile.nodeId;
    final name = member.name?.trim().toLowerCase() ?? '';
    entries.add(RosterEntry(
      member: member,
      isMe: isMe,
      // This device answers with its own pref first — that is the role it
      // stamps everything it authors with from now on.
      craftRole: (isMe && myRole != null && myRole.isNotEmpty)
          ? myRole
          : byName[name] ?? byAuthorId[member.peerId],
    ));
  }

  entries.sort((a, b) {
    if (a.member.online != b.member.online) return a.member.online ? -1 : 1;
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  });
  return entries;
});

// ---------------------------------------------------------------------------
// Constitution
// ---------------------------------------------------------------------------

/// The on-device PREVIEW resolve for a board: the merged markdown, the
/// preference rows kept apart from it, the chain hash and the provenance. The
/// caller IS the device owner here, so the user scope is included.
final constitutionPreviewProvider =
    FutureProvider.family<ResolvedConstitution, String>((ref, boardId) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.constitutionResolved(boardId);
});

/// The HARD rules the engine classified off the same chain — a constraint a run
/// may not trade away, carrying its note text verbatim.
final constitutionHardRulesProvider =
    FutureProvider.family<EffectiveConstitution, String>((ref, boardId) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.constitutionEffective(boardId);
});

/// The group a board sits in. A GROUP-scope rule is anchored on the GROUP, so
/// this is the id the write is addressed with — the engine keys group notes by
/// the group, and a read of the chain looks for them there.
final boardGroupIdProvider =
    FutureProvider.family<String?, String>((ref, boardId) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  for (final group in await backend.loadGroups()) {
    for (final workspace in group.workspaces) {
      for (final board in workspace.boards) {
        if (board.id == boardId) return group.id;
      }
    }
  }
  return null;
});

/// The board's authored notes — the authorship + role surface under the editor.
final boardAuthorshipProvider =
    FutureProvider.family<List<CyanNote>, String>((ref, boardId) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.noteListScoped(boardId, 'board');
});
