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
import '../../media/providers/media_providers.dart';
import '../../library/providers/library_providers.dart';
import '../domain/playlist_model.dart';
import '../providers/playlist_providers.dart';
import 'widgets/create_playlist_dialog.dart';

/// Redesigned Playlists Screen as a consolidated music hub.
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

  void _showPlaylistOptions(BuildContext context, WidgetRef ref, PlaylistModel playlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                playlist.name,
                style: AppTypography.headlineMedium.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppColors.onSurface),
              title: const Text('Rename Playlist', style: TextStyle(color: AppColors.onSurface)),
              onTap: () {
                Navigator.pop(context);
                showCreatePlaylistDialog(context, existingId: playlist.id, initialName: playlist.name);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete Playlist', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, ref, playlist);
              },
            ),
            const SizedBox(height: 12.0),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, PlaylistModel playlist) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text('Delete Playlist', style: TextStyle(color: AppColors.onSurface)),
        content: Text(
          'Are you sure you want to delete "${playlist.name}"? This action cannot be undone.',
          style: const TextStyle(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref.read(playlistControllerProvider.notifier).deletePlaylist(playlist.id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(allPlaylistsProvider);
    final localSongs = ref.watch(songsProvider);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final favorites = ref.watch(favoritesProvider);

    return Scaffold(
      extendBody: true,
      backgroundColor: AppColors.background,
      appBar: AppHeader(
        title: 'Playlists',
        isScrolled: _isScrolled,
      ),
      body: Stack(
        children: [
          // 1. Content View
          Positioned.fill(
            child: SafeArea(
              top: false,
              bottom: false,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // Prominent Local Songs Card
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.marginMobile,
                        right: AppSpacing.marginMobile,
                        top: AppSpacing.md,
                        bottom: AppSpacing.md,
                      ),
                      child: GestureDetector(
                        onTap: () => context.push('/local-songs'),
                        child: Container(
                          padding: const EdgeInsets.all(20.0),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF111111), Color(0xFF2A2A2A)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20.0),
                            boxShadow: AppShadows.shadowLow,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 56.0,
                                height: 56.0,
                                decoration: const BoxDecoration(
                                  color: Colors.black26,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.music_note,
                                  color: Colors.white,
                                  size: 32.0,
                                ),
                              ),
                              const SizedBox(width: 16.0),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Local Songs',
                                      style: AppTypography.headlineMedium.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4.0),
                                    Text(
                                      '${localSongs.length} track${localSongs.length != 1 ? "s" : ""}',
                                      style: AppTypography.bodyMedium.copyWith(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Colors.white70,
                                size: 28.0,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Divider Line
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
                      child: Divider(color: AppColors.outlineVariant, height: 24.0),
                    ),
                  ),

                  // "Your Playlists" Section Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.marginMobile,
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Your Playlists',
                            style: AppTypography.headlineMedium.copyWith(
                              color: AppColors.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async => showCreatePlaylistDialog(context),
                            icon: const Icon(Icons.add, size: 18.0),
                            label: const Text('Create'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Grid or Empty State of User Playlists
                  if (playlists.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.marginMobile,
                          vertical: AppSpacing.lg,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.queue_music_outlined,
                                size: 56.0,
                                color: AppColors.onSurfaceVariant,
                              ),
                              AppSpacing.heightSm,
                              Text(
                                'No playlists created yet',
                                style: AppTypography.bodyLarge.copyWith(
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              AppSpacing.heightXs,
                              Text(
                                'Create custom playlists to group your favorite tracks.',
                                textAlign: TextAlign.center,
                                style: AppTypography.labelSmall.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.only(
                        left: AppSpacing.marginMobile,
                        right: AppSpacing.marginMobile,
                        top: AppSpacing.sm,
                        bottom: 180.0,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16.0,
                          mainAxisSpacing: 20.0,
                          childAspectRatio: 0.75,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final playlist = playlists[index];
                            return _PlaylistGridCard(
                              playlist: playlist,
                              onOptionsTap: () => _showPlaylistOptions(context, ref, playlist),
                            );
                          },
                          childCount: playlists.length,
                        ),
                      ),
                    ),

                  // Bottom Spacing for MiniPlayer & BottomNavigation
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 180.0),
                  ),
                ],
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

          // 3. Fixed Shell Bottom Navigation Bar (4-item layout)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BottomNavigation(
              currentIndex: 2, // Playlists tab is index 2
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
  final VoidCallback onOptionsTap;

  const _PlaylistGridCard({
    required this.playlist,
    required this.onOptionsTap,
  });

  @override
  Widget build(BuildContext context) {
    final artwork = playlist.artworkTrack?.imageUrl;

    return GestureDetector(
      onTap: () => context.push('/playlist/${playlist.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: artwork != null
                      ? AlbumArtwork(
                          imageUrl: artwork,
                          size: double.infinity,
                          borderRadius: BorderRadius.circular(16.0),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF111111), Color(0xFF2A2A2A)],
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
                              color: Colors.white54,
                            ),
                          ),
                        ),
                ),
                Positioned(
                  top: 8.0,
                  right: 8.0,
                  child: GestureDetector(
                    onTap: onOptionsTap,
                    child: Container(
                      padding: const EdgeInsets.all(6.0),
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.more_vert,
                        color: Colors.white,
                        size: 18.0,
                      ),
                    ),
                  ),
                ),
              ],
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
