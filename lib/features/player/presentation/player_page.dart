import 'dart:io';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/audio/playback_state.dart';
import '../../../core/audio/player_controller.dart';
import '../../../core/audio/providers.dart';
import '../../../shared/models/track.dart';
import '../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../library/providers/library_providers.dart';
import '../../../shared/widgets/waveform_widget.dart';
import '../../lyrics/presentation/widgets/lyrics_overlay.dart';
import '../../rooms/providers/room_providers.dart';

/// Recreated Now Playing Screen matching the reference design:
/// - Cocoa Plum background (#3A252B)
/// - Top header with down chevron, "PLAYING FROM", and 3-dots menu
/// - Prominent square album artwork with rounded corners
/// - Song title (Playfair Display) + artist + heart action
/// - Clean slider with Dusty Rose active track and timestamps
/// - Playback controls with circular Dusty Rose play button
/// - "Lyrics" pill at the bottom
class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTrack =
        ref.watch(playerControllerProvider.select((s) => s.currentTrack));
    final isPlaying = ref.watch(
        playerControllerProvider.select((s) => s.status == PlaybackStatus.playing));
    final isLoading = ref.watch(
        playerControllerProvider.select((s) =>
            s.status == PlaybackStatus.loading ||
            s.status == PlaybackStatus.buffering));
    final isShuffleEnabled =
        ref.watch(playerControllerProvider.select((s) => s.isShuffleEnabled));
    final repeatMode =
        ref.watch(playerControllerProvider.select((s) => s.repeatMode));
    final playingFrom =
        ref.watch(playerControllerProvider.select((s) => s.playingFrom));
    final controller = ref.read(playerControllerProvider.notifier);

    final hasTrack = currentTrack != null;
    final favorites = ref.watch(favoritesProvider);
    final isLiked = hasTrack ? favorites.any((t) => t.id == currentTrack.id) : false;
    final activeRoom = ref.watch(activeRoomProvider);

    return Scaffold(
      backgroundColor: AppColors.cocoaPlum,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
              // ── 1. Top Header Bar ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 28,
                      color: AppColors.vanillaCream,
                    ),
                    onPressed: () => context.pop(),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'PLAYING FROM',
                          style: GoogleFonts.geist(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: AppColors.softClay.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          playingFrom ?? 'Now Playing',
                          style: GoogleFonts.geist(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.vanillaCream,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      activeRoom != null ? Icons.groups_rounded : Icons.groups_outlined,
                      size: 26,
                      color: activeRoom != null ? AppColors.dustyRose : AppColors.vanillaCream,
                    ),
                    tooltip: activeRoom != null ? 'Active Room (${activeRoom.joinCode})' : 'Listen Together',
                    onPressed: () {
                      if (activeRoom != null) {
                        context.push('/rooms/active');
                      } else {
                        context.push('/rooms');
                      }
                    },
                  ),
                ],
              ),

              const Spacer(flex: 1),

              // ── 2. Prominent Square Album Artwork ──
              Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 320, maxHeight: 320),
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: hasTrack
                            ? _buildArtworkImage(currentTrack.imageUrl)
                            : _buildFallbackArtwork(),
                      ),
                    ),
                  ),
                ),
              ),

              const Spacer(flex: 1),

              // ── 3. Title & Artist + Like and Overflow Buttons ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      icon: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        size: 24,
                        color: isLiked
                            ? AppColors.dustyRose
                            : AppColors.vanillaCream,
                      ),
                      onPressed: hasTrack
                          ? () {
                              final favNotifier =
                                  ref.read(favoritesProvider.notifier);
                              if (isLiked) {
                                favNotifier.removeFavorite(currentTrack.id);
                              } else {
                                favNotifier.addFavorite(
                                Track(
                                  id: currentTrack.id,
                                  title: currentTrack.title,
                                  artist: currentTrack.artist,
                                  imageUrl: currentTrack.imageUrl,
                                  duration: currentTrack.duration,
                                  filePath: currentTrack.filePath,
                                ),
                              );
                              }
                            }
                          : null,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            hasTrack ? currentTrack.title : 'No track selected',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.vanillaCream,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasTrack
                                ? currentTrack.artist
                                : 'Select a song to play',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.geist(
                              fontSize: 14,
                              color: AppColors.softClay.withOpacity(0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      icon: const Icon(
                        Icons.more_horiz,
                        size: 24,
                        color: AppColors.vanillaCream,
                      ),
                      onPressed: hasTrack
                          ? () => showAddToPlaylistSheet(context, currentTrack)
                          : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── 4. Waveform Progress & Timestamps ──
              _WaveformProgressSection(
                hasTrack: hasTrack,
                isPlaying: isPlaying,
                controller: controller,
              ),

              const SizedBox(height: 16),

              // ── 5. Playback Controls Row ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.shuffle_rounded),
                    iconSize: 22,
                    color: isShuffleEnabled
                        ? AppColors.dustyRose
                        : AppColors.vanillaCream.withOpacity(0.6),
                    onPressed: () => controller.toggleShuffle(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded),
                    iconSize: 32,
                    color: AppColors.vanillaCream,
                    onPressed: () => controller.previous(),
                  ),

                  // Large Circular Dusty Rose Play Button
                  Material(
                    color: AppColors.dustyRose,
                    shape: const CircleBorder(),
                    elevation: 4,
                    shadowColor: AppColors.dustyRose.withOpacity(0.5),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: isLoading
                          ? null
                          : () {
                              if (isPlaying) {
                                controller.pause();
                              } else {
                                controller.play();
                              }
                            },
                      child: Container(
                        width: 58,
                        height: 58,
                        alignment: Alignment.center,
                        child: isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.6,
                                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                                ),
                              )
                            : Icon(
                                isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 34,
                                color: AppColors.white,
                              ),
                      ),
                    ),
                  ),

                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded),
                    iconSize: 32,
                    color: AppColors.vanillaCream,
                    onPressed: () => controller.next(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.repeat_rounded),
                    iconSize: 22,
                    color: repeatMode != RepeatMode.off
                        ? AppColors.dustyRose
                        : AppColors.vanillaCream.withOpacity(0.6),
                    onPressed: () => controller.toggleRepeatMode(),
                  ),
                ],
              ),

              const Spacer(flex: 1),

              // ── 6. Bottom Actions: Lyrics & Queue ──
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  InkWell(
                    onTap: hasTrack
                        ? () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              useRootNavigator: true,
                              backgroundColor: Colors.transparent,
                              builder: (ctx) => FractionallySizedBox(
                                heightFactor: 0.92,
                                child: LyricsOverlay(
                                  track: currentTrack,
                                  onClose: () => Navigator.of(ctx).pop(),
                                ),
                              ),
                            );
                          }
                        : null,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.lyrics_outlined,
                            size: 16,
                            color: AppColors.vanillaCream,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Lyrics',
                            style: GoogleFonts.geist(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.vanillaCream,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  InkWell(
                    onTap: () => context.push('/queue'),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.queue_music_rounded,
                            size: 16,
                            color: AppColors.vanillaCream,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Queue',
                            style: GoogleFonts.geist(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.vanillaCream,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    ),
  ),
);
  }

  Widget _buildFallbackArtwork() {
    return Container(
      color: AppColors.softClay,
      alignment: Alignment.center,
      child: const Icon(
        Icons.music_note_rounded,
        size: 80,
        color: AppColors.cocoaPlum,
      ),
    );
  }

  Widget _buildArtworkImage(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return _buildFallbackArtwork();
    }
    final cleanUrl = rawUrl.trim();
    if (cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://')) {
      return Image.network(
        cleanUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildFallbackArtwork(),
      );
    }
    try {
      final normalizedPath = cleanUrl.startsWith('file://')
          ? Uri.parse(cleanUrl).toFilePath()
          : cleanUrl;
      final file = File(normalizedPath);
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildFallbackArtwork(),
      );
    } catch (_) {
      return _buildFallbackArtwork();
    }
  }
}

class _WaveformProgressSection extends ConsumerWidget {
  final bool hasTrack;
  final bool isPlaying;
  final PlayerController controller;

  const _WaveformProgressSection({
    required this.hasTrack,
    required this.isPlaying,
    required this.controller,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(
      playerControllerProvider.select((s) => s.position),
    );
    final duration = ref.watch(
      playerControllerProvider.select((s) => s.duration),
    );

    final progress = (duration.inMilliseconds > 0)
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Center(
      child: SizedBox(
        width: 270.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WaveformWidget(
              isPlaying: isPlaying,
              activeProgress: progress,
              activeColor: AppColors.dustyRose,
              inactiveColor: AppColors.white.withOpacity(0.2),
              onScrub: (val) {
                if (hasTrack && duration.inMilliseconds > 0) {
                  final seekPos = Duration(
                    milliseconds: (val * duration.inMilliseconds).toInt(),
                  );
                  controller.seek(seekPos);
                }
              },
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  hasTrack ? _formatDuration(position) : '0:00',
                  style: GoogleFonts.geist(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.vanillaCream.withOpacity(0.65),
                  ),
                ),
                Text(
                  hasTrack && duration.inMilliseconds > 0
                      ? _formatDuration(duration)
                      : '--:--',
                  style: GoogleFonts.geist(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.vanillaCream.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}


