// screens/login_screen.dart
// XaeroID Login - Matches Swift LoginView.swift exactly
// Real Google OAuth, backup QR, restore key entry

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/monokai_theme.dart';
import '../providers/auth_provider.dart';
import '../models/xaero_identity.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final String? initialError;
  const LoginScreen({super.key, this.initialError});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      backgroundColor: MonokaiTheme.background,
      body: Stack(
        children: [
          // Main content
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const Spacer(),
                    _logoSection(),
                    const SizedBox(height: 48),
                    _buttonsSection(isLoading),
                    const Spacer(),
                    _footerSection(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
          // Loading overlay
          if (isLoading) _loadingOverlay(),
        ],
      ),
    );
  }

  // ==== LOGO ====

  Widget _logoSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Hexagon with X
        SizedBox(
          width: 90, height: 90,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.hexagon, size: 80, color: MonokaiTheme.cyan.withOpacity(0.15)),
              Icon(Icons.hexagon_outlined, size: 80, color: MonokaiTheme.cyan),
              const Text('X', style: TextStyle(
                fontSize: 32, fontWeight: FontWeight.bold,
                fontFamily: 'monospace', color: MonokaiTheme.cyan,
              )),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('Cyan', style: TextStyle(
          fontSize: 28, fontWeight: FontWeight.w600, color: Color(0xFFF8F8F2),
        )),
        const SizedBox(height: 4),
        Text('Decentralized Collaboration', style: TextStyle(
          fontSize: 14, color: MonokaiTheme.comment,
        )),
      ],
    );
  }

  // ==== BUTTONS ====

  Widget _buttonsSection(bool isLoading) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Error message
        if (_error != null || ref.watch(authProvider).error != null)
          _errorBanner(_error ?? ref.watch(authProvider).error!),

        // Primary: Scan XaeroID
        _primaryButton(
          icon: Icons.qr_code_scanner,
          label: 'Scan XaeroID',
          onTap: isLoading ? null : _scanQRCode,
        ),
        const SizedBox(height: 16),

        // Secondary: Enter Backup Key
        _secondaryButton(
          icon: Icons.key,
          label: 'Enter Backup Key',
          onTap: isLoading ? null : _enterBackupKey,
        ),
        const SizedBox(height: 16),

        // Google Sign-Up
        _googleButton(isLoading),
        const SizedBox(height: 20),

        // Divider
        _orDivider(),
        const SizedBox(height: 20),

        // Test Account
        GestureDetector(
          onTap: isLoading ? null : _useTestAccount,
          child: Text('Use Test Account', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w500,
            color: MonokaiTheme.comment,
            decoration: TextDecoration.underline,
            decorationColor: MonokaiTheme.comment,
          )),
        ),
      ],
    );
  }

  Widget _primaryButton({required IconData icon, required String label, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: MonokaiTheme.cyan,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: MonokaiTheme.background),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: MonokaiTheme.background,
            )),
          ],
        ),
      ),
    );
  }

  Widget _secondaryButton({required IconData icon, required String label, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: MonokaiTheme.cyan.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MonokaiTheme.cyan.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: MonokaiTheme.cyan),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w500, color: MonokaiTheme.cyan,
            )),
          ],
        ),
      ),
    );
  }

  Widget _googleButton(bool isLoading) {
    return GestureDetector(
      onTap: isLoading ? null : _signUpWithGoogle,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: MonokaiTheme.comment.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MonokaiTheme.comment.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Google G icon
            Container(
              width: 20, height: 20,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Text('G', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue,
              )),
            ),
            const SizedBox(width: 12),
            const Text('Sign up with Google', style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFFF8F8F2),
            )),
          ],
        ),
      ),
    );
  }

  Widget _orDivider() {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: MonokaiTheme.comment.withOpacity(0.3))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: TextStyle(fontSize: 12, color: MonokaiTheme.comment)),
        ),
        Expanded(child: Container(height: 1, color: MonokaiTheme.comment.withOpacity(0.3))),
      ],
    );
  }

  Widget _errorBanner(String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MonokaiTheme.red.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MonokaiTheme.red.withOpacity(0.5)),
        ),
        child: Text(message, style: TextStyle(fontSize: 13, color: Color(0xFFF8F8F2))),
      ),
    );
  }

  // ==== FOOTER ====

  Widget _footerSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Your identity stays on your device', style: TextStyle(
          fontSize: 12, color: MonokaiTheme.comment.withOpacity(0.7),
        )),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock, size: 10, color: MonokaiTheme.green.withOpacity(0.7)),
            const SizedBox(width: 4),
            Text('End-to-end encrypted', style: TextStyle(
              fontSize: 11, color: MonokaiTheme.green.withOpacity(0.7),
            )),
          ],
        ),
      ],
    );
  }

  Widget _loadingOverlay() {
    return Container(
      color: MonokaiTheme.background.withOpacity(0.8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: MonokaiTheme.cyan),
            const SizedBox(height: 16),
            Text('Connecting...', style: TextStyle(fontSize: 14, color: MonokaiTheme.comment)),
          ],
        ),
      ),
    );
  }

  // ==== ACTIONS ====

  void _scanQRCode() {
    // TODO: Camera QR scanner (requires mobile or macOS camera permission)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('QR Scanner requires camera access - use Enter Backup Key instead')),
    );
  }

  Future<void> _enterBackupKey() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => const _RestoreKeyDialog(),
    );

    if (result != null && result.isNotEmpty && mounted) {
      final success = await ref.read(authProvider.notifier).restoreFromBackup(result);
      if (!success && mounted) {
        setState(() => _error = 'Failed to restore identity');
      }
    }
  }

  Future<void> _signUpWithGoogle() async {
    setState(() => _error = null);

    final authNotifier = ref.read(authProvider.notifier);
    final result = await authNotifier.signUpWithGoogle();

    if (result == null) {
      // Error already set in auth state
      return;
    }

    if (!mounted) return;

    // Show BackupQR sheet - user MUST confirm before proceeding
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BackupQRDialog(
        identity: result.identity,
        displayName: result.displayName,
        avatarUrl: result.avatarUrl,
      ),
    );

    if (confirmed == true && mounted) {
      await authNotifier.confirmGoogleSignUp(
        result.identity,
        displayName: result.displayName,
        avatarUrl: result.avatarUrl,
      );
    }
  }

  Future<void> _useTestAccount() async {
    setState(() => _error = null);
    await ref.read(authProvider.notifier).signInAsTest();
  }
}

// ============================================================================
// RESTORE KEY DIALOG - Matches Swift RestoreKeyEntryView
// ============================================================================

class _RestoreKeyDialog extends StatefulWidget {
  const _RestoreKeyDialog();

  @override
  State<_RestoreKeyDialog> createState() => _RestoreKeyDialogState();
}

class _RestoreKeyDialogState extends State<_RestoreKeyDialog> {
  final _controller = TextEditingController();
  bool _showError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: MonokaiTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Text('Restore from Backup', style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFFF8F8F2),
                  )),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: MonokaiTheme.comment),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Text('Enter your 64-character backup key', style: TextStyle(
                fontSize: 14, color: MonokaiTheme.comment,
              )),
              const SizedBox(height: 16),

              // Key input
              TextField(
                controller: _controller,
                maxLines: 2,
                style: const TextStyle(fontSize: 14, fontFamily: 'monospace', color: Color(0xFFF8F8F2)),
                decoration: InputDecoration(
                  filled: true, fillColor: MonokaiTheme.background,
                  hintText: 'Paste backup key here...',
                  hintStyle: TextStyle(color: MonokaiTheme.comment.withOpacity(0.5)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _showError ? MonokaiTheme.red : MonokaiTheme.comment.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: _showError ? MonokaiTheme.red : MonokaiTheme.comment.withOpacity(0.3)),
                  ),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                  LengthLimitingTextInputFormatter(64),
                ],
              ),

              if (_showError) ...[
                const SizedBox(height: 8),
                Text('Key must be exactly 64 hexadecimal characters', style: TextStyle(
                  fontSize: 12, color: MonokaiTheme.red,
                )),
              ],

              const SizedBox(height: 20),

              // Restore button
              SizedBox(
                width: double.infinity, height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MonokaiTheme.cyan,
                    foregroundColor: MonokaiTheme.background,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    final cleaned = _controller.text.trim().toLowerCase();
                    if (cleaned.length == 64 && RegExp(r'^[0-9a-f]+$').hasMatch(cleaned)) {
                      Navigator.pop(context, cleaned);
                    } else {
                      setState(() => _showError = true);
                    }
                  },
                  child: const Text('Restore Identity', style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600,
                  )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// BACKUP QR DIALOG - Matches Swift BackupQRView
// ============================================================================

class _BackupQRDialog extends StatefulWidget {
  final XaeroIdentity identity;
  final String? displayName;
  final String? avatarUrl;

  const _BackupQRDialog({
    required this.identity,
    this.displayName,
    this.avatarUrl,
  });

  @override
  State<_BackupQRDialog> createState() => _BackupQRDialogState();
}

class _BackupQRDialogState extends State<_BackupQRDialog> {
  bool _hasSaved = false;
  bool _showCopied = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: MonokaiTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Welcome header
              if (widget.displayName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('Welcome, ${widget.displayName}!', style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFFF8F8F2),
                  )),
                ),

              // Warning banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MonokaiTheme.yellow.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warning_amber, size: 18, color: MonokaiTheme.yellow),
                    const SizedBox(width: 8),
                    Text('Save Your Backup Key', style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: MonokaiTheme.yellow,
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'This key is your only way to recover your identity on a new device. Copy it and store it securely.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: MonokaiTheme.comment),
              ),
              const SizedBox(height: 20),

              // QR Code placeholder (rendered as text grid)
              Container(
                width: 200, height: 200,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CustomPaint(
                  painter: _QRPainter(widget.identity.secretKeyHex),
                  size: const Size(168, 168),
                ),
              ),
              const SizedBox(height: 16),

              // XaeroID
              Text('XaeroID: ${widget.identity.shortId}', style: const TextStyle(
                fontSize: 14, fontFamily: 'monospace', color: MonokaiTheme.cyan,
              )),
              const SizedBox(height: 16),

              // Backup Key (copyable)
              Text('Backup Key', style: TextStyle(fontSize: 12, color: MonokaiTheme.comment)),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _copyKey,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: MonokaiTheme.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: MonokaiTheme.comment.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(widget.identity.secretKeyHex, style: const TextStyle(
                          fontSize: 10, fontFamily: 'monospace', color: Color(0xFFF8F8F2),
                        ), maxLines: 2, textAlign: TextAlign.center),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _showCopied ? Icons.check : Icons.copy,
                        size: 14,
                        color: _showCopied ? MonokaiTheme.green : MonokaiTheme.comment,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Confirmation checkbox
              GestureDetector(
                onTap: () => setState(() => _hasSaved = !_hasSaved),
                child: Row(
                  children: [
                    Icon(
                      _hasSaved ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 22,
                      color: _hasSaved ? MonokaiTheme.green : MonokaiTheme.comment,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('I have saved my backup key', style: TextStyle(
                        fontSize: 14, color: Color(0xFFF8F8F2),
                      )),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Continue button
              SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _hasSaved ? MonokaiTheme.cyan : MonokaiTheme.comment.withOpacity(0.3),
                    foregroundColor: _hasSaved ? MonokaiTheme.background : MonokaiTheme.comment,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _hasSaved ? () => Navigator.pop(context, true) : null,
                  child: const Text('Continue to Cyan', style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600,
                  )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _copyKey() {
    Clipboard.setData(ClipboardData(text: widget.identity.secretKeyHex));
    setState(() => _showCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showCopied = false);
    });
  }
}

// ============================================================================
// QR CODE PAINTER (deterministic from hex data)
// ============================================================================

class _QRPainter extends CustomPainter {
  final String data;
  _QRPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    // Generate a deterministic QR-like pattern from the hex key
    // Real QR would use qr_flutter package; this is a visual placeholder
    // that creates a unique, recognizable pattern per key
    final paint = Paint()..color = Colors.black;
    final cellSize = size.width / 25;

    // Fixed finder patterns (top-left, top-right, bottom-left)
    _drawFinderPattern(canvas, paint, 0, 0, cellSize);
    _drawFinderPattern(canvas, paint, 18 * cellSize, 0, cellSize);
    _drawFinderPattern(canvas, paint, 0, 18 * cellSize, cellSize);

    // Data area - deterministic from hex
    final bytes = <int>[];
    for (var i = 0; i < data.length - 1; i += 2) {
      bytes.add(int.parse(data.substring(i, i + 2), radix: 16));
    }

    var byteIdx = 0;
    for (var row = 0; row < 25; row++) {
      for (var col = 0; col < 25; col++) {
        // Skip finder pattern areas
        if ((row < 8 && col < 8) || (row < 8 && col > 16) || (row > 16 && col < 8)) continue;

        if (byteIdx < bytes.length) {
          final bit = (bytes[byteIdx % bytes.length] >> (col % 8)) & 1;
          if (bit == 1) {
            canvas.drawRect(
              Rect.fromLTWH(col * cellSize, row * cellSize, cellSize, cellSize),
              paint,
            );
          }
          if (col % 3 == 0) byteIdx++;
        }
      }
    }
  }

  void _drawFinderPattern(Canvas canvas, Paint paint, double x, double y, double cellSize) {
    // Outer ring
    canvas.drawRect(Rect.fromLTWH(x, y, 7 * cellSize, 7 * cellSize), paint);
    // White inner
    final whitePaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(x + cellSize, y + cellSize, 5 * cellSize, 5 * cellSize), whitePaint);
    // Center
    canvas.drawRect(Rect.fromLTWH(x + 2 * cellSize, y + 2 * cellSize, 3 * cellSize, 3 * cellSize), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
