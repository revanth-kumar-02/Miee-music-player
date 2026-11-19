import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/audio/providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../shared/models/music_item.dart';
import '../../artwork/presentation/miee_artwork_image.dart';
import '../../media/providers/media_providers.dart';
import '../../search/providers/search_providers.dart';
import '../domain/playlist_model.dart';
import '../providers/playlist_providers.dart';
import 'widgets/add_songs_to_playlist_sheet.dart';
import 'widgets/add_to_playlist_sheet.dart';
import 'widgets/create_playlist_dialog.dart';
import 'widgets/playlist_collaboration_sheet.dart';

/// Full-screen Playlist Detail — shows artwork, metadata, natural song list with options,
/// and explicit drag-and-drop reorder mode.
class PlaylistDetailPage extends ConsumerWidget {
  final String playlistId;
  const PlaylistDetailPage({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistState = ref.watch(playlistControllerProvider);
    final playlist = playlistState.playlists
        .where((p) => p.id == playlistId)
        .firstOrNull;

    if (playlist == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/playlists');
              }
            },
            splashRadius: 20.0,
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

class _PlaylistDetailView extends ConsumerStatefulWidget {
  final PlaylistModel playlist;
  const _PlaylistDetailView({required this.playlist});

  @override
  ConsumerState<_PlaylistDetailView> createState() => _PlaylistDetailViewState();
}

class _PlaylistDetailViewState extends ConsumerState<_PlaylistDetailView> {
  bool _isReorderMode = false;
  List<MusicItem>? _workingTracks;

  PlaylistModel get playlist => widget.playlist;

  @override
  void didUpdateWidget(covariant _PlaylistDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isReorderMode) {
      _workingTracks = null;
    }
  }

  void _startReorderMode() {
    setState(() {
      _isReorderMode = true;
      _workingTracks = List<MusicItem>.from(playlist.tracks);
    });
  }

  void _cancelReorderMode() {
    setState(() {
      _isReorderMode = false;
      _workingTracks = null;
    });
  }

  Future<void> _saveReorderMode() async {
    final tracks = _workingTracks;
    if (tracks != null) {
      final trackIds = tracks.map((t) => t.id).toList();
      await ref
          .read(playlistControllerProvider.notifier)
          .updateTrackOrder(playlist.id, trackIds);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Playlist order saved'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
    if (mounted) {
      setState(() {
        _isReorderMode = false;
        _workingTracks = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPlayingTrackId = ref.watch(
      playerControllerProvider.select((s) => s.currentTrack?.id),
    );
    final controller = ref.read(playlistControllerProvider.notifier);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isReorderMode) {
          _cancelReorderMode();
          return;
        }
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/playlists');
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: _isReorderMode
            ? _buildReorderView()
            : _buildNormalView(currentPlayingTrackId, controller),
      ),
    );
  }

  /// Explicit Reorder Mode: clean header, dedicated drag handles, no gesture interference.
  Widget _buildReorderView() {
    final displayTracks = _workingTracks ?? playlist.tracks;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverAppBar(
          pinned: true,
          elevation: 1,
          backgroundColor: AppColors.background,
          leading: IconButton(
            icon: const Icon(Icons.close, color: AppColors.onSurface),
            tooltip: 'Cancel',
            onPressed: _cancelReorderMode,
            splashRadius: 20.0,
          ),
          title: Text(
            'Reorder Songs',
            style: AppTypography.labelLarge.copyWith(
              fontSize: 18.0,
              color: AppColors.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saveReorderMode,
              child: Text(
                'Done',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8.0),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.marginMobile,
              12.0,
              AppSpacing.marginMobile,
              8.0,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.drag_indicator_rounded,
                  size: 16.0,
                  color: AppColors.onSurfaceVariant,
                ),
                const SizedBox(width: 8.0),
                Text(
                  'Drag the handles to rearrange songs',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverReorderableList(
          itemCount: displayTracks.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (oldIndex < newIndex) {
                newIndex -= 1;
              }
              final item = _workingTracks!.removeAt(oldIndex);
              _workingTracks!.insert(newIndex, item);
            });
          },
          itemBuilder: (context, index) {
            final track = displayTracks[index];

            return Padding(
              key: ValueKey('reorder_${track.id}'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.marginMobile,
                vertical: 2.0,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8.0),
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
                        trailingWidget: const SizedBox.shrink(),
                      ),
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 16.0,
                        ),
                        child: Icon(
                          Icons.drag_handle_rounded,
                          color: AppColors.onSurfaceVariant,
                          size: 24.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 80.0)),
      ],
    );
  }

  /// Normal Browsing Mode: natural smooth vertical scroll, no drag handles, clean 3-dot overflow options.
  Widget _buildNormalView(
    String? currentPlayingTrackId,
    PlaylistController controller,
  ) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Sliver App Bar with artwork ─────────────────────────────────────
        SliverAppBar(
          expandedHeight: 280.0,
          pinned: true,
          backgroundColor: AppColors.background,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/playlists');
              }
            },
            splashRadius: 20.0,
          ),
          actions: [
            if (playlist.canEdit)
              IconButton(
                icon: const Icon(Icons.playlist_add, color: AppColors.onSurface),
                tooltip: 'Add Songs',
                onPressed: () => showAddSongsToPlaylistSheet(context, playlist),
                splashRadius: 20.0,
              ),
            IconButton(
              icon: Icon(
                playlist.isCollaborative
                    ? Icons.group_outlined
                    : Icons.person_add_outlined,
                color: AppColors.onSurface,
              ),
              tooltip: 'Collaborate & Share',
              onPressed: () => showPlaylistCollaborationSheet(context, playlist),
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
                Row(
                  children: [
                    Text(
                      '${playlist.songCount} ${playlist.songCount == 1 ? 'song' : 'songs'} · ${playlist.totalDurationFormatted}',
                      style: AppTypography.labelMedium
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                    if (playlist.isCollaborative ||
                        playlist.type == PlaylistType.shared) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: playlist.isCollaborative
                              ? AppColors.primary.withValues(alpha: 0.15)
                              : AppColors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: playlist.isCollaborative
                                ? AppColors.primary.withValues(alpha: 0.4)
                                : AppColors.outlineVariant,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              playlist.isCollaborative
                                  ? Icons.group_outlined
                                  : Icons.share_outlined,
                              size: 13,
                              color: playlist.isCollaborative
                                  ? AppColors.primary
                                  : AppColors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              playlist.isCollaborative
                                  ? 'Collaborative'
                                  : 'Shared',
                              style: AppTypography.labelSmall.copyWith(
                                color: playlist.isCollaborative
                                    ? AppColors.primary
                                    : AppColors.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                if (playlist.description.isNotEmpty) ...[
                  AppSpacing.heightXs,
                  Text(
                    playlist.description,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.onSurfaceVariant),
                  ),
                ],
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
                    if (playlist.canEdit) ...[
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
            : SliverList.builder(
                itemCount: playlist.tracks.length,
                itemBuilder: (context, index) {
                  final track = playlist.tracks[index];
                  final isCurrentTrack = currentPlayingTrackId == track.id;

                  return Padding(
                    key: ValueKey(track.id),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.marginMobile,
                      vertical: 2.0,
                    ),
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
                      onMoreTap: () =>
                          _showTrackOptionsMenu(context, ref, track),
                    ),
                  );
                },
              ),

        // Bottom padding
        const SliverToBoxAdapter(child: SizedBox(height: 80.0)),
      ],
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
        final file = File(artworkUrl);
        if (file.existsSync()) {
          return SizedBox.expand(
            child: Image.file(file, fit: BoxFit.cover),
          );
        }
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

  /// Track-level options bottom sheet exposing all actions supported by the architecture.
  void _showTrackOptionsMenu(
    BuildContext context,
    WidgetRef ref,
    MusicItem track,
  ) {
    showModalBottomSheet<void>(
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
                // Modal Handle
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

                // Track Preview Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.marginMobile,
                    vertical: 8.0,
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6.0),
                        child: MieeArtworkImage(
                          musicItem: track,
                          explicitUrl: track.imageUrl,
                          width: 44.0,
                          height: 44.0,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.displayTitle,
                              style: AppTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2.0),
                            Text(
                              track.artist,
                              style: AppTypography.labelSmall.copyWith(
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
                const Divider(height: 16.0),

                // 1. Play next
                ListTile(
                  leading: const Icon(
                    Icons.playlist_play_rounded,
                    color: AppColors.primary,
                  ),
                  title: const Text('Play next'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await ref
                        .read(playerControllerProvider.notifier)
                        .playNext(track);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Playing "${track.title}" next'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),

                // 2. Add to queue
                ListTile(
                  leading: const Icon(
                    Icons.queue_music_rounded,
                    color: AppColors.primary,
                  ),
                  title: const Text('Add to queue'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await ref
                        .read(playerControllerProvider.notifier)
                        .addTrackToQueue(track);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Added "${track.title}" to queue'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),

                // 3. Add to another playlist
                ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: const Text('Add to another playlist'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    showAddToPlaylistSheet(context, track);
                  },
                ),

                // 4. Remove from this playlist (if canEdit)
                if (playlist.canEdit)
                  ListTile(
                    leading: const Icon(
                      Icons.remove_circle_outline,
                      color: AppColors.error,
                    ),
                    title: const Text(
                      'Remove from this playlist',
                      style: TextStyle(color: AppColors.error),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _confirmRemove(context, ref, track);
                    },
                  ),

                // 5. View album (if album exists)
                if (track.album != null && track.album!.trim().isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.album_outlined),
                    title: Text('View album (${track.album})'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      final albums = ref.read(albumsProvider);
                      final localAlbum = albums
                          .where((a) =>
                              (track.album != null &&
                                  a.title.toLowerCase() ==
                                      track.album!.toLowerCase()) ||
                              a.id == track.album)
                          .firstOrNull;
                      if (localAlbum != null) {
                        context.push('/album/${localAlbum.id}');
                      } else {
                        ref
                            .read(searchNotifierProvider.notifier)
                            .updateQuery(track.album!);
                        context.push('/search');
                      }
                    },
                  ),

                // 6. View artist (if artist exists)
                if (track.artist.trim().isNotEmpty &&
                    track.artist.trim() != 'Unknown')
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text('View artist (${track.artist})'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.push(
                        '/artist/${Uri.encodeComponent(track.artist.trim())}',
                      );
                    },
                  ),

                // 7. Share track
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('Share track'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    final shareUrl = track.isYoutube
                        ? 'https://www.youtube.com/watch?v=${track.id.replaceFirst('youtube_', '')}'
                        : null;
                    final shareText = shareUrl != null
                        ? 'Listen to "${track.title}" by ${track.artist} on Miee:\n$shareUrl'
                        : 'Listen to "${track.title}" by ${track.artist} on Miee';
                    SharePlus.instance.share(
                      ShareParams(
                        text: shareText,
                        subject: track.title,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showOptionsMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
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
                      const Icon(Icons.group_outlined, color: AppColors.primary),
                  title: const Text('Collaboration & Sharing'),
                  subtitle: Text(
                    playlist.isCollaborative
                        ? 'Collaborative · ${playlist.role.name.toUpperCase()}'
                        : 'Private',
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    showPlaylistCollaborationSheet(context, playlist);
                  },
                ),
                if (playlist.canEdit)
                  ListTile(
                    leading:
                        const Icon(Icons.playlist_add, color: AppColors.primary),
                    title: const Text('Add Songs'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      showAddSongsToPlaylistSheet(context, playlist);
                    },
                  ),
                if (playlist.canEdit && playlist.tracks.length > 1)
                  ListTile(
                    leading: const Icon(
                      Icons.swap_vert_rounded,
                      color: AppColors.primary,
                    ),
                    title: const Text('Reorder Songs'),
                    subtitle: const Text('Rearrange track sequence'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _startReorderMode();
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
