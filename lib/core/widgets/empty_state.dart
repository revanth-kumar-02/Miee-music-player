import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

/// Reusable Empty State widget.
/// Displayed as a fallback when search lists, libraries, or playlists are empty.
class EmptyState extends StatelessWidget {
  /// The title text of the empty state.
  final String title;

  /// Optional detailed message description.
  final String? message;

  /// Optional icon to show above the title.
  final IconData? icon;

  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: AppSpacing.paddingAllLg,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 48.0,
                color: AppColors.outlineVariant,
              ),
              AppSpacing.heightMd,
            ],
            Text(
              title,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: AppColors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              AppSpacing.heightSm,
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
