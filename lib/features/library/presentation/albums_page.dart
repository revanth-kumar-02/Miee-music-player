import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../../media/providers/media_providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/audio/providers.dart';
import '../../../core/audio/playback_state.dart';
import '../../../features/library/providers/library_providers.dart';

class AlbumsPage extends ConsumerStatefulWidget {
  const AlbumsPage({super.key});

  @override
  ConsumerState<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends ConsumerState<AlbumsPage> {
  final TextEditingController _searchController = TextEditingController();
  bool _isScrolled = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.offset > 10.0 && !_isScrolled) {
      setState(() => _isScrolled = true);
    } else if (_scrollController.offset <= 10.0 && _isScrolled) {
      setState(() => _isScrolled = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final albums = ref.watch(albumsProvider);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final query = _searchController.text.toLowerCase().trim();
    final filteredAlbums = albums.where((album) {
      return album.title.toLowerCase().contains(query) ||
          album.artist.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppHeader(
        title: 'Albums',
        isScrolled: _isScrolled,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              top: false,
              bottom: false,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // Search Bar
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.marginMobile,
                        vertical: AppSpacing.md,
                      ),
                      child: AppSearchBar(
                        controller: _searchController,
                        placeholder: 'Search albums...',
                        onSubmitted: (_) {},
                      ),
                    ),
                  ),

                  if (filteredAlbums.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        title: 'No albums found',
                        message: 'Try checking your search query.',
                        icon: Icons.album_outlined,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.marginMobile,
                        right: AppSpacing.marginMobile,
                        bottom: 120.0,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16.0,
                          mainAxisSpacing: 16.0,
                          childAspectRatio: 0.75,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final album = filteredAlbums[index];
                            final hasArt = album.artworkPath.isNotEmpty;
                            
                            return GestureDetector(
                              onTap: () => context.push('/album/${album.id}'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(16.0),
                                        image: hasArt
                                            ? DecorationImage(
                                                image: FileImage(File(album.artworkPath)),
                                                fit: BoxFit.cover,
                                              )
                                            : null,
                                      ),
                                      alignment: Alignment.center,
                                      child: !hasArt
                                          ? const Icon(
                                              Icons.album,
                                              size: 48.0,
                                              color: AppColors.onSurfaceVariant,
                                            )
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 8.0),
                                  Text(
                                    album.title,
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: AppColors.onSurface,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2.0),
                                  Text(
                                    '${album.artist} · ${album.trackCount} track${album.trackCount != 1 ? 's' : ''}',
                                    style: AppTypography.labelSmall.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            );
                          },
                          childCount: filteredAlbums.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Mini Player
          Positioned(
            left: AppSpacing.marginMobile,
            right: AppSpacing.marginMobile,
            bottom: bottomInset + AppSpacing.sm,
            child: Consumer(
              builder: (context, ref, child) {
                final playbackState = ref.watch(playerControllerProvider);
                final currentTrack = playbackState.currentTrack;
                if (currentTrack == null) return const SizedBox.shrink();
                
                final favorites = ref.watch(favoritesProvider);
                final isPlaying = playbackState.status == PlaybackStatus.playing;
                final total = playbackState.duration.inMilliseconds;
                final pos = playbackState.position.inMilliseconds;
                final progress = total > 0 ? pos / total : 0.0;

                return MiniPlayer(
                  musicItem: currentTrack,
                  progress: progress,
                  isPlaying: isPlaying,
                  isFavorited: favorites.any((t) => t.id == currentTrack.id),
                  isDark: false,
                  onTap: () => context.push('/player'),
                  onPlayPauseTap: () {
                    final controller = ref.read(playerControllerProvider.notifier);
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
        ],
      ),
    );
  }
}
