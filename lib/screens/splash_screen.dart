// screens/splash_screen.dart
// Initial loading screen - checks for stored identity

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/identity_service.dart';
import 'login_screen.dart';
import 'home_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  String _status = 'Initializing...';
  
  @override
  void initState() {
    super.initState();
    _initialize();
  }
  
  Future<void> _initialize() async {
    await Future.delayed(const Duration(milliseconds: 500));
    
    setState(() => _status = 'Checking identity...');
    
    final identityService = ref.read(identityServiceProvider);
    final hasIdentity = await identityService.hasStoredIdentity();
    
    if (!mounted) return;
    
    if (hasIdentity) {
      setState(() => _status = 'Loading identity...');
      final identity = await identityService.loadIdentity();
      
      if (identity != null && mounted) {
        setState(() => _status = 'Starting backend...');
        final success = await identityService.initializeBackend(identity);
        
        if (success && mounted) {
          _navigateToHome();
        } else if (mounted) {
          _navigateToLogin(error: 'Failed to initialize backend');
        }
      } else if (mounted) {
        _navigateToLogin();
      }
    } else {
      if (mounted) {
        _navigateToLogin();
      }
    }
  }
  
  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }
  
  void _navigateToLogin({String? error}) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => LoginScreen(initialError: error)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF272822),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Cyan logo placeholder
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF66D9EF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.hub,
                size: 48,
                color: Color(0xFF272822),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Cyan',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF8F8F2),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _status,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF75715E),
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF66D9EF)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
