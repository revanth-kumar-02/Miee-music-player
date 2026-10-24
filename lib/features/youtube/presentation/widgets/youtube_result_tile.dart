import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/audio/playback_state.dart';
import '../../../../core/audio/providers.dart';
import '../../domain/youtube_model.dart';
import 'youtube_options_menu.dart';

/// Renders a single YouTube search result item with image thumbnails, duration,
/// channel title, view count, and options.
class YouTubeResultTile extends ConsumerWidget {
  final YouTubeVideo video;
  final VoidCallback? onTap;

  const YouTubeResultTile({
    super.key,
    required this.video,
    this.onTap,
  });

  void _showOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      builder: (_) => YouTubeOptionsMenu(video: video),
    );
  }

  void _handleTap(WidgetRef ref) {
    final isLoading = ref.read(
      playerControllerProvider.select((s) =>
          s.loadingTrackId != null &&
          isSameTrackId(s.loadingTrackId, video.id)),
    );
    if (isLoading) return;

    if (onTap != null) {
      onTap!();
    } else {
      final track = video.toTrack();
      ref.read(playerControllerProvider.notifier).selectTrack(
            track,
            [track],
            playingFrom: 'YouTube Search',
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTrackId = ref.watch(
      playerControllerProvider.select((s) => s.currentTrack?.id),
    );
    final isCurrentTrack =
        currentTrackId != null && isSameTrackId(currentTrackId, video.id);
    final isPlaying = isCurrentTrack &&
        ref.watch(
          playerControllerProvider.select(
              (s) => s.status == PlaybackStatus.playing),
        );
    final isTrackLoading = ref.watch(
      playerControllerProvider.select((s) =>
          s.loadingTrackId != null &&
          isSameTrackId(s.loadingTrackId, video.id)),
    );

    return Semantics(
      label: 'YouTube video: ${video.title} by ${video.channelTitle}, duration ${video.duration}',
      button: true,
      child: InkWell(
        onTap: isTrackLoading ? null : () => _handleTap(ref),
        borderRadius: BorderRadius.circular(10.0),
        child: Container(
          height: 72.0,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10.0),
            color: isCurrentTrack ? AppColors.dustyRose.withOpacity(0.08) : Colors.transparent,
          ),
          child: Row(
            children: [
              // 1. Thumbnail with Duration Overlay & Playing Indicator
              Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: AppRadius.radiusMd,
                    child: Image.network(
                      video.thumbnailUrl,
                      width: 80.0,
                      height: 56.0,
                      fit: BoxFit.cover,
                      cacheWidth: 160,
                      cacheHeight: 112,
                      errorBuilder: (_, __, ___) => Container(
                        width: 80.0,
                        height: 56.0,
                        color: AppColors.softClay,
                        child: const Icon(Icons.music_note, color: AppColors.cocoaPlum),
                      ),
                    ),
                  ),
                  if (isPlaying)
                    Container(
                      width: 80.0,
                      height: 56.0,
                      decoration: BoxDecoration(
                        color: AppColors.cocoaPlum.withOpacity(0.45),
                        borderRadius: AppRadius.radiusMd,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.equalizer_rounded,
                          color: AppColors.dustyRose,
                          size: 24.0,
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 3.0,
                    right: 4.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.cocoaPlum.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Text(
                        video.duration,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.vanillaCream,
                          fontSize: 10.0,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              AppSpacing.widthMd,

              // 2. Metadata details (Title, Channel, Views)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      style: AppTypography.bodyMedium.copyWith(
                        color: isCurrentTrack ? AppColors.dustyRose : AppColors.cocoaPlum,
                        fontWeight: isCurrentTrack ? FontWeight.w700 : FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3.0),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${video.channelTitle}${video.viewCount.isNotEmpty ? ' · ${video.viewCount}' : ''}',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.mutedMauve,
                              fontSize: 11.5,
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

              // 3. Clear Play Action Button
              IconButton(
                icon: isTrackLoading
                    ? const SizedBox(
                        width: 22.0,
                        height: 22.0,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.dustyRose),
                        ),
                      )
                    : Icon(
                        isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                        color: isCurrentTrack ? AppColors.dustyRose : AppColors.mutedMauve.withOpacity(0.6),
                        size: 28.0,
                      ),
                onPressed: isTrackLoading
                    ? null
                    : () {
                        if (isCurrentTrack) {
                          if (isPlaying) {
                            ref.read(playerControllerProvider.notifier).pause();
                          } else {
                            ref.read(playerControllerProvider.notifier).play();
                          }
                        } else {
                          _handleTap(ref);
                        }
                      },
                splashRadius: 20.0,
                tooltip: isTrackLoading ? 'Loading' : (isPlaying ? 'Pause' : 'Play'),
              ),

              // 4. Options Menu trigger
              IconButton(
                icon: const Icon(Icons.more_vert, size: 20.0),
                color: AppColors.mutedMauve,
                onPressed: () => _showOptions(context),
                splashRadius: 20.0,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
