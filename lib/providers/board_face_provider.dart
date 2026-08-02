// providers/board_face_provider.dart
//
// PARITY face_board_container — what the board container needs before it can
// paint: which board it is standing on, and which of the three faces that board
// OPENS to.
//
// SwiftUI reference (read-only): Views/BoardContainerViewNew.swift
//   `loadActiveFace()` — read the saved face through `BoardFaceBridge`, then
//   run it through `BoardFace.resolved(saved:deployment:)` so a deployed board
//   with a live dashboard opens on the Dashboard, not the editable Workflow.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/parity_models.dart';
import '../models/board_face.dart';
import 'cyan_backend_provider.dart';

/// The face the board OPENS to. Two reads through the ONE seam: the saved face
/// (migrated off any face this app no longer has) and the board's deploy state.
///
/// autoDispose, and that is load-bearing: this is the read a board OPEN does.
/// Cached for the app's lifetime it would answer with the face the board was on
/// the first time it was ever opened, so a board closed on Notes would reopen on
/// whatever it started as.
final boardOpeningFaceProvider =
    FutureProvider.autoDispose.family<BoardFace, String>((ref, boardId) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  final saved = boardFaceFromLegacy(await backend.boardActiveFace(boardId));
  // A deploy state that could not be READ leaves the saved face standing —
  // `BoardWorkflowState.error` is exactly that distinction, so it is honored
  // inside `resolvedBoardFace` rather than read as "not deployed".
  final deployment = await backend.boardWorkflowState(boardId);
  return resolvedBoardFace(saved: saved, deployment: deployment);
});

/// The board the container is standing on, with its group + workspace context —
/// what the header names. Null when the id names no board the tree knows.
final boardContextProvider = FutureProvider.autoDispose
    .family<BoardWithContext?, String>((ref, boardId) async {
  for (final b in await ref.watch(allBoardsProvider.future)) {
    if (b.board.id == boardId) return b;
  }
  return null;
});
