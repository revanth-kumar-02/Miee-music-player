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
import '../../../shared/models/music_item.dart';
import '../../../shared/widgets/widgets.dart';
import '../../profile/presentation/profile_controller.dart';

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

    // Listen to real device music providers
    final localSongs = ref.watch(songsProvider);
    final localAlbums = ref.watch(albumsProvider);
    final localArtists = ref.watch(artistsProvider);
    final profile = ref.watch(profileProvider);

    final hour = DateTime.now().hour;
    final greetingPrefix = hour < 12 ? 'Good Morning' : (hour < 17 ? 'Good Afternoon' : 'Good Evening');
    final firstName = profile.displayName.split(' ').first;

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
              imageUrl: profile.profilePicturePath,
              size: 32.0,
              onTap: () => context.push('/profile'),
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
                    '$greetingPrefix, $firstName',
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
                  _buildContinueListeningCard(context, localSongs),
                  AppSpacing.heightLg,

                  // Recently Played Section
                  const SectionHeader(
                    title: 'Recently Played',
                    isUppercase: true,
                  ),
                  AppSpacing.heightMd,
                  _buildRecentlyPlayedList(localAlbums),
                  AppSpacing.heightLg,

                  // Albums Section (Bento Grid)
                  const SectionHeader(
                    title: 'Albums',
                    isUppercase: true,
                  ),
                  AppSpacing.heightMd,
                  _buildBentoAlbumsGrid(context, localAlbums),
                  AppSpacing.heightLg,

                  // Favorite Artists Section
                  const SectionHeader(
                    title: 'Favorite Artists',
                    isUppercase: true,
                  ),
                  AppSpacing.heightMd,
                  _buildFavoriteArtistsList(localArtists),

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
                  musicItem: currentTrack,
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

  Widget _buildContinueListeningCard(BuildContext context, List<MediaSong> localSongs) {
    final hasLocal = localSongs.isNotEmpty;
    final displayTitle = hasLocal ? localSongs.first.title : MockData.featuredTrack.title;
    final displayArtist = hasLocal ? localSongs.first.artist : MockData.featuredTrack.artist;
    final displayArtwork = hasLocal ? localSongs.first.artworkPath : MockData.featuredTrack.imageUrl;

    final MusicItem targetTrack = hasLocal
        ? localSongs.first
        : MockData.featuredTrack;

    final List<MusicItem> trackList = hasLocal
        ? localSongs
        : [MockData.featuredTrack, ...MockData.favoriteSongs];

    return GestureDetector(
      onTap: () {
        ref.read(playerControllerProvider.notifier).selectTrack(targetTrack, trackList);
        context.push('/player');
      },
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
                  imageUrl: displayArtwork,
                  size: cardWidth,
                  showPlayButton: true,
                  onPlayTap: () {
                    ref.read(playerControllerProvider.notifier).selectTrack(targetTrack, trackList);
                    context.push('/player');
                  },
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
                    displayTitle,
                    style: AppTypography.headlineMedium.copyWith(
                      color: AppColors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  AppSpacing.heightXs,
                  Text(
                    displayArtist,
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

  Widget _buildRecentlyPlayedList(List<MediaAlbum> localAlbums) {
    final hasLocal = localAlbums.isNotEmpty;
    final itemCount = hasLocal ? localAlbums.length : MockData.recentlyPlayed.length;

    return SizedBox(
      height: 190.0, // Restrain height to wrap standard AlbumCards comfortably
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.none,
        itemCount: itemCount,
        separatorBuilder: (context, index) => AppSpacing.widthMd,
        itemBuilder: (context, index) {
          final imageUrl = hasLocal ? localAlbums[index].artworkPath : MockData.recentlyPlayed[index].imageUrl;
          final title = hasLocal ? localAlbums[index].title : MockData.recentlyPlayed[index].title;
          final subtitle = hasLocal ? '${localAlbums[index].trackCount} Songs' : MockData.recentlyPlayed[index].subtitle;

          return AlbumCard(
            imageUrl: imageUrl,
            title: title,
            subtitle: subtitle,
            variant: AlbumCardVariant.standard,
            onTap: () => context.push('/player'),
          );
        },
      ),
    );
  }

  Widget _buildBentoAlbumsGrid(BuildContext context, List<MediaAlbum> localAlbums) {
    final hasLocal = localAlbums.length >= 3;

    final heroImageUrl = hasLocal ? localAlbums[0].artworkPath : MockData.bentoHeroAlbum.imageUrl;
    final heroTitle = hasLocal ? localAlbums[0].title : MockData.bentoHeroAlbum.title;
    final heroSubtitle = hasLocal ? '${localAlbums[0].trackCount} Songs' : MockData.bentoHeroAlbum.subtitle;

    final sub1ImageUrl = hasLocal ? localAlbums[1].artworkPath : MockData.bentoSubAlbums[0].imageUrl;
    final sub1Title = hasLocal ? localAlbums[1].title : MockData.bentoSubAlbums[0].title;

    final sub2ImageUrl = hasLocal ? localAlbums[2].artworkPath : MockData.bentoSubAlbums[1].imageUrl;
    final sub2Title = hasLocal ? localAlbums[2].title : MockData.bentoSubAlbums[1].title;

    return Column(
      children: [
        AlbumCard(
          imageUrl: heroImageUrl,
          title: heroTitle,
          subtitle: heroSubtitle,
          variant: AlbumCardVariant.bentoHero,
          onTap: () => context.push('/player'),
        ),
        AppSpacing.heightMd,
        Row(
          children: [
            Expanded(
              child: AlbumCard(
                imageUrl: sub1ImageUrl,
                title: sub1Title,
                variant: AlbumCardVariant.bentoSub,
                onTap: () => context.push('/player'),
              ),
            ),
            AppSpacing.widthMd,
            Expanded(
              child: AlbumCard(
                imageUrl: sub2ImageUrl,
                title: sub2Title,
                variant: AlbumCardVariant.bentoSub,
                onTap: () => context.push('/player'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFavoriteArtistsList(List<MediaArtist> localArtists) {
    final hasLocal = localArtists.isNotEmpty;
    final itemCount = hasLocal ? localArtists.length : MockData.favoriteArtists.length;

    return SizedBox(
      height: 110.0, // Restrain height for avatar + space + text label
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.none,
        itemCount: itemCount,
        separatorBuilder: (context, index) => AppSpacing.widthLg,
        itemBuilder: (context, index) {
          final imageUrl = hasLocal ? '' : MockData.favoriteArtists[index].imageUrl;
          final name = hasLocal ? localArtists[index].name : MockData.favoriteArtists[index].name;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProfileAvatar(
                imageUrl: imageUrl.isEmpty ? null : imageUrl,
                size: 72.0,
                onTap: () {},
              ),
              AppSpacing.heightSm,
              Text(
                name,
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
