import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import '../../../shared/models/mock_data.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/search_providers.dart';
import '../../../features/library/providers/library_providers.dart';
import '../../youtube/providers/youtube_providers.dart';
import '../../youtube/presentation/widgets/youtube_result_tile.dart';

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
  String _selectedFilter = 'All';
  String _searchQuery = '';
  int _currentTab = 0; // 0 = Local, 1 = YouTube


  final List<String> _filters = [
    'All',
    'Ambient',
    'Neoclassical',
    'Electronic',
    'Jazz'
  ];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_handleScroll);

    _searchController = TextEditingController();
    _searchController.addListener(_handleSearchQueryChange);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();

    _searchController.removeListener(_handleSearchQueryChange);
    _searchController.dispose();
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
    if (_currentTab == 0) {
      ref.read(searchNotifierProvider.notifier).updateQuery(_searchController.text);
    } else {
      ref.read(youtubeSearchProvider.notifier).searchDebounced(_searchController.text);
    }
  }

  /// Called when user submits the search (keyboard done / enter).
  void _handleSearchSubmit(String query) {
    if (query.trim().isEmpty) return;
    if (_currentTab == 0) {
      ref.read(searchHistoryProvider.notifier).addSearch(query.trim());
      ref.read(searchNotifierProvider.notifier).searchNow(query);
    } else {
      ref.read(youtubeSearchHistoryProvider.notifier).addSearch(query.trim());
      ref.read(youtubeSearchProvider.notifier).searchNow(query);
    }
  }

  /// Populates the search bar with [query] and triggers a search.
  void _applyHistoryQuery(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    setState(() => _searchQuery = query);
    if (_currentTab == 0) {
      ref.read(searchNotifierProvider.notifier).searchNow(query);
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

    return Scaffold(
      extendBody: true,
      appBar: AppHeader(
        title: 'Miee',
        isScrolled: _isScrolled,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {},
          splashRadius: 20.0,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.marginMobile),
            child: ProfileAvatar(
              imageUrl: null,
              size: 32.0,
              onTap: () => context.push('/settings'),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Main scrollable content canvas
          Positioned.fill(
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
                    placeholder: _currentTab == 0 ? 'Artists, songs, or podcasts' : 'Search YouTube videos...',
                    onSubmitted: _handleSearchSubmit,
                  ),
                  AppSpacing.heightMd,

                  // Sliding Tab Selector
                  _buildTabSelector(),
                  AppSpacing.heightLg,

                  // Live search results when a query is active
                  if (isSearching) ...[
                    if (_currentTab == 0)
                      _SearchResultsSection(query: _searchQuery)
                    else
                      _YouTubeSearchResultsSection(query: _searchQuery),
                  ] else ...[
                    if (_currentTab == 0) ...[
                      // Filter Chips horizontal row
                      _buildFilterChips(),
                      AppSpacing.heightLg,

                      // Recent Searches Section (Bento Grid)
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

                      // Trending Now Section
                      const SectionHeader(
                        title: 'Trending Now',
                      ),
                      AppSpacing.heightMd,
                      _buildTrendingSongsList(context, localSongs),
                      AppSpacing.heightLg,

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
                    ] else ...[
                      _buildYouTubeRecentSection(),
                    ]
                  ],


                  // Bottom padding offset for MiniPlayer & BottomNavigation
                  SizedBox(height: 160.0 + bottomInset),
                ],
              ),
            ),
          ),

          // 2. Fixed Mini Player Overlay (Light Mode matches Page Background)
          Positioned(
            left: AppSpacing.marginMobile,
            right: AppSpacing.marginMobile,
            bottom: 80.0 + bottomInset + AppSpacing.sm,
            child: Consumer(
              builder: (context, ref, child) {
                final playbackState = ref.watch(playerControllerProvider);
                final controller = ref.read(playerControllerProvider.notifier);
                final currentTrack = playbackState.currentTrack;

                if (currentTrack == null) {
                  return const SizedBox.shrink();
                }

                final isPlaying = playbackState.status == PlaybackStatus.playing;
                final total = playbackState.duration.inMilliseconds;
                final pos = playbackState.position.inMilliseconds;
                final progress = total > 0 ? pos / total : 0.0;

                return MiniPlayer(
                  imageUrl: currentTrack.imageUrl,
                  title: currentTrack.title,
                  artist: currentTrack.artist,
                  progress: progress,
                  isPlaying: isPlaying,
                  isFavorited: currentTrack.isFavorited,
                  isDark: false, // Light mode matches the surface container background
                  onTap: () => context.push('/player'),
                  onPlayPauseTap: () {
                    if (isPlaying) {
                      controller.pause();
                    } else {
                      controller.play();
                    }
                  },
                  onFavoriteTap: () {},
                );
              },
            ),
          ),

          // 3. Fixed Shell Bottom Navigation Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BottomNavigation(
              currentIndex: 1, // Search tab highlighted as active
              onTap: (index) {
                switch (index) {
                  case 0:
                    context.go('/home');
                    break;
                  case 1:
                    break;
                  case 2:
                    context.go('/library');
                    break;
                  case 3:
                    context.go('/queue');
                    break;
                  case 4:
                    context.go('/settings');
                    break;
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
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
          final isSelected = _selectedFilter == filter;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedFilter = filter;
              });
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

    // When no persisted history yet, fall back to device library context as before.
    if (history.isEmpty) {
      final hasArtist = localArtists.isNotEmpty;
      final artistName = hasArtist ? localArtists.first.name : 'Brambles';
      final hasAlbum = localAlbums.isNotEmpty;
      final albumTitle = hasAlbum ? localAlbums.first.title : 'Charcoal';
      final albumArtwork = hasAlbum ? localAlbums.first.artworkPath : MockData.recentlyPlayed[0].imageUrl;

      return Row(
        children: [
          Expanded(
            child: _buildRecentSearchCard(
              title: artistName,
              subtitle: 'Artist',
              onTap: () => _applyHistoryQuery(artistName),
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
          ),
          AppSpacing.widthMd,
          Expanded(
            child: _buildRecentSearchCard(
              title: albumTitle,
              subtitle: 'Album',
              onTap: () => _applyHistoryQuery(albumTitle),
              topWidget: ClipRRect(
                borderRadius: BorderRadius.circular(20.0),
                child: albumArtwork.startsWith('http')
                    ? Image.network(albumArtwork, width: 40.0, height: 40.0, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(width: 40.0, height: 40.0, color: AppColors.surfaceContainerHigh))
                    : Image.file(File(albumArtwork), width: 40.0, height: 40.0, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(width: 40.0, height: 40.0, color: AppColors.surfaceContainerHigh)),
              ),
            ),
          ),
        ],
      );
    }

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
    final hasLocal = localSongs.isNotEmpty;

    if (hasLocal) {
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

    // Show top 3 tracks from mock data as trending tracks fallback
    final tracks = MockData.recentlyPlayed;

    return Column(
      children: List.generate(tracks.length, (index) {
        final track = tracks[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: SongTile(
            title: track.title,
            artist: track.artist,
            duration: '3:24',
            imageUrl: track.imageUrl,
            isPlaying: false,
            onTap: () {
              ref.read(playerControllerProvider.notifier).selectTrack(track, tracks);
              context.push('/player');
            },
          ),
        );
      }),
    );
  }

  Widget _buildBrowseCategoriesGrid(int albumsCount, int artistsCount, int playlistsCount, int genresCount) {
    final albumsLabel = albumsCount > 0 ? '$albumsCount Albums' : '24 Albums';
    final artistsLabel = artistsCount > 0 ? '$artistsCount Artists' : '12 Artists';
    final playlistsLabel = playlistsCount > 0 ? '$playlistsCount Playlists' : '8 Playlists';
    final genresLabel = genresCount > 0 ? '$genresCount Genres' : '6 Genres';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: CategoryCard(
                icon: Icons.album_outlined,
                title: 'Albums',
                subtitle: albumsLabel,
                onTap: () {},
              ),
            ),
            AppSpacing.widthMd,
            Expanded(
              child: CategoryCard(
                icon: Icons.person_outline,
                title: 'Artists',
                subtitle: artistsLabel,
                onTap: () {},
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
                onTap: () {},
              ),
            ),
            AppSpacing.widthMd,
            Expanded(
              child: CategoryCard(
                icon: Icons.music_note_outlined,
                title: 'Genres',
                subtitle: genresLabel,
                onTap: () {},
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
    final searchState = ref.watch(searchNotifierProvider);
    final library = ref.watch(mediaLibraryServiceProvider);

    // ── Loading ──────────────────────────────────────────────────────────────
    if (searchState.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // ── Permission denied / library not available ────────────────────────────
    if (!library.hasPermission && !library.isLoading) {
      return EmptyState(
        title: 'Library Unavailable',
        message: 'Grant storage permission to search your music.',
        icon: Icons.lock_outline,
      );
    }

    // ── Empty results ────────────────────────────────────────────────────────
    final results = searchState.results;
    if (results.isEmpty) {
      return EmptyState(
        title: 'No results',
        message: 'Nothing found for "$query".',
        icon: Icons.search_off,
      );
    }

    // ── Grouped results ──────────────────────────────────────────────────────
    // Convert local songs to Track list for the player controller.
    final allSongTracks = results.songs.map((s) => Track(
          id: s.id,
          title: s.title,
          artist: s.artist,
          imageUrl: s.artworkPath,
          duration: s.duration,
          filePath: s.filePath,
        )).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSpacing.heightSm,

        // ── Songs ────────────────────────────────────────────────────────────
        if (results.songs.isNotEmpty) ...[
          SectionHeader(
            title: 'Songs',
            actionLabel: results.songs.length > 5 ? 'See all' : null,
          ),
          AppSpacing.heightMd,
          ...results.songs.take(5).map((song) {
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
                  ref
                      .read(playerControllerProvider.notifier)
                      .selectTrack(track, allSongTracks);
                  context.push('/player');
                },
              ),
            );
          }),
          AppSpacing.heightMd,
        ],

        // ── Albums ───────────────────────────────────────────────────────────
        if (results.albums.isNotEmpty) ...[
          const SectionHeader(title: 'Albums'),
          AppSpacing.heightMd,
          ...results.albums.take(4).map((album) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _ResultListTile(
                  imageUrl: album.artworkPath,
                  title: album.title,
                  subtitle: '${album.artist} · ${album.trackCount} songs',
                  icon: Icons.album_outlined,
                  onTap: () {},
                ),
              )),
          AppSpacing.heightMd,
        ],

        // ── Artists ──────────────────────────────────────────────────────────
        if (results.artists.isNotEmpty) ...[
          const SectionHeader(title: 'Artists'),
          AppSpacing.heightMd,
          ...results.artists.take(4).map((artist) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _ResultListTile(
                  imageUrl: null,
                  title: artist.name,
                  subtitle: '${artist.trackCount} songs · ${artist.albumCount} albums',
                  icon: Icons.person_outline,
                  isCircle: true,
                  onTap: () {},
                ),
              )),
          AppSpacing.heightMd,
        ],

        // ── Genres ───────────────────────────────────────────────────────────
        if (results.genres.isNotEmpty) ...[
          const SectionHeader(title: 'Genres'),
          AppSpacing.heightMd,
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: results.genres.take(6).map((genre) {
              return Container(
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
              );
            }).toList(),
          ),
          AppSpacing.heightMd,
        ],

        // ── Playlists ────────────────────────────────────────────────────────
        if (results.playlists.isNotEmpty) ...[
          const SectionHeader(title: 'Playlists'),
          AppSpacing.heightMd,
          ...results.playlists.take(4).map((playlist) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _ResultListTile(
                  imageUrl: null,
                  title: playlist.name,
                  subtitle: '${playlist.trackCount} songs',
                  icon: Icons.playlist_play,
                  onTap: () {},
                ),
              )),
          AppSpacing.heightMd,
        ],
      ],
    );
  }
}

/// Compact list tile for albums, artists, playlists in search results.
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
    required this.onTap,
    this.isCircle = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final borderRadius =
        isCircle ? BorderRadius.circular(24.0) : AppRadius.radiusMd;

    Widget thumbnail;
    if (hasImage) {
      thumbnail = ClipRRect(
        borderRadius: borderRadius,
        child: imageUrl!.startsWith('http')
            ? Image.network(
                imageUrl!,
                width: 48.0,
                height: 48.0,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _iconFallback(borderRadius),
              )
            : Image.file(
                File(imageUrl!),
                width: 48.0,
                height: 48.0,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _iconFallback(borderRadius),
              ),
      );
    } else {
      thumbnail = _iconFallback(borderRadius);
    }

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

// ── YouTube Specific Sections and Tabs ────────────────────────────────────────

extension _YouTubeSearchPageExtensions on _SearchPageState {
  Widget _buildTabSelector() {
    return Container(
      height: 44.0,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHighest,
        borderRadius: AppRadius.radiusMd,
      ),
      padding: const EdgeInsets.all(4.0),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _currentTab = 0;
                  _searchController.text = _searchQuery;
                });
                ref.read(searchNotifierProvider.notifier).updateQuery(_searchQuery);
              },
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _currentTab == 0
                      ? AppColors.surfaceContainerLowest
                      : Colors.transparent,
                  borderRadius: AppRadius.radiusMd,
                  boxShadow: _currentTab == 0 ? AppShadows.shadowLow : null,
                ),
                child: Text(
                  'Local Music',
                  style: AppTypography.labelMedium.copyWith(
                    color: _currentTab == 0
                        ? AppColors.primary
                        : AppColors.onSurfaceVariant,
                    fontWeight: _currentTab == 0 ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _currentTab = 1;
                  _searchController.text = _searchQuery;
                });
                ref.read(youtubeSearchProvider.notifier).searchDebounced(_searchQuery);
              },
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _currentTab == 1
                      ? AppColors.surfaceContainerLowest
                      : Colors.transparent,
                  borderRadius: AppRadius.radiusMd,
                  boxShadow: _currentTab == 1 ? AppShadows.shadowLow : null,
                ),
                child: Text(
                  'YouTube',
                  style: AppTypography.labelMedium.copyWith(
                    color: _currentTab == 1
                        ? AppColors.primary
                        : AppColors.onSurfaceVariant,
                    fontWeight: _currentTab == 1 ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYouTubeRecentSection() {
    final history = ref.watch(youtubeSearchHistoryProvider);
    if (history.isEmpty) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.45,
        child: EmptyState(
          title: 'Search YouTube',
          message: 'Find songs, artists, or albums online to stream immediately.',
          icon: Icons.youtube_searched_for,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Recent Searches',
          actionLabel: 'Clear',
          onActionTap: () {
            ref.read(youtubeSearchHistoryProvider.notifier).clearAll();
          },
        ),
        AppSpacing.heightMd,
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: history.take(4).map((query) {
            return SizedBox(
              width: (MediaQuery.of(context).size.width - AppSpacing.marginMobile * 2 - AppSpacing.md) / 2,
              child: _buildRecentSearchCard(
                title: query,
                subtitle: 'YouTube',
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
        ),
      ],
    );
  }
}

/// Displays YouTube search results dynamically.
class _YouTubeSearchResultsSection extends ConsumerWidget {
  final String query;

  const _YouTubeSearchResultsSection({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(youtubeSearchProvider);

    // 1. Loading State
    if (searchState.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48.0),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 2. Error State
    if (searchState.error != null) {
      return EmptyState(
        title: 'Search Error',
        message: searchState.error!,
        icon: Icons.wifi_off,
      );
    }

    // 3. Empty Results State
    if (searchState.isEmpty) {
      return EmptyState(
        title: 'No results found',
        message: 'Could not find any videos matching "$query".',
        icon: Icons.search_off,
      );
    }

    // 4. Results List
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'YouTube Results',
          actionLabel: '${searchState.results.length} found',
        ),
        AppSpacing.heightMd,
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: searchState.results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8.0),
          itemBuilder: (context, index) {
            final video = searchState.results[index];
            return YouTubeResultTile(video: video);
          },
        ),
        const SizedBox(height: 24.0),
      ],
    );
  }
}

