import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radius.dart';
import '../../app/theme/app_shadows.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

/// Reusable Category Card widget.
/// Used in Library pages as Bento Grid category blocks.
class CategoryCard extends StatelessWidget {
  /// The icon representing the category (e.g. [Icons.music_note]).
  final IconData icon;

  /// The main category name (e.g. "Songs").
  final String title;

  /// Sub-label indicating count or details (e.g. "328 Songs").
  final String subtitle;

  /// Callback when the card block is tapped.
  final VoidCallback? onTap;

  const CategoryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 112.0,
        padding: AppSpacing.paddingAllMd,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest, // `#ffffff`
          borderRadius: AppRadius.radiusLg,
          boxShadow: AppShadows.shadowLow,
          border: Border.all(
            color: AppColors.outlineVariant.withOpacity(0.1),
            width: 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.between,
          children: [
            // Top icon
            Icon(
              icon,
              color: AppColors.primary,
              size: 24.0,
            ),
            // Bottom Metadata
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
                AppSpacing.heightXs,
                Text(
                  subtitle,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
