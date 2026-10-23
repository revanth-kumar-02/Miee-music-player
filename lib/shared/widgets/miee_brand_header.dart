import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_shadows.dart';
import '../../app/theme/app_spacing.dart';

/// The canonical Stitch Miee wordmark with the signature crimson dot.
class MieeWordmarkDot extends StatelessWidget {
  final double fontSize;
  final Color textColor;
  final Color dotColor;

  const MieeWordmarkDot({
    super.key,
    this.fontSize = 22,
    this.textColor = const Color(0xFF1A0F12),
    this.dotColor = const Color(0xFFBA0032),
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.plusJakartaSans(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
          color: textColor,
        ),
        children: [
          const TextSpan(text: 'miee'),
          TextSpan(
            text: '.',
            style: TextStyle(
              color: dotColor,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// A consistent brand header matching the Stitch Design System screens
/// (`design_source/miee_design_system/active_screens`).
///
/// Features:
/// - Canonical Stitch `miee.` wordmark with crimson accent dot
/// - Screen title separated by a delicate hairline divider
/// - Right-side notification and profile avatar actions
/// - Respects Android status bar safe areas
/// - Adapts dynamically when scrolled with backdrop blur and hairline border
/// - Compatible with Flutter's [Scaffold.appBar] via [PreferredSizeWidget]
class MieeBrandHeader extends StatelessWidget implements PreferredSizeWidget {
  /// Header title text (e.g. 'Search', 'Playlists', 'Settings').
  /// If omitted or empty, the header renders just the `miee.` brand wordmark.
  final String? title;

  /// Custom title widget if advanced header content is needed.
  final Widget? titleWidget;

  /// Optional widget on the left side (back button, etc.).
  /// If null and [automaticallyImplyLeading] is true, automatically shows a back arrow when canPop.
  final Widget? leading;

  /// Optional action buttons on the right side.
  final List<Widget>? actions;

  /// Controls background blur and subtle elevation border when scrolled.
  final bool isScrolled;

  /// Header content height excluding the status bar. Defaults to 56.0.
  final double height;

  /// Whether to automatically show a back button when Navigator can pop.
  final bool automaticallyImplyLeading;

  /// Optional tap callback for the brand logo. Defaults to navigating to `/home`.
  final VoidCallback? onLogoTap;

  /// Optional tap callback for the notification bell icon.
  /// If null, displays a brief, non-blocking SnackBar ("No new notifications").
  final VoidCallback? onNotificationTap;

  /// Whether to display the Stitch default actions (notifications + avatar) when actions are not provided.
  final bool showProfileAvatar;

  /// Background color of the header bar. Defaults to [AppColors.background] (`#FAF9F7`).
  final Color backgroundColor;

  const MieeBrandHeader({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.isScrolled = false,
    this.height = 56.0,
    this.automaticallyImplyLeading = true,
    this.onLogoTap,
    this.onNotificationTap,
    this.showProfileAvatar = true,
    this.backgroundColor = AppColors.background,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final canPop = automaticallyImplyLeading && Navigator.of(context).canPop();

    Widget? effectiveLeading = leading;
    if (effectiveLeading == null && canPop) {
      effectiveLeading = IconButton(
        icon: const Icon(
          Icons.arrow_back,
          color: AppColors.onSurface,
          size: 22,
        ),
        splashRadius: 20,
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => Navigator.of(context).maybePop(),
      );
    }

    // Build the brand mark + optional title matching Stitch HTML
    Widget? effectiveTitle = titleWidget;
    if (effectiveTitle == null) {
      if (title != null && title!.trim().isNotEmpty) {
        effectiveTitle = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onLogoTap ??
                  () {
                    try {
                      context.go('/home');
                    } catch (_) {}
                  },
              child: const MieeWordmarkDot(
                fontSize: 21,
                textColor: AppColors.onSurface,
                dotColor: Color(0xFFBA0032),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Container(
                width: 1.0,
                height: 14.0,
                color: const Color(0xFFDDC0C1).withValues(alpha: 0.6),
              ),
            ),
            Flexible(
              child: Text(
                title!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      } else {
        // Full brand wordmark for root screens (Home)
        effectiveTitle = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onLogoTap ??
              () {
                try {
                  context.go('/home');
                } catch (_) {}
              },
          child: const MieeWordmarkDot(
            fontSize: 24,
            textColor: AppColors.onSurface,
            dotColor: Color(0xFFBA0032),
          ),
        );
      }
    }

    List<Widget>? effectiveActions = actions;
    if (effectiveActions == null && showProfileAvatar) {
      effectiveActions = [
        IconButton(
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: AppColors.onSurfaceVariant,
            size: 22,
          ),
          splashRadius: 20,
          tooltip: 'Notifications',
          onPressed: onNotificationTap ??
              () {
                final messenger = ScaffoldMessenger.maybeOf(context);
                if (messenger == null) return;
                messenger.hideCurrentSnackBar();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('No new notifications'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
        ),
        GestureDetector(
          onTap: () {
            try {
              context.go('/settings');
            } catch (_) {}
          },
          child: Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(right: 16, left: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF4B0014), // Stitch primary
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(
                Icons.person,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ];
    }

    final topPadding = MediaQuery.paddingOf(context).top;
    final totalHeight = height + topPadding;

    final headerBox = Container(
      height: totalHeight,
      padding: EdgeInsets.only(top: topPadding),
      decoration: isScrolled
          ? BoxDecoration(
              color: backgroundColor.withValues(alpha: 0.90),
              border: const Border(
                bottom: BorderSide(
                  color: Color(0xFFECE7E4),
                  width: 0.5,
                ),
              ),
              boxShadow: AppShadows.shadowLow,
            )
          : BoxDecoration(
              color: backgroundColor,
            ),
      child: SizedBox(
        height: height,
        child: AppBar(
          primary: false,
          leading: effectiveLeading,
          automaticallyImplyLeading: false,
          title: effectiveTitle,
          titleSpacing: effectiveLeading == null ? AppSpacing.marginMobile : 0.0,
          centerTitle: false,
          actions: effectiveActions,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
    );

    if (isScrolled) {
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: headerBox,
        ),
      );
    }

    return headerBox;
  }
}
