// main.dart
// Entry point for Cyan Flutter app

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/monokai_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/workspace_screen.dart';
import 'screens/profile_screen.dart';
import 'providers/auth_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: CyanApp(),
    ),
  );
}

class CyanApp extends ConsumerWidget {
  const CyanApp({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Cyan',
      debugShowCheckedModeBanner: false,
      theme: MonokaiTheme.darkTheme,
      darkTheme: MonokaiTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const _AppRoot(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/workspace': (context) => const WorkspaceScreen(),
        '/profile': (context) => const ProfileScreen(),
      },
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
      return const SplashScreen();
    }
    
    // Show login if not authenticated
    if (!authState.isAuthenticated) {
      return const LoginScreen();
    }
    
    // Show main workspace
    return const WorkspaceScreen();
  }
}
