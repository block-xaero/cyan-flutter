// screens/profile_screen.dart
// User profile with QR code, stats, and sign out

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/identity_service.dart';
import '../providers/backend_provider.dart';
import 'login_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityService = ref.watch(identityServiceProvider);
    final currentIdentity = identityService.currentIdentity;
    final backend = ref.watch(backendProvider);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Profile header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF3E3D32),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    // Avatar
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: const Color(0xFF66D9EF),
                        borderRadius: BorderRadius.circular(40),
                      ),
                      child: Center(
                        child: Text(
                          (currentIdentity?.displayName ?? 'U')[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF272822),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Display name
                    Text(
                      currentIdentity?.displayName ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF8F8F2),
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Short ID
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF272822),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        currentIdentity?.shortId ?? '--------',
                        style: const TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                          color: Color(0xFF66D9EF),
                        ),
                      ),
                    ),
                    
                    if (currentIdentity?.isTest ?? false) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFD971F).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'TEST ACCOUNT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFD971F),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Stats
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF3E3D32),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Statistics',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF8F8F2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _StatRow(
                      icon: Icons.storage,
                      label: 'Objects',
                      value: backend.objectCount.toString(),
                    ),
                    const SizedBox(height: 12),
                    _StatRow(
                      icon: Icons.people,
                      label: 'Connected Peers',
                      value: backend.peerCount.toString(),
                    ),
                    const SizedBox(height: 12),
                    _StatRow(
                      icon: Icons.check_circle,
                      label: 'Backend Status',
                      value: backend.isReady ? 'Ready' : 'Not Ready',
                      valueColor: backend.isReady
                          ? const Color(0xFFA6E22E)
                          : const Color(0xFFF92672),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Node ID
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF3E3D32),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Node ID',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF8F8F2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      currentIdentity?.nodeId ?? 'Not available',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Color(0xFF75715E),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Sign out button
              OutlinedButton(
                onPressed: () => _signOut(context, ref),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF92672),
                  side: const BorderSide(color: Color(0xFFF92672)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF3E3D32),
        title: const Text('Sign Out', style: TextStyle(color: Color(0xFFF8F8F2))),
        content: const Text(
          'Are you sure you want to sign out? Your identity will be cleared from this device.',
          style: TextStyle(color: Color(0xFF75715E)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF92672),
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    
    if (confirmed == true && context.mounted) {
      final identityService = ref.read(identityServiceProvider);
      await identityService.clearIdentity();
      
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    }
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF75715E)),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: Color(0xFF75715E))),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? const Color(0xFFF8F8F2),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
