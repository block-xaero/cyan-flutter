// app.dart
// Cyan Flutter - App Configuration

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/monokai_theme.dart';
import 'screens/splash_screen.dart';

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
      home: const SplashScreen(),
    );
  }
}
