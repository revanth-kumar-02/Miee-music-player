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
import '../../../shared/models/mock_data.dart';
import '../../../shared/widgets/widgets.dart';

/// Miee Home Screen.
/// Arranges continue listening spotlight, scroll lists for recently played,
/// bento grid albums, favorite artists, mini player overlays, and bottom nav shells.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late final ScrollController _scrollController;
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

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
              imageUrl: null, // Displays default outline person icon
              size: 32.0,
              onTap: () => context.push('/settings'),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Scrollable Main Content Canvas
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSpacing.heightSm,
                  // Greeting Header
                  Text(
                    'Good morning',
                    style: AppTypography.headlineLargeMobile.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                  AppSpacing.heightLg,

                  // Continue Listening Section
                  const SectionHeader(
                    title: 'Continue Listening',
                    isUppercase: true,
                  ),
                  AppSpacing.heightMd,
                  _buildContinueListeningCard(context),
                  AppSpacing.heightLg,

                  // Recently Played Section
                  const SectionHeader(
                    title: 'Recently Played',
                    isUppercase: true,
                  ),
                  AppSpacing.heightMd,
                  _buildRecentlyPlayedList(),
                  AppSpacing.heightLg,

                  // Albums Section (Bento Grid)
                  const SectionHeader(
                    title: 'Albums',
                    isUppercase: true,
                  ),
                  AppSpacing.heightMd,
                  _buildBentoAlbumsGrid(context),
                  AppSpacing.heightLg,

                  // Favorite Artists Section
                  const SectionHeader(
                    title: 'Favorite Artists',
                    isUppercase: true,
                  ),
                  AppSpacing.heightMd,
                  _buildFavoriteArtistsList(),

                  // Bottom padding to ensure items scroll completely above floating players
                  SizedBox(height: 160.0 + bottomInset),
                ],
              ),
            ),
          ),

          // 2. Fixed Mini Player Overlay
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
                  isDark: true, // Black backing color matches Stitch HTML design
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
              currentIndex: 0,
              onTap: (index) {
                switch (index) {
                  case 0:
                    break;
                  case 1:
                    context.go('/search');
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

  Widget _buildContinueListeningCard(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/player'),
      child: Container(
        padding: AppSpacing.paddingAllSm,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest, // `#ffffff`
          borderRadius: AppRadius.radiusXl,
          boxShadow: AppShadows.shadowLow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth;
                return AlbumArtwork(
                  imageUrl: MockData.featuredTrack.imageUrl,
                  size: cardWidth,
                  showPlayButton: true,
                  onPlayTap: () => context.push('/player'),
                );
              },
            ),
            AppSpacing.heightSm,
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    MockData.featuredTrack.title,
                    style: AppTypography.headlineMedium.copyWith(
                      color: AppColors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  AppSpacing.heightXs,
                  Text(
                    MockData.featuredTrack.artist,
                    style: AppTypography.labelMedium.copyWith(
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

  Widget _buildRecentlyPlayedList() {
    return SizedBox(
      height: 190.0, // Restrain height to wrap standard AlbumCards comfortably
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.none,
        itemCount: MockData.recentlyPlayed.length,
        separatorBuilder: (context, index) => AppSpacing.widthMd,
        itemBuilder: (context, index) {
          final album = MockData.recentlyPlayed[index];
          return AlbumCard(
            imageUrl: album.imageUrl,
            title: album.title,
            subtitle: album.subtitle,
            variant: AlbumCardVariant.standard,
            onTap: () => context.push('/player'),
          );
        },
      ),
    );
  }

  Widget _buildBentoAlbumsGrid(BuildContext context) {
    return Column(
      children: [
        AlbumCard(
          imageUrl: MockData.bentoHeroAlbum.imageUrl,
          title: MockData.bentoHeroAlbum.title,
          subtitle: MockData.bentoHeroAlbum.subtitle,
          variant: AlbumCardVariant.bentoHero,
          onTap: () => context.push('/player'),
        ),
        AppSpacing.heightMd,
        Row(
          children: [
            Expanded(
              child: AlbumCard(
                imageUrl: MockData.bentoSubAlbums[0].imageUrl,
                title: MockData.bentoSubAlbums[0].title,
                variant: AlbumCardVariant.bentoSub,
                onTap: () => context.push('/player'),
              ),
            ),
            AppSpacing.widthMd,
            Expanded(
              child: AlbumCard(
                imageUrl: MockData.bentoSubAlbums[1].imageUrl,
                title: MockData.bentoSubAlbums[1].title,
                variant: AlbumCardVariant.bentoSub,
                onTap: () => context.push('/player'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFavoriteArtistsList() {
    return SizedBox(
      height: 110.0, // Restrain height for avatar + space + text label
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.none,
        itemCount: MockData.favoriteArtists.length,
        separatorBuilder: (context, index) => AppSpacing.widthLg,
        itemBuilder: (context, index) {
          final artist = MockData.favoriteArtists[index];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProfileAvatar(
                imageUrl: artist.imageUrl,
                size: 72.0,
                onTap: () {},
              ),
              AppSpacing.heightSm,
              Text(
                artist.name,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
