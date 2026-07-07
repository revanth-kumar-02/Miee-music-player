import 'package:flutter/material.dart';

/// Design system border corner radius constants for Miee.
abstract class AppRadius {
  /// Small: 4px - Checkboxes, switches
  static const double sm = 4.0;

  /// Medium: 8px - Artwork grids, track highlights
  static const double md = 8.0;

  /// Large: 12px - Bento grids, scroll cards, CONTINUE LISTENING card
  static const double lg = 12.0;

  /// Extra Large: 16px - Standard details cards
  static const double xl = 16.0;

  /// Double Extra Large: 24px - Mini Player, Bottom Navigation Bar
  static const double xxl = 24.0;

  /// Sheet Top Rounded Corners: 32px - Queue Bottom Sheet
  static const double sheet = 32.0;

  /// Large Artwork: 32px - Now Playing Cover Artwork
  static const double largeArtwork = 32.0;

  /// Page Frame: 40px - Main outer page frames
  static const double frame = 40.0;

  /// Full Pill Corner: 9999px - Input fields, search bars, primary buttons
  static const double full = 9999.0;

  // -- Predefined BorderRadius helpers --

  static final BorderRadius radiusSm = BorderRadius.circular(sm);
  static final BorderRadius radiusMd = BorderRadius.circular(md);
  static final BorderRadius radiusLg = BorderRadius.circular(lg);
  static final BorderRadius radiusXl = BorderRadius.circular(xl);
  static final BorderRadius radiusXxl = BorderRadius.circular(xxl);
  static final BorderRadius radiusFull = BorderRadius.circular(full);

  /// Top rounded corner radius for bottom sheets: 32px
  static const BorderRadius radiusSheetTop = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );

  /// Top rounded corner radius for navigation bars: 24px
  static const BorderRadius radiusNavTop = BorderRadius.vertical(
    top: Radius.circular(xxl),
  );
}
