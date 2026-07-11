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
import '../../../shared/models/music_item.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../core/widgets/empty_state.dart';
import '../../profile/presentation/profile_controller.dart';
import '../../library/providers/library_providers.dart';

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
    final favorites = ref.watch(favoritesProvider);

    final hour = DateTime.now().hour;
    final greetingPrefix = hour < 12 ? 'Good Morning' : (hour < 17 ? 'Good Afternoon' : 'Good Evening');
    final firstName = profile.displayName.split(' ').first;

    return Scaffold(
      extendBody: true,
      appBar: AppHeader(
        title: 'Miee',
        isScrolled: _isScrolled,
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

                  if (localSongs.isEmpty) ...[
                    AppSpacing.heightLg,
                    const EmptyState(
                      title: 'No music found',
                      message: 'Import your local music or connect a music source.',
                      icon: Icons.music_off_outlined,
                    ),
                  ] else ...[
                    // Continue Listening Section
                    const SectionHeader(
                      title: 'Continue Listening',
                      isUppercase: true,
                    ),
                    AppSpacing.heightMd,
                    _buildContinueListeningCard(context, localSongs),
                    AppSpacing.heightLg,

                    if (localAlbums.isNotEmpty) ...[
                      // Recently Played Section
                      const SectionHeader(
                        title: 'Recently Played',
                        isUppercase: true,
                      ),
                      AppSpacing.heightMd,
                      _buildRecentlyPlayedList(localAlbums, localSongs),
                      AppSpacing.heightLg,

                      // Albums Section (Bento Grid)
                      const SectionHeader(
                        title: 'Albums',
                        isUppercase: true,
                      ),
                      AppSpacing.heightMd,
                      _buildBentoAlbumsGrid(context, localAlbums, localSongs),
                      AppSpacing.heightLg,
                    ],

                    if (localArtists.isNotEmpty) ...[
                      // Favorite Artists Section
                      const SectionHeader(
                        title: 'Favorite Artists',
                        isUppercase: true,
                      ),
                      AppSpacing.heightMd,
                      _buildFavoriteArtistsList(localArtists),
                    ],
                  ],

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
                  isFavorited: favorites.any((t) => t.id == currentTrack.id),
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
                    context.go('/playlists');
                    break;
                  case 3:
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
    final displayTitle = localSongs.first.title;
    final displayArtist = localSongs.first.artist;
    final displayArtwork = localSongs.first.artworkPath;

    final MusicItem targetTrack = localSongs.first;
    final List<MusicItem> trackList = localSongs;

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

  Widget _buildRecentlyPlayedList(
    List<MediaAlbum> localAlbums,
    List<MediaSong> localSongs,
  ) {
    return SizedBox(
      height: 205.0, // Restrain height to wrap standard AlbumCards comfortably without overflows
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.none,
        itemCount: localAlbums.length,
        separatorBuilder: (context, index) => AppSpacing.widthMd,
        itemBuilder: (context, index) {
          final album = localAlbums[index];
          final imageUrl = album.artworkPath;
          final title = album.title;
          final subtitle = '${album.trackCount} Songs';

          return AlbumCard(
            imageUrl: imageUrl,
            title: title,
            subtitle: subtitle,
            variant: AlbumCardVariant.standard,
            onTap: () {
              // Find songs that belong to this album and start playback
              final albumSongs = localSongs
                  .where((s) => s.album == album.title)
                  .toList();
              final queue = albumSongs.isNotEmpty ? albumSongs : localSongs;
              if (queue.isNotEmpty) {
                ref
                    .read(playerControllerProvider.notifier)
                    .selectTrack(queue.first, queue);
                context.push('/player');
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildBentoAlbumsGrid(
    BuildContext context,
    List<MediaAlbum> localAlbums,
    List<MediaSong> localSongs,
  ) {
    // Helper: start playback of the first song in an album
    void playAlbum(MediaAlbum album) {
      final albumSongs = localSongs
          .where((s) => s.album == album.title)
          .toList();
      final queue = albumSongs.isNotEmpty ? albumSongs : localSongs;
      if (queue.isNotEmpty) {
        ref
            .read(playerControllerProvider.notifier)
            .selectTrack(queue.first, queue);
        context.push('/player');
      }
    }

    final heroImageUrl = localAlbums.isNotEmpty ? localAlbums[0].artworkPath : '';
    final heroTitle = localAlbums.isNotEmpty ? localAlbums[0].title : '';
    final heroSubtitle = localAlbums.isNotEmpty ? '${localAlbums[0].trackCount} Songs' : '';

    final sub1ImageUrl = localAlbums.length > 1 ? localAlbums[1].artworkPath : '';
    final sub1Title = localAlbums.length > 1 ? localAlbums[1].title : '';

    final sub2ImageUrl = localAlbums.length > 2 ? localAlbums[2].artworkPath : '';
    final sub2Title = localAlbums.length > 2 ? localAlbums[2].title : '';

    return Column(
      children: [
        AlbumCard(
          imageUrl: heroImageUrl,
          title: heroTitle,
          subtitle: heroSubtitle,
          variant: AlbumCardVariant.bentoHero,
          onTap: localAlbums.isNotEmpty
              ? () => playAlbum(localAlbums[0])
              : null,
        ),
        AppSpacing.heightMd,
        Row(
          children: [
            Expanded(
              child: AlbumCard(
                imageUrl: sub1ImageUrl,
                title: sub1Title,
                variant: AlbumCardVariant.bentoSub,
                onTap: localAlbums.length > 1
                    ? () => playAlbum(localAlbums[1])
                    : null,
              ),
            ),
            AppSpacing.widthMd,
            Expanded(
              child: AlbumCard(
                imageUrl: sub2ImageUrl,
                title: sub2Title,
                variant: AlbumCardVariant.bentoSub,
                onTap: localAlbums.length > 2
                    ? () => playAlbum(localAlbums[2])
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFavoriteArtistsList(List<MediaArtist> localArtists) {
    return SizedBox(
      height: 125.0, // Expanded height for avatar + space + single-line text label
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.none,
        itemCount: localArtists.length,
        separatorBuilder: (context, index) => AppSpacing.widthLg,
        itemBuilder: (context, index) {
          final name = localArtists[index].name;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProfileAvatar(
                imageUrl: localArtists[index].artworkPath,
                size: 72.0,
                onTap: () {},
              ),
              AppSpacing.heightSm,
              SizedBox(
                width: 72.0, // Constrain text width to match avatar width
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
