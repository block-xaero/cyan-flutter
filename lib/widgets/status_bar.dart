// widgets/status_bar.dart
// Bottom status bar with sync progress, peer count, breadcrumb, and transfers

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/selection_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// STATUS BAR PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

final statusBarProvider = StateNotifierProvider<StatusBarNotifier, StatusBarData>((ref) {
  return StatusBarNotifier();
});

class StatusBarData {
  final int objectCount;
  final int peerCount;
  final SyncActivity syncActivity;
  final double syncProgress;
  final List<FileTransferInfo> activeTransfers;
  final bool isNetworkConnected;

  const StatusBarData({
    this.objectCount = 0,
    this.peerCount = 0,
    this.syncActivity = const SyncActivityIdle(),
    this.syncProgress = 0.0,
    this.activeTransfers = const [],
    this.isNetworkConnected = true,
  });

  StatusBarData copyWith({
    int? objectCount,
    int? peerCount,
    SyncActivity? syncActivity,
    double? syncProgress,
    List<FileTransferInfo>? activeTransfers,
    bool? isNetworkConnected,
  }) {
    return StatusBarData(
      objectCount: objectCount ?? this.objectCount,
      peerCount: peerCount ?? this.peerCount,
      syncActivity: syncActivity ?? this.syncActivity,
      syncProgress: syncProgress ?? this.syncProgress,
      activeTransfers: activeTransfers ?? this.activeTransfers,
      isNetworkConnected: isNetworkConnected ?? this.isNetworkConnected,
    );
  }
}

class StatusBarNotifier extends StateNotifier<StatusBarData> {
  StatusBarNotifier() : super(const StatusBarData()) {
    _startPolling();
  }

  void _startPolling() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        // Simulate FFI polling - replace with actual FFI calls
        state = state.copyWith(
          objectCount: state.objectCount + 1,
          peerCount: 3,
        );
        _startPolling();
      }
    });
  }

  void beginSync(String description) {
    state = state.copyWith(
      syncActivity: SyncActivitySyncing(description),
      syncProgress: 0.1,
    );
  }

  void updateSyncProgress(double progress) {
    state = state.copyWith(syncProgress: progress);
  }

  void endSync() {
    state = state.copyWith(
      syncActivity: const SyncActivityIdle(),
      syncProgress: 0.0,
    );
  }

  void addTransfer(FileTransferInfo transfer) {
    state = state.copyWith(
      activeTransfers: [...state.activeTransfers, transfer],
    );
  }

  void updateTransferProgress(String id, double progress) {
    final updated = state.activeTransfers.map((t) {
      if (t.id == id) return t.copyWith(progress: progress);
      return t;
    }).toList();
    state = state.copyWith(activeTransfers: updated);
  }

  void removeTransfer(String id) {
    state = state.copyWith(
      activeTransfers: state.activeTransfers.where((t) => t.id != id).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SYNC ACTIVITY TYPES
// ═══════════════════════════════════════════════════════════════════════════

abstract class SyncActivity {
  const SyncActivity();
  bool get isActive;
  String get displayText;
  IconData get icon;
  Color get color;
}

class SyncActivityIdle extends SyncActivity {
  const SyncActivityIdle();
  @override bool get isActive => false;
  @override String get displayText => 'Synced';
  @override IconData get icon => Icons.check_circle;
  @override Color get color => const Color(0xFFA6E22E);
}

class SyncActivitySyncing extends SyncActivity {
  final String description;
  const SyncActivitySyncing(this.description);
  @override bool get isActive => true;
  @override String get displayText => description;
  @override IconData get icon => Icons.sync;
  @override Color get color => const Color(0xFFE6DB74);
}

class SyncActivityDownloading extends SyncActivity {
  final String fileName;
  final double progress;
  const SyncActivityDownloading(this.fileName, this.progress);
  @override bool get isActive => true;
  @override String get displayText => '↓ $fileName ${(progress * 100).toInt()}%';
  @override IconData get icon => Icons.download;
  @override Color get color => const Color(0xFF66D9EF);
}

// ═══════════════════════════════════════════════════════════════════════════
// FILE TRANSFER INFO
// ═══════════════════════════════════════════════════════════════════════════

class FileTransferInfo {
  final String id;
  final String fileName;
  final bool isDownload;
  final double progress;
  final TransferStatus status;

  const FileTransferInfo({
    required this.id,
    required this.fileName,
    this.isDownload = true,
    this.progress = 0.0,
    this.status = TransferStatus.inProgress,
  });

  FileTransferInfo copyWith({double? progress, TransferStatus? status}) {
    return FileTransferInfo(
      id: id,
      fileName: fileName,
      isDownload: isDownload,
      progress: progress ?? this.progress,
      status: status ?? this.status,
    );
  }
}

enum TransferStatus { inProgress, completed, failed }

// ═══════════════════════════════════════════════════════════════════════════
// STATUS BAR WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class StatusBar extends ConsumerWidget {
  final VoidCallback? onChatToggle;
  final bool isChatOpen;

  const StatusBar({
    super.key,
    this.onChatToggle,
    this.isChatOpen = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(statusBarProvider);
    final selection = ref.watch(selectionProvider);

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF252525),
      child: Row(
        children: [
          // Breadcrumb
          _Breadcrumb(selection: selection),
          
          const Spacer(),
          
          // Active transfers (if any)
          if (status.activeTransfers.isNotEmpty) ...[
            _TransfersIndicator(transfers: status.activeTransfers),
            _divider(),
          ],
          
          // Object count
          _ObjectCount(count: status.objectCount),
          _divider(),
          
          // Peer count
          _PeerCount(count: status.peerCount),
          _divider(),
          
          // Sync status
          _SyncStatus(
            activity: status.syncActivity,
            progress: status.syncProgress,
          ),
          _divider(),
          
          // Chat toggle
          _ChatToggle(
            isOpen: isChatOpen,
            canOpen: selection.selectedWorkspaceId != null || selection.selectedGroupId != null,
            onTap: onChatToggle,
          ),
          _divider(),
          
          // Profile
          _ProfileButton(),
        ],
      ),
    );
  }

  static Widget _divider() {
    return Container(
      width: 1,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFF808080).withOpacity(0.3),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUBCOMPONENTS
// ═══════════════════════════════════════════════════════════════════════════

class _Breadcrumb extends StatelessWidget {
  final SelectionState selection;
  const _Breadcrumb({required this.selection});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          selection.selectedBoardId != null ? Icons.dashboard
            : selection.selectedWorkspaceId != null ? Icons.workspaces_outline
            : selection.selectedGroupId != null ? Icons.folder
            : Icons.circle_outlined,
          size: 10,
          color: const Color(0xFF66D9EF),
        ),
        const SizedBox(width: 6),
        Text(
          selection.breadcrumb,
          style: const TextStyle(fontSize: 11, color: Color(0xFFF8F8F2)),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _ObjectCount extends StatelessWidget {
  final int count;
  const _ObjectCount({required this.count});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Total objects',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.layers, size: 10, color: Color(0xFF808080)),
          const SizedBox(width: 4),
          Text('$count', style: const TextStyle(fontSize: 10, color: Color(0xFF808080))),
        ],
      ),
    );
  }
}

class _PeerCount extends StatelessWidget {
  final int count;
  const _PeerCount({required this.count});

  @override
  Widget build(BuildContext context) {
    final color = count > 0 ? const Color(0xFFA6E22E) : const Color(0xFF808080).withOpacity(0.5);
    return Tooltip(
      message: '$count peers connected',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.people_outline, size: 10, color: Color(0xFF808080)),
          const SizedBox(width: 4),
          Text('$count', style: TextStyle(fontSize: 10, color: count > 0 ? const Color(0xFFA6E22E) : const Color(0xFF808080))),
        ],
      ),
    );
  }
}

class _SyncStatus extends StatelessWidget {
  final SyncActivity activity;
  final double progress;
  const _SyncStatus({required this.activity, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: activity.isActive ? 'Syncing...' : 'All changes synced',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (activity.isActive)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(activity.color),
              ),
            )
          else
            Icon(activity.icon, size: 10, color: activity.color),
          const SizedBox(width: 4),
          if (activity.isActive && progress > 0)
            SizedBox(
              width: 50,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: const Color(0xFF3E3D32),
                valueColor: AlwaysStoppedAnimation(activity.color),
                minHeight: 3,
              ),
            ),
          if (activity.isActive && progress > 0) const SizedBox(width: 4),
          Text(
            activity.displayText,
            style: TextStyle(fontSize: 10, color: activity.color),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TransfersIndicator extends StatelessWidget {
  final List<FileTransferInfo> transfers;
  const _TransfersIndicator({required this.transfers});

  @override
  Widget build(BuildContext context) {
    final activeCount = transfers.where((t) => t.status == TransferStatus.inProgress).length;
    return Tooltip(
      message: '$activeCount active transfer(s)',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.swap_vert, size: 10, color: Color(0xFF66D9EF)),
          const SizedBox(width: 4),
          Text('$activeCount', style: const TextStyle(fontSize: 10, color: Color(0xFF66D9EF))),
        ],
      ),
    );
  }
}

class _ChatToggle extends StatelessWidget {
  final bool isOpen;
  final bool canOpen;
  final VoidCallback? onTap;
  const _ChatToggle({required this.isOpen, required this.canOpen, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = isOpen
        ? const Color(0xFFAE81FF)
        : canOpen
            ? const Color(0xFF808080)
            : const Color(0xFF808080).withOpacity(0.3);
    return Tooltip(
      message: isOpen ? 'Hide chat' : canOpen ? 'Open chat' : 'Select workspace to chat',
      child: GestureDetector(
        onTap: canOpen || isOpen ? onTap : null,
        child: Icon(
          isOpen ? Icons.chat_bubble : Icons.chat_bubble_outline,
          size: 12,
          color: color,
        ),
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Profile',
      child: GestureDetector(
        onTap: () {
          // TODO: Show profile dialog
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: const Color(0xFF66D9EF).withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('U', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF66D9EF))),
              ),
            ),
            const SizedBox(width: 4),
            const Text('abc123', style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFF66D9EF))),
          ],
        ),
      ),
    );
  }
}
