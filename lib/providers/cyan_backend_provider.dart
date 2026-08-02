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

/// Ops console — the per-step audit for ONE run (metering face). Null when the
/// run is unknown or the lens has not traced it.
final runTraceProvider =
    FutureProvider.family<RunTrace?, String>((ref, runId) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.loadRunTrace(runId);
});

/// The cached signed entitlement behind the trial banner + the paid-surface
/// locks (metering face). OFFLINE-SAFE: an uncached device falls back to the
/// offline trial default rather than hard-locking itself.
final entitlementProvider = FutureProvider<Entitlement>((ref) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  final json = await backend.cachedEntitlementJson();
  if (json != null) {
    final decoded = Entitlement.decode(json);
    if (decoded != null) return decoded;
  }
  return Entitlement.offlineDefault(
      'local', DateTime.now().millisecondsSinceEpoch ~/ 1000);
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

/// The plugin bundles installed on this device (Plugins workspace).
final pluginCatalogProvider = FutureProvider<List<InstalledPlugin>>((ref) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.pluginCatalog();
});

/// The non-secret config rows the engine holds for one group + plugin.
///
/// The engine is the single source of truth: the config sheet WRITES through
/// `pluginConfigSet` and then INVALIDATES this provider, so what lands on
/// screen is what the engine actually stored — never a shadow copy in widget
/// state that could disagree with a refused write.
final pluginConfigProvider =
    FutureProvider.family<PluginConfig, ({String groupId, String pluginId})>(
        (ref, key) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.pluginConfigGet(key.groupId, key.pluginId);
});
