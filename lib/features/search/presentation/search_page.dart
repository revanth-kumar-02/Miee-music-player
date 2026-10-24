import 'dart:io';
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
import '../../youtube/domain/youtube_model.dart';
import '../../youtube/presentation/widgets/youtube_result_tile.dart';
import '../../recommendations/providers/recommendation_providers.dart';
import '../../recommendations/data/recommendation_service.dart';
import '../../library/providers/library_providers.dart';
import '../../../shared/models/track.dart';
import '../../../shared/models/music_item.dart';
import '../../onboarding/domain/artist_model.dart';

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

  void _playYouTubeResult(YouTubeVideo video, List<YouTubeVideo> results) {
    if (results.isEmpty) return;

    final isLoading = ref.read(playerControllerProvider.select((s) =>
        s.loadingTrackId != null && isSameTrackId(s.loadingTrackId, video.id)));
    if (isLoading) return;

    final normVideoId = video.id.startsWith('youtube_')
        ? video.id.replaceFirst('youtube_', '')
        : video.id;

    final targetIndex = results.indexWhere((v) {
      final normV = v.id.startsWith('youtube_')
          ? v.id.replaceFirst('youtube_', '')
          : v.id;
      return normV == normVideoId;
    });

    if (targetIndex < 0) return;

    final tracks = List<Track>.unmodifiable(
      results.map((v) => v.toTrack()),
    );
    final targetTrack = tracks[targetIndex];

    ref.read(playerControllerProvider.notifier).selectTrack(
          targetTrack,
          tracks,
          playingFrom: 'YouTube Search',
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

    final isSearching = searchState.hasQuery;
    final showSuggestions = _searchFocusNode.hasFocus &&
        _searchQuery.isNotEmpty &&
        searchState.suggestions.isNotEmpty;
    final showRecentSearches = _searchFocusNode.hasFocus &&
        _searchQuery.isEmpty &&
        searchState.recentSearches.isNotEmpty;

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 960;

    // Sync search input controller with global search query when not focused
    ref.listen<String>(searchNotifierProvider.select((s) => s.query), (previous, next) {
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

            // Filter Chips Row
            _buildFilterChips(searchState.activeFilter),
            const SizedBox(height: 20),

            // Active Query Header (Editorial indicator when searching)
            if (isSearching)
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
                        ref.read(searchNotifierProvider.notifier).updateQuery('');
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.oatBeige.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.close_rounded, size: 14, color: AppColors.mutedMauve),
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
                        ? (imageUrl.startsWith('http')
                            ? Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                cacheWidth: 150,
                                cacheHeight: 150,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Icon(
                                    isSong ? Icons.music_note_rounded : Icons.person_rounded,
                                    color: AppColors.cocoaPlum,
                                    size: 32,
                                  ),
                                ),
                              )
                            : Image.file(
                                File(imageUrl.startsWith('file://')
                                    ? Uri.parse(imageUrl).toFilePath()
                                    : imageUrl),
                                fit: BoxFit.cover,
                                cacheWidth: 150,
                                cacheHeight: 150,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Icon(
                                    isSong ? Icons.music_note_rounded : Icons.person_rounded,
                                    color: AppColors.cocoaPlum,
                                    size: 32,
                                  ),
                                ),
                              ))
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

  // ── DEFAULT EXPLORE VIEW (Matches Reference Composition) ───────────────────

  Widget _buildDefaultExploreView(
    List<MediaArtist> localArtists,
    List<MediaSong> localSongs,
    List<MediaAlbum> localAlbums,
    List<Track> favorites,
    RecommendationSections? recs,
  ) {
    final activeTrackId = ref.watch(playerControllerProvider.select((s) =>
        s.status == PlaybackStatus.playing ? s.currentTrack?.id : null));

    // Determine songs to display
    final List<dynamic> songsToDisplay = localSongs.isNotEmpty
        ? localSongs.take(5).toList()
        : (recs != null && recs.fromYourArtists.isNotEmpty
            ? recs.fromYourArtists.take(5).toList()
            : favorites.take(5).toList());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Discovery Landing Banner
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

          ...songsToDisplay.map((item) {
            final itemId = item is MediaSong
                ? item.id
                : (item is Track ? item.id : (item as MusicItem).id);
            final isItemPlaying = activeTrackId == itemId;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Consumer(
                builder: (context, ref, _) {
                  final isItemLoading = ref.watch(
                    playerControllerProvider.select((s) =>
                        s.loadingTrackId != null &&
                        isSameTrackId(s.loadingTrackId, itemId)),
                  );
                  return SongTile(
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
                    isPlaying: isItemPlaying,
                    isLoading: isItemLoading,
                    onTap: isItemLoading
                        ? null
                        : () {
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
                          },
                  );
                },
              ),
            );
          }),
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
                  ? (imageUrl.startsWith('http')
                      ? Image.network(
                          imageUrl,
                          width: 130,
                          height: 130,
                          fit: BoxFit.cover,
                          cacheWidth: 260,
                          cacheHeight: 260,
                          errorBuilder: (_, __, ___) => Container(
                            width: 130,
                            height: 130,
                            color: AppColors.softClay,
                            child: const Icon(Icons.album_rounded,
                                color: AppColors.cocoaPlum),
                          ),
                        )
                      : Image.file(
                          File(imageUrl.startsWith('file://')
                              ? Uri.parse(imageUrl).toFilePath()
                              : imageUrl),
                          width: 130,
                          height: 130,
                          fit: BoxFit.cover,
                          cacheWidth: 260,
                          cacheHeight: 260,
                          errorBuilder: (_, __, ___) => Container(
                            width: 130,
                            height: 130,
                            color: AppColors.softClay,
                            child: const Icon(Icons.album_rounded,
                                color: AppColors.cocoaPlum),
                          ),
                        ))
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
    final isLoading = state.isLocalLoading || state.isYouTubeLoading || state.isArtistsLoading;
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
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.dustyRose),
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
      if ((filter == 'Songs' || filter == 'Videos') && state.totalSongsCount == 0) {
        return _buildCategoryEmptyState(
          icon: Icons.music_off_rounded,
          title: 'No songs found',
          message: 'No songs found for "${state.query}". Try searching another title.',
        );
      }
      if (filter == 'Albums' && state.totalAlbumsCount == 0) {
        return _buildCategoryEmptyState(
          icon: Icons.album_outlined,
          title: 'No albums found',
          message: 'No albums found for "${state.query}".',
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
    final showSongs = filter == 'All' || filter == 'Songs' || filter == 'Videos';
    final showAlbums = filter == 'All' || filter == 'Albums';

    final activeTrackId = ref.watch(playerControllerProvider.select((s) =>
        s.status == PlaybackStatus.playing ? s.currentTrack?.id : null));

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
      if (seenArtistIds.add(a.id) && (norm.isEmpty || seenArtistNames.add(norm))) {
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
                  a.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') ==
                      normCleanQuery)),
      orElse: () =>
          (filter == 'Artists' && allArtists.isNotEmpty ? allArtists.first : null),
    );

    final matchingSong = state.youtubeResults.cast<YouTubeVideo?>().firstWhere(
      (v) =>
          v != null &&
          (v.title.toLowerCase().contains(cleanQuery) ||
              cleanQuery.contains(v.title.toLowerCase())),
      orElse: () =>
          (state.youtubeResults.isNotEmpty ? state.youtubeResults.first : null),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Top Result Card
        if (showArtists && matchingArtist != null) ...[
          _buildTopResultCard(
            name: matchingArtist.name,
            subtitle: matchingArtist.fanCount > 0
                ? '${_formatNumber(matchingArtist.fanCount)} fans'
                : 'Artist',
            imageUrl: matchingArtist.imageUrl,
            onTap: () => _navigateToArtist(context, matchingArtist),
            onPlay: () {
              if (state.youtubeResults.isNotEmpty) {
                _playYouTubeResult(state.youtubeResults.first, state.youtubeResults);
              }
            },
          ),
          const SizedBox(height: 28),
        ] else if (showSongs && matchingSong != null) ...[
          _buildTopResultCard(
            name: matchingSong.title,
            subtitle: matchingSong.channelTitle,
            imageUrl: matchingSong.thumbnailUrl,
            isSong: true,
            onTap: () {
              _playYouTubeResult(matchingSong, state.youtubeResults);
            },
            onPlay: () {
              _playYouTubeResult(matchingSong, state.youtubeResults);
            },
          ),
          const SizedBox(height: 28),
        ],

        // 2. Artists Section
        if (filter == 'Artists' && allArtists.isNotEmpty) ...[
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
        ] else if (filter == 'All' && allArtists.isNotEmpty) ...[
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
              itemBuilder: (context, idx) => _buildArtistCard(allArtists[idx]),
            ),
          ),
          const SizedBox(height: 24),
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
            ...state.localSongs.take(5).map(
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
                          ref
                              .read(playerControllerProvider.notifier)
                              .selectTrack(song, state.localSongs);
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
            ...state.youtubeResults.take(15).map(
                  (video) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: YouTubeResultTile(
                      video: video,
                      onTap: () => _playYouTubeResult(video, state.youtubeResults),
                    ),
                  ),
                ),
            const SizedBox(height: 24),
          ],
        ],

        // 4. Albums Section
        if (showAlbums &&
            (state.onlineAlbums.isNotEmpty || state.localAlbums.isNotEmpty)) ...[
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
                      album.artworkPath,
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

  void _navigateToArtist(BuildContext context, dynamic artist) {
    if (artist is ArtistModel) {
      context.push('/artist/${Uri.encodeComponent(artist.id.trim())}', extra: artist);
    } else if (artist is MediaArtist) {
      final model = ArtistModel(
        id: artist.id,
        name: artist.name,
        imageUrl: artist.artworkPath ?? '',
      );
      context.push('/artist/${Uri.encodeComponent(artist.id.trim())}', extra: model);
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
              artist.fanCount > 0 ? '${_formatNumber(artist.fanCount)} fans' : 'Artist',
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
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
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
