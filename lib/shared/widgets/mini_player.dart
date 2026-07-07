import 'dart:io';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radius.dart';
import '../../app/theme/app_shadows.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../models/music_item.dart';

/// Reusable persistent floating Mini Player bar.
/// Supports both light and dark color contexts and maps progress percentages.
class MiniPlayer extends StatelessWidget {
  /// The unified playable music item.
  final MusicItem musicItem;

  /// Playback progress fraction from 0.0 to 1.0.
  final double progress;

  /// Playing state (true shows pause icon, false shows play icon).
  final bool isPlaying;

  /// Favorited state.
  final bool isFavorited;

  /// Toggles dark-themed backing style. Defaults to false.
  final bool isDark;

  /// Callback when the player bar body is tapped.
  final VoidCallback? onTap;

  /// Callback when the play/pause icon button is tapped.
  final VoidCallback? onPlayPauseTap;

  /// Callback when the favorite button is tapped.
  final VoidCallback? onFavoriteTap;

  const MiniPlayer({
    super.key,
    required this.musicItem,
    required this.progress,
    required this.isPlaying,
    this.isFavorited = false,
    this.isDark = false,
    this.onTap,
    this.onPlayPauseTap,
    this.onFavoriteTap,
  });

  @override
  Widget build(BuildContext context) {
    // Styling colors based on theme variant
    final Color backgroundColor = isDark
        ? AppColors.inverseSurface // `#313030`
        : AppColors.surfaceContainerLowest; // `#ffffff`

    final Color primaryTextColor = isDark ? Colors.white : AppColors.onSurface;
    final Color secondaryTextColor = isDark
        ? Colors.white.withOpacity(0.7)
        : AppColors.onSurfaceVariant;

    final Color progressTrackColor = isDark
        ? Colors.white.withOpacity(0.2)
        : AppColors.primary.withOpacity(0.1);

    final Color progressColor = isDark
        ? Colors.white
        : AppColors.primary;

    final Color favoriteColor = isDark
        ? Colors.white
        : AppColors.onSurface;

    final Color playBtnBg = isDark ? Colors.white : AppColors.primary;
    final Color playBtnIconColor = isDark ? AppColors.onSurface : Colors.white;

    final imageUrl = musicItem.imageUrl;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64.0,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: AppRadius.radiusXl, // 16px
          boxShadow: AppShadows.shadowHigh,
          border: isDark
              ? null
              : Border.all(
                  color: AppColors.outlineVariant.withOpacity(0.1),
                  width: 1.0,
                ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Top Progress Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 2.0,
                color: progressTrackColor,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(
                      color: progressColor,
                    ),
                  ),
                ),
              ),
            ),
            // Player Content Elements
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  // Cover Artwork Thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: imageUrl.startsWith('http')
                        ? Image.network(
                            imageUrl,
                            width: 48.0,
                            height: 48.0,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              width: 48.0,
                              height: 48.0,
                              color: AppColors.surfaceContainerHigh,
                              child: const Icon(
                                Icons.music_note,
                                color: AppColors.onSurfaceVariant,
                                size: 20.0,
                              ),
                            ),
                          )
                        : Image.file(
                            File(imageUrl),
                            width: 48.0,
                            height: 48.0,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              width: 48.0,
                              height: 48.0,
                              color: AppColors.surfaceContainerHigh,
                              child: const Icon(
                                Icons.music_note,
                                color: AppColors.onSurfaceVariant,
                                size: 20.0,
                              ),
                            ),
                          ),
                  ),
                  AppSpacing.widthMd,
                  // Track Metadata Stack
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          musicItem.title,
                          style: AppTypography.labelMedium.copyWith(
                            color: primaryTextColor,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        AppSpacing.heightXs,
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                musicItem.artist,
                                style: AppTypography.labelSmall.copyWith(
                                  color: secondaryTextColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8.0),
                            _SourceBadge(isYoutube: musicItem.isYoutube, isDark: isDark),
                          ],
                        ),
                      ],
                    ),
                  ),
                  AppSpacing.widthSm,
                  // Heart Favorite Button
                  IconButton(
                    icon: Icon(
                      isFavorited ? Icons.favorite : Icons.favorite_border,
                      color: isFavorited ? AppColors.error : favoriteColor,
                      size: 20.0,
                    ),
                    onPressed: onFavoriteTap,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 20.0,
                  ),
                  AppSpacing.widthSm,
                  // Play/Pause circular FAB
                  GestureDetector(
                    onTap: onPlayPauseTap,
                    child: Container(
                      width: 40.0,
                      height: 40.0,
                      decoration: BoxDecoration(
                        color: playBtnBg,
                        shape: BoxShape.circle,
                        boxShadow: AppShadows.shadowLow,
                      ),
                      child: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: playBtnIconColor,
                        size: 20.0,
                      ),
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

class _SourceBadge extends StatelessWidget {
  final bool isYoutube;
  final bool isDark;

  const _SourceBadge({required this.isYoutube, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final label = isYoutube ? 'YouTube' : 'Local';
    final icon = isYoutube ? Icons.language : Icons.phone_android;

    final bgColor = isYoutube
        ? (isDark ? const Color(0xFF6B2020) : const Color(0xFFFFEBEE))
        : (isDark ? const Color(0xFF2E4030) : const Color(0xFFE8F5E9));

    final textColor = isYoutube
        ? (isDark ? const Color(0xFFFF8A80) : const Color(0xFFC62828))
        : (isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 10.0,
            color: textColor,
          ),
          const SizedBox(width: 4.0),
          Text(
            label,
            style: TextStyle(
              fontSize: 8.0,
              fontWeight: FontWeight.bold,
              color: textColor,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
