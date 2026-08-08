// models/notes_face_mode.dart
//
// The Notes face's modes — the picker every Mac route to the constitution goes
// through.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Views/NotesEditorView.swift:277
//     `enum NotesFaceMode: Hashable { case editor, structure, constitution }`
//   and :403-411, the segmented picker that switches the body.
//
// WHY THIS MATTERS BEYOND A TAB: the CONSTITUTION is the WITHOUT-NOTES lever.
// A board with no review notes takes its arguments from the house rules, so
// "add a rule, re-run, the output changes" is the whole without-notes
// demonstration — and on Windows it could not be performed at all, because
// `ParityConstitutionEditor` is a complete port with no mount site and no
// in-tree parent to inherit one.
//
// [structure] is DELIBERATELY ABSENT from [NotesFaceMode.values] usage in the
// picker for now. The structuring lane is lens HTTP (`POST /api/v1/notes/
// structure`) and `LensApi` carries no such method yet, so a Structure segment
// would be a control with no lane behind it — which this port has already
// decided, in writing, is worse than no control (see the row-15 note in
// PARITY_TRACKER.md). The case exists here so the day the lens method lands the
// segment is one line, not a refactor.

/// The Notes face's three modes. See the file header on why only two are
/// currently offered in the picker.
enum NotesFaceMode {
  /// The freeform markdown document.
  editor,

  /// Freeform → Lens-typed proposals → human confirm. Not yet reachable: the
  /// `LensApi` seam has no `structure` method.
  structure,

  /// The scoped house rules + authorship surface.
  constitution;

  /// The segment label, matching the Swift picker word for word.
  String get label => switch (this) {
        NotesFaceMode.editor => 'Editor',
        NotesFaceMode.structure => 'Structure',
        NotesFaceMode.constitution => 'Constitution',
      };

  /// The widget key its segment carries.
  String get segmentKey => 'notes-mode-${name}';
}
