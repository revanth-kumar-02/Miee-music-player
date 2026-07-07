import 'package:flutter/material.dart';

/// Design system layout spacing constants for Miee.
/// Utilizes a standard 4px base-unit spacing scale.
abstract class AppSpacing {
  /// Base unit: 4px
  static const double unit = 4.0;

  /// Extra small: 4px
  static const double xs = 4.0;

  /// Small: 8px
  static const double sm = 8.0;

  /// Medium: 16px
  static const double md = 16.0;

  /// Large: 24px
  static const double lg = 24.0;

  /// Extra large: 32px
  static const double xl = 32.0;

  /// Double extra large: 48px
  static const double xxl = 48.0;

  /// Outer horizontal mobile margins: 20px
  static const double marginMobile = 20.0;

  /// Grid/List item spacing: 12px
  static const double gutterMobile = 12.0;

  // -- Predefined SizedBox spacing helpers --

  // Vertical spacings
  static const SizedBox heightXs = SizedBox(height: xs);
  static const SizedBox heightSm = SizedBox(height: sm);
  static const SizedBox heightMd = SizedBox(height: md);
  static const SizedBox heightLg = SizedBox(height: lg);
  static const SizedBox heightXl = SizedBox(height: xl);
  static const SizedBox heightXxl = SizedBox(height: xxl);

  // Horizontal spacings
  static const SizedBox widthXs = SizedBox(width: xs);
  static const SizedBox widthSm = SizedBox(width: sm);
  static const SizedBox widthMd = SizedBox(width: md);
  static const SizedBox widthLg = SizedBox(width: lg);
  static const SizedBox widthXl = SizedBox(width: xl);
  static const SizedBox widthXxl = SizedBox(width: xxl);

  // Edge Insets Padding helpers
  static const EdgeInsets paddingAllXs = EdgeInsets.all(xs);
  static const EdgeInsets paddingAllSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingAllMd = EdgeInsets.all(md);
  static const EdgeInsets paddingAllLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingAllXl = EdgeInsets.all(xl);

  static const EdgeInsets paddingSymmetricHorizontal = EdgeInsets.symmetric(horizontal: marginMobile);
  static const EdgeInsets paddingSymmetricVertical = EdgeInsets.symmetric(vertical: md);
}
