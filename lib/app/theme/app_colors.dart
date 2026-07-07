import 'package:flutter/material.dart';

/// Design system color constants for Miee.
/// Colors are defined using static constants matching the Stitch tokens.
abstract class AppColors {
  /// Base background canvas: `#fcf8f8`
  static const Color background = Color(0xFFFCF8F8);

  /// Surface dim: `#ddd9d9`
  static const Color surfaceDim = Color(0xFFDDD9D9);

  /// Surface bright: `#fcf8f8`
  static const Color surfaceBright = Color(0xFFFCF8F8);

  /// Elevated surface lowest: `#ffffff`
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);

  /// Surface container low: `#f6f3f2`
  static const Color surfaceContainerLow = Color(0xFFF6F3F2);

  /// Standard surface container: `#f1edec`
  static const Color surfaceContainer = Color(0xFFF1EDEC);

  /// Surface container high: `#ebe7e7`
  static const Color surfaceContainerHigh = Color(0xFFEBE7E7);

  /// Surface container highest: `#e5e2e1`
  static const Color surfaceContainerHighest = Color(0xFFE5E2E1);

  /// Primary text / main color: `#1c1b1b` (softened black)
  static const Color onSurface = Color(0xFF1C1B1B);
  static const Color onBackground = Color(0xFF1C1B1B);

  /// Secondary text / metadata color: `#444748` (medium gray)
  static const Color onSurfaceVariant = Color(0xFF444748);

  /// Slate gray primary brand color: `#5d5f5f`
  static const Color primary = Color(0xFF5D5F5F);

  /// Slate gray secondary brand color: `#5d5f5f`
  static const Color secondary = Color(0xFF5D5F5F);

  /// Text on primary / secondary elements: `#ffffff`
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSecondary = Color(0xFFFFFFFF);

  /// Brand deep indigo active/functional accent: `#3F51B5`
  static const Color accentIndigo = Color(0xFF3F51B5);

  /// Outline border color: `#747878`
  static const Color outline = Color(0xFF747878);

  /// Light outline border color: `#c4c7c8`
  static const Color outlineVariant = Color(0xFFC4C7C8);

  /// Dark inverse surface: `#313030`
  static const Color inverseSurface = Color(0xFF313030);

  /// Light text on inverse surface: `#f4f0ef`
  static const Color inverseOnSurface = Color(0xFFF4F0EF);

  /// Error color: `#ba1a1a`
  static const Color error = Color(0xFFBA1A1A);

  /// Error container background: `#ffdad6`
  static const Color errorContainer = Color(0xFFFFDAD6);

  /// Text on error container: `#ffffff`
  static const Color onError = Color(0xFFFFFFFF);

  /// Semi-transparent overlays
  static const Color scrim = Color(0x99000000);
}
