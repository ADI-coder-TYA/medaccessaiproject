import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // --- 1. Primary Clinical Palette ---
  static const Color primaryDarkBlue = Color(0xFF0F172A); // Deep Clinical Navy
  static const Color cardDarkNavy = Color(0xFF1E293B);    // Standard Dark Slate Card
  static const Color primaryBrand = Color(0xFF0D9488);    // Deep Clinical Teal
  static const Color accentTeal = Color(0xFF14B8A6);      // Cyber Teal
  static const Color accentCyan = Color(0xFF0EA5E9);      // Medical Sky Blue
  static const Color accentMint = Color(0xFF5EEAD4);      // High-Visibility Mint
  static const Color surfaceLight = Color(0xFFF8FAFC);    // Soft Slate Background
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color surfaceSlate = Color(0xFFF8FAFC);
  static const Color primaryDark = Color(0xFF0F766E);
  static const Color primaryContainer = Color(0xFFCCFBF1);
  static const Color accentSky = Color(0xFF38BDF8);

  // --- 2. Typography & Neutral Text Colors ---
  static const Color textDark = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textSoftGray = Color(0xFF94A3B8);
  static const Color borderSubtle = Color(0xFFE2E8F0);
  static const Color darkCardBorder = Color(0x1FFFFFFF); // Colors.white.withOpacity(0.08)

  // --- 3. Unified Status Colors ---
  static const Color successEmerald = Color(0xFF10B981);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color dangerRose = Color(0xFFF43F5E);
  static const Color emergencyRed = Color(0xFFEF4444);

  // ESI Triage Colors
  static const Color esi1Critical = Color(0xFFDC2626);
  static const Color esi2Emergent = Color(0xFFEA580C);
  static const Color esi3Urgent = Color(0xFFD97706);
  static const Color routine = Color(0xFF16A34A);

  // --- 4. Card & Container Standards ---
  static const double radiusValue = 16.0;
  static final BorderRadius standardRadius = BorderRadius.circular(radiusValue);
  static const EdgeInsets standardPadding = EdgeInsets.all(16.0);

  static BoxDecoration darkCardDecoration({
    Color? color,
    BorderRadius? borderRadius,
    Border? border,
  }) {
    return BoxDecoration(
      color: color ?? cardDarkNavy,
      borderRadius: borderRadius ?? standardRadius,
      border: border ?? Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.0),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  static BoxDecoration lightCardDecoration({
    Color? color,
    BorderRadius? borderRadius,
    Border? border,
  }) {
    return BoxDecoration(
      color: color ?? surfaceWhite,
      borderRadius: borderRadius ?? standardRadius,
      border: border ?? Border.all(color: borderSubtle, width: 1.0),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  // --- 5. ESI Helpers ---
  static Color getEsiColor(String? esiLevel) {
    if (esiLevel == null) return routine;
    final level = esiLevel.toUpperCase();
    if (level.contains('1') || level.contains('CRITICAL')) return esi1Critical;
    if (level.contains('2') || level.contains('EMERGENT')) return esi2Emergent;
    if (level.contains('3') || level.contains('URGENT')) return esi3Urgent;
    return routine;
  }

  static String getEsiLabel(String? esiLevel) {
    if (esiLevel == null) return 'Routine / Standard Care';
    final level = esiLevel.toUpperCase();
    if (level.contains('1') || level.contains('CRITICAL')) return 'ESI-1: Resuscitation / Critical (100% Relief)';
    if (level.contains('2') || level.contains('EMERGENT')) return 'ESI-2: Emergent / Acute Distress (80% Relief)';
    if (level.contains('3') || level.contains('URGENT')) return 'ESI-3: Urgent / Moderate Need (50% Relief)';
    return 'Routine: Standard Care (30% Relief)';
  }

  // --- 6. Themes ---
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    primaryColor: primaryBrand,
    scaffoldBackgroundColor: surfaceLight,
    cardColor: surfaceWhite,
    colorScheme: const ColorScheme.light(
      primary: primaryBrand,
      primaryContainer: primaryContainer,
      secondary: accentCyan,
      error: emergencyRed,
      surface: surfaceWhite,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: textDark,
    ),
    textTheme: GoogleFonts.outfitTextTheme().copyWith(
      titleLarge: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: textDark),
      titleMedium: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: textDark),
      bodyLarge: GoogleFonts.inter(fontSize: 14, color: textDark),
      bodyMedium: GoogleFonts.inter(fontSize: 13, color: textMuted),
      labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: textMuted),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surfaceWhite,
      foregroundColor: textDark,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: textDark),
    ),
    cardTheme: CardThemeData(
      color: surfaceWhite,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: standardRadius,
        side: const BorderSide(color: borderSubtle),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surfaceWhite,
      selectedItemColor: primaryBrand,
      unselectedItemColor: textSoftGray,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBrand,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: standardRadius),
      ),
    ),
    brightness: Brightness.light,
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    primaryColor: primaryBrand,
    scaffoldBackgroundColor: primaryDarkBlue,
    colorScheme: const ColorScheme.dark(
      primary: primaryBrand,
      primaryContainer: Color(0xFF134E4A),
      secondary: accentCyan,
      error: dangerRose,
      surface: cardDarkNavy,
      onPrimary: Colors.white,
      onSecondary: Colors.black,
      onSurface: Color(0xFFF1F5F9),
    ),
    textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme).copyWith(
      titleLarge: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
      titleMedium: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
      bodyLarge: GoogleFonts.inter(fontSize: 14, color: Colors.white),
      bodyMedium: GoogleFonts.inter(fontSize: 13, color: textSoftGray),
      labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: textSoftGray),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryDarkBlue,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: cardDarkNavy,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: standardRadius,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBrand,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: standardRadius),
      ),
    ),
    brightness: Brightness.dark,
  );
}
