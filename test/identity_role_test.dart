// test/identity_role_test.dart
//
// The RBAC vocabulary and the one enforcement seam. Pure model, no widgets.
//
// There was NO role model in the Windows app at all — no `Role`, no
// `AppAction`, no `authorize`, and nothing on the auth state carrying a role or
// a tenant. The only role strings in lib/ were two hardcoded lists that nothing
// fed. So every role-gated affordance was either absent or, worse, present and
// permanently denying.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Models/Identity.swift:24 / :75 / :97

import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/models/identity_role.dart';

void main() {
  test('the vocabulary is fixed and ordered low to high', () {
    expect(Role.values.map((r) => r.name),
        ['guest', 'viewer', 'member', 'admin', 'owner']);
    expect(Role.guest.rank, 0);
    expect(Role.owner.rank, 4);

    // Rank is what makes authority comparable at all.
    for (var i = 1; i < Role.values.length; i++) {
      expect(Role.values[i].rank, greaterThan(Role.values[i - 1].rank));
    }
  });

  test('the three capability predicates match the backend', () {
    expect(Role.values.where((r) => r.canAdminister).toList(),
        [Role.admin, Role.owner]);
    expect(Role.values.where((r) => r.canWrite).toList(),
        [Role.member, Role.admin, Role.owner]);
    expect(Role.values.every((r) => r.canRead), isTrue);
  });

  test('a role decodes case-insensitively and refuses anything else', () {
    // The grant role arrives from the backend on scan, and both spellings are
    // seen on the wire.
    expect(roleFromWire('owner'), Role.owner);
    expect(roleFromWire('Owner'), Role.owner);
    expect(roleFromWire('  ADMIN '), Role.admin);

    // Null rather than a default: guessing a role from a spelling nobody
    // recognises is how a viewer silently becomes an admin.
    for (final junk in const ['', '   ', 'superuser', 'root', null]) {
      expect(roleFromWire(junk), isNull, reason: '"$junk" is not a role');
    }
  });

  test('authorize is role rank against the action minimum', () {
    const gated = {
      AppAction.read: Role.guest,
      AppAction.runWorkflow: Role.member,
      AppAction.installPlugin: Role.admin,
      AppAction.publishPlugin: Role.admin,
      AppAction.codegenPlugin: Role.admin,
    };
    expect(gated.length, AppAction.values.length,
        reason: 'every action must declare a minimum');

    for (final entry in gated.entries) {
      expect(entry.key.minimumRole, entry.value);
      for (final role in Role.values) {
        expect(authorize(entry.key, role), role.rank >= entry.value.rank,
            reason: '${role.name} on ${entry.key.name}');
      }
    }
  });

  test('no session denies everything, read included', () {
    // Deliberate, and it matches Swift: a signed-out client has no tenant
    // scope, so there is nothing for `read` to be scoped to.
    for (final action in AppAction.values) {
      expect(authorize(action, null), isFalse, reason: action.name);
    }
  });

  test('a viewer cannot run a workflow and an owner can do everything', () {
    expect(authorize(AppAction.runWorkflow, Role.viewer), isFalse);
    expect(authorize(AppAction.runWorkflow, Role.member), isTrue);
    expect(authorize(AppAction.codegenPlugin, Role.member), isFalse,
        reason: 'the forge is admin and up');
    for (final action in AppAction.values) {
      expect(authorize(action, Role.owner), isTrue);
    }
  });
}
