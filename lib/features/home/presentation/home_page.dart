import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/audio/providers.dart';
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
    final currentTrack = ref.watch(playerControllerProvider).currentTrack;
    final playlists = ref.watch(allPlaylistsProvider);
    final favorites = ref.watch(favoritesProvider);

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
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.dustyRose,
                  ),
                ),
              ),
              error: (e, _) => _buildDiscoveryErrorBanner(context, e),
            ),

            // ── 4. Local Music Spotlight (if present) ───────────────────────
            if (localSongs.isNotEmpty) ...[
              _buildSectionTitle('Continue Listening'),
              const SizedBox(height: 14),
              _buildContinueListeningCard(context, localSongs),
              const SizedBox(height: 32),

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

  // ── EDITORIAL HERO BANNER ──────────────────────────────────────────────────

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

        return Container(
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
              // Subtle gradient overlay from left
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        const Color(0xFFF8F1E8).withOpacity(0.92),
                        const Color(0xFFF8F1E8).withOpacity(0.75),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.48, 0.85],
                    ),
                  ),
                ),
              ),

              // Content on Left
              Positioned(
                left: isNarrow ? 20 : 28,
                top: isNarrow ? 18 : 24,
                bottom: isNarrow ? 18 : 24,
                right: isNarrow ? 40 : 180,
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
                right: 24,
                bottom: 20,
                child: Row(
                  children: [
                    // Dot indicators
                    Row(
                      children: List.generate(3, (index) {
                        final isActive = index == _heroSlideIndex;
                        return Container(
                          margin: const EdgeInsets.only(right: 6),
                          width: isActive ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.white
                                : AppColors.white.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(width: 14),

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
                            child: Image.network(
                              playlist.effectiveCoverUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(
                                  Icons.queue_music_rounded,
                                  size: 44,
                                  color: AppColors.cocoaPlum,
                                ),
                              ),
                            ),
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

        // ── 3. From Your Artists ─────────────────────────────────────────────
        if (sections.fromYourArtists.isNotEmpty) ...[
          _buildSectionTitle('From Your Artists'),
          const SizedBox(height: 6),
          Text(
            'Selected songs tailored to your taste',
            style: GoogleFonts.geist(
              fontSize: 13,
              color: AppColors.mutedMauve,
            ),
          ),
          const SizedBox(height: 14),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sections.fromYourArtists.take(6).length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final track = sections.fromYourArtists[index];
              final isPlaying = currentTrack?.id == track.id;

              return SongTile(
                title: track.title,
                artist: track.artist,
                duration: track.duration,
                imageUrl: track.imageUrl,
                isPlaying: isPlaying,
                onTap: () {
                  ref
                      .read(playerControllerProvider.notifier)
                      .selectTrack(track, sections.fromYourArtists, playingFrom: 'From Your Artists');
                },
              );
            },
          ),
          const SizedBox(height: 36),
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
        if (sections.recentlyPlayed.isNotEmpty) ...[
          _buildSectionTitle('Recently Played'),
          const SizedBox(height: 14),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sections.recentlyPlayed.take(5).length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final event = sections.recentlyPlayed[index];
              final m = event.durationSec ~/ 60;
              final s = event.durationSec % 60;
              final dur = '$m:${s.toString().padLeft(2, '0')}';
              return SongTile(
                title: event.title,
                artist: event.artist,
                duration: dur,
                imageUrl: null,
                isPlaying: currentTrack?.id == event.trackId,
                onTap: () {
                  final track = Track(
                    id: event.trackId,
                    title: event.title,
                    artist: event.artist,
                    imageUrl: '',
                    duration: dur,
                  );
                  ref
                      .read(playerControllerProvider.notifier)
                      .playTrack(track);
                },
              );
            },
          ),
          const SizedBox(height: 36),
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
    return InkWell(
      onTap: () {
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
            color: isPlaying ? AppColors.dustyRose : AppColors.oatBeige,
            width: isPlaying ? 1.5 : 1.0,
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
                      color: isPlaying ? AppColors.dustyRose : AppColors.cocoaPlum,
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
                color: isPlaying ? AppColors.dustyRose : AppColors.softClay.withOpacity(0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 20,
                color: isPlaying ? AppColors.white : AppColors.cocoaPlum,
              ),
            ),
          ],
        ),
      ),
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

  Widget _buildContinueListeningCard(
      BuildContext context, List<MediaSong> localSongs) {
    final recentSong = localSongs.first;
    return GestureDetector(
      onTap: () {
        ref.read(playerControllerProvider.notifier).playTrack(recentSong);
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
              child: Container(
                width: 54,
                height: 54,
                color: AppColors.softClay,
                child: const Icon(
                  Icons.music_note_rounded,
                  color: AppColors.cocoaPlum,
                ),
              ),
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
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: songs.take(4).length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final song = songs[index];
        return SongTile(
          title: song.title,
          artist: song.artist,
          duration: song.duration,
          isPlaying: false,
          onTap: () {
            ref.read(playerControllerProvider.notifier).playTrack(song);
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
                    child: Container(
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
}
