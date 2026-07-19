import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_shadows.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/audio/playback_state.dart';
import '../../../core/audio/providers.dart';
import '../../media/domain/models.dart';
import '../../media/providers/media_providers.dart';
import '../../../shared/models/track.dart';
import '../../../shared/models/music_item.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/search_providers.dart';
import '../../../features/library/providers/library_providers.dart';
import '../../profile/presentation/profile_controller.dart';
import '../../youtube/providers/youtube_providers.dart';
import '../../youtube/presentation/widgets/youtube_result_tile.dart';

final selectedGenreProvider = StateProvider<String>((ref) => 'All');

final genreSongIdsProvider = FutureProvider.family<Set<String>, String>((ref, genreName) async {
  if (genreName.toLowerCase() == 'all') return <String>{};
  
  final genres = ref.watch(genresProvider);
  final targetGenre = genres.firstWhere(
    (g) => g.name.trim().toLowerCase() == genreName.trim().toLowerCase(),
    orElse: () => const MediaGenre(id: '', name: '', trackCount: 0),
  );
  if (targetGenre.id.isEmpty) return <String>{};
  
  final audioQuery = OnAudioQuery();
  try {
    final rawSongs = await audioQuery.queryAudiosFrom(
      AudiosFromType.GENRE_ID,
      int.parse(targetGenre.id),
    );
    return rawSongs.map((s) => s.id.toString()).toSet();
  } catch (_) {
    return <String>{};
  }
});

/// Miee Search Screen.
/// Combines dynamic search toggles, filter chip selectors, bento-grid search history,
/// vertical list of trending song tiles, library category grids, and overlay mini players.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final ScrollController _scrollController;
  late final TextEditingController _searchController;
  bool _isScrolled = false;
  String _searchQuery = '';

  final List<String> _filters = [
    'All',
    'Ambient',
    'Neoclassical',
    'Electronic',
    'Jazz'
  ];

  late final FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_handleScroll);

    _searchController = TextEditingController();
    _searchController.addListener(_handleSearchQueryChange);
    _searchFocusNode = FocusNode();
    _searchFocusNode.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();

    _searchController.removeListener(_handleSearchQueryChange);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_scrollController.offset > 0 && !_isScrolled) {
      setState(() {
        _isScrolled = true;
      });
    } else if (_scrollController.offset <= 0 && _isScrolled) {
      setState(() {
        _isScrolled = false;
      });
    }
  }

  void _handleSearchQueryChange() {
    setState(() {
      _searchQuery = _searchController.text;
    });
    ref.read(searchNotifierProvider.notifier).updateQuery(_searchController.text);
    
    final selectedGenre = ref.read(selectedGenreProvider);
    final query = _searchController.text;
    final youtubeQuery = (selectedGenre != 'All' && query.isNotEmpty) ? '$query $selectedGenre' : query;
    _triggerYouTubeSearch(youtubeQuery, debounced: true);
  }

  /// Called when user submits the search (keyboard done / enter).
  void _handleSearchSubmit(String query) {
    if (query.trim().isEmpty) return;
    ref.read(searchHistoryProvider.notifier).addSearch(query.trim());
    ref.read(searchNotifierProvider.notifier).searchNow(query);
    
    final selectedGenre = ref.read(selectedGenreProvider);
    final youtubeQuery = (selectedGenre != 'All') ? '${query.trim()} $selectedGenre' : query.trim();
    _triggerYouTubeSearch(youtubeQuery, debounced: false);
  }

  /// Populates the search bar with [query] and triggers a search.
  void _applyHistoryQuery(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    setState(() => _searchQuery = query);
    ref.read(searchNotifierProvider.notifier).searchNow(query);
    
    final selectedGenre = ref.read(selectedGenreProvider);
    final youtubeQuery = (selectedGenre != 'All') ? '$query $selectedGenre' : query;
    _triggerYouTubeSearch(youtubeQuery, debounced: false);
  }

  /// Fires a YouTube search only when the device has internet connectivity.
  /// Uses [Connectivity] from connectivity_plus for a quick check.
  Future<void> _triggerYouTubeSearch(String query, {required bool debounced}) async {
    final result = await Connectivity().checkConnectivity();
    final isOnline = result.any((r) => r != ConnectivityResult.none);
    if (!isOnline) {
      ref.read(youtubeSearchProvider.notifier).clear();
      return;
    }
    if (debounced) {
      ref.read(youtubeSearchProvider.notifier).searchDebounced(query);
    } else {
      ref.read(youtubeSearchProvider.notifier).searchNow(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isSearching = _searchQuery.isNotEmpty;

    // Listen to real device music providers
    final localSongs = ref.watch(songsProvider);
    final localAlbums = ref.watch(albumsProvider);
    final localArtists = ref.watch(artistsProvider);
    final localGenres = ref.watch(genresProvider);
    final localPlaylists = ref.watch(playlistsProvider);
    final favorites = ref.watch(favoritesProvider);
    final history = ref.watch(searchHistoryProvider);
    final selectedGenre = ref.watch(selectedGenreProvider);
    final genreSongIdsAsync = ref.watch(genreSongIdsProvider(selectedGenre));

    return Scaffold(
      extendBody: true,
      appBar: AppHeader(
        title: 'Search',
        isScrolled: _isScrolled,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSpacing.heightSm,
              // Search Bar Input widget
              AppSearchBar(
                controller: _searchController,
                focusNode: _searchFocusNode,
                placeholder: 'Artists, songs, or online videos',
                onSubmitted: _handleSearchSubmit,
              ),
              AppSpacing.heightLg,

               // Live search results when a query is active
              if (isSearching) ...[
                _buildLiveSearchResults(favorites)
              ] else if (selectedGenre != 'All') ...[
                // Render list of tracks matching the selected genre filter
                genreSongIdsAsync.when(
                  data: (songIds) {
                    final genreSongs = localSongs.where((s) => songIds.contains(s.id)).toList();
                    if (genreSongs.isEmpty) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionHeader(
                            title: '$selectedGenre Songs',
                          ),
                          AppSpacing.heightLg,
                          const EmptyState(
                            title: 'No songs found',
                            message: 'No songs match this category.',
                            icon: Icons.music_note_outlined,
                          ),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionHeader(
                          title: '$selectedGenre Songs',
                        ),
                        AppSpacing.heightMd,
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: genreSongs.length,
                          itemBuilder: (context, index) {
                            final song = genreSongs[index];
                            final track = Track(
                              id: song.id,
                              title: song.title,
                              artist: song.artist,
                              imageUrl: song.artworkPath,
                              duration: song.duration,
                              filePath: song.filePath,
                            );
                            final playbackState = ref.watch(playerControllerProvider);
                            final isCurrentTrack = playbackState.currentTrack?.id == song.id;
                            
                            return Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: SongTile(
                                title: song.title,
                                artist: song.artist,
                                duration: song.duration,
                                imageUrl: song.artworkPath,
                                isPlaying: isCurrentTrack,
                                onTap: () {
                                  final playlistTracks = genreSongs.map((s) => Track(
                                    id: s.id,
                                    title: s.title,
                                    artist: s.artist,
                                    imageUrl: s.artworkPath,
                                    duration: s.duration,
                                    filePath: s.filePath,
                                  )).toList();
                                  ref.read(playerControllerProvider.notifier).selectTrack(track, playlistTracks);
                                  context.push('/player');
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (e, __) => EmptyState(
                    title: 'Error loading genre',
                    message: e.toString(),
                    icon: Icons.error_outline,
                  ),
                ),
              ] else ...[
                // Filter Chips horizontal row
                _buildFilterChips(),
                AppSpacing.heightLg,

                // Recent Searches Section (Bento Grid)
                if (history.isNotEmpty) ...[
                  SectionHeader(
                    title: 'Recent',
                    actionLabel: 'Clear',
                    onActionTap: () {
                      ref.read(searchHistoryProvider.notifier).clearAll();
                    },
                  ),
                  AppSpacing.heightMd,
                  _buildBentoRecentSearches(localArtists, localAlbums),
                  AppSpacing.heightLg,
                ],

                if (localSongs.isNotEmpty) ...[
                  // Trending Now Section
                  const SectionHeader(
                    title: 'Trending Now',
                  ),
                  AppSpacing.heightMd,
                  _buildTrendingSongsList(context, localSongs),
                  AppSpacing.heightLg,
                ],

                // Browse Categories Grid
                const SectionHeader(
                  title: 'Browse Categories',
                ),
                AppSpacing.heightMd,
                _buildBrowseCategoriesGrid(
                  localAlbums.length,
                  localArtists.length,
                  localPlaylists.length,
                  localGenres.length,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final selectedFilter = ref.watch(selectedGenreProvider);
    
    return SizedBox(
      height: 38.0,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.none,
        itemCount: _filters.length,
        separatorBuilder: (context, index) => AppSpacing.widthSm,
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isSelected = selectedFilter == filter;

          return GestureDetector(
            onTap: () {
              ref.read(selectedGenreProvider.notifier).state = filter;
              // If searching, trigger a new search on YouTube with the selected genre appended!
              if (_searchQuery.isNotEmpty) {
                final ytQuery = (filter != 'All') ? '$_searchQuery $filter' : _searchQuery;
                _triggerYouTubeSearch(ytQuery, debounced: false);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.onSurface
                    : AppColors.surfaceContainerHighest,
                borderRadius: AppRadius.radiusFull,
              ),
              alignment: Alignment.center,
              child: Text(
                filter,
                style: AppTypography.labelMedium.copyWith(
                  color: isSelected ? AppColors.background : AppColors.onSurface,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBentoRecentSearches(List<MediaArtist> localArtists, List<MediaAlbum> localAlbums) {
    final history = ref.watch(searchHistoryProvider);

    // Show persisted search history as tappable bento cards (up to 4).
    final displayed = history.take(4).toList();
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: displayed.map((query) {
        return SizedBox(
          width: (MediaQuery.of(context).size.width - AppSpacing.marginMobile * 2 - AppSpacing.md) / 2,
          child: _buildRecentSearchCard(
            title: query,
            subtitle: 'Search',
            onTap: () => _applyHistoryQuery(query),
            topWidget: Container(
              width: 40.0,
              height: 40.0,
              decoration: const BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.history, color: AppColors.onSurfaceVariant, size: 20.0),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRecentSearchCard({
    required String title,
    required String subtitle,
    required Widget topWidget,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: AppSpacing.paddingAllMd,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: AppRadius.radiusXl,
          boxShadow: AppShadows.shadowLow,
          border: Border.all(
            color: AppColors.outlineVariant.withOpacity(0.1),
            width: 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            topWidget,
            AppSpacing.heightSm,
            Text(
              title,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            AppSpacing.heightXs,
            Text(
              subtitle,
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendingSongsList(BuildContext context, List<MediaSong> localSongs) {
    final displaySongs = localSongs.take(3).toList();
    final trackList = localSongs.map((song) => Track(
      id: song.id,
      title: song.title,
      artist: song.artist,
      imageUrl: song.artworkPath,
      duration: song.duration,
      filePath: song.filePath,
    )).toList();

    return Column(
      children: List.generate(displaySongs.length, (index) {
        final song = displaySongs[index];
        final track = trackList[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: SongTile(
            title: song.title,
            artist: song.artist,
            duration: song.duration,
            imageUrl: song.artworkPath,
            isPlaying: false,
            onTap: () {
              ref.read(playerControllerProvider.notifier).selectTrack(track, trackList);
              context.push('/player');
            },
          ),
        );
      }),
    );
  }

  Widget _buildBrowseCategoriesGrid(int albumsCount, int artistsCount, int playlistsCount, int genresCount) {
    final albumsLabel = '$albumsCount Albums';
    final artistsLabel = '$artistsCount Artists';
    final playlistsLabel = '$playlistsCount Playlists';
    final genresLabel = '$genresCount Genres';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: CategoryCard(
                icon: Icons.album_outlined,
                title: 'Albums',
                subtitle: albumsLabel,
                onTap: () => context.push('/albums'),
              ),
            ),
            AppSpacing.widthMd,
            Expanded(
              child: CategoryCard(
                icon: Icons.person_outline,
                title: 'Artists',
                subtitle: artistsLabel,
                onTap: () => context.push('/artists'),
              ),
            ),
          ],
        ),
        AppSpacing.heightMd,
        Row(
          children: [
            Expanded(
              child: CategoryCard(
                icon: Icons.playlist_play,
                title: 'Playlists',
                subtitle: playlistsLabel,
                onTap: () => context.push('/playlists'),
              ),
            ),
            AppSpacing.widthMd,
            Expanded(
              child: CategoryCard(
                icon: Icons.music_note_outlined,
                title: 'Genres',
                subtitle: genresLabel,
                onTap: () => context.push('/genres'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Search Results Section ────────────────────────────────────────────────────

/// Displays grouped live search results when a query is active.
///
/// Uses only existing shared widgets ([SongTile], [CategoryCard], [SectionHeader]).
/// Reads from [searchNotifierProvider] — never touches device storage directly.
class _SearchResultsSection extends ConsumerWidget {
  final String query;

  const _SearchResultsSection({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localState = ref.watch(searchNotifierProvider);
    final youtubeState = ref.watch(youtubeSearchProvider);
    final songs = ref.watch(songsProvider);
    final selectedGenre = ref.watch(selectedGenreProvider);
    final genreSongIdsAsync = ref.watch(genreSongIdsProvider(selectedGenre));

    final showLocalLoading = localState.isLoading;
    final showYoutubeLoading = youtubeState.isLoading;

    final localResults = localState.results;
    final Set<String> genreSongIds = genreSongIdsAsync.value ?? <String>{};

    final filteredSongs = selectedGenre == 'All'
        ? localResults.songs
        : localResults.songs.where((s) => genreSongIds.contains(s.id)).toList();

    final filteredAlbums = selectedGenre == 'All'
        ? localResults.albums
        : localResults.albums.where((album) {
            return songs.any((s) =>
                s.album.trim().toLowerCase() == album.title.trim().toLowerCase() &&
                genreSongIds.contains(s.id));
          }).toList();

    final filteredArtists = selectedGenre == 'All'
        ? localResults.artists
        : localResults.artists.where((artist) {
            return songs.any((s) =>
                s.artist.trim().toLowerCase() == artist.name.trim().toLowerCase() &&
                genreSongIds.contains(s.id));
          }).toList();

    final hasLocalResults = filteredSongs.isNotEmpty ||
        filteredAlbums.isNotEmpty ||
        filteredArtists.isNotEmpty;

    final hasYoutubeResults = youtubeState.results.isNotEmpty;

    // Check if both sources are completely empty and finished loading
    final isBothEmpty = !showLocalLoading &&
        !showYoutubeLoading &&
        !hasLocalResults &&
        !hasYoutubeResults &&
        youtubeState.error == null;

    if (isBothEmpty) {
      return EmptyState(
        title: 'No results',
        message: 'Nothing found for "$query" in local music or YouTube${selectedGenre != 'All' ? ' for genre $selectedGenre' : ''}.',
        icon: Icons.search_off,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSpacing.heightSm,

        // ── 1. Local Songs Section ───────────────────────────────────────────
        if (showLocalLoading)
          _buildLoadingSection('Songs')
        else if (filteredSongs.isNotEmpty) ...[
          SectionHeader(
            title: 'Songs',
            actionLabel: filteredSongs.length > 5 ? 'See all' : null,
          ),
          AppSpacing.heightMd,
          ...filteredSongs.take(5).map((song) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: SongTile(
                title: song.title,
                artist: song.artist,
                duration: song.duration,
                imageUrl: song.artworkPath,
                isPlaying: false,
                onTap: () {
                  ref
                      .read(playerControllerProvider.notifier)
                      .selectTrack(song, filteredSongs);
                  context.push('/player');
                },
              ),
            );
          }),
          AppSpacing.heightMd,
        ],

        // ── 2. Local Albums Section ──────────────────────────────────────────
        if (showLocalLoading)
          _buildLoadingSection('Albums')
        else if (filteredAlbums.isNotEmpty) ...[
          const SectionHeader(title: 'Albums'),
          AppSpacing.heightMd,
          ...filteredAlbums.take(4).map((album) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _ResultListTile(
                  imageUrl: album.artworkPath,
                  title: album.title,
                  subtitle: '${album.artist} · ${album.trackCount} songs',
                  icon: Icons.album_outlined,
                  onTap: () => context.push('/album/${album.id}'),
                ),
              )),
          AppSpacing.heightMd,
        ],

        // ── 3. Local Artists Section ─────────────────────────────────────────
        if (showLocalLoading)
          _buildLoadingSection('Artists')
        else if (filteredArtists.isNotEmpty) ...[
          const SectionHeader(title: 'Artists'),
          AppSpacing.heightMd,
          ...filteredArtists.take(4).map((artist) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _ResultListTile(
                  imageUrl: artist.artworkPath,
                  title: artist.name,
                  subtitle: '${artist.trackCount} songs · ${artist.albumCount} albums',
                  icon: Icons.person_outline,
                  isCircle: true,
                  onTap: () => context.push('/artist/${artist.id}'),
                ),
              )),
          AppSpacing.heightMd,
        ],

        // ── 4. Local Genres Section ──────────────────────────────────────────
        if (selectedGenre == 'All' && !showLocalLoading && localResults.genres.isNotEmpty) ...[
          const SectionHeader(title: 'Genres'),
          AppSpacing.heightMd,
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: localResults.genres.take(6).map((genre) {
              return GestureDetector(
                onTap: () => context.push('/genre/${genre.id}'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHighest,
                    borderRadius: AppRadius.radiusFull,
                  ),
                  child: Text(
                    genre.name,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          AppSpacing.heightMd,
        ],

        // ── 5. YouTube Section (Online) ──────────────────────────────────────
        if (showYoutubeLoading) ...[
          const SectionHeader(title: 'YouTube'),
          AppSpacing.heightMd,
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24.0),
            child: Center(
              child: SizedBox(
                width: 24.0,
                height: 24.0,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ),
          AppSpacing.heightMd,
        ] else if (youtubeState.error != null) ...[
          const SectionHeader(title: 'YouTube'),
          AppSpacing.heightMd,
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: AppRadius.radiusMd,
            ),
            child: Row(
              children: [
                const Icon(Icons.wifi_off, color: AppColors.error),
                AppSpacing.widthMd,
                Expanded(
                  child: Text(
                    'YouTube offline or unavailable: ${youtubeState.error}',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.heightMd,
        ] else if (hasYoutubeResults) ...[
          SectionHeader(
            title: 'YouTube',
            actionLabel: '${youtubeState.results.length} found',
          ),
          AppSpacing.heightMd,
          ...youtubeState.results.take(6).map((video) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: YouTubeResultTile(video: video),
            );
          }),
          AppSpacing.heightMd,
        ],
      ],
    );
  }

  Widget _buildLoadingSection(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        AppSpacing.heightMd,
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12.0),
          child: Center(
            child: SizedBox(
              width: 18.0,
              height: 18.0,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
          ),
        ),
        AppSpacing.heightMd,
      ],
    );
  }
}

/// Helper tile used to display local Albums and Artists in search list.
class _ResultListTile extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isCircle;
  final VoidCallback onTap;

  const _ResultListTile({
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.isCircle = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = isCircle ? BorderRadius.circular(24.0) : AppRadius.radiusMd;

    final Widget thumbnail = imageUrl != null && imageUrl!.isNotEmpty
        ? ClipRRect(
            borderRadius: radius,
            child: imageUrl!.startsWith('http')
                ? Image.network(
                    imageUrl!,
                    width: 48.0,
                    height: 48.0,
                    fit: BoxFit.cover,
                    cacheWidth: 120,
                    cacheHeight: 120,
                    errorBuilder: (_, __, ___) => _iconFallback(radius),
                  )
                : Image.file(
                    File(imageUrl!),
                    width: 48.0,
                    height: 48.0,
                    fit: BoxFit.cover,
                    cacheWidth: 120,
                    cacheHeight: 120,
                    errorBuilder: (_, __, ___) => _iconFallback(radius),
                  ),
          )
        : _iconFallback(radius);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            thumbnail,
            AppSpacing.widthMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconFallback(BorderRadius radius) {
    return Container(
      width: 48.0,
      height: 48.0,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: radius,
      ),
      child: Icon(icon, color: AppColors.onSurfaceVariant, size: 22.0),
    );
  }
}

class _SearchSuggestionsList extends ConsumerWidget {
  final String query;
  final ValueChanged<String> onSelect;

  const _SearchSuggestionsList({
    required this.query,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestionsAsync = ref.watch(searchSuggestionsProvider(query));

    return suggestionsAsync.when(
      data: (suggestions) {
        if (suggestions.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(top: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: AppRadius.radiusXl,
            boxShadow: AppShadows.shadowLow,
            border: Border.all(
              color: AppColors.outlineVariant.withOpacity(0.1),
              width: 1.0,
            ),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: suggestions.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final suggestion = suggestions[index];
              return ListTile(
                leading: const Icon(Icons.search, color: AppColors.onSurfaceVariant, size: 20.0),
                title: Text(
                  suggestion,
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.onSurface),
                ),
                trailing: const Icon(Icons.north_west, color: AppColors.onSurfaceVariant, size: 16.0),
                onTap: () => onSelect(suggestion),
              );
            },
          ),
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
