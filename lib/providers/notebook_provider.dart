// providers/notebook_provider.dart
//
// The board DOCUMENT behind the notebook face: every cell the board holds, in
// `cell_order`. Kept apart from `boardWorkflowProvider` (which reads the same
// ledger for its step cells only) because the two answer different questions —
// what the board RUNS, and what the board SAYS.
//
// Everything goes through the `CyanBackend` seam, so the face is drivable
// against `FakeCyanBackend` with no dylib.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/parity_models.dart';
import 'cyan_backend_provider.dart';

/// Every cell of [boardId]'s notebook (`cyan_load_notebook_cells`), oldest-first.
///
/// A board nobody has written in reads back EMPTY rather than with a seeded
/// starter cell: the document is the operator's, and inventing a first cell for
/// them would be a write this side never made.
final boardNotebookProvider =
    FutureProvider.family<List<NotebookCell>, String>((ref, boardId) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.notebookCells(boardId);
});
