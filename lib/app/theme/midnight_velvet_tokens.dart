import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the Miee Desktop "Midnight Velvet & Warm Studio" visual specification.
/// Approved in MIEE_DESKTOP_MIDNIGHT_VELVET_DESIGN_SPEC.md.
class MidnightVelvetTokens {
  MidnightVelvetTokens._();

  // --- Surfaces & Canvas ---
  static const Color canvasBase = Color(0xFF121114);
  static const Color surfaceLayer1 = Color(0xBF18161C); // rgba(24, 22, 28, 0.75)
  static const Color surfaceCard = Color(0xA6201C26);   // rgba(32, 28, 38, 0.65)
  static const Color surfaceCardHover = Color(0xD92A2432); // rgba(42, 36, 50, 0.85)
  static const Color surfaceElevated = Color(0xBF282330);  // rgba(40, 35, 48, 0.75)
  static const Color surfaceOverlay = Color(0x990C0B0E);   // rgba(12, 11, 14, 0.60)

  // --- Physical Rim & Borders ---
  static const Color hairlineRim = Color(0x14FFEBF0);          // rgba(255, 235, 240, 0.08)
  static const Color hairlineRimHighlight = Color(0x2EFFEBF0); // rgba(255, 235, 240, 0.18)
  static const Color hairlineRimSubtle = Color(0x0AFFEBF0);    // rgba(255, 235, 240, 0.04)

  // --- Accents & Kinetics ---
  static const Color primaryEmber = Color(0xFFFF385C);
  static const Color primaryEmberDark = Color(0xFFD62B4C);
  static const Color amberChampagne = Color(0xFFF59E0B);
  static const Color studioGold = Color(0xFFD97706);
  static const Color emeraldStream = Color(0xFF10B981);

  // --- Ambient Glows ---
  static const Color glowEmberLow = Color(0x26FF385C); // rgba(255, 56, 92, 0.15)
  static const Color glowEmberMid = Color(0x59FF385C); // rgba(255, 56, 92, 0.35)
  static const Color glowAmberLow = Color(0x26F59E0B); // rgba(245, 158, 11, 0.15)

  // --- Text Colors ---
  static const Color textDisplay = Color(0xFFFAFAF8);
  static const Color textTitle = Color(0xFFF5F3EF);
  static const Color textSecondary = Color(0xFFA8A29E);
  static const Color textMuted = Color(0xFF78716C);
  static const Color textMono = Color(0xFFD6D3D1);

  // --- Dimensions ---
  static const double consoleRailWidth = 260.0;
  static const double telemetryHeaderHeight = 68.0;
  static const double masterDeckHeight = 88.0;
  static const double masterDeckBottomMargin = 18.0;
  static const double glassBlurSigma = 24.0;

  // --- Typography Styles ---
  static TextStyle get fontDisplayLarge => GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.035 * 32,
        color: textDisplay,
        height: 1.15,
      );

  static TextStyle get fontDisplayMedium => GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.03 * 24,
        color: textDisplay,
        height: 1.2,
      );

  static TextStyle get fontSectionTitle => GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.02 * 18,
        color: textTitle,
        height: 1.25,
      );

  static TextStyle get fontBodyMedium => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.01 * 14,
        color: textSecondary,
        height: 1.35,
      );

  static TextStyle get fontLabelSmall => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.05 * 11,
        color: textMuted,
        height: 1.2,
      );

  static TextStyle get fontMonoTimecode => GoogleFonts.jetBrainsMono(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.0,
        color: textMono,
      );

  static TextStyle get fontMonoTelemetry => GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.02 * 11,
        color: amberChampagne,
      );

  // --- Physical Box Decorations ---
  static BoxDecoration glassPanel({
    double radius = 16.0,
    Color surfaceColor = surfaceCard,
    Color borderColor = hairlineRim,
    List<BoxShadow>? shadows,
  }) {
    return BoxDecoration(
      color: surfaceColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor, width: 1.0),
      boxShadow: shadows ??
          [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 20.0,
              offset: const Offset(0, 8),
            ),
          ],
    );
  }

  static BoxDecoration emberButton({
    double radius = 24.0,
    bool isHovered = false,
  }) {
    return BoxDecoration(
      color: isHovered ? primaryEmber : primaryEmberDark,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: glowEmberMid,
          blurRadius: isHovered ? 18.0 : 12.0,
          spreadRadius: isHovered ? 1.0 : 0.0,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  // --- Complete Material 3 Dark Theme for Desktop Midnight Velvet ---
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: canvasBase,
        canvasColor: canvasBase,
        cardColor: surfaceCard,
        dialogBackgroundColor: surfaceElevated,
        colorScheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: primaryEmber,
          onPrimary: Colors.white,
          secondary: amberChampagne,
          onSecondary: Colors.black,
          surface: surfaceLayer1,
          onSurface: textDisplay,
          surfaceContainer: surfaceCard,
          surfaceContainerHigh: surfaceElevated,
          error: Color(0xFFEF4444),
          onError: Colors.white,
          outline: hairlineRim,
          outlineVariant: hairlineRimSubtle,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: canvasBase,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: textDisplay),
        ),
        textTheme: TextTheme(
          displayLarge: fontDisplayLarge,
          displayMedium: fontDisplayMedium,
          titleLarge: fontSectionTitle,
          titleMedium: fontSectionTitle.copyWith(fontSize: 16),
          bodyLarge: fontBodyMedium.copyWith(color: textDisplay, fontSize: 16),
          bodyMedium: fontBodyMedium,
          labelMedium: fontLabelSmall.copyWith(fontSize: 12),
          labelSmall: fontLabelSmall,
        ),
      );
}
