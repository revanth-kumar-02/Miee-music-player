import 'package:flutter/material.dart';

/// Design system color constants for Miee.
/// Colors are defined using static constants matching the Stitch tokens.
abstract class AppColors {
  // ── Exact Reference Design Palette ─────────────────────────────────────────
  /// Vanilla Cream canvas background: `#F8F1E8`
  static const Color vanillaCream = Color(0xFFF8F1E8);

  /// Cocoa Plum dark sidebar, player surface, dark accents: `#3A252B`
  static const Color cocoaPlum = Color(0xFF3A252B);

  /// Dusty Rose selected states, playback controls, brand accents: `#D78D9B`
  static const Color dustyRose = Color(0xFFD78D9B);

  /// Soft Clay featured content, secondary accents: `#E9C9B7`
  static const Color softClay = Color(0xFFE9C9B7);

  /// Oat Beige dividers, subtle borders, card outlines: `#E7DED5`
  static const Color oatBeige = Color(0xFFE7DED5);

  /// Pure White surfaces and high-contrast text: `#FFFFFF`
  static const Color white = Color(0xFFFFFFFF);

  /// Muted Mauve secondary text and subtle iconography: `#75656A`
  static const Color mutedMauve = Color(0xFF75656A);

  // ── Semantic Token Mappings ────────────────────────────────────────────────
  /// Base canvas background: Vanilla Cream
  static const Color background = vanillaCream;

  /// Surface dim / border tint
  static const Color surfaceDim = oatBeige;

  /// Pure white / bright surface
  static const Color surfaceBright = white;

  /// Elevated surface lowest
  static const Color surfaceContainerLowest = white;

  /// Surface container low (warm ivory tint)
  static const Color surfaceContainerLow = Color(0xFFFDFBF7);

  /// Standard surface container
  static const Color surfaceContainer = Color(0xFFF3EBE1);

  /// Surface container high
  static const Color surfaceContainerHigh = oatBeige;

  /// Surface container highest: Soft Clay
  static const Color surfaceContainerHighest = softClay;

  /// Primary text / main typography color: Cocoa Plum
  static const Color onSurface = cocoaPlum;
  static const Color onBackground = cocoaPlum;

  /// Secondary text / metadata color: Muted Mauve
  static const Color onSurfaceVariant = mutedMauve;

  /// Primary action / accent color: Dusty Rose
  static const Color primary = dustyRose;

  /// Secondary brand color: Cocoa Plum
  static const Color secondary = cocoaPlum;

  /// Text on primary elements: White
  static const Color onPrimary = white;
  static const Color onSecondary = white;

  /// Active accent: Dusty Rose
  static const Color accentIndigo = dustyRose;

  /// Outline border color: Oat Beige
  static const Color outline = oatBeige;

  /// Light outline border color: soft beige
  static const Color outlineVariant = Color(0xFFF0EAE2);

  /// Inverse surface (Cocoa Plum dark surfaces)
  static const Color inverseSurface = cocoaPlum;

  /// Light text on inverse surface: Vanilla Cream
  static const Color inverseOnSurface = vanillaCream;

  /// Error color
  static const Color error = Color(0xFFBA1A1A);

  /// Error container background
  static const Color errorContainer = Color(0xFFFFDAD6);

  /// Text on error container
  static const Color onError = white;

  /// Semi-transparent overlays
  static const Color scrim = Color(0x663A252B);
}
