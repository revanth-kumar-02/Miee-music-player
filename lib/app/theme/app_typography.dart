import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design system typography hierarchy for Miee.
/// Headline styles use `Plus Jakarta Sans` and body/label styles use `Inter`.
abstract class AppTypography {
  /// Display Large: `Plus Jakarta Sans`, 40px, bold 800, tracking -2%
  static TextStyle get displayLarge => GoogleFonts.plusJakartaSans(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        height: 1.2, // 48px line height
        letterSpacing: -0.02 * 40,
      );

  /// Headline Large (Desktop): `Plus Jakarta Sans`, 32px, bold 700, tracking -1%
  static TextStyle get headlineLarge => GoogleFonts.plusJakartaSans(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 1.25, // 40px line height
        letterSpacing: -0.01 * 32,
      );

  /// Headline Large (Mobile): `Plus Jakarta Sans`, 28px, bold 700
  static TextStyle get headlineLargeMobile => GoogleFonts.plusJakartaSans(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.21, // 34px line height
      );

  /// Headline Medium: `Plus Jakarta Sans`, 24px, bold 700
  static TextStyle get headlineMedium => GoogleFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.25, // 30px line height
      );

  /// Body Large: `Inter`, 18px, regular 400
  static TextStyle get bodyLarge => GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 1.55, // 28px line height
      );

  /// Body Medium: `Inter`, 16px, regular 400
  static TextStyle get bodyMedium => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5, // 24px line height
      );

  /// Label Medium: `Inter`, 14px, semi-bold 600, tracking 1%
  static TextStyle get labelMedium => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.43, // 20px line height
        letterSpacing: 0.01 * 14,
      );

  /// Label Small: `Inter`, 12px, medium 500, tracking 4%
  static TextStyle get labelSmall => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.33, // 16px line height
        letterSpacing: 0.04 * 12,
      );
}
