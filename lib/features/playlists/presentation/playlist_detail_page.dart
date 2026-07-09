import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/audio/providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../shared/models/track.dart';
import '../../../shared/models/music_item.dart';
import '../domain/playlist_model.dart';
import '../providers/playlist_providers.dart';
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
    final playbackState = ref.watch(playerControllerProvider);
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
                    '${playlist.songCount} songs · ${playlist.totalDurationFormatted}',
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.onSurfaceVariant),
                  ),
                  AppSpacing.heightMd,

                  // ── Play / Shuffle buttons ──────────────────────────────────
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
                      AppSpacing.widthMd,
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
                    ],
                  ),
                  AppSpacing.heightMd,
                ],
              ),
            ),
          ),

          // ── Song list ───────────────────────────────────────────────────────
          playlist.isEmpty
              ? const SliverFillRemaining(
                  child: EmptyState(
                    title: 'No songs yet',
                    message: 'Long-press any song and choose "Add to Playlist".',
                    icon: Icons.music_off,
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
                        playbackState.currentTrack?.id == track.id;

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
    final artworkUrl = playlist.artworkTrack?.imageUrl;
    final hasArtwork = artworkUrl != null && artworkUrl.isNotEmpty;

    if (hasArtwork) {
      return SizedBox.expand(
        child: artworkUrl.startsWith('http')
            ? Image.network(artworkUrl, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _defaultArtwork())
            : Image.file(File(artworkUrl), fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _defaultArtwork()),
      );
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
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      builder: (_) => SafeArea(
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
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.of(context).pop();
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
                Navigator.of(context).pop();
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
              leading:
                  const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('Delete',
                  style: TextStyle(color: AppColors.error)),
              onTap: () async {
                Navigator.of(context).pop();
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
    );
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
