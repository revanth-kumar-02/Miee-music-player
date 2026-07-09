import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';

/// Reusable Section Header.
/// Used to separate sections with optional actions (text button or icon button).
class SectionHeader extends StatelessWidget {
  /// The header text.
  final String title;

  /// Toggles between standard headline style and uppercase label style.
  final bool isUppercase;

  /// Optional text label for the right-aligned button.
  final String? actionLabel;

  /// Callback when the text button is tapped.
  final VoidCallback? onActionTap;

  /// Optional icon for the right-aligned icon button.
  final IconData? actionIcon;

  /// Callback when the icon button is tapped.
  final VoidCallback? onIconTap;

  const SectionHeader({
    super.key,
    required this.title,
    this.isUppercase = false,
    this.actionLabel,
    this.onActionTap,
    this.actionIcon,
    this.onIconTap,
  });

  @override
  Widget build(BuildContext context) {
    final titleStyle = isUppercase
        ? AppTypography.labelMedium.copyWith(
            color: AppColors.onSurfaceVariant,
            letterSpacing: 1.5,
          )
        : AppTypography.headlineMedium.copyWith(
            color: AppColors.onSurface,
          );

    final cleanTitle = isUppercase ? title.toUpperCase() : title;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            cleanTitle,
            style: titleStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onActionTap,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              actionLabel!.toUpperCase(),
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.outline,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        else if (actionIcon != null)
          IconButton(
            onPressed: onIconTap,
            icon: Icon(
              actionIcon,
              size: 20.0,
              color: AppColors.onSurfaceVariant,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            splashRadius: 20.0,
          ),
      ],
    );
  }
}
