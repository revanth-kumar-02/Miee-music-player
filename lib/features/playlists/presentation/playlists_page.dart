import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_shadows.dart';
import '../../../app/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../core/audio/providers.dart';
import '../../../core/audio/playback_state.dart';
import '../../library/providers/library_providers.dart';
import '../domain/playlist_model.dart';
import '../providers/playlist_providers.dart';
import 'widgets/create_playlist_dialog.dart';

/// Playlists Screen listing all user created playlists in a beautiful grid.
class PlaylistsPage extends ConsumerStatefulWidget {
  const PlaylistsPage({super.key});

  @override
  ConsumerState<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends ConsumerState<PlaylistsPage> {
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
    final playlists = ref.watch(allPlaylistsProvider);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final favorites = ref.watch(favoritesProvider);

    return Scaffold(
      extendBody: true,
      appBar: AppHeader(
        title: 'Playlists',
        isScrolled: _isScrolled,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
          splashRadius: 20.0,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async => showCreatePlaylistDialog(context),
            splashRadius: 20.0,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Grid Content
          Positioned.fill(
            child: SafeArea(
              top: false,
              bottom: false,
              child: playlists.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.queue_music_outlined,
                            size: 64.0,
                            color: AppColors.onSurfaceVariant,
                          ),
                          AppSpacing.heightMd,
                          Text(
                            'No playlists yet',
                            style: AppTypography.headlineMedium.copyWith(
                              color: AppColors.onSurface,
                            ),
                          ),
                          AppSpacing.heightSm,
                          Text(
                            'Create your first playlist to organize your music.',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          AppSpacing.heightLg,
                          FilledButton.icon(
                            onPressed: () async => showCreatePlaylistDialog(context),
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: const Text('Create Playlist', style: TextStyle(color: Colors.white)),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                            ),
                          ),
                          SizedBox(height: 160.0 + bottomInset),
                        ],
                      ),
                    )
                  : GridView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.only(
                        left: AppSpacing.marginMobile,
                        right: AppSpacing.marginMobile,
                        top: AppSpacing.md,
                        bottom: 180.0 + bottomInset,
                      ),
                      physics: const BouncingScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16.0,
                        mainAxisSpacing: 20.0,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: playlists.length,
                      itemBuilder: (context, index) {
                        final playlist = playlists[index];
                        return _PlaylistGridCard(playlist: playlist);
                      },
                    ),
            ),
          ),

          // 2. Floating MiniPlayer
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
                  isDark: true,
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
              currentIndex: 3,
              onTap: (index) {
                switch (index) {
                  case 0:
                    context.go('/home');
                    break;
                  case 1:
                    context.go('/search');
                    break;
                  case 2:
                    context.go('/library');
                    break;
                  case 3:
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
}

class _PlaylistGridCard extends StatelessWidget {
  final PlaylistModel playlist;

  const _PlaylistGridCard({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final artwork = playlist.artworkTrack?.imageUrl;

    return GestureDetector(
      onTap: () => context.push('/playlist/${playlist.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: artwork != null
                ? AlbumArtwork(
                    imageUrl: artwork,
                    size: double.infinity,
                    borderRadius: BorderRadius.circular(16.0),
                  )
                : Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.surfaceContainerHigh, AppColors.surfaceContainer],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16.0),
                      boxShadow: AppShadows.shadowLow,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.queue_music,
                        size: 48.0,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),
          AppSpacing.heightSm,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Text(
              playlist.tracks.isEmpty
                  ? '0 tracks'
                  : '${playlist.tracks.length} track${playlist.tracks.length > 1 ? "s" : ""}',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
