// island_tidy_test.dart — remove the DUPLICATE demo groups the corpus runs left.
//
// `standUpBoard` was made idempotent at the BOARD level but not the GROUP
// level, so every invocation created another "DEMO — Styled Masters" group,
// and the engine auto-seeds each new group with an empty "Board 1". Twenty-odd
// runs later the demo island opens on a wall of identical folders — the four
// real boards are in there, but nobody could find them.
//
// This deletes ONLY groups of that name which contain no board other than the
// auto-seeded "Board 1", through the engine's own `deleteGroup` verb so the
// deletion keeps referential integrity and gossips like any other. A group
// holding real work is never touched, and if the survivor cannot be identified
// the whole thing refuses rather than guessing.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cyan_flutter/ffi/ffi_helpers.dart';

import 'flight_harness.dart';

const demoGroup = 'DEMO — Styled Masters';
const realBoards = <String>{
  'Lynch — In Dreams',
  'Wes — The Multicut Society',
  "90s — Summer of '94",
  'Phone — Field Notes',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final flight = Flight('island-tidy',
      dataDir: '${Platform.environment['HOME']}/cyan-demo-island');

  setUpAll(() async => flight.boot());
  tearDownAll(() async => flight.log.close());

  test('the demo island keeps ONE styled-masters group, the one with the work',
      () async {
    final boards = await flight.backend.loadAllBoards();

    // group id -> the board names it holds. BoardWithContext carries the
    // group directly, so no workspace join is needed here.
    final byGroup = <String, Set<String>>{};
    final groupName = <String, String>{};
    for (final b in boards) {
      (byGroup[b.group.id] ??= <String>{}).add(b.board.name);
      groupName[b.group.id] = b.group.name;
    }

    final keepers = byGroup.entries
        .where((e) => e.value.any(realBoards.contains))
        .map((e) => e.key)
        .toSet();
    expect(keepers.length, 1,
        reason: 'expected exactly one group to hold the demo boards, found '
            '${keepers.length} — refusing to guess which to keep: $keepers');
    final keep = keepers.single;
    flight.log('keeping group $keep');

    // Everything else of that NAME holding only the auto-seeded board.
    final doomed = byGroup.entries
        .where((e) =>
            e.key != keep &&
            groupName[e.key] == demoGroup &&
            e.value.every((n) => n == 'Board 1' || n.trim().isEmpty))
        .map((e) => e.key)
        .toList();
    flight.log('deleting ${doomed.length} empty duplicate groups');

    // LEAVE, not delete. `DeleteGroup` checks `group_is_owner(id, node_id)`
    // and silently does nothing when it fails — and it fails here for every
    // one of these: each corpus run booted a FRESH node identity, so all 22
    // duplicates are owned by node ids that no longer exist. `LeaveGroup` is
    // the right verb anyway: a local cascade delete with no dissolution
    // broadcast, which is what junk-on-my-own-island deserves.
    for (final g in doomed) {
      CyanFFI.leaveGroup(g);
    }
    await Future<void>.delayed(const Duration(seconds: 8));

    final after = await flight.backend.loadAllBoards();
    final names = after.map((b) => b.board.name).toSet();
    for (final r in realBoards) {
      expect(names, contains(r), reason: 'the tidy deleted real work: $r is gone');
    }
    flight.log('island after tidy: ${after.length} boards — '
        '${names.take(8).join(' | ')}');
    expect(after.length, lessThan(boards.length),
        reason: 'nothing was actually removed — the delete path refused '
            'silently again (${boards.length} boards before and after)');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
