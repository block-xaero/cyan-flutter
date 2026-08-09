// widgets/parity/parity_board_container.dart
//
// PARITY face_board_container — the board CUBE: one board, three faces, and the
// selector that turns it.
//
// SwiftUI reference (read-only):
//   Views/BoardContainerViewNew.swift   — the container, its header, the face
//                                         switch + `switchToFace` persistence
//   Views/BoardFace.swift               — `BoardFaceSelector` / `FaceTab`
//   CyanTests/BoardFacesVMTests.swift   — the face set, canvas absent
//
// The container OWNS the face and the board, and nothing else: each face is the
// real parity surface already ported (`ParityWorkflowView` / `ParityNotesView` /
// `ParityDashboardView`), mounted on the SAME board id. Turning the cube never
// changes which board is open — the selection is the container's, the face is a
// view of it.
//
// Persistence goes through the `CyanBackend` seam's board-mode pair, and it is
// ordered the way Swift orders it: the engine accepts the write FIRST, the tab
// moves second. A refused write leaves the operator where they were rather than
// showing them a face the board is not on.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../models/board_face.dart';
import '../../providers/board_face_provider.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';
import 'parity_dashboard_view.dart';
import 'parity_notes_view.dart';
import 'parity_review_player.dart';
import 'parity_workflow_view.dart';

/// ⌘1 · ⌘2 · ⌘3 — one chord per face, in [kStandardBoardFaces] order (Swift
/// Tier 3.5 face shortcuts).
/// Which modifier is THIS platform's accelerator.
///
/// Swift binds the face chords to Command. Carrying `meta: true` straight
/// across put them on the WINDOWS KEY here — a chord no Windows operator would
/// ever try, and one the OS partly owns (Win+1..9 activates taskbar items), so
/// the face shortcuts were both undiscoverable and fighting the shell.
///
/// Read once at startup rather than per build: the platform does not change,
/// and `defaultTargetPlatform` is not free.
final bool _kAcceleratorIsMeta = defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

const List<LogicalKeyboardKey> _faceDigits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
];

class ParityBoardContainer extends ConsumerStatefulWidget {
  /// The board this container is standing on. Every face is mounted on it.
  final String boardId;

  /// Leaving the board — Swift's `board.back` button, which posts
  /// `.whiteboardNavigateBack` to whoever opened the board. No callback means
  /// no back affordance (a container that is already the whole surface).
  final VoidCallback? onBack;

  /// The face actually mounted changed — i.e. the engine accepted the write.
  final void Function(BoardFace)? onFaceChanged;

  const ParityBoardContainer({
    super.key,
    required this.boardId,
    this.onBack,
    this.onFaceChanged,
  });

  @override
  ConsumerState<ParityBoardContainer> createState() =>
      _ParityBoardContainerState();
}

class _ParityBoardContainerState extends ConsumerState<ParityBoardContainer> {
  /// The face the operator turned to during THIS open, once they have. Null
  /// means the board is still on the face it opened to.
  BoardFace? _switched;

  @override
  void didUpdateWidget(ParityBoardContainer old) {
    super.didUpdateWidget(old);
    // A different board is a different cube: its own saved face resolves again
    // rather than inheriting the face the previous board was turned to.
    if (old.boardId != widget.boardId) _switched = null;
  }

  Future<void> _switchTo(BoardFace face, BoardFace current) async {
    if (face == current) return;
    final accepted = await ref
        .read(cyanBackendProvider)
        .setBoardActiveFace(widget.boardId, face.rawValue);
    // Swift publishes the switch only after `setActiveFace` returns true — a
    // refused write must not paint a face the board is not actually on.
    if (!accepted || !mounted) return;
    setState(() => _switched = face);
    widget.onFaceChanged?.call(face);
  }

  /// The faces THIS board offers — Swift `availableFaces`. The standard three,
  /// plus Video only when the board actually resolves a media asset. A Video
  /// tab on a board with no media is a tab onto "No video asset linked", and
  /// the review station is exactly where a dead tab is most expensive.
  List<BoardFace> _availableFaces(BoardVideoMedia? media) => [
        ...kStandardBoardFaces,
        if (media != null &&
            (media.proxyPath != null ||
                media.previewPath != null ||
                media.masterUri != null))
          BoardFace.video,
      ];

  @override
  Widget build(BuildContext context) {
    final opening = ref.watch(boardOpeningFaceProvider(widget.boardId));
    final media = ref.watch(boardVideoMediaProvider(widget.boardId));

    return Material(
      color: MonokaiTheme.background,
      child: opening.when(
        loading: () => const _LoadingBoard(),
        // An unreadable saved face is not a reason to refuse the board: the
        // Swift bridge answers "notebook" when the engine says nothing, so the
        // cube opens on Workflow and stays fully usable.
        error: (_, __) => _cube(BoardFace.workflow, media.valueOrNull),
        data: (resolved) {
          var face = _switched ?? resolved;
          // A board saved on the Video face whose media has since gone lands on
          // Workflow rather than on a face its own selector does not offer.
          if (face == BoardFace.video &&
              !_availableFaces(media.valueOrNull).contains(BoardFace.video)) {
            face = BoardFace.workflow;
          }
          return _cube(face, media.valueOrNull);
        },
      ),
    );
  }

  Widget _cube(BoardFace face, BoardVideoMedia? media) {
    final faces = _availableFaces(media);
    return CallbackShortcuts(
      bindings: {
        // ⌘4 exists only when the Video face does — Swift binds it inside the
        // same `if videoAsset != nil` its tab lives in.
        for (var i = 0; i < faces.length; i++)
          SingleActivator(
            _faceDigits[i],
            meta: _kAcceleratorIsMeta,
            control: !_kAcceleratorIsMeta,
          ): () => _switchTo(faces[i], face),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BoardHeader(
              boardId: widget.boardId,
              face: face,
              faces: faces,
              onBack: widget.onBack,
              onSelectFace: (f) => _switchTo(f, face),
            ),
            const Divider(height: 1, color: MonokaiTheme.divider),
            Expanded(child: _face(face, media)),
          ],
        ),
      ),
    );
  }

  /// The mounted face. Exactly one is built at a time — the same
  /// `switch activeFace` Swift's `faceContent` is.
  Widget _face(BoardFace face, BoardVideoMedia? media) => switch (face) {
        // Deploying follows the board to its Dashboard: once the steps are
        // frozen the operator's next question is what the RUN is doing, not
        // what the editor looks like read-only. Swift lands them the same way.
        BoardFace.workflow => ParityWorkflowView(
            boardId: widget.boardId,
            onDeployed: () => _switchTo(BoardFace.dashboard, face),
          ),
        BoardFace.notes => ParityNotesView(boardId: widget.boardId),
        BoardFace.dashboard => ParityDashboardView(boardId: widget.boardId),
        // The REVIEW STATION — the surface that carries approve/reject, the
        // graphics rail and PRODUCE MASTER, which is the only click path in the
        // app that ends at a delivered master. Both it and `ParityVideoFace`
        // were fully ported and neither had a door.
        //
        // Swift splits these two on `assetUnderReview` — the review player for
        // a board whose asset is under Frame.io review, the plain timecoded
        // player otherwise. `BoardVideoMedia` carries no such flag, so rather
        // than infer one from the paths (which would guess, and guess wrong on
        // exactly the boards that matter) the review station is mounted for
        // every media board and the missing signal is recorded on COORD.md.
        BoardFace.video => ParityReviewPlayerView(boardId: widget.boardId),
      };
}

// ---------------------------------------------------------------------------
// Header: back · board name · the face selector
// ---------------------------------------------------------------------------

class _BoardHeader extends ConsumerWidget {
  final String boardId;
  final BoardFace face;
  final List<BoardFace> faces;
  final VoidCallback? onBack;
  final void Function(BoardFace) onSelectFace;

  const _BoardHeader({
    required this.boardId,
    required this.face,
    required this.faces,
    required this.onBack,
    required this.onSelectFace,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The board's own name, from the tree. Until it arrives (or when the id
    // names no board the tree knows) the header says what it honestly knows:
    // this is a board, and the face selector below still works.
    final name = ref.watch(boardContextProvider(boardId)).maybeWhen(
          data: (b) => b?.board.name,
          orElse: () => null,
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: MonokaiTheme.surface.withValues(alpha: 0.5),
      child: Row(
        children: [
          if (onBack != null)
            _BackButton(onBack: onBack!)
          else
            const SizedBox(width: 4),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              name ?? 'Board',
              key: const ValueKey('board.name'),
              overflow: TextOverflow.ellipsis,
              style: MonokaiTheme.titleSmall,
            ),
          ),
          const Spacer(),
          _FaceSelector(face: face, faces: faces, onSelect: onSelectFace),
          const Spacer(),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onBack;
  const _BackButton({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('board.back'),
      onTap: onBack,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chevron_left, size: 16, color: MonokaiTheme.cyan),
            const SizedBox(width: 4),
            Text('Back',
                style: MonokaiTheme.labelMedium
                    .copyWith(color: MonokaiTheme.cyan)),
          ],
        ),
      ),
    );
  }
}

/// Swift `BoardFaceSelector` — the tab strip. Three tabs, always the same
/// three: there is no canvas or whiteboard face to offer.
class _FaceSelector extends StatelessWidget {
  final BoardFace face;

  /// The faces THIS board offers — the standard three, plus Video when the
  /// board resolves media. Passed in rather than read off the enum: `.values`
  /// would hand every board a Video tab onto an empty player.
  final List<BoardFace> faces;
  final void Function(BoardFace) onSelect;

  const _FaceSelector(
      {required this.face, required this.faces, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MonokaiTheme.border.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < faces.length; i++)
            _FaceTab(
              face: faces[i],
              isSelected: faces[i] == face,
              shortcutDigit: i + 1,
              onTap: () => onSelect(faces[i]),
            ),
        ],
      ),
    );
  }
}

class _FaceTab extends StatelessWidget {
  final BoardFace face;
  final bool isSelected;
  final int shortcutDigit;
  final VoidCallback onTap;

  const _FaceTab({
    required this.face,
    required this.isSelected,
    required this.shortcutDigit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? MonokaiTheme.cyan : MonokaiTheme.textMuted;
    return Tooltip(
      // Swift shows the face's description and names its chord on hover.
      message: '${face.description} · ⌘$shortcutDigit',
      child: GestureDetector(
        key: ValueKey('board.face.${face.rawValue}'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? MonokaiTheme.cyan.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(face.icon, size: 13, color: color),
              const SizedBox(width: 6),
              Text(face.label,
                  style: MonokaiTheme.labelMedium.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingBoard extends StatelessWidget {
  const _LoadingBoard();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: MonokaiTheme.cyan),
    );
  }
}
