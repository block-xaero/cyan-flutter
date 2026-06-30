// providers/cyan_backend_provider.dart
//
// Riverpod wiring for the `CyanBackend` seam. Parity screens read
// `cyanBackendProvider` to get the backend, and `allBoardsProvider` /
// `groupsProvider` for data. In tests, override `cyanBackendProvider` with a
// `FakeCyanBackend` — nothing else changes.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/cyan_backend.dart';
import '../ffi/cyan_backend_ffi.dart';
import '../ffi/parity_models.dart';

/// The single backend instance. Prod = real FFI adapter.
/// Tests override this with `FakeCyanBackend`.
final cyanBackendProvider = Provider<CyanBackend>((ref) {
  return CyanBackendFFI();
});

/// All boards (flattened, with group/workspace context) for the living wall.
final allBoardsProvider = FutureProvider<List<BoardWithContext>>((ref) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.loadAllBoards();
});

/// The group tree (for the Explorer screen, row 2).
final groupsProvider = FutureProvider<List<CyanGroup>>((ref) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.loadGroups();
});

/// The sample/most-recent run for a board (Dashboard face, row 4).
final boardRunProvider =
    FutureProvider.family<WorkflowRun?, String>((ref, boardId) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.loadRun(boardId);
});
