// screens/login_view.dart
// Login screen with Google OAuth and test mode

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class LoginView extends ConsumerStatefulWidget {
  const LoginView({super.key});

  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> {
  bool _showQRRestore = false;
  final _secretKeyController = TextEditingController();

  @override
  void dispose() {
    _secretKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF66D9EF), Color(0xFFA6E22E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF66D9EF).withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.hexagon_outlined,
                  size: 50,
                  color: Color(0xFF1E1E1E),
                ),
              ),
              const SizedBox(height: 24),

              // Title
              const Text(
                'Cyan',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF8F8F2),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Decentralized Collaboration',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF808080),
                ),
              ),
              const SizedBox(height: 48),

              // Error message
              if (authState.error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF92672).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF92672).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFF92672), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          authState.error!,
                          style: const TextStyle(color: Color(0xFFF92672), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // QR Restore form
              if (_showQRRestore) ...[
                _QRRestoreForm(
                  controller: _secretKeyController,
                  isLoading: authState.isLoading,
                  onRestore: () async {
                    final key = _secretKeyController.text.trim();
                    if (key.isNotEmpty) {
                      await ref.read(authProvider.notifier).restoreFromBackup(key);
                    }
                  },
                  onCancel: () => setState(() => _showQRRestore = false),
                ),
              ] else ...[
                // Login options
                _LoginButtons(
                  isLoading: authState.isLoading,
                  onGoogleSignIn: () => ref.read(authProvider.notifier).signInWithGoogle(),
                  onTestMode: () => ref.read(authProvider.notifier).signInAsTest(),
                  onRestoreQR: () => setState(() => _showQRRestore = true),
                ),
              ],

              const SizedBox(height: 48),

              // Footer
              const Text(
                'Your identity is secured locally.\nNo central servers. No tracking.',
                style: TextStyle(fontSize: 11, color: Color(0xFF606060)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LOGIN BUTTONS
// ═══════════════════════════════════════════════════════════════════════════

class _LoginButtons extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onGoogleSignIn;
  final VoidCallback onTestMode;
  final VoidCallback onRestoreQR;

  const _LoginButtons({
    required this.isLoading,
    required this.onGoogleSignIn,
    required this.onTestMode,
    required this.onRestoreQR,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Google Sign In
        SizedBox(
          width: 280,
          height: 48,
          child: ElevatedButton(
            onPressed: isLoading ? null : onGoogleSignIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.g_mobiledata, size: 24),
                      SizedBox(width: 8),
                      Text('Sign in with Google', style: TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),

        // Test Mode
        SizedBox(
          width: 280,
          height: 48,
          child: OutlinedButton(
            onPressed: isLoading ? null : onTestMode,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF66D9EF),
              side: const BorderSide(color: Color(0xFF66D9EF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.science_outlined, size: 20),
                SizedBox(width: 8),
                Text('Continue as Test User'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Restore from QR
        TextButton(
          onPressed: isLoading ? null : onRestoreQR,
          child: const Text(
            'Restore from backup QR',
            style: TextStyle(color: Color(0xFF808080), fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// QR RESTORE FORM
// ═══════════════════════════════════════════════════════════════════════════

class _QRRestoreForm extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onRestore;
  final VoidCallback onCancel;

  const _QRRestoreForm({
    required this.controller,
    required this.isLoading,
    required this.onRestore,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3E3D32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Restore from Backup',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFFF8F8F2),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter your secret key from your backup QR code',
            style: TextStyle(fontSize: 12, color: Color(0xFF808080)),
          ),
          const SizedBox(height: 16),

          // Secret key input
          TextField(
            controller: controller,
            style: const TextStyle(color: Color(0xFFF8F8F2), fontSize: 12, fontFamily: 'monospace'),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Paste secret key hex...',
              hintStyle: const TextStyle(color: Color(0xFF808080)),
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
          const SizedBox(height: 16),

          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isLoading ? null : onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF808080),
                    side: const BorderSide(color: Color(0xFF3E3D32)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: isLoading ? null : onRestore,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA6E22E),
                    foregroundColor: const Color(0xFF1E1E1E),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Restore'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Scan QR hint
          TextButton.icon(
            onPressed: () {
              // TODO: Open QR scanner
            },
            icon: const Icon(Icons.qr_code_scanner, size: 16),
            label: const Text('Scan QR Code'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF66D9EF),
            ),
          ),
        ],
      ),
    );
  }
}
