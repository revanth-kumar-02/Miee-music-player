import 'dart:io';
import 'dart:math' as math;
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

  /// Controls whether this tile represents the current active track (e.g. in Now Playing row).
  /// If null, defaults to [isPlaying].
  final bool? isActive;

  /// Controls the active loading state (shows spinner on artwork). Defaults to false.
  final bool isLoading;

  /// Callback when the tile is tapped.
  final VoidCallback? onTap;

  /// Callback when the more options icon button is tapped.
  final VoidCallback? onMoreTap;

  /// Callback when the tile is long-pressed (e.g. show Add to Playlist).
  final VoidCallback? onLongPress;

  /// Optional source badge widget (e.g. Local vs YouTube indicator).
  final Widget? sourceBadge;

  /// Optional trailing icon.
  final IconData? trailingIcon;

  /// Optional custom trailing widget (e.g. playback action buttons).
  /// If provided, replaces the default duration label and onMoreTap button.
  final Widget? trailingWidget;

  const SongTile({
    super.key,
    required this.title,
    required this.artist,
    required this.duration,
    this.imageUrl,
    this.index,
    this.isPlaying = false,
    this.isActive,
    this.isLoading = false,
    this.onTap,
    this.onMoreTap,
    this.onLongPress,
    this.sourceBadge,
    this.trailingIcon,
    this.trailingWidget,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveImageUrl = imageUrl;
    final isLocalFile = effectiveImageUrl != null &&
        effectiveImageUrl.isNotEmpty &&
        !effectiveImageUrl.startsWith('http://') &&
        !effectiveImageUrl.startsWith('https://');

    final normalizedPath = isLocalFile && effectiveImageUrl.startsWith('file://')
        ? effectiveImageUrl.substring(7)
        : effectiveImageUrl;

    final isCurrent = isActive ?? isPlaying;

    Widget leadingWidget;
    if (normalizedPath != null && normalizedPath.isNotEmpty) {
      leadingWidget = ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: Stack(
          alignment: Alignment.center,
          children: [
            !isLocalFile && effectiveImageUrl != null
                ? Image.network(
                    effectiveImageUrl,
                    width: 48.0,
                    height: 48.0,
                    fit: BoxFit.cover,
                    cacheWidth: 120,
                    cacheHeight: 120,
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
                    File(normalizedPath),
                    width: 48.0,
                    height: 48.0,
                    fit: BoxFit.cover,
                    cacheWidth: 120,
                    cacheHeight: 120,
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
            if (isLoading)
              Container(
                width: 48.0,
                height: 48.0,
                color: Colors.black.withOpacity(0.55),
                child: const Center(
                  child: SizedBox(
                    width: 20.0,
                    height: 20.0,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                ),
              )
            else if (isCurrent)
              Container(
                width: 48.0,
                height: 48.0,
                color: Colors.black.withOpacity(0.35),
                child: Center(
                  child: _EqualizerAnimation(isPlaying: isPlaying),
                ),
              ),
          ],
        ),
      );
    } else if (index != null) {
      if (isLoading) {
        leadingWidget = const SizedBox(
          width: 32.0,
          child: Center(
            child: SizedBox(
              width: 18.0,
              height: 18.0,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ),
        );
      } else if (isCurrent) {
        leadingWidget = SizedBox(
          width: 32.0,
          child: Center(
            child: _EqualizerAnimation(isPlaying: isPlaying),
          ),
        );
      } else {
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
      }
    } else {
      // Fallback 48x48 placeholder container when no image and no track index
      leadingWidget = ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 48.0,
              height: 48.0,
              color: AppColors.surfaceContainerHigh,
              child: const Icon(
                Icons.music_note,
                color: AppColors.onSurfaceVariant,
                size: 20.0,
              ),
            ),
            if (isLoading)
              Container(
                width: 48.0,
                height: 48.0,
                color: Colors.black.withOpacity(0.55),
                child: const Center(
                  child: SizedBox(
                    width: 20.0,
                    height: 20.0,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                ),
              )
            else if (isCurrent)
              Container(
                width: 48.0,
                height: 48.0,
                color: Colors.black.withOpacity(0.35),
                child: Center(
                  child: _EqualizerAnimation(isPlaying: isPlaying),
                ),
              ),
          ],
        ),
      );
    }

    final isHighlighted = isPlaying || isLoading;

    return Semantics(
      label: 'Song: $title by $artist, duration $duration${isPlaying ? ", currently playing" : (isLoading ? ", currently loading" : "")}',
      button: true,
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8.0),
        child: Container(
          height: 64.0,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              leadingWidget,
              AppSpacing.widthMd,
              // Track Metadata
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: isHighlighted
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
                    Row(
                      children: [
                        if (sourceBadge != null) ...[
                          sourceBadge!,
                          AppSpacing.widthXs,
                        ],
                        Expanded(
                          child: Text(
                            artist,
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Trailing Actions (Custom widget or Duration + Options Menu)
              if (trailingWidget != null)
                trailingWidget!
              else ...[
                Text(
                  duration,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                if (onMoreTap != null) ...[
                  AppSpacing.widthXs,
                  IconButton(
                    icon: Icon(
                      trailingIcon ?? Icons.more_vert,
                      color: AppColors.onSurfaceVariant,
                      size: 20.0,
                    ),
                    onPressed: onMoreTap,
                    splashRadius: 20.0,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32.0,
                      minHeight: 32.0,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper widget to paint and animate 3 EQ bar lines.
class _EqualizerAnimation extends StatefulWidget {
  final bool isPlaying;
  const _EqualizerAnimation({this.isPlaying = true});

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
      duration: const Duration(milliseconds: 2000), // ~50% speed of the previous 1000ms duration
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_EqualizerAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        if (!_controller.isAnimating) {
          _controller.repeat();
        }
      } else {
        _controller.stop();
      }
    }
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
            // Smooth sinusoidal oscillation between 0.25 and 1.0 height factor
            final heightFactor = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(progress * 2 * math.pi));

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
