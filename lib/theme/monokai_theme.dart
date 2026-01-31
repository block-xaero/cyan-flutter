// theme/monokai_theme.dart
// Monokai Pro color scheme with refined typography

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MonokaiTheme {
  // Core Monokai Pro colors - matching Swift CyanTheme.monokai exactly
  static const Color background = Color(0xFF272822);  // Swift: "272822"
  static const Color surface = Color(0xFF3E3D32);     // Swift: "3E3D32"
  static const Color surfaceLight = Color(0xFF4E4D42); // Swift: surfaceHover
  static const Color surfaceLighter = Color(0xFF2A2A2A);
  static const Color foreground = Color(0xFFF8F8F2);  // Swift: "F8F8F2"
  static const Color comment = Color(0xFF75715E);     // Swift: "75715E"
  
  // Accent colors (Monokai Pro)
  static const Color cyan = Color(0xFF66D9EF);
  static const Color green = Color(0xFFA6E22E);
  static const Color yellow = Color(0xFFE6DB74);
  static const Color orange = Color(0xFFFD971F);
  static const Color red = Color(0xFFF92672);
  static const Color purple = Color(0xFFAE81FF);
  static const Color pink = Color(0xFFFF79C6);
  
  // UI colors - matching Swift
  static const Color selection = Color(0xFF49483E);
  static const Color border = Color(0xFF4A4A40);      // Swift: divider "4A4A40"
  static const Color divider = Color(0xFF4A4A40);
  static const Color hover = Color(0xFF2A2A2A);
  static const Color active = Color(0xFF264F78);
  
  // Text hierarchy
  static const Color textPrimary = foreground;
  static const Color textSecondary = Color(0xFFBBBBBB);
  static const Color textMuted = Color(0xFF808080);
  static const Color textDisabled = Color(0xFF5A5A5A);
  
  // Status
  static const Color success = green;
  static const Color warning = orange;
  static const Color error = red;
  static const Color info = cyan;
  
  // Font families
  static const String fontFamily = '.SF Pro Text';
  static const String fontFamilyMono = 'SF Mono';

  /// Text styles
  static TextStyle get displayLarge => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    color: textPrimary,
  );
  
  static TextStyle get displayMedium => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: textPrimary,
  );
  
  static TextStyle get titleLarge => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: textPrimary,
  );
  
  static TextStyle get titleMedium => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: textPrimary,
  );
  
  static TextStyle get titleSmall => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: textPrimary,
  );
  
  static TextStyle get bodyLarge => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: textPrimary,
    height: 1.5,
  );
  
  static TextStyle get bodyMedium => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: textPrimary,
    height: 1.4,
  );
  
  static TextStyle get bodySmall => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: textSecondary,
    height: 1.4,
  );
  
  static TextStyle get labelLarge => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    color: textSecondary,
  );
  
  static TextStyle get labelMedium => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    color: textMuted,
  );
  
  static TextStyle get labelSmall => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    color: textMuted,
  );
  
  static TextStyle get codeStyle => const TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: textPrimary,
    height: 1.5,
  );
  
  static TextStyle get codeSmall => const TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: textMuted,
  );

  /// Dark theme data for MaterialApp
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      
      colorScheme: ColorScheme.dark(
        primary: cyan,
        secondary: purple,
        tertiary: green,
        surface: surface,
        surfaceContainerHighest: surfaceLighter,
        error: red,
        onPrimary: background,
        onSecondary: background,
        onSurface: foreground,
        onError: foreground,
      ),
      
      scaffoldBackgroundColor: background,
      
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: titleMedium,
        toolbarHeight: 40,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      
      cardTheme: CardThemeData(
        color: surfaceLight,
        elevation: 0,
        margin: EdgeInsets.zero,
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
      
      textTheme: TextTheme(
        displayLarge: displayLarge,
        displayMedium: displayMedium,
        displaySmall: titleLarge,
        headlineLarge: titleLarge,
        headlineMedium: titleMedium,
        headlineSmall: titleSmall,
        titleLarge: titleLarge,
        titleMedium: titleMedium,
        titleSmall: titleSmall,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelLarge: labelLarge,
        labelMedium: labelMedium,
        labelSmall: labelSmall,
      ),
      
      iconTheme: const IconThemeData(
        color: textMuted,
        size: 18,
      ),
      
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cyan,
          foregroundColor: background,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: labelLarge.copyWith(color: background),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cyan,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: labelLarge,
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: labelLarge,
        ),
      ),
      
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          borderSide: const BorderSide(color: cyan, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: red),
        ),
        hintStyle: bodyMedium.copyWith(color: textMuted),
        labelStyle: labelMedium,
      ),
      
      listTileTheme: ListTileThemeData(
        iconColor: textMuted,
        textColor: foreground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        dense: true,
        minVerticalPadding: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceLight,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: border),
        ),
        textStyle: bodyMedium,
      ),
      
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceLighter,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: border),
        ),
        textStyle: bodySmall.copyWith(color: foreground),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 400),
      ),
      
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceLighter,
        contentTextStyle: bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: border),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),
      
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: cyan,
        linearTrackColor: border,
        circularTrackColor: border,
      ),
      
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(textMuted.withValues(alpha: 0.4)),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(6),
        thumbVisibility: WidgetStateProperty.all(false),
        interactive: true,
      ),
      
      tabBarTheme: TabBarThemeData(
        labelColor: cyan,
        unselectedLabelColor: textMuted,
        labelStyle: labelLarge,
        unselectedLabelStyle: labelLarge,
        indicatorColor: cyan,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: border,
      ),
      
      chipTheme: ChipThemeData(
        backgroundColor: surfaceLight,
        selectedColor: cyan.withValues(alpha: 0.2),
        labelStyle: labelMedium.copyWith(color: foreground),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: border),
        ),
      ),
      
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border),
        ),
        titleTextStyle: titleMedium,
        contentTextStyle: bodyMedium,
      ),
      
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
      ),
    );
  }
}

/// Extension for easy color access
extension MonokaiColors on BuildContext {
  Color get cyanAccent => MonokaiTheme.cyan;
  Color get greenAccent => MonokaiTheme.green;
  Color get yellowAccent => MonokaiTheme.yellow;
  Color get orangeAccent => MonokaiTheme.orange;
  Color get redAccent => MonokaiTheme.red;
  Color get purpleAccent => MonokaiTheme.purple;
  Color get pinkAccent => MonokaiTheme.pink;
  Color get surfaceColor => MonokaiTheme.surface;
  Color get surfaceLightColor => MonokaiTheme.surfaceLight;
  Color get backgroundColor => MonokaiTheme.background;
  Color get textPrimaryColor => MonokaiTheme.textPrimary;
  Color get textSecondaryColor => MonokaiTheme.textSecondary;
  Color get textMutedColor => MonokaiTheme.textMuted;
  Color get commentColor => MonokaiTheme.comment;
  Color get borderColor => MonokaiTheme.border;
  Color get dividerColor => MonokaiTheme.divider;
  Color get hoverColor => MonokaiTheme.hover;
  Color get activeColor => MonokaiTheme.active;
  Color get selectionColor => MonokaiTheme.selection;
}
