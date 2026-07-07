import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/audio/providers.dart';
import '../../domain/youtube_model.dart';
import 'youtube_options_menu.dart';

/// Renders a single YouTube search result item with image thumbnails, duration,
/// channel title, view count, and options.
class YouTubeResultTile extends ConsumerWidget {
  final YouTubeVideo video;

  const YouTubeResultTile({super.key, required this.video});

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      builder: (_) => YouTubeOptionsMenu(video: video),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackState = ref.watch(playerControllerProvider);
    final isCurrentTrack = playbackState.currentTrack?.id == video.id;

    return Semantics(
      label: 'YouTube video: ${video.title} by ${video.channelTitle}, duration ${video.duration}',
      button: true,
      child: InkWell(
        onTap: () {
          // Play the selected YouTube video immediately
          ref.read(playerControllerProvider.notifier).selectTrack(video, [video]);
          context.push('/player');
        },

        borderRadius: BorderRadius.circular(8.0),
        child: Container(
          height: 72.0,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              // 1. Thumbnail with Duration Overlay
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: AppRadius.radiusMd,
                    child: Image.network(
                      video.thumbnailUrl,
                      width: 80.0,
                      height: 56.0,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 80.0,
                        height: 56.0,
                        color: AppColors.surfaceContainerHigh,
                        child: const Icon(Icons.music_note, color: AppColors.onSurfaceVariant),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 2.0,
                    right: 4.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Text(
                        video.duration,
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.white,
                          fontSize: 10.0,
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
                        color: isCurrentTrack ? AppColors.primary : AppColors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2.0),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${video.channelTitle}${video.viewCount.isNotEmpty ? " · " + video.viewCount : ""}',
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

              // 3. Options Menu trigger
              IconButton(
                icon: const Icon(Icons.more_vert, size: 20.0),
                color: AppColors.onSurfaceVariant,
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
