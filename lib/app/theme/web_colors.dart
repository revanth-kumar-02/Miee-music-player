import 'package:flutter/material.dart';

/// Dedicated color system for Miee Web & Desktop viewports.
/// 
/// Strictly isolated from mobile/Android [AppColors] per architectural rules:
/// mobile and desktop palettes are decoupled and preserved independently.
/// Based on the "Editorial Tactility" design system in `design_source/miee_design_system/`.
abstract class MieeWebColors {
  // ── 1. Paper Canvases & Surfaces ───────────────────────────────────────────
  /// Chalk base paper canvas: `#FAF9F7`
  static const Color surface = Color(0xFFFAF9F7);

  /// Linen paper for sidebar, modal trays, elevated backgrounds: `#F4F3F1`
  static const Color surfaceLow = Color(0xFFF4F3F1);

  /// Standard surface container: `#EFEEEC`
  static const Color surfaceContainer = Color(0xFFEFEEEC);

  /// Surface container high (hover states, pill backgrounds): `#E9E8E6`
  static const Color surfaceContainerHigh = Color(0xFFE9E8E6);

  /// Surface container highest (badges, unplayed waveform, tags): `#E3E2E0`
  static const Color surfaceContainerHighest = Color(0xFFE3E2E0);

  /// Pure white for cards, quick access tiles, bottom dock: `#FFFFFF`
  static const Color surfaceLowest = Color(0xFFFFFFFF);

  /// Dim surface for backdrop scrims: `#DADAD8`
  static const Color surfaceDim = Color(0xFFDADAD8);

  // ── 2. Editorial Typography & Contrast ─────────────────────────────────────
  /// Deep charcoal primary ink typography: `#1A1C1B`
  static const Color onSurface = Color(0xFF1A1C1B);

  /// Muted dust secondary text, artists, metadata: `#564243`
  static const Color onSurfaceVariant = Color(0xFF564243);

  /// Intense ink-black for main track titles: `#1A0F12`
  static const Color textDark = Color(0xFF1A0F12);

  /// Inverse surface for high-contrast dark pills: `#2F3130`
  static const Color inverseSurface = Color(0xFF2F3130);

  /// Inverse text on dark pills: `#F1F1EF`
  static const Color inverseOnSurface = Color(0xFFF1F1EF);

  // ── 3. Subtle Hairline Borders & Rules ─────────────────────────────────────
  /// Mid-tone hairline outline for metadata chips & icons: `#897173`
  static const Color outline = Color(0xFF897173);

  /// Delicate hairline rule for dividers and structural borders: `#DDC0C1`
  static const Color outlineVariant = Color(0xFFDDC0C1);

  /// Hairline border color for desktop cards and grids: `#E2DFD9`
  static const Color subtleBorder = Color(0xFFE2DFD9);

  // ── 4. Brand Anchors & Tactile Controls ────────────────────────────────────
  /// Deep vintage wine brand background: `#4B0014`
  static const Color primary = Color(0xFF4B0014);

  /// Bordeaux Accent (signature active pills, main play/pause deck): `#6E0D25`
  static const Color primaryContainer = Color(0xFF6E0D25);

  /// Text on primary elements: Pure White `#FFFFFF`
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// Secondary text on primary elements: `#F77788`
  static const Color onPrimaryContainer = Color(0xFFF77788);

  // ── 5. Punch Accents & Dynamic States ──────────────────────────────────────
  /// Crimson for liked heart states, active tags: `#BA0032`
  static const Color secondary = Color(0xFFBA0032);

  /// Notification badges, active indicator chips: `#E41944`
  static const Color secondaryContainer = Color(0xFFE41944);

  /// Text on secondary: Pure White `#FFFFFF`
  static const Color onSecondary = Color(0xFFFFFFFF);

  /// Razor-sharp neon crimson highlight (live recording dot, lossless badge): `#FF3355`
  static const Color punch = Color(0xFFFF3355);

  // ── 6. Waveform Audio Colors ───────────────────────────────────────────────
  /// Bordeaux played audio waveform bars: `#6E0D25`
  static const Color waveformPlayed = Color(0xFF6E0D25);

  /// Taupe-grey unplayed audio waveform bars: `#D5CDD0`
  static const Color waveformNeutral = Color(0xFFD5CDD0);

  // ── 7. Extended Editorial Tokens ───────────────────────────────────────────
  /// Deep carbon dark surface for media tags & chips: `#22211E`
  static const Color tertiary = Color(0xFF22211E);

  /// Light rose tint for active icons & pills: `#FFDADC`
  static const Color primaryFixed = Color(0xFFFFDADC);

  /// Soft pink container for dynamic mixes: `#FFDADA`
  static const Color secondaryFixed = Color(0xFFFFDADA);
}
