import 'package:flutter/material.dart';

class AppColors {
  // ── Brand palette (exact from logo) ──────────────────────────
  static const Color primary    = Color(0xFF1E2D7D); // deep navy blue
  static const Color accent     = Color(0xFFE31E24); // brand red
  static const Color lightBlue  = Color(0xFF4B7BEC); // "SAIBER WIFI" text blue
  static const Color primaryDark = Color(0xFF16235F); // darker navy for gradients

  // ── Surfaces ─────────────────────────────────────────────────
  static const Color white      = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFFFFFFF); // pure white app background
  static const Color surface    = Color(0xFFFFFFFF);
  static const Color cardBg     = Color(0xFFFFFFFF);
  static const Color inputBg    = Color(0xFFF8F9FC); // very subtle blue-tinted white

  // ── Text ─────────────────────────────────────────────────────
  static const Color textDark   = Color(0xFF0F1729); // near-black navy
  static const Color textGray   = Color(0xFF8A93A6);
  static const Color textLight  = Color(0xFFB0B9CC);

  // ── Utility ──────────────────────────────────────────────────
  static const Color divider    = Color(0xFFEBEFF8);
  static const Color success    = Color(0xFF10B981);
  static const Color warning    = Color(0xFFF59E0B);
  static const Color error      = Color(0xFFE31E24); // use brand red for error too
}

const String _fontFamily = 'Cairo';

class AppTheme {
  static ThemeData get theme {
    const textTheme = TextTheme(
      displayLarge:  TextStyle(fontFamily: _fontFamily, color: AppColors.textDark),
      displayMedium: TextStyle(fontFamily: _fontFamily, color: AppColors.textDark),
      displaySmall:  TextStyle(fontFamily: _fontFamily, color: AppColors.textDark),
      headlineLarge: TextStyle(fontFamily: _fontFamily, color: AppColors.textDark),
      headlineMedium:TextStyle(fontFamily: _fontFamily, color: AppColors.textDark),
      headlineSmall: TextStyle(fontFamily: _fontFamily, color: AppColors.textDark),
      titleLarge:    TextStyle(fontFamily: _fontFamily, color: AppColors.textDark, fontWeight: FontWeight.w600),
      titleMedium:   TextStyle(fontFamily: _fontFamily, color: AppColors.textDark),
      titleSmall:    TextStyle(fontFamily: _fontFamily, color: AppColors.textDark),
      bodyLarge:     TextStyle(fontFamily: _fontFamily, color: AppColors.textDark),
      bodyMedium:    TextStyle(fontFamily: _fontFamily, color: AppColors.textDark),
      bodySmall:     TextStyle(fontFamily: _fontFamily, color: AppColors.textGray),
      labelLarge:    TextStyle(fontFamily: _fontFamily, color: AppColors.textDark),
      labelMedium:   TextStyle(fontFamily: _fontFamily, color: AppColors.textDark),
      labelSmall:    TextStyle(fontFamily: _fontFamily, color: AppColors.textGray),
    );

    return ThemeData(
      useMaterial3: false,
      fontFamily: _fontFamily,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: Colors.white,
        surfaceTint: Colors.transparent,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.textDark,
        onError: Colors.white,
      ),
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: Colors.white,
      canvasColor: Colors.white,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          color: AppColors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: _fontFamily, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: _fontFamily, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.divider, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
        labelStyle: const TextStyle(fontFamily: _fontFamily, color: AppColors.textGray, fontSize: 14),
        hintStyle:  const TextStyle(fontFamily: _fontFamily, color: AppColors.textLight, fontSize: 14),
        floatingLabelStyle: const TextStyle(fontFamily: _fontFamily, color: AppColors.primary, fontSize: 13),
        prefixIconColor: AppColors.textGray,
        suffixIconColor: AppColors.textGray,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textGray,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
}
