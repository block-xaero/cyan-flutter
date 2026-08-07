// widgets/parity/parity_review_player.dart
//
// PARITY face_review_player · LAYER 3 (the pure view) — THE POST-PRODUCTION
// SURFACE.
//
// SwiftUI reference (READ-ONLY):
//   Views/ReviewPlayerView.swift      — the three surface states, the transport,
//                                       the version selector, produce master
//   Views/RegionDrawingOverlay.swift  — the drawing layer on the hero
//   Views/RegionComposerView.swift    — the chip rows + the ask field
//   Views/ScrubberView.swift          — the weaved strip
//
// Renders the change list DECLARATIVELY off the render registry — no per-source
// or per-op branching. Three surface states over ONE hero:
//
//   State A (default) — hero + the weaved strip (op spans in their role tint,
//                       note marks, the playhead) + transport. Calm.
//   …and layered on the hero, the DRAWING SURFACE: a RIGHT drag seeds a region
//                       at the press frame and the composer opens on release.
//                       It claims the secondary button only, so the card, the
//                       strip and the transport keep working under it.
//   State B (on pause / focus) — one in-place card over the hero: the op, its
//                       params, the intent, and the actions the REGISTRY says
//                       this entry has. A creative note is "your call" and has
//                       no approve gate; a mechanical one has all three.
//   State C (the rail) — tc-ordered entries + the gate banner (phase, round,
//                       waiting_on).
//
// All data flows through `ReviewPlayerController` (the single `CyanBackend`
// seam); all video flows through `ReviewVideoSurface`. The view is identical on
// the fake and the real engine.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/region_gesture.dart';
import '../../models/review_entry.dart';
import '../../models/spatial_note.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../providers/region_composer_controller.dart';
import '../../providers/review_player_controller.dart';
import '../../providers/review_player_provider.dart';
import '../../services/review_video_surface.dart';
import '../../theme/monokai_theme.dart';

/// The hero's display aspect. The picture is aspect-fit inside it, and every
/// region coordinate is normalized against the PICTURE, never this box.
const double kHeroAspect = 16 / 9;

class ParityReviewPlayerView extends StatelessWidget {
  /// The board whose review lane this player reads.
  final String boardId;

  /// An explicit player, for callers that drive their own reads (Tier-1 tests
  /// step the controller directly). Null uses the app's per-board one.
  final ReviewPlayerController? controller;

  /// An explicit surface. Null mounts the app's own (AVFoundation).
  final ReviewVideoSurface? surface;

  /// The surface the GRAPHICS preview mounts on. It is a second surface on
  /// purpose: previewing a render must not disturb the hero's media, playhead
  /// or version — closing the preview returns the player exactly as it was.
  final ReviewVideoSurface? graphicSurface;

  const ParityReviewPlayerView({
    super.key,
    required this.boardId,
    this.controller,
    this.surface,
    this.graphicSurface,
  });

  @override
  Widget build(BuildContext context) {
    // A different board is a different player: the ledger read, the media and
    // the composer's anchors all belong to ONE board, so the surface is keyed
    // by it rather than re-pointed underneath its own state.
    return _ReviewPlayerSurface(
      key: ValueKey('review.player.$boardId'),
      boardId: boardId,
      controller: controller,
      surface: surface,
      graphicSurface: graphicSurface,
    );
  }
}

enum _RailFilter { all, needsYou, notes, ops }

class _ReviewPlayerSurface extends ConsumerStatefulWidget {
  final String boardId;
  final ReviewPlayerController? controller;
  final ReviewVideoSurface? surface;
  final ReviewVideoSurface? graphicSurface;

  const _ReviewPlayerSurface({
    super.key,
    required this.boardId,
    this.controller,
    this.surface,
    this.graphicSurface,
  });

  @override
  ConsumerState<_ReviewPlayerSurface> createState() =>
      _ParityReviewPlayerViewState();
}

class _ParityReviewPlayerViewState
    extends ConsumerState<_ReviewPlayerSurface> {
  late final ReviewPlayerController _player;
  late final ReviewVideoSurface _surface;
  late final RegionComposerController _composer;
  late final VoidCallback _unsubscribePlayer;
  late final VoidCallback _unsubscribeComposer;

  /// True once the first listener delivery has landed — before that, the
  /// element cannot be marked dirty, so the state assigns rather than setState.
  bool _mountedOnce = false;

  bool _ownsPlayer = false;
  bool _ownsSurface = false;

  /// The graphics preview's own surface, and the card it is showing. Both are
  /// lazy: a board with no registered render never mounts a second decoder.
  ReviewVideoSurface? _graphicSurface;
  bool _ownsGraphicSurface = false;
  BoardGraphic? _previewGraphic;

  ReviewPlayerState _state = const ReviewPlayerState();
  RegionComposerState _composerState = const RegionComposerState();

  /// What the hero actually has mounted — the remount guard, so a conform that
  /// publishes v2 reaches the hero without tearing the view down.
  String? _mounted;

  bool _railVisible = true;
  _RailFilter _filter = _RailFilter.all;

  final TextEditingController _ask = TextEditingController();
  final TextEditingController _tcIn = TextEditingController();
  final TextEditingController _tcOut = TextEditingController();
  final TextEditingController _params = TextEditingController();

  @override
  void initState() {
    super.initState();
    final injected = widget.controller;
    if (injected != null) {
      _player = injected;
    } else {
      _ownsPlayer = true;
      _player = ReviewPlayerController(
        backend: ref.read(cyanBackendProvider),
        boardId: widget.boardId,
      );
    }
    final surface = widget.surface;
    if (surface != null) {
      _surface = surface;
    } else {
      _ownsSurface = true;
      _surface = ref.read(reviewVideoSurfaceFactoryProvider)();
    }

    // Version and tenant are read LIVE at capture time — both arrive async on
    // the player, so capturing either by value here would freeze a placeholder
    // and the engine would refuse every note the composer sent.
    _composer = RegionComposerController(
      backend: ref.read(cyanBackendProvider),
      boardId: widget.boardId,
      resolveTenantId: () => _player.current.tenantId ?? '',
      resolveAssetHash: () => _player.current.assetHash ?? '',
      resolveVersionId: () => 'v${_player.current.selectedVersionNumber}',
      resolveSourceFrame: _player.masterFrameForDisplay,
      isCaptureGrade: () => _surface.isCaptureGrade,
      playheadFrame: () => _surface.currentFrame,
      isPlaying: () => _surface.isPlaying,
      pause: _surface.pause,
    );

    _state = _player.current;
    _composerState = _composer.current;
    _unsubscribePlayer = _player.addListener(_onPlayer);
    _unsubscribeComposer = _composer.addListener(_onComposer);
    _surface.addListener(_onSurface);
    _mountedOnce = true;

    // The ledger, then the media it names. The graphics rail is its OWN read:
    // it answers for boards with no review lane at all, so it never waits on
    // one.
    _player.load();
    _player.loadGraphics();
  }

  /// The preview's surface, mounted on first use. An injected one is used as
  /// given (tests drive the same seam the app mounts AVFoundation on).
  ReviewVideoSurface get _graphics {
    final existing = _graphicSurface;
    if (existing != null) return existing;
    final injected = widget.graphicSurface;
    final surface = injected ?? ref.read(reviewVideoSurfaceFactoryProvider)();
    _ownsGraphicSurface = injected == null;
    _graphicSurface = surface;
    surface.addListener(_onGraphicSurface);
    return surface;
  }

  void _onGraphicSurface() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _unsubscribePlayer();
    _unsubscribeComposer();
    _surface.removeListener(_onSurface);
    _composer.dispose();
    _graphicSurface?.removeListener(_onGraphicSurface);
    if (_ownsGraphicSurface) _graphicSurface?.dispose();
    if (_ownsPlayer) _player.dispose();
    if (_ownsSurface) _surface.dispose();
    _ask.dispose();
    _tcIn.dispose();
    _tcOut.dispose();
    _params.dispose();
    super.dispose();
  }

  void _onPlayer(ReviewPlayerState s) {
    if (_mountedOnce) {
      setState(() => _state = s);
    } else {
      _state = s;
    }
    _mountSelectedVersion();
  }

  void _onComposer(RegionComposerState s) {
    if (_mountedOnce) {
      setState(() => _composerState = s);
    } else {
      _composerState = s;
    }
  }

  void _onSurface() {
    // The surface is the playhead's only source. The controller sees frame
    // indices and nothing else.
    _player.setPlayhead(_surface.currentFrame);
    _player.adoptFrameRate(_surface.fps);
    _composer.notePlayhead(_surface.currentFrame);
    if (mounted) setState(() {});
  }

  /// Mount the SELECTED version on the hero, preserving the moment on screen:
  /// the master frame captured BEFORE the switch re-seeks through the map that
  /// applies AFTER it, so a head trim keeps the same picture rather than the
  /// same frame number. A no-op when the target is already mounted.
  Future<void> _mountSelectedVersion() async {
    final path = _state.selectedVersionPath;
    if (path == null || path == _mounted) return;
    final masterFrame = _player.masterFrameForDisplay(_surface.currentFrame);
    _mounted = path;
    await _surface.load(path, fps: _state.fps);
    if (!mounted) return;
    _surface.seek(_player.displayFrameForMaster(masterFrame));
  }

  Future<void> _switchVersion(int number) async {
    if (number == _state.selectedVersionNumber) return;
    _surface.pause();
    _player.selectVersion(number);
    await _mountSelectedVersion();
  }

  /// Focus an entry: pause, seek to its picture (master-anchored entry → proxy
  /// coordinates), and raise its card.
  void _focus(ReviewEntry entry) {
    _surface.pause();
    _surface.seek(_player.displayFrameForMaster(entry.tcIn));
    _player.focus(entry.id);
  }

  /// After a gate decision the controller focuses the next unresolved entry —
  /// follow it, so the review flows gate-to-gate without hunting.
  void _seekToSelection() {
    final next = _state.selectedEntry;
    if (next != null) _surface.seek(_player.displayFrameForMaster(next.tcIn));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MonokaiTheme.background,
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The hero takes the room it can: a review player that
                      // shows the picture small is not a review player.
                      Expanded(child: Center(child: _hero())),
                      const SizedBox(height: 10),
                      _strip(),
                      const SizedBox(height: 8),
                      _transport(),
                      // The graphics rail exists ONLY when the board holds
                      // registered graphics — an empty board shows nothing
                      // rather than an affordance with nothing behind it.
                      if (_state.graphics.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _graphicsStrip(),
                      ],
                    ],
                  ),
                ),
              ),
              if (_railVisible) _rail(),
            ],
          ),
          if (_previewGraphic != null) Positioned.fill(child: _graphicPreview()),
        ],
      ),
    );
  }

  // ---- the hero + the drawing surface --------------------------------------

  Widget _hero() {
    return AspectRatio(
      aspectRatio: kHeroAspect,
      child: LayoutBuilder(
        builder: (context, box) {
          final bounds = Size(box.maxWidth, box.maxHeight);
          final picture = pictureRect(bounds, kHeroAspect);
          return Listener(
            key: const ValueKey('review.hero'),
            // The drawing layer claims the SECONDARY button only: a left drag
            // stays free for scrubbing and selection, exactly as the gesture
            // spec puts the region on right-click-drag.
            onPointerDown: (e) {
              if (e.buttons & kSecondaryButton == 0) return;
              _composer.beginDrag(e.localPosition);
            },
            onPointerMove: (e) {
              if (_composerState.inFlight == null) return;
              _composer.extendDrag(e.localPosition);
            },
            onPointerUp: (_) {
              if (_composerState.inFlight == null) return;
              _composer.endDrag(bounds);
            },
            onPointerCancel: (_) => _composer.cancelDrag(resume: _surface.play),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFF14140F)),
                  _surface.buildPicture(context),
                  ..._anchoredRegions(picture),
                  ..._draftRegion(picture),
                  ..._rubberBand(picture),
                  if (_composerState.draft != null)
                    _composerPanel()
                  else if (_state.cardEntry != null && !_surface.isPlaying)
                    _entryCard(_state.cardEntry!),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Regions are visible ONLY on the frame they were drawn on. A region is a
  /// tracker seed with no motion path; painting it across a range would claim
  /// tracking the format explicitly does not have.
  List<Widget> _anchoredRegions(Rect picture) {
    final out = <Widget>[];
    for (final e in _state.entries) {
      final region = e.region;
      if (region == null) continue;
      if (_player.displayFrameForMaster(region.keyFrame) !=
          _state.playheadFrame) {
        continue;
      }
      final role = _player.registry.describe(e).colorRole;
      out.add(_regionBox(
        key: ValueKey('review.region.${e.id}'),
        region: region,
        picture: picture,
        color: _roleColor(role),
        emphasis: 1,
      ));
    }
    return out;
  }

  /// The DRAFT box. On release the rubber band is cleared and the draft is the
  /// only record of the selection, so it stays VISIBLE for the whole life of
  /// the composer — full strength on its own frame, dimmed (never hidden)
  /// elsewhere.
  List<Widget> _draftRegion(Rect picture) {
    final draft = _composerState.draft;
    if (draft == null) return const [];
    return [
      _regionBox(
        key: const ValueKey('review.region.draft'),
        region: NoteRegion(
          keyFrame: draft.displayedFrame,
          shape: draft.shape,
          rasterRef: draft.raster,
        ),
        picture: picture,
        color: MonokaiTheme.cyan,
        emphasis: draftEmphasis(
            anchorFrame: draft.displayedFrame, playhead: _state.playheadFrame),
      ),
    ];
  }

  List<Widget> _rubberBand(Rect picture) {
    final f = _composerState.inFlight;
    if (f == null || f.points.length < 2) return const [];
    final a = f.points.first;
    final b = f.points.last;
    final rect = Rect.fromPoints(a, b);
    return [
      Positioned.fromRect(
        rect: rect,
        child: Container(
          key: const ValueKey('review.region.live'),
          decoration: BoxDecoration(
            border: Border.all(color: MonokaiTheme.cyan, width: 1.5),
            color: MonokaiTheme.cyan.withValues(alpha: 0.08),
          ),
        ),
      ),
    ];
  }

  Widget _regionBox({
    required Key key,
    required NoteRegion region,
    required Rect picture,
    required Color color,
    required double emphasis,
  }) {
    final points = region.project(picture.size);
    final rect = points.length >= 2
        ? Rect.fromPoints(points.first, points.last)
        : Rect.fromCenter(
            center: points.isEmpty ? picture.center : points.first,
            width: 18,
            height: 18);
    return Positioned.fromRect(
      rect: rect.shift(picture.topLeft),
      child: IgnorePointer(
        child: Opacity(
          key: key,
          opacity: emphasis,
          child: CustomPaint(
            painter: _ShapePainter(kind: region.shape.kind, color: color),
          ),
        ),
      ),
    );
  }

  // ---- the composer (the capture surface) ----------------------------------

  Widget _composerPanel() {
    final draft = _composerState.draft!;
    return Positioned(
      left: 10,
      right: 10,
      bottom: 10,
      child: Container(
        key: const ValueKey('review.composer'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: MonokaiTheme.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MonokaiTheme.cyan.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('${draft.shape.kind} @ ${smpteLabel(draft.displayedFrame, _state.fps)}',
                    key: const ValueKey('review.composer.anchor'),
                    style: MonokaiTheme.labelSmall
                        .copyWith(color: MonokaiTheme.cyan)),
                const Spacer(),
                // Skipping every row is FIRST-CLASS: no chip is required and
                // nothing nags for one.
                Text('weight ${_composerState.trainingWeight}',
                    style: MonokaiTheme.labelSmall),
                const SizedBox(width: 8),
                _iconButton(
                  key: const ValueKey('review.composer.cancel'),
                  icon: Icons.close,
                  tooltip: 'Discard this region',
                  onTap: _composer.cancel,
                ),
              ],
            ),
            const SizedBox(height: 6),
            _chipRow([
              for (final craft in _composer.craftShortlist())
                _chip(
                  key: ValueKey('review.composer.craft.${craft.wireName}'),
                  label: craft.label,
                  selected: _composerState.craft == craft,
                  onTap: () => _composer.tapCraft(craft),
                ),
              if (draft.shape.kind != 'point')
                _chip(
                  key: const ValueKey('review.composer.qualifier'),
                  label: 'like these pixels',
                  selected: _composerState.qualifyByColour,
                  onTap: _composer.toggleQualifier,
                ),
            ]),
            if (_composer.subjectShortlist().isNotEmpty) ...[
              const SizedBox(height: 4),
              _chipRow([
                for (final subject in _composer.subjectShortlist())
                  _chip(
                    key: ValueKey('review.composer.subject.$subject'),
                    label: subject,
                    selected: _composerState.subject == subject,
                    onTap: () => _composer.tapSubject(subject),
                  ),
              ]),
            ],
            if (_composer.defectShortlist().isNotEmpty) ...[
              const SizedBox(height: 4),
              _chipRow([
                for (final defect in _composer.defectShortlist())
                  _chip(
                    key: ValueKey('review.composer.defect.$defect'),
                    label: defect,
                    selected: _composerState.defect == defect,
                    onTap: () => _composer.tapDefect(defect),
                  ),
              ]),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('review.composer.field'),
                    controller: _ask,
                    style: MonokaiTheme.bodyMedium
                        .copyWith(color: MonokaiTheme.foreground),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'say what you want here',
                      hintStyle: MonokaiTheme.labelSmall,
                      filled: true,
                      fillColor: MonokaiTheme.background,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _sendAsk(),
                  ),
                ),
                const SizedBox(width: 8),
                _textButton(
                  key: const ValueKey('review.composer.send'),
                  label: _composerState.isAsking ? 'asking…' : 'Send',
                  color: MonokaiTheme.green,
                  onTap: _sendAsk,
                ),
              ],
            ),
            if (_composerState.failure != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_composerState.failure!,
                    key: const ValueKey('review.composer.failure'),
                    style: MonokaiTheme.labelSmall
                        .copyWith(color: MonokaiTheme.red)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendAsk() async {
    final text = _ask.text.trim();
    if (text.isEmpty) return;
    final stored = await _composer.send(text);
    // A refused write KEEPS the draft and the text: the reviewer's work is not
    // thrown away by a clear() that follows a write which never happened.
    if (stored == null) return;
    _ask.clear();
    // A committed note is a new ledger fact — re-read so the strip, the rail
    // and the overlay show it (and whatever the agent proposed from it).
    await _player.load();
  }

  // ---- State B: the in-place card ------------------------------------------

  Widget _entryCard(ReviewEntry entry) {
    final desc = _player.registry.describe(entry);
    final color = _roleColor(desc.colorRole);
    final editing = _state.editingEntryId == entry.id;
    return Positioned(
      left: 10,
      right: 10,
      bottom: 10,
      child: Container(
        key: ValueKey('review.card.${entry.id}'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MonokaiTheme.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (entry.entry.source != null)
                  _badge(entry.entry.source!.toUpperCase(), color),
                const SizedBox(width: 8),
                Text(_tcLabel(entry),
                    style: MonokaiTheme.codeSmall
                        .copyWith(color: MonokaiTheme.foreground)),
                if (entry.proposedBy == 'agent') ...[
                  const SizedBox(width: 8),
                  _badge('agent', MonokaiTheme.cyan),
                ],
                const Spacer(),
                _iconButton(
                  key: const ValueKey('review.card.dismiss'),
                  icon: Icons.close,
                  tooltip: 'Dismiss',
                  onTap: () => _player.focus(null),
                ),
              ],
            ),
            if (entry.intent.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('“${entry.intent}”',
                  style: MonokaiTheme.bodyMedium
                      .copyWith(color: MonokaiTheme.foreground)),
            ],
            if (desc.isCreative) ...[
              const SizedBox(height: 6),
              Text('Creative — your call.',
                  key: const ValueKey('review.card.creative'),
                  style: MonokaiTheme.labelMedium
                      .copyWith(color: MonokaiTheme.purple)),
            ] else if (entry.op != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.auto_fix_high, size: 11, color: color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('${entry.op} ${_paramsLine(entry)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MonokaiTheme.codeSmall
                            .copyWith(color: MonokaiTheme.textSecondary)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            if (editing) _editForm(entry) else _cardActions(entry, desc),
          ],
        ),
      ),
    );
  }

  /// The panel actions, straight from the registry — the view never decides.
  /// `toggleActive` and `promoteToOp` need engine verbs this build does not
  /// bind, so they render NOTHING rather than a button that lies.
  Widget _cardActions(ReviewEntry entry, RenderDescriptor desc) {
    final buttons = <Widget>[];
    for (final action in desc.panelActions) {
      switch (action) {
        case PanelAction.approve:
          buttons.add(_textButton(
            key: ValueKey('review.card.approve.${entry.id}'),
            label: 'Approve',
            color: MonokaiTheme.green,
            onTap: () async {
              await _player.approve(entry);
              _seekToSelection();
            },
          ));
        case PanelAction.edit:
          buttons.add(_textButton(
            key: ValueKey('review.card.edit.${entry.id}'),
            label: 'Edit',
            color: MonokaiTheme.yellow,
            onTap: () {
              _tcIn.text = '${entry.tcIn}';
              _tcOut.text = entry.tcOut?.toString() ?? '';
              _params.text = _paramsLine(entry);
              _player.beginEdit(entry.id);
            },
          ));
        case PanelAction.reject:
          buttons.add(_textButton(
            key: ValueKey('review.card.reject.${entry.id}'),
            label: 'Reject',
            color: MonokaiTheme.red,
            onTap: () async {
              await _player.reject(entry);
              _seekToSelection();
            },
          ));
        case PanelAction.keepNote:
          buttons.add(_textButton(
            key: ValueKey('review.card.keep.${entry.id}'),
            label: 'Keep as note',
            color: MonokaiTheme.purple,
            onTap: () async {
              // Keep = confirm it stays a note. It is never promoted to an op.
              await _player.approve(entry);
              _seekToSelection();
            },
          ));
        case PanelAction.promoteToOp:
        case PanelAction.toggleActive:
          break;
      }
    }
    return Wrap(spacing: 8, runSpacing: 6, children: buttons);
  }

  Widget _editForm(ReviewEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: _field(
                    key: const ValueKey('review.edit.tcIn'),
                    label: 'tc in',
                    controller: _tcIn)),
            const SizedBox(width: 8),
            Expanded(
                child: _field(
                    key: const ValueKey('review.edit.tcOut'),
                    label: 'tc out',
                    controller: _tcOut)),
          ],
        ),
        const SizedBox(height: 6),
        _field(
            key: const ValueKey('review.edit.params'),
            label: 'params',
            controller: _params),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          _textButton(
            key: ValueKey('review.edit.commit.${entry.id}'),
            label: 'Confirm edit',
            color: MonokaiTheme.green,
            onTap: () async {
              await _player.approveEdited(
                entry,
                tcIn: int.tryParse(_tcIn.text),
                tcOut: int.tryParse(_tcOut.text),
                params: _parseParams(_params.text),
              );
              _seekToSelection();
            },
          ),
          _textButton(
            key: const ValueKey('review.edit.cancel'),
            label: 'Cancel',
            color: MonokaiTheme.textMuted,
            onTap: _player.cancelEdit,
          ),
        ]),
      ],
    );
  }

  // ---- the weaved strip ----------------------------------------------------

  /// The entries and the playhead over one bed. The strip and the overlay read
  /// the SAME entry set, so they can never disagree about what exists or where.
  Widget _strip() {
    final duration = _surface.durationFrames > 0
        ? _surface.durationFrames
        : _stripSpan();
    return SizedBox(
      height: 26,
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth;
          double x(int frame) =>
              duration <= 0 ? 0 : (frame / duration).clamp(0.0, 1.0) * width;
          return GestureDetector(
            key: const ValueKey('review.strip'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              if (duration <= 0) return;
              _surface.pause();
              _surface.seek(((d.localPosition.dx / width) * duration).round());
            },
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 11,
                  child: Container(height: 4, color: MonokaiTheme.surface),
                ),
                for (final e in _state.entries)
                  Positioned(
                    left: x(_player.displayFrameForMaster(e.tcIn)),
                    top: 6,
                    child: GestureDetector(
                      key: ValueKey('review.strip.${e.id}'),
                      onTap: () => _focus(e),
                      child: Container(
                        width: _player.registry.describe(e).markerStyle ==
                                MarkerStyle.range
                            ? (x(_player.displayFrameForMaster(e.tcEnd)) -
                                    x(_player.displayFrameForMaster(e.tcIn)))
                                .clamp(6.0, width)
                            : 6,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _roleColor(_player.registry.describe(e).colorRole)
                              .withValues(alpha: e.active ? 0.85 : 0.4),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: x(_state.playheadFrame),
                  top: 2,
                  child: Container(
                      key: const ValueKey('review.strip.playhead'),
                      width: 2,
                      height: 22,
                      color: MonokaiTheme.red),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---- the graphics rail (AE-2: rendered graphics are first-class) ---------

  /// A horizontal strip of the board's registered graphic assets — what the
  /// workflow's render steps produced, previewable in place. The caller guards
  /// on non-empty, so this never draws an empty rail.
  Widget _graphicsStrip() {
    return Column(
      key: const ValueKey('review.graphics.strip'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome_motion,
                size: 12, color: MonokaiTheme.purple),
            const SizedBox(width: 6),
            Text('Graphics',
                style: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.textSecondary)),
            const SizedBox(width: 6),
            Container(
              key: const ValueKey('review.graphics.count'),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: MonokaiTheme.surface,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text('${_state.graphics.length}',
                  style: MonokaiTheme.labelSmall
                      .copyWith(color: MonokaiTheme.textMuted)),
            ),
            const Spacer(),
            Text("from the workflow's render steps",
                style: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.comment)),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _state.graphics.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _graphicCard(_state.graphics[i]),
          ),
        ),
      ],
    );
  }

  /// One graphic card. A file the ENGINE could not find on disk is grayed and
  /// carries an OFFLINE badge — an honest state, never a dead click.
  Widget _graphicCard(BoardGraphic g) {
    final playable = g.playable;
    return Tooltip(
      message: playable ? g.name : '${g.name} — the file is missing on disk',
      child: GestureDetector(
        key: ValueKey('review.graphic.${g.hash.substring(0, 8)}'),
        onTap: playable ? () => _openGraphic(g) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 128,
              height: 72,
              decoration: BoxDecoration(
                color: MonokaiTheme.surfaceLighter,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: MonokaiTheme.border),
              ),
              child: Center(
                child: playable
                    ? Container(
                        padding: const EdgeInsets.all(7),
                        decoration: const BoxDecoration(
                          color: Colors.black38,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow,
                            size: 14, color: Colors.white),
                      )
                    : _badge('OFFLINE', MonokaiTheme.textMuted,
                        key: ValueKey(
                            'review.graphic.offline.${g.hash.substring(0, 8)}')),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 128,
              child: Text(g.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MonokaiTheme.labelSmall.copyWith(
                      color: playable
                          ? MonokaiTheme.textSecondary
                          : MonokaiTheme.textDisabled)),
            ),
          ],
        ),
      ),
    );
  }

  /// Open a render in the in-place preview. The hero and the before/after pair
  /// are PAUSED, not unmounted: closing returns the player exactly as it was.
  Future<void> _openGraphic(BoardGraphic g) async {
    final path = g.path;
    if (path == null) return;
    _surface.pause();
    setState(() => _previewGraphic = g);
    await _graphics.load(path, fps: _state.fps);
  }

  void _closeGraphicPreview() {
    _graphicSurface?.pause();
    setState(() => _previewGraphic = null);
  }

  /// The in-place preview: a scrimmed panel with its OWN surface over the
  /// player. The hero's mounted media, playhead and version are untouched
  /// underneath.
  Widget _graphicPreview() {
    final g = _previewGraphic!;
    final surface = _graphics;
    return Stack(
      key: const ValueKey('review.graphic.preview'),
      children: [
        GestureDetector(
          key: const ValueKey('review.graphic.preview.scrim'),
          onTap: _closeGraphicPreview,
          child: Container(color: Colors.black.withValues(alpha: 0.85)),
        ),
        Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 640),
            margin: const EdgeInsets.all(30),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: MonokaiTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MonokaiTheme.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_motion,
                        size: 14, color: MonokaiTheme.purple),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(g.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MonokaiTheme.labelSmall
                              .copyWith(color: MonokaiTheme.foreground)),
                    ),
                    const SizedBox(width: 8),
                    _badge('AE RENDER', MonokaiTheme.purple),
                    const Spacer(),
                    _iconButton(
                      key: const ValueKey('review.graphic.preview.close'),
                      icon: Icons.cancel,
                      tooltip: 'Close',
                      color: MonokaiTheme.textMuted,
                      onTap: _closeGraphicPreview,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AspectRatio(
                  aspectRatio: kHeroAspect,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ColoredBox(
                      color: MonokaiTheme.surfaceLighter,
                      child: surface.buildPicture(context),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _iconButton(
                      key: const ValueKey('review.graphic.preview.toggle'),
                      icon: surface.isPlaying ? Icons.pause : Icons.play_arrow,
                      tooltip: surface.isPlaying ? 'Pause' : 'Play',
                      onTap: () =>
                          surface.isPlaying ? surface.pause() : surface.play(),
                    ),
                    const SizedBox(width: 8),
                    Text(_byteLabel(g.bytes),
                        key: const ValueKey('review.graphic.preview.bytes'),
                        style: MonokaiTheme.labelSmall
                            .copyWith(color: MonokaiTheme.textMuted)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// File-style byte label (1000-based, the same units the Swift card shows).
  static String _byteLabel(int bytes) {
    if (bytes < 1000) return '$bytes bytes';
    const units = ['kB', 'MB', 'GB', 'TB'];
    var value = bytes / 1000;
    var unit = 0;
    while (value >= 1000 && unit < units.length - 1) {
      value /= 1000;
      unit++;
    }
    return '${value.toStringAsFixed(1)} ${units[unit]}';
  }

  /// A bed for a surface that has not reported a duration: the ledger's own
  /// span, so entries stay placeable rather than all stacking at zero.
  int _stripSpan() {
    var span = 0;
    for (final e in _state.entries) {
      if (e.tcEnd > span) span = e.tcEnd;
    }
    return span == 0 ? 0 : (span * 1.1).round();
  }

  // ---- the transport -------------------------------------------------------

  Widget _transport() {
    final gates = _state.pendingGates.length;
    return Row(
      children: [
        _iconButton(
          key: const ValueKey('review.stepBack'),
          icon: Icons.skip_previous,
          tooltip: 'Step back one frame',
          onTap: () => _surface.step(-1),
        ),
        _iconButton(
          key: const ValueKey('review.playPause'),
          icon: _surface.isPlaying ? Icons.pause : Icons.play_arrow,
          tooltip: _surface.isPlaying ? 'Pause' : 'Play',
          onTap: () {
            if (_surface.isPlaying) {
              _surface.pause();
            } else {
              // Playing returns to the calm hero.
              _player.focus(null);
              _surface.play();
            }
          },
        ),
        _iconButton(
          key: const ValueKey('review.stepForward'),
          icon: Icons.skip_next,
          tooltip: 'Step forward one frame',
          onTap: () => _surface.step(1),
        ),
        const SizedBox(width: 8),
        Text(smpteLabel(_state.playheadFrame, _state.fps),
            key: const ValueKey('review.timecode'),
            style:
                MonokaiTheme.codeSmall.copyWith(color: MonokaiTheme.foreground)),
        const SizedBox(width: 8),
        // The playback state, said out loud: an operator should never have to
        // infer whether what they are looking at is running.
        Text(_surface.isPlaying ? 'Playing' : 'Paused',
            key: const ValueKey('review.playbackState'),
            style: MonokaiTheme.labelSmall.copyWith(
                color: _surface.isPlaying
                    ? MonokaiTheme.green
                    : MonokaiTheme.textMuted)),
        if (_state.versions.isNotEmpty) ...[
          const SizedBox(width: 10),
          _versionSelector(),
          if (_state.versionAdvance != null) ...[
            const SizedBox(width: 6),
            Container(
              key: const ValueKey('review.version.badge'),
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: MonokaiTheme.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_state.versionAdvance!.label,
                  style: MonokaiTheme.labelSmall
                      .copyWith(color: MonokaiTheme.green)),
            ),
          ],
        ],
        if (_state.version > 0) ...[
          const SizedBox(width: 6),
          _iconButton(
            key: const ValueKey('review.undo'),
            icon: Icons.undo,
            tooltip: 'Undo the cut — step the version head back',
            onTap: _player.undoCut,
          ),
          _iconButton(
            key: const ValueKey('review.redo'),
            icon: Icons.redo,
            tooltip: 'Redo the cut — step the version head forward',
            onTap: _player.redoCut,
          ),
        ],
        // The delivery is a PRODUCT action, and it is offered only once this
        // board's run HAS a delivered asset to render from.
        if (_state.canProduceMaster) ...[
          _iconButton(
            key: const ValueKey('review.produceMaster'),
            icon: Icons.inventory_2_outlined,
            tooltip: 'Produce master — render this version’s delivery',
            onTap: _player.produceMaster,
          ),
          if (_state.produceStatus.isNotEmpty)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(_state.produceStatus,
                    key: const ValueKey('review.produceMaster.status'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MonokaiTheme.labelSmall),
              ),
            ),
        ],
        const Spacer(),
        if (gates > 0)
          GestureDetector(
            key: const ValueKey('review.needYou'),
            onTap: () => setState(() {
              _filter = _RailFilter.needsYou;
              _railVisible = true;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: MonokaiTheme.yellow.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('$gates need you',
                  style: MonokaiTheme.labelSmall
                      .copyWith(color: MonokaiTheme.yellow)),
            ),
          ),
        _iconButton(
          key: const ValueKey('review.railToggle'),
          icon: Icons.view_sidebar_outlined,
          tooltip: 'Show all entries',
          color: _railVisible ? MonokaiTheme.cyan : MonokaiTheme.textMuted,
          onTap: () => setState(() => _railVisible = !_railVisible),
        ),
      ],
    );
  }

  /// The asset's versions, newest last — the hero follows the selection. Every
  /// round's cut is listable, so a reviewer can scrub back through round 1's
  /// picture and the notes that drove round 2 (vN belongs to round N−1).
  Widget _versionSelector() {
    return PopupMenuButton<int>(
      key: const ValueKey('review.version.selector'),
      tooltip: 'Version under review — pick a cut to compare',
      color: MonokaiTheme.surface,
      // Every round's cut is listed with what it IS, so the menu has to be wide
      // enough to say it.
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
      onSelected: _switchVersion,
      itemBuilder: (context) => [
        for (final v in _state.versions)
          PopupMenuItem<int>(
            key: ValueKey('review.version.option.v${v.number}'),
            value: v.number,
            child: Row(
              children: [
                Icon(
                    v.number == _state.selectedVersionNumber
                        ? Icons.check
                        : Icons.remove,
                    size: 12,
                    color: MonokaiTheme.cyan),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(_versionLabel(v),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MonokaiTheme.labelMedium
                          .copyWith(color: MonokaiTheme.foreground)),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: MonokaiTheme.cyan.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('v${_state.selectedVersionNumber}',
            key: const ValueKey('review.version.current'),
            style: MonokaiTheme.labelSmall
                .copyWith(color: MonokaiTheme.background)),
      ),
    );
  }

  String _versionLabel(AssetVersion v) {
    final round = v.number - 1 < 0 ? 0 : v.number - 1;
    if (_state.versions.length <= 1) return 'v${v.number} · round $round';
    if (v.number == 1) return 'v1 · round 0 — source';
    if (v.number == _state.versions.last.number) {
      return 'v${v.number} · round $round — conformed (newest)';
    }
    return 'v${v.number} · round $round';
  }

  // ---- State C: the rail ---------------------------------------------------

  Widget _rail() {
    final rows = [
      for (final e in _state.entries)
        if (switch (_filter) {
          _RailFilter.all => true,
          _RailFilter.needsYou => e.state == 'proposed',
          _RailFilter.notes => e.kind == 'note',
          _RailFilter.ops => e.kind == 'op',
        })
          e,
    ];
    return Container(
      key: const ValueKey('review.rail'),
      width: 320,
      decoration: const BoxDecoration(
        color: MonokaiTheme.background,
        border: Border(left: BorderSide(color: MonokaiTheme.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                if (_state.phase != null)
                  _badge(_state.phase!.label, MonokaiTheme.cyan,
                      key: const ValueKey('review.rail.phase')),
                const SizedBox(width: 6),
                Text('round ${_state.round}',
                    style: MonokaiTheme.labelSmall),
                const Spacer(),
                if (_state.waitingOn != null)
                  Flexible(
                    child: Text(
                        switch (_state.waitingOn!) {
                          WaitingOn.you => 'waiting on you',
                          WaitingOn.cyan => 'waiting on cyan',
                          WaitingOn.producer => 'waiting on the producer',
                        },
                        key: const ValueKey('review.rail.waiting'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MonokaiTheme.labelSmall
                            .copyWith(color: MonokaiTheme.yellow)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _chipRow([
              for (final f in _RailFilter.values)
                _chip(
                  key: ValueKey('review.rail.filter.${f.name}'),
                  label: switch (f) {
                    _RailFilter.all => 'All',
                    _RailFilter.needsYou => 'Needs you',
                    _RailFilter.notes => 'Notes',
                    _RailFilter.ops => 'Ops',
                  },
                  selected: _filter == f,
                  onTap: () => setState(() => _filter = f),
                ),
            ]),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, color: MonokaiTheme.divider),
          Expanded(
            child: !_state.hydrated
                ? const Center(
                    child: CircularProgressIndicator(color: MonokaiTheme.cyan))
                : rows.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                              _state.phase == null
                                  ? 'This board has no review lane yet'
                                  : 'Nothing on this filter',
                              key: const ValueKey('review.rail.empty'),
                              textAlign: TextAlign.center,
                              style: MonokaiTheme.labelMedium),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: rows.length,
                        itemBuilder: (context, i) => _railRow(rows[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _railRow(ReviewEntry entry) {
    final desc = _player.registry.describe(entry);
    final color = _roleColor(desc.colorRole);
    final selected = _state.selectedEntryId == entry.id;
    return InkWell(
      key: ValueKey('review.rail.row.${entry.id}'),
      onTap: () => _focus(entry),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: selected ? MonokaiTheme.selection : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_tcLabel(entry),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MonokaiTheme.codeSmall
                          .copyWith(color: MonokaiTheme.textSecondary)),
                ),
                const SizedBox(width: 6),
                Text(entry.op ?? entry.kind,
                    style: MonokaiTheme.labelSmall.copyWith(color: color)),
              ],
            ),
            const SizedBox(height: 3),
            Text(entry.intent.isEmpty ? '—' : entry.intent,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: MonokaiTheme.labelMedium
                    .copyWith(color: MonokaiTheme.foreground)),
            if (entry.region != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('region · ${entry.region!.shape.kind}',
                    key: ValueKey('review.rail.region.${entry.id}'),
                    style: MonokaiTheme.labelSmall
                        .copyWith(color: MonokaiTheme.cyan)),
              ),
          ],
        ),
      ),
    );
  }

  // ---- small pieces --------------------------------------------------------

  String _tcLabel(ReviewEntry e) {
    final start = smpteLabel(e.tcIn, _state.fps);
    if (e.entry.isPoint) return start;
    return '$start – ${smpteLabel(e.tcEnd, _state.fps)}';
  }

  String _paramsLine(ReviewEntry e) {
    if (e.entry.params.isEmpty) return '';
    return e.entry.params.entries.map((kv) => '${kv.key}=${kv.value}').join(' ');
  }

  /// `k=v k=v` back into the engine's typed payload. Numbers stay numbers —
  /// the engine's op params are typed and a stringified number is not one.
  Map<String, dynamic>? _parseParams(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final out = <String, dynamic>{};
    for (final pair in trimmed.split(RegExp(r'\s+'))) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final key = pair.substring(0, eq);
      final value = pair.substring(eq + 1);
      final number = num.tryParse(value);
      out[key] = number ?? value;
    }
    return out.isEmpty ? null : out;
  }

  Color _roleColor(ColorRole role) => switch (role) {
        ColorRole.proposed => MonokaiTheme.yellow,
        ColorRole.aiProposed => MonokaiTheme.cyan,
        ColorRole.approved => MonokaiTheme.green,
        ColorRole.rejected => MonokaiTheme.comment,
        ColorRole.applied => MonokaiTheme.green,
        ColorRole.creative => MonokaiTheme.purple,
        ColorRole.neutral => MonokaiTheme.textMuted,
      };

  Widget _chipRow(List<Widget> children) =>
      Wrap(spacing: 6, runSpacing: 6, children: children);

  Widget _chip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? MonokaiTheme.cyan.withValues(alpha: 0.22)
              : MonokaiTheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? MonokaiTheme.cyan : MonokaiTheme.border),
        ),
        child: Text(label,
            style: MonokaiTheme.labelSmall.copyWith(
                color:
                    selected ? MonokaiTheme.cyan : MonokaiTheme.textSecondary)),
      ),
    );
  }

  Widget _badge(String text, Color color, {Key? key}) => Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: MonokaiTheme.labelSmall.copyWith(color: color)),
      );

  Widget _iconButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color color = MonokaiTheme.foreground,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }

  Widget _textButton({
    required Key key,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color),
        ),
        child: Text(label,
            style: MonokaiTheme.labelSmall.copyWith(color: color)),
      ),
    );
  }

  Widget _field({
    required Key key,
    required String label,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: MonokaiTheme.labelSmall),
        const SizedBox(height: 2),
        TextField(
          key: key,
          controller: controller,
          style: MonokaiTheme.codeSmall.copyWith(color: MonokaiTheme.foreground),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: MonokaiTheme.background,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }
}

/// Draws the region's own shape inside its bounding box. A rect is a rect, an
/// ellipse is an ellipse and a path is the polyline the reviewer drew — the
/// shape the format stores is the shape they see.
class _ShapePainter extends CustomPainter {
  final String kind;
  final Color color;

  const _ShapePainter({required this.kind, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    final fill = Paint()..color = color.withValues(alpha: 0.10);
    final rect = Offset.zero & size;
    switch (kind) {
      case 'ellipse':
        canvas.drawOval(rect, fill);
        canvas.drawOval(rect, stroke);
      case 'point':
        canvas.drawCircle(rect.center, size.shortestSide / 2, fill);
        canvas.drawCircle(rect.center, size.shortestSide / 2, stroke);
      default:
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, stroke);
    }
  }

  @override
  bool shouldRepaint(_ShapePainter old) =>
      old.kind != kind || old.color != color;
}
