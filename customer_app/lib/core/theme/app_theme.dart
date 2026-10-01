import 'package:flutter/material.dart';

class AppColors {
  static const Color primary     = Color(0xFF1E2D7D);
  static const Color primaryDark = Color(0xFF16235F);
  static const Color accent      = Color(0xFFE31E24);
  static const Color lightBlue   = Color(0xFF4B7BEC);
  static const Color white       = Color(0xFFFFFFFF);
  static const Color background  = Color(0xFFFFFFFF);
  static const Color surface     = Color(0xFFFFFFFF);
  static const Color inputBg     = Color(0xFFF8F9FC);
  static const Color textDark    = Color(0xFF0F1729);
  static const Color textGray    = Color(0xFF8A93A6);
  static const Color textLight   = Color(0xFFB0B9CC);
  static const Color divider     = Color(0xFFEBEFF8);
  static const Color success     = Color(0xFF10B981);
  static const Color warning     = Color(0xFFF59E0B);
  static const Color error       = Color(0xFFE31E24);
  static const Color cardShadow  = Color(0x14000000);
}

const String _font = 'Cairo';

class AppTheme {
  static ThemeData get theme {
    const tt = TextTheme(
      displayLarge:   TextStyle(fontFamily: _font, color: AppColors.textDark),
      displayMedium:  TextStyle(fontFamily: _font, color: AppColors.textDark),
      displaySmall:   TextStyle(fontFamily: _font, color: AppColors.textDark),
      headlineLarge:  TextStyle(fontFamily: _font, color: AppColors.textDark),
      headlineMedium: TextStyle(fontFamily: _font, color: AppColors.textDark),
      headlineSmall:  TextStyle(fontFamily: _font, color: AppColors.textDark),
      titleLarge:     TextStyle(fontFamily: _font, color: AppColors.textDark, fontWeight: FontWeight.w600),
      titleMedium:    TextStyle(fontFamily: _font, color: AppColors.textDark),
      titleSmall:     TextStyle(fontFamily: _font, color: AppColors.textDark),
      bodyLarge:      TextStyle(fontFamily: _font, color: AppColors.textDark),
      bodyMedium:     TextStyle(fontFamily: _font, color: AppColors.textDark),
      bodySmall:      TextStyle(fontFamily: _font, color: AppColors.textGray),
      labelLarge:     TextStyle(fontFamily: _font, color: AppColors.textDark),
      labelMedium:    TextStyle(fontFamily: _font, color: AppColors.textDark),
      labelSmall:     TextStyle(fontFamily: _font, color: AppColors.textGray),
    );

    return ThemeData(
      useMaterial3: false,
      fontFamily: _font,
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
      textTheme: tt,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: _font,
          color: AppColors.textDark,
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
          textStyle: const TextStyle(fontFamily: _font, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: _font, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.divider, width: 1.2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.accent)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.accent, width: 2)),
        labelStyle: const TextStyle(fontFamily: _font, color: AppColors.textGray, fontSize: 14),
        hintStyle:  const TextStyle(fontFamily: _font, color: AppColors.textLight, fontSize: 14),
        floatingLabelStyle: const TextStyle(fontFamily: _font, color: AppColors.primary, fontSize: 13),
        prefixIconColor: AppColors.textGray,
        suffixIconColor: AppColors.textGray,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shadowColor: AppColors.cardShadow,
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
