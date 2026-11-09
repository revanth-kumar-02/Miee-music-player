import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/audio/playback_state.dart';
import '../../../core/audio/providers.dart';
import '../../media/domain/models.dart';
import '../../media/providers/media_providers.dart';
import '../../../shared/widgets/widgets.dart';
import '../providers/search_providers.dart';
import '../domain/search_state.dart';
import '../domain/search_deduplicator.dart';
import '../../youtube/domain/youtube_model.dart';
import '../../youtube/domain/music_result_classifier.dart';
import '../../youtube/presentation/widgets/youtube_result_tile.dart';
import '../../recommendations/providers/recommendation_providers.dart';
import '../../recommendations/data/recommendation_service.dart';
import '../../library/providers/library_providers.dart';
import '../../../shared/models/track.dart';
import '../../onboarding/domain/artist_model.dart';
import '../../onboarding/data/artist_discovery_repository.dart';
import '../../artwork/presentation/miee_artwork_image.dart';

/// Recreated Miee Search Screen matching the reference design:
/// - Cocoa Plum sidebar + Vanilla Cream canvas
/// - Pill search field with active query and clear 'x' button
/// - Filter chips: All, Songs, Artists, Albums, Playlists with Dusty Rose selection
/// - "Top result" card in Cocoa Plum with artist portrait and Dusty Rose play button
/// - Songs list with artwork, duration, and overflow menu
/// - Albums section with horizontal cards
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final ScrollController _scrollController;
  late final TextEditingController _searchController;
  String _searchQuery = '';

  final List<String> _filters = const [
    'All',
    'Songs',
    'Artists',
    'Albums',
    'Playlists',
  ];

  late final FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    final initialQuery = ref.read(searchNotifierProvider).query;
    _searchQuery = initialQuery;
    _searchController = TextEditingController(text: initialQuery);
    _searchController.addListener(_handleSearchQueryChange);
    _searchFocusNode = FocusNode();
    _searchFocusNode.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.removeListener(_handleSearchQueryChange);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleSearchQueryChange() {
    setState(() {
      _searchQuery = _searchController.text;
    });
    ref
        .read(searchNotifierProvider.notifier)
        .updateQuery(_searchController.text);
  }

  void _handleSearchSubmit(String query) {
    if (query.trim().isEmpty) return;
    _searchFocusNode.unfocus();
    ref.read(searchNotifierProvider.notifier).searchNow(query);
  }

  void _applyHistoryQuery(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    setState(() => _searchQuery = query);
    _searchFocusNode.unfocus();
    ref.read(searchNotifierProvider.notifier).searchNow(query);
  }

  void _playYouTubeResult(YouTubeVideo video) {
    // Strict validation: Reject commentary, exposés, podcasts or non-music videos
    if (!MusicResultClassifier.isValidIndividualSong(video,
        query: _searchQuery)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This video is not a recognized music track.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final isLoading = ref.read(playerControllerProvider.select((s) =>
        s.loadingTrackId != null && isSameTrackId(s.loadingTrackId, video.id)));
    if (isLoading) return;

    final targetTrack = video.toTrack();
    final playerNotifier = ref.read(playerControllerProvider.notifier);

    // Play the selected track as the queue's current item.
    // Separation of Search and Queue: search results must not become the playback queue.
    // Intelligent queue replenishment will seed context-aware upcoming recommendations from this track.
    playerNotifier.selectTrack(
      targetTrack,
      [targetTrack],
      playingFrom:
          'Search: ${targetTrack.artist.isNotEmpty ? targetTrack.artist : 'Track'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchNotifierProvider);
    final localSongs = ref.watch(songsProvider);
    final localAlbums = ref.watch(albumsProvider);
    final localArtists = ref.watch(artistsProvider);
    final favorites = ref.watch(favoritesProvider);
    final recs = ref.watch(recommendationSectionsProvider).valueOrNull;

    final activeQuery =
        _searchQuery.isNotEmpty ? _searchQuery : searchState.query;
    final hasFocus = _searchFocusNode.hasFocus;
    final isSearching = searchState.hasQuery;
    final showLiveSuggestions = hasFocus && activeQuery.isNotEmpty;
    final showRecentSearches = hasFocus && activeQuery.isEmpty;

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 960;

    // Sync search input controller with global search query when not focused
    ref.listen<String>(searchNotifierProvider.select((s) => s.query),
        (previous, next) {
      if (_searchController.text != next && !_searchFocusNode.hasFocus) {
        _searchController.text = next;
        _searchQuery = next;
      }
    });

    return Scaffold(
      backgroundColor: AppColors.vanillaCream,
      appBar: isDesktop ? null : const MieeBrandHeader(title: 'Search'),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 28.0 : AppSpacing.marginMobile,
          vertical: 12.0,
        ),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // On mobile, show the search input bar. On desktop, the search bar is in the top header.
            if (!isDesktop) ...[
              AppSearchBar(
                controller: _searchController,
                focusNode: _searchFocusNode,
                placeholder: 'Search songs, artists, albums...',
                onSubmitted: _handleSearchSubmit,
              ),
              const SizedBox(height: 14),
            ],

            // 1. Live Music Suggestions while typing
            if (showLiveSuggestions) ...[
              _buildLiveSuggestionsList(
                searchState.liveSuggestions,
                searchState.isSuggestionsLoading,
              ),
            ]
            // 2. Recent Searches list when focused with empty query
            else if (showRecentSearches) ...[
              _buildRecentSearches(searchState.recentSearches),
            ]
            // 3. Main Results Grid (when submitted or viewing results)
            else if (isSearching) ...[
              // Filter Chips Row
              _buildFilterChips(searchState.activeFilter),
              const SizedBox(height: 20),

              // Active Query Header (Editorial indicator when searching)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  children: [
                    Text(
                      'Results for ',
                      style: GoogleFonts.geist(
                        fontSize: 14,
                        color: AppColors.mutedMauve,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        '"${searchState.query}"',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.cocoaPlum,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        _searchController.clear();
                        ref
                            .read(searchNotifierProvider.notifier)
                            .updateQuery('');
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.oatBeige.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.close_rounded,
                                size: 14, color: AppColors.mutedMauve),
                            const SizedBox(width: 3),
                            Text(
                              'Clear',
                              style: GoogleFonts.geist(
                                fontSize: 11.5,
                                color: AppColors.mutedMauve,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              _buildSearchResults(searchState),
            ]
            // 4. Default Exploration matching the reference layout
            else ...[
              _buildFilterChips(searchState.activeFilter),
              const SizedBox(height: 20),
              _buildDefaultExploreView(
                localArtists,
                localSongs,
                localAlbums,
                favorites,
                recs,
              ),
            ],
            const SizedBox(height: 100.0),
          ],
        ),
      ),
    );
  }

  // ── FILTER CHIPS ───────────────────────────────────────────────────────────

  Widget _buildFilterChips(String activeFilter) {
    return SizedBox(
      height: 34.0,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isSelected = activeFilter == filter;

          return InkWell(
            onTap: () {
              ref.read(searchNotifierProvider.notifier).setFilter(filter);
            },
            borderRadius: BorderRadius.circular(17),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.dustyRose : AppColors.white,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: isSelected ? AppColors.dustyRose : AppColors.oatBeige,
                  width: 1.0,
                ),
              ),
              child: Text(
                filter,
                style: GoogleFonts.geist(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppColors.white : AppColors.cocoaPlum,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── TOP RESULT CARD (Cocoa Plum) ───────────────────────────────────────────

  Widget _buildTopResultCard({
    required String name,
    String? subtitle,
    String? imageUrl,
    bool isSong = false,
    required VoidCallback onTap,
    required VoidCallback onPlay,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top result',
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.cocoaPlum,
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.cocoaPlum,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.cocoaPlum.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Avatar (Circle for Artist, Rounded rect for Song)
                ClipRRect(
                  borderRadius: BorderRadius.circular(isSong ? 12 : 36),
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.softClay, width: 2),
                      color: AppColors.softClay,
                    ),
                    child: (imageUrl != null && imageUrl.isNotEmpty)
                        ? MieeArtworkImage(
                            explicitUrl: imageUrl,
                            width: 72,
                            height: 72,
                            borderRadius:
                                BorderRadius.circular(isSong ? 12 : 36),
                            fit: BoxFit.cover,
                            errorWidget: Center(
                              child: Icon(
                                isSong
                                    ? Icons.music_note_rounded
                                    : Icons.person_rounded,
                                color: AppColors.cocoaPlum,
                                size: 32,
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'M',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.cocoaPlum,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 20),

                // Name & Subtitle / Badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.vanillaCream,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle ?? (isSong ? 'Song' : 'Artist'),
                        style: GoogleFonts.geist(
                          fontSize: 13,
                          color: AppColors.softClay,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Circular Dusty Rose Play Button
                Material(
                  color: AppColors.dustyRose,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onPlay,
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 26,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── DEFAULT EXPLORE VIEW (Matches Reference Screen 2) ─────────────────────

  Widget _buildDefaultExploreView(
    List<MediaArtist> localArtists,
    List<MediaSong> localSongs,
    List<MediaAlbum> localAlbums,
    List<Track> favorites,
    RecommendationSections? recs,
  ) {
    const popularSearches = [
      (
        title: 'Lo-fi Beats',
        asset: 'assets/images/banner_discover.png',
        query: 'Lo-fi Beats chill study'
      ),
      (
        title: 'Focus Mix',
        asset: 'assets/images/banner_your_music.png',
        query: 'Deep focus ambient instrumental'
      ),
      (
        title: 'Anime OST',
        asset: 'assets/images/banner_listen_together.png',
        query: 'Anime soundtrack orchestral'
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. Browse 2x2 Grid ──
        Text(
          'Browse',
          style: GoogleFonts.geist(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.denseObsidian,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 12),

        // 2x2 Grid
        Row(
          children: [
            // Charts (Electric Cobalt)
            Expanded(
              child: GestureDetector(
                onTap: () => _applyHistoryQuery('Top Global Charts'),
                child: Container(
                  height: 76,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.electricCobalt,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.electricCobalt.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Charts',
                        style: GoogleFonts.geist(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const Icon(
                        Icons.bar_chart_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // New Releases (Pale Concrete)
            Expanded(
              child: GestureDetector(
                onTap: () => _applyHistoryQuery('New Releases 2026'),
                child: Container(
                  height: 76,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.paleConcrete,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'New\nReleases',
                        style: GoogleFonts.geist(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          color: AppColors.denseObsidian,
                        ),
                      ),
                      const Icon(
                        Icons.history_toggle_off_rounded,
                        color: AppColors.electricCobalt,
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            // Genres (Pale Concrete)
            Expanded(
              child: GestureDetector(
                onTap: () => _applyHistoryQuery('Acoustic Pop Indie'),
                child: Container(
                  height: 76,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.paleConcrete,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Genres',
                        style: GoogleFonts.geist(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.denseObsidian,
                        ),
                      ),
                      const Icon(
                        Icons.local_offer_outlined,
                        color: AppColors.electricCobalt,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Moods (Pale Concrete)
            Expanded(
              child: GestureDetector(
                onTap: () => _applyHistoryQuery('Chill Relaxing Calm'),
                child: Container(
                  height: 76,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.paleConcrete,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Moods',
                        style: GoogleFonts.geist(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.denseObsidian,
                        ),
                      ),
                      const Icon(
                        Icons.sentiment_satisfied_alt_rounded,
                        color: AppColors.electricCobalt,
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),

        // ── 2. Popular Searches Section ──
        Text(
          'Popular Searches',
          style: GoogleFonts.geist(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.denseObsidian,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 12),

        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: popularSearches.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = popularSearches[index];
            return InkWell(
              onTap: () => _applyHistoryQuery(item.query),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 40,
                        height: 40,
                        color: AppColors.paleConcrete,
                        child: Image.asset(
                          item.asset,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.music_note_rounded,
                            color: AppColors.industrialSteel,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        item.title,
                        style: GoogleFonts.geist(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.denseObsidian,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.industrialSteel,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAlbumCard(
    String title,
    String year,
    String? imageUrl, {
    bool isGrid = false,
  }) {
    return InkWell(
      onTap: () => _applyHistoryQuery(title),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: isGrid ? double.infinity : 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            isGrid
                ? AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: (imageUrl != null && imageUrl.isNotEmpty)
                          ? MieeArtworkImage(
                              explicitUrl: imageUrl,
                              fit: BoxFit.cover,
                              errorWidget: Container(
                                color: AppColors.softClay,
                                child: const Icon(
                                  Icons.album_rounded,
                                  color: AppColors.cocoaPlum,
                                ),
                              ),
                            )
                          : Container(
                              color: AppColors.softClay,
                              child: const Icon(
                                Icons.album_rounded,
                                color: AppColors.cocoaPlum,
                              ),
                            ),
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: (imageUrl != null && imageUrl.isNotEmpty)
                        ? MieeArtworkImage(
                            explicitUrl: imageUrl,
                            width: 130,
                            height: 130,
                            borderRadius: BorderRadius.circular(12),
                            fit: BoxFit.cover,
                            errorWidget: Container(
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
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.geist(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.cocoaPlum,
              ),
            ),
            Text(
              year,
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
  }

  Widget _buildPlaylistCard({
    required String title,
    required String subtitle,
    required String? imageUrl,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: (imageUrl != null && imageUrl.isNotEmpty)
                  ? MieeArtworkImage(
                      explicitUrl: imageUrl,
                      width: 130,
                      height: 130,
                      borderRadius: BorderRadius.circular(12),
                      fit: BoxFit.cover,
                      errorWidget: Container(
                        width: 130,
                        height: 130,
                        color: AppColors.softClay,
                        child: const Icon(
                          Icons.queue_music_rounded,
                          color: AppColors.mutedMauve,
                          size: 36,
                        ),
                      ),
                    )
                  : Container(
                      width: 130,
                      height: 130,
                      color: AppColors.softClay,
                      child: const Icon(
                        Icons.queue_music_rounded,
                        color: AppColors.mutedMauve,
                        size: 36,
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.geist(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.cocoaPlum,
              ),
            ),
            Text(
              subtitle,
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
  }

  Widget _buildPlaylistListTile({
    required String title,
    required String subtitle,
    required String? imageUrl,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.oatBeige, width: 1),
            boxShadow: [
              BoxShadow(
                color: AppColors.cocoaPlum.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: (imageUrl != null && imageUrl.isNotEmpty)
                    ? MieeArtworkImage(
                        explicitUrl: imageUrl,
                        width: 52,
                        height: 52,
                        borderRadius: BorderRadius.circular(10),
                        fit: BoxFit.cover,
                        errorWidget: Container(
                          width: 52,
                          height: 52,
                          color: AppColors.softClay,
                          child: const Icon(
                            Icons.queue_music_rounded,
                            color: AppColors.mutedMauve,
                            size: 24,
                          ),
                        ),
                      )
                    : Container(
                        width: 52,
                        height: 52,
                        color: AppColors.softClay,
                        child: const Icon(
                          Icons.queue_music_rounded,
                          color: AppColors.mutedMauve,
                          size: 24,
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.geist(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.cocoaPlum,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.geist(
                        fontSize: 12,
                        color: AppColors.mutedMauve,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.mutedMauve),
            ],
          ),
        ),
      ),
    );
  }

  // ── SEARCH RESULTS (Active Search Query) ───────────────────────────────────

  Widget _buildSearchResults(SearchState state) {
    if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
      final hasLocalResults = state.localSongs.isNotEmpty ||
          state.localAlbums.isNotEmpty ||
          state.localArtists.isNotEmpty ||
          state.localPlaylists.isNotEmpty;

      if (!hasLocalResults) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
          alignment: Alignment.center,
          child: Column(
            children: [
              const Icon(
                Icons.wifi_off_outlined,
                size: 48,
                color: AppColors.dustyRose,
              ),
              const SizedBox(height: 14),
              Text(
                state.errorMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.geist(
                  color: AppColors.cocoaPlum,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }
    }

    final isDoneLoading = !state.isLoading;
    final isLoading = state.isLoading;
    final filter = state.activeFilter;

    if (isLoading && state.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.dustyRose),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Searching for "${state.query}"...',
                style: GoogleFonts.geist(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.mutedMauve,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Category-specific empty states when loading completes
    if (isDoneLoading) {
      if (filter == 'Artists' && state.totalArtistsCount == 0) {
        return _buildCategoryEmptyState(
          icon: Icons.person_search_rounded,
          title: 'No artists found',
          message: 'No artist profiles found for "${state.query}".',
        );
      }
      if (filter == 'Songs' && state.totalSongsCount == 0) {
        return _buildCategoryEmptyState(
          icon: Icons.music_off_rounded,
          title: 'No songs found',
          message:
              'No songs found for "${state.query}". Try searching another title.',
        );
      }
      if (filter == 'Albums' && state.totalAlbumsCount == 0) {
        return _buildCategoryEmptyState(
          icon: Icons.album_outlined,
          title: 'No albums found',
          message: 'No albums found for "${state.query}".',
        );
      }
      if (filter == 'Playlists' && state.totalPlaylistsCount == 0) {
        return _buildCategoryEmptyState(
          icon: Icons.queue_music_rounded,
          title: 'No playlists found',
          message: 'No playlists found for "${state.query}".',
        );
      }
      if (state.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.softClay,
                  ),
                  child: const Icon(
                    Icons.search_off_rounded,
                    size: 32,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'No results found',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'No matches found for "${state.query}". Try searching another title.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.geist(
                    fontSize: 13.5,
                    color: AppColors.mutedMauve,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    final showArtists = filter == 'All' || filter == 'Artists';
    final showSongs = filter == 'All' || filter == 'Songs';
    final showAlbums = filter == 'All' || filter == 'Albums';
    final showPlaylists = filter == 'All' || filter == 'Playlists';

    final activeTrackId = ref.watch(playerControllerProvider.select(
        (s) => s.status == PlaybackStatus.playing ? s.currentTrack?.id : null));

    final cleanQuery = state.query.trim().toLowerCase();
    final normCleanQuery = cleanQuery.replaceAll(RegExp(r'[^a-z0-9]'), '');

    // Aggregate unique artists across online and local
    final allArtists = <ArtistModel>[];
    final seenArtistIds = <String>{};
    final seenArtistNames = <String>{};

    for (final a in state.onlineArtists) {
      if (a.id.isNotEmpty && seenArtistIds.add(a.id)) {
        final norm = a.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (norm.isNotEmpty) seenArtistNames.add(norm);
        allArtists.add(a);
      }
    }
    for (final a in state.localArtists) {
      final norm = a.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (seenArtistIds.add(a.id) &&
          (norm.isEmpty || seenArtistNames.add(norm))) {
        allArtists.add(ArtistModel(
          id: a.id,
          name: a.name,
          imageUrl: a.artworkPath ?? '',
        ));
      }
    }

    // Top Result matching
    final matchingArtist = allArtists.cast<ArtistModel?>().firstWhere(
          (a) =>
              a != null &&
              (a.name.toLowerCase() == cleanQuery ||
                  a.name.toLowerCase().contains(cleanQuery) ||
                  cleanQuery.contains(a.name.toLowerCase()) ||
                  (normCleanQuery.length >= 3 &&
                      a.name
                              .toLowerCase()
                              .replaceAll(RegExp(r'[^a-z0-9]'), '') ==
                          normCleanQuery)),
          orElse: () => (filter == 'Artists' && allArtists.isNotEmpty
              ? allArtists.first
              : null),
        );

    final matchingSong = state.youtubeResults.cast<YouTubeVideo?>().firstWhere(
          (v) =>
              v != null &&
              (v.title.toLowerCase().contains(cleanQuery) ||
                  cleanQuery.contains(v.title.toLowerCase())),
          orElse: () => (state.youtubeResults.isNotEmpty
              ? state.youtubeResults.first
              : null),
        );

    final isArtistHighProminence = matchingArtist != null &&
        (DeezerArtistRepository.findCuratedByName(matchingArtist.name) !=
                null ||
            matchingArtist.fanCount >= 5000);

    final hasExactSongMatch = matchingSong != null &&
        (matchingSong.title.toLowerCase().contains(cleanQuery) ||
            cleanQuery.contains(matchingSong.title.toLowerCase()) ||
            (matchingSong.canonicalTitle != null &&
                matchingSong.canonicalTitle!
                    .toLowerCase()
                    .contains(cleanQuery)));

    final preferSongTopResult = (hasExactSongMatch && !isArtistHighProminence);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Offline Notification Banner when offline with local items
        if (state.errorMessage != null && state.errorMessage!.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.softClay.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.oatBeige),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.wifi_off_outlined,
                  size: 20,
                  color: AppColors.dustyRose,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Offline — Showing local library results',
                    style: GoogleFonts.geist(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.cocoaPlum,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 1. Top Result Card (Rendered only in 'All' overview tab)
        if (filter == 'All') ...[
          if (preferSongTopResult) ...[
            _buildTopResultCard(
              name: matchingSong.canonicalTitle ?? matchingSong.title,
              subtitle:
                  matchingSong.canonicalArtist ?? matchingSong.channelTitle,
              imageUrl:
                  matchingSong.highResArtworkUrl ?? matchingSong.thumbnailUrl,
              isSong: true,
              onTap: () {
                _playYouTubeResult(matchingSong);
              },
              onPlay: () {
                _playYouTubeResult(matchingSong);
              },
            ),
            const SizedBox(height: 28),
          ] else if (matchingArtist != null) ...[
            _buildTopResultCard(
              name: matchingArtist.name,
              subtitle: matchingArtist.fanCount > 0
                  ? '${_formatNumber(matchingArtist.fanCount)} fans'
                  : 'Artist',
              imageUrl: matchingArtist.imageUrl,
              onTap: () => _navigateToArtist(context, matchingArtist),
              onPlay: () {
                if (state.youtubeResults.isNotEmpty) {
                  final artistNorm =
                      SearchDeduplicator.normalizeArtist(matchingArtist.name);
                  final artistTrack = state.youtubeResults.firstWhere(
                    (v) =>
                        SearchDeduplicator.normalizeArtist(v.channelTitle) ==
                        artistNorm,
                    orElse: () => state.youtubeResults.first,
                  );
                  _playYouTubeResult(artistTrack);
                }
              },
            ),
            const SizedBox(height: 28),
          ] else if (matchingSong != null) ...[
            _buildTopResultCard(
              name: matchingSong.canonicalTitle ?? matchingSong.title,
              subtitle:
                  matchingSong.canonicalArtist ?? matchingSong.channelTitle,
              imageUrl:
                  matchingSong.highResArtworkUrl ?? matchingSong.thumbnailUrl,
              isSong: true,
              onTap: () {
                _playYouTubeResult(matchingSong);
              },
              onPlay: () {
                _playYouTubeResult(matchingSong);
              },
            ),
            const SizedBox(height: 28),
          ],
        ],

        // 2. Artists Section
        if (showArtists && allArtists.isNotEmpty) ...[
          if (filter == 'Artists') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Artists',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                Text(
                  '${allArtists.length} FOUND',
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedMauve,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...allArtists.map((artist) => _buildArtistListTile(artist)),
            const SizedBox(height: 24),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Artists',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                Text(
                  '${allArtists.length} found',
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    color: AppColors.mutedMauve,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 145,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: allArtists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, idx) =>
                    _buildArtistCard(allArtists[idx]),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],

        // 3. Songs Section
        if (showSongs) ...[
          if (state.localSongs.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Local Songs',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                Text(
                  '${state.localSongs.length} found',
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    color: AppColors.mutedMauve,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...(filter == 'All' ? state.localSongs.take(5) : state.localSongs)
                .map(
              (song) {
                final isPlaying = activeTrackId == song.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SongTile(
                    title: song.title,
                    artist: song.artist,
                    duration: song.duration,
                    imageUrl: song.artworkPath,
                    isPlaying: isPlaying,
                    onTap: () {
                      ref.read(playerControllerProvider.notifier).selectTrack(
                          song, [song],
                          playingFrom: 'Local Search');
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
          if (state.youtubeResults.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  state.localSongs.isEmpty ? 'Songs' : 'Online Tracks',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                Text(
                  '${state.youtubeResults.length} FOUND',
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedMauve,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...state.youtubeResults.take(filter == 'All' ? 5 : 50).map(
                  (video) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: YouTubeResultTile(
                      video: video,
                      onTap: () => _playYouTubeResult(video),
                    ),
                  ),
                ),
            const SizedBox(height: 24),
          ],
        ],

        // 4. Albums Section
        if (showAlbums &&
            (state.onlineAlbums.isNotEmpty ||
                state.localAlbums.isNotEmpty)) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Albums',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.cocoaPlum,
                ),
              ),
              Text(
                '${state.totalAlbumsCount} ${filter == 'Albums' ? 'FOUND' : 'found'}',
                style: GoogleFonts.geist(
                  fontSize: 12,
                  fontWeight:
                      filter == 'Albums' ? FontWeight.w600 : FontWeight.normal,
                  color: AppColors.mutedMauve,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (filter == 'Albums') ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.78,
              ),
              itemCount: state.onlineAlbums.length + state.localAlbums.length,
              itemBuilder: (context, idx) {
                if (idx < state.onlineAlbums.length) {
                  final album = state.onlineAlbums[idx];
                  return _buildAlbumCard(
                    album.title,
                    album.releaseDate.isNotEmpty
                        ? album.releaseDate.split('-').first
                        : album.artistName,
                    album.coverUrl,
                    isGrid: true,
                  );
                } else {
                  final album =
                      state.localAlbums[idx - state.onlineAlbums.length];
                  return _buildAlbumCard(
                    album.title,
                    album.artist,
                    album.artworkPath,
                    isGrid: true,
                  );
                }
              },
            ),
            const SizedBox(height: 24),
          ] else ...[
            SizedBox(
              height: 180,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: [
                  ...state.onlineAlbums.map(
                    (album) => Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: _buildAlbumCard(
                        album.title,
                        album.releaseDate.isNotEmpty
                            ? album.releaseDate.split('-').first
                            : album.artistName,
                        album.coverUrl,
                      ),
                    ),
                  ),
                  ...state.localAlbums.map(
                    (album) => Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: _buildAlbumCard(
                        album.title,
                        album.artist,
                        album.artworkPath,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],

        // 5. Playlists Section
        if (showPlaylists &&
            (state.onlinePlaylists.isNotEmpty ||
                state.localPlaylists.isNotEmpty)) ...[
          if (filter == 'Playlists') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Playlists',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                Text(
                  '${state.totalPlaylistsCount} FOUND',
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedMauve,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...state.localPlaylists.map(
              (playlist) => _buildPlaylistListTile(
                title: playlist.name,
                subtitle: '${playlist.trackCount} tracks · Local Playlist',
                imageUrl: null,
                onTap: () => context
                    .push('/playlist/${Uri.encodeComponent(playlist.id)}'),
              ),
            ),
            ...state.onlinePlaylists.map(
              (playlist) => _buildPlaylistListTile(
                title: playlist.title,
                subtitle: '${playlist.trackCount} tracks · ${playlist.author}',
                imageUrl: playlist.thumbnailUrl,
                onTap: () => _applyHistoryQuery(playlist.title),
              ),
            ),
            const SizedBox(height: 24),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Playlists',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                Text(
                  '${state.totalPlaylistsCount} found',
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    color: AppColors.mutedMauve,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: [
                  ...state.localPlaylists.map(
                    (playlist) => Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: _buildPlaylistCard(
                        title: playlist.name,
                        subtitle: '${playlist.trackCount} tracks',
                        imageUrl: null,
                        onTap: () => context.push(
                            '/playlist/${Uri.encodeComponent(playlist.id)}'),
                      ),
                    ),
                  ),
                  ...state.onlinePlaylists.map(
                    (playlist) => Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: _buildPlaylistCard(
                        title: playlist.title,
                        subtitle: '${playlist.trackCount} tracks',
                        imageUrl: playlist.thumbnailUrl,
                        onTap: () => _applyHistoryQuery(playlist.title),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ],
    );
  }

  void _navigateToArtist(BuildContext context, dynamic artist) {
    if (artist is ArtistModel) {
      context.push('/artist/${Uri.encodeComponent(artist.id.trim())}',
          extra: artist);
    } else if (artist is MediaArtist) {
      final model = ArtistModel(
        id: artist.id,
        name: artist.name,
        imageUrl: artist.artworkPath ?? '',
      );
      context.push('/artist/${Uri.encodeComponent(artist.id.trim())}',
          extra: model);
    }
  }

  String _formatNumber(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(0)}K';
    }
    return count.toString();
  }

  Widget _buildArtistCard(ArtistModel artist) {
    return InkWell(
      onTap: () => _navigateToArtist(context, artist),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 104,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.oatBeige, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cocoaPlum.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ArtistAvatar(
                name: artist.name,
                imageUrl: artist.imageUrl,
                radius: 36,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.geist(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.cocoaPlum,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              artist.fanCount > 0
                  ? '${_formatNumber(artist.fanCount)} fans'
                  : 'Artist',
              style: GoogleFonts.geist(
                fontSize: 11,
                color: AppColors.mutedMauve,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtistListTile(ArtistModel artist) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _navigateToArtist(context, artist),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.oatBeige, width: 1),
            boxShadow: [
              BoxShadow(
                color: AppColors.cocoaPlum.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.softClay, width: 1.5),
                ),
                child: ArtistAvatar(
                  name: artist.name,
                  imageUrl: artist.imageUrl,
                  radius: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artist.name,
                      style: GoogleFonts.geist(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.cocoaPlum,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.oatBeige.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Artist',
                            style: GoogleFonts.geist(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.dustyRose,
                            ),
                          ),
                        ),
                        if (artist.fanCount > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '·  ${_formatNumber(artist.fanCount)} fans',
                            style: GoogleFonts.geist(
                              fontSize: 12,
                              color: AppColors.mutedMauve,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: AppColors.mutedMauve,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48.0, horizontal: 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.softClay,
              ),
              child: Icon(
                icon,
                size: 32,
                color: AppColors.cocoaPlum,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: GoogleFonts.playfairDisplay(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.cocoaPlum,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.geist(
                fontSize: 13.5,
                color: AppColors.mutedMauve,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── AUTOCOMPLETE & RECENT SEARCHES ─────────────────────────────────────────

  // ── AUTOCOMPLETE & LIVE MUSIC SUGGESTIONS ──────────────────────────────────

  Widget _buildLiveSuggestionsList(
    List<MusicSuggestion> suggestions,
    bool isLoading,
  ) {
    if (suggestions.isEmpty && isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.dustyRose),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Finding music for "$_searchQuery"...',
              style: GoogleFonts.geist(
                fontSize: 13.5,
                color: AppColors.mutedMauve,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (suggestions.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.music_off_outlined,
              size: 36,
              color: AppColors.mutedMauve,
            ),
            const SizedBox(height: 12),
            Text(
              'No music suggestions for "$_searchQuery"',
              style: GoogleFonts.geist(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.cocoaPlum,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Press Enter or search to see all results',
              style: GoogleFonts.geist(
                fontSize: 12,
                color: AppColors.mutedMauve,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'SUGGESTIONS',
            style: GoogleFonts.geist(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.mutedMauve,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.oatBeige),
            boxShadow: [
              BoxShadow(
                color: AppColors.cocoaPlum.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: suggestions.length,
            separatorBuilder: (_, __) =>
                const Divider(color: AppColors.oatBeige, height: 1, indent: 58),
            itemBuilder: (context, index) {
              final suggestion = suggestions[index];
              return _buildSuggestionTile(suggestion);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestionTile(MusicSuggestion suggestion) {
    final isArtist = suggestion.type == SuggestionType.artist;
    final isSong = suggestion.type == SuggestionType.song;
    final isAlbum = suggestion.type == SuggestionType.album;
    final isPlaylist = suggestion.type == SuggestionType.playlist;
    final isQuery = suggestion.type == SuggestionType.searchQuery;

    Widget leadingWidget;
    if (isQuery) {
      leadingWidget = Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.softClay,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.search_rounded,
            color: AppColors.dustyRose, size: 20),
      );
    } else if (isArtist) {
      leadingWidget = ClipOval(
        child: (suggestion.imageUrl != null && suggestion.imageUrl!.isNotEmpty)
            ? MieeArtworkImage(
                explicitUrl: suggestion.imageUrl!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorWidget: Container(
                  width: 40,
                  height: 40,
                  color: AppColors.softClay,
                  child: const Icon(Icons.person,
                      color: AppColors.cocoaPlum, size: 22),
                ),
              )
            : Container(
                width: 40,
                height: 40,
                color: AppColors.softClay,
                child: const Icon(Icons.person,
                    color: AppColors.cocoaPlum, size: 22),
              ),
      );
    } else {
      leadingWidget = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: (suggestion.imageUrl != null && suggestion.imageUrl!.isNotEmpty)
            ? MieeArtworkImage(
                explicitUrl: suggestion.imageUrl!,
                width: 40,
                height: 40,
                borderRadius: BorderRadius.circular(8),
                fit: BoxFit.cover,
                errorWidget: Container(
                  width: 40,
                  height: 40,
                  color: AppColors.softClay,
                  child: Icon(
                    isAlbum
                        ? Icons.album_rounded
                        : isPlaylist
                            ? Icons.queue_music_rounded
                            : Icons.music_note_rounded,
                    color: AppColors.cocoaPlum,
                    size: 20,
                  ),
                ),
              )
            : Container(
                width: 40,
                height: 40,
                color: AppColors.softClay,
                child: Icon(
                  isAlbum
                      ? Icons.album_rounded
                      : isPlaylist
                          ? Icons.queue_music_rounded
                          : Icons.music_note_rounded,
                  color: AppColors.cocoaPlum,
                  size: 20,
                ),
              ),
      );
    }

    Widget trailingWidget;
    if (isSong) {
      trailingWidget = const Icon(
        Icons.play_circle_outline_rounded,
        color: AppColors.dustyRose,
        size: 22,
      );
    } else if (isQuery) {
      trailingWidget = const Icon(
        Icons.north_west_rounded,
        color: AppColors.mutedMauve,
        size: 16,
      );
    } else {
      trailingWidget = const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.mutedMauve,
        size: 20,
      );
    }

    return InkWell(
      onTap: () => _handleSuggestionTap(suggestion),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            leadingWidget,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    suggestion.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.geist(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color:
                          isQuery ? AppColors.dustyRose : AppColors.cocoaPlum,
                    ),
                  ),
                  if (!isQuery) ...[
                    const SizedBox(height: 2),
                    Text(
                      suggestion.typeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.geist(
                        fontSize: 12,
                        color: AppColors.mutedMauve,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailingWidget,
          ],
        ),
      ),
    );
  }

  void _handleSuggestionTap(MusicSuggestion suggestion) {
    switch (suggestion.type) {
      case SuggestionType.artist:
        _searchFocusNode.unfocus();
        if (suggestion.entity is ArtistModel) {
          _navigateToArtist(context, suggestion.entity);
        } else if (suggestion.entity is MediaArtist) {
          _navigateToArtist(context, suggestion.entity);
        } else {
          context.push('/artist/${Uri.encodeComponent(suggestion.id.trim())}');
        }
        break;

      case SuggestionType.song:
        if (suggestion.entity is YouTubeVideo) {
          final video = suggestion.entity as YouTubeVideo;
          _playYouTubeResult(video);
        } else if (suggestion.entity is MediaSong) {
          final song = suggestion.entity as MediaSong;
          ref.read(playerControllerProvider.notifier).selectTrack(song, [song]);
        }
        break;

      case SuggestionType.album:
        _searchFocusNode.unfocus();
        if (suggestion.entity is ArtistAlbum) {
          final album = suggestion.entity as ArtistAlbum;
          _searchController.text = album.title;
          _searchQuery = album.title;
          ref.read(searchNotifierProvider.notifier).searchNow(album.title);
        } else if (suggestion.entity is MediaAlbum) {
          final album = suggestion.entity as MediaAlbum;
          _searchController.text = album.title;
          _searchQuery = album.title;
          ref.read(searchNotifierProvider.notifier).searchNow(album.title);
        } else {
          _searchController.text = suggestion.title;
          _searchQuery = suggestion.title;
          ref.read(searchNotifierProvider.notifier).searchNow(suggestion.title);
        }
        break;

      case SuggestionType.playlist:
        _searchFocusNode.unfocus();
        if (suggestion.entity is MediaPlaylist) {
          final p = suggestion.entity as MediaPlaylist;
          context.push('/playlist/${Uri.encodeComponent(p.id)}');
        } else {
          _searchController.text = suggestion.title;
          _searchQuery = suggestion.title;
          ref.read(searchNotifierProvider.notifier).searchNow(suggestion.title);
        }
        break;

      case SuggestionType.searchQuery:
        _handleSearchSubmit(_searchQuery);
        break;
    }
  }

  Widget _buildRecentSearches(List<String> history) {
    if (history.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.softClay,
              ),
              child: const Icon(
                Icons.search_rounded,
                size: 28,
                color: AppColors.dustyRose,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Play what you love',
              style: GoogleFonts.playfairDisplay(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.cocoaPlum,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Search for artists, songs, albums, and playlists.',
              textAlign: TextAlign.center,
              style: GoogleFonts.geist(
                fontSize: 13,
                color: AppColors.mutedMauve,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Searches',
              style: GoogleFonts.playfairDisplay(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.cocoaPlum,
              ),
            ),
            TextButton(
              onPressed: () {
                ref.read(searchNotifierProvider.notifier).clearHistory();
              },
              child: Text(
                'Clear All',
                style: GoogleFonts.geist(
                  fontSize: 12.5,
                  color: AppColors.dustyRose,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Material(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.oatBeige),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: history.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: AppColors.oatBeige, height: 1),
              itemBuilder: (context, index) {
                final query = history[index];
                return ListTile(
                  leading: const Icon(Icons.history,
                      color: AppColors.mutedMauve, size: 20.0),
                  title: Text(
                    query,
                    style: GoogleFonts.geist(color: AppColors.cocoaPlum),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.clear, size: 16.0),
                    onPressed: () {
                      ref
                          .read(searchNotifierProvider.notifier)
                          .removeHistory(query);
                    },
                  ),
                  onTap: () => _applyHistoryQuery(query),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
