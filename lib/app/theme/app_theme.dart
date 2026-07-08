import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// Unified design system theme assembler for Miee.
abstract class AppTheme {
  /// Assembled Light Theme for the application (Material 3 enabled).
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        secondary: AppColors.secondary,
        onSecondary: AppColors.onSecondary,
        error: AppColors.error,
        onError: AppColors.onError,
        errorContainer: AppColors.errorContainer,
        onErrorContainer: AppColors.onSurface,
        background: AppColors.background,
        onBackground: AppColors.onBackground,
        surface: AppColors.surfaceBright,
        onSurface: AppColors.onSurface,
        surfaceVariant: AppColors.surfaceContainerHigh,
        onSurfaceVariant: AppColors.onSurfaceVariant,
        outline: AppColors.outline,
        outlineVariant: AppColors.outlineVariant,
        scrim: AppColors.scrim,
        inverseSurface: AppColors.inverseSurface,
        onInverseSurface: AppColors.inverseOnSurface,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.onSurface),
        actionsIconTheme: IconThemeData(color: AppColors.onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceContainerLowest,
        elevation: 8,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return AppTypography.labelSmall.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary);
          }
          return AppTypography.labelSmall.copyWith(color: AppColors.onSurfaceVariant);
        }),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.accentIndigo,
        inactiveTrackColor: AppColors.surfaceContainerHighest,
        thumbColor: AppColors.accentIndigo,
        trackHeight: 2.0,
      ),
      textTheme: TextTheme(
        displayLarge: AppTypography.displayLarge,
        headlineLarge: AppTypography.headlineLarge,
        headlineMedium: AppTypography.headlineMedium,
        bodyLarge: AppTypography.bodyLarge,
        bodyMedium: AppTypography.bodyMedium,
        labelMedium: AppTypography.labelMedium,
        labelSmall: AppTypography.labelSmall,
      ),
    );
  }

  /// Assembled Dark Theme for the application.
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        secondary: AppColors.secondary,
        onSecondary: AppColors.onSecondary,
        error: AppColors.error,
        onError: AppColors.onError,
        errorContainer: AppColors.errorContainer,
        onErrorContainer: Colors.white,
        background: const Color(0xFF121212),
        onBackground: Colors.white,
        surface: const Color(0xFF1E1E1E),
        onSurface: Colors.white,
        surfaceVariant: const Color(0xFF2C2C2C),
        onSurfaceVariant: Colors.white70,
        outline: AppColors.outline,
        outlineVariant: AppColors.outlineVariant,
        scrim: AppColors.scrim,
        inverseSurface: Colors.white,
        onInverseSurface: const Color(0xFF121212),
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: const AppBarTheme(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        actionsIconTheme: IconThemeData(color: Colors.white),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 8,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return AppTypography.labelSmall.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary);
          }
          return AppTypography.labelSmall.copyWith(color: Colors.white70);
        }),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.accentIndigo,
        inactiveTrackColor: Colors.white24,
        thumbColor: AppColors.accentIndigo,
        trackHeight: 2.0,
      ),
      textTheme: TextTheme(
        displayLarge: AppTypography.displayLarge.copyWith(color: Colors.white),
        headlineLarge: AppTypography.headlineLarge.copyWith(color: Colors.white),
        headlineMedium: AppTypography.headlineMedium.copyWith(color: Colors.white),
        bodyLarge: AppTypography.bodyLarge.copyWith(color: Colors.white),
        bodyMedium: AppTypography.bodyMedium.copyWith(color: Colors.white70),
        labelMedium: AppTypography.labelMedium.copyWith(color: Colors.white70),
        labelSmall: AppTypography.labelSmall.copyWith(color: Colors.white70),
      ),
    );
  }
}
