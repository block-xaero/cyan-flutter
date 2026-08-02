// models/spine_lane.dart
//
// PARITY face `spine_e2e` · the DCC LANES.
//
// The post-production spine is not a flat list of steps — it is seven rooms the
// work walks through in order: ingest, review, edit, sound, conform, color,
// master. The engine does not hand the lane down: a template's `stage` is
// DISPLAY-ONLY and the compile "derives the real stage from the cell text and
// accepts no hint" (parity_models.dart, `TemplateStep.stage`). So the lane is
// read the same way the engine reads a step — out of its English.
//
// Reference (READ-ONLY): cyan-backend/src/templates.rs, the `DEMO_SPINE_ID`
// seed, whose steps carry exactly these seven stages.
//
// The classifier is ORDERED, and the order is the whole trick: several steps
// name two rooms at once ("land the review notes in the session via
// @protools.inject_notes" is SOUND, not review; "produce the graded master" is
// MASTER, not color). The most specific claim wins, so each rule below is
// placed where it out-ranks the looser word it shares a step with.

/// One room of the post-production spine.
enum SpineLane {
  ingest,
  review,
  edit,
  sound,
  conform,
  color,
  master,

  /// A step whose English names no room — an authored step that is not part of
  /// the spine. Kept as a lane rather than dropped: a step nobody can place is
  /// still a step the operator has to see.
  unplaced;

  String get label => switch (this) {
        SpineLane.ingest => 'Ingest',
        SpineLane.review => 'Review',
        SpineLane.edit => 'Edit',
        SpineLane.sound => 'Sound',
        SpineLane.conform => 'Conform',
        SpineLane.color => 'Color',
        SpineLane.master => 'Master',
        SpineLane.unplaced => 'Other',
      };
}

/// The spine's rooms in WALK ORDER — the order the template authors them in,
/// and the order the surface lays them out.
const List<SpineLane> kSpineWalk = [
  SpineLane.ingest,
  SpineLane.review,
  SpineLane.edit,
  SpineLane.sound,
  SpineLane.conform,
  SpineLane.color,
  SpineLane.master,
];

/// The ordered rules. First match wins; see the header for why the order is
/// load-bearing.
const List<(SpineLane, List<String>)> _laneRules = [
  (SpineLane.ingest, ['ingest', 'probe']),
  // "produce the graded master" says both `graded` and `master`. Delivery wins.
  (SpineLane.master, ['master', 'deliver']),
  (SpineLane.conform, ['conform', 'relink']),
  (SpineLane.color, ['resolve', 'lut', 'look', 'grade', 'color', 'colour']),
  // "land the REVIEW NOTES in the session via @protools.inject_notes" is the
  // sound room's work, not another review round.
  (SpineLane.sound, ['protools', 'pro tools', 'turnover', 'aaf', 'audio']),
  // "post the confirmed REVIEW NOTES as markers" is the cutting room's work.
  (SpineLane.edit, [
    'premiere',
    'marker',
    'picture lock',
    'sequence',
    'timeline',
  ]),
  (SpineLane.review, ['frameio', 'frame.io', 'review', 'comment']),
];

extension SpineLaneX on SpineLane {
  /// Which room a step belongs to, read out of its authored English.
  static SpineLane forStepText(String text) {
    final lower = text.toLowerCase();
    for (final (lane, words) in _laneRules) {
      for (final word in words) {
        if (lower.contains(word)) return lane;
      }
    }
    return SpineLane.unplaced;
  }
}

/// The two steps the spine hinges on, recognised the same way — by what the
/// author wrote, never by an index into the template.

/// Picture lock: the confirm that closes the cutting room and lets the sound
/// room start. Nothing downstream may move until a human has said this.
bool isPictureLockStep(String text) =>
    text.toLowerCase().contains('picture lock');

/// The producer-review round: the proxy goes out, the window opens, and the
/// notes that come back are what the agent pass reads.
bool isProducerReviewStep(String text) {
  final lower = text.toLowerCase();
  return lower.contains('producer review');
}

/// The delivery hand-off — the last step, which produces the graded master.
bool isProduceMasterStep(String text) =>
    text.toLowerCase().contains('produce') && text.toLowerCase().contains('master');
