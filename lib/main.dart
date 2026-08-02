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
import 'ffi/cyan_bindings.dart';
import 'ffi/ffi_helpers.dart';
import 'screens/engine_unavailable_screen.dart';
import 'services/python_executor.dart';
import 'services/model_registry.dart';

/// The backend the app runs against.
///
/// Every target — macOS, Windows, Linux — gets the same FFI adapter. Which
/// engine binary that adapter opens is decided by `CyanEngineLibrary`, keyed on
/// the running OS. There is deliberately no `Platform.isMacOS` gate here — the
/// adapter is the same everywhere and a per-OS branch would rot.
///
/// This function stays unconditional. The engine-missing case is handled ONCE,
/// in `main`, by refusing to start rather than by branching the backend: a
/// second no-op backend would be another way to look like it works.
CyanBackend selectCyanBackend() => CyanBackendFFI();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notebook cache for persistence
  await CyanFFI.initializeCache();

  // Initialize Python environment detection (async, non-blocking)
  PythonEnvironment.instance.initialize();

  // Initialize model registry
  ModelRegistry.instance.initialize();

  // Force the engine to resolve BEFORE the first frame, and refuse to present a
  // working-looking app if it did not.
  //
  // The binder degrades to no-ops when the engine is absent — legitimately, on
  // iOS, where the engine is linked statically and its symbols come from the
  // process. What is NOT legitimate is a desktop build shipping in that state:
  // every screen renders, every button responds, and nothing is written. That is
  // indistinguishable from working right up until a customer loses a day's work,
  // and it is exactly how a six-month-old engine went unnoticed on macOS.
  //
  // So a degraded build stops here and says why. This is the last line of
  // defence; the build itself already fails when the engine is unstaged
  // (macOS "Embed Cyan Engine" phase, Windows CMake FATAL_ERROR).
  CyanBindings.instance;
  if (CyanBindings.isDegraded) {
    runApp(EngineUnavailableApp(
      reason: CyanBindings.degradedReason ?? 'unknown',
      triedPaths: CyanBindings.triedPaths,
    ));
    return;
  }

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
