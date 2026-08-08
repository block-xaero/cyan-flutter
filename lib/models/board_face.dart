// models/board_face.dart
//
// PARITY face_board_container — the faces of the board "cube".
//
// SwiftUI reference (read-only):
//   Views/BoardFace.swift                  — the enum, its labels + `resolved`
//   Views/BoardContainerViewNew.swift      — the container that switches them
//   CyanTests/BoardFacesVMTests.swift      — `test_canvas_face_absent`,
//                                            `standardFaces == [.notebook,
//                                            .notes, .dashboard]`
//
// THREE faces, and only three: Workflow (the authored plain-English steps),
// Notes (the editor) and Dashboard (the running workflow). The canvas /
// whiteboard face was REMOVED upstream in Run A — in Swift `BoardFace(rawValue:
// "canvas")` is nil and `fromLegacy("canvas")` opens the notebook/Workflow
// face. Both halves are carried here: [tryParseBoardFace] refuses the removed
// spellings outright, while [boardFaceFromLegacy] migrates a board SAVED as
// canvas onto Workflow rather than stranding it on a face that no longer
// exists.
//
// (Swift also carries a `.video` face, but only for boards that resolve a media
// asset — that surface is the review-player stage, not this container.)

import 'package:flutter/material.dart';

import '../ffi/parity_models.dart';

/// The faces every board carries, in tab order. Swift: `BoardFace.notebook`
/// keeps the `"notebook"` rawValue for back-compat while presenting as
/// "Workflow"; [BoardFaceX.rawValue] preserves that split so a face written by
/// this app is still read by the macOS one.
enum BoardFace { workflow, notes, dashboard, video }

extension BoardFaceX on BoardFace {
  /// How the ENGINE spells this face (`cyan_get_board_mode` /
  /// `cyan_set_board_mode`). Workflow is stored as `notebook`.
  String get rawValue => switch (this) {
        BoardFace.workflow => 'notebook',
        BoardFace.notes => 'notes',
        BoardFace.dashboard => 'dashboard',
        BoardFace.video => 'video',
      };

  /// The tab label (Swift `BoardFace.label`).
  String get label => switch (this) {
        BoardFace.workflow => 'Workflow',
        BoardFace.notes => 'Notes',
        BoardFace.dashboard => 'Dashboard',
        BoardFace.video => 'Video',
      };

  /// Swift `BoardFace.icon` (SF Symbols → Material equivalents).
  IconData get icon => switch (this) {
        BoardFace.workflow => Icons.list_alt, // list.bullet.rectangle
        BoardFace.notes => Icons.description_outlined, // doc.text
        BoardFace.dashboard => Icons.bar_chart, // chart.bar.xaxis
        BoardFace.video => Icons.movie_outlined, // film
      };

  /// Swift `BoardFace.description` — the tab tooltip.
  String get description => switch (this) {
        BoardFace.workflow => 'Plain-English steps the workflow runs for you',
        BoardFace.notes => 'Text editor with syntax highlighting',
        BoardFace.dashboard => 'The running workflow — live status and summary',
        BoardFace.video => 'Video player with timecoded notes',
      };
}

/// The faces EVERY board carries, in tab order — Swift `BoardFace.standardFaces`.
///
/// Deliberately NOT `BoardFace.values`: `video` is a real face but a
/// CONDITIONAL one, offered only by a board that resolves a media asset
/// (Swift `BoardContainerViewNew.availableFaces`). Writing it as `.values` is
/// what made the fourth face impossible to add without silently granting it to
/// every board.
const List<BoardFace> kStandardBoardFaces = [
  BoardFace.workflow,
  BoardFace.notes,
  BoardFace.dashboard,
];

/// STRICT parse of an engine face string (Swift `BoardFace(rawValue:)`): an
/// unknown spelling is not a face, and `canvas` / `whiteboard` / `freeform` are
/// unknown spellings — they were removed, not renamed.
BoardFace? tryParseBoardFace(String? raw) =>
    switch (raw?.trim().toLowerCase()) {
      'notebook' || 'workflow' => BoardFace.workflow,
      'notes' => BoardFace.notes,
      'dashboard' => BoardFace.dashboard,
      _ => null,
    };

/// TOLERANT read of a board's SAVED face (Swift `BoardFace.fromLegacy`). A
/// board written before the canvas face was removed still has to open on
/// something, and that something is Workflow — never a fourth tab.
BoardFace boardFaceFromLegacy(String? saved) =>
    tryParseBoardFace(saved) ?? BoardFace.workflow;

/// Swift `BoardFace.resolved(saved:deployment:)` (R12 D2): a board whose
/// workflow is DEPLOYED with a live dashboard opens on the running Dashboard
/// rather than the editable Workflow. Absent or unreadable deployment state
/// changes nothing — the saved face stands.
BoardFace resolvedBoardFace({
  required BoardFace saved,
  BoardWorkflowState? deployment,
}) {
  if (deployment == null || deployment.error != null) return saved;
  if (deployment.isDeployed && deployment.hasDashboard) {
    return BoardFace.dashboard;
  }
  return saved;
}
