// tree_hydration_test.dart — TIER 2, the first SCREEN proved against the engine.
//
// real_engine_test.dart proves the engine loads. engine_roundtrip_test.dart
// proves a write survives a read. Neither says anything about the SEAM the
// parity screens actually depend on: `CyanBackend`. Every one of the 302 widget
// tests drives `FakeCyanBackend`, so a seam method that returns an honest empty
// forever passes all of them and ships a screen that renders nothing.
//
// This file drives the PRODUCTION seam — `CyanBackendFFI` — against a real
// seeded engine and asserts the Boards wall and the Explorer tree get REAL
// data: the seeded group names, their colours, the workspaces under them and
// the boards under those.
//
// WHAT IT CAUGHT. `loadGroups` used to derive the tree from the flat board list,
// which carries no names: every group came out called "Group", every group's
// `workspaces` list was empty, and the Explorer drew nothing over a database
// full of boards. That passes Tier-1 forever.
//
// SEEDING — `cyan_seed_demo`, NOT `cyan_seed_demo_if_empty`. The latter is an
// INERT no-op in this engine, kept only for ABI stability ("R10FB §D: demo
// seeding has been REMOVED", cyan-backend/src/ffi/core.rs). A test that seeded
// with it would assert against an empty database and prove nothing.
//
//   flutter test integration_test/tree_hydration_test.dart -d windows

import 'dart:io';

import 'package:cyan_flutter/ffi/cyan_backend_ffi.dart';
import 'package:cyan_flutter/ffi/ffi_helpers.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The demo seed is a FIXED, idempotent set (cyan-backend/src/seed.rs): three
/// distinctly-named groups, ten distinctly-named boards. Asserting against the
/// engine's own constants is what makes this a parity test rather than a
/// "something came back" test.
const _seededGroups = <String, ({String name, String color, int boards})>{
  'post-production': (name: 'Post-Production', color: '#22D3EE', boards: 4),
  'promos': (name: 'Trailers & Promos', color: '#A855F7', boards: 3),
  'broadcast': (name: 'Broadcast Delivery', color: '#34D399', boards: 3),
};

/// Every group is provisioned with these two workspaces and no others
/// (`storage::provision_group_workspaces`). "Plugins" is the interesting one:
/// it holds NO boards, so a tree derived from the board list can never show it.
const _seededWorkspaces = ['General', 'Plugins'];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final backend = CyanBackendFFI();
  List<CyanGroup> groups = const [];
  List<BoardWithContext> boards = const [];

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('cyan_tree_');

    // BEFORE the boot: the engine's `DATA_DIR` is a process-lifetime OnceCell
    // that defaults to ".", and its blob store roots at `<data>/blobs/<node>`.
    // Under `flutter test` that "." is the REPOSITORY.
    expect(CyanFFI.setDataDir(tmp.path), isTrue,
        reason: 'the engine refused ${tmp.path} as its data dir and would '
            'write its blob store into the source tree');

    // A throwaway identity in a throwaway directory — this suite must never be
    // able to damage a working install. Same boot the round trip uses, because
    // a bare `cyan_init` leaves no identity to stamp the seeded groups with.
    final ok = CyanFFI.initWithIdentity(
      dbPath: '${tmp.path}/cyan.db',
      secretKeyHex: List.filled(64, 'b').join(),
      relayUrl: '',
      discoveryKey: 'cyan-tree-hydration-test',
    );
    expect(ok, isTrue, reason: 'the engine refused to boot with an identity');

    await backend.initialize();

    // Fire-and-forget: the engine seeds on its command thread and emits
    // TreeLoaded when it lands, so poll the SEAM for the result rather than
    // sleeping a guessed interval. Polling the seam is also the point — it is
    // the thing under test.
    CyanFFI.seedDemo();
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      groups = await backend.loadGroups();
      if (groups.length >= _seededGroups.length) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    boards = await backend.loadAllBoards();
  });

  // The engine holds the database open for the life of the process and exports
  // no shutdown verb, so on Windows this unlink cannot succeed. Tolerate that
  // and name it; a bare catch would hide a real cleanup bug just as well.
  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException catch (e) {
      // ignore: avoid_print
      print('note: left ${tmp.path} for the OS to reap — the engine still holds '
          'the database open and has no shutdown verb to call. ($e)');
    }
  });

  test('the seam reads the seeded groups by NAME, not by placeholder', () {
    expect(groups, isNotEmpty,
        reason: 'the seam returned no groups against a seeded engine. Either '
            'the Snapshot command never reached the engine or its TreeLoaded '
            'answer was never drained — the Explorer would render empty over a '
            'database with three groups in it.');

    final byId = {for (final g in groups) g.id: g};
    for (final entry in _seededGroups.entries) {
      final g = byId[entry.key];
      expect(g, isNotNull, reason: 'seeded group ${entry.key} is missing');
      expect(g!.name, entry.value.name,
          reason: 'group ${entry.key} came back as "${g.name}". A name the '
              'engine did not supply means the tree was DERIVED, not read.');
      expect(g.colorHex, entry.value.color,
          reason: 'group ${entry.key} lost the colour it was seeded with');
    }
  });

  test('every group carries its workspaces — including the empty one', () {
    for (final entry in _seededGroups.entries) {
      final g = groups.firstWhere((g) => g.id == entry.key);
      expect(
        g.workspaces.map((w) => w.name).toSet(),
        _seededWorkspaces.toSet(),
        reason: 'group ${entry.key} came back with ${g.workspaces.length} '
            'workspaces. The Explorer tree and workspacesProvider are built '
            'entirely out of this list.',
      );
      for (final w in g.workspaces) {
        expect(w.groupId, g.id,
            reason: 'workspace ${w.id} is filed under the wrong group');
      }

      // The boards hang off the workspace, which is what the tree draws — and
      // "Plugins" holding none is exactly the row a board-derived tree could
      // never produce.
      final general = g.workspaces.firstWhere((w) => w.name == 'General');
      expect(general.boards, hasLength(entry.value.boards),
          reason: 'General in ${entry.key} should hold ${entry.value.boards} '
              'seeded boards');
      expect(g.workspaces.firstWhere((w) => w.name == 'Plugins').boards, isEmpty,
          reason: 'the Plugins workspace is seeded with no boards');
      for (final b in general.boards) {
        expect(b.workspaceId, general.id);
        expect(b.name, isNotEmpty);
      }
    }
  });

  test('the living wall names the real group behind every card', () {
    expect(boards, hasLength(10),
        reason: 'the seed lays down ten boards across the three groups');

    for (final b in boards) {
      expect(b.group.name, isNot('Unknown group'),
          reason: 'board "${b.board.name}" has no group name — the wall would '
              'caption it with a placeholder');
      expect(b.workspace.name, 'General',
          reason: 'every seeded board lives in its group\'s General workspace');
      final seeded = _seededGroups[b.group.id];
      expect(seeded, isNotNull,
          reason: 'board "${b.board.name}" points at unseeded group '
              '"${b.group.id}"');
      expect(b.group.name, seeded!.name);
      expect(b.group.colorHex, seeded.color);
    }

    // The seed marks every board deployed AND pinned (`mark_deployed` +
    // `board_meta_set_pinned`), which is what the living wall's running pill
    // and pin row are for. `cyan_get_all_boards` carries neither flag, so both
    // are separate reads and both used to come back false for every card.
    for (final b in boards) {
      expect(b.board.isDeployed, isTrue,
          reason: 'board "${b.board.name}" is deployed in the engine but the '
              'wall says it is not — the living wall would show a dead grid');
      expect(b.board.isPinned, isTrue,
          reason: 'every seeded board is pinned');
    }

    // The wall and the Explorer must agree about who owns what — they read the
    // board list and the tree through two different verbs, and a disagreement
    // means one of them is lying.
    final fromTree = <String, String>{
      for (final g in groups)
        for (final w in g.workspaces)
          for (final b in w.boards) b.id: g.id,
    };
    for (final b in boards) {
      expect(fromTree[b.board.id], b.group.id,
          reason: 'the wall files board ${b.board.id} under ${b.group.id}, the '
              'Explorer under ${fromTree[b.board.id]}');
    }
  });
}
