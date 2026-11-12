import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/audio/providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../shared/models/music_item.dart';
import '../../artwork/presentation/miee_artwork_image.dart';
import '../domain/playlist_model.dart';
import '../providers/playlist_providers.dart';
import 'widgets/add_songs_to_playlist_sheet.dart';
import 'widgets/add_to_playlist_sheet.dart';
import 'widgets/create_playlist_dialog.dart';

/// Full-screen Playlist Detail — shows artwork, metadata, reorderable song list.
class PlaylistDetailPage extends ConsumerWidget {
  final String playlistId;
  const PlaylistDetailPage({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(playlistControllerProvider).playlists
        .where((p) => p.id == playlistId)
        .firstOrNull;

    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const EmptyState(
          title: 'Playlist not found',
          message: 'This playlist may have been deleted.',
          icon: Icons.playlist_remove,
        ),
      );
    }

    return _PlaylistDetailView(playlist: playlist);
  }
}

class _PlaylistDetailView extends ConsumerWidget {
  final PlaylistModel playlist;
  const _PlaylistDetailView({required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPlayingTrackId = ref.watch(
      playerControllerProvider.select((s) => s.currentTrack?.id),
    );
    final controller = ref.read(playlistControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Sliver App Bar with artwork ─────────────────────────────────────
          SliverAppBar(
            expandedHeight: 280.0,
            pinned: true,
            backgroundColor: AppColors.background,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
              onPressed: () => context.pop(),
              splashRadius: 20.0,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.playlist_add, color: AppColors.onSurface),
                tooltip: 'Add Songs',
                onPressed: () => showAddSongsToPlaylistSheet(context, playlist),
                splashRadius: 20.0,
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, color: AppColors.onSurface),
                onPressed: () => _showOptionsMenu(context, ref),
                splashRadius: 20.0,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildArtwork(playlist),
            ),
          ),

          // ── Playlist metadata ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.marginMobile),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    style: AppTypography.headlineLargeMobile
                        .copyWith(color: AppColors.onSurface),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  AppSpacing.heightXs,
                  Text(
                    '${playlist.songCount} ${playlist.songCount == 1 ? 'song' : 'songs'} · ${playlist.totalDurationFormatted}',
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.onSurfaceVariant),
                  ),
                  AppSpacing.heightMd,

                  // ── Play / Shuffle / Add buttons ─────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.play_arrow, size: 20.0),
                          label: Text('Play',
                              style: AppTypography.labelMedium
                                  .copyWith(color: Colors.white)),
                          onPressed: playlist.isEmpty
                              ? null
                              : () {
                                  controller.playPlaylist(playlist.id);
                                  context.push('/player');
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                                borderRadius: AppRadius.radiusMd),
                          ),
                        ),
                      ),
                      AppSpacing.widthSm,
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.shuffle, size: 20.0),
                          label: Text('Shuffle',
                              style: AppTypography.labelMedium
                                  .copyWith(color: AppColors.onSurface)),
                          onPressed: playlist.isEmpty
                              ? null
                              : () {
                                  controller.shufflePlaylist(playlist.id);
                                  context.push('/player');
                                },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: AppColors.outline, width: 1.0),
                            shape: RoundedRectangleBorder(
                                borderRadius: AppRadius.radiusMd),
                          ),
                        ),
                      ),
                      AppSpacing.widthSm,
                      IconButton.filledTonal(
                        icon: const Icon(Icons.playlist_add, size: 22.0),
                        tooltip: 'Add Songs',
                        onPressed: () =>
                            showAddSongsToPlaylistSheet(context, playlist),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surfaceContainerHigh,
                          foregroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.radiusMd),
                        ),
                      ),
                    ],
                  ),
                  AppSpacing.heightMd,
                ],
              ),
            ),
          ),

          // ── Song list ───────────────────────────────────────────────────────
          playlist.isEmpty
              ? SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.queue_music_rounded,
                            size: 64,
                            color: AppColors.outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No songs yet',
                            style: AppTypography.headlineMedium
                                .copyWith(color: AppColors.onSurface),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add songs to build your playlist',
                            style: AppTypography.bodyMedium
                                .copyWith(color: AppColors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            icon: const Icon(Icons.add, size: 20),
                            label: const Text('Add Songs'),
                            onPressed: () =>
                                showAddSongsToPlaylistSheet(context, playlist),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppRadius.radiusMd,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : SliverReorderableList(
                  itemCount: playlist.tracks.length,
                  onReorder: (oldIndex, newIndex) {
                    ref
                        .read(playlistControllerProvider.notifier)
                        .reorderTracks(playlist.id, oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final track = playlist.tracks[index];
                    final isCurrentTrack =
                        currentPlayingTrackId == track.id;

                    return ReorderableDragStartListener(
                      key: ValueKey(track.id),
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.marginMobile,
                          vertical: 2.0,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SongTile(
                                musicItem: track,
                                title: track.title,
                                artist: track.artist,
                                duration: track.duration,
                                imageUrl: track.imageUrl,
                                isPlaying: isCurrentTrack,
                                onTap: () {
                                  ref
                                      .read(playerControllerProvider.notifier)
                                      .selectTrack(track, playlist.tracks);
                                  context.push('/player');
                                },
                                onLongPress: () =>
                                    showAddToPlaylistSheet(context, track),
                              ),
                            ),
                            // Remove button
                            GestureDetector(
                              onTap: () => _confirmRemove(context, ref, track),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4.0, vertical: 12.0),
                                child: const Icon(
                                  Icons.remove_circle_outline,
                                  color: AppColors.outlineVariant,
                                  size: 20.0,
                                ),
                              ),
                            ),
                            // Drag handle
                            ReorderableDragStartListener(
                              index: index,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 4.0, vertical: 12.0),
                                child: Icon(
                                  Icons.drag_handle,
                                  color: AppColors.outlineVariant,
                                  size: 20.0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 80.0)),
        ],
      ),
    );
  }

  Widget _buildArtwork(PlaylistModel playlist) {
    final artworkUrl = playlist.effectiveCoverUrl;
    final hasArtwork = artworkUrl != null && artworkUrl.isNotEmpty;

    if (hasArtwork) {
      if (artworkUrl.startsWith('http')) {
        return SizedBox.expand(
          child: MieeArtworkImage(
            musicItem: playlist.tracks.isNotEmpty ? playlist.tracks.first : null,
            explicitUrl: artworkUrl,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.zero,
            errorWidget: _defaultArtwork(),
          ),
        );
      } else {
        final localPath = artworkUrl.startsWith('file://')
            ? Uri.parse(artworkUrl).toFilePath()
            : artworkUrl;
        return SizedBox.expand(
          child: Image.file(
            File(localPath),
            fit: BoxFit.cover,
            cacheWidth: 600,
            cacheHeight: 600,
            errorBuilder: (_, __, ___) => _defaultArtwork(),
          ),
        );
      }
    }
    return _defaultArtwork();
  }

  Widget _defaultArtwork() {
    return Container(
      color: AppColors.surfaceContainerHighest,
      child: const Center(
        child: Icon(Icons.queue_music,
            size: 80.0, color: AppColors.onSurfaceVariant),
      ),
    );
  }

  void _showOptionsMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).padding.bottom + 8.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
                  child: Container(
                    width: 36.0,
                    height: 4.0,
                    decoration: BoxDecoration(
                      color: AppColors.outlineVariant,
                      borderRadius: BorderRadius.circular(2.0),
                    ),
                  ),
                ),
                ListTile(
                  leading:
                      const Icon(Icons.playlist_add, color: AppColors.primary),
                  title: const Text('Add Songs'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    showAddSongsToPlaylistSheet(context, playlist);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Rename'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await showCreatePlaylistDialog(
                      context,
                      existingId: playlist.id,
                      initialName: playlist.name,
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: const Text('Duplicate'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    ref
                        .read(playlistControllerProvider.notifier)
                        .duplicatePlaylist(playlist.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Duplicated "${playlist.name}"'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('Change Cover'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickPlaylistCover(context, ref, playlist.id);
                  },
                ),
                if (playlist.customCoverPath != null)
                  ListTile(
                    leading: const Icon(Icons.hide_image_outlined),
                    title: const Text('Remove Custom Cover'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      ref
                          .read(playlistControllerProvider.notifier)
                          .updateCoverPath(playlist.id, null);
                    },
                  ),
                ListTile(
                  leading:
                      const Icon(Icons.delete_outline, color: AppColors.error),
                  title: const Text('Delete',
                      style: TextStyle(color: AppColors.error)),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    final confirmed = await _confirmDelete(context);
                    if (confirmed == true && context.mounted) {
                      await ref
                          .read(playlistControllerProvider.notifier)
                          .deletePlaylist(playlist.id);
                      if (context.mounted) context.pop();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickPlaylistCover(
      BuildContext context, WidgetRef ref, String playlistId) async {
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

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Playlist?'),
        content: Text(
            'Are you sure you want to delete "${playlist.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, MusicItem track) async {
    await ref
        .read(playlistControllerProvider.notifier)
        .removeTrack(playlist.id, track.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${track.title}" removed'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              ref
                  .read(playlistControllerProvider.notifier)
                  .addTrack(playlist.id, track);
            },
          ),
        ),
      );
    }
  }
}
