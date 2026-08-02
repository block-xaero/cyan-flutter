// providers/workflow_authoring_provider.dart
//
// The Workflow (author) face's reads. Kept beside `boardWorkflowProvider` (the
// authored steps) rather than inside it: authoring and the COMPILED plan are
// two different truths, and the face shows them side by side — the English the
// operator wrote, and the DAG a run would actually walk.
//
// Everything here goes through the `CyanBackend` seam, so the whole face is
// drivable against `FakeCyanBackend` with no dylib.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/parity_models.dart';
import 'cyan_backend_provider.dart';

/// The board's compiled DAG, as the engine persisted it (`cyan_pipeline_status`).
///
/// The Workflow face's preview reads THIS rather than re-deriving a plan from
/// the authored English on the client: a preview that disagreed with the plan
/// a run walks would be worse than no preview at all. A board that has never
/// compiled reads back with no steps.
final boardPipelineProvider =
    FutureProvider.family<PipelineStatus, String>((ref, boardId) async {
  final backend = ref.watch(cyanBackendProvider);
  await backend.initialize();
  return backend.pipelineStatus(boardId);
});
