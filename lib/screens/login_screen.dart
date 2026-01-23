// screens/login_screen.dart
// XaeroID Login with Google Sign-in, QR scan, and backup key entry

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/identity_service.dart';
import 'home_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final String? initialError;
  
  const LoginScreen({super.key, this.initialError});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isLoading = false;
  String? _error;
  
  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
  }
  
  Future<void> _scanQRCode() async {
    // TODO: Implement QR scanner
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('QR Scanner coming soon')),
    );
  }
  
  Future<void> _enterBackupKey() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const _BackupKeyDialog(),
    );
    
    if (result != null && result.isNotEmpty) {
      await _restoreFromKey(result);
    }
  }
  
  Future<void> _signUpWithGoogle() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      // TODO: Implement actual Google Sign-in
      // For now, create a new identity
      final identityService = ref.read(identityServiceProvider);
      final identity = await identityService.createIdentity(displayName: 'Google User');
      
      if (!mounted) return;
      
      // Show backup QR view
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _BackupQRDialog(identity: identity),
      );
      
      if (confirmed == true && mounted) {
        final success = await identityService.initializeBackend(identity);
        if (success && mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }
  
  Future<void> _useTestAccount() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final identityService = ref.read(identityServiceProvider);
      final identity = await identityService.createTestIdentity();
      
      if (!mounted) return;
      
      final success = await identityService.initializeBackend(identity);
      
      if (success && mounted) {
        identityService.seedDemoData();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to initialize backend';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }
  
  Future<void> _restoreFromKey(String secretKeyHex) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      // TODO: Implement restore from backup key
      setState(() {
        _isLoading = false;
        _error = 'Restore from backup key not yet implemented';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo section
                      _buildLogo(),
                      const SizedBox(height: 48),
                      
                      // Error message
                      if (_error != null) ...[
                        _buildErrorBanner(),
                        const SizedBox(height: 16),
                      ],
                      
                      // Primary: Scan XaeroID
                      _PrimaryButton(
                        icon: Icons.qr_code_scanner,
                        label: 'Scan XaeroID',
                        onTap: _isLoading ? null : _scanQRCode,
                      ),
                      const SizedBox(height: 16),
                      
                      // Secondary: Enter Backup Key
                      _SecondaryButton(
                        icon: Icons.key,
                        label: 'Enter Backup Key',
                        onTap: _isLoading ? null : _enterBackupKey,
                      ),
                      const SizedBox(height: 16),
                      
                      // Google Sign-Up
                      _GoogleButton(
                        onTap: _isLoading ? null : _signUpWithGoogle,
                      ),
                      const SizedBox(height: 32),
                      
                      // Footer
                      _buildFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Loading overlay
          if (_isLoading)
            Container(
              color: const Color(0xFF1E1E1E).withValues(alpha: 0.8),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF66D9EF)),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Initializing...',
                      style: TextStyle(color: Color(0xFF808080)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildLogo() {
    return Column(
      children: [
        // Hexagon with X
        SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.hexagon,
                size: 72,
                color: const Color(0xFF66D9EF).withValues(alpha: 0.15),
              ),
              Icon(
                Icons.hexagon_outlined,
                size: 72,
                color: const Color(0xFF66D9EF),
              ),
              const Text(
                'X',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: Color(0xFF66D9EF),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // App name
        const Text(
          'Cyan',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF8F8F2),
          ),
        ),
        const SizedBox(height: 8),
        
        // Tagline
        const Text(
          'Decentralized Collaboration',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF808080),
          ),
        ),
      ],
    );
  }
  
  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF92672).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFF92672).withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        _error!,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFFF8F8F2),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
  
  Widget _buildFooter() {
    return Column(
      children: [
        TextButton(
          onPressed: _isLoading ? null : _useTestAccount,
          child: const Text(
            'Use Test Account',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF808080),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Your identity is cryptographically secure\nand never leaves your device',
          style: TextStyle(
            fontSize: 11,
            color: Color(0xFF606060),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 48,
          decoration: BoxDecoration(
            color: _isHovered && widget.onTap != null
                ? const Color(0xFF7CE9FF)
                : const Color(0xFF66D9EF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 18, color: const Color(0xFF1E1E1E)),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E1E1E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<_SecondaryButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 44,
          decoration: BoxDecoration(
            color: _isHovered && widget.onTap != null
                ? const Color(0xFF66D9EF).withValues(alpha: 0.15)
                : const Color(0xFF66D9EF).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF66D9EF).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 16, color: const Color(0xFF66D9EF)),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF66D9EF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatefulWidget {
  final VoidCallback? onTap;

  const _GoogleButton({required this.onTap});

  @override
  State<_GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<_GoogleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 44,
          decoration: BoxDecoration(
            color: _isHovered && widget.onTap != null
                ? const Color(0xFF3E3D32)
                : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF606060).withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Google "G" icon approximation
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Center(
                  child: Text(
                    'G',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4285F4),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Sign up with Google',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
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

class _BackupKeyDialog extends StatefulWidget {
  const _BackupKeyDialog();

  @override
  State<_BackupKeyDialog> createState() => _BackupKeyDialogState();
}

class _BackupKeyDialogState extends State<_BackupKeyDialog> {
  final _controller = TextEditingController();
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF252525),
      title: const Text(
        'Enter Backup Key',
        style: TextStyle(color: Color(0xFFF8F8F2)),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paste your 64-character backup key to restore your XaeroID',
            style: TextStyle(fontSize: 13, color: Color(0xFF808080)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: Color(0xFFF8F8F2),
            ),
            decoration: InputDecoration(
              hintText: '0123456789abcdef...',
              hintStyle: const TextStyle(color: Color(0xFF606060)),
              filled: true,
              fillColor: const Color(0xFF1E1E1E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF3E3D32)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF66D9EF)),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF808080))),
        ),
        ElevatedButton(
          onPressed: () {
            final key = _controller.text.trim();
            if (key.length == 64) {
              Navigator.pop(context, key);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF66D9EF),
            foregroundColor: const Color(0xFF1E1E1E),
          ),
          child: const Text('Restore'),
        ),
      ],
    );
  }
}

class _BackupQRDialog extends StatefulWidget {
  final dynamic identity;

  const _BackupQRDialog({required this.identity});

  @override
  State<_BackupQRDialog> createState() => _BackupQRDialogState();
}

class _BackupQRDialogState extends State<_BackupQRDialog> {
  bool _hasSaved = false;
  bool _showCopied = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            const Row(
              children: [
                Icon(Icons.warning_amber, color: Color(0xFFFD971F)),
                SizedBox(width: 8),
                Text(
                  'Save Your XaeroID',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF8F8F2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            const Text(
              'This is your cryptographic identity. Store it securely - you\'ll need it to restore access on other devices.',
              style: TextStyle(fontSize: 13, color: Color(0xFF808080)),
            ),
            const SizedBox(height: 24),
            
            // QR Code placeholder
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
            
            // Backup key
            const Text(
              'Backup Key',
              style: TextStyle(fontSize: 12, color: Color(0xFF808080)),
            ),
            const SizedBox(height: 8),
            
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: widget.identity.secretKeyHex ?? ''));
                setState(() => _showCopied = true);
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) setState(() => _showCopied = false);
                });
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF252525),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF3E3D32)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.identity.secretKeyHex ?? 'Key not available',
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: Color(0xFFF8F8F2),
                        ),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _showCopied ? Icons.check : Icons.copy,
                      size: 14,
                      color: _showCopied ? const Color(0xFFA6E22E) : const Color(0xFF808080),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Confirmation checkbox
            GestureDetector(
              onTap: () => setState(() => _hasSaved = !_hasSaved),
              child: Row(
                children: [
                  Icon(
                    _hasSaved ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 20,
                    color: _hasSaved ? const Color(0xFFA6E22E) : const Color(0xFF808080),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'I have saved my backup key',
                    style: TextStyle(fontSize: 14, color: Color(0xFFF8F8F2)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Continue button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _hasSaved ? () => Navigator.pop(context, true) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _hasSaved
                      ? const Color(0xFF66D9EF)
                      : const Color(0xFF606060).withValues(alpha: 0.3),
                  foregroundColor: _hasSaved
                      ? const Color(0xFF1E1E1E)
                      : const Color(0xFF808080),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Continue to Cyan',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
