// ffi/cyan_backend.dart
//
// THE single FFI seam for the Flutter parity port.
//
// Mirrors the SwiftUI app's `CyanBackend` protocol: every interaction with the
// Rust engine goes through this abstraction. No parity screen, view-model, or
// provider talks to `CyanFFI` / `component_bridge` directly — they depend on a
// `CyanBackend` instance.
//
//   - prod  : `CyanBackendFFI` (wraps the real component_bridge / CyanFFI)
//   - test  : `FakeCyanBackend` (lib/ffi/fake_cyan_backend.dart) — seeded demo
//             data, no native library, so Tier-1 widget/golden tests need NO
//             backend.
//
// Keep this surface SMALL and additive. It is a contract; grow it screen by
// screen as the parity port advances. The command/event JSON shapes are owned
// by cyan-backend (frozen at swiftui-parity-baseline-2026-06-29) — match, don't
// invent.

import 'parity_models.dart';

/// The single gateway between Flutter UI and the Cyan engine.
///
/// Methods return plain Dart parity models (see `parity_models.dart`) so the UI
/// layer never has to know whether it is talking to FFI or a fake.
abstract class CyanBackend {
  // ---- lifecycle -----------------------------------------------------------

  /// Idempotent: bring the backend to a ready state. For the fake this seeds
  /// demo data; for FFI this initialises the engine + cache.
  Future<void> initialize();

  /// True once [initialize] has completed and the engine can serve reads.
  bool get isReady;

  // ---- tree (Group -> Workspace -> Board) ----------------------------------

  /// All groups with their nested workspaces and boards.
  Future<List<CyanGroup>> loadGroups();

  /// Flattened list of every board across all groups/workspaces, each carrying
  /// its group + workspace context. This is what the Boards grid / living wall
  /// renders.
  Future<List<BoardWithContext>> loadAllBoards();

  // ---- a single workflow run (Dashboard) -----------------------------------

  /// The most recent / sample run for a board, if any. Drives the Dashboard
  /// DAG + gated-run face.
  Future<WorkflowRun?> loadRun(String boardId);

  // ---- board faces ---------------------------------------------------------

  /// The authored workflow (steps + compiled inference chips) for a board's
  /// Workflow face.
  Future<Workflow> loadWorkflow(String boardId);

  /// The notes document for a board's Notes face.
  Future<BoardNotes> loadNotes(String boardId);

  // ---- operations console --------------------------------------------------

  /// All runs across the tenant for the Ops Runs feed.
  Future<List<OpsRun>> loadOpsRuns();

  /// The tenant-wide asset-minute cost meter (Ops Cost face).
  Future<CostMeter> loadCostMeter();

  /// The efficiency report (insight cards + per-step table).
  Future<EfficiencyReport> loadEfficiency();

  // ---- marketplace ---------------------------------------------------------

  /// All marketplace plugin cards (featured flagged on the card).
  Future<List<PluginCard>> loadMarketplace();

  // ---- lens ----------------------------------------------------------------

  /// The Lens intelligence bundle (nudges / asks / decisions).
  Future<LensIntelligence> loadLensIntelligence();

  // ---- chat ----------------------------------------------------------------

  /// The chat transcript for a board.
  Future<List<ChatMessage>> loadChat(String boardId);
}
