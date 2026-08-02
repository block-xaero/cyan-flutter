// providers/review_player_controller.dart
//
// PARITY face_review_player · LAYER 2 (the portable view-model).
//
// SwiftUI reference (READ-ONLY):
//   ViewModels/ReviewPlayerViewModel.swift — the load envelope, the version
//        resolution + auto-advance, the confirm gate, produce master, and the
//        Keystone undo/redo of the version head
//   Review/ConformFrameMap.swift           — the proxy ⇄ master frame map
//
// Reads the change list + review state through the ONE `CyanBackend` seam
// (`changelistCommand` / `reviewCommand` / `ingestCommand`) and republishes it
// as the player's state: tc-ordered entries, the entry under the playhead, the
// pending-gate queue, the review phase, and the asset's selectable versions.
//
// TWO-WAY BUT INTENT-ONLY. Approve / edit / reject are `{"op":"confirm"}` — the
// three-actor authority model is the ENGINE's and it re-enforces every gate. A
// nil or unusable response is the EMPTY CALM STATE: no entries, no gates,
// nothing actionable, never a crash.
//
// The controller never touches a decoder. It sees frame indices and a play
// flag through `ReviewVideoSurface`, exactly as the Swift VM sees `VideoSurface`.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/cyan_backend.dart';
import '../ffi/parity_models.dart';
import '../models/review_entry.dart';
import '../services/review_video_surface.dart';

/// One selectable version of the asset: the ledger version number and the
/// playable media for it (v1 = the source, the newest = the conformed proxy).
class AssetVersion {
  final int number;
  final String? path;
  const AssetVersion(this.number, this.path);
}

/// A newest-version arrival the player reacted to — the "v1→v2" indicator.
class VersionAdvance {
  final int from;
  final int to;
  const VersionAdvance(this.from, this.to);
  String get label => 'v$from→v$to';
}

/// One piece of the piecewise-linear proxy ⇄ master map. `proxyEnd` null is an
/// unbounded tail; `masterStart` null marks inserted foreign media.
class ConformMapSegment {
  final int proxyStart;
  final int? proxyEnd;
  final int? masterStart;
  final double ratio;

  const ConformMapSegment({
    required this.proxyStart,
    this.proxyEnd,
    this.masterStart,
    this.ratio = 1,
  });

  static ConformMapSegment fromJson(Map<String, dynamic> j) => ConformMapSegment(
        proxyStart: (j['proxy_start'] as num?)?.toInt() ?? 0,
        proxyEnd: (j['proxy_end'] as num?)?.toInt(),
        masterStart: (j['master_start'] as num?)?.toInt(),
        ratio: (j['ratio'] as num?)?.toDouble() ?? 1,
      );
}

/// The proxy ⇄ master frame map for one version — the engine builds it, this
/// only EVALUATES it. Entries anchor in MASTER frames while the hero plays the
/// conformed proxy, so a comment at master 30 pins to proxy 18 after a
/// 12-frame head trim.
class ConformFrameMap {
  final List<ConformMapSegment> segments;
  const ConformFrameMap(this.segments);

  /// No structural op moved any frame — proxy tc IS master tc.
  bool get isIdentity =>
      segments.length == 1 &&
      segments[0].proxyStart == 0 &&
      segments[0].proxyEnd == null &&
      segments[0].masterStart == 0 &&
      segments[0].ratio == 1.0;

  /// proxy → master. Null for inserted foreign media or an unmapped frame.
  int? proxyToMaster(int proxyTc) {
    for (final s in segments) {
      final inside = proxyTc >= s.proxyStart &&
          (s.proxyEnd == null || proxyTc < s.proxyEnd!);
      if (inside) {
        final ms = s.masterStart;
        if (ms == null) return null;
        return ms + ((proxyTc - s.proxyStart) * s.ratio).round();
      }
    }
    return null;
  }

  /// master → proxy. Null when the cut removed that master frame.
  int? masterToProxy(int masterTc) {
    for (final s in segments) {
      final ms = s.masterStart;
      if (ms == null) continue;
      final pe = s.proxyEnd;
      final masterEnd =
          pe == null ? null : ms + ((pe - s.proxyStart) * s.ratio).round();
      if (masterTc >= ms && (masterEnd == null || masterTc < masterEnd)) {
        return s.proxyStart + ((masterTc - ms) / s.ratio).round();
      }
    }
    return null;
  }
}

/// Everything the review player renders. A plain value, so every state the
/// engine can put the face in is a state — never a special code path.
class ReviewPlayerState {
  /// True once a read attempt has completed. The ONLY time a spinner is honest
  /// is before the first one.
  final bool hydrated;

  /// The lane, tc-ordered (tc_in, then seq).
  final List<ReviewEntry> entries;

  /// The review-loop phase; null is the calm state (no ledger to read).
  final ReviewPhase? phase;
  final int round;
  final String branch;

  /// The ledger's frozen version head. 0 until a run has delivered one.
  final int version;

  final String? assetHash;
  final String? tenantId;

  final int playheadFrame;

  /// The entry under the playhead (smallest span wins, then seq).
  final String? currentEntryId;

  /// The card the human explicitly focused (rail tap / gate stepping).
  final String? selectedEntryId;

  /// The entry in the inline edit form, if any.
  final String? editingEntryId;

  final List<AssetVersion> versions;
  final int selectedVersionNumber;

  /// Set when a refresh found a NEWER version than what was on screen. Cleared
  /// by an explicit pick — the human has acknowledged the new cut.
  final VersionAdvance? versionAdvance;

  final String produceStatus;
  final String? lastDeliveryPath;
  final String? lastError;

  /// The rate labels and seconds conversion use. Frames stay the truth.
  final double fps;

  const ReviewPlayerState({
    this.hydrated = false,
    this.entries = const [],
    this.phase,
    this.round = 0,
    this.branch = 'main',
    this.version = 0,
    this.assetHash,
    this.tenantId,
    this.playheadFrame = 0,
    this.currentEntryId,
    this.selectedEntryId,
    this.editingEntryId,
    this.versions = const [],
    this.selectedVersionNumber = 0,
    this.versionAdvance,
    this.produceStatus = '',
    this.lastDeliveryPath,
    this.lastError,
    this.fps = kReviewFallbackFps,
  });

  ReviewPlayerState copyWith({
    bool? hydrated,
    List<ReviewEntry>? entries,
    ReviewPhase? phase,
    bool clearPhase = false,
    int? round,
    String? branch,
    int? version,
    String? assetHash,
    String? tenantId,
    int? playheadFrame,
    String? currentEntryId,
    bool clearCurrent = false,
    String? selectedEntryId,
    bool clearSelected = false,
    String? editingEntryId,
    bool clearEditing = false,
    List<AssetVersion>? versions,
    int? selectedVersionNumber,
    VersionAdvance? versionAdvance,
    bool clearAdvance = false,
    String? produceStatus,
    String? lastDeliveryPath,
    String? lastError,
    bool clearError = false,
    double? fps,
  }) =>
      ReviewPlayerState(
        hydrated: hydrated ?? this.hydrated,
        entries: entries ?? this.entries,
        phase: clearPhase ? null : (phase ?? this.phase),
        round: round ?? this.round,
        branch: branch ?? this.branch,
        version: version ?? this.version,
        assetHash: assetHash ?? this.assetHash,
        tenantId: tenantId ?? this.tenantId,
        playheadFrame: playheadFrame ?? this.playheadFrame,
        currentEntryId:
            clearCurrent ? null : (currentEntryId ?? this.currentEntryId),
        selectedEntryId:
            clearSelected ? null : (selectedEntryId ?? this.selectedEntryId),
        editingEntryId:
            clearEditing ? null : (editingEntryId ?? this.editingEntryId),
        versions: versions ?? this.versions,
        selectedVersionNumber:
            selectedVersionNumber ?? this.selectedVersionNumber,
        versionAdvance:
            clearAdvance ? null : (versionAdvance ?? this.versionAdvance),
        produceStatus: produceStatus ?? this.produceStatus,
        lastDeliveryPath: lastDeliveryPath ?? this.lastDeliveryPath,
        lastError: clearError ? null : (lastError ?? this.lastError),
        fps: fps ?? this.fps,
      );

  /// The pending-gate queue: proposed, active entries in tc order — the
  /// "N need you" count and the Approve/Edit/Reject stepper feed.
  List<ReviewEntry> get pendingGates =>
      [for (final e in entries) if (e.state == 'proposed' && e.active) e];

  ReviewEntry? get currentEntry => _byId(currentEntryId);
  ReviewEntry? get selectedEntry => _byId(selectedEntryId);

  /// An explicit focus wins; otherwise whatever the playhead is on.
  ReviewEntry? get cardEntry => selectedEntry ?? currentEntry;

  ReviewEntry? _byId(String? id) {
    if (id == null) return null;
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Who the loop waits on (the three-actor banner). Null in the calm state.
  WaitingOn? get waitingOn {
    final p = phase;
    if (p == null) return null;
    return switch (p) {
      ReviewPhase.notesIn =>
        pendingGates.isEmpty ? WaitingOn.cyan : WaitingOn.you,
      ReviewPhase.conforming || ReviewPhase.finishing => WaitingOn.cyan,
      _ => WaitingOn.producer,
    };
  }

  AssetVersion? get selectedVersion {
    for (final v in versions) {
      if (v.number == selectedVersionNumber) return v;
    }
    return null;
  }

  /// What the hero should be playing. Null in the calm state.
  String? get selectedVersionPath => selectedVersion?.path;

  /// The delivery is a PRODUCT action, and it is only offered once the board's
  /// review lane HAS a delivered version to render from.
  bool get canProduceMaster => version > 0;
}

/// The player's controller. Owns the ledger read, the confirm gate, the version
/// head and the delivery — nothing else.
class ReviewPlayerController extends StateNotifier<ReviewPlayerState> {
  ReviewPlayerController({
    required this.backend,
    required this.boardId,
    String? assetHash,
  }) : super(ReviewPlayerState(assetHash: assetHash));

  final CyanBackend backend;
  final String boardId;

  /// Rendering is a pure function of the entry — the view asks, never branches.
  final ReviewEntryRenderRegistry registry = ReviewEntryRenderRegistry.standard;

  /// The engine's proxy ⇄ master map for the branch head. Null = identity.
  ConformFrameMap? _conformMap;

  /// The human's explicit non-newest choice; null = follow the newest.
  int? _pinnedVersionNumber;

  ReviewPlayerState get current => state;

  // ---- load ----------------------------------------------------------------

  /// Pull the change list + review state through the seam. Any unusable
  /// response (a lane with no review state, a busy store, an engine that
  /// answered nothing) lands in the empty calm state.
  Future<void> load() async {
    final cmd = <String, dynamic>{'op': 'list', 'board_id': boardId};
    final hash = state.assetHash;
    if (hash != null && hash.isNotEmpty) cmd['asset_hash'] = hash;
    ChangelistCommandResult reply;
    try {
      reply = await backend.changelistCommand(cmd);
    } catch (e) {
      state = state.copyWith(hydrated: true, lastError: _describe(e));
      return;
    }
    if (!_applyEnvelope(reply.fields)) {
      // The calm state: nothing to show and nothing to act on.
      state = ReviewPlayerState(
        hydrated: true,
        assetHash: state.assetHash,
        playheadFrame: state.playheadFrame,
        fps: state.fps,
        produceStatus: state.produceStatus,
        lastDeliveryPath: state.lastDeliveryPath,
        lastError: reply.error,
      );
      _conformMap = null;
      _pinnedVersionNumber = null;
      return;
    }
    await _fetchConformMap();
    await _refreshVersions();
  }

  /// Apply a `{review_state, entries, …}` envelope. False when it carries no
  /// review state — the caller decides the fallback.
  bool _applyEnvelope(Map<String, dynamic> fields) {
    final rs = fields['review_state'];
    if (rs is! Map<String, dynamic>) return false;

    final rows = <ReviewEntry>[
      for (final e in (fields['entries'] as List? ?? const []))
        if (e is Map<String, dynamic>) ReviewEntry.fromJson(e),
    ]..sort((a, b) => a.tcIn != b.tcIn
        ? a.tcIn.compareTo(b.tcIn)
        : a.seq.compareTo(b.seq));

    final assetHash = (fields['asset_hash'] as String?)?.isNotEmpty == true
        ? fields['asset_hash'] as String
        : state.assetHash;
    final tenantId = (fields['tenant_id'] as String?)?.isNotEmpty == true
        ? fields['tenant_id'] as String
        : state.tenantId;

    var selected = state.selectedEntryId;
    if (selected != null && !rows.any((e) => e.id == selected)) selected = null;
    // Found live in Swift: with nothing explicitly focused, PRESELECT the open
    // proposal — the card the confirm gate exists for. A reviewer's point note
    // at the default playhead is "narrower" than a whole-clip trim and would
    // otherwise hide the Approve card entirely.
    if (selected == null) {
      for (final e in rows) {
        if (e.kind == 'op' && e.state == 'proposed') {
          selected = e.id;
          break;
        }
      }
    }

    state = state.copyWith(
      hydrated: true,
      entries: rows,
      phase: ReviewPhase.parse(rs['state'] as String?),
      clearPhase: ReviewPhase.parse(rs['state'] as String?) == null,
      round: (rs['round'] as num?)?.toInt() ?? state.round,
      branch: fields['branch'] as String? ?? state.branch,
      version: (fields['version'] as num?)?.toInt() ?? state.version,
      assetHash: assetHash,
      tenantId: tenantId,
      selectedEntryId: selected,
      clearSelected: selected == null,
      clearError: true,
    );
    // Re-derive the playhead card against the fresh entry set.
    _setCurrentEntry();
    return true;
  }

  // ---- versions ------------------------------------------------------------

  /// Resolve the asset's playable versions through the seam:
  ///   rung 1 — `review_media_info` (the asset registry's truth: the registered
  ///            master, the newest conform-derived proxy, the ledger head);
  ///   rung 2 — `boardVideoMedia` (staged master + newest run-derived proxy),
  ///            with the head from the change-list envelope.
  /// Neither resolving leaves the list empty — the face keeps what it has.
  Future<void> _refreshVersions() async {
    var head = state.version;
    String? master;
    String? proxy;
    String? preview;

    try {
      // The v1 leg's playable fallback: the engine's preview render of the
      // anchor, consulted whichever rung answers, so a camera original never
      // dead-ends the version flip.
      final media = await backend.boardVideoMedia(boardId);
      preview = media.previewPath;
      final info = await backend
          .reviewCommand({'op': 'review_media_info', 'board_id': boardId});
      if (info.ok &&
          (info.fields['master_path'] != null ||
              info.fields['derived_proxy_path'] != null)) {
        head = (info.fields['version'] as num?)?.toInt() ?? head;
        master = info.fields['master_path'] as String?;
        proxy = info.fields['derived_proxy_path'] as String?;
      } else {
        master = media.masterUri;
        proxy = media.proxyPath;
      }
    } catch (e) {
      state = state.copyWith(lastError: _describe(e));
      return;
    }
    applyVersions(
        head: head, masterPath: master, proxyPath: proxy, previewPath: preview);
  }

  /// The pure derivation: the version options, the auto-advance, the pin and
  /// the v1→v2 indicator.
  ///   head ≥ 2 with a distinct conformed proxy ⇒ [v1 source, vHEAD conformed];
  ///   otherwise the sole playable media is v1 (pre-conform the review proxy IS
  ///   the v1 cut, so it stays preferred).
  void applyVersions({
    required int head,
    String? masterPath,
    String? proxyPath,
    String? previewPath,
  }) {
    final master = (masterPath?.isEmpty ?? true) ? null : masterPath;
    final proxy = (proxyPath?.isEmpty ?? true) ? null : proxyPath;
    final preview = (previewPath?.isEmpty ?? true) ? null : previewPath;

    // A camera-original master (MXF / BRAW / R3D) is un-decodable, and mounting
    // it dead-ends the v1 leg of the before/after flip. The engine's
    // frame-mapped preview stands in; the ledger stays master-native either way.
    final v1Playable = master == null
        ? preview
        : (_undecodable(master) ? (preview ?? master) : master);

    final list = <AssetVersion>[];
    if (head >= 2 && proxy != null && proxy != master) {
      if (v1Playable != null) list.add(AssetVersion(1, v1Playable));
      list.add(AssetVersion(head, proxy));
    } else if (head >= 1 && (proxy ?? v1Playable) != null) {
      list.add(AssetVersion(1, proxy ?? v1Playable));
    }

    final previousNewest =
        state.versions.isEmpty ? 0 : state.versions.last.number;
    if (list.isEmpty) {
      state = state.copyWith(
          versions: const [], selectedVersionNumber: 0, clearAdvance: true);
      _pinnedVersionNumber = null;
      return;
    }
    final newest = list.last.number;
    // Only an OBSERVED arrival raises the indicator — a player that opens on an
    // already-conformed v2 just shows v2, never a stale banner.
    final advance = (newest > previousNewest && previousNewest > 0)
        ? VersionAdvance(previousNewest, newest)
        : null;
    final pin = _pinnedVersionNumber;
    final keepsPin =
        pin != null && pin != newest && list.any((v) => v.number == pin);
    if (!keepsPin) _pinnedVersionNumber = null;
    state = state.copyWith(
      versions: list,
      selectedVersionNumber: keepsPin ? pin : newest,
      versionAdvance: advance,
      clearAdvance: advance == null,
    );
  }

  /// Containers the player cannot decode — the camera originals.
  static bool _undecodable(String path) {
    final lower = path.toLowerCase();
    return const ['.mxf', '.braw', '.r3d', '.ari', '.arri']
        .any(lower.endsWith);
  }

  /// An explicit pick from the version selector. Picking the newest resumes
  /// auto-advance; picking an older cut pins it. Either way the human has
  /// acknowledged the arrival, so the indicator clears.
  void selectVersion(int number) {
    if (!state.versions.any((v) => v.number == number)) return;
    _pinnedVersionNumber =
        number == state.versions.last.number ? null : number;
    state = state.copyWith(
        selectedVersionNumber: number, clearAdvance: true);
  }

  // ---- the conform map -----------------------------------------------------

  /// Pull the branch head's proxy ⇄ master map. An identity map is stored as
  /// null so every call site can use the cheap fallback; a failed fetch
  /// degrades to identity — markers stay visible, never crash, never vanish.
  Future<void> _fetchConformMap() async {
    try {
      final cmd = <String, dynamic>{'op': 'conform_map', 'board_id': boardId};
      final hash = state.assetHash;
      if (hash != null && hash.isNotEmpty) cmd['asset_hash'] = hash;
      final reply = await backend.changelistCommand(cmd);
      final segments = [
        for (final s in (reply.fields['segments'] as List? ?? const []))
          if (s is Map<String, dynamic>) ConformMapSegment.fromJson(s),
      ];
      if (segments.isEmpty) {
        _conformMap = null;
        return;
      }
      final map = ConformFrameMap(segments);
      _conformMap = map.isIdentity ? null : map;
    } catch (_) {
      _conformMap = null;
    }
  }

  /// The map that applies to the version ON SCREEN. The engine's map belongs to
  /// the branch-head proxy, so a hero showing an OLDER cut is in master frames
  /// already and the map degrades to identity there.
  ConformFrameMap? get _effectiveConformMap {
    if (state.versions.isNotEmpty &&
        state.selectedVersionNumber > 0 &&
        state.selectedVersionNumber < state.versions.last.number) {
      return null;
    }
    return _conformMap;
  }

  /// The frame to DRAW/SEEK for an entry anchored at master [frame] while the
  /// hero shows the conformed proxy. A master frame the cut removed lands on
  /// the first surviving proxy frame after it — the closest true context,
  /// never a silent mis-pin.
  int displayFrameForMaster(int frame) {
    final map = _effectiveConformMap;
    if (map == null) return frame;
    final mapped = map.masterToProxy(frame);
    if (mapped != null) return mapped;
    ConformMapSegment? next;
    for (final s in map.segments) {
      final ms = s.masterStart;
      if (ms == null || ms <= frame) continue;
      if (next == null || ms < (next.masterStart ?? 0)) next = s;
    }
    return next?.proxyStart ?? frame;
  }

  /// The MASTER frame for a proxy/display frame — the capture and before-sync
  /// leg.
  int masterFrameForDisplay(int frame) {
    final map = _effectiveConformMap;
    if (map == null) return frame;
    return map.proxyToMaster(frame) ?? frame;
  }

  // ---- playhead ------------------------------------------------------------

  /// Bind a surface's playhead. The controller only ever sees frame indices.
  void setPlayhead(int frame) {
    state = state.copyWith(playheadFrame: frame);
    _setCurrentEntry();
  }

  void adoptFrameRate(double fps) {
    if (fps <= 0 || fps == state.fps) return;
    state = state.copyWith(fps: fps);
  }

  void _setCurrentEntry() {
    final hit = entryAt(state.playheadFrame);
    state = state.copyWith(
        currentEntryId: hit?.id, clearCurrent: hit == null);
  }

  /// The entry the playhead is on: containment in [tc_in, tc_out] (a point
  /// matches exactly at its frame); the smallest span wins, ties go to the
  /// lower seq.
  ReviewEntry? entryAt(int frame) {
    ReviewEntry? best;
    for (final e in state.entries) {
      final display = displayFrameForMaster(e.tcIn);
      final displayEnd = displayFrameForMaster(e.tcEnd);
      if (frame < display || frame > displayEnd) continue;
      if (best == null) {
        best = e;
        continue;
      }
      final span = displayEnd - display;
      final bestSpan =
          displayFrameForMaster(best.tcEnd) - displayFrameForMaster(best.tcIn);
      if (span < bestSpan || (span == bestSpan && e.seq < best.seq)) best = e;
    }
    return best;
  }

  // ---- focus ---------------------------------------------------------------

  void focus(String? entryId) {
    state = state.copyWith(
        selectedEntryId: entryId,
        clearSelected: entryId == null,
        clearEditing: true);
  }

  void beginEdit(String entryId) {
    state = state.copyWith(selectedEntryId: entryId, editingEntryId: entryId);
  }

  void cancelEdit() => state = state.copyWith(clearEditing: true);

  // ---- the confirm gate (HUMAN, editable) ----------------------------------

  /// Approve as-is, then step the focus to the next unresolved gate.
  Future<void> approve(ReviewEntry entry) async {
    await _confirm(entry.id, 'approve', const {});
    _advanceSelection(entry);
  }

  /// Reject, then step the focus to the next unresolved gate.
  Future<void> reject(ReviewEntry entry) async {
    await _confirm(entry.id, 'reject', const {});
    _advanceSelection(entry);
  }

  /// Approve WITH an edit — the nudged tc / params ride inside the confirm op.
  Future<void> approveEdited(
    ReviewEntry entry, {
    int? tcIn,
    int? tcOut,
    Map<String, dynamic>? params,
  }) async {
    await _confirm(entry.id, 'edit', {
      if (tcIn != null) 'tc_in': tcIn,
      if (tcOut != null) 'tc_out': tcOut,
      if (params != null) 'params': params,
    });
    state = state.copyWith(clearEditing: true);
    _advanceSelection(entry);
  }

  Future<void> _confirm(
      String entryId, String decision, Map<String, dynamic> edits) async {
    final cmd = <String, dynamic>{
      'op': 'confirm',
      'board_id': boardId,
      'entry_id': entryId,
      'decision': decision,
      ...edits,
    };
    ReviewCommandResult reply;
    try {
      reply = await backend.reviewCommand(cmd);
    } catch (e) {
      state = state.copyWith(lastError: _describe(e));
      return;
    }
    if (!reply.ok) {
      state = state.copyWith(lastError: reply.error);
      return;
    }
    // The engine answers the confirm with the whole lane, so the decision and
    // the ledger it produced arrive together — no second read to race.
    if (!_applyEnvelope(reply.fields)) {
      state = state.copyWith(lastError: 'Confirm failed');
    }
  }

  /// After deciding a gate, focus the next unresolved one (tc order, wrapping)
  /// so the review flows gate-to-gate without hunting.
  void _advanceSelection(ReviewEntry decided) {
    final remaining =
        [for (final e in state.pendingGates) if (e.id != decided.id) e];
    ReviewEntry? next;
    for (final e in remaining) {
      if (e.tcIn > decided.tcIn ||
          (e.tcIn == decided.tcIn && e.seq > decided.seq)) {
        next = e;
        break;
      }
    }
    next ??= remaining.isEmpty ? null : remaining.first;
    state = state.copyWith(
        selectedEntryId: next?.id, clearSelected: next == null);
  }

  // ---- produce master ------------------------------------------------------

  /// Export the conformed, graded master through the ENGINE's own delivery lane
  /// (`produce_master`, board-keyed — the engine resolves the frozen version
  /// from this board's review lane). Minutes-scale: the status narrates.
  Future<void> produceMaster() async {
    if (state.version <= 0) {
      state = state.copyWith(
          produceStatus:
              'produce master: no delivered version yet — confirm and conform first');
      return;
    }
    state = state.copyWith(produceStatus: 'producing master…');
    IngestCommandResult reply;
    try {
      reply = await backend.ingestCommand({
        'op': 'produce_master',
        'board_id': boardId,
        if (state.selectedVersionNumber > 0)
          'version': state.selectedVersionNumber,
      });
    } catch (e) {
      state = state.copyWith(
          produceStatus: 'produce master: no answer from the engine',
          lastError: _describe(e));
      return;
    }
    if (!reply.ok) {
      state = state.copyWith(produceStatus: 'produce master failed: ${reply.error}');
      return;
    }
    final path = reply.fields['output_path'] as String?;
    if (path == null || path.isEmpty) {
      state = state.copyWith(
          produceStatus: 'produce master: engine returned no output_path');
      return;
    }
    state = state.copyWith(
        lastDeliveryPath: path, produceStatus: 'master: $path');
  }

  // ---- Keystone checkout (undo / redo the version head) --------------------

  /// Step the branch head back one version — a version-pointer move the engine
  /// audits and reconciles.
  Future<void> undoCut() => _stepVersion('undo');

  /// Step the branch head forward again.
  Future<void> redoCut() => _stepVersion('redo');

  Future<void> _stepVersion(String verb) async {
    // A click can beat the async envelope: resolve the ledger FIRST, then step
    // — never silently drop the verb (the engine would refuse "" anchors).
    if ((state.tenantId ?? '').isEmpty || (state.assetHash ?? '').isEmpty) {
      await load();
    }
    final tenant = state.tenantId ?? '';
    final asset = state.assetHash ?? '';
    if (tenant.isEmpty || asset.isEmpty) return;
    try {
      final reply = await backend.changelistCommand({
        'op': verb,
        'tenant_id': tenant,
        'asset_hash': asset,
        'branch': state.branch,
        'by': 'review-player',
      });
      // "nothing to undo" is an answer, not a fault — it is shown, and the
      // reload below still re-reads the truth.
      if (!reply.ok) state = state.copyWith(lastError: reply.error);
    } catch (e) {
      state = state.copyWith(lastError: _describe(e));
    }
    // Whatever the verb did, the ledger is the truth — re-read it so every
    // mark and every version chrome tracks it.
    await load();
  }

  static String _describe(Object e) {
    final text = e.toString().trim();
    for (final p in const ['Exception: ', 'Bad state: ', 'StateError: ']) {
      if (text.startsWith(p)) return text.substring(p.length);
    }
    return text;
  }
}
