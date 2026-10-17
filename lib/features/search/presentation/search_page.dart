import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/audio/providers.dart';
import '../../media/domain/models.dart';
import '../../media/providers/media_providers.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/search_providers.dart';
import '../domain/search_state.dart';
import '../../youtube/presentation/widgets/youtube_result_tile.dart';
import '../../recommendations/providers/recommendation_providers.dart';
import '../../recommendations/data/recommendation_service.dart';
import '../../library/providers/library_providers.dart';
import '../../../shared/models/track.dart';
import '../../../shared/models/music_item.dart';

/// Recreated Miee Search Screen matching the reference design:
/// - Cocoa Plum sidebar + Vanilla Cream canvas
/// - Pill search field with active query and clear 'x' button
/// - Filter chips: All, Songs, Artists, Albums, Playlists, Videos with Dusty Rose selection
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
    'Videos',
  ];

  late final FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _searchController = TextEditingController();
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
    ref.read(searchNotifierProvider.notifier).updateQuery(_searchController.text);
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

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchNotifierProvider);
    final localSongs = ref.watch(songsProvider);
    final localAlbums = ref.watch(albumsProvider);
    final localArtists = ref.watch(artistsProvider);
    final favorites = ref.watch(favoritesProvider);
    final recs = ref.watch(recommendationSectionsProvider).valueOrNull;

    final isSearching = searchState.hasQuery;
    final showSuggestions = _searchFocusNode.hasFocus &&
        _searchQuery.isNotEmpty &&
        searchState.suggestions.isNotEmpty;
    final showRecentSearches = _searchFocusNode.hasFocus &&
        _searchQuery.isEmpty &&
        searchState.recentSearches.isNotEmpty;

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 960;

    return Scaffold(
      backgroundColor: AppColors.vanillaCream,
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
            // Search Input Bar
            AppSearchBar(
              controller: _searchController,
              focusNode: _searchFocusNode,
              placeholder: 'Search songs, artists, albums...',
              onSubmitted: _handleSearchSubmit,
            ),
            const SizedBox(height: 14),

            // Filter Chips Row
            _buildFilterChips(searchState.activeFilter),
            const SizedBox(height: 24),

            // 1. Suggestions autocomplete
            if (showSuggestions) ...[
              _buildSuggestionsList(searchState.suggestions),
            ]
            // 2. Recent Searches list
            else if (showRecentSearches) ...[
              _buildRecentSearches(searchState.recentSearches),
            ]
            // 3. Main Results Grid
            else if (isSearching) ...[
              _buildSearchResults(searchState),
            ]
            // 4. Default Exploration matching the reference layout
            else ...[
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
    String? imageUrl,
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
                  color: AppColors.cocoaPlum.withOpacity(0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Round Artist Avatar with clean border
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.softClay, width: 2),
                    image: (imageUrl != null && imageUrl.isNotEmpty)
                        ? DecorationImage(
                            image: NetworkImage(imageUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                    color: AppColors.softClay,
                  ),
                  child: (imageUrl == null || imageUrl.isEmpty)
                      ? Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'A',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: AppColors.cocoaPlum,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 20),

                // Name & "Artist" Badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.vanillaCream,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Artist',
                        style: GoogleFonts.geist(
                          fontSize: 13,
                          color: AppColors.softClay,
                        ),
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

  // ── DEFAULT EXPLORE VIEW (Matches Reference Composition) ───────────────────

  Widget _buildDefaultExploreView(
    List<MediaArtist> localArtists,
    List<MediaSong> localSongs,
    List<MediaAlbum> localAlbums,
    List<Track> favorites,
    RecommendationSections? recs,
  ) {
    // Determine Top Result
    String? topArtistName;
    String? topArtistImage;
    VoidCallback? onTopTap;
    VoidCallback? onTopPlay;

    if (localArtists.isNotEmpty) {
      final a = localArtists.first;
      topArtistName = a.name;
      topArtistImage = a.artworkPath;
      onTopTap = () => context.push('/artist/${a.id}', extra: a);
      onTopPlay = () {
        if (localSongs.isNotEmpty) {
          ref
              .read(playerControllerProvider.notifier)
              .playTrack(localSongs.first);
        }
      };
    } else if (recs != null && recs.favoriteArtists.isNotEmpty) {
      final a = recs.favoriteArtists.first;
      topArtistName = a.name;
      topArtistImage = a.imageUrl;
      onTopTap = () => context.push('/artist/${a.id}', extra: a);
      onTopPlay = () => _applyHistoryQuery(a.name);
    } else if (recs != null && recs.fromYourArtists.isNotEmpty) {
      final t = recs.fromYourArtists.first;
      topArtistName = t.artist;
      topArtistImage = t.imageUrl;
      onTopTap = () => _applyHistoryQuery(t.artist);
      onTopPlay = () => ref
          .read(playerControllerProvider.notifier)
          .selectTrack(t, recs.fromYourArtists, playingFrom: 'For You');
    } else if (favorites.isNotEmpty) {
      final t = favorites.first;
      topArtistName = t.artist;
      topArtistImage = t.imageUrl;
      onTopTap = () => _applyHistoryQuery(t.artist);
      onTopPlay = () => ref
          .read(playerControllerProvider.notifier)
          .selectTrack(t, favorites, playingFrom: 'Liked Songs');
    }

    // Determine songs to display
    final List<dynamic> songsToDisplay = localSongs.isNotEmpty
        ? localSongs.take(5).toList()
        : (recs != null && recs.fromYourArtists.isNotEmpty
            ? recs.fromYourArtists.take(5).toList()
            : favorites.take(5).toList());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Top Result Card (if top artist exists)
        if (topArtistName != null) ...[
          _buildTopResultCard(
            name: topArtistName,
            imageUrl: topArtistImage,
            onTap: onTopTap ?? () {},
            onPlay: onTopPlay ?? () {},
          ),
          const SizedBox(height: 28),
        ] else ...[
          // Discovery Banner when no prior library or artist exists yet
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cocoaPlum,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppColors.dustyRose,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.explore_rounded,
                    color: AppColors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Discover Music',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.vanillaCream,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Type in the search bar above to stream songs or search artists.',
                        style: GoogleFonts.geist(
                          fontSize: 12.5,
                          color: AppColors.softClay,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
        ],

        // 2. Songs Section
        if (songsToDisplay.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Songs',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.cocoaPlum,
                ),
              ),
              InkWell(
                onTap: () {
                  ref.read(searchNotifierProvider.notifier).setFilter('Songs');
                },
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
          const SizedBox(height: 12),

          for (final item in songsToDisplay)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SongTile(
                title: item is MediaSong
                    ? item.title
                    : (item is Track ? item.title : (item as MusicItem).title),
                artist: item is MediaSong
                    ? item.artist
                    : (item is Track
                        ? item.artist
                        : (item as MusicItem).artist),
                duration: item is MediaSong
                    ? item.duration
                    : (item is Track
                        ? item.duration
                        : (item as MusicItem).duration),
                imageUrl: item is MediaSong
                    ? item.artworkPath
                    : (item is Track
                        ? item.imageUrl
                        : (item as MusicItem).imageUrl),
                isPlaying: false,
                onTap: () {
                  if (item is MediaSong) {
                    ref.read(playerControllerProvider.notifier).selectTrack(
                          item,
                          localSongs,
                          playingFrom: 'Local Music',
                        );
                  } else if (item is Track) {
                    ref.read(playerControllerProvider.notifier).selectTrack(
                          item,
                          favorites,
                          playingFrom: 'Liked Songs',
                        );
                  } else if (item is MusicItem && recs != null) {
                    ref.read(playerControllerProvider.notifier).selectTrack(
                          item,
                          recs.fromYourArtists,
                          playingFrom: 'For You',
                        );
                  }
                  context.push('/player');
                },
              ),
            ),
          const SizedBox(height: 28),
        ],

        // 3. Albums Section (only real local albums if any exist)
        if (localAlbums.isNotEmpty) ...[
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
              InkWell(
                onTap: () {
                  ref.read(searchNotifierProvider.notifier).setFilter('Albums');
                },
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
          const SizedBox(height: 14),

          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: localAlbums.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final album = localAlbums[index];
                return _buildAlbumCard(
                  album.title,
                  '${album.trackCount} songs',
                  album.artworkPath,
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAlbumCard(String title, String year, String? imageUrl) {
    return InkWell(
      onTap: () => _applyHistoryQuery(title),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: (imageUrl != null && imageUrl.isNotEmpty)
                  ? Image.network(
                      imageUrl,
                      width: 130,
                      height: 130,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 130,
                        height: 130,
                        color: AppColors.softClay,
                        child: const Icon(Icons.album_rounded,
                            color: AppColors.cocoaPlum),
                      ),
                    )
                  : Container(
                      width: 130,
                      height: 130,
                      color: AppColors.softClay,
                      child: const Icon(Icons.album_rounded,
                          color: AppColors.cocoaPlum),
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

  // ── SEARCH RESULTS (Active Search Query) ───────────────────────────────────

  Widget _buildSearchResults(SearchState state) {
    if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
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

    final isDoneLoading = !state.isLocalLoading &&
        !state.isYouTubeLoading &&
        !state.isArtistsLoading;
    final filter = state.activeFilter;

    if (isDoneLoading && state.isEmpty) {
      return EmptyState(
        title: 'No results found',
        message: 'No matches found for "${state.query}". Try searching another title.',
        icon: Icons.search_off,
      );
    }

    final showArtists =
        filter == 'All' || filter == 'Artists';
    final showSongs = filter == 'All' || filter == 'Songs' || filter == 'Videos';
    final showAlbums = filter == 'All' || filter == 'Albums';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Top Result Card (if top online or local artist exists)
        if (showArtists && (state.onlineArtists.isNotEmpty || state.localArtists.isNotEmpty)) ...[
          _buildTopResultCard(
            name: state.onlineArtists.isNotEmpty
                ? state.onlineArtists.first.name
                : state.localArtists.first.name,
            imageUrl: state.onlineArtists.isNotEmpty
                ? state.onlineArtists.first.imageUrl
                : state.localArtists.first.artworkPath,
            onTap: () {
              if (state.onlineArtists.isNotEmpty) {
                final artist = state.onlineArtists.first;
                context.push('/artist/${artist.id}', extra: artist);
              }
            },
            onPlay: () {
              if (state.youtubeResults.isNotEmpty) {
                ref
                    .read(playerControllerProvider.notifier)
                    .selectTrack(state.youtubeResults.first, state.youtubeResults);
              }
            },
          ),
          const SizedBox(height: 28),
        ],

        // 2. Songs Section
        if (showSongs) ...[
          if (state.localSongs.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Songs',
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
            ...state.localSongs.take(5).map(
                  (song) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SongTile(
                      title: song.title,
                      artist: song.artist,
                      duration: song.duration,
                      imageUrl: song.artworkPath,
                      isPlaying: false,
                      onTap: () {
                        ref
                            .read(playerControllerProvider.notifier)
                            .selectTrack(song, state.localSongs);
                        context.push('/player');
                      },
                    ),
                  ),
                ),
            const SizedBox(height: 16),
          ],
          if (state.youtubeResults.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'YouTube',
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
            ...state.youtubeResults.take(15).map(
                  (video) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: YouTubeResultTile(video: video),
                  ),
                ),
            const SizedBox(height: 24),
          ],
        ],

        // 3. Albums Section
        if (showAlbums && (state.onlineAlbums.isNotEmpty || state.localAlbums.isNotEmpty)) ...[
          Text(
            'Albums',
            style: GoogleFonts.playfairDisplay(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.cocoaPlum,
            ),
          ),
          const SizedBox(height: 12),
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
                      album.artworkPath ?? '',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── AUTOCOMPLETE & RECENT SEARCHES ─────────────────────────────────────────

  Widget _buildSuggestionsList(List<String> suggestions) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.oatBeige),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) =>
            const Divider(color: AppColors.oatBeige, height: 1),
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          return ListTile(
            leading: const Icon(Icons.search,
                color: AppColors.mutedMauve, size: 20.0),
            title: Text(
              suggestion,
              style: GoogleFonts.geist(color: AppColors.cocoaPlum),
            ),
            trailing: const Icon(Icons.north_west,
                color: AppColors.mutedMauve, size: 16.0),
            onTap: () => _applyHistoryQuery(suggestion),
          );
        },
      ),
    );
  }

  Widget _buildRecentSearches(List<String> history) {
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
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
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
      ],
    );
  }
}
