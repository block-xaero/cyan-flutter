// models/identity_role.dart
//
// The fixed RBAC role vocabulary and the ONE enforcement seam the UI gates on.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Models/Identity.swift:24  (Role)
//   cyan-iOS/Cyan/Cyan/Models/Identity.swift:75  (AppAction)
//   cyan-iOS/Cyan/Cyan/Models/Identity.swift:97  (authorize)
//
// The vocabulary is shared VERBATIM with cyan-backend and cyan-lens, and the
// mapping from action to minimum role is the whole policy — there is no DSL and
// no per-object ACL. Permissions are computed.
//
// This decides what the UI SHOWS, never what the server allows: the engine and
// the lens re-check at every door. Which is exactly why it must not be
// approximated — a UI that offers an action the server will refuse teaches an
// operator to distrust the app, and one that hides an action they are entitled
// to is indistinguishable from the feature being missing.

/// The fixed role vocabulary, ordered low to high so [rank] is a single
/// comparable authority level.
enum Role {
  guest,
  viewer,
  member,
  admin,
  owner;

  /// Authority level: higher is more capable. guest(0) … owner(4).
  int get rank => index;

  /// Owner/Admin may administer — install and publish plugins, issue grants.
  /// Matches the backend's `Role::can_administer`.
  bool get canAdminister => rank >= Role.admin.rank;

  /// Owner/Admin/Member may write, i.e. run workflows. Viewer and Guest are
  /// read-only. Matches the backend's `Role::can_write`.
  bool get canWrite => rank >= Role.member.rank;

  /// Everyone in the vocabulary may read.
  bool get canRead => rank >= Role.guest.rank;

  /// How this role is spelled on the wire.
  String get wireValue => name;
}

/// Case-INSENSITIVE decode, returning null for anything outside the fixed
/// vocabulary.
///
/// Insensitive because we control the wire format in Tier-1 but the grant role
/// arrives from the backend on scan, and both `"Owner"` and `"owner"` are seen.
/// Null rather than a default, because guessing a role from a spelling nobody
/// recognises is how a viewer silently becomes an admin.
Role? roleFromWire(String? raw) {
  final value = raw?.trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  for (final role in Role.values) {
    if (role.name == value) return role;
  }
  return null;
}

/// The actions the UI gates on.
enum AppAction {
  /// Guest and up.
  read,

  /// Member and up.
  runWorkflow,

  /// Admin and up.
  installPlugin,

  /// Admin and up.
  publishPlugin,

  /// Admin and up — the forge's "Build a custom tool".
  codegenPlugin;

  /// The minimum role this action requires.
  Role get minimumRole => switch (this) {
        AppAction.read => Role.guest,
        AppAction.runWorkflow => Role.member,
        AppAction.installPlugin => Role.admin,
        AppAction.publishPlugin => Role.admin,
        AppAction.codegenPlugin => Role.admin,
      };
}

/// The single computed enforcement point: role x action -> allow or deny.
///
/// No session means no role means DENY EVERYTHING — including `read`. That is
/// deliberate and matches Swift: a signed-out client has no tenant scope, so
/// there is nothing for `read` to be scoped to.
bool authorize(AppAction action, Role? role) {
  if (role == null) return false;
  return role.rank >= action.minimumRole.rank;
}
