import 'package:flutter/material.dart';

/// Design system elevation and shadow constants for Miee.
abstract class AppShadows {
  /// Low elevation shadow for standard cards: `0px 4px 20px rgba(0, 0, 0, 0.04)`
  static const BoxShadow low = BoxShadow(
    color: Color(0x0A000000), // rgba(0, 0, 0, 0.04)
    offset: Offset(0, 4),
    blurRadius: 20,
    spreadRadius: 0,
  );

  /// High elevation shadow for mini players and floating headers: `0px 8px 30px rgba(0, 0, 0, 0.08)`
  static const BoxShadow high = BoxShadow(
    color: Color(0x14000000), // rgba(0, 0, 0, 0.08)
    offset: Offset(0, 8),
    blurRadius: 30,
    spreadRadius: 0,
  );

  /// Highest elevation shadow for bottom sheets and large details: `0px 12px 40px rgba(0, 0, 0, 0.12)`
  static const BoxShadow highest = BoxShadow(
    color: Color(0x1F000000), // rgba(0, 0, 0, 0.12)
    offset: Offset(0, 12),
    blurRadius: 40,
    spreadRadius: 0,
  );

  // Lists of shadows to be applied directly in BoxDecoration

  static const List<BoxShadow> shadowLow = [low];
  static const List<BoxShadow> shadowHigh = [high];
  static const List<BoxShadow> shadowHighest = [highest];
}
