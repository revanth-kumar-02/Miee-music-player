import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// Recreated Nordic Cobalt Floating Bottom Navigation Dock.
///
/// Exactly reproduces the reference design across all 4 screens:
/// 1. Home
/// 2. Search
/// 3. Central elevated circular Electric Cobalt Play/Pause button
/// 4. Library (/playlists)
/// 5. Now Playing / Equalizer (/player)
class BottomNavigation extends StatelessWidget {
  /// The index of the currently selected tab:
  /// 0 = Home, 1 = Search, 3 = Library, 4 = Now Playing
  final int currentIndex;

  /// Callback when a tab is tapped.
  final ValueChanged<int> onTap;

  /// Callback when the central elevated play button is tapped.
  final VoidCallback? onCenterPlayTap;

  /// Whether audio is actively playing (controls play vs pause icon on the center button).
  final bool isPlaying;

  const BottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.onCenterPlayTap,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20.0,
        right: 20.0,
        bottom: bottomPadding > 0 ? bottomPadding : 14.0,
      ),
      child: SizedBox(
        height: 64.0,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // ── Floating Dock Container ──────────────────────────────────
            Container(
              height: 56.0,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(28.0),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.denseObsidian.withValues(alpha: 0.08),
                    blurRadius: 20.0,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(
                  color: AppColors.paleConcrete.withValues(alpha: 0.8),
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  // Tab 0: Home
                  Expanded(
                    child: _buildNavItem(
                      index: 0,
                      icon: Icons.home_rounded,
                      isActive: currentIndex == 0,
                    ),
                  ),

                  // Tab 1: Search
                  Expanded(
                    child: _buildNavItem(
                      index: 1,
                      icon: Icons.search_rounded,
                      isActive: currentIndex == 1,
                    ),
                  ),

                  // Spacer for center elevated button
                  const SizedBox(width: 58.0),

                  // Tab 3: Library
                  Expanded(
                    child: _buildNavItem(
                      index: 3,
                      icon: Icons.queue_music_rounded,
                      isActive: currentIndex == 3,
                    ),
                  ),

                  // Tab 4: Now Playing / Equalizer
                  Expanded(
                    child: _buildNavItem(
                      index: 4,
                      icon: Icons.equalizer_rounded,
                      isActive: currentIndex == 4,
                    ),
                  ),
                ],
              ),
            ),

            // ── Center Elevated Circular Cobalt Play/Pause Button ─────────
            Positioned(
              top: -6.0,
              child: GestureDetector(
                onTap: onCenterPlayTap ?? () => onTap(2),
                child: Container(
                  width: 52.0,
                  height: 52.0,
                  decoration: BoxDecoration(
                    color: AppColors.electricCobalt,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.electricCobalt.withValues(alpha: 0.35),
                        blurRadius: 12.0,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: AppColors.white,
                      size: 28.0,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required bool isActive,
  }) {
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Icon(
          icon,
          size: 24.0,
          color: isActive ? AppColors.electricCobalt : AppColors.industrialSteel,
        ),
      ),
    );
  }
}
