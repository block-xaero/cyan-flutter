// theme/monokai_theme.dart
// Monokai Pro color scheme

import 'package:flutter/material.dart';

class MonokaiTheme {
  // Core Monokai Pro colors
  static const Color background = Color(0xFF1A1A1A);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color surfaceLight = Color(0xFF2D2D2D);
  static const Color foreground = Color(0xFFF8F8F2);
  static const Color comment = Color(0xFF75715E);
  
  // Accent colors
  static const Color cyan = Color(0xFF66D9EF);
  static const Color green = Color(0xFFA6E22E);
  static const Color yellow = Color(0xFFE6DB74);
  static const Color orange = Color(0xFFFD971F);
  static const Color red = Color(0xFFF92672);
  static const Color purple = Color(0xFFAE81FF);
  static const Color pink = Color(0xFFFF79C6);
  
  // Semantic colors
  static const Color selection = Color(0xFF49483E);
  static const Color border = Color(0xFF3E3D32);
  static const Color divider = Color(0xFF2A2A2A);
  
  // Status colors
  static const Color success = green;
  static const Color warning = orange;
  static const Color error = red;
  static const Color info = cyan;
  
  // Text colors
  static const Color textPrimary = foreground;
  static const Color textSecondary = comment;
  static const Color textMuted = Color(0xFF606060);
  
  /// Dark theme data for MaterialApp
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      
      colorScheme: const ColorScheme.dark(
        primary: cyan,
        secondary: purple,
        surface: surface,
        error: red,
        onPrimary: background,
        onSecondary: background,
        onSurface: foreground,
        onError: foreground,
      ),
      
      scaffoldBackgroundColor: background,
      
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: foreground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: foreground,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),
      
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: foreground),
        displayMedium: TextStyle(color: foreground),
        displaySmall: TextStyle(color: foreground),
        headlineLarge: TextStyle(color: foreground),
        headlineMedium: TextStyle(color: foreground),
        headlineSmall: TextStyle(color: foreground),
        titleLarge: TextStyle(color: foreground, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: foreground, fontWeight: FontWeight.w500),
        titleSmall: TextStyle(color: foreground, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: foreground),
        bodyMedium: TextStyle(color: foreground),
        bodySmall: TextStyle(color: comment),
        labelLarge: TextStyle(color: foreground),
        labelMedium: TextStyle(color: comment),
        labelSmall: TextStyle(color: comment),
      ),
      
      iconTheme: const IconThemeData(
        color: comment,
        size: 20,
      ),
      
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cyan,
          foregroundColor: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cyan,
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
      
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: cyan),
        ),
        hintStyle: const TextStyle(color: comment),
        labelStyle: const TextStyle(color: comment),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      
      listTileTheme: const ListTileThemeData(
        iconColor: comment,
        textColor: foreground,
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),
      
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceLight,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: border),
        ),
        textStyle: const TextStyle(color: foreground, fontSize: 12),
      ),
      
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceLight,
        contentTextStyle: const TextStyle(color: foreground),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: cyan,
        linearTrackColor: border,
      ),
      
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(comment.withValues(alpha: 0.5)),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(6),
      ),
    );
  }
}

extension MonokaiColors on BuildContext {
  Color get cyanAccent => MonokaiTheme.cyan;
  Color get greenAccent => MonokaiTheme.green;
  Color get yellowAccent => MonokaiTheme.yellow;
  Color get orangeAccent => MonokaiTheme.orange;
  Color get redAccent => MonokaiTheme.red;
  Color get purpleAccent => MonokaiTheme.purple;
  Color get surfaceColor => MonokaiTheme.surface;
  Color get commentColor => MonokaiTheme.comment;
}
