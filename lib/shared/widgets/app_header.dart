import 'dart:ui';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_shadows.dart';

/// Reusable Top App Bar header.
/// Adapts its styling (translucency, shadow) based on scroll state.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  /// Header title text.
  final String title;

  /// Optional widget on the left side (typically drawer menu or back arrow).
  final Widget? leading;

  /// Optional action buttons on the right side.
  final List<Widget>? actions;

  /// Controls background blur and shadow. Set to true when scrolled.
  final bool isScrolled;

  /// Custom height for the App Bar. Defaults to 64.0.
  final double height;

  const AppHeader({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.isScrolled = false,
    this.height = 64.0,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Widget appBarBody = AppBar(
      title: Text(
        title,
        style: theme.textTheme.displayLarge?.copyWith(
          fontSize: 24.0, // Restrain displayLarge size for header title
          color: AppColors.onSurface,
        ),
      ),
      leading: leading,
      actions: actions,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    );

    if (isScrolled) {
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            height: height + MediaQuery.of(context).padding.top,
            decoration: BoxDecoration(
              color: AppColors.background.withOpacity(0.85),
              boxShadow: AppShadows.shadowLow,
            ),
            child: SafeArea(child: appBarBody),
          ),
        ),
      );
    }

    return Container(
      height: height + MediaQuery.of(context).padding.top,
      color: AppColors.background,
      child: SafeArea(child: appBarBody),
    );
  }
}
