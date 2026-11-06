import 'package:flutter/material.dart';

/// CyberNet brand — same palette family as the saiberwifi apps:
/// deep navy gradient, red accent, Cairo typeface, Arabic RTL.
///
/// Named AppColors because both feature sets living in this app
/// (CYB-05 client screens + CYB-07 agent screens) import it.
class AppColors {
  static const Color primary = Color(0xFF1E2D7D);
  static const Color primaryDark = Color(0xFF16235F);
  static const Color navy = Color(0xFF0D1640);
  static const Color accent = Color(0xFFE31E24);
  static const Color error = accent;
  static const Color cyan = Color(0xFF27C4F5);
  static const Color lightBlue = Color(0xFF4B7BEC);
  static const Color white = Colors.white;
  static const Color background = Color(0xFFF6F8FD);
  static const Color surface = background;
  static const Color card = Colors.white;
  static const Color inputBg = Color(0xFFF8F9FC);
  static const Color textDark = Color(0xFF0F1729);
  static const Color textGray = Color(0xFF8A93A6);
  static const Color textLight = Color(0xFFB0B9CC);
  static const Color divider = Color(0xFFEBEFF8);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color cardShadow = Color(0x14000000);

  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [navy, primary, Color(0xFF2E4BB0)],
  );

  static const LinearGradient simGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [Color(0xFF28348F), Color(0xFF121E5E)],
  );
}

/// Alias kept for the CYB-05 client screens.
typedef CyberColors = AppColors;

const String kFont = 'Cairo';

class CyberTheme {
  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        fontFamily: kFont,
        scaffoldBackgroundColor: CyberColors.surface,
        colorScheme: const ColorScheme.light(
          primary: CyberColors.primary,
          secondary: CyberColors.accent,
          surface: CyberColors.card,
          error: CyberColors.accent,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: CyberColors.primary,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: kFont,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: CyberColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: CyberColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: CyberColors.primary, width: 1.5),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: CyberColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(
              fontFamily: kFont,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: CyberColors.card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: CyberColors.divider),
          ),
        ),
      );
}
