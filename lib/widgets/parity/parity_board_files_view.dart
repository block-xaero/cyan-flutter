// widgets/parity/parity_board_files_view.dart
//
// PARITY port of the SwiftUI `BoardFilesView` (Views/BoardFilesView.swift): the
// board's FILES surface — the files attached to this board, with a clear way to
// pull a peer's file down to this device and watch the transfer while it runs.
//
// Driven ENTIRELY through the `CyanBackend` seam (via `boardFilesProvider`,
// which reads `filesForBoard` / `fileStatus` and writes `requestFileDownload` /
// `deleteFile`). This widget never touches `CyanFFI` directly — the parity rule.
//
// A file row is one of three things, and the row says WHICH:
//   • on this device      — the bytes are here (green doc)
//   • remote              — the row synced, the bytes did not; downloadable
//   • downloading         — bytes are moving; the row reports the percent
//
// That distinction is the whole point of the face: in the 3-face board model a
// board's files had no home, and "is this file actually here?" had no answer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/board_files_controller.dart';
import '../../theme/monokai_theme.dart';

class ParityBoardFilesView extends ConsumerWidget {
  /// The board whose files to list. Files are board-scoped: another board's
  /// files are a different set, never a filter of this one.
  final String boardId;

  /// Dismissing the panel (it opens as a sheet off the board header). Null
  /// renders no close affordance — the panel is embedded rather than presented.
  final VoidCallback? onClose;

  const ParityBoardFilesView({
    super.key,
    this.boardId = 'b-eng-1',
    this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(boardFilesProvider(boardId));
    final controller = ref.read(boardFilesProvider(boardId).notifier);

    return Material(
      color: MonokaiTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(count: files.rows.length, onClose: onClose),
          const Divider(height: 1, color: MonokaiTheme.divider),
          Expanded(
            child: switch (files) {
              BoardFilesState(loading: true) => const Center(
                  child: CircularProgressIndicator(color: MonokaiTheme.cyan),
                ),
              BoardFilesState(error: final String e) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(e,
                        textAlign: TextAlign.center,
                        style: MonokaiTheme.bodyMedium
                            .copyWith(color: MonokaiTheme.red)),
                  ),
                ),
              BoardFilesState(isEmpty: true) => const _Empty(),
              _ => ListView(
                  padding: const EdgeInsets.all(10),
                  children: [
                    for (final row in files.rows)
                      _FileRow(
                        row: row,
                        onDownload: () => controller.download(row.id),
                        onDelete: () => controller.delete(row.id),
                      ),
                  ],
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int count;
  final VoidCallback? onClose;
  const _Header({required this.count, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      color: MonokaiTheme.surface,
      child: Row(
        children: [
          const Icon(Icons.attach_file, size: 15, color: MonokaiTheme.cyan),
          const SizedBox(width: 10),
          Text('Files', style: MonokaiTheme.titleSmall),
          const SizedBox(width: 8),
          if (count > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: MonokaiTheme.selection,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$count', style: MonokaiTheme.labelSmall),
            ),
          const Spacer(),
          if (onClose != null)
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 14),
              color: MonokaiTheme.comment,
              splashRadius: 16,
              visualDensity: VisualDensity.compact,
              tooltip: 'Close',
            ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  final BoardFileRow row;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const _FileRow({
    required this.row,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final here = row.isDownloaded;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                here ? Icons.description : Icons.cloud_download_outlined,
                size: 14,
                color: here ? MonokaiTheme.green : MonokaiTheme.comment,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.name,
                        style: MonokaiTheme.bodySmall.copyWith(
                            color: MonokaiTheme.foreground,
                            fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 1),
                    Text(_subtitle, style: MonokaiTheme.labelSmall),
                  ],
                ),
              ),
              // While a transfer runs the percent IS the affordance — there is
              // nothing to press, and the row says how far along it is.
              if (row.isDownloading)
                Text('${row.percent}%',
                    style: MonokaiTheme.labelSmall
                        .copyWith(color: MonokaiTheme.cyan))
              else if (!here)
                IconButton(
                  onPressed: onDownload,
                  icon: const Icon(Icons.arrow_circle_down, size: 16),
                  color: MonokaiTheme.cyan,
                  splashRadius: 16,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Download to this device',
                ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 14),
                color: MonokaiTheme.comment,
                splashRadius: 16,
                visualDensity: VisualDensity.compact,
                tooltip: 'Delete file',
              ),
            ],
          ),
          if (row.isDownloading) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: row.progress,
                minHeight: 3,
                backgroundColor: MonokaiTheme.selection,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(MonokaiTheme.cyan),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The row's second line: size, plus where the bytes stand. A remote file
  /// says so — "synced but not here" is the state the face exists to show.
  String get _subtitle {
    final size = fileSizeLabel(row.file.size);
    if (row.isDownloading) return '$size · downloading ${row.percent}%';
    if (row.hasFailed) return '$size · download failed — retry';
    if (row.isDownloaded) return '$size · on this device';
    return '$size · on the mesh';
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inbox_outlined,
              size: 34, color: MonokaiTheme.border),
          const SizedBox(height: 10),
          Text('No files on this board yet',
              style: MonokaiTheme.bodyMedium
                  .copyWith(color: MonokaiTheme.comment)),
          const SizedBox(height: 4),
          Text('Drop one into the board chat to attach it.',
              style: MonokaiTheme.labelSmall),
        ],
      ),
    );
  }
}
