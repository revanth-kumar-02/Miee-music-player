import 'dart:ui';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radius.dart';
import '../../app/theme/app_shadows.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

/// Reusable Bottom Navigation Bar.
/// Features a custom glass-like blur backing, top corner rounding, and active dot indicators.
class BottomNavigation extends StatelessWidget {
  /// The index of the currently selected tab.
  final int currentIndex;

  /// Callback when a tab is tapped.
  final ValueChanged<int> onTap;

  const BottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return ClipRRect(
      borderRadius: AppRadius.radiusNavTop,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
        child: Container(
          height: 80.0 + bottomPadding,
          padding: EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: bottomPadding,
          ),
          decoration: BoxDecoration(
            color: AppColors.background.withOpacity(0.9),
            borderRadius: AppRadius.radiusNavTop,
            boxShadow: AppShadows.shadowLow,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                index: 0,
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: 'Home',
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.search_outlined,
                activeIcon: Icons.search,
                label: 'Search',
              ),
              _buildNavItem(
                index: 2,
                icon: Icons.library_music_outlined,
                activeIcon: Icons.library_music,
                label: 'Library',
              ),
              _buildNavItem(
                index: 3,
                icon: Icons.queue_music_outlined,
                activeIcon: Icons.queue_music,
                label: 'Playlists',
              ),
              _buildNavItem(
                index: 4,
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings,
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isActive = currentIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Active Indicator Dot (aligned at the top of the nav item)
            if (isActive)
              Positioned(
                top: AppSpacing.xs,
                child: Container(
                  width: 6.0,
                  height: 6.0,
                  decoration: const BoxDecoration(
                    color: AppColors.onSurface,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            // Nav Item Content
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isActive ? activeIcon : icon,
                    color: isActive ? AppColors.primary : AppColors.onSurfaceVariant,
                    size: 24.0,
                  ),
                  AppSpacing.heightXs,
                  Text(
                    label,
                    style: AppTypography.labelSmall.copyWith(
                      fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                      color: isActive ? AppColors.primary : AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
