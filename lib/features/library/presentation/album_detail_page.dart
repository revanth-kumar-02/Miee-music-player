import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../core/audio/providers.dart';
import '../../../core/audio/playback_state.dart';
import '../../media/providers/media_providers.dart';
import '../../media/domain/models.dart';
import '../../../shared/models/track.dart';
import '../../../core/widgets/empty_state.dart';

class AlbumDetailPage extends ConsumerWidget {
  final String albumId;
  const AlbumDetailPage({super.key, required this.albumId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = ref.watch(albumsProvider)
        .where((a) => a.id == albumId)
        .firstOrNull;

    if (album == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const EmptyState(
          title: 'Album not found',
          message: 'The album was not found on your device.',
          icon: Icons.album_outlined,
        ),
      );
    }

    final songs = ref.watch(songsProvider);
    final albumSongs = songs
        .where((s) => s.album.trim().toLowerCase() == album.title.trim().toLowerCase())
        .toList();

    // Map MediaSong to Track
    final trackList = albumSongs.map((song) => Track(
      id: song.id,
      title: song.title,
      artist: song.artist,
      imageUrl: song.artworkPath,
      duration: song.duration,
      filePath: song.filePath,
    )).toList();

    final playbackState = ref.watch(playerControllerProvider);
    final playerController = ref.read(playerControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 280.0,
            pinned: true,
            backgroundColor: AppColors.background,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
              onPressed: () => context.pop(),
              splashRadius: 20.0,
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: album.artworkPath.isNotEmpty
                  ? Image.file(
                      File(album.artworkPath),
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: AppColors.surfaceContainerHigh,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.album,
                        size: 96.0,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.marginMobile),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    style: AppTypography.headlineLargeMobile
                        .copyWith(color: AppColors.onSurface),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  AppSpacing.heightXs,
                  Text(
                    '${album.artist} · ${albumSongs.length} song${albumSongs.length != 1 ? 's' : ''}',
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.onSurfaceVariant),
                  ),
                  AppSpacing.heightMd,

                  // Play / Shuffle
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.play_arrow, size: 20.0),
                          label: Text('Play',
                              style: AppTypography.labelMedium
                                  .copyWith(color: Colors.white)),
                          onPressed: trackList.isEmpty
                              ? null
                              : () {
                                  playerController.setQueue(trackList, startIndex: 0);
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
                          onPressed: trackList.isEmpty
                              ? null
                              : () {
                                  final list = List<Track>.from(trackList)..shuffle();
                                  playerController.setQueue(list, startIndex: 0);
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

          if (trackList.isEmpty)
            const SliverFillRemaining(
              child: EmptyState(
                title: 'No songs',
                message: 'No scanned songs belong to this album.',
                icon: Icons.music_off,
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = trackList[index];
                  final isCurrentTrack =
                      playbackState.currentTrack?.id == track.id;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.marginMobile,
                      vertical: 2.0,
                    ),
                    child: SongTile(
                      title: track.title,
                      artist: track.artist,
                      duration: track.duration,
                      imageUrl: track.imageUrl,
                      isPlaying: isCurrentTrack,
                      onTap: () {
                        playerController.setQueue(trackList, startIndex: index);
                        context.push('/player');
                      },
                    ),
                  );
                },
                childCount: trackList.length,
              ),
            ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 120.0),
          ),
        ],
      ),
    );
  }
}
