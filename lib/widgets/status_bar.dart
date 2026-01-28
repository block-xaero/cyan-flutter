// widgets/status_bar.dart
// Status bar matching Swift app - CyanLens, context, sync status, node ID

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/selection_provider.dart';

// Status bar state
final syncStatusProvider = StateProvider<SyncStatus>((ref) => SyncStatus.synced);
final nodeIdProvider = StateProvider<String>((ref) => 'EMQg8nmp'); // TODO: from FFI
final viewCountProvider = StateProvider<int>((ref) => 20);
final peerCountProvider = StateProvider<int>((ref) => 0);

enum SyncStatus { synced, syncing, offline, error }

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final nodeId = ref.watch(nodeIdProvider);
    final viewCount = ref.watch(viewCountProvider);
    final peerCount = ref.watch(peerCountProvider);

    return Container(
      height: 24,
      color: const Color(0xFF252525),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // CyanLens expandable
          _CyanLensButton(),
          
          const SizedBox(width: 12),
          
          // Current context (group/workspace/board)
          if (selection.selectedGroupName != null) ...[
            Icon(
              Icons.folder,
              size: 12,
              color: _getGroupColor(selection.selectedGroupId),
            ),
            const SizedBox(width: 4),
            Text(
              selection.selectedBoardName ?? 
              selection.selectedWorkspaceName ?? 
              selection.selectedGroupName ?? '',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFF8F8F2),
              ),
            ),
          ] else
            const Text(
              'No selection',
              style: TextStyle(fontSize: 11, color: Color(0xFF808080)),
            ),
          
          const Spacer(),
          
          // View count
          Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 12, color: Color(0xFF808080)),
              const SizedBox(width: 4),
              Text('$viewCount', style: const TextStyle(fontSize: 11, color: Color(0xFF808080))),
            ],
          ),
          
          const SizedBox(width: 12),
          const _StatusDivider(),
          const SizedBox(width: 12),
          
          // Peer count
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: peerCount > 0 ? const Color(0xFFA6E22E) : const Color(0xFF808080),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.people_outline, size: 12, color: Color(0xFF808080)),
              const SizedBox(width: 4),
              Text('$peerCount', style: const TextStyle(fontSize: 11, color: Color(0xFF808080))),
            ],
          ),
          
          const SizedBox(width: 12),
          const _StatusDivider(),
          const SizedBox(width: 12),
          
          // Sync status
          _SyncStatusIndicator(status: syncStatus),
          
          const SizedBox(width: 12),
          const _StatusDivider(),
          const SizedBox(width: 12),
          
          // Node ID (clickable to copy)
          _NodeIdBadge(nodeId: nodeId),
        ],
      ),
    );
  }

  Color _getGroupColor(String? groupId) {
    // TODO: Get from actual group data
    return const Color(0xFF66D9EF);
  }
}

class _CyanLensButton extends StatefulWidget {
  @override
  State<_CyanLensButton> createState() => _CyanLensButtonState();
}

class _CyanLensButtonState extends State<_CyanLensButton> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 12, color: Color(0xFFFD971F)),
          const SizedBox(width: 4),
          const Text(
            'CyanLens',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xFFF8F8F2),
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            _isExpanded ? Icons.expand_less : Icons.expand_more,
            size: 14,
            color: const Color(0xFF808080),
          ),
        ],
      ),
    );
  }
}

class _SyncStatusIndicator extends StatelessWidget {
  final SyncStatus status;

  const _SyncStatusIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (status) {
      SyncStatus.synced => (Icons.check_circle, const Color(0xFFA6E22E), 'Synced'),
      SyncStatus.syncing => (Icons.sync, const Color(0xFF66D9EF), 'Syncing'),
      SyncStatus.offline => (Icons.cloud_off, const Color(0xFF808080), 'Offline'),
      SyncStatus.error => (Icons.error_outline, const Color(0xFFF92672), 'Error'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

class _NodeIdBadge extends StatelessWidget {
  final String nodeId;

  const _NodeIdBadge({required this.nodeId});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Click to copy Node ID',
      child: GestureDetector(
        onTap: () {
          Clipboard.setData(ClipboardData(text: nodeId));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Node ID copied: $nodeId'),
              duration: const Duration(seconds: 2),
              backgroundColor: const Color(0xFF3E3D32),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF3E3D32),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFFA6E22E),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                nodeId,
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: Color(0xFFF8F8F2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDivider extends StatelessWidget {
  const _StatusDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 12,
      color: const Color(0xFF3E3D32),
    );
  }
}
