import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';


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
              leading: const Icon(Icons.image_outlined, color: AppColors.onSurface),
              title: const Text('Change Cover', style: TextStyle(color: AppColors.onSurface)),
              onTap: () {
                Navigator.pop(context);
                _pickPlaylistCover(context, ref, playlist.id);
              },
            ),
            if (playlist.customCoverPath != null)
              ListTile(
                leading: const Icon(Icons.hide_image_outlined, color: AppColors.onSurfaceVariant),
                title: const Text('Remove Custom Cover', style: TextStyle(color: AppColors.onSurfaceVariant)),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(playlistControllerProvider.notifier).updateCoverPath(playlist.id, null);
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

  Future<void> _pickPlaylistCover(BuildContext context, WidgetRef ref, String playlistId) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null) return;
    await ref
        .read(playlistControllerProvider.notifier)
        .updateCoverPath(playlistId, picked.path);
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
      backgroundColor: AppColors.background,
      appBar: AppHeader(
        title: 'Playlists',
        isScrolled: _isScrolled,
      ),
      body: SafeArea(
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
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Playlist Grid Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.marginMobile,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'User Playlists',
                      style: AppTypography.headlineLargeMobile.copyWith(
                        color: AppColors.onBackground,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => showCreatePlaylistDialog(context),
                      icon: const Icon(Icons.add),
                      label: const Text('New'),
                    ),
                  ],
                ),
              ),
            ),

            // Playlists Grid Layout
            if (playlists.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48.0),
                    child: EmptyState(
                      title: 'No playlists',
                      message: 'Create your first custom playlist above.',
                      icon: Icons.playlist_add,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220.0,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    childAspectRatio: 0.76,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final playlist = playlists[index];
                      return _buildPlaylistCard(context, playlist);
                    },
                    childCount: playlists.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistCard(BuildContext context, PlaylistModel playlist) {
    return _PlaylistGridCard(
      playlist: playlist,
      onOptionsTap: () => _showPlaylistOptions(context, ref, playlist),
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
    final artwork = playlist.effectiveCoverUrl;

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
