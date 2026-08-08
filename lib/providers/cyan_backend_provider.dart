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

// The Ops console's three faces — Runs (row 6), Cost (row 7) and Efficiency
// (row 8) — MOVED to `providers/lens_console_provider.dart` under PHASE-2 D3.
// They are not FFI: on the Mac they read cyan-lens over HTTP and always have,
// which is why `loadCostMeter`/`loadEfficiency` could only ever answer zeros
// here.

/// The ENGINE-assembled run feed: every board's `cyan_pipeline_status`, mapped
/// (Tier-2 T7 proves it). Deliberately NOT the same provider as the Ops
/// console's — this is what the engine knows about runs on THIS device, and
/// [opsRunsProvider] is what the tenant's lens knows.
///
/// Two callers, both of which must stay on this lane:
///   • the boards WALL, whose card state is a local read;
///   • the metering spine, whose drill-down is `loadRunTrace` — an ENGINE
///     trace. A list from one lane and a drill-down from the other would let
///     an operator tap a run that has no audit. When row 26 moves the audit to
///     `GET /runs/{id}`, the list moves with it.
final engineOpsRunsProvider = FutureProvider<List<OpsRun>>((ref) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.loadOpsRuns();
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

// The Marketplace (row 9 / 20) MOVED to `providers/lens_console_provider.dart`
// under PHASE-2 D3: `GET /api/v1/marketplace/browse` is a lens route, and the
// engine's only plugin verbs are `cyan_plugin_catalog` (what is INSTALLED here,
// still on this seam) and `cyan_install_plugin_bundle` (the land).

// The Lens AI face (row 10 / 21) MOVED to
// `providers/lens_console_provider.dart` under PHASE-2 D3. Nudges, asks and
// decisions are lens routes; the engine's lens surface is
// `cyan_parse_lens_command` + `cyan_poll_ai_insights` and reports none of them,
// which is why `loadLensIntelligence` could only ever answer `connected:false`.

/// Board chat transcript (row 11).
final boardChatProvider =
    FutureProvider.family<List<ChatMessage>, String>((ref, boardId) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.loadChat(boardId);
});

/// The plugin bundles installed on this device (Plugins workspace).
final pluginCatalogProvider =
    FutureProvider<List<InstalledPlugin>>((ref) async {
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

/// The board's review media — the proxy, the preview render and the master, as
/// the engine resolves them.
///
/// The board CUBE reads it to decide whether to offer the Video face at all:
/// Swift's `availableFaces` appends `.video` only when the board resolves a
/// media asset, so a board with no media never grows a tab onto an empty
/// player.
final boardVideoMediaProvider =
    FutureProvider.family<BoardVideoMedia, String>((ref, boardId) async {
  final backend = ref.watch(cyanBackendProvider);
  return backend.boardVideoMedia(boardId);
});
