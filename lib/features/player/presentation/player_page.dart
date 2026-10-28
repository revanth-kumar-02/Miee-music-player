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
import '../../../shared/widgets/artist_avatar.dart';
import '../../onboarding/domain/artist_model.dart';
import '../../onboarding/data/artist_discovery_repository.dart';
import '../../onboarding/providers/onboarding_providers.dart';
import '../../media/providers/media_providers.dart';
import '../../connect/presentation/connect_sheet.dart';
import '../../connect/providers/connect_providers.dart';

/// Recreated Now Playing Screen matching the reference design:
/// - Cocoa Plum background (#3A252B) on Mobile
/// - Editorial Tactility studio 2-column layout on Desktop / Web
/// - Top header with down chevron, "PLAYING FROM", and 3-dots menu
/// - Prominent square album artwork with rounded corners
/// - Song title (Playfair Display) + artist + heart action
/// - Clean slider with Dusty Rose active track and timestamps
/// - Playback controls with circular Dusty Rose play button
/// - "Lyrics" pill at the bottom
/// Dynamically resolves artist metadata for the currently playing track.
/// Checks curated catalog, local library, and Deezer repository with graceful fallback.
final nowPlayingArtistProvider = FutureProvider.autoDispose<ArtistModel?>((ref) async {
  final currentTrack = ref.watch(playerControllerProvider.select((s) => s.currentTrack));
  if (currentTrack == null || currentTrack.artist.trim().isEmpty) return null;

  final rawArtist = currentTrack.artist.trim();

  // 1. Direct curated match on full string
  final curatedDirect = DeezerArtistRepository.findCuratedByName(rawArtist);
  if (curatedDirect != null) return curatedDirect;

  // 2. Extract primary artist from multi-artist string (commas, &, feat, ft, etc.)
  final delimiters = RegExp(r'[,/|&]|\s+(feat\.?|ft\.?)\s+', caseSensitive: false);
  final parts = rawArtist.split(delimiters);
  if (parts.isNotEmpty) {
    final first = parts.first.trim();
    if (first.isNotEmpty && first != rawArtist) {
      final curatedFirst = DeezerArtistRepository.findCuratedByName(first);
      if (curatedFirst != null) return curatedFirst;
    }
  }

  // 3. Check local device artists
  try {
    final localArtists = ref.read(artistsProvider);
    final primaryName = parts.isNotEmpty && parts.first.trim().isNotEmpty ? parts.first.trim() : rawArtist;
    final match = localArtists.where((a) {
      final an = a.name.trim().toLowerCase();
      return an == rawArtist.toLowerCase() || an == primaryName.toLowerCase();
    }).firstOrNull;
    if (match != null) {
      return ArtistModel(
        id: match.id,
        name: match.name,
        imageUrl: match.artworkPath ?? '',
      );
    }
  } catch (_) {}

  // 4. Online lookup via repository
  try {
    final repo = ref.read(artistRepositoryProvider);
    final primaryName = parts.isNotEmpty && parts.first.trim().isNotEmpty ? parts.first.trim() : rawArtist;
    final searchResults = await repo.searchArtists(primaryName);
    if (searchResults.isNotEmpty) {
      return searchResults.first;
    }
  } catch (_) {}

  // 5. Fallback artist entity
  final primaryName = parts.isNotEmpty && parts.first.trim().isNotEmpty ? parts.first.trim() : rawArtist;
  return ArtistModel(
    id: '',
    name: primaryName,
    imageUrl: '',
  );
});

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
    final connectState = ref.watch(connectControllerProvider);
    final isRemoteConnectActive = connectState.isRemote;

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
                            color: AppColors.softClay.withValues(alpha: 0.7),
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
                            color: Colors.black.withValues(alpha: 0.35),
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
                              color: AppColors.softClay.withValues(alpha: 0.85),
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

              if (isRemoteConnectActive) ...[
                GestureDetector(
                  onTap: () => ConnectSheet.show(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1DB954).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF1DB954).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.speaker_group_rounded,
                          color: Color(0xFF1DB954),
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Playing on ${connectState.activeDevice.name}',
                          style: GoogleFonts.geist(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1DB954),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],

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
                        : AppColors.vanillaCream.withValues(alpha: 0.6),
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
                    shadowColor: AppColors.dustyRose.withValues(alpha: 0.5),
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
                        : AppColors.vanillaCream.withValues(alpha: 0.6),
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
                        color: AppColors.white.withValues(alpha: 0.08),
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
                        color: AppColors.white.withValues(alpha: 0.08),
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
                  const SizedBox(width: 14),
                  InkWell(
                    onTap: () => ConnectSheet.show(context),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isRemoteConnectActive
                            ? const Color(0xFF1DB954).withValues(alpha: 0.2)
                            : AppColors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: isRemoteConnectActive
                            ? Border.all(color: const Color(0xFF1DB954).withValues(alpha: 0.5))
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.devices_rounded,
                            size: 16,
                            color: isRemoteConnectActive
                                ? const Color(0xFF1DB954)
                                : AppColors.vanillaCream,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isRemoteConnectActive ? 'Connected' : 'Devices',
                            style: GoogleFonts.geist(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isRemoteConnectActive
                                  ? const Color(0xFF1DB954)
                                  : AppColors.vanillaCream,
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

  static String _formatFanCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(0)}K';
    }
    return '$count';
  }

  static String _getArtistDescription(ArtistModel artist) {
    if (artist.bio != null && artist.bio!.trim().isNotEmpty) {
      return artist.bio!.trim();
    }
    final segments = <String>[];
    if (artist.genres.isNotEmpty) {
      segments.add(artist.genres.join(', '));
    }
    if (artist.languages.isNotEmpty) {
      segments.add(artist.languages.join(' • '));
    }
    if (segments.isNotEmpty) {
      return segments.join(' — ');
    }
    if (artist.fanCount > 0) {
      return 'Over ${_formatFanCount(artist.fanCount)} fans on streaming platforms worldwide.';
    }
    return 'Featured artist on Miee.';
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
    final artistAsync = ref.watch(nowPlayingArtistProvider);

    return Scaffold(
      backgroundColor: MieeWebColors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.maxHeight;
            final availableWidth = constraints.maxWidth;
            final isCompactHeight = availableHeight < 740;
            final isLargeHeight = availableHeight >= 920;

            final outerPadV = isLargeHeight ? 28.0 : (isCompactHeight ? 16.0 : 20.0);
            final outerPadH = availableWidth >= 1400
                ? 36.0
                : (availableWidth >= 1100 ? 28.0 : 20.0);

            // Responsive artwork sizing:
            // Desktop 1686 x 864 target: 380 - 420 px (400.0 px)
            // Desktop 1440 x 900 target: 380 - 420 px (400.0 px)
            // Desktop 1920 x 1080 target: 400 - 440 px (420.0 px)
            // Desktop 1366 x 768 target: 330 - 360 px (345.0 px)
            // Desktop 1280 x 720 target: 300 - 330 px (315.0 px)
            final double artworkSize;
            if (availableHeight >= 950) {
              artworkSize = 420.0;
            } else if (availableHeight >= 820 || (availableWidth >= 1400 && availableHeight >= 780)) {
              artworkSize = 400.0;
            } else if (availableHeight >= 740) {
              artworkSize = 345.0;
            } else {
              artworkSize = 315.0;
            }

            // Playback column width: generous width allowing wide waveform and comfortable controls
            final double playbackColumnWidth;
            if (availableWidth >= 1400) {
              playbackColumnWidth = 560.0;
            } else if (availableWidth >= 1200) {
              playbackColumnWidth = 520.0;
            } else {
              playbackColumnWidth = 480.0;
            }

            final double rightCardWidth;
            if (availableWidth >= 1400) {
              rightCardWidth = 400.0;
            } else if (availableWidth >= 1200) {
              rightCardWidth = 380.0;
            } else {
              rightCardWidth = 360.0;
            }

            final columnGap = isLargeHeight ? 52.0 : (isCompactHeight ? 36.0 : 44.0);

            const headerHeight = 32.0;
            final headerBottomGap = isLargeHeight ? 16.0 : (isCompactHeight ? 10.0 : 14.0);
            final artworkBottomGap = isLargeHeight ? 18.0 : (isCompactHeight ? 12.0 : 16.0);
            final metaBottomGap = isLargeHeight ? 14.0 : (isCompactHeight ? 8.0 : 12.0);
            final waveformBottomGap = isLargeHeight ? 16.0 : (isCompactHeight ? 10.0 : 14.0);
            final gapBetweenCards = isLargeHeight ? 18.0 : 14.0;

            final scrubberHeight = isLargeHeight ? 54.0 : (isCompactHeight ? 44.0 : 48.0);
            final playBtnSize = isLargeHeight ? 68.0 : (isCompactHeight ? 58.0 : 64.0);
            final playIconSize = isLargeHeight ? 38.0 : (isCompactHeight ? 32.0 : 36.0);
            final navIconSize = isLargeHeight ? 32.0 : (isCompactHeight ? 28.0 : 30.0);
            final subIconSize = isLargeHeight ? 22.0 : 20.0;

            final metaTitleSize = isLargeHeight ? 26.0 : (isCompactHeight ? 22.0 : 24.0);
            final metaArtistSize = isLargeHeight ? 15.5 : (isCompactHeight ? 13.5 : 14.5);

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: outerPadH, vertical: outerPadV),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (availableHeight - outerPadV * 2).clamp(0.0, double.infinity),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Left Column: Playback Studio ──
                      SizedBox(
                        width: playbackColumnWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. Top Context Bar (Back Arrow + NOW PLAYING)
                            SizedBox(
                              height: headerHeight,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.arrow_back_rounded, size: 22),
                                      color: MieeWebColors.onSurfaceVariant,
                                      tooltip: 'Back',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
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
                                  ],
                                ),
                                if (activeRoom != null) ...[
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
                                        const Icon(Icons.groups_rounded, size: 13, color: MieeWebColors.primaryContainer),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Room ${activeRoom.joinCode}',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 10.5,
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
                          ),
                          SizedBox(height: headerBottomGap),

                          // 2. Large Crisp Square Artwork with DIRECT MASTER badge (Centered in playback column)
                          Center(
                            child: Container(
                              width: artworkSize,
                              height: artworkSize,
                              decoration: BoxDecoration(
                                color: MieeWebColors.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(isCompactHeight ? 16 : 20),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF1A0F12).withValues(alpha: 0.12),
                                    blurRadius: isCompactHeight ? 28 : 42,
                                    offset: Offset(0, isCompactHeight ? 12 : 18),
                                  ),
                                  BoxShadow(
                                    color: const Color(0xFF1A0F12).withValues(alpha: 0.06),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(isCompactHeight ? 16 : 20),
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
                                        borderRadius: BorderRadius.circular(isCompactHeight ? 16 : 20),
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
                                  // DIRECT MASTER Badge (Preserved)
                                  Positioned(
                                    top: isCompactHeight ? 12 : 16,
                                    left: isCompactHeight ? 12 : 16,
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isCompactHeight ? 9 : 10,
                                        vertical: isCompactHeight ? 3.5 : 4,
                                      ),
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
                                          Icon(
                                            Icons.graphic_eq,
                                            size: isCompactHeight ? 13 : 14,
                                            color: MieeWebColors.primaryFixed,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            'DIRECT MASTER',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: isCompactHeight ? 10 : 11,
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
                          SizedBox(height: artworkBottomGap),

                          // 3. Metadata Bar (Title + Artist left, Action icons right, perfectly aligned)
                          Row(
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
                                        fontSize: metaTitleSize,
                                        fontWeight: FontWeight.w700,
                                        color: MieeWebColors.textDark,
                                        letterSpacing: -0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      hasTrack ? currentTrack.artist : 'Select a song from your library or search',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: metaArtistSize,
                                        fontWeight: FontWeight.w500,
                                        color: MieeWebColors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Heart, Playlist, Lyrics action buttons
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      isLiked ? Icons.favorite : Icons.favorite_border,
                                      size: isCompactHeight ? 22 : 24,
                                      color: isLiked ? MieeWebColors.secondary : MieeWebColors.onSurfaceVariant,
                                    ),
                                    tooltip: isLiked ? 'Liked' : 'Like',
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(),
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
                                  const SizedBox(width: 6),
                                  IconButton(
                                    icon: Icon(Icons.playlist_add, size: isCompactHeight ? 24 : 26),
                                    color: MieeWebColors.onSurfaceVariant,
                                    tooltip: 'Add to Playlist',
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(),
                                    onPressed: hasTrack
                                        ? () => showAddToPlaylistSheet(context, currentTrack)
                                        : null,
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    icon: Icon(Icons.lyrics_outlined, size: isCompactHeight ? 22 : 24),
                                    color: MieeWebColors.onSurfaceVariant,
                                    tooltip: 'Lyrics',
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(),
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
                          SizedBox(height: metaBottomGap),

                          // 4. Discrete Waveform Audio Scrubber (Aligned with artwork width)
                          Column(
                            children: [
                              DiscreteWaveformScrubber(
                                progress: progress,
                                isPlaying: isPlaying,
                                height: scrubberHeight,
                                onSeek: (val) {
                                  if (hasTrack && duration.inMilliseconds > 0) {
                                    final ms = (val * duration.inMilliseconds).toInt();
                                    controller.seek(Duration(milliseconds: ms));
                                  }
                                },
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    hasTrack ? _formatTimeDuration(position) : '0:00',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: isCompactHeight ? 12 : 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: MieeWebColors.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    hasTrack && duration.inMilliseconds > 0
                                        ? _formatTimeDuration(duration)
                                        : '--:--',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: isCompactHeight ? 12 : 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: MieeWebColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: waveformBottomGap),

                          // 5. Primary Transport Controls Deck
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // Shuffle
                              IconButton(
                                icon: const Icon(Icons.shuffle_rounded),
                                iconSize: subIconSize,
                                color: isShuffleEnabled
                                    ? MieeWebColors.primaryContainer
                                    : MieeWebColors.outline,
                                tooltip: 'Shuffle',
                                onPressed: () => controller.toggleShuffle(),
                              ),
                              // Prev
                              IconButton(
                                icon: const Icon(Icons.skip_previous_rounded),
                                iconSize: navIconSize,
                                color: MieeWebColors.textDark,
                                tooltip: 'Previous',
                                onPressed: () => controller.previous(),
                              ),
                              // Big Bordeaux Circular Play/Pause #6E0D25
                              Material(
                                color: MieeWebColors.primaryContainer,
                                shape: const CircleBorder(),
                                elevation: 5,
                                shadowColor: MieeWebColors.primaryContainer.withValues(alpha: 0.35),
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
                                    width: playBtnSize,
                                    height: playBtnSize,
                                    alignment: Alignment.center,
                                    child: isLoading
                                        ? SizedBox(
                                            width: playBtnSize * 0.4,
                                            height: playBtnSize * 0.4,
                                            child: const CircularProgressIndicator(
                                              strokeWidth: 2.4,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          )
                                        : Icon(
                                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                            size: playIconSize,
                                            color: Colors.white,
                                          ),
                                  ),
                                ),
                              ),
                              // Next
                              IconButton(
                                icon: const Icon(Icons.skip_next_rounded),
                                iconSize: navIconSize,
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
                                iconSize: subIconSize,
                                color: repeatMode != RepeatMode.off
                                    ? MieeWebColors.primaryContainer
                                    : MieeWebColors.outline,
                                tooltip: 'Repeat',
                                onPressed: () => controller.toggleRepeatMode(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Space between Left and Right columns
                    SizedBox(width: columnGap),

                    // ── Right Column: Up Next + About Artist (Aligned with Album Artwork) ──
                    SizedBox(
                      width: rightCardWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Top offset to align Up Next card with Album Artwork top baseline
                          SizedBox(height: headerHeight + headerBottomGap),

                          // 1. Up Next Queue Panel
                          _buildUpNextCard(
                            context: context,
                            controller: controller,
                            upcomingList: upcomingList,
                            queueList: queueList,
                            isCompact: isCompactHeight,
                          ),
                          SizedBox(height: gapBetweenCards),

                          // 2. About Artist Card (Directly Below Up Next)
                          _buildAboutArtistCard(
                            context: context,
                            artistAsync: artistAsync,
                            isCompact: isCompactHeight,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        ),
      ),
    );
  }

  Widget _buildUpNextCard({
    required BuildContext context,
    required PlayerController controller,
    required List<MusicItem> upcomingList,
    required List<MusicItem> queueList,
    required bool isCompact,
  }) {
    final maxTracks = isCompact ? 2 : 3;

    return Container(
      padding: EdgeInsets.all(isCompact ? 16 : 20),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          // Up Next Header
          Row(
            children: [
              const Icon(
                Icons.queue_music_rounded,
                size: 20,
                color: MieeWebColors.primaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Up Next',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: isCompact ? 14 : 16,
                          fontWeight: FontWeight.w700,
                          color: MieeWebColors.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: MieeWebColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${upcomingList.length} tracks',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: MieeWebColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => context.push('/queue'),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
              ),
            ],
          ),
          Divider(
            height: isCompact ? 16 : 20,
            color: MieeWebColors.subtleBorder,
          ),

          // Upcoming List
          if (upcomingList.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: isCompact ? 14 : 20),
              child: Column(
                children: [
                  Icon(
                    Icons.queue_music_rounded,
                    size: isCompact ? 32 : 40,
                    color: MieeWebColors.outline.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Queue is empty',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: isCompact ? 13 : 14,
                      fontWeight: FontWeight.w600,
                      color: MieeWebColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Play songs to queue up next',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: isCompact ? 11.5 : 12.5,
                      color: MieeWebColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: upcomingList.length > maxTracks ? maxTracks : upcomingList.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final track = upcomingList[index];
                return InkWell(
                  onTap: () {
                    controller.selectTrack(track, queueList);
                  },
                  borderRadius: BorderRadius.circular(10),
                  hoverColor: MieeWebColors.surfaceLow,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: isCompact ? 4 : 6,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          child: Text(
                            '${index + 1}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: MieeWebColors.outline,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: isCompact ? 36 : 40,
                            height: isCompact ? 36 : 40,
                            child: _buildArtworkImage(track.imageUrl),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: isCompact ? 12.5 : 13,
                                  fontWeight: FontWeight.w600,
                                  color: MieeWebColors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: isCompact ? 11 : 11.5,
                                  color: MieeWebColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          track.duration.trim().isNotEmpty
                              ? track.duration
                              : '--:--',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
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
    );
  }

  Widget _buildAboutArtistCard({
    required BuildContext context,
    required AsyncValue<ArtistModel?> artistAsync,
    required bool isCompact,
  }) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 16 : 20),
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
      child: artistAsync.when(
        data: (artist) {
          if (artist == null) {
            return _buildAboutArtistEmptyState(isCompact: isCompact);
          }
          final hasProfileLink = artist.id.trim().isNotEmpty;
          final description = _getArtistDescription(artist);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Row: Icon + Title + Verified Badge + View Profile Button
              Row(
                children: [
                  const Icon(
                    Icons.person_pin_rounded,
                    size: 20,
                    color: MieeWebColors.primaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            'About the Artist',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: isCompact ? 14 : 16,
                              fontWeight: FontWeight.w700,
                              color: MieeWebColors.textDark,
                            ),
                          ),
                        ),
                        if (artist.fanCount > 5000) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: MieeWebColors.primaryContainer.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.verified_rounded,
                                  size: 11,
                                  color: MieeWebColors.primaryContainer,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  'Verified',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10.5,
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
                  ),
                  if (hasProfileLink) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        context.push(
                          '/artist/${Uri.encodeComponent(artist.id.trim())}',
                          extra: artist,
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'View Profile',
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
                    ),
                  ],
                ],
              ),
              Divider(
                height: isCompact ? 16 : 20,
                color: MieeWebColors.subtleBorder,
              ),

              // Profile Row: Avatar + Name + Listener Stats
              Row(
                children: [
                  ArtistAvatar(
                    name: artist.name,
                    imageUrl: artist.imageUrl,
                    radius: isCompact ? 24.0 : 28.0,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          artist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: isCompact ? 14.5 : 16,
                            fontWeight: FontWeight.w700,
                            color: MieeWebColors.textDark,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          artist.fanCount > 0
                              ? '${_formatFanCount(artist.fanCount)} monthly listeners'
                              : (artist.languages.isNotEmpty
                                  ? artist.languages.take(2).join(', ')
                                  : 'Artist on Miee'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: isCompact ? 11.5 : 12.5,
                            fontWeight: FontWeight.w500,
                            color: MieeWebColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (description.isNotEmpty) ...[
                SizedBox(height: isCompact ? 8 : 12),
                Text(
                  description,
                  maxLines: isCompact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: isCompact ? 11.5 : 12.5,
                    height: 1.4,
                    color: MieeWebColors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          );
        },
        loading: () => _buildAboutArtistLoadingState(isCompact: isCompact),
        error: (_, __) => _buildAboutArtistEmptyState(isCompact: isCompact),
      ),
    );
  }

  Widget _buildAboutArtistEmptyState({required bool isCompact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(
              Icons.person_pin_rounded,
              size: 20,
              color: MieeWebColors.primaryContainer,
            ),
            const SizedBox(width: 8),
            Text(
              'About the Artist',
              style: GoogleFonts.plusJakartaSans(
                fontSize: isCompact ? 15 : 17,
                fontWeight: FontWeight.w700,
                color: MieeWebColors.textDark,
              ),
            ),
          ],
        ),
        Divider(
          height: isCompact ? 16 : 20,
          color: MieeWebColors.subtleBorder,
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: isCompact ? 8 : 12),
          child: Column(
            children: [
              Icon(
                Icons.account_circle_outlined,
                size: isCompact ? 32 : 38,
                color: MieeWebColors.outline.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 6),
              Text(
                'No artist details available',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: isCompact ? 12.5 : 13.5,
                  fontWeight: FontWeight.w600,
                  color: MieeWebColors.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Artist information will update with the playing track',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: isCompact ? 11 : 12,
                  color: MieeWebColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAboutArtistLoadingState({required bool isCompact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(
              Icons.person_pin_rounded,
              size: 20,
              color: MieeWebColors.primaryContainer,
            ),
            const SizedBox(width: 8),
            Text(
              'About the Artist',
              style: GoogleFonts.plusJakartaSans(
                fontSize: isCompact ? 15 : 17,
                fontWeight: FontWeight.w700,
                color: MieeWebColors.textDark,
              ),
            ),
          ],
        ),
        Divider(
          height: isCompact ? 16 : 20,
          color: MieeWebColors.subtleBorder,
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: isCompact ? 8 : 12),
          child: Row(
            children: [
              Container(
                width: isCompact ? 48 : 56,
                height: isCompact ? 48 : 56,
                decoration: const BoxDecoration(
                  color: MieeWebColors.surfaceContainer,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 14,
                      decoration: BoxDecoration(
                        color: MieeWebColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 80,
                      height: 10,
                      decoration: BoxDecoration(
                        color: MieeWebColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
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
              inactiveColor: AppColors.white.withValues(alpha: 0.2),
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
                    color: AppColors.vanillaCream.withValues(alpha: 0.65),
                  ),
                ),
                Text(
                  hasTrack && duration.inMilliseconds > 0
                      ? _formatDuration(duration)
                      : '--:--',
                  style: GoogleFonts.geist(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.vanillaCream.withValues(alpha: 0.65),
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


