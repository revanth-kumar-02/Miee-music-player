import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/web_colors.dart';
import '../../../core/audio/playback_state.dart';
import '../../../core/audio/player_controller.dart';
import '../../../core/audio/providers.dart';
import '../../../shared/models/music_item.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/desktop_waveform_scrubber.dart';
import '../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../library/providers/library_providers.dart';
import '../../../shared/widgets/waveform_widget.dart';
import '../../lyrics/presentation/widgets/lyrics_overlay.dart';
import '../../rooms/providers/room_providers.dart';

/// Recreated Now Playing Screen matching the reference design:
/// - Cocoa Plum background (#3A252B) on Mobile
/// - Editorial Tactility studio 2-column layout on Desktop / Web
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

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 960;

    if (isDesktop) {
      return _buildDesktopNowPlaying(
        context: context,
        ref: ref,
        currentTrack: currentTrack,
        isPlaying: isPlaying,
        isLoading: isLoading,
        isShuffleEnabled: isShuffleEnabled,
        repeatMode: repeatMode,
        playingFrom: playingFrom,
        isLiked: isLiked,
        activeRoom: activeRoom,
        controller: controller,
      );
    }

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
                            showModalBottomSheet<void>(
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

  Widget _buildDesktopNowPlaying({
    required BuildContext context,
    required WidgetRef ref,
    required MusicItem? currentTrack,
    required bool isPlaying,
    required bool isLoading,
    required bool isShuffleEnabled,
    required RepeatMode repeatMode,
    required String? playingFrom,
    required bool isLiked,
    required dynamic activeRoom,
    required PlayerController controller,
  }) {
    final position = ref.watch(playerControllerProvider.select((s) => s.position));
    final duration = ref.watch(playerControllerProvider.select((s) => s.duration));
    final hasTrack = currentTrack != null;
    final progress = (duration.inMilliseconds > 0)
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final queueManager = ref.watch(queueManagerProvider);
    final queueList = queueManager.queue;
    final activeIndex = queueManager.currentIndex;
    final upcomingList = activeIndex >= 0 && activeIndex < queueList.length
        ? queueList.sublist(activeIndex + 1)
        : queueList;

    return Scaffold(
      backgroundColor: MieeWebColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Top Context Bar ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded, size: 22),
                            color: MieeWebColors.onSurfaceVariant,
                            tooltip: 'Back',
                            onPressed: () {
                              if (context.canPop()) {
                                context.pop();
                              } else {
                                context.go('/home');
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'NOW PLAYING',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                              color: MieeWebColors.outline,
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: MieeWebColors.outlineVariant,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(
                            playingFrom ?? 'Hi-Fi Direct Stream',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: MieeWebColors.primaryContainer,
                            ),
                          ),
                          if (activeRoom != null) ...[
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: MieeWebColors.primaryContainer.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: MieeWebColors.primaryContainer.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.groups_rounded, size: 14, color: MieeWebColors.primaryContainer),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Room ${activeRoom.joinCode}',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: MieeWebColors.primaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox.shrink(),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // ── 2-Column Studio Grid: Left Canvas (7 cols) + Right Up Next (5 cols) ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column: Cover + Metadata + Waveform Card + Deck (flex 7)
                      Expanded(
                        flex: 7,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 1. Crisp Square Album Cover
                            Center(
                              child: Container(
                                width: 440,
                                height: 440,
                                decoration: BoxDecoration(
                                  color: MieeWebColors.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF1A0F12).withValues(alpha: 0.12),
                                      blurRadius: 45,
                                      offset: const Offset(0, 20),
                                    ),
                                    BoxShadow(
                                      color: const Color(0xFF1A0F12).withValues(alpha: 0.06),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(20),
                                      child: SizedBox.expand(
                                        child: hasTrack
                                            ? _buildArtworkImage(currentTrack.imageUrl)
                                            : _buildFallbackArtwork(),
                                      ),
                                    ),
                                    // Gradient sheen
                                    Positioned.fill(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(20),
                                          gradient: LinearGradient(
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                            colors: [
                                              Colors.black.withValues(alpha: 0.25),
                                              Colors.transparent,
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    // DIRECT MASTER Badge
                                    Positioned(
                                      top: 14,
                                      left: 14,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: MieeWebColors.tertiary.withValues(alpha: 0.75),
                                          borderRadius: BorderRadius.circular(6),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.15),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.graphic_eq,
                                              size: 14,
                                              color: MieeWebColors.primaryFixed,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'DIRECT MASTER',
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.6,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),

                            // 2. Metadata Bar
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 500),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          hasTrack ? currentTrack.title : 'No Track Selected',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 26,
                                            fontWeight: FontWeight.w700,
                                            color: MieeWebColors.textDark,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          hasTrack ? currentTrack.artist : 'Select a song from your library or search',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: MieeWebColors.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Heart, Playlist, Lyrics action buttons
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          isLiked ? Icons.favorite : Icons.favorite_border,
                                          size: 24,
                                          color: isLiked ? MieeWebColors.secondary : MieeWebColors.onSurfaceVariant,
                                        ),
                                        tooltip: isLiked ? 'Liked' : 'Like',
                                        onPressed: hasTrack
                                            ? () {
                                                final favNotifier = ref.read(favoritesProvider.notifier);
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
                                      IconButton(
                                        icon: const Icon(Icons.playlist_add, size: 24),
                                        color: MieeWebColors.onSurfaceVariant,
                                        tooltip: 'Add to Playlist',
                                        onPressed: hasTrack
                                            ? () => showAddToPlaylistSheet(context, currentTrack)
                                            : null,
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.lyrics_outlined, size: 22),
                                        color: MieeWebColors.onSurfaceVariant,
                                        tooltip: 'Lyrics',
                                        onPressed: hasTrack
                                            ? () {
                                                showModalBottomSheet<void>(
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
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // 3. Discrete Waveform Audio Scrubber (Clean, no card background, timestamps below)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 500),
                              child: Column(
                                children: [
                                  DiscreteWaveformScrubber(
                                    progress: progress,
                                    isPlaying: isPlaying,
                                    height: 60.0,
                                    onSeek: (val) {
                                      if (hasTrack && duration.inMilliseconds > 0) {
                                        final ms = (val * duration.inMilliseconds).toInt();
                                        controller.seek(Duration(milliseconds: ms));
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        hasTrack ? _formatTimeDuration(position) : '0:00',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: MieeWebColors.onSurfaceVariant,
                                        ),
                                      ),
                                      Text(
                                        hasTrack && duration.inMilliseconds > 0
                                            ? _formatTimeDuration(duration)
                                            : '--:--',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: MieeWebColors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // 4. Primary Transport Controls Deck
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  // Shuffle
                                  IconButton(
                                    icon: const Icon(Icons.shuffle_rounded),
                                    iconSize: 22,
                                    color: isShuffleEnabled
                                        ? MieeWebColors.primaryContainer
                                        : MieeWebColors.outline,
                                    tooltip: 'Shuffle',
                                    onPressed: () => controller.toggleShuffle(),
                                  ),
                                  // Prev
                                  IconButton(
                                    icon: const Icon(Icons.skip_previous_rounded),
                                    iconSize: 32,
                                    color: MieeWebColors.textDark,
                                    tooltip: 'Previous',
                                    onPressed: () => controller.previous(),
                                  ),
                                  // Big Bordeaux Circular Play/Pause #6E0D25
                                  Material(
                                    color: MieeWebColors.primaryContainer,
                                    shape: const CircleBorder(),
                                    elevation: 6,
                                    shadowColor: MieeWebColors.primaryContainer.withValues(alpha: 0.4),
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
                                        width: 64,
                                        height: 64,
                                        alignment: Alignment.center,
                                        child: isLoading
                                            ? const SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2.6,
                                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                ),
                                              )
                                            : Icon(
                                                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                                size: 36,
                                                color: Colors.white,
                                              ),
                                      ),
                                    ),
                                  ),
                                  // Next
                                  IconButton(
                                    icon: const Icon(Icons.skip_next_rounded),
                                    iconSize: 32,
                                    color: MieeWebColors.textDark,
                                    tooltip: 'Next',
                                    onPressed: () => controller.next(),
                                  ),
                                  // Repeat
                                  IconButton(
                                    icon: Icon(
                                      repeatMode == RepeatMode.one
                                          ? Icons.repeat_one_rounded
                                          : Icons.repeat_rounded,
                                    ),
                                    iconSize: 22,
                                    color: repeatMode != RepeatMode.off
                                        ? MieeWebColors.primaryContainer
                                        : MieeWebColors.outline,
                                    tooltip: 'Repeat',
                                    onPressed: () => controller.toggleRepeatMode(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 40),

                      // Right Column: Up Next Queue Panel (flex 5)
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: MieeWebColors.surfaceLowest,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: MieeWebColors.outlineVariant.withValues(alpha: 0.25),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Up Next Header
                              Row(
                                children: [
                                  const Icon(
                                    Icons.queue_music_rounded,
                                    size: 22,
                                    color: MieeWebColors.primaryContainer,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Up Next',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: MieeWebColors.textDark,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: MieeWebColors.surfaceContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${upcomingList.length} tracks',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: MieeWebColors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () => context.push('/queue'),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'View All',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: MieeWebColors.primaryContainer,
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          size: 16,
                                          color: MieeWebColors.primaryContainer,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 24, color: MieeWebColors.subtleBorder),

                              // Upcoming List
                              if (upcomingList.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 48),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.queue_music_rounded,
                                        size: 48,
                                        color: MieeWebColors.outline.withValues(alpha: 0.4),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Queue is empty',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: MieeWebColors.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Play songs or an album to queue up next',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 13,
                                          color: MieeWebColors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: upcomingList.length > 6 ? 6 : upcomingList.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                                  itemBuilder: (context, index) {
                                    final track = upcomingList[index];
                                    return InkWell(
                                      onTap: () {
                                        controller.selectTrack(track, queueList);
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      hoverColor: MieeWebColors.surfaceLow,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 20,
                                              child: Text(
                                                '${index + 1}',
                                                style: GoogleFonts.plusJakartaSans(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: MieeWebColors.outline,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: SizedBox(
                                                width: 44,
                                                height: 44,
                                                child: _buildArtworkImage(track.imageUrl),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    track.title,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: GoogleFonts.plusJakartaSans(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                      color: MieeWebColors.onSurface,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    track.artist,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: GoogleFonts.plusJakartaSans(
                                                      fontSize: 12,
                                                      color: MieeWebColors.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              track.duration.trim().isNotEmpty
                                                  ? track.duration
                                                  : '--:--',
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: MieeWebColors.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
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
    if (kIsWeb) {
      return _buildFallbackArtwork();
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

String _formatTimeDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString();
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
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


