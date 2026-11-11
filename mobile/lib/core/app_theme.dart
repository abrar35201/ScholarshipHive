import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// "Ocean" — the same teal-and-ink identity as the web admin panel (same
// tokens, same Sora/Outfit pairing), so the app and the console read as one
// product rather than two differently-branded halves.
class AppColors {
  static const primary = Color(0xFF0891B2);
  static const primaryDark = Color(0xFF0E7490);
  static const primarySoft = Color(0xFFECFAFD);
  static const accent = Color(0xFFD97706);
  static const accentDark = Color(0xFFB45F04);
  static const success = Color(0xFF059669);
  static const danger = Color(0xFFDC2626);
  static const warning = Color(0xFFD97706);
  static const alt = Color(0xFF7C5CBF);
  static const ink = Color(0xFF062026);
  static const inkMuted = Color(0xFF5F8189);
  static const surfaceLight = Color(0xFFF7FCFD);
  static const surfaceDark = Color(0xFF0B2E36);
  static const cardDark = Color(0xFF0E3B45);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary, Color(0xFF22C3E6)],
  );

  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentDark],
  );
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: Colors.white,
        error: AppColors.danger,
      ),
      scaffoldBackgroundColor: AppColors.surfaceLight,
      useMaterial3: true,
    );

    final headlineTheme = GoogleFonts.soraTextTheme(base.textTheme);
    final bodyTheme = GoogleFonts.outfitTextTheme(base.textTheme);

    return base.copyWith(
      textTheme: bodyTheme.copyWith(
        displayLarge: headlineTheme.displayLarge?.copyWith(color: AppColors.ink),
        displayMedium: headlineTheme.displayMedium?.copyWith(color: AppColors.ink),
        displaySmall: headlineTheme.displaySmall?.copyWith(color: AppColors.ink),
        headlineLarge: headlineTheme.headlineLarge?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
        headlineMedium: headlineTheme.headlineMedium?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
        headlineSmall: headlineTheme.headlineSmall?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
        titleLarge: headlineTheme.titleLarge?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
        titleMedium: headlineTheme.titleMedium?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
        titleSmall: headlineTheme.titleSmall?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
        bodyLarge: bodyTheme.bodyLarge?.copyWith(color: AppColors.ink),
        bodyMedium: bodyTheme.bodyMedium?.copyWith(color: AppColors.ink),
        bodySmall: bodyTheme.bodySmall?.copyWith(color: AppColors.inkMuted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
        centerTitle: false,
        titleTextStyle: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.primarySoft, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          side: const BorderSide(color: AppColors.primarySoft, width: 1.4),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.primarySoft,
        labelStyle: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
        shape: const StadiumBorder(),
        side: BorderSide.none,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFEFF8FA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        labelStyle: GoogleFonts.outfit(color: AppColors.inkMuted, fontSize: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.primarySoft, thickness: 1),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.inkMuted,
        indicatorColor: AppColors.primary,
        labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
    );
  }
}
