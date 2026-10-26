import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/audio/playback_state.dart';
import '../../../core/audio/providers.dart';
import '../../../core/storage/adapters/history_entry.dart';
import '../../history/domain/listening_event.dart';
import '../../media/domain/models.dart';
import '../../media/providers/media_providers.dart';
import '../../../shared/models/music_item.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/widgets.dart';
import '../../recommendations/providers/recommendation_providers.dart';
import '../../recommendations/data/recommendation_service.dart';
import '../../playlists/domain/playlist_model.dart';
import '../../playlists/providers/playlist_providers.dart';
import '../../playlists/presentation/widgets/create_playlist_dialog.dart';
import '../../library/providers/library_providers.dart';
import '../../rooms/providers/room_providers.dart';
import 'widgets/artist_rotation_section.dart';

/// Recreated Miee Home Screen matching the reference design:
/// - Vanilla Cream primary canvas
/// - Editorial hero banner: "Music for a calmer you.", "Play now" button in Dusty Rose
/// - Carousel indicators and pagination arrows
/// - "Made for you" section with genuine playlists, liked songs, and discovery cards
/// - Seamless integration of personalized recommendations and local spotlight
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _heroSlideIndex = 0;

  @override
  Widget build(BuildContext context) {
    final localSongs = ref.watch(songsProvider);
    final localAlbums = ref.watch(albumsProvider);
    final recsAsync = ref.watch(recommendationSectionsProvider);
    final currentTrack =
        ref.watch(playerControllerProvider.select((s) => s.currentTrack));
    final playlists = ref.watch(allPlaylistsProvider);
    final favorites = ref.watch(favoritesProvider);
    final recentlyPlayedAsync = ref.watch(recentlyPlayedProvider);
    final queueManager = ref.watch(queueManagerProvider);

    final recentEntries = recentlyPlayedAsync.valueOrNull ?? [];
    final cloudHistory = recsAsync.valueOrNull?.recentlyPlayed ?? [];

    final recentlyPlayedTracks = _resolveRecentlyPlayedTracks(
      recentEntries: recentEntries,
      cloudHistory: cloudHistory,
      localSongs: localSongs,
      limit: 10,
    );

    final continueTrack = _resolveContinueListeningTrack(
      recentEntries: recentEntries,
      cloudHistory: cloudHistory,
      localSongs: localSongs,
    );
    final continueQueue = continueTrack != null
        ? _resolveContinueListeningQueue(
            targetTrack: continueTrack,
            recentEntries: recentEntries,
            localSongs: localSongs,
            activeQueue: queueManager.queue,
          )
        : <MusicItem>[];

    final hour = DateTime.now().hour;
    final greetingPrefix = hour < 12
        ? 'GOOD MORNING'
        : (hour < 17 ? 'GOOD AFTERNOON' : 'GOOD EVENING');

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 960;

    return Scaffold(
      backgroundColor: AppColors.vanillaCream,
      appBar: isDesktop ? null : const MieeBrandHeader(showProfileAvatar: true),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 28.0 : AppSpacing.marginMobile,
          vertical: 12.0,
        ),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. Editorial Hero Banner ────────────────────────────────────
            _buildEditorialHeroBanner(context, greetingPrefix, recsAsync, localSongs),

            const SizedBox(height: 24),

            // ── 1.5 Listen Together Banner ──────────────────────────────────
            _buildListenTogetherBanner(context),

            const SizedBox(height: 32),

            // ── 2. "Made for you" Section ───────────────────────────────────
            _buildMadeForYouSection(context, playlists, favorites, recsAsync.valueOrNull),

            const SizedBox(height: 36),

            // ── 3. Personalized Cloud Recommendations ───────────────────────
            recsAsync.when(
              data: (sections) => _buildPersonalizedShelves(
                context,
                sections,
                currentTrack,
                recentlyPlayedTracks,
              ),
              loading: () => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.dustyRose,
                      ),
                    ),
                  ),
                  if (recentlyPlayedTracks.isNotEmpty)
                    _buildRecentlyPlayedList(
                      context,
                      recentlyPlayedTracks,
                      currentTrack,
                    ),
                ],
              ),
              error: (e, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDiscoveryErrorBanner(context, e),
                  if (recentlyPlayedTracks.isNotEmpty)
                    _buildRecentlyPlayedList(
                      context,
                      recentlyPlayedTracks,
                      currentTrack,
                    ),
                ],
              ),
            ),

            // ── 4. Continue Listening (Recent History / Local Fallback) ───────
            if (continueTrack != null) ...[
              _buildSectionTitle('Continue Listening'),
              const SizedBox(height: 14),
              _buildContinueListeningCard(
                context: context,
                recentSong: continueTrack,
                resolvedQueue: continueQueue,
              ),
              const SizedBox(height: 32),
            ],

            // ── 5. Local Music Spotlight (if present) ───────────────────────
            if (localSongs.isNotEmpty) ...[
              _buildSectionTitle('Local Tracks'),
              const SizedBox(height: 14),
              _buildLocalTracksList(localAlbums, localSongs),
              const SizedBox(height: 32),
            ],

            if (localAlbums.isNotEmpty) ...[
              _buildSectionTitle('Local Albums'),
              const SizedBox(height: 14),
              _buildAlbumsGrid(context, localAlbums, localSongs),
              const SizedBox(height: 32),
            ],

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildListenTogetherBanner(BuildContext context) {
    final activeRoom = ref.watch(activeRoomProvider);

    if (activeRoom != null) {
      return InkWell(
        onTap: () => context.push('/rooms/active'),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.cocoaPlum,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.cocoaPlum.withOpacity(0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.dustyRose.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.groups_rounded, color: AppColors.dustyRose, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'LISTENING TOGETHER • ${activeRoom.joinCode}',
                          style: GoogleFonts.geist(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: AppColors.dustyRose,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activeRoom.name,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.vanillaCream,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.vanillaCream, size: 14),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => context.push('/rooms'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cocoaPlum.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: AppColors.cocoaPlum.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.dustyRose.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.groups_outlined, color: AppColors.dustyRose, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Listen Together',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.cocoaPlum,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Host or join private rooms with up to 5 friends',
                    style: GoogleFonts.geist(
                      fontSize: 11,
                      color: AppColors.cocoaPlum.withOpacity(0.65),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.cocoaPlum,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Join',
                style: GoogleFonts.geist(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.vanillaCream,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── EDITORIAL HERO BANNER ──────────────────────────────────────────────────

  void _handleBannerTap(int index) {
    switch (index % 3) {
      case 0:
        // Slide 1: Discover Music -> Search
        context.go('/search');
        break;
      case 1:
        // Slide 2: Your Music -> Library / Playlists
        context.go('/playlists');
        break;
      case 2:
        // Slide 3: Listen Together -> Listening Room entrance
        context.push('/rooms');
        break;
    }
  }

  Widget _buildBannerArtwork(int slideIndex, bool isNarrow) {
    final assetPath = switch (slideIndex % 3) {
      0 => 'assets/images/banner_discover.png',
      1 => 'assets/images/banner_your_music.png',
      2 => 'assets/images/banner_listen_together.png',
      _ => 'assets/images/banner_discover.png',
    };

    return Image.asset(
      assetPath,
      fit: BoxFit.cover,
      alignment: Alignment.centerRight,
      errorBuilder: (context, error, stackTrace) {
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildEditorialHeroBanner(
    BuildContext context,
    String greeting,
    AsyncValue<RecommendationSections> recsAsync,
    List<MediaSong> localSongs,
  ) {
    const slideTitles = [
      'Music for\na calmer you.',
      'Discover sound\nwithout noise.',
      'Your sanctuary\nof rhythm.',
    ];
    const slideSubtitles = [
      'A little more feeling in every note.',
      'Handcrafted discovery tailored to your artists.',
      'Every playlist, track, and moment in harmony.',
    ];

    final currentTitle = slideTitles[_heroSlideIndex % slideTitles.length];
    final currentSubtitle =
        slideSubtitles[_heroSlideIndex % slideSubtitles.length];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final height = constraints.maxWidth > 800
            ? 250.0
            : (isNarrow ? 230.0 : 220.0);

        return GestureDetector(
          onTap: () => _handleBannerTap(_heroSlideIndex),
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity != null) {
              if (details.primaryVelocity! < -100) {
                // Swiped left -> next slide
                setState(() {
                  _heroSlideIndex = (_heroSlideIndex + 1) % 3;
                });
              } else if (details.primaryVelocity! > 100) {
                // Swiped right -> prev slide
                setState(() {
                  _heroSlideIndex = (_heroSlideIndex - 1 + 3) % 3;
                });
              }
            }
          },
          child: Container(
            width: double.infinity,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: const Color(0xFFEADFD2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.cocoaPlum.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF7EFE6),
                  Color(0xFFEDE0D2),
                  Color(0xFFDFCBC0),
                ],
              ),
            ),
            child: Stack(
              children: [
                // Right-Side Artwork Area (Clean illustration blended into banner background)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: isNarrow
                      ? constraints.maxWidth * 0.44
                      : (constraints.maxWidth > 800 ? 340.0 : 250.0),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(20),
                    ),
                    child: ShaderMask(
                      shaderCallback: (bounds) {
                        return const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,
                            Colors.white,
                          ],
                          stops: [0.0, 0.22],
                        ).createShader(bounds);
                      },
                      blendMode: BlendMode.dstIn,
                      child: _buildBannerArtwork(_heroSlideIndex, isNarrow),
                    ),
                  ),
                ),

                // Subtle gradient overlay from left preserving headline readability
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          const Color(0xFFF8F1E8).withOpacity(0.94),
                          const Color(0xFFF8F1E8).withOpacity(0.70),
                          Colors.transparent,
                        ],
                        stops: isNarrow
                            ? const [0.0, 0.55, 0.88]
                            : const [0.0, 0.45, 0.78],
                      ),
                    ),
                  ),
                ),

                // Content on Left (Text and Play Now button unchanged)
                Positioned(
                  left: isNarrow ? 20 : 28,
                  top: isNarrow ? 18 : 24,
                  bottom: isNarrow ? 18 : 24,
                  right: isNarrow
                      ? constraints.maxWidth * 0.38
                      : (constraints.maxWidth > 800 ? 330.0 : 240.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            greeting,
                            style: GoogleFonts.geist(
                              fontSize: isNarrow ? 10 : 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2.0,
                              color: AppColors.cocoaPlum.withOpacity(0.75),
                            ),
                          ),
                          SizedBox(height: isNarrow ? 4 : 6),
                          Text(
                            currentTitle,
                            style: GoogleFonts.playfairDisplay(
                              fontSize: height > 230 && !isNarrow
                                  ? 34
                                  : (isNarrow ? 24 : 28),
                              fontWeight: FontWeight.bold,
                              height: 1.12,
                              color: AppColors.cocoaPlum,
                            ),
                          ),
                          if (!isNarrow) ...[
                            const SizedBox(height: 6),
                            Text(
                              currentSubtitle,
                              style: GoogleFonts.geist(
                                fontSize: 13,
                                color: AppColors.mutedMauve,
                              ),
                            ),
                          ],
                        ],
                      ),

                      // "Play now" Button
                      Material(
                        color: AppColors.dustyRose,
                        borderRadius: BorderRadius.circular(20),
                        elevation: 1,
                        child: InkWell(
                          onTap: () {
                            recsAsync.whenData((sections) {
                              final targetTrack = sections.featuredTrack ??
                                  sections.popularTracks.firstOrNull ??
                                  sections.fromYourArtists.firstOrNull ??
                                  sections.discoverMore.firstOrNull;
                              final queue = sections.popularTracks.isNotEmpty
                                  ? sections.popularTracks
                                  : (sections.fromYourArtists.isNotEmpty
                                      ? sections.fromYourArtists
                                      : sections.discoverMore);

                              if (targetTrack != null) {
                                ref
                                    .read(playerControllerProvider.notifier)
                                    .selectTrack(
                                      targetTrack,
                                      queue,
                                      playingFrom: 'Featured Music',
                                    );
                              } else if (localSongs.isNotEmpty) {
                                ref
                                    .read(playerControllerProvider.notifier)
                                    .selectTrack(
                                      localSongs.first,
                                      localSongs,
                                      playingFrom: 'Local Music',
                                    );
                              } else {
                                context.go('/search');
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 18,
                                  color: AppColors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Play now',
                                  style: GoogleFonts.geist(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Carousel Controls on Bottom Right
                Positioned(
                  right: isNarrow ? 16 : 24,
                  bottom: isNarrow ? 16 : 20,
                  child: Row(
                    children: [
                      // Dot indicators
                      Row(
                        children: List.generate(3, (index) {
                          final isActive = index == _heroSlideIndex;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _heroSlideIndex = index;
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 6),
                              width: isActive ? 18 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppColors.white
                                    : AppColors.white.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          );
                        }),
                      ),
                      SizedBox(width: isNarrow ? 8 : 14),

                      // Previous (<)
                      _buildCircleArrowButton(
                        icon: Icons.chevron_left_rounded,
                        onTap: () {
                          setState(() {
                            _heroSlideIndex = (_heroSlideIndex - 1 + 3) % 3;
                          });
                        },
                      ),
                      const SizedBox(width: 8),

                      // Next (>)
                      _buildCircleArrowButton(
                        icon: Icons.chevron_right_rounded,
                        onTap: () {
                          setState(() {
                            _heroSlideIndex = (_heroSlideIndex + 1) % 3;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCircleArrowButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.white.withOpacity(0.85),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 20, color: AppColors.cocoaPlum),
        onPressed: onTap,
      ),
    );
  }

  // ── "MADE FOR YOU" SECTION ─────────────────────────────────────────────────

  Widget _buildMadeForYouSection(
    BuildContext context,
    List<PlaylistModel> playlists,
    List<Track> favorites,
    RecommendationSections? recs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Made for you',
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.cocoaPlum,
              ),
            ),
            InkWell(
              onTap: () => context.go('/playlists'),
              child: Row(
                children: [
                  Text(
                    'See all',
                    style: GoogleFonts.geist(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedMauve,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppColors.mutedMauve,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Horizontal Grid of Artwork Cards (Liked Songs, User Playlists, Discover Tracks, New Playlist)
        SizedBox(
          height: 215,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              // 1. Liked Songs Card
              _buildCustomMadeForYouCard(
                title: 'Liked Songs',
                subtitle:
                    '${favorites.length} ${favorites.length == 1 ? 'song' : 'songs'}',
                artwork: Container(
                  width: 154,
                  height: 154,
                  decoration: BoxDecoration(
                    color: AppColors.dustyRose,
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.dustyRose,
                        Color(0xFFC77987),
                      ],
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.favorite_rounded,
                      size: 52,
                      color: AppColors.white,
                    ),
                  ),
                ),
                onTap: () => context.go('/liked-songs'),
              ),
              const SizedBox(width: 16),

              // 2. Real User Playlists
              for (final playlist in playlists) ...[
                _buildCustomMadeForYouCard(
                  title: playlist.name,
                  subtitle:
                      '${playlist.songCount} ${playlist.songCount == 1 ? 'song' : 'songs'}',
                  artwork: Container(
                    width: 154,
                    height: 154,
                    decoration: BoxDecoration(
                      color: AppColors.softClay,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.oatBeige,
                        width: 1.0,
                      ),
                    ),
                    child: (playlist.effectiveCoverUrl != null &&
                            playlist.effectiveCoverUrl!.isNotEmpty)
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: _buildCoverImage(playlist.effectiveCoverUrl!),
                          )
                        : const Center(
                            child: Icon(
                              Icons.queue_music_rounded,
                              size: 44,
                              color: AppColors.cocoaPlum,
                            ),
                          ),
                  ),
                  onTap: () =>
                      context.push('/playlist/${playlist.id}', extra: playlist),
                ),
                const SizedBox(width: 16),
              ],

              // 3. Recommended Tracks from Discover More
              if (recs != null && recs.discoverMore.isNotEmpty) ...[
                for (final track in recs.discoverMore.take(4)) ...[
                  _buildCustomMadeForYouCard(
                    title: track.title,
                    subtitle: track.artist,
                    artwork: Container(
                      width: 154,
                      height: 154,
                      decoration: BoxDecoration(
                        color: AppColors.softClay,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.oatBeige,
                          width: 1.0,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          track.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.music_note_rounded,
                              size: 44,
                              color: AppColors.cocoaPlum,
                            ),
                          ),
                        ),
                      ),
                    ),
                    onTap: () {
                      ref.read(playerControllerProvider.notifier).selectTrack(
                            track,
                            recs.discoverMore,
                            playingFrom: 'Discover',
                          );
                    },
                  ),
                  const SizedBox(width: 16),
                ],
              ],

              // 4. Create Playlist Action Card
              _buildCustomMadeForYouCard(
                title: 'Create Playlist',
                subtitle: 'Add custom mix',
                artwork: Container(
                  width: 154,
                  height: 154,
                  decoration: BoxDecoration(
                    color: AppColors.oatBeige.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.mutedMauve.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.add_rounded,
                      size: 48,
                      color: AppColors.cocoaPlum,
                    ),
                  ),
                ),
                onTap: () => showCreatePlaylistDialog(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCustomMadeForYouCard({
    required String title,
    required String subtitle,
    required Widget artwork,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 154,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            artwork,
            const SizedBox(height: 8),

            // Card Title
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.geist(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.cocoaPlum,
              ),
            ),
            const SizedBox(height: 2),

            // Card Subtitle
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.geist(
                fontSize: 12,
                color: AppColors.mutedMauve,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── PERSONALIZED SHELVES (Riverpod Recommendation Sections) ────────────────

  Widget _buildPersonalizedShelves(
    BuildContext context,
    RecommendationSections sections,
    MusicItem? currentTrack,
    List<Track> recentlyPlayedTracks,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 960;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. Popular Tracks ────────────────────────────────────────────────
        if (sections.popularTracks.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionTitle('Popular Tracks'),
              Text(
                '${sections.popularTracks.length} tracks',
                style: GoogleFonts.geist(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.mutedMauve,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Trending individual songs by verified artists',
            style: GoogleFonts.geist(
              fontSize: 13,
              color: AppColors.mutedMauve,
            ),
          ),
          const SizedBox(height: 14),

          // Responsive grid/row of popular song cards
          if (isDesktop) ...[
            Wrap(
              spacing: 16,
              runSpacing: 14,
              children: [
                for (final track in sections.popularTracks)
                  _buildPopularTrackCard(
                    context,
                    track,
                    currentTrack?.id == track.id,
                    sections.popularTracks,
                    width: (screenWidth - 56 - 32) / 3,
                  ),
              ],
            ),
          ] else ...[
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: sections.popularTracks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final track = sections.popularTracks[index];
                  return _buildPopularTrackCard(
                    context,
                    track,
                    currentTrack?.id == track.id,
                    sections.popularTracks,
                    width: 270,
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 36),
        ],

        // ── 2. Artists to Explore ────────────────────────────────────────────
        if (sections.relatedArtists.isNotEmpty) ...[
          _buildSectionTitle('Artists to Explore'),
          const SizedBox(height: 6),
          Text(
            'Verified artists across genres and languages',
            style: GoogleFonts.geist(
              fontSize: 13,
              color: AppColors.mutedMauve,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 125,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: sections.relatedArtists.length,
              separatorBuilder: (_, __) => const SizedBox(width: 18),
              itemBuilder: (context, index) {
                final artist = sections.relatedArtists[index];
                return GestureDetector(
                  onTap: () =>
                      context.push('/artist/${artist.id}', extra: artist),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.dustyRose.withOpacity(0.5),
                            width: 1.5,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 36,
                          backgroundColor: AppColors.softClay,
                          backgroundImage: artist.hasValidImage
                              ? NetworkImage(artist.imageUrl)
                              : null,
                          child: !artist.hasValidImage
                              ? Text(
                                  artist.name.isNotEmpty
                                      ? artist.name[0].toUpperCase()
                                      : 'A',
                                  style: GoogleFonts.geist(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.cocoaPlum,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 84,
                        child: Text(
                          artist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.geist(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.cocoaPlum,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 36),
        ],

        // ── 3. From Your Artists (Cross-Platform Dynamic Rotation) ──────────
        if (sections.favoriteArtists.isNotEmpty || sections.fromYourArtists.isNotEmpty) ...[
          ArtistRotationSection(
            artists: sections.favoriteArtists,
            initialTracks: sections.fromYourArtists,
          ),
        ],

        // ── 4. Discover More ─────────────────────────────────────────────────
        if (sections.discoverMore.isNotEmpty) ...[
          _buildSectionTitle('Discover More'),
          const SizedBox(height: 6),
          Text(
            'Handpicked individual tracks for your session',
            style: GoogleFonts.geist(
              fontSize: 13,
              color: AppColors.mutedMauve,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: sections.discoverMore.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final track = sections.discoverMore[index];
                final isPlaying = currentTrack?.id == track.id;

                return GestureDetector(
                  onTap: () {
                    ref
                        .read(playerControllerProvider.notifier)
                        .selectTrack(track, sections.discoverMore, playingFrom: 'Discover More');
                  },
                  child: SizedBox(
                    width: 144,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.network(
                                track.imageUrl,
                                width: 144,
                                height: 144,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 144,
                                  height: 144,
                                  color: AppColors.softClay,
                                  child: const Icon(Icons.music_note, color: AppColors.cocoaPlum),
                                ),
                              ),
                            ),
                            if (isPlaying)
                              Positioned(
                                right: 8,
                                bottom: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: AppColors.dustyRose,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.equalizer_rounded,
                                    color: AppColors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.geist(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isPlaying ? AppColors.dustyRose : AppColors.cocoaPlum,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.geist(
                            fontSize: 11,
                            color: AppColors.mutedMauve,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 36),
        ],

        // ── 5. Recently Played (hidden when empty) ───────────────────────────
        if (recentlyPlayedTracks.isNotEmpty) ...[
          _buildRecentlyPlayedList(
            context,
            recentlyPlayedTracks,
            currentTrack,
          ),
        ],
      ],
    );
  }

  Widget _buildPopularTrackCard(
    BuildContext context,
    MusicItem track,
    bool isPlaying,
    List<MusicItem> queue, {
    required double width,
  }) {
    return Consumer(
      builder: (context, ref, _) {
        final isTrackLoading = ref.watch(
          playerControllerProvider.select((s) =>
              s.loadingTrackId != null &&
              isSameTrackId(s.loadingTrackId, track.id)),
        );

        return InkWell(
          onTap: isTrackLoading
              ? null
              : () {
                  ref.read(playerControllerProvider.notifier).selectTrack(
                        track,
                        queue,
                        playingFrom: 'Popular Tracks',
                      );
                },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: (isPlaying || isTrackLoading)
                    ? AppColors.dustyRose
                    : AppColors.oatBeige,
                width: (isPlaying || isTrackLoading) ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.cocoaPlum.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    track.imageUrl,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 52,
                      height: 52,
                      color: AppColors.softClay,
                      child: const Icon(
                        Icons.music_note_rounded,
                        color: AppColors.cocoaPlum,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.geist(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: (isPlaying || isTrackLoading)
                              ? AppColors.dustyRose
                              : AppColors.cocoaPlum,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.geist(
                          fontSize: 11,
                          color: AppColors.mutedMauve,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.duration,
                        style: GoogleFonts.geist(
                          fontSize: 10,
                          color: AppColors.mutedMauve.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: (isPlaying || isTrackLoading)
                        ? AppColors.dustyRose
                        : AppColors.softClay.withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                  child: isTrackLoading
                      ? const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.0,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.white),
                            ),
                          ),
                        )
                      : Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 20,
                          color: isPlaying
                              ? AppColors.white
                              : AppColors.cocoaPlum,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDiscoveryErrorBanner(BuildContext context, Object error) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.softClay),
        boxShadow: [
          BoxShadow(
            color: AppColors.cocoaPlum.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.softClay.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.music_off_rounded,
              color: AppColors.cocoaPlum,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Music Discovery Offline or Unavailable',
                  style: GoogleFonts.geist(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Could not fetch online recommendations. Check your connection or retry.',
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    color: AppColors.mutedMauve,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () {
              ref.invalidate(recommendationSectionsProvider);
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.dustyRose,
              foregroundColor: AppColors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  // ── LOCAL SPOTLIGHT HELPERS ────────────────────────────────────────────────

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.playfairDisplay(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: AppColors.cocoaPlum,
      ),
    );
  }

  MusicItem? _resolveContinueListeningTrack({
    required List<HistoryEntry> recentEntries,
    required List<ListeningEvent> cloudHistory,
    required List<MediaSong> localSongs,
  }) {
    // 1. Check local Hive recently played entries (sorted newest first)
    if (recentEntries.isNotEmpty) {
      final newest = recentEntries.first.track.toTrack();
      if (!newest.isYoutube) {
        final localMatch = localSongs.where((s) {
          if (s.id == newest.id) return true;
          if (s.filePath.isNotEmpty && s.filePath == newest.filePath) return true;
          return s.id == newest.id.replaceFirst('youtube_', '');
        }).firstOrNull;
        if (localMatch != null) return localMatch;
      } else {
        if (newest.imageUrl.isEmpty || !newest.imageUrl.startsWith('http')) {
          final vid = newest.id.replaceFirst('youtube_', '');
          return Track(
            id: newest.id,
            title: newest.title,
            artist: newest.artist,
            imageUrl: 'https://i.ytimg.com/vi/$vid/hqdefault.jpg',
            duration: newest.duration,
            filePath: newest.filePath,
          );
        }
      }
      return newest;
    }

    // 2. Check cloud listening history
    if (cloudHistory.isNotEmpty) {
      final event = cloudHistory.first;
      final localMatch = localSongs.where((s) {
        if (s.id == event.trackId) return true;
        return s.id == event.trackId.replaceFirst('youtube_', '');
      }).firstOrNull;
      if (localMatch != null) return localMatch;

      final m = event.durationSec ~/ 60;
      final s = event.durationSec % 60;
      final isYoutube = event.source == 'youtube' || event.trackId.startsWith('youtube_');
      final vid = event.trackId.replaceFirst('youtube_', '');
      final resolvedArt = (event.imageUrl != null && event.imageUrl!.isNotEmpty)
          ? event.imageUrl!
          : (isYoutube ? 'https://i.ytimg.com/vi/$vid/hqdefault.jpg' : '');

      return Track(
        id: event.trackId.startsWith('youtube_')
            ? event.trackId
            : 'youtube_${event.trackId}',
        title: event.title,
        artist: event.artist,
        imageUrl: resolvedArt,
        duration: '$m:${s.toString().padLeft(2, '0')}',
      );
    }

    // 3. Fallback to first available local track
    return localSongs.firstOrNull;
  }

  /// Resolves the unified Recently Played track list with correct cover artwork,
  /// newest-first ordering, and stable deduplication across online and local libraries.
  List<Track> _resolveRecentlyPlayedTracks({
    required List<HistoryEntry> recentEntries,
    required List<ListeningEvent> cloudHistory,
    required List<MediaSong> localSongs,
    int limit = 10,
  }) {
    final resolved = <Track>[];
    final seenTrackIds = <String>{};

    // 1. Process local Hive recently played entries (reactive, immediate, offline-ready)
    if (recentEntries.isNotEmpty) {
      final sorted = List<HistoryEntry>.from(recentEntries)
        ..sort((a, b) => b.playedAt.compareTo(a.playedAt));

      for (final entry in sorted) {
        if (resolved.length >= limit) break;
        final rawTrack = entry.track.toTrack();
        final normId = rawTrack.id.replaceFirst('youtube_', '');
        if (seenTrackIds.contains(rawTrack.id) || seenTrackIds.contains(normId)) {
          continue;
        }
        seenTrackIds.add(rawTrack.id);
        seenTrackIds.add(normId);

        String resolvedImageUrl = rawTrack.imageUrl;

        if (!rawTrack.isYoutube) {
          final localMatch = localSongs.where((s) {
            if (s.id == rawTrack.id || s.id == normId) return true;
            if (s.filePath.isNotEmpty && s.filePath == rawTrack.filePath) return true;
            return s.title.trim().toLowerCase() == rawTrack.title.trim().toLowerCase() &&
                s.artist.trim().toLowerCase() == rawTrack.artist.trim().toLowerCase();
          }).firstOrNull;

          if (localMatch != null && localMatch.artworkPath.isNotEmpty) {
            resolvedImageUrl = localMatch.artworkPath;
          }
        } else {
          if (resolvedImageUrl.isEmpty || !resolvedImageUrl.startsWith('http')) {
            resolvedImageUrl = 'https://i.ytimg.com/vi/$normId/hqdefault.jpg';
          }
        }

        resolved.add(Track(
          id: rawTrack.id,
          title: rawTrack.title,
          artist: rawTrack.artist,
          imageUrl: resolvedImageUrl,
          duration: rawTrack.duration,
          filePath: rawTrack.filePath,
        ));
      }
    }

    // 2. Process cloud listening history if we haven't reached the limit
    if (resolved.length < limit && cloudHistory.isNotEmpty) {
      final sortedCloud = List<ListeningEvent>.from(cloudHistory)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      for (final event in sortedCloud) {
        if (resolved.length >= limit) break;
        final normId = event.trackId.replaceFirst('youtube_', '');
        if (seenTrackIds.contains(event.trackId) || seenTrackIds.contains(normId)) {
          continue;
        }
        seenTrackIds.add(event.trackId);
        seenTrackIds.add(normId);

        final isYoutube = event.source == 'youtube' || event.trackId.startsWith('youtube_');
        String resolvedImageUrl = event.imageUrl ?? '';

        if (isYoutube) {
          if (resolvedImageUrl.isEmpty || !resolvedImageUrl.startsWith('http')) {
            resolvedImageUrl = 'https://i.ytimg.com/vi/$normId/hqdefault.jpg';
          }
        } else {
          final localMatch = localSongs.where((s) {
            if (s.id == event.trackId || s.id == normId) return true;
            return s.title.trim().toLowerCase() == event.title.trim().toLowerCase() &&
                s.artist.trim().toLowerCase() == event.artist.trim().toLowerCase();
          }).firstOrNull;
          if (localMatch != null && localMatch.artworkPath.isNotEmpty) {
            resolvedImageUrl = localMatch.artworkPath;
          }
        }

        final m = event.durationSec ~/ 60;
        final s = event.durationSec % 60;
        final dur = '$m:${s.toString().padLeft(2, '0')}';

        resolved.add(Track(
          id: isYoutube && !event.trackId.startsWith('youtube_')
              ? 'youtube_${event.trackId}'
              : event.trackId,
          title: event.title,
          artist: event.artist,
          imageUrl: resolvedImageUrl,
          duration: dur,
        ));
      }
    }

    return resolved;
  }

  Widget _buildRecentlyPlayedList(
    BuildContext context,
    List<Track> recentlyPlayedTracks,
    MusicItem? currentTrack,
  ) {
    return Column(
      key: const ValueKey('recently_played_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Recently Played'),
        const SizedBox(height: 14),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: recentlyPlayedTracks.take(5).length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final track = recentlyPlayedTracks[index];
            return Consumer(
              builder: (context, ref, _) {
                final isTrackLoading = ref.watch(
                  playerControllerProvider.select((s) =>
                      s.loadingTrackId != null &&
                      isSameTrackId(s.loadingTrackId, track.id)),
                );
                return SongTile(
                  title: track.title,
                  artist: track.artist,
                  duration: track.duration,
                  imageUrl: track.imageUrl,
                  isPlaying: currentTrack?.id == track.id,
                  isLoading: isTrackLoading,
                  onTap: isTrackLoading
                      ? null
                      : () {
                          ref
                              .read(playerControllerProvider.notifier)
                              .selectTrack(track, recentlyPlayedTracks,
                                  playingFrom: 'Recently Played');
                        },
                );
              },
            );
          },
        ),
        const SizedBox(height: 36),
      ],
    );
  }

  List<MusicItem> _resolveContinueListeningQueue({
    required MusicItem targetTrack,
    required List<HistoryEntry> recentEntries,
    required List<MediaSong> localSongs,
    required List<MusicItem> activeQueue,
  }) {
    final normTargetId = targetTrack.id.replaceFirst('youtube_', '');

    // 1. If active player queue contains this track, preserve active queue!
    final activeIndex = activeQueue.indexWhere((t) =>
        t.id == targetTrack.id ||
        t.id.replaceFirst('youtube_', '') == normTargetId);
    if (activeIndex >= 0) {
      return activeQueue;
    }

    // 2. If target is in localSongs, use localSongs queue
    final localIndex = localSongs.indexWhere(
        (s) => s.id == targetTrack.id || s.id == normTargetId);
    if (localIndex >= 0) {
      return localSongs;
    }

    // 3. If recent entries exist, use the recent history queue
    if (recentEntries.isNotEmpty) {
      return recentEntries.map((e) => e.track.toTrack()).toList();
    }

    // 4. Standalone track
    return [targetTrack];
  }

  Widget _buildContinueListeningCard({
    required BuildContext context,
    required MusicItem? recentSong,
    required List<MusicItem> resolvedQueue,
  }) {
    if (recentSong == null) {
      return const SizedBox.shrink();
    }

    final imageUrl = recentSong.imageUrl;
    final hasHttpArt =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    final hasFileArt = !hasHttpArt && imageUrl.isNotEmpty;

    Widget artworkWidget = Container(
      width: 54,
      height: 54,
      color: AppColors.softClay,
      child: const Icon(
        Icons.music_note_rounded,
        color: AppColors.cocoaPlum,
      ),
    );

    if (hasHttpArt) {
      artworkWidget = Image.network(
        imageUrl,
        width: 54,
        height: 54,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 54,
          height: 54,
          color: AppColors.softClay,
          child: const Icon(
            Icons.music_note_rounded,
            color: AppColors.cocoaPlum,
          ),
        ),
      );
    } else if (hasFileArt) {
      try {
        final normPath = imageUrl.startsWith('file://')
            ? Uri.parse(imageUrl).toFilePath()
            : imageUrl;
        artworkWidget = Image.file(
          File(normPath),
          width: 54,
          height: 54,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 54,
            height: 54,
            color: AppColors.softClay,
            child: const Icon(
              Icons.music_note_rounded,
              color: AppColors.cocoaPlum,
            ),
          ),
        );
      } catch (_) {
        // Fallback assigned by default
      }
    }

    return GestureDetector(
      onTap: () {
        ref.read(playerControllerProvider.notifier).selectTrack(
              recentSong,
              resolvedQueue,
              playingFrom: 'Continue Listening',
            );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.oatBeige),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: artworkWidget,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recentSong.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.geist(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.cocoaPlum,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    recentSong.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.geist(
                      fontSize: 12,
                      color: AppColors.mutedMauve,
                    ),
                  ),
                ],
              ),
            ),
            Material(
              color: AppColors.dustyRose,
              shape: const CircleBorder(),
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 22,
                  color: AppColors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalTracksList(
      List<MediaAlbum> albums, List<MediaSong> songs) {
    final activeTrackId =
        ref.watch(playerControllerProvider.select((s) => s.currentTrack?.id));
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: songs.take(4).length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final song = songs[index];
        final isSongPlaying = activeTrackId == song.id;
        return SongTile(
          title: song.title,
          artist: song.artist,
          duration: song.duration,
          imageUrl: song.artworkPath,
          isPlaying: isSongPlaying,
          onTap: () {
            ref.read(playerControllerProvider.notifier).selectTrack(
                  song,
                  songs,
                  playingFrom: 'Device Tracks',
                );
          },
        );
      },
    );
  }

  Widget _buildAlbumsGrid(
      BuildContext context, List<MediaAlbum> albums, List<MediaSong> songs) {
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: albums.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final album = albums[index];
          return GestureDetector(
            onTap: () => context.push('/album/${album.id}', extra: album),
            child: SizedBox(
              width: 130,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: album.artworkPath.isNotEmpty
                        ? Image.file(
                            File(album.artworkPath.startsWith('file://')
                                ? Uri.parse(album.artworkPath).toFilePath()
                                : album.artworkPath),
                            width: 130,
                            height: 130,
                            fit: BoxFit.cover,
                            cacheWidth: 260,
                            cacheHeight: 260,
                            errorBuilder: (_, __, ___) => Container(
                              width: 130,
                              height: 130,
                              color: AppColors.softClay,
                              child: const Icon(
                                Icons.album_rounded,
                                color: AppColors.cocoaPlum,
                              ),
                            ),
                          )
                        : Container(
                            width: 130,
                            height: 130,
                            color: AppColors.softClay,
                            child: const Icon(
                              Icons.album_rounded,
                              color: AppColors.cocoaPlum,
                            ),
                          ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.geist(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.cocoaPlum,
                    ),
                  ),
                  Text(
                    album.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.geist(
                      fontSize: 11,
                      color: AppColors.mutedMauve,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCoverImage(String rawUrl) {
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      return Image.network(
        rawUrl,
        fit: BoxFit.cover,
        cacheWidth: 300,
        cacheHeight: 300,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(
            Icons.queue_music_rounded,
            size: 44,
            color: AppColors.cocoaPlum,
          ),
        ),
      );
    }
    try {
      final normalizedPath = rawUrl.startsWith('file://')
          ? Uri.parse(rawUrl).toFilePath()
          : rawUrl;
      return Image.file(
        File(normalizedPath),
        fit: BoxFit.cover,
        cacheWidth: 300,
        cacheHeight: 300,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(
            Icons.queue_music_rounded,
            size: 44,
            color: AppColors.cocoaPlum,
          ),
        ),
      );
    } catch (_) {
      return const Center(
        child: Icon(
          Icons.queue_music_rounded,
          size: 44,
          color: AppColors.cocoaPlum,
        ),
      );
    }
  }
}

