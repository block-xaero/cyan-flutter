// widgets/status_bar.dart
// Bottom status bar showing connection, peers, and sync status
// Uses backendProvider for status instead of direct FFI

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/backend_provider.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(backendProvider);
    
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1F1C),
        border: Border(
          top: BorderSide(color: Color(0xFF3E3D32)),
        ),
      ),
      child: Row(
        children: [
          // Connection status
          _StatusIndicator(
            icon: backend.isReady ? Icons.cloud_done : Icons.cloud_off,
            label: backend.isReady ? 'Connected' : 'Disconnected',
            color: backend.isReady
                ? const Color(0xFFA6E22E)
                : const Color(0xFFF92672),
          ),
          
          const SizedBox(width: 24),
          
          // Object count
          _StatusIndicator(
            icon: Icons.storage,
            label: '${backend.objectCount} objects',
            color: const Color(0xFF75715E),
          ),
          
          const SizedBox(width: 24),
          
          // Peer count
          _StatusIndicator(
            icon: Icons.people,
            label: '${backend.peerCount} peers',
            color: backend.peerCount > 0
                ? const Color(0xFF66D9EF)
                : const Color(0xFF75715E),
          ),
          
          const Spacer(),
          
          // Sync indicator (could be driven by events later)
          const Icon(
            Icons.check_circle,
            size: 14,
            color: Color(0xFFA6E22E),
          ),
          const SizedBox(width: 4),
          const Text(
            'Synced',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFFA6E22E),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  
  const _StatusIndicator({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
          ),
        ),
      ],
    );
  }
}
