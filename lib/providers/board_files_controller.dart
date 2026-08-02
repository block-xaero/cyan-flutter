// providers/board_files_controller.dart
//
// The board's FILES surface, ported from `BoardFilesViewModel`
// (ViewModels/BoardFilesViewModel.swift). Lists the files attached to a board,
// fetches a remote one to this device, and reports the transfer while it runs.
// Every read and write goes through the `CyanBackend` seam (`filesForBoard` /
// `requestFileDownload` / `fileStatus` / `deleteFile`), so the face is Tier-1
// drivable against FakeCyanBackend with no dylib and no mesh.
//
// Three invariants carried over from the Swift view-model:
//
//   • BOARD SCOPE — files are listed for this board only. The Swift VM drops a
//     `.fileReceived` delta whose board id is not its own ("no cross-board
//     bleed"); the same rule is why the listing is scoped rather than filtered
//     after the fact.
//   • DEDUP by content hash AND id (Swift B3), so a file the mesh gossips twice
//     — once by row, once by hash — never renders twice.
//   • The engine is the truth — a completed transfer ends in a re-read of the
//     listing rather than the row being patched locally.
//
// The transfer is POLLED, not streamed: `cyan_get_file_status` is a read, and
// the engine has no transfer event. The poll chain STOPS as soon as the file is
// no longer in flight — it is not a periodic timer, so a face that is settling
// (in a test or in a pumped frame) always reaches quiescence.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/cyan_backend.dart';
import '../ffi/parity_models.dart';
import 'cyan_backend_provider.dart';

/// One row of the board's files list: the file, plus the transfer state when
/// this device has asked for its bytes.
@immutable
class BoardFileRow {
  final CyanFile file;

  /// The live transfer, present only while this row is downloading or once it
  /// has finished in this session. Null means "never asked" — the row reads its
  /// state off [CyanFile.isDownloaded] alone.
  final FileTransfer? transfer;

  const BoardFileRow({required this.file, this.transfer});

  String get id => file.id;
  String get name => file.name;

  /// True when the bytes are on this device — either the listing already said
  /// so, or a transfer this session finished.
  bool get isDownloaded => file.isDownloaded || (transfer?.isLocal ?? false);

  /// True while bytes are moving. Only then is [percent] meaningful.
  bool get isDownloading => transfer?.isInFlight ?? false;

  /// The transfer as a whole percent, for the row's progress readout.
  int get percent => transfer?.percent ?? 0;

  /// The 0–1 fraction a progress bar draws.
  double get progress => transfer?.progress ?? 0;

  /// True when the transfer stopped short. The row stays remote and is
  /// retryable — a failure is not a missing file.
  bool get hasFailed => transfer?.state == FileTransferState.failed;

  BoardFileRow copyWith({CyanFile? file, FileTransfer? transfer}) =>
      BoardFileRow(file: file ?? this.file, transfer: transfer ?? this.transfer);
}

@immutable
class BoardFilesState {
  final bool loading;

  /// The listing could not be read — the face says so rather than showing the
  /// empty state, which would read as "this board has no files".
  final String? error;

  final List<BoardFileRow> rows;

  const BoardFilesState({
    this.loading = true,
    this.error,
    this.rows = const [],
  });

  BoardFilesState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    List<BoardFileRow>? rows,
  }) {
    return BoardFilesState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      rows: rows ?? this.rows,
    );
  }

  bool get isEmpty => rows.isEmpty;

  BoardFileRow? byId(String id) {
    for (final r in rows) {
      if (r.id == id) return r;
    }
    return null;
  }
}

/// The files for one board. Keyed by board id — a file is attached to its
/// board, so another board's list is a different set.
final boardFilesProvider = StateNotifierProvider.autoDispose
    .family<BoardFilesController, BoardFilesState, String>((ref, boardId) {
  final controller = BoardFilesController(
    backend: ref.watch(cyanBackendProvider),
    boardId: boardId,
  );
  controller.load();
  return controller;
});

class BoardFilesController extends StateNotifier<BoardFilesState> {
  final CyanBackend _backend;
  final String boardId;

  /// How often a transfer in flight is re-read. The engine has no transfer
  /// event, so progress is polled; short enough to animate, long enough not to
  /// hammer the seam.
  static const Duration pollInterval = Duration(milliseconds: 120);

  /// A guard against a transfer that never resolves holding the poll chain
  /// open forever — the chain gives up and leaves the row remote (retryable)
  /// rather than spinning.
  static const int maxPolls = 200;

  BoardFilesController({
    required CyanBackend backend,
    required this.boardId,
  })  : _backend = backend,
        super(const BoardFilesState());

  /// Read the board's files off the engine, de-duped. This is also the RELOAD a
  /// finished transfer or a delete ends with.
  Future<void> load() async {
    try {
      final files = await _backend.filesForBoard(boardId);
      if (!mounted) return;
      // Transfers observed this session survive the re-read, so a row that just
      // finished does not flicker back to "remote" before the listing catches
      // up.
      final rows = [
        for (final f in _deduped(files))
          BoardFileRow(file: f, transfer: state.byId(f.id)?.transfer),
      ];
      state = state.copyWith(loading: false, clearError: true, rows: rows);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        error: "Could not read this board's files: $e",
      );
    }
  }

  /// Swift B3: a file renders once. The mesh can gossip the same bytes under a
  /// second row, so the content HASH dedupes as well as the id.
  static List<CyanFile> _deduped(List<CyanFile> files) {
    final seen = <String>{};
    final out = <CyanFile>[];
    for (final f in files) {
      if (!seen.add('i:${f.id}')) continue;
      if (f.hash.isNotEmpty && !seen.add('h:${f.hash}')) continue;
      out.add(f);
    }
    return out;
  }

  /// Fetch a remote file's bytes to this device, reporting the transfer as it
  /// runs. Returns whether the engine ACCEPTED the request — not whether the
  /// bytes arrived, which is what the polled progress reports.
  ///
  /// A file that is already here is not re-fetched: the request is accepted and
  /// there is simply nothing to transfer.
  Future<bool> download(String fileId) async {
    final row = state.byId(fileId);
    if (row == null || row.isDownloaded || row.isDownloading) return false;

    bool accepted;
    try {
      accepted = await _backend.requestFileDownload(fileId);
    } catch (e) {
      if (mounted) state = state.copyWith(error: 'Download failed: $e');
      return false;
    }
    if (!accepted) {
      if (mounted) {
        state = state.copyWith(error: 'The engine refused that download.');
      }
      return false;
    }
    if (!mounted) return true;

    // Show the transfer as started BEFORE the first poll, so the row reports
    // "downloading" on the very next frame rather than staying remote until a
    // status read lands.
    _setTransfer(fileId, const FileTransfer(state: FileTransferState.downloading));
    await _pollUntilSettled(fileId);
    return true;
  }

  /// Re-read one file's transfer until it is no longer in flight. Terminates on
  /// local / failed / unknown / a vanished file — it is a chain, not a periodic
  /// timer, so it always reaches an end.
  Future<void> _pollUntilSettled(String fileId) async {
    for (var i = 0; i < maxPolls; i++) {
      await Future<void>.delayed(pollInterval);
      if (!mounted) return;

      FileTransfer? status;
      try {
        status = await _backend.fileStatus(fileId);
      } catch (e) {
        if (mounted) state = state.copyWith(error: 'Download failed: $e');
        return;
      }
      if (!mounted) return;

      if (status == null) {
        // The engine no longer knows the id — the file went away under us, so
        // the listing is what is stale, not the transfer.
        await load();
        return;
      }

      _setTransfer(fileId, status);
      if (!status.isInFlight) {
        // Settled. Re-read so the row's file carries the local path the engine
        // recorded rather than one inferred here.
        await load();
        return;
      }
    }
  }

  void _setTransfer(String fileId, FileTransfer transfer) {
    if (!mounted) return;
    state = state.copyWith(rows: [
      for (final r in state.rows)
        if (r.id == fileId) r.copyWith(transfer: transfer) else r,
    ]);
  }

  /// Soft-delete a board file. The engine gossips a tombstone, so the listing
  /// is re-read rather than the row being spliced out locally.
  Future<bool> delete(String fileId) async {
    try {
      await _backend.deleteFile(fileId);
    } catch (e) {
      if (mounted) state = state.copyWith(error: 'Failed to delete: $e');
      return false;
    }
    await load();
    return true;
  }
}

/// A file size as the macOS row renders it (`ByteCountFormatter`, file style —
/// decimal units).
String fileSizeLabel(int bytes) {
  if (bytes < 1000) return '$bytes bytes';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1000;
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  // One decimal below 100, none above — what the formatter shows.
  final text =
      value >= 100 ? value.round().toString() : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}
