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

/// Miee Library Screen.
/// Arranges category grids (Songs, Albums, Artists, Playlists, Genres, Folders),
/// recently added horizontal list, favorites track rows, fixed mini player, and bottom nav.
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
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

    // Direct profile image URL from Stitch design header asset
    const profileImageUrl =
        'https://lh3.googleusercontent.com/aida-public/AB6AXuCDZmpkhy-KZuf2O4xloHsZzxPp8DkoTGkjoVFnKicBJ6XInSpyLlI7yQY9pd49dU1cRtDq_xCLGdWwTYRALTpFoQs81kp8gIHaCC5JRhN2a294dQGoH7x67HFERLUUS-_8hZlEJ_VaspfYRd-TKOIkujaKRQJivS2hEhODaDlj6L5AgeV6ZVq6y6L2KIsAEB-SgefGsC4x0oRFu0cGizDlywju5_X_jtaNz8W_aj03825ZM8XtF3WlB8anP5-f29u01fLWnLy-OanQ';

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
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: AppSpacing.marginMobile),
            child: ProfileAvatar(
              imageUrl: profileImageUrl,
              size: 32.0,
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
                  // Page Header Row
                  _buildPageHeader(context),
                  AppSpacing.heightLg,

                  // Library Categories Grid (3-row, 2-column flex layout)
                  _buildCategoryGrid(),
                  AppSpacing.heightLg,

                  // Recently Added Section
                  const SectionHeader(
                    title: 'Recently Added',
                  ),
                  AppSpacing.heightMd,
                  _buildRecentlyAddedList(),
                  AppSpacing.heightLg,

                  // Favorites Section
                  const SectionHeader(
                    title: 'Favorites',
                  ),
                  AppSpacing.heightMd,
                  _buildFavoritesList(context),

                  // Bottom padding safety offset for floating overlays
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
              currentIndex: 2, // Library tab highlighted as active
              onTap: (index) {
                switch (index) {
                  case 0:
                    context.go('/home');
                    break;
                  case 1:
                    context.go('/search');
                    break;
                  case 2:
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

  Widget _buildPageHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.between,
      children: [
        Text(
          'Library',
          style: AppTypography.headlineLargeMobile.copyWith(
            color: AppColors.onSurface,
          ),
        ),
        GestureDetector(
          onTap: () => context.go('/search'),
          child: Container(
            width: 40.0,
            height: 40.0,
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerLow,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search,
              color: AppColors.onSurface,
              size: 20.0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: CategoryCard(
                icon: Icons.music_note,
                title: 'Songs',
                subtitle: '328 Songs',
                onTap: () {},
              ),
            ),
            AppSpacing.widthMd,
            Expanded(
              child: CategoryCard(
                icon: Icons.album,
                title: 'Albums',
                subtitle: '45 Albums',
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
                icon: Icons.mic_none,
                title: 'Artists',
                subtitle: '12 Artists',
                onTap: () {},
              ),
            ),
            AppSpacing.widthMd,
            Expanded(
              child: CategoryCard(
                icon: Icons.queue_music,
                title: 'Playlists',
                subtitle: '8 Playlists',
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
                icon: Icons.category_outlined,
                title: 'Genres',
                subtitle: '15 Genres',
                onTap: () {},
              ),
            ),
            AppSpacing.widthMd,
            Expanded(
              child: CategoryCard(
                icon: Icons.folder_open,
                title: 'Folders',
                subtitle: '4 Folders',
                onTap: () {},
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecentlyAddedList() {
    return SizedBox(
      height: 190.0, // Restrain height to wrap standard AlbumCards comfortably
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.none,
        itemCount: MockData.recentlyAdded.length,
        separatorBuilder: (context, index) => AppSpacing.widthMd,
        itemBuilder: (context, index) {
          final album = MockData.recentlyAdded[index];
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

  Widget _buildFavoritesList(BuildContext context) {
    return Column(
      children: List.generate(MockData.favoriteSongs.length, (index) {
        final track = MockData.favoriteSongs[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: SongTile(
            title: track.title,
            artist: track.artist,
            duration: track.duration,
            imageUrl: track.imageUrl,
            isPlaying: false,
            onTap: () => context.push('/player'),
          ),
        );
      }),
    );
  }
}
