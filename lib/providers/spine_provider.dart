// providers/spine_provider.dart
//
// Riverpod wiring for the post-production spine (see spine_controller.dart).
//
// autoDispose + family, keyed on the (board, tenant) pair the spine runs in:
// the review ledger and the pipeline are both scoped to that pair, and a
// controller that outlived its surface would keep writing gates for a board
// nobody is looking at.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cyan_backend_provider.dart';
import 'spine_controller.dart';

/// The board + tenant a spine runs in.
typedef SpineScope = ({String boardId, String tenantId});

final spineProvider = StateNotifierProvider.autoDispose
    .family<SpineController, SpineState, SpineScope>((ref, scope) {
  final controller = SpineController(
    backend: ref.watch(cyanBackendProvider),
    boardId: scope.boardId,
    tenantId: scope.tenantId,
  );
  controller.hydrate();
  return controller;
});
