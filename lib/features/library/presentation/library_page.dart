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
import '../../../shared/models/music_item.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../core/widgets/empty_state.dart';
import '../../playlists/domain/playlist_model.dart';
import '../../playlists/providers/playlist_providers.dart';
import '../../playlists/presentation/widgets/create_playlist_dialog.dart';
import '../../profile/presentation/profile_controller.dart';
import '../providers/library_providers.dart';

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

    final profile = ref.watch(profileProvider);
    final localSongs = ref.watch(songsProvider);
    final favorites = ref.watch(favoritesProvider);

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
                  // Page Header Row
                  _buildPageHeader(context),
                  AppSpacing.heightLg,

                  if (localSongs.isEmpty) ...[
                    AppSpacing.heightLg,
                    const EmptyState(
                      title: 'No songs available',
                      message: 'Scan your device to start building your library.',
                      icon: Icons.library_music_outlined,
                    ),
                  ] else ...[
                    // Library Categories Grid (3-row, 2-column flex layout)
                    Consumer(
                      builder: (context, ref, child) {
                        final localAlbums = ref.watch(albumsProvider);
                        final localArtists = ref.watch(artistsProvider);
                        final localGenres = ref.watch(genresProvider);
                        final localPlaylists = ref.watch(playlistsProvider);
                        final localFolders = ref.watch(foldersProvider);

                        return _buildCategoryGrid(
                          localSongs.length,
                          localAlbums.length,
                          localArtists.length,
                          localPlaylists.length,
                          localGenres.length,
                          localFolders.length,
                        );
                      },
                    ),
                    AppSpacing.heightLg,

                    // Recently Added Section
                    Consumer(
                      builder: (context, ref, child) {
                        final localAlbums = ref.watch(albumsProvider);
                        if (localAlbums.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionHeader(
                              title: 'Recently Added',
                            ),
                            AppSpacing.heightMd,
                            _buildRecentlyAddedList(localAlbums),
                            AppSpacing.heightLg,
                          ],
                        );
                      },
                    ),

                    // My Playlists Section
                    Consumer(
                      builder: (context, ref, child) {
                        final playlists = ref.watch(allPlaylistsProvider);
                        return _buildMyPlaylistsSection(context, ref, playlists);
                      },
                    ),

                    AppSpacing.heightLg,

                    // Favorites Section
                    const SectionHeader(
                      title: 'Favorites',
                    ),
                    AppSpacing.heightMd,
                    _buildFavoritesList(context, favorites),
                  ],

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
                  musicItem: currentTrack,
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
                    context.go('/playlists');
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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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

  Widget _buildCategoryGrid(
    int songsCount,
    int albumsCount,
    int artistsCount,
    int playlistsCount,
    int genresCount,
    int foldersCount,
  ) {
    final songsLabel = songsCount > 0 ? '$songsCount Songs' : '328 Songs';
    final albumsLabel = albumsCount > 0 ? '$albumsCount Albums' : '45 Albums';
    final artistsLabel = artistsCount > 0 ? '$artistsCount Artists' : '12 Artists';
    final playlistsLabel = playlistsCount > 0 ? '$playlistsCount Playlists' : '8 Playlists';
    final genresLabel = genresCount > 0 ? '$genresCount Genres' : '15 Genres';
    final foldersLabel = foldersCount > 0 ? '$foldersCount Folders' : '4 Folders';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: CategoryCard(
                icon: Icons.music_note,
                title: 'Songs',
                subtitle: songsLabel,
                onTap: () {},
              ),
            ),
            AppSpacing.widthMd,
            Expanded(
              child: CategoryCard(
                icon: Icons.album,
                title: 'Albums',
                subtitle: albumsLabel,
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
                subtitle: artistsLabel,
                onTap: () {},
              ),
            ),
            AppSpacing.widthMd,
            Expanded(
              child: CategoryCard(
                icon: Icons.queue_music,
                title: 'Playlists',
                subtitle: playlistsLabel,
                onTap: () => _showPlaylistsSheet(context),
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
                subtitle: genresLabel,
                onTap: () {},
              ),
            ),
            AppSpacing.widthMd,
            Expanded(
              child: CategoryCard(
                icon: Icons.folder_open,
                title: 'Folders',
                subtitle: foldersLabel,
                onTap: () {},
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecentlyAddedList(List<MediaAlbum> localAlbums) {
    return SizedBox(
      height: 190.0, // Restrain height to wrap standard AlbumCards comfortably
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.none,
        itemCount: localAlbums.length,
        separatorBuilder: (context, index) => AppSpacing.widthMd,
        itemBuilder: (context, index) {
          final imageUrl = localAlbums[index].artworkPath;
          final title = localAlbums[index].title;
          final subtitle = '${localAlbums[index].trackCount} Songs';

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

  Widget _buildFavoritesList(BuildContext context, List<Track> favorites) {
    if (favorites.isNotEmpty) {
      final displaySongs = favorites.take(5).toList();
      return Column(
        children: List.generate(displaySongs.length, (index) {
          final track = displaySongs[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: SongTile(
              title: track.title,
              artist: track.artist,
              duration: track.duration,
              imageUrl: track.imageUrl,
              isPlaying: false,
              onTap: () {
                ref.read(playerControllerProvider.notifier).selectTrack(track, favorites);
                context.push('/player');
              },
            ),
          );
        }),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Text(
        'No favorite songs yet',
        style: AppTypography.bodyMedium
            .copyWith(color: AppColors.onSurfaceVariant),
      ),
    );
  }

  Widget _buildMyPlaylistsSection(
      BuildContext context, WidgetRef ref, List<PlaylistModel> playlists) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'My Playlists',
          actionLabel: 'New',
          onActionTap: () async {
            await showCreatePlaylistDialog(context);
          },
        ),
        if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No playlists yet',
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
                AppSpacing.heightMd,
                ElevatedButton.icon(
                  onPressed: () async => showCreatePlaylistDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Create Playlist'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          AppSpacing.heightMd,
          SizedBox(
            height: 100.0,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              clipBehavior: Clip.none,
              itemCount: playlists.length,
              separatorBuilder: (_, __) => AppSpacing.widthMd,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return _PlaylistCard(playlist: playlist);
              },
            ),
          ),
        ],
      ],
    );
  }

  void _showPlaylistsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final playlists = ref.watch(allPlaylistsProvider);
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
                  child: Container(
                    width: 36.0, height: 4.0,
                    decoration: BoxDecoration(
                      color: AppColors.outlineVariant,
                      borderRadius: BorderRadius.circular(2.0),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.marginMobile, vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Playlists',
                            style: AppTypography.headlineMedium
                                .copyWith(color: AppColors.onSurface)),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 18.0),
                        label: const Text('New'),
                        onPressed: () async {
                          await showCreatePlaylistDialog(context);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: playlists.isEmpty
                      ? Center(
                          child: Text('No playlists yet',
                              style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.onSurfaceVariant)))
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          itemCount: playlists.length,
                          itemBuilder: (context, index) {
                            final p = playlists[index];
                            return ListTile(
                              leading: Container(
                                width: 48.0, height: 48.0,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerHighest,
                                  borderRadius: AppRadius.radiusMd,
                                ),
                                child: const Icon(Icons.queue_music,
                                    color: AppColors.onSurfaceVariant),
                              ),
                              title: Text(p.name,
                                  style: AppTypography.labelMedium
                                      .copyWith(color: AppColors.onSurface)),
                              subtitle: Text(
                                  '${p.songCount} songs · ${p.totalDurationFormatted}',
                                  style: AppTypography.labelSmall.copyWith(
                                      color: AppColors.onSurfaceVariant)),
                              onTap: () {
                                Navigator.of(context).pop();
                                context.push('/playlist/${p.id}');
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Small horizontal-scroll playlist card used in My Playlists row.
class _PlaylistCard extends StatelessWidget {
  final PlaylistModel playlist;
  const _PlaylistCard({required this.playlist});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/playlist/${playlist.id}'),
      child: Container(
        width: 90.0,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: AppRadius.radiusLg,
          boxShadow: AppShadows.shadowLow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.lg)),
              child: Container(
                width: 90.0,
                height: 60.0,
                color: AppColors.surfaceContainerHighest,
                child: const Icon(Icons.queue_music,
                    color: AppColors.onSurfaceVariant, size: 28.0),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6.0, vertical: 4.0),
                child: Text(
                  playlist.name,
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.onSurface),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
