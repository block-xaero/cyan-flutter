// models/review_entry.dart
//
// PARITY face_review_player · LAYER 1 (the portable core).
//
// SwiftUI reference (READ-ONLY):
//   Review/EntryRenderRegistry.swift — the declarative registry, whose header
//                                      says it is "portable verbatim to the
//                                      Flutter port". This is that port.
//   Review/ReviewModels.swift        — the entry's lifecycle vocabularies.
//
// Two things live here:
//
//   [ReviewEntry] — one change-list row as the player needs it: the ledger
//   columns (already modelled on the seam as `ChangeEntry`) PLUS the spatial
//   field groups a captured note carries (`ref` / `region` / `intent_struct`).
//   Carried alongside rather than folded into the seam's model, because the
//   seam's `ChangeEntry` is shared by every face and the spatial groups are
//   this face's.
//
//   [ReviewEntryRenderRegistry] — rendering as a PURE FUNCTION of the entry.
//   The view asks it and never branches, so a new kind / op / plugin op is a
//   registry RULE (data), not a new screen. The rules are ordered
//   most-specific → most-general and the last one is total, so an entry this
//   build has never seen still renders coherently.

import 'package:flutter/foundation.dart';

import '../ffi/parity_models.dart';
import 'spatial_note.dart';

/// The review-loop phase, carried verbatim from the engine's own vocabulary
/// rather than narrowed to an enum this build would have to keep in step.
enum ReviewPhase {
  draft,
  inReview,
  notesIn,
  conforming,
  approved,
  finishing,
  delivered;

  static ReviewPhase? parse(String? raw) => switch (raw?.toUpperCase()) {
        'DRAFT' => ReviewPhase.draft,
        'IN_REVIEW' => ReviewPhase.inReview,
        'NOTES_IN' => ReviewPhase.notesIn,
        'CONFORMING' => ReviewPhase.conforming,
        'APPROVED' => ReviewPhase.approved,
        'FINISHING' => ReviewPhase.finishing,
        'DELIVERED' => ReviewPhase.delivered,
        _ => null,
      };

  String get label => switch (this) {
        ReviewPhase.draft => 'Draft',
        ReviewPhase.inReview => 'In review',
        ReviewPhase.notesIn => 'Notes in',
        ReviewPhase.conforming => 'Conforming',
        ReviewPhase.approved => 'Approved',
        ReviewPhase.finishing => 'Finishing',
        ReviewPhase.delivered => 'Delivered',
      };
}

/// Who the loop is waiting on — the three-actor banner.
enum WaitingOn { you, cyan, producer }

/// One change-list row plus the spatial groups the player draws.
@immutable
class ReviewEntry {
  /// The ledger columns, exactly as every other face reads them.
  final ChangeEntry entry;

  /// What the note is ABOUT (absent on rows written before the field group).
  final EntryRef? ref;

  /// The drawn region — absent on a note that pointed at nothing.
  final NoteRegion? region;

  /// The structured intent slot; absent means "general".
  final IntentStruct? intentStruct;

  /// Display-only provenance, never identity.
  final CaptureCtx? captureCtx;

  const ReviewEntry({
    required this.entry,
    this.ref,
    this.region,
    this.intentStruct,
    this.captureCtx,
  });

  String get id => entry.id;
  String get kind => entry.kind;
  String? get op => entry.op;
  String get state => entry.state;
  bool get active => entry.active;
  int get tcIn => entry.tcIn;
  int? get tcOut => entry.tcOut;
  int get seq => entry.seq;
  String get intent => entry.intent;
  String? get proposedBy => entry.proposedBy;

  /// The last frame this entry covers — a point covers exactly its own frame.
  int get tcEnd => (tcOut ?? tcIn) < tcIn ? tcIn : (tcOut ?? tcIn);

  factory ReviewEntry.fromJson(Map<String, dynamic> j) => ReviewEntry(
        entry: ChangeEntry.fromJson(j),
        ref: EntryRef.fromJson(j['ref'] as Map<String, dynamic>?),
        region: NoteRegion.fromJson(j['region'] as Map<String, dynamic>?),
        intentStruct:
            IntentStruct.fromJson(j['intent_struct'] as Map<String, dynamic>?),
        captureCtx:
            CaptureCtx.fromJson(j['capture_ctx'] as Map<String, dynamic>?),
      );
}

// ---------------------------------------------------------------------------
// Semantic roles — meaning only. No colours, no sizes: those are the view's.
// ---------------------------------------------------------------------------

/// How the strip draws the marker/range — a semantic shape, not a pixel style.
enum MarkerStyle { point, range, gate }

/// The semantic colour ROLE. These names describe MEANING, never a hue; the
/// view maps them onto Monokai.
enum ColorRole {
  proposed,
  aiProposed,
  approved,
  rejected,
  applied,
  creative,
  neutral,
}

/// A panel action offered for this entry. The view renders buttons; the
/// controller turns a tap into an INTENT the engine adjudicates.
enum PanelAction {
  approve,
  edit,
  reject,
  keepNote,
  promoteToOp,
  toggleActive,
}

/// The pure, colour-free description of how ONE entry is presented.
@immutable
class RenderDescriptor {
  final MarkerStyle markerStyle;
  final ColorRole colorRole;

  /// The panel offers a decision — an op awaiting confirm, or a toggle on an
  /// applied one.
  final bool isActionable;

  /// A note the agent may not auto-op — "your call".
  final bool isCreative;

  /// The action buttons, in presentation order.
  final List<PanelAction> panelActions;

  /// Whether the card offers the before↔after compare at this tc.
  final bool showsBeforeAfterPreview;

  const RenderDescriptor({
    required this.markerStyle,
    required this.colorRole,
    required this.isActionable,
    required this.isCreative,
    required this.panelActions,
    required this.showsBeforeAfterPreview,
  });
}

/// One declarative rule: a pure predicate over the entry → the descriptor.
@immutable
class RenderRule {
  final String name;
  final bool Function(ReviewEntry) match;
  final RenderDescriptor Function(ReviewEntry) descriptor;

  const RenderRule({
    required this.name,
    required this.match,
    required this.descriptor,
  });
}

/// The ops this build's vocabulary knows. An op outside it is not an error —
/// it falls through to the data-driven `default.opLike` rule, which is what
/// makes the taxonomy extensible by DATA.
const List<String> kKnownOps = [
  'trim_head',
  'trim_tail',
  'trim',
  'cut',
  'speed',
  'reorder',
  'swap',
  'insert',
  'color',
  'audio_duck',
  'audio_level',
  'mute',
  'fade',
  'gfx_swap',
];

/// The declarative registry — `describe` walks the ordered rules and the first
/// match wins.
class ReviewEntryRenderRegistry {
  final List<RenderRule> rules;
  const ReviewEntryRenderRegistry(this.rules);

  /// The descriptor AND the rule that produced it (tests and debugging read
  /// the name; the view only ever needs the descriptor).
  ({RenderDescriptor descriptor, String ruleName}) resolve(ReviewEntry e) {
    for (final rule in rules) {
      if (rule.match(e)) {
        return (descriptor: rule.descriptor(e), ruleName: rule.name);
      }
    }
    // Unreachable — the default registry ends with a total rule — but we never
    // trap: a neutral descriptor is always safe.
    return (
      descriptor: const RenderDescriptor(
        markerStyle: MarkerStyle.point,
        colorRole: ColorRole.neutral,
        isActionable: false,
        isCreative: false,
        panelActions: [],
        showsBeforeAfterPreview: false,
      ),
      ruleName: 'fallback.neutral',
    );
  }

  RenderDescriptor describe(ReviewEntry e) => resolve(e).descriptor;

  static bool _knownOp(ReviewEntry e) =>
      e.kind == 'op' && (e.op == null || kKnownOps.contains(e.op));

  /// The production registry, ordered most-specific → most-general.
  static final ReviewEntryRenderRegistry standard =
      ReviewEntryRenderRegistry([
    // 1) Agent-proposed mechanical op awaiting the human confirm gate.
    RenderRule(
      name: 'op.agentProposed',
      match: (e) =>
          _knownOp(e) && e.proposedBy == 'agent' && e.state == 'proposed',
      descriptor: (_) => const RenderDescriptor(
        markerStyle: MarkerStyle.range,
        colorRole: ColorRole.aiProposed,
        isActionable: true,
        isCreative: false,
        panelActions: [PanelAction.approve, PanelAction.edit, PanelAction.reject],
        showsBeforeAfterPreview: true,
      ),
    ),

    // 2) Human-proposed op awaiting confirm — the same gate, its own tint.
    RenderRule(
      name: 'op.humanProposed',
      match: (e) => _knownOp(e) && e.state == 'proposed',
      descriptor: (_) => const RenderDescriptor(
        markerStyle: MarkerStyle.range,
        colorRole: ColorRole.proposed,
        isActionable: true,
        isCreative: false,
        panelActions: [PanelAction.approve, PanelAction.edit, PanelAction.reject],
        showsBeforeAfterPreview: true,
      ),
    ),

    // 3) Approved op — confirmed and active, reversible without deletion.
    RenderRule(
      name: 'op.approved',
      match: (e) => _knownOp(e) && e.state == 'approved',
      descriptor: (_) => const RenderDescriptor(
        markerStyle: MarkerStyle.range,
        colorRole: ColorRole.approved,
        isActionable: true,
        isCreative: false,
        panelActions: [PanelAction.toggleActive],
        showsBeforeAfterPreview: true,
      ),
    ),

    // 4) Applied op — conformed into the master.
    RenderRule(
      name: 'op.applied',
      match: (e) => _knownOp(e) && e.state == 'applied',
      descriptor: (_) => const RenderDescriptor(
        markerStyle: MarkerStyle.range,
        colorRole: ColorRole.applied,
        isActionable: true,
        isCreative: false,
        panelActions: [PanelAction.toggleActive],
        showsBeforeAfterPreview: true,
      ),
    ),

    // 5) Rejected op — kept for history, inactive.
    RenderRule(
      name: 'op.rejected',
      match: (e) => _knownOp(e) && e.state == 'rejected',
      descriptor: (_) => const RenderDescriptor(
        markerStyle: MarkerStyle.range,
        colorRole: ColorRole.rejected,
        isActionable: false,
        isCreative: false,
        panelActions: [],
        showsBeforeAfterPreview: false,
      ),
    ),

    // 6) Superseded op — replaced by a redo.
    RenderRule(
      name: 'op.superseded',
      match: (e) => _knownOp(e) && e.state == 'superseded',
      descriptor: (_) => const RenderDescriptor(
        markerStyle: MarkerStyle.range,
        colorRole: ColorRole.rejected,
        isActionable: false,
        isCreative: false,
        panelActions: [],
        showsBeforeAfterPreview: false,
      ),
    ),

    // 7) Creative note — "your call". NEVER auto-op'd: keep it, or a human
    //    promotes it by hand.
    RenderRule(
      name: 'note.creative',
      match: (e) => e.kind == 'note',
      descriptor: (_) => const RenderDescriptor(
        markerStyle: MarkerStyle.point,
        colorRole: ColorRole.creative,
        isActionable: true,
        isCreative: true,
        panelActions: [PanelAction.keepNote, PanelAction.promoteToOp],
        showsBeforeAfterPreview: false,
      ),
    ),

    // 8) Marker — a pure point annotation, informational.
    RenderRule(
      name: 'marker.point',
      match: (e) => e.kind == 'marker',
      descriptor: (_) => const RenderDescriptor(
        markerStyle: MarkerStyle.point,
        colorRole: ColorRole.neutral,
        isActionable: false,
        isCreative: false,
        panelActions: [],
        showsBeforeAfterPreview: false,
      ),
    ),

    // 9) DEFAULT for an op this build has never seen. Extension-by-DATA: it
    //    still renders as a range and still offers the gate when proposed —
    //    no code change was needed to accept the new op.
    RenderRule(
      name: 'default.opLike',
      match: (e) => e.kind == 'op' || e.op != null,
      descriptor: (e) {
        final role = switch (e.state) {
          'approved' => ColorRole.approved,
          'applied' => ColorRole.applied,
          'rejected' || 'superseded' => ColorRole.rejected,
          _ => e.proposedBy == 'agent' ? ColorRole.aiProposed : ColorRole.proposed,
        };
        final actionable = e.state == 'proposed' ||
            e.state == 'approved' ||
            e.state == 'applied';
        final actions = e.state == 'proposed'
            ? const [PanelAction.approve, PanelAction.edit, PanelAction.reject]
            : (e.state == 'approved' || e.state == 'applied')
                ? const [PanelAction.toggleActive]
                : const <PanelAction>[];
        return RenderDescriptor(
          markerStyle: MarkerStyle.range,
          colorRole: role,
          isActionable: actionable,
          isCreative: false,
          panelActions: actions,
          showsBeforeAfterPreview:
              e.state == 'proposed' || e.state == 'approved',
        );
      },
    ),

    // 10) TOTAL fallback — an unknown kind that is not op-like renders as a
    //     neutral point. `describe` is total, so a forward decode never
    //     crashes and never renders blank.
    RenderRule(
      name: 'default.pointNeutral',
      match: (_) => true,
      descriptor: (_) => const RenderDescriptor(
        markerStyle: MarkerStyle.point,
        colorRole: ColorRole.neutral,
        isActionable: false,
        isCreative: false,
        panelActions: [],
        showsBeforeAfterPreview: false,
      ),
    ),
  ]);
}

/// SMPTE-ish timecode for a frame count at a rate. Frames stay the truth; the
/// rate only governs the label.
String smpteLabel(int frames, double fps) {
  final rate = fps > 0 ? fps.round() : 24;
  final f = frames < 0 ? 0 : frames;
  final totalSeconds = f ~/ rate;
  final hh = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
  final mm = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
  final ss = (totalSeconds % 60).toString().padLeft(2, '0');
  final ff = (f % rate).toString().padLeft(2, '0');
  return '$hh:$mm:$ss:$ff';
}
