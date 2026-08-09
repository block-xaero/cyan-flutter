// providers/notes_intent_controller.dart
//
// STAGE 4 — NOTES AS INTENT, human-gated.
//
// The operator writes plain English on the Notes face; the lens drafts workflow
// steps from it; the steps land as REAL step cells through the EXACT composer
// path the manual toolbar uses; the board compiles so the bind chips are ready;
// and the human is handed to the Workflow face to review.
//
// IT NEVER RUNS. The human presses Run. A lane that drafted and ran would be
// the model authoring and executing a workflow on someone's board.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/ViewModels/NotesIntentViewModel.swift
//
// Two lanes, one landing tail:
//   • BRIEF  -> `/generate`  — "author a workflow with Lens" from a blurb.
//   • NOTES  -> `/transpile` — the ledger's "Create workflow", which keeps the
//     provenance receipts saying which note or rule shaped each step.
//
// Both forward the board's EFFECTIVE CONSTITUTION. That is the with-notes /
// without-notes bridge: with notes the notes lead and the house rules constrain;
// without notes the constitution is all there is, and it still steers.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/cyan_backend.dart';
import '../lens/lens_api.dart';
import '../lens/lens_models.dart';
import 'cyan_backend_provider.dart';
import 'lens_console_provider.dart';

@immutable
class NotesIntentState {
  /// A draft is in flight. Generation is minutes-scale, so this is the whole
  /// difference between "working" and "broken" to the operator.
  final bool isAuthoring;

  /// The lens's own words when a draft failed. NEVER silent, and never a
  /// generic shrug — an empty draft is a result the operator must see.
  final String? error;

  /// How many steps the last successful pass actually landed.
  final int lastAuthoredCount;

  /// The money line, or null when the lens sent no cost payload.
  final String? costLine;

  /// Per-step receipts from a transpile: which note or rule shaped each step.
  final List<String> provenance;

  const NotesIntentState({
    this.isAuthoring = false,
    this.error,
    this.lastAuthoredCount = 0,
    this.costLine,
    this.provenance = const [],
  });

  NotesIntentState copyWith({
    bool? isAuthoring,
    String? error,
    bool clearError = false,
    int? lastAuthoredCount,
    String? costLine,
    bool clearCostLine = false,
    List<String>? provenance,
  }) =>
      NotesIntentState(
        isAuthoring: isAuthoring ?? this.isAuthoring,
        error: clearError ? null : (error ?? this.error),
        lastAuthoredCount: lastAuthoredCount ?? this.lastAuthoredCount,
        costLine: clearCostLine ? null : (costLine ?? this.costLine),
        provenance: provenance ?? this.provenance,
      );

  /// The banner has something to say.
  bool get hasOutcome =>
      error != null || lastAuthoredCount > 0 || costLine != null;
}

class NotesIntentController extends StateNotifier<NotesIntentState> {
  NotesIntentController({
    required CyanBackend backend,
    required LensApi lens,
    required this.boardId,
  })  : _backend = backend,
        _lens = lens,
        super(const NotesIntentState());

  final CyanBackend _backend;
  final LensApi _lens;
  final String boardId;

  /// Clear the failure banner. The operator acknowledging an error is the only
  /// thing that dismisses it — it never times out on its own, because a draft
  /// that failed while they were looking elsewhere is exactly the one they need
  /// to see.
  void dismissError() {
    if (state.error == null) return;
    state = state.copyWith(clearError: true);
  }

  /// "Author a workflow with Lens" — a plain-English brief becomes steps.
  Future<bool> authorFromBrief(String brief) async {
    final text = brief.trim();
    if (text.isEmpty || state.isAuthoring) return false;
    state = state.copyWith(
        isAuthoring: true, clearError: true, clearCostLine: true);

    final LensDraft draft;
    try {
      draft = await _lens.generateSteps(
        boardId: boardId,
        brief: text,
        constitutionJson: await _constitutionSeat(),
      );
    } catch (e) {
      state = state.copyWith(
          isAuthoring: false, error: 'Lens draft failed: $e', provenance: []);
      return false;
    }

    state = state.copyWith(costLine: lensCostLine(draft.cache, draft.cost));
    return _land(draft.steps.expand(parseStepLines).toList());
  }

  /// "Create workflow" from the board's notes — the transpile lane, which keeps
  /// the receipts.
  Future<bool> authorFromNotes(List<String> notes) async {
    if (notes.isEmpty || state.isAuthoring) return false;
    state = state.copyWith(
        isAuthoring: true, clearError: true, clearCostLine: true);

    final LensTranspiled transpiled;
    try {
      transpiled = await _lens.transpileNotes(
        boardId: boardId,
        notes: notes,
        constitutionJson: await _constitutionSeat(),
      );
    } catch (e) {
      state = state.copyWith(
          isAuthoring: false,
          error: 'Lens transpile failed: $e',
          provenance: []);
      return false;
    }

    state = state.copyWith(
      provenance: transpiled.provenance,
      costLine:
          'IR ${transpiled.irCached ? 'cached — \$0 strong spend' : 'fresh'}'
          ' · bind ${transpiled.bindCached ? 'cached' : 'fresh'}',
    );
    return _land(transpiled.steps.expand(parseStepLines).toList());
  }

  /// The board's effective constitution, serialised as the distiller SEAT.
  ///
  /// Re-encoded from the typed model rather than passed through as raw engine
  /// JSON, because the two seams stay separate: the lens client must not learn
  /// the FFI's shapes. Only the three fields the server reads are sent, and
  /// `hard` is among them because a present `hard` is what switches
  /// server-side distillation on — that is how the house rules end up spliced
  /// into the draft verbatim.
  ///
  /// A failure here must NOT fail the draft. Generating without the house rules
  /// is the legacy behaviour and is far better than refusing to generate at
  /// all; likewise a constitution with no hash, which the seat builder drops.
  Future<String?> _constitutionSeat() async {
    try {
      final c = await _backend.constitutionEffective(boardId);
      if (c.hash.isEmpty) return null;
      return jsonEncode({
        'hash': c.hash,
        'markdown': c.markdown,
        'hard': [
          for (final rule in c.hard)
            {
              'id': rule.id,
              'scope': rule.scope,
              'category': rule.category,
              'text': rule.text,
            },
        ],
      });
    } catch (_) {
      return null;
    }
  }

  /// The shared landing tail: step texts -> REAL `step` cells through the same
  /// seam the composer uses -> compile -> hand to the human.
  Future<bool> _land(List<String> lines) async {
    if (lines.isEmpty) {
      state = state.copyWith(
        isAuthoring: false,
        error: 'The lens returned no usable steps — try rephrasing the note.',
      );
      return false;
    }

    var added = 0;
    for (final line in lines) {
      // The EXACT composer path, appending after any existing steps, so manual
      // authoring keeps working untouched and the engine applies the same
      // validation it applies to a hand-typed step.
      final step = await _backend.addWorkflowStep(boardId, line);
      if (step != null) added++;
    }

    if (added == 0) {
      state = state.copyWith(
          isAuthoring: false, error: 'The drafted steps could not be saved.');
      return false;
    }

    // Compile so the bind chips are ready for the human to review…
    await _backend.pipelineCompile(boardId);

    // …and stop. The human presses Run.
    state = state.copyWith(isAuthoring: false, lastAuthoredCount: added);
    return true;
  }
}

/// One intent controller per board.
final notesIntentProvider = StateNotifierProvider.autoDispose
    .family<NotesIntentController, NotesIntentState, String>((ref, boardId) {
  return NotesIntentController(
    backend: ref.watch(cyanBackendProvider),
    lens: ref.watch(lensApiProvider),
    boardId: boardId,
  );
});
