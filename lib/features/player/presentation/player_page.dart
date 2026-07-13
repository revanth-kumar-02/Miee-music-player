import 'dart:io';
import 'dart:ui';
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
import '../../lyrics/presentation/widgets/lyrics_overlay.dart';

final showLyricsProvider = StateProvider.autoDispose<bool>((ref) => false);

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

    final blurBackingUrl = hasTrack ? currentTrack.imageUrl : '';

    return Scaffold(
      body: Stack(
        children: [
          // Baseline background container to ensure the GPU always has a layer to draw on
          Positioned.fill(
            child: Container(
              color: AppColors.background,
            ),
          ),
          if (hasTrack && blurBackingUrl.isNotEmpty)
            Positioned.fill(
              child: Opacity(
                opacity: 0.4,
                child: blurBackingUrl.startsWith('http')
                    ? Image.network(
                        blurBackingUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                      )
                    : Image.file(
                        File(blurBackingUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                      ),
              ),
            ),
          // Glassmorphic overlay backdrop filter
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                child: Container(
                  color: AppColors.background.withValues(alpha: 0.5),
                ),
              ),
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
                      IconButton(
                        icon: const Icon(Icons.lyrics_outlined),
                        onPressed: hasTrack
                            ? () => ref.read(showLyricsProvider.notifier).update((s) => !s)
                            : null,
                        splashRadius: 20.0,
                      ),
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
                              return Center(
                                child: hasTrack
                                    ? AlbumArtwork(
                                        imageUrl: currentTrack.imageUrl,
                                        size: artworkSize,
                                        borderRadius: BorderRadius.circular(32.0),
                                        hasShadow: true,
                                      )
                                    : Container(
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
                                      MarqueeText(
                                        text: hasTrack ? currentTrack.title : 'No song selected',
                                        style: AppTypography.headlineLargeMobile.copyWith(
                                          color: AppColors.onSurface,
                                        ),
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

                           // ── Live audio visualizer + seek bar ──
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
                                  // Animated bar visualizer centered and narrower (75% of screen width)
                                  FractionallySizedBox(
                                    widthFactor: 0.75,
                                    child: LiveAudioVisualizer(
                                      isPlaying: isPlaying,
                                      progress: progress,
                                      trackId: currentTrack?.id,
                                      barCount: 24,
                                      height: 60.0,
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
          Consumer(
            builder: (context, ref, child) {
              final showLyrics = ref.watch(showLyricsProvider);
              if (!showLyrics || !hasTrack) return const SizedBox.shrink();
              return Positioned.fill(
                child: LyricsOverlay(
                  track: currentTrack,
                  onClose: () => ref.read(showLyricsProvider.notifier).state = false,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
