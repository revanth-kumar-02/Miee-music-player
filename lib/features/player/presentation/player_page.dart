import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_shadows.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/audio/playback_state.dart';
import '../../../core/audio/providers.dart';
import '../../../shared/widgets/widgets.dart';
import '../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../../shared/models/track.dart';
import '../../library/providers/library_providers.dart';
import '../../../core/audio/youtube_player_widget.dart';
// import '../../lyrics/presentation/widgets/lyrics_overlay.dart';

// final showLyricsProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Miee Now Playing Screen.
/// Observes active states (track details, position progress, buffering, playing status, and mode changes)
/// from Riverpod PlayerController providers and updates views.
class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTrack = ref.watch(playerControllerProvider.select((s) => s.currentTrack));
    final isPlaying = ref.watch(playerControllerProvider.select((s) => s.status == PlaybackStatus.playing));
    final isShuffleEnabled = ref.watch(playerControllerProvider.select((s) => s.isShuffleEnabled));
    final repeatMode = ref.watch(playerControllerProvider.select((s) => s.repeatMode));
    final status = ref.watch(playerControllerProvider.select((s) => s.status));
    final errorMessage = ref.watch(playerControllerProvider.select((s) => s.errorMessage));
    final controller = ref.read(playerControllerProvider.notifier);

    final hasTrack = currentTrack != null;

    // Format Duration Helper
    String formatDuration(Duration duration) {
      String twoDigits(int n) => n.toString().padLeft(2, '0');
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds.remainder(60);
      return '$minutes:${twoDigits(seconds)}';
    }


    return Scaffold(
      body: Stack(
        children: [
          // 1. Clean white minimalist background
          Positioned.fill(
            child: Container(
              color: Colors.white,
            ),
          ),

          // 2. Foreground content scaffold
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  // Now Playing Header AppBar
                  AppHeader(
                    title: 'Now Playing',
                    titleWidget: Text(
                      'NOW PLAYING',
                      style: AppTypography.labelSmall.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    leading: IconButton(
                      icon: const Icon(Icons.expand_more),
                      onPressed: () => context.pop(),
                      splashRadius: 20.0,
                    ),
                    actions: [
                      // IconButton(
                      //   icon: const Icon(Icons.lyrics_outlined),
                      //   onPressed: hasTrack
                      //       ? () => ref.read(showLyricsProvider.notifier).update((s) => !s)
                      //       : null,
                      //   splashRadius: 20.0,
                      // ),
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: IconButton(
                          icon: const Icon(Icons.queue_music),
                          onPressed: hasTrack ? () => context.push('/queue') : null,
                          splashRadius: 20.0,
                        ),
                      ),
                    ],
                  ),

                  // Main content column
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.marginMobile,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Large album cover artwork centered
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final artworkSize = constraints.maxWidth * 0.8;
                              if (!hasTrack) {
                                return Center(
                                  child: Container(
                                    width: artworkSize,
                                    height: artworkSize,
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(32.0),
                                      boxShadow: AppShadows.shadowHigh,
                                    ),
                                    child: Icon(
                                      Icons.music_note,
                                      size: artworkSize * 0.4,
                                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.3),
                                    ),
                                  ),
                                );
                              }

                              if (currentTrack.isYoutube) {
                                final videoId = currentTrack.id.startsWith('youtube_')
                                    ? currentTrack.id.replaceFirst('youtube_', '')
                                    : currentTrack.id;
                                return Center(
                                  child: MieeYouTubePlayerWidget(
                                    videoId: videoId,
                                    width: artworkSize,
                                    height: artworkSize * 0.7,
                                    borderRadius: BorderRadius.circular(24.0),
                                  ),
                                );
                              }

                              return Center(
                                child: AlbumArtwork(
                                  imageUrl: currentTrack.imageUrl,
                                  size: artworkSize,
                                  borderRadius: BorderRadius.circular(32.0),
                                  hasShadow: true,
                                ),
                              );
                            },
                          ),

                          // Song Information flanked by favorite and options buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Consumer(
                                builder: (context, ref, child) {
                                  if (!hasTrack) {
                                    return IconButton(
                                      icon: const Icon(Icons.favorite_border),
                                      color: AppColors.onSurfaceVariant,
                                      onPressed: null,
                                      splashRadius: 20.0,
                                    );
                                  }
                                  final isFav = ref.watch(
                                    favoritesProvider.select((list) => list.any((t) => t.id == currentTrack.id)),
                                  );
                                  return IconButton(
                                    icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
                                    color: isFav ? AppColors.primary : AppColors.onSurfaceVariant,
                                    onPressed: () async {
                                      final notifier = ref.read(favoritesProvider.notifier);
                                      if (isFav) {
                                        await notifier.removeFavorite(currentTrack.id);
                                      } else {
                                        final track = Track(
                                          id: currentTrack.id,
                                          title: currentTrack.title,
                                          artist: currentTrack.artist,
                                          imageUrl: currentTrack.imageUrl,
                                          duration: currentTrack.duration,
                                          filePath: currentTrack.filePath,
                                        );
                                        await notifier.addFavorite(track);
                                      }
                                    },
                                    splashRadius: 20.0,
                                  );
                                },
                              ),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (status == PlaybackStatus.error && errorMessage != null) ...[
                                      Text(
                                        'Playback Error',
                                        style: AppTypography.labelSmall.copyWith(
                                          color: AppColors.error,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                      const SizedBox(height: 4.0),
                                      Text(
                                        errorMessage,
                                        style: AppTypography.bodyMedium.copyWith(
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ] else ...[
                                      Text(
                                        hasTrack ? currentTrack.title : 'No song selected',
                                        style: AppTypography.headlineLargeMobile.copyWith(
                                          color: AppColors.onSurface,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      AppSpacing.heightXs,
                                      Text(
                                        hasTrack ? currentTrack.artist : '—',
                                        style: AppTypography.bodyMedium.copyWith(
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.more_horiz),
                                color: AppColors.onSurfaceVariant,
                                onPressed: hasTrack
                                    ? () => showAddToPlaylistSheet(
                                          context,
                                          currentTrack,
                                        )
                                    : null,
                                splashRadius: 20.0,
                              ),
                            ],
                          ),

                           // ── Symmetrical Waveform Progress ──
                          Consumer(
                            builder: (context, ref, child) {
                              final state = ref.watch(playerControllerProvider);
                              final currentPosition = hasTrack
                                  ? state.position
                                  : Duration.zero;
                              final totalDuration = hasTrack
                                  ? state.duration
                                  : Duration.zero;
                              final isPlaying =
                                  state.status == PlaybackStatus.playing;

                              final progress = totalDuration.inMilliseconds > 0
                                  ? (currentPosition.inMilliseconds /
                                          totalDuration.inMilliseconds)
                                      .clamp(0.0, 1.0)
                                  : 0.0;

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Symmetrical Waveform progress tracker
                                  FractionallySizedBox(
                                    widthFactor: 0.85,
                                    child: WaveformWidget(
                                      isPlaying: isPlaying,
                                      activeProgress: progress,
                                      onScrub: hasTrack
                                          ? (frac) {
                                              final seekPos = Duration(
                                                milliseconds: (frac *
                                                        totalDuration
                                                            .inMilliseconds)
                                                    .toInt(),
                                              );
                                              controller.seek(seekPos);
                                            }
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 12.0),
                                  // Duration timestamps
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        formatDuration(currentPosition),
                                        style: AppTypography.labelSmall,
                                      ),
                                      Text(
                                        formatDuration(totalDuration),
                                        style: AppTypography.labelSmall,
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),

                          // Playback circular control rows
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm),
                            child: PlaybackControls(
                              isPlaying: isPlaying,
                              isShuffleActive: isShuffleEnabled,
                              isRepeatActive: repeatMode != RepeatMode.off,
                              onPlayPauseTap: hasTrack
                                  ? () {
                                      if (isPlaying) {
                                        controller.pause();
                                      } else {
                                        controller.play();
                                      }
                                    }
                                  : null,
                              onPrevTap: hasTrack ? controller.previous : null,
                              onNextTap: hasTrack ? controller.next : null,
                              onShuffleTap: hasTrack ? controller.toggleShuffle : null,
                              onRepeatTap: hasTrack ? controller.toggleRepeatMode : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom padding spacer above device safe areas
                  AppSpacing.heightLg,
                ],
              ),
            ),
          ),

          // 3. Lyrics Overlay layer
          // Consumer(
          //   builder: (context, ref, child) {
          //     final showLyrics = ref.watch(showLyricsProvider);
          //     if (!showLyrics || !hasTrack) return const SizedBox.shrink();
          //     return Positioned.fill(
          //       child: LyricsOverlay(
          //         track: currentTrack,
          //         onClose: () => ref.read(showLyricsProvider.notifier).state = false,
          //       ),
          //     );
          //   },
          // ),
        ],
      ),
    );
  }
}
