import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design system typography hierarchy for Miee.
/// Headline styles use `Plus Jakarta Sans` and body/label styles use `Inter`.
abstract class AppTypography {
  /// Editorial headline font: Playfair Display (Serif)
  static TextStyle get editorialHeadline => GoogleFonts.playfairDisplay(
        fontSize: 36,
        fontWeight: FontWeight.bold,
        height: 1.15,
        letterSpacing: -0.5,
      );

  /// Editorial hero headline: Playfair Display (Serif), 40px
  static TextStyle get editorialHero => GoogleFonts.playfairDisplay(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        height: 1.15,
        letterSpacing: -0.5,
      );

  /// Editorial small headline / greeting: Geist, 12px, tracking 2.0
  static TextStyle get editorialOverline => GoogleFonts.geist(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 2.0,
      );

  /// Display Large: Geist, 40px, bold
  static TextStyle get displayLarge => GoogleFonts.geist(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        height: 1.2,
        letterSpacing: -0.02 * 40,
      );

  /// Headline Large (Desktop): Playfair Display / Geist
  static TextStyle get headlineLarge => GoogleFonts.playfairDisplay(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.01 * 32,
      );

  /// Headline Large (Mobile): Playfair Display
  static TextStyle get headlineLargeMobile => GoogleFonts.playfairDisplay(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.21,
      );

  /// Headline Medium: Geist, 24px, bold 700
  static TextStyle get headlineMedium => GoogleFonts.geist(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.25,
      );

  /// Body Large: Geist, 18px, regular 400
  static TextStyle get bodyLarge => GoogleFonts.geist(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 1.55,
      );

  /// Body Medium: Geist, 16px, regular 400
  static TextStyle get bodyMedium => GoogleFonts.geist(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
      );

  /// Label Medium: Geist, 14px, semi-bold 600
  static TextStyle get labelMedium => GoogleFonts.geist(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.43,
        letterSpacing: 0.01 * 14,
      );

  /// Label Small: Geist, 12px, medium 500
  static TextStyle get labelSmall => GoogleFonts.geist(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.33,
        letterSpacing: 0.04 * 12,
      );
}
