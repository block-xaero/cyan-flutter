// main.dart
// App entry point with identity-based initialization

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/auth_provider.dart';
import 'screens/login_view.dart';
import 'screens/workspace_screen.dart';
import 'widgets/icon_rail.dart';
import 'widgets/status_bar.dart';

void main() {
  runApp(const ProviderScope(child: CyanApp()));
}

class CyanApp extends ConsumerWidget {
  const CyanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Cyan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF66D9EF),
          secondary: Color(0xFFA6E22E),
          surface: Color(0xFF252525),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF252525),
          elevation: 0,
        ),
        // Monokai-inspired text theme
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontFamily: 'SF Pro Text', color: Color(0xFFF8F8F2)),
          bodyMedium: TextStyle(fontFamily: 'SF Pro Text', color: Color(0xFFF8F8F2)),
          bodySmall: TextStyle(fontFamily: 'SF Pro Text', color: Color(0xFF808080)),
          titleLarge: TextStyle(fontFamily: 'SF Pro Text', fontWeight: FontWeight.w600, color: Color(0xFFF8F8F2)),
          titleMedium: TextStyle(fontFamily: 'SF Pro Text', fontWeight: FontWeight.w500, color: Color(0xFFF8F8F2)),
          labelSmall: TextStyle(fontFamily: 'SF Mono', fontSize: 10, color: Color(0xFF808080)),
        ),
      ),
      home: const _AppRoot(),
    );
  }
}

class _AppRoot extends ConsumerWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    // Show splash while initializing
    if (!authState.isInitialized) {
      return const _SplashScreen();
    }

    // Show login if not authenticated
    if (!authState.isAuthenticated) {
      return const LoginView();
    }

    // Show main app with shell
    return const _AppShell();
  }
}

/// Main app shell with IconRail + Content + StatusBar
class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    return KeyboardShortcuts(
      child: Scaffold(
        body: Column(
          children: [
            // Main content area
            Expanded(
              child: Row(
                children: [
                  // Icon rail (left)
                  const IconRail(),
                  
                  // Vertical divider
                  Container(width: 1, color: const Color(0xFF3E3D32)),
                  
                  // Content area
                  const Expanded(child: WorkspaceScreen()),
                ],
              ),
            ),
            
            // Status bar (bottom)
            const StatusBar(),
          ],
        ),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Center(
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
            const Text(
              'Cyan',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF8F8F2),
              ),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(
              color: Color(0xFF66D9EF),
              strokeWidth: 2,
            ),
          ],
        ),
      ),
    );
  }
}
