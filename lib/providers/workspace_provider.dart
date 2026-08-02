// providers/workspace_provider.dart
//
// PARITY face_workspaces — Riverpod wiring for the workspace surface. Reads go
// through the ONE `CyanBackend` seam, so the whole face drives off
// `FakeCyanBackend` in a widget test with no dylib.
//
// SwiftUI reference (read-only):
//   ViewModels/BoardGridViewModel.swift  — `loadBoardsForWorkspace(_:)`
//   ViewModels/BoardRunStateStore.swift  — `seedFromTenant(knownBoards:)`

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/parity_models.dart';
import '../models/workspace_surface.dart';
import 'cyan_backend_provider.dart';

/// Every workspace in the tree, group order preserved. The workspace picker and
/// the New Board target resolver read this rather than re-walking the groups.
final workspacesProvider = FutureProvider<List<CyanWorkspace>>((ref) async {
  final groups = await ref.watch(groupsProvider.future);
  return [for (final g in groups) ...g.workspaces];
});

/// One workspace, its boards, and each board's run state. Null when no
/// workspace goes by that id — the surface says so rather than rendering an
/// empty frame that looks like a workspace with nothing in it.
///
/// Run state comes from ONE tenant-wide feed call, bucketed by board, exactly
/// as `BoardRunStateStore.seedFromTenant` does — never one fetch per card.
/// A feed that FAILS to arrive leaves every board `unknown`: an outage must not
/// repaint the workspace as "No runs yet".
final workspaceSurfaceProvider =
    FutureProvider.family<WorkspaceSurface?, String>((ref, workspaceId) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();

  final groups = await backend.loadGroups();
  for (final group in groups) {
    for (final workspace in group.workspaces) {
      if (workspace.id != workspaceId) continue;

      List<OpsRun>? tenantRuns;
      try {
        tenantRuns = await backend.loadOpsRuns();
      } catch (_) {
        // The lens is down. Claim NOTHING about any board's runs; the boards
        // themselves still render, which is the invariant that keeps an outage
        // from blanking the wall.
        tenantRuns = null;
      }

      return WorkspaceSurface.assemble(
        group: group,
        workspace: workspace,
        tenantRuns: tenantRuns,
      );
    }
  }
  return null;
});

/// ONE board's asset-class step counts (`cyan_pipeline_status`).
///
/// Deliberately NOT folded into [workspaceSurfaceProvider]: the engine has no
/// bulk pipeline-status verb, so seeding it there would be one blocking engine
/// call per card on every workspace open. SwiftUI's card fires this on HOVER
/// (`BoardGridView.loadPipelineCounts`, "one call per hover, no polling loop"),
/// and a family provider watched only by a hovered card reproduces that exactly
/// — the read happens when a card is asked about, and the answer is cached for
/// the next hover.
///
/// Null when the read did not land: an unreachable engine claims nothing rather
/// than painting a zero-strip onto a board that may be mid-workflow.
final boardPipelineCountsProvider =
    FutureProvider.family<BoardPipelineCounts?, String>((ref, boardId) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  try {
    return BoardPipelineCounts.from(await backend.pipelineStatus(boardId));
  } catch (_) {
    return null;
  }
});

/// The workspace a new board files into when the operator names only a group.
///
/// Port of `FileTreeViewModel.defaultWorkspaceIdForNewBoard()`'s inner
/// `workspace(inGroup:)`: the conventional `General`, then any non-system
/// workspace. A SYSTEM workspace (`Plugins`) is never the answer — it is the
/// group's registry, and a board filed there is a board nobody finds again.
/// Returns null when the group holds nothing but system workspaces, which is a
/// refusal, not a fallback.
CyanWorkspace? boardTargetIn(Iterable<CyanWorkspace> within) {
  final candidates = within.where((w) => w.acceptsBoards);
  if (candidates.isEmpty) return null;
  for (final w in candidates) {
    if (w.name == 'General') return w;
  }
  return candidates.first;
}
