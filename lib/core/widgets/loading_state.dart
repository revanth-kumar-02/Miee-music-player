import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

/// Reusable Loading State indicator.
/// Shows a centered progress indicator and an optional descriptive message.
class LoadingState extends StatelessWidget {
  /// Optional descriptive text to show below the progress indicator.
  final String? message;

  const LoadingState({
    super.key,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.labelMedium?.copyWith(
      color: AppColors.onSurfaceVariant,
    );

    return Center(
      child: Padding(
        padding: AppSpacing.paddingAllMd,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              strokeWidth: 2.0,
            ),
            if (message != null) ...[
              AppSpacing.heightMd,
              Text(
                message!,
                style: textStyle,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
