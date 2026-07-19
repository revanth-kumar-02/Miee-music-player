import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_shadows.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/audio/providers.dart';
import '../../media/domain/models.dart';
import '../../media/providers/media_providers.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/search_providers.dart';
import '../domain/search_state.dart';
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
  
  return <String>{}; // Genre fallback for Web v2
});

/// Redesigned functional Miee Search Screen.
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
  }

  void _handleSearchSubmit(String query) {
    if (query.trim().isEmpty) return;
    ref.read(searchNotifierProvider.notifier).searchNow(query);
  }

  void _applyHistoryQuery(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    setState(() => _searchQuery = query);
    ref.read(searchNotifierProvider.notifier).searchNow(query);
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchNotifierProvider);
    final localSongs = ref.watch(songsProvider);
    final localAlbums = ref.watch(albumsProvider);
    final localArtists = ref.watch(artistsProvider);
    final localGenres = ref.watch(genresProvider);
    final localPlaylists = ref.watch(playlistsProvider);
    final selectedGenre = ref.watch(selectedGenreProvider);
    final genreSongIdsAsync = ref.watch(genreSongIdsProvider(selectedGenre));

    final isSearching = searchState.hasQuery;
    final showSuggestions = _searchFocusNode.hasFocus && _searchQuery.isNotEmpty;
    final showRecentSearches = _searchFocusNode.hasFocus && _searchQuery.isEmpty && searchState.recentSearches.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
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
              // Search Bar
              AppSearchBar(
                controller: _searchController,
                focusNode: _searchFocusNode,
                placeholder: 'Artists, songs, or online videos',
                onSubmitted: _handleSearchSubmit,
              ),
              AppSpacing.heightLg,

              // 1. Suggestions autocomplete drop
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
              // 4. Default categories / Genre list
              else if (selectedGenre != 'All') ...[
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
                            
                            return Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: SongTile(
                                title: song.title,
                                artist: song.artist,
                                duration: song.duration,
                                imageUrl: song.artworkPath,
                                isPlaying: false,
                                onTap: () {
                                  ref.read(playerControllerProvider.notifier).selectTrack(track, genreSongs);
                                  context.push('/player');
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, __) => EmptyState(title: 'Error', message: e.toString(), icon: Icons.error_outline),
                ),
              ] else ...[
                _buildFilterChips(),
                AppSpacing.heightLg,

                if (localSongs.isNotEmpty) ...[
                  const SectionHeader(title: 'Trending Now'),
                  AppSpacing.heightMd,
                  _buildTrendingSongsList(context, localSongs),
                  AppSpacing.heightLg,
                ],

                const SectionHeader(title: 'Browse Categories'),
                AppSpacing.heightMd,
                _buildBrowseCategoriesGrid(
                  localAlbums.length,
                  localArtists.length,
                  localPlaylists.length,
                  localGenres.length,
                ),
              ],
              const SizedBox(height: 120.0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionsList(List<String> suggestions) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
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
        SectionHeader(
          title: 'Recent Searches',
          actionLabel: 'Clear All',
          onActionTap: () {
            ref.read(searchNotifierProvider.notifier).clearHistory();
          },
        ),
        AppSpacing.heightMd,
        Container(
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
            itemCount: history.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final query = history[index];
              return ListTile(
                leading: const Icon(Icons.history, color: AppColors.onSurfaceVariant, size: 20.0),
                title: Text(
                  query,
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.onSurface),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.clear, size: 16.0),
                  onPressed: () {
                    ref.read(searchNotifierProvider.notifier).removeHistory(query);
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

  Widget _buildSearchResults(SearchState state) {
    final isDoneLoading = !state.isLocalLoading && !state.isYouTubeLoading;

    if (isDoneLoading && state.isEmpty) {
      return const EmptyState(
        title: 'No results found',
        message: 'Try searching with different terms or check spelling.',
        icon: Icons.search_off,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Local Songs
        if (state.isLocalLoading) ...[
          const SectionHeader(title: 'Local Songs'),
          AppSpacing.heightMd,
          _buildShimmerPlaceholder(),
          AppSpacing.heightLg,
        ] else if (state.localSongs.isNotEmpty) ...[
          const SectionHeader(title: 'Local Songs'),
          AppSpacing.heightMd,
          ...state.localSongs.take(5).map((song) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: SongTile(
                  title: song.title,
                  artist: song.artist,
                  duration: song.duration,
                  imageUrl: song.artworkPath,
                  isPlaying: false,
                  onTap: () {
                    ref.read(playerControllerProvider.notifier).selectTrack(song, state.localSongs);
                    context.push('/player');
                  },
                ),
              )),
          AppSpacing.heightLg,
        ],

        // 2. Albums
        if (state.isLocalLoading) ...[
          const SectionHeader(title: 'Albums'),
          AppSpacing.heightMd,
          _buildShimmerPlaceholder(),
          AppSpacing.heightLg,
        ] else if (state.localAlbums.isNotEmpty) ...[
          const SectionHeader(title: 'Albums'),
          AppSpacing.heightMd,
          ...state.localAlbums.take(4).map((album) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _ResultListTile(
                  imageUrl: album.artworkPath,
                  title: album.title,
                  subtitle: '${album.artist} · ${album.trackCount} songs',
                  icon: Icons.album_outlined,
                  onTap: () => context.push('/album/${album.id}'),
                ),
              )),
          AppSpacing.heightLg,
        ],

        // 3. Artists
        if (state.isLocalLoading) ...[
          const SectionHeader(title: 'Artists'),
          AppSpacing.heightMd,
          _buildShimmerPlaceholder(),
          AppSpacing.heightLg,
        ] else if (state.localArtists.isNotEmpty) ...[
          const SectionHeader(title: 'Artists'),
          AppSpacing.heightMd,
          ...state.localArtists.take(4).map((artist) => Padding(
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
          AppSpacing.heightLg,
        ],

        // 4. Playlists
        if (state.isLocalLoading) ...[
          const SectionHeader(title: 'Playlists'),
          AppSpacing.heightMd,
          _buildShimmerPlaceholder(),
          AppSpacing.heightLg,
        ] else if (state.localPlaylists.isNotEmpty) ...[
          const SectionHeader(title: 'Playlists'),
          AppSpacing.heightMd,
          ...state.localPlaylists.take(4).map((playlist) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _ResultListTile(
                  imageUrl: null,
                  title: playlist.name,
                  subtitle: '${playlist.trackCount} songs',
                  icon: Icons.playlist_play_outlined,
                  onTap: () => context.push('/playlist/${playlist.id}'),
                ),
              )),
          AppSpacing.heightLg,
        ],

        // 5. YouTube Results
        if (state.isYouTubeLoading) ...[
          const SectionHeader(title: 'YouTube'),
          AppSpacing.heightMd,
          _buildShimmerPlaceholder(),
          AppSpacing.heightLg,
        ] else if (state.youtubeResults.isNotEmpty) ...[
          SectionHeader(
            title: 'YouTube',
            actionLabel: '${state.youtubeResults.length} found',
          ),
          AppSpacing.heightMd,
          ...state.youtubeResults.take(6).map((video) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: YouTubeResultTile(video: video),
              )),
          AppSpacing.heightLg,
        ] else if (state.errorMessage != null) ...[
          const SectionHeader(title: 'YouTube'),
          AppSpacing.heightMd,
          Text(
            'Online search failed: ${state.errorMessage}',
            style: const TextStyle(color: Colors.red),
          ),
          AppSpacing.heightLg,
        ],
      ],
    );
  }

  Widget _buildShimmerPlaceholder() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(3, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Container(
                width: 48.0,
                height: 48.0,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              const SizedBox(width: 16.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 140.0,
                      height: 14.0,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                    ),
                    const SizedBox(height: 6.0),
                    Container(
                      width: 80.0,
                      height: 10.0,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildFilterChips() {
    final selectedGenre = ref.watch(selectedGenreProvider);
    return SizedBox(
      height: 36.0,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _filters.length,
        separatorBuilder: (context, index) => AppSpacing.widthSm,
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isSelected = selectedGenre == filter;
          return ChoiceChip(
            label: Text(filter),
            selected: isSelected,
            onSelected: (val) {
              ref.read(selectedGenreProvider.notifier).state = filter;
            },
          );
        },
      ),
    );
  }

  Widget _buildTrendingSongsList(BuildContext context, List<MediaSong> localSongs) {
    final displaySongs = localSongs.take(3).toList();
    return Column(
      children: List.generate(displaySongs.length, (index) {
        final song = displaySongs[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: SongTile(
            title: song.title,
            artist: song.artist,
            duration: song.duration,
            imageUrl: song.artworkPath,
            isPlaying: false,
            onTap: () {
              ref.read(playerControllerProvider.notifier).selectTrack(song, localSongs);
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
