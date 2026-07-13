import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../core/audio/providers.dart';
import '../../media/providers/media_providers.dart';
import '../../media/domain/models.dart';
import '../../../core/widgets/empty_state.dart';

final genreSongsProvider = FutureProvider.family<List<MediaSong>, String>((ref, genreId) async {
  final songs = ref.watch(songsProvider);
  final audioQuery = OnAudioQuery();
  
  try {
    final rawSongs = await audioQuery.queryAudiosFrom(
      AudiosFromType.GENRE_ID,
      int.parse(genreId),
    );
    
    // Intersect with active songs (which are already filtered for unknown artists)
    return rawSongs
        .map((rawSong) => songs.where((s) => s.id == rawSong.id.toString()).firstOrNull)
        .whereType<MediaSong>()
        .toList();
  } catch (_) {
    return [];
  }
});

class GenreDetailPage extends ConsumerWidget {
  final String genreId;
  const GenreDetailPage({super.key, required this.genreId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genre = ref.watch(genresProvider)
        .where((g) => g.id == genreId)
        .firstOrNull;

    if (genre == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const EmptyState(
          title: 'Genre not found',
          message: 'The genre was not found on your device.',
          icon: Icons.music_note_outlined,
        ),
      );
    }

    final songsAsync = ref.watch(genreSongsProvider(genreId));
    final playbackState = ref.watch(playerControllerProvider);
    final playerController = ref.read(playerControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0.0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => context.pop(),
        ),
        title: Text(
          genre.name,
          style: AppTypography.headlineMedium.copyWith(
            color: AppColors.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: songsAsync.when(
        data: (genreSongs) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.marginMobile,
                  vertical: AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${genreSongs.length} song${genreSongs.length != 1 ? 's' : ''}',
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
                            onPressed: genreSongs.isEmpty
                                ? null
                                : () {
                                    playerController.setQueue(genreSongs, startIndex: 0);
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
                            onPressed: genreSongs.isEmpty
                                ? null
                                : () {
                                    final list = List<MediaSong>.from(genreSongs)..shuffle();
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
                  ],
                ),
              ),

              Expanded(
                child: genreSongs.isEmpty
                    ? const EmptyState(
                        title: 'No songs',
                        message: 'No scanned songs belong to this genre.',
                        icon: Icons.music_off,
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 120.0),
                        itemCount: genreSongs.length,
                        itemBuilder: (context, index) {
                          final track = genreSongs[index];
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
                                playerController.setQueue(genreSongs, startIndex: index);
                                context.push('/player');
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (e, __) => EmptyState(
          title: 'Error loading songs',
          message: e.toString(),
          icon: Icons.error_outline,
        ),
      ),
    );
  }
}
