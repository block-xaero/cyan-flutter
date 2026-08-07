// widgets/parity/parity_video_face.dart
//
// PARITY face_video · LAYER 3 (the pure view).
//
// SwiftUI reference (READ-ONLY):
//   Views/VideoPlayerFace.swift — the pinned player, the note timeline, the
//        AI/human segmented notes panel with threads, and the note composer
//
// The board's media with its review pinned to it BY SECONDS. Four bands, top to
// bottom, exactly as the reference stacks them:
//
//   1. the player — the picture, a monospaced timecode overlay top-right, and
//      the note the playhead has most recently passed along the bottom;
//   2. the timeline — a progress track with one marker per root note in its
//      type colour, plus the ad-break revenue strip when the board has breaks;
//   3. the composer — the current timecode as a badge, the text field, and the
//      note-type send menu (a reply carries its parent's timecode instead);
//   4. the notes panel — AI findings and Review comments as two collapsible
//      sections, each note with its thread, its AI answer and its actions.
//
// All data flows through `VideoFaceController` (the one `CyanBackend` seam) and
// all video through `ReviewVideoSurface`, so the face is identical on the fake
// and on the real engine.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../providers/review_player_provider.dart';
import '../../providers/video_face_controller.dart';
import '../../services/review_video_surface.dart';
import '../../theme/monokai_theme.dart';

/// The player's display aspect — the same 16:9 box the review player uses.
const double kVideoFaceAspect = 16 / 9;

class ParityVideoFace extends StatelessWidget {
  final String boardId;

  /// An explicit controller, for callers driving their own reads.
  final VideoFaceController? controller;

  /// An explicit surface. Null mounts the app's own (AVFoundation).
  final ReviewVideoSurface? surface;

  const ParityVideoFace({
    super.key,
    required this.boardId,
    this.controller,
    this.surface,
  });

  @override
  Widget build(BuildContext context) {
    // A different board is a different face: the media, the note rail and the
    // composer's anchor all belong to ONE board.
    return _VideoFaceSurface(
      key: ValueKey('video.face.$boardId'),
      boardId: boardId,
      controller: controller,
      surface: surface,
    );
  }
}

class _VideoFaceSurface extends ConsumerStatefulWidget {
  final String boardId;
  final VideoFaceController? controller;
  final ReviewVideoSurface? surface;

  const _VideoFaceSurface({
    super.key,
    required this.boardId,
    this.controller,
    this.surface,
  });

  @override
  ConsumerState<_VideoFaceSurface> createState() => _ParityVideoFaceState();
}

class _ParityVideoFaceState extends ConsumerState<_VideoFaceSurface> {
  late final VideoFaceController _face;
  late final ReviewVideoSurface _surface;
  late final VoidCallback _unsubscribe;

  bool _ownsSurface = false;
  bool _mountedOnce = false;

  VideoFaceState _state = const VideoFaceState();

  /// What the player actually has mounted — the remount guard.
  String? _mounted;

  bool _showAi = true;
  bool _showHuman = true;
  bool _composerOpen = false;

  final TextEditingController _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    final injected = widget.controller;
    if (injected != null) {
      _face = injected;
    } else {
      _face = VideoFaceController(
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

    _state = _face.state;
    _unsubscribe = _face.addListener(_onFace);
    _surface.addListener(_onSurface);
    _mountedOnce = true;
    _face.load();
  }

  @override
  void dispose() {
    _unsubscribe();
    _surface.removeListener(_onSurface);
    if (_ownsSurface) _surface.dispose();
    _note.dispose();
    super.dispose();
  }

  void _onFace(VideoFaceState s) {
    if (_mountedOnce) {
      setState(() => _state = s);
    } else {
      _state = s;
    }
    _mountMedia();
  }

  void _onSurface() {
    if (mounted) setState(() {});
  }

  /// Mount whatever the engine resolved for this board. The proxy is preferred
  /// over the master for the same reason the review player prefers it: it is
  /// the cut that plays.
  Future<void> _mountMedia() async {
    final media = _state.media;
    final path = media?.proxyPath ?? media?.previewPath ?? media?.masterUri;
    if (path == null || path.isEmpty || path == _mounted) return;
    _mounted = path;
    await _surface.load(path);
  }

  /// The playhead in SECONDS — the unit a timecoded note is pinned in.
  double get _seconds =>
      _surface.fps > 0 ? _surface.currentFrame / _surface.fps : 0;

  double get _duration =>
      _surface.fps > 0 ? _surface.durationFrames / _surface.fps : 0;

  void _seekSeconds(double seconds) {
    _surface.pause();
    _surface.seek((seconds * _surface.fps).round());
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MonokaiTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _player(),
          const Divider(height: 1, color: MonokaiTheme.border),
          _timeline(),
          const Divider(height: 1, color: MonokaiTheme.border),
          Expanded(child: _notesPanel()),
        ],
      ),
    );
  }

  // ---- the player ----------------------------------------------------------

  Widget _player() {
    final active = _state.activeNoteAt(_seconds);
    return SizedBox(
      height: 300,
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: MonokaiTheme.surfaceLighter,
              child: Center(
                child: AspectRatio(
                  aspectRatio: kVideoFaceAspect,
                  child: _state.media == null && !_state.hydrated
                      ? const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _surface.buildPicture(context),
                ),
              ),
            ),
          ),
          // The timecode overlay, top-right — monospaced, because a timecode
          // that shifts as its digits change is unreadable while scrubbing.
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              key: const ValueKey('video.timecode'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(formatTimecode(_seconds),
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.white)),
            ),
          ),
          // The note the playhead has most recently passed.
          if (active != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 8,
              child: Container(
                key: const ValueKey('video.activeNote'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(_noteIcon(active.noteType),
                        size: 14, color: _noteColor(active.noteType)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(active.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.white)),
                    ),
                    const SizedBox(width: 8),
                    Text(active.author,
                        style: MonokaiTheme.labelSmall
                            .copyWith(color: MonokaiTheme.textMuted)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- the timeline --------------------------------------------------------

  Widget _timeline() {
    final duration = _duration;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 24,
            child: LayoutBuilder(
              builder: (context, box) {
                final width = box.maxWidth;
                double x(double seconds) => duration <= 0
                    ? 0
                    : (seconds / duration).clamp(0.0, 1.0) * width;
                return GestureDetector(
                  key: const ValueKey('video.timeline'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) {
                    if (duration <= 0) return;
                    _seekSeconds((d.localPosition.dx / width) * duration);
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(
                          child: Container(color: MonokaiTheme.surface)),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: x(_seconds),
                        child: Container(color: MonokaiTheme.cyan),
                      ),
                      for (final n in _state.roots)
                        Positioned(
                          left: (x(n.timecodeSeconds) - 4)
                              .clamp(0.0, width > 8 ? width - 8 : 0.0),
                          top: 8,
                          child: GestureDetector(
                            key: ValueKey('video.marker.${n.id}'),
                            onTap: () {
                              _seekSeconds(n.timecodeSeconds);
                              _face.select(n.id);
                            },
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _noteColor(n.noteType),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          // The revenue strip exists only when the board HAS ad breaks — the
          // number is derived from the notes, never a standing caption.
          if (_state.adBreakCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  key: const ValueKey('video.adRevenue'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: MonokaiTheme.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                      '${_state.adBreakCount} ad breaks · '
                      '\$${_thousands(_state.adBreakRevenue)} /1M views',
                      style: MonokaiTheme.labelSmall
                          .copyWith(color: MonokaiTheme.cyan)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- the notes panel -----------------------------------------------------

  Widget _notesPanel() {
    final ai = _state.aiFindings;
    final human = _state.humanComments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('Timecoded Notes',
                  style: MonokaiTheme.labelSmall
                      .copyWith(color: MonokaiTheme.foreground)),
              const Spacer(),
              Text('${ai.length} AI · ${human.length} human',
                  key: const ValueKey('video.counts'),
                  style: MonokaiTheme.labelSmall
                      .copyWith(color: MonokaiTheme.comment)),
              const SizedBox(width: 10),
              _iconButton(
                key: const ValueKey('video.export'),
                icon: Icons.ios_share,
                tooltip: 'Export to Notes',
                color: MonokaiTheme.yellow,
                onTap: _face.exportToNotes,
              ),
              _iconButton(
                key: const ValueKey('video.compose'),
                icon: Icons.add_circle,
                tooltip: 'Add a note at the current timecode',
                color: MonokaiTheme.cyan,
                onTap: () => setState(() => _composerOpen = !_composerOpen),
              ),
            ],
          ),
        ),
        if (_state.exportStatus != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
            child: Text(_state.exportStatus!,
                key: const ValueKey('video.export.status'),
                style: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.green)),
          ),
        if (_state.addedToPipeline != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
            child: Text('Added to pipeline: ${_state.addedToPipeline}',
                key: const ValueKey('video.pipeline.chip'),
                style: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.yellow)),
          ),
        if (_state.lastError != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
            child: Text(_state.lastError!,
                key: const ValueKey('video.error'),
                style:
                    MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.red)),
          ),
        if (_composerOpen && _state.replyingToId == null) _composer(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            children: [
              if (ai.isNotEmpty) ...[
                _sectionHeader(
                  key: const ValueKey('video.section.ai'),
                  title: 'AI Findings',
                  count: ai.length,
                  icon: Icons.memory,
                  color: MonokaiTheme.cyan,
                  expanded: _showAi,
                  onTap: () => setState(() => _showAi = !_showAi),
                ),
                if (_showAi)
                  for (final n in ai) _noteWithThread(n),
              ],
              if (human.isNotEmpty) ...[
                _sectionHeader(
                  key: const ValueKey('video.section.human'),
                  title: 'Review Comments',
                  count: human.length,
                  icon: Icons.people_outline,
                  color: MonokaiTheme.green,
                  expanded: _showHuman,
                  onTap: () => setState(() => _showHuman = !_showHuman),
                ),
                if (_showHuman)
                  for (final n in human) _noteWithThread(n),
              ],
              if (_state.roots.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text('No notes yet. Click + to add a note.',
                        key: const ValueKey('video.empty'),
                        style: MonokaiTheme.labelSmall
                            .copyWith(color: MonokaiTheme.comment)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader({
    required Key key,
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 6),
              Text(title, style: MonokaiTheme.labelSmall.copyWith(color: color)),
              const SizedBox(width: 6),
              Text('($count)',
                  style: MonokaiTheme.labelSmall
                      .copyWith(color: MonokaiTheme.comment)),
              const Spacer(),
              Icon(expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 12, color: MonokaiTheme.comment),
            ],
          ),
        ),
      ),
    );
  }

  // ---- the composer --------------------------------------------------------

  Widget _composer({String? parentId}) {
    final replying = parentId != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: MonokaiTheme.cyan.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
                replying ? 'reply' : formatTimecode(_seconds),
                key: ValueKey(
                    'video.composer.stamp${replying ? '.reply' : ''}'),
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: MonokaiTheme.cyan)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const ValueKey('video.composer.field'),
              controller: _note,
              style: const TextStyle(
                  fontSize: 13, color: MonokaiTheme.foreground),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: MonokaiTheme.surface,
                hintText: replying
                    ? 'Reply...'
                    : 'Add note at current timecode...',
                hintStyle: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.comment),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => _send('comment'),
            ),
          ),
          const SizedBox(width: 8),
          // The type picker IS the send button, exactly as the reference's
          // paperplane menu is: a note is always filed AS something.
          PopupMenuButton<String>(
            key: const ValueKey('video.composer.send'),
            tooltip: 'File this note',
            icon: const Icon(Icons.send, size: 15, color: MonokaiTheme.green),
            onSelected: _send,
            itemBuilder: (_) => [
              for (final type in kComposableNoteTypes)
                PopupMenuItem<String>(
                  key: ValueKey('video.composer.type.$type'),
                  value: type,
                  child: Text(_noteTypeLabel(type)),
                ),
            ],
          ),
          if (replying)
            _iconButton(
              key: const ValueKey('video.composer.cancel'),
              icon: Icons.close,
              tooltip: 'Cancel the reply',
              color: MonokaiTheme.comment,
              onTap: () {
                _note.clear();
                _face.replyTo(null);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _send(String type) async {
    final text = _note.text;
    if (text.trim().isEmpty) return;
    _note.clear();
    await _face.addNote(content: text, atSeconds: _seconds, noteType: type);
  }

  // ---- one note, with its thread -------------------------------------------

  Widget _noteWithThread(TimecodeNote note) {
    final replies = _state.repliesTo(note.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _noteRow(note),
        for (final r in replies)
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: _noteRow(r),
          ),
        if (replies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 40, bottom: 4),
            child: Row(
              children: [
                const Icon(Icons.forum_outlined,
                    size: 10, color: MonokaiTheme.comment),
                const SizedBox(width: 4),
                Text(
                    '${replies.length} '
                    '${replies.length == 1 ? 'reply' : 'replies'}',
                    key: ValueKey('video.thread.count.${note.id}'),
                    style: MonokaiTheme.labelSmall
                        .copyWith(color: MonokaiTheme.comment)),
              ],
            ),
          ),
        if (_state.replyingToId == note.id) _composer(parentId: note.id),
      ],
    );
  }

  Widget _noteRow(TimecodeNote note) {
    final selected = _state.selectedNoteId == note.id;
    final acting = _state.actingNoteId == note.id;
    return GestureDetector(
      key: ValueKey('video.note.${note.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _face.select(note.id);
        _seekSeconds(note.timecodeSeconds);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? MonokaiTheme.cyan.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 58,
                  child: Text(formatTimecode(note.timecodeSeconds),
                      key: ValueKey('video.note.tc.${note.id}'),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: MonokaiTheme.cyan)),
                ),
                const SizedBox(width: 8),
                Icon(_noteIcon(note.noteType),
                    size: 12, color: _noteColor(note.noteType)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(note.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: MonokaiTheme.foreground)),
                ),
                if (note.pipelineStepId != null) ...[
                  const SizedBox(width: 6),
                  _badge(note.pipelineStepId!, MonokaiTheme.purple),
                ],
                const SizedBox(width: 6),
                Text(note.author,
                    style: MonokaiTheme.labelSmall
                        .copyWith(color: MonokaiTheme.comment)),
                if (note.aiReviewed)
                  _dot(MonokaiTheme.cyan,
                      key: ValueKey('video.note.reviewed.${note.id}')),
                if (note.humanApproved)
                  _dot(MonokaiTheme.green,
                      key: ValueKey('video.note.approved.${note.id}')),
                // "Act on this" only exists for a note the AI has NOT seen —
                // re-asking a reviewed note would spend a call to be told the
                // same thing.
                if (!note.aiReviewed)
                  acting
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 5),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _iconButton(
                          key: ValueKey('video.note.act.${note.id}'),
                          icon: Icons.bolt,
                          tooltip: 'Send to AI for analysis',
                          color: MonokaiTheme.yellow,
                          onTap: () => _face.actOnNote(note),
                        ),
                if (note.replyTo == null)
                  _iconButton(
                    key: ValueKey('video.note.reply.${note.id}'),
                    icon: Icons.reply,
                    tooltip: 'Reply to this note',
                    color: MonokaiTheme.comment,
                    onTap: () {
                      _note.clear();
                      _face.replyTo(note.id);
                    },
                  ),
              ],
            ),
            if ((note.actionResult ?? '').isNotEmpty) _aiResult(note),
          ],
        ),
      ),
    );
  }

  /// The AI's answer under the note it answered, plus the three things a human
  /// can do with it.
  Widget _aiResult(TimecodeNote note) {
    final raw = note.actionResult!;
    final parsed = parseAiResponse(raw);
    final analysis = parsed['analysis'];
    final action = parsed['recommended_action'] ?? parsed['action'];
    final priority = parsed['priority'];
    return Padding(
      padding: const EdgeInsets.only(left: 66, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (analysis != null)
            _resultLine(Icons.memory, MonokaiTheme.green, analysis,
                key: ValueKey('video.note.analysis.${note.id}')),
          if (action != null)
            _resultLine(Icons.arrow_circle_right, MonokaiTheme.yellow, action,
                key: ValueKey('video.note.action.${note.id}')),
          if (priority != null)
            _resultLine(
                priority.toLowerCase().contains('high')
                    ? Icons.warning_amber
                    : Icons.flag,
                priority.toLowerCase().contains('high')
                    ? MonokaiTheme.red
                    : MonokaiTheme.comment,
                'Priority: $priority',
                key: ValueKey('video.note.priority.${note.id}')),
          // Unparseable is still an answer — the model said something and the
          // reviewer is entitled to read it.
          if (parsed.isEmpty)
            _resultLine(
                Icons.memory, MonokaiTheme.green, cleanRawResponse(raw),
                key: ValueKey('video.note.raw.${note.id}')),
          const SizedBox(height: 4),
          if (note.humanApproved)
            Row(
              key: ValueKey('video.note.approvedChip.${note.id}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified, size: 12, color: MonokaiTheme.green),
                const SizedBox(width: 4),
                Text('Approved',
                    style: MonokaiTheme.labelSmall
                        .copyWith(color: MonokaiTheme.green)),
              ],
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _actionChip(
                  key: ValueKey('video.note.toPipeline.${note.id}'),
                  icon: Icons.bolt,
                  label: 'Add to Pipeline',
                  color: MonokaiTheme.yellow,
                  onTap: () => _face.addToPipeline(note, action ?? raw),
                ),
                _actionChip(
                  key: ValueKey('video.note.approve.${note.id}'),
                  icon: Icons.check_circle_outline,
                  label: 'Approve',
                  color: MonokaiTheme.green,
                  onTap: () => _face.approve(note),
                ),
                _actionChip(
                  key: ValueKey('video.note.dismiss.${note.id}'),
                  icon: Icons.close,
                  label: 'Dismiss',
                  color: MonokaiTheme.comment,
                  filled: false,
                  onTap: () => _face.dismiss(note),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _resultLine(IconData icon, Color color, String text, {Key? key}) =>
      Padding(
        key: key,
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 11, color: color),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: color)),
            ),
          ],
        ),
      );

  // ---- small parts ---------------------------------------------------------

  Widget _actionChip({
    required Key key,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool filled = true,
  }) =>
      GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: filled ? color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 10, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: MonokaiTheme.labelSmall.copyWith(color: color)),
            ],
          ),
        ),
      );

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: TextStyle(
                fontFamily: 'monospace', fontSize: 9, color: color)),
      );

  Widget _dot(Color color, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(left: 4),
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      );

  Widget _iconButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color color = MonokaiTheme.foreground,
  }) =>
      Tooltip(
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

  static String _noteTypeLabel(String type) => switch (type) {
        'comment' => 'Comment',
        'qc_issue' => 'QC Issue',
        'revision' => 'Revision Needed',
        'approved' => 'Approved',
        _ => type,
      };

  /// The reference's `noteTypeIcon`, mapped SF Symbol → Material.
  static IconData _noteIcon(String type) => switch (type) {
        'comment' => Icons.chat_bubble_outline,
        'qc_issue' => Icons.warning_amber,
        'revision' => Icons.edit,
        'approved' => Icons.verified,
        'action' => Icons.bolt,
        'ad_break' => Icons.tv,
        'compliance' => Icons.shield,
        'compliance_bleep' => Icons.volume_off,
        'ad_insertion' => Icons.playlist_play,
        'qc_fix' => Icons.auto_fix_high,
        'review_comment' => Icons.forum,
        'plugin_result' => Icons.settings,
        // A note kind this build has never seen still draws — the face must not
        // lose an operator's note because the vocab grew.
        _ => Icons.chat_bubble_outline,
      };

  /// The reference's `noteTypeColor`.
  static Color _noteColor(String type) => switch (type) {
        'comment' => MonokaiTheme.cyan,
        'qc_issue' => MonokaiTheme.yellow,
        'revision' => MonokaiTheme.orange,
        'approved' => MonokaiTheme.green,
        'action' => MonokaiTheme.purple,
        'ad_break' => MonokaiTheme.cyan,
        'compliance' => MonokaiTheme.red,
        'compliance_bleep' => MonokaiTheme.red,
        'ad_insertion' => MonokaiTheme.cyan,
        'qc_fix' => MonokaiTheme.green,
        'review_comment' => MonokaiTheme.cyan,
        'plugin_result' => MonokaiTheme.comment,
        _ => MonokaiTheme.comment,
      };

  static String _thousands(int n) {
    final digits = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}
