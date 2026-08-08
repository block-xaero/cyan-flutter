// providers/board_lock_store.dart
//
// The board DEPLOY / LOCK / UNLOCK lifecycle, app side.
//
// A deployed workflow is LOCKED: its steps are frozen and the composer goes
// read-only, so an in-flight or scheduled run is never edited out from under
// itself. Unlock re-enables authoring.
//
// WHY A CLIENT-SIDE STORE and not a seam write: the engine exposes only the
// READ verb `cyan_board_workflow_state` (deployed / locked / dashboard
// available). There is no deploy/lock SETTER in the 157-verb export table — see
// `lib/ffi/cyan_bindings.dart`, which binds `boardWorkflowState` and nothing
// paired with it. So the lock the OPERATOR toggles lives here and is OR'd with
// the engine's own `deployed` truth wherever a gate reads it. This is a port of
// the same decision the Mac already took, for the same reason:
//
//   cyan-iOS/Cyan/Cyan/ViewModels/BoardLockStore.swift  (read-only reference)
//
// When the engine later grows a real lock setter this store becomes its local
// mirror, and no UI above it changes.
//
// NOT ported: Swift emits a tenant-scoped obs event on each toggle
// (`CyanObs.emit(.deploy/.lock/.unlock)`). There is no CyanObs port in this repo
// yet — `grep -rn "CyanObs" lib/` finds nothing — so rather than invent an
// audit lane, the toggles are silent here and the gap is recorded.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the lock set survives a relaunch. Swift uses `UserDefaults`; this is
/// the same contract, behind an interface so a widget test can drive the store
/// with no plugin registered.
abstract class BoardLockPersistence {
  const BoardLockPersistence();

  Future<Set<String>> load();
  Future<void> save(Set<String> boardIds);
}

/// The default: `shared_preferences`, the direct analogue of `UserDefaults`.
///
/// Every call is TOLERANT. A device whose preference store cannot be read must
/// still be able to deploy a board — losing the lock across a relaunch is a far
/// smaller failure than refusing to run the workflow at all — so a failure
/// degrades to an in-memory lock rather than throwing into the UI.
class SharedPrefsBoardLockPersistence extends BoardLockPersistence {
  const SharedPrefsBoardLockPersistence();

  static const String _key = 'cyan_board_locked_ids';

  @override
  Future<Set<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_key) ?? const <String>[]).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  @override
  Future<void> save(Set<String> boardIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, boardIds.toList());
    } catch (_) {
      // Deliberately swallowed — see the class comment.
    }
  }
}

/// The set of board ids the operator has deployed-and-locked on this device.
class BoardLockStore extends StateNotifier<Set<String>> {
  BoardLockStore({BoardLockPersistence? persistence})
      : _persistence = persistence ?? const SharedPrefsBoardLockPersistence(),
        super(const <String>{}) {
    _restore();
  }

  final BoardLockPersistence _persistence;

  Future<void> _restore() async {
    final saved = await _persistence.load();
    if (!mounted || saved.isEmpty) return;
    state = saved;
  }

  /// True when this board is locked HERE. Callers must OR this with the
  /// engine's own `deployed` flag; a board deployed elsewhere is locked too.
  bool isLocked(String boardId) => state.contains(boardId);

  /// Deploy + lock. Idempotent, so a double tap cannot double-write.
  ///
  /// The state flip is SYNCHRONOUS and the write is best-effort behind it —
  /// Swift's `UserDefaults.set` is synchronous, and more importantly the UI must
  /// not wait on a preference store to tell the operator their board is
  /// deployed. A device that cannot persist still deploys; it just forgets
  /// across a relaunch, which the engine's own `deployed` flag then re-supplies.
  void lock(String boardId) {
    if (boardId.isEmpty || state.contains(boardId)) return;
    state = {...state, boardId};
    unawaited(_persistence.save(state));
  }

  /// Re-enable authoring. Idempotent.
  void unlock(String boardId) {
    if (!state.contains(boardId)) return;
    state = {...state}..remove(boardId);
    unawaited(_persistence.save(state));
  }
}

final boardLockStoreProvider =
    StateNotifierProvider<BoardLockStore, Set<String>>(
  (ref) => BoardLockStore(),
);
