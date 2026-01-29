// widgets/status_bar.dart
// Status bar - 24px, shows sync status and node info
// IMPORTANT: No provider modifications during build/initState

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/monokai_theme.dart';
import '../services/cyan_service.dart';
import '../providers/selection_provider.dart';

// ============================================================================
// STATUS BAR WIDGET - Stateless to avoid lifecycle issues
// ============================================================================

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionProvider);
    
    return Container(
      height: 24,
      color: MonokaiTheme.surface,
      child: Row(
        children: [
          const SizedBox(width: 8),
          
          // CyanLens badge
          _CyanLensBadge(),
          
          const SizedBox(width: 12),
          
          // Selection breadcrumb
          Expanded(
            child: _SelectionBreadcrumb(selection: selection),
          ),
          
          // Sync status (static for now - avoids provider issues)
          const _SyncStatusBadge(),
          
          const SizedBox(width: 16),
          
          // Stats - uses CyanService directly, no provider
          const _StatsDisplay(),
          
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _CyanLensBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'CyanLens AI',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              MonokaiTheme.cyan.withOpacity(0.3),
              MonokaiTheme.purple.withOpacity(0.3),
            ],
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: MonokaiTheme.cyan,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'CyanLens',
              style: MonokaiTheme.labelSmall.copyWith(
                color: MonokaiTheme.cyan,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionBreadcrumb extends StatelessWidget {
  final SelectionState selection;
  
  const _SelectionBreadcrumb({required this.selection});
  
  @override
  Widget build(BuildContext context) {
    final breadcrumb = selection.breadcrumb;
    
    if (breadcrumb.isEmpty) {
      return Text(
        'No selection',
        style: MonokaiTheme.labelSmall.copyWith(
          color: MonokaiTheme.textMuted,
        ),
      );
    }
    
    return Text(
      breadcrumb,
      style: MonokaiTheme.labelSmall.copyWith(
        color: MonokaiTheme.textSecondary,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _SyncStatusBadge extends StatelessWidget {
  const _SyncStatusBadge();
  
  @override
  Widget build(BuildContext context) {
    // Static "Synced" display - no async provider modifications
    return Tooltip(
      message: 'Synced',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_done_outlined,
            size: 14,
            color: MonokaiTheme.green,
          ),
          const SizedBox(width: 4),
          Text(
            'Synced',
            style: MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.green),
          ),
        ],
      ),
    );
  }
}

// Stats display that polls CyanService directly without providers
class _StatsDisplay extends StatefulWidget {
  const _StatsDisplay();
  
  @override
  State<_StatsDisplay> createState() => _StatsDisplayState();
}

class _StatsDisplayState extends State<_StatsDisplay> {
  Timer? _timer;
  int _objectCount = 0;
  int _peerCount = 0;
  String _nodeId = '...';
  
  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _startTimer();
    });
  }
  
  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _refresh();
    });
  }
  
  void _refresh() {
    if (!mounted) return;
    
    final service = CyanService.instance;
    if (service.isReady) {
      setState(() {
        _objectCount = service.objectCount;
        _peerCount = service.peerCount;
        final fullId = service.nodeId;
        _nodeId = (fullId != null && fullId.length >= 8) 
            ? fullId.substring(0, 8) 
            : '...';
      });
    }
  }
  
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Objects
        Tooltip(
          message: 'Objects in database',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.storage_outlined,
                size: 12,
                color: MonokaiTheme.textMuted,
              ),
              const SizedBox(width: 3),
              Text(
                '$_objectCount',
                style: MonokaiTheme.codeSmall.copyWith(
                  color: MonokaiTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Peers
        Tooltip(
          message: 'Connected peers',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.people_outline,
                size: 12,
                color: MonokaiTheme.textMuted,
              ),
              const SizedBox(width: 3),
              Text(
                '$_peerCount',
                style: MonokaiTheme.codeSmall.copyWith(
                  color: MonokaiTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(width: 16),
        
        // Node ID
        Tooltip(
          message: 'Node ID (click to copy)',
          child: GestureDetector(
            onTap: () {
              final service = CyanService.instance;
              if (service.nodeId != null) {
                Clipboard.setData(ClipboardData(text: service.nodeId!));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Node ID copied: $_nodeId...'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: MonokaiTheme.surfaceLight,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _nodeId,
                style: MonokaiTheme.codeSmall.copyWith(
                  color: MonokaiTheme.cyan,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
