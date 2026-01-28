// screens/profile_view.dart
// Profile screen with XaeroID display, QR backup, and logout

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class ProfileView extends ConsumerStatefulWidget {
  const ProfileView({super.key});

  @override
  ConsumerState<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<ProfileView> {
  bool _showSecretKey = false;
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    _nameController.text = auth.identity?.displayName ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final identity = auth.identity;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF252525),
        title: const Text('Profile', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Avatar and basic info
            Center(
              child: Column(
                children: [
                  _Avatar(
                    avatarUrl: auth.avatarUrl,
                    displayName: auth.displayName,
                    size: 80,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    auth.displayName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF8F8F2),
                    ),
                  ),
                  if (identity?.email != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      identity!.email!,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF808080)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),

            // XaeroID Card
            _SectionCard(
              title: 'XaeroID',
              icon: Icons.fingerprint,
              iconColor: const Color(0xFF66D9EF),
              children: [
                _InfoRow(
                  label: 'Short ID',
                  value: identity?.shortId ?? '—',
                  copyable: true,
                ),
                const Divider(height: 24, color: Color(0xFF3E3D32)),
                _InfoRow(
                  label: 'DID',
                  value: identity?.did ?? '—',
                  copyable: true,
                  monospace: true,
                ),
                const Divider(height: 24, color: Color(0xFF3E3D32)),
                _InfoRow(
                  label: 'Public Key',
                  value: identity?.publicKeyHex ?? '—',
                  copyable: true,
                  monospace: true,
                  truncate: true,
                ),
                const Divider(height: 24, color: Color(0xFF3E3D32)),
                _InfoRow(
                  label: 'Created',
                  value: identity != null
                      ? '${identity.createdAt.year}-${identity.createdAt.month.toString().padLeft(2, '0')}-${identity.createdAt.day.toString().padLeft(2, '0')}'
                      : '—',
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Backup Card
            _SectionCard(
              title: 'Backup',
              icon: Icons.backup,
              iconColor: const Color(0xFFA6E22E),
              children: [
                const Text(
                  'Save your secret key to restore your identity on another device.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF808080)),
                ),
                const SizedBox(height: 16),

                // Show/Hide Secret Key
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _showSecretKey
                                ? const Color(0xFFF92672)
                                : const Color(0xFF3E3D32),
                          ),
                        ),
                        child: Text(
                          _showSecretKey
                              ? (identity?.secretKeyHex ?? '')
                              : '••••••••••••••••••••••••',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            color: _showSecretKey
                                ? const Color(0xFFF92672)
                                : const Color(0xFF808080),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        _showSecretKey ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                      ),
                      color: const Color(0xFF808080),
                      onPressed: () => setState(() => _showSecretKey = !_showSecretKey),
                      tooltip: _showSecretKey ? 'Hide' : 'Show',
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 20),
                      color: const Color(0xFF808080),
                      onPressed: identity != null
                          ? () {
                              Clipboard.setData(ClipboardData(text: identity.secretKeyHex));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Secret key copied!'),
                                  backgroundColor: Color(0xFFA6E22E),
                                ),
                              );
                            }
                          : null,
                      tooltip: 'Copy',
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Warning
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF92672).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF92672).withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber, size: 18, color: Color(0xFFF92672)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Never share your secret key. Anyone with it can impersonate you.',
                          style: TextStyle(fontSize: 11, color: Color(0xFFF92672)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // QR Code button
                OutlinedButton.icon(
                  onPressed: () => _showQRBackup(context, identity?.secretKeyHex),
                  icon: const Icon(Icons.qr_code, size: 18),
                  label: const Text('Show QR Backup'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF66D9EF),
                    side: const BorderSide(color: Color(0xFF66D9EF)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Edit Profile Card
            _SectionCard(
              title: 'Edit Profile',
              icon: Icons.edit,
              iconColor: const Color(0xFFFD971F),
              children: [
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Color(0xFFF8F8F2), fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Display Name',
                    labelStyle: const TextStyle(color: Color(0xFF808080)),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF3E3D32)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF3E3D32)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF66D9EF)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    ref.read(authProvider.notifier).updateProfile(
                          displayName: _nameController.text.trim(),
                        );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Profile updated'),
                        backgroundColor: Color(0xFFA6E22E),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA6E22E),
                    foregroundColor: const Color(0xFF1E1E1E),
                  ),
                  child: const Text('Save Changes'),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Sign Out
            OutlinedButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF252525),
                    title: const Text('Sign Out?', style: TextStyle(color: Color(0xFFF8F8F2))),
                    content: const Text(
                      'Make sure you have backed up your secret key. You will need it to restore your identity.',
                      style: TextStyle(color: Color(0xFF808080)),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF92672),
                        ),
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await ref.read(authProvider.notifier).signOut();
                  if (mounted) Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign Out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF92672),
                side: const BorderSide(color: Color(0xFFF92672)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showQRBackup(BuildContext context, String? secretKey) {
    if (secretKey == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252525),
        title: const Text('Backup QR Code', style: TextStyle(color: Color(0xFFF8F8F2))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Placeholder for QR code
            // In real app, use qr_flutter package
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Icon(Icons.qr_code_2, size: 150, color: Color(0xFF1E1E1E)),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Scan this code to restore your identity on another device.',
              style: TextStyle(fontSize: 12, color: Color(0xFF808080)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _Avatar extends StatelessWidget {
  final String? avatarUrl;
  final String displayName;
  final double size;

  const _Avatar({
    this.avatarUrl,
    required this.displayName,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 4),
        child: Image.network(
          avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF66D9EF), Color(0xFFA6E22E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: Center(
        child: Text(
          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E1E1E),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3E3D32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFF8F8F2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;
  final bool monospace;
  final bool truncate;

  const _InfoRow({
    required this.label,
    required this.value,
    this.copyable = false,
    this.monospace = false,
    this.truncate = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF808080)),
          ),
        ),
        Expanded(
          child: Text(
            truncate && value.length > 24
                ? '${value.substring(0, 12)}...${value.substring(value.length - 8)}'
                : value,
            style: TextStyle(
              fontSize: 11,
              color: const Color(0xFFF8F8F2),
              fontFamily: monospace ? 'monospace' : null,
            ),
          ),
        ),
        if (copyable)
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label copied!'),
                  backgroundColor: const Color(0xFFA6E22E),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            child: const Icon(Icons.copy, size: 14, color: Color(0xFF808080)),
          ),
      ],
    );
  }
}
