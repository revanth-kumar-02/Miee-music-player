import 'package:flutter/material.dart';
import 'miee_brand_header.dart';

/// Reusable Top App Bar header for Miee screens.
///
/// Integrates the Miee brand mark ([MieeBrandHeader]) and adapts
/// its styling (translucency, shadow) based on scroll state.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  /// Header title text.
  final String title;

  /// Optional custom title widget. If provided, replaces the standard title text.
  final Widget? titleWidget;

  /// Optional widget on the left side (typically drawer menu or back arrow).
  final Widget? leading;

  /// Optional action buttons on the right side.
  final List<Widget>? actions;

  /// Controls background blur and shadow. Set to true when scrolled.
  final bool isScrolled;

  /// Custom height for the App Bar. Defaults to 56.0.
  final double height;

  /// Optional tap callback for the notification bell icon.
  final VoidCallback? onNotificationTap;

  const AppHeader({
    super.key,
    required this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.isScrolled = false,
    this.height = 56.0,
    this.onNotificationTap,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    return MieeBrandHeader(
      title: title,
      titleWidget: titleWidget,
      leading: leading,
      actions: actions,
      isScrolled: isScrolled,
      height: height,
      onNotificationTap: onNotificationTap,
    );
  }
}
