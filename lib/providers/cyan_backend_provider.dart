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

/// The authored workflow for a board (Workflow face, row 3).
final boardWorkflowProvider =
    FutureProvider.family<Workflow, String>((ref, boardId) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.loadWorkflow(boardId);
});

/// The notes document for a board (Notes face, row 5).
final boardNotesProvider =
    FutureProvider.family<BoardNotes, String>((ref, boardId) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.loadNotes(boardId);
});

/// Ops console — all runs (row 6).
final opsRunsProvider = FutureProvider<List<OpsRun>>((ref) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.loadOpsRuns();
});

/// Ops console — cost meter (row 7).
final costMeterProvider = FutureProvider<CostMeter>((ref) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.loadCostMeter();
});

/// Ops console — efficiency report (row 8).
final efficiencyProvider = FutureProvider<EfficiencyReport>((ref) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.loadEfficiency();
});

/// Marketplace plugin cards (row 9).
final marketplaceProvider = FutureProvider<List<PluginCard>>((ref) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.loadMarketplace();
});

/// Lens intelligence bundle (row 10).
final lensIntelligenceProvider =
    FutureProvider<LensIntelligence>((ref) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.loadLensIntelligence();
});

/// Board chat transcript (row 11).
final boardChatProvider =
    FutureProvider.family<List<ChatMessage>, String>((ref, boardId) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.loadChat(boardId);
});
