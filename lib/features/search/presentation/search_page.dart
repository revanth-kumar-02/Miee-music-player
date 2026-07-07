import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_shadows.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../shared/models/mock_data.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../core/widgets/empty_state.dart';

/// Miee Search Screen.
/// Combines dynamic search toggles, filter chip selectors, bento-grid search history,
/// vertical list of trending song tiles, library category grids, and overlay mini players.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final ScrollController _scrollController;
  late final TextEditingController _searchController;
  bool _isScrolled = false;
  String _selectedFilter = 'All';
  String _searchQuery = '';

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
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isSearching = _searchQuery.isNotEmpty;

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
                    placeholder: 'Artists, songs, or podcasts',
                  ),
                  AppSpacing.heightLg,

                  // Show EmptyState placeholder if search query is active
                  if (isSearching) ...[
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.45,
                      child: EmptyState(
                        title: 'Search results',
                        message: 'Results for "$_searchQuery" will appear here once connected to the music engine.',
                        icon: Icons.search,
                      ),
                    ),
                  ] else ...[
                    // Filter Chips horizontal row
                    _buildFilterChips(),
                    AppSpacing.heightLg,

                    // Recent Searches Section (Bento Grid)
                    const SectionHeader(
                      title: 'Recent',
                      actionLabel: 'Clear',
                    ),
                    AppSpacing.heightMd,
                    _buildBentoRecentSearches(),
                    AppSpacing.heightLg,

                    // Trending Now Section
                    const SectionHeader(
                      title: 'Trending Now',
                    ),
                    AppSpacing.heightMd,
                    _buildTrendingSongsList(context),
                    AppSpacing.heightLg,

                    // Browse Categories Grid
                    const SectionHeader(
                      title: 'Browse Categories',
                    ),
                    AppSpacing.heightMd,
                    _buildBrowseCategoriesGrid(),
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
            child: MiniPlayer(
              imageUrl: MockData.featuredTrack.imageUrl,
              title: MockData.featuredTrack.title,
              artist: MockData.featuredTrack.artist,
              progress: MockData.featuredTrack.progress,
              isPlaying: MockData.featuredTrack.isPlaying,
              isFavorited: MockData.featuredTrack.isFavorited,
              isDark: false, // Light mode matches the surface container background
              onTap: () => context.push('/player'),
              onPlayPauseTap: () {},
              onFavoriteTap: () {},
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

  Widget _buildBentoRecentSearches() {
    return Row(
      children: [
        // Bento Search Item 1: Artist
        Expanded(
          child: _buildRecentSearchCard(
            title: 'Brambles',
            subtitle: 'Artist',
            topWidget: Container(
              width: 40.0,
              height: 40.0,
              decoration: const BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history,
                color: AppColors.onSurfaceVariant,
                size: 20.0,
              ),
            ),
          ),
        ),
        AppSpacing.widthMd,
        // Bento Search Item 2: Album
        Expanded(
          child: _buildRecentSearchCard(
            title: 'Charcoal',
            subtitle: 'Album',
            topWidget: ClipRRect(
              borderRadius: BorderRadius.circular(20.0), // circular avatar size 40
              child: Image.network(
                MockData.recentlyPlayed[0].imageUrl,
                width: 40.0,
                height: 40.0,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 40.0,
                  height: 40.0,
                  color: AppColors.surfaceContainerHigh,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentSearchCard({
    required String title,
    required String subtitle,
    required Widget topWidget,
  }) {
    return Container(
      padding: AppSpacing.paddingAllMd,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest, // `#ffffff`
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
    );
  }

  Widget _buildTrendingSongsList(BuildContext context) {
    // Show top 3 tracks from mock data as trending tracks
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
            onTap: () => context.push('/player'),
          ),
        );
      }),
    );
  }

  Widget _buildBrowseCategoriesGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: CategoryCard(
                icon: Icons.album_outlined,
                title: 'Albums',
                subtitle: '24 Albums',
                onTap: () {},
              ),
            ),
            AppSpacing.widthMd,
            Expanded(
              child: CategoryCard(
                icon: Icons.person_outline,
                title: 'Artists',
                subtitle: '12 Artists',
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
                subtitle: '8 Playlists',
                onTap: () {},
              ),
            ),
            AppSpacing.widthMd,
            Expanded(
              child: CategoryCard(
                icon: Icons.music_note_outlined,
                title: 'Genres',
                subtitle: '6 Genres',
                onTap: () {},
              ),
            ),
          ],
        ),
      ],
    );
  }
}
