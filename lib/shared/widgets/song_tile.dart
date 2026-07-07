import 'dart:io';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

/// Reusable Song/Track Tile widget.
/// Renders as a list tile with options for numbering, artwork, options menus,
/// and playing active states (highlighted text + animated Equalizer visualizer).
class SongTile extends StatelessWidget {
  /// Optional image URL for cover thumbnail.
  final String? imageUrl;

  /// Title of the track.
  final String title;

  /// Name of the artist.
  final String artist;

  /// Duration of the track (e.g. "3:42").
  final String duration;

  /// Optional track number prefix in album lists (e.g. 1).
  final int? index;

  /// Controls the active highlighted playing style. Defaults to false.
  final bool isPlaying;

  /// Callback when the tile is tapped.
  final VoidCallback? onTap;

  /// Callback when the more options icon button is tapped.
  final VoidCallback? onMoreTap;

  /// Callback when the tile is long-pressed (e.g. show Add to Playlist).
  final VoidCallback? onLongPress;

  const SongTile({
    super.key,
    required this.title,
    required this.artist,
    required this.duration,
    this.imageUrl,
    this.index,
    this.isPlaying = false,
    this.onTap,
    this.onMoreTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // Left-most leading element (Equalizer vs Number vs Artwork)
    Widget leadingWidget;

    if (isPlaying) {
      leadingWidget = const SizedBox(
        width: 48.0,
        height: 48.0,
        child: Center(
          child: _EqualizerAnimation(),
        ),
      );
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      leadingWidget = ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: imageUrl!.startsWith('http')
            ? Image.network(
                imageUrl!,
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
                File(imageUrl!),
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
      );
    } else if (index != null) {
      leadingWidget = SizedBox(
        width: 32.0,
        child: Text(
          index!.toString().padLeft(2, '0'),
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.onSurfaceVariant,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      );
    } else {
      leadingWidget = const SizedBox.shrink();
    }

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8.0),
      child: Container(
        height: 64.0,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          children: [
            leadingWidget,
            if (imageUrl != null || index != null) AppSpacing.widthMd,
            // Track Metadata
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: isPlaying
                        ? AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          )
                        : AppTypography.bodyMedium.copyWith(
                            color: AppColors.onSurface,
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  AppSpacing.heightXs,
                  Text(
                    artist,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            AppSpacing.widthMd,
            // Track Duration
            Text(
              duration,
              style: AppTypography.labelSmall.copyWith(
                color: isPlaying ? AppColors.primary : AppColors.onSurfaceVariant,
                fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            AppSpacing.widthSm,
            // More Actions
            IconButton(
              icon: Icon(
                Icons.more_horiz,
                color: isPlaying ? AppColors.primary : AppColors.onSurfaceVariant,
                size: 20.0,
              ),
              onPressed: onMoreTap,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              splashRadius: 20.0,
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper widget to paint and animate 3 EQ bar lines.
class _EqualizerAnimation extends StatefulWidget {
  const _EqualizerAnimation();

  @override
  State<_EqualizerAnimation> createState() => _EqualizerAnimationState();
}

class _EqualizerAnimationState extends State<_EqualizerAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // Apply unique sinusoidal offsets to each equalizer bar
            final phaseShift = index * 0.3;
            final progress = (_controller.value + phaseShift) % 1.0;
            final heightFactor = 0.3 + 0.7 * (0.5 + 0.5 * (progress * 2 * 3.14159).sin()).abs();

            return Container(
              width: 3.0,
              height: 16.0 * heightFactor,
              margin: const EdgeInsets.symmetric(horizontal: 1.0),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(1.0),
              ),
            );
          },
        );
      }),
    );
  }
}

extension on double {
  double sin() => javaMathSin(this);
}

// Simple approximation of sin in pure Dart for the animation
double javaMathSin(double rad) {
  // Use core library approximation or standard expansion
  // We can approximate sin(x) cleanly since it's just visual EQ bars
  double x = rad % (2 * 3.141592653589793);
  if (x < 0) x += 2 * 3.141592653589793;
  double sinValue = 0.0;
  double term = x;
  double square = -x * x;
  double fact = 1.0;
  for (int i = 1; i <= 7; i += 2) {
    if (i > 1) {
      fact *= (i - 1) * i;
      term *= square;
    }
    sinValue += term / fact;
  }
  return sinValue;
}
