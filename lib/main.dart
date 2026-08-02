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
import 'providers/cyan_backend_provider.dart';
import 'ffi/cyan_backend.dart';
import 'ffi/cyan_backend_ffi.dart';
import 'ffi/ffi_helpers.dart';
import 'services/python_executor.dart';
import 'services/model_registry.dart';

/// The backend the app runs against.
///
/// Every target — macOS, Windows, Linux — gets the same FFI adapter. Which
/// engine binary that adapter opens is decided by `CyanEngineLibrary`, keyed on
/// the running OS, and a target with no binary degrades to the bindings'
/// local-only fallbacks. So there is deliberately no `Platform.isMacOS` gate
/// and no assertion here: adding one would make the Windows runner abort at
/// startup instead of launching against whatever engine it can find.
CyanBackend selectCyanBackend() => CyanBackendFFI();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notebook cache for persistence
  await CyanFFI.initializeCache();

  // Initialize Python environment detection (async, non-blocking)
  PythonEnvironment.instance.initialize();

  // Initialize model registry
  ModelRegistry.instance.initialize();

  runApp(
    ProviderScope(
      overrides: [
        cyanBackendProvider.overrideWithValue(selectCyanBackend()),
      ],
      child: const CyanApp(),
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
