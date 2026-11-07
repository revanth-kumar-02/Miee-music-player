import 'package:flutter/material.dart';

/// Design system color constants for Miee — Nordic Cobalt Identity.
/// 
/// Strictly reproduces the locked Nordic Cobalt reference design:
/// - Chalk White: `#F6F6F4`
/// - Electric Cobalt: `#1D4ED8`
/// - Cobalt Blue: `#2563EB`
/// - Dense Obsidian: `#131416`
/// - Pale Concrete: `#E8E8E2`
/// - Industrial Steel: `#64748B`
abstract class AppColors {
  // ── Locked Nordic Cobalt Palette Tokens ────────────────────────────────────
  /// Chalk White canvas background: `#F6F6F4`
  static const Color chalkWhite = Color(0xFFF6F6F4);

  /// Electric Cobalt primary brand accent: `#1D4ED8`
  static const Color electricCobalt = Color(0xFF1D4ED8);

  /// Cobalt Blue alternate primary / hover / highlight: `#2563EB`
  static const Color cobaltBlue = Color(0xFF2563EB);

  /// Dense Obsidian deep typography, dark cards, icons: `#131416`
  static const Color denseObsidian = Color(0xFF131416);

  /// Pale Concrete secondary cards, unselected pills, search field: `#E8E8E2`
  static const Color paleConcrete = Color(0xFFE8E8E2);

  /// Industrial Steel secondary text, unselected icons, metadata: `#64748B`
  static const Color industrialSteel = Color(0xFF64748B);

  /// Pure White for elevated card surfaces, dock backing: `#FFFFFF`
  static const Color white = Color(0xFFFFFFFF);

  // ── Backward-Compatible Semantic Mappings ──────────────────────────────────
  /// Legacy mapping for vanillaCream -> Chalk White
  static const Color vanillaCream = chalkWhite;

  /// Legacy mapping for cocoaPlum -> Dense Obsidian
  static const Color cocoaPlum = denseObsidian;

  /// Legacy mapping for dustyRose -> Electric Cobalt
  static const Color dustyRose = electricCobalt;

  /// Legacy mapping for softClay -> Pale Concrete
  static const Color softClay = paleConcrete;

  /// Legacy mapping for oatBeige -> Pale Concrete / divider
  static const Color oatBeige = Color(0xFFE2E2DC);

  /// Legacy mapping for mutedMauve -> Industrial Steel
  static const Color mutedMauve = industrialSteel;

  // ── Semantic Token Mappings ────────────────────────────────────────────────
  /// Base canvas background: Chalk White
  static const Color background = chalkWhite;

  /// Surface dim / border tint
  static const Color surfaceDim = Color(0xFFDFDFD8);

  /// Pure white / bright surface
  static const Color surfaceBright = white;

  /// Elevated surface lowest
  static const Color surfaceContainerLowest = white;

  /// Surface container low (Chalk White tint)
  static const Color surfaceContainerLow = Color(0xFFF9F9F8);

  /// Standard surface container: Pale Concrete
  static const Color surfaceContainer = paleConcrete;

  /// Surface container high
  static const Color surfaceContainerHigh = Color(0xFFE2E2DC);

  /// Surface container highest: Pale Concrete
  static const Color surfaceContainerHighest = paleConcrete;

  /// Primary text / main typography color: Dense Obsidian
  static const Color onSurface = denseObsidian;
  static const Color onBackground = denseObsidian;

  /// Secondary text / metadata color: Industrial Steel
  static const Color onSurfaceVariant = industrialSteel;

  /// Primary action / accent color: Electric Cobalt
  static const Color primary = electricCobalt;

  /// Secondary brand color: Cobalt Blue
  static const Color secondary = cobaltBlue;

  /// Text on primary elements: White
  static const Color onPrimary = white;
  static const Color onSecondary = white;

  /// Active accent: Electric Cobalt
  static const Color accentIndigo = electricCobalt;

  /// Outline border color: Pale Concrete / hairline
  static const Color outline = Color(0xFFE2E2DC);

  /// Light outline border color
  static const Color outlineVariant = Color(0xFFEDEDE8);

  /// Inverse surface (Dense Obsidian dark surfaces)
  static const Color inverseSurface = denseObsidian;

  /// Light text on inverse surface: Chalk White
  static const Color inverseOnSurface = chalkWhite;

  /// Error color
  static const Color error = Color(0xFFBA1A1A);

  /// Error container background
  static const Color errorContainer = Color(0xFFFFDAD6);

  /// Text on error container
  static const Color onError = white;

  /// Semi-transparent overlays
  static const Color scrim = Color(0x66131416);
}
