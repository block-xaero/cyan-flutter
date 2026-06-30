// ffi/parity_models.dart
//
// Plain, immutable view models returned by the `CyanBackend` seam. These are
// deliberately UI-facing and decoupled from the FFI JSON wire format and from
// the legacy `tree_item.dart` models, so the parity screens have one stable
// shape to render whether the data came from the real engine or the fake.
//
// Hierarchy mirrors the SwiftUI app: Group -> Workspace -> Board.

import 'package:flutter/foundation.dart';

/// A top-level group (a P2P collaboration space).
@immutable
class CyanGroup {
  final String id;
  final String name;
  final String colorHex; // e.g. "#66D9EF"
  final int peerCount;
  final List<CyanWorkspace> workspaces;

  const CyanGroup({
    required this.id,
    required this.name,
    required this.colorHex,
    this.peerCount = 0,
    this.workspaces = const [],
  });
}

/// A workspace inside a group.
@immutable
class CyanWorkspace {
  final String id;
  final String groupId;
  final String name;
  final List<CyanBoard> boards;

  const CyanWorkspace({
    required this.id,
    required this.groupId,
    required this.name,
    this.boards = const [],
  });
}

/// The three faces a board can present (canvas is removed in the parity target;
/// kept here only as a fallback for legacy data).
enum BoardFaceKind { workflow, notes, dashboard, canvas }

extension BoardFaceKindX on BoardFaceKind {
  String get label => switch (this) {
        BoardFaceKind.workflow => 'Workflow',
        BoardFaceKind.notes => 'Notes',
        BoardFaceKind.dashboard => 'Dashboard',
        BoardFaceKind.canvas => 'Canvas',
      };

  static BoardFaceKind fromString(String? s) => switch (s?.toLowerCase()) {
        'workflow' || 'notebook' => BoardFaceKind.workflow,
        'notes' => BoardFaceKind.notes,
        'dashboard' => BoardFaceKind.dashboard,
        _ => BoardFaceKind.canvas,
      };
}

/// A board. The unit the living-wall grid renders as a card.
@immutable
class CyanBoard {
  final String id;
  final String workspaceId;
  final String name;
  final BoardFaceKind activeFace;
  final bool isPinned;
  final int rating; // 0..5
  final List<String> labels;
  final int stepCount; // number of workflow steps / cells
  final bool isDeployed; // running workflow => "living" card
  final DateTime createdAt;
  final DateTime? lastModified;

  const CyanBoard({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.activeFace = BoardFaceKind.workflow,
    this.isPinned = false,
    this.rating = 0,
    this.labels = const [],
    this.stepCount = 0,
    this.isDeployed = false,
    required this.createdAt,
    this.lastModified,
  });
}

/// A board plus the group/workspace it lives in. The flat unit the All-Boards
/// living wall renders.
@immutable
class BoardWithContext {
  final CyanBoard board;
  final CyanGroup group;
  final CyanWorkspace workspace;

  const BoardWithContext({
    required this.board,
    required this.group,
    required this.workspace,
  });
}

// ---------------------------------------------------------------------------
// Workflow run (Dashboard face)
// ---------------------------------------------------------------------------

enum RunStepStatus { pending, running, awaitingApproval, done, failed }

enum RunStepKind { ai, human }

@immutable
class RunStep {
  final String id;
  final String title;
  final RunStepKind kind;
  final RunStepStatus status;

  const RunStep({
    required this.id,
    required this.title,
    required this.kind,
    required this.status,
  });
}

@immutable
class WorkflowRun {
  final String boardId;
  final String title;
  final List<RunStep> steps;

  const WorkflowRun({
    required this.boardId,
    required this.title,
    required this.steps,
  });
}
