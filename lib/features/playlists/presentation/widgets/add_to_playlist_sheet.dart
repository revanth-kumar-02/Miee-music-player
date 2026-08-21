import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../shared/models/track.dart';
import '../../../../shared/models/music_item.dart';
import '../../providers/playlist_providers.dart';
import 'create_playlist_dialog.dart';

/// Shows the "Add to Playlist" bottom sheet for [track].
void showAddToPlaylistSheet(BuildContext context, MusicItem track) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddToPlaylistSheet(track: track),
  );
}

class _AddToPlaylistSheet extends ConsumerWidget {
  final MusicItem track;
  const _AddToPlaylistSheet({required this.track});


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(allPlaylistsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
                child: Container(
                  width: 36.0,
                  height: 4.0,
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant,
                    borderRadius: AppRadius.radiusFull,
                  ),
                ),
              ),

              // Title
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.marginMobile,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Add to Playlist',
                        style: AppTypography.headlineMedium
                            .copyWith(color: AppColors.onSurface),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: AppColors.onSurfaceVariant,
                      onPressed: () => Navigator.of(context).pop(),
                      splashRadius: 20.0,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // List
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  children: [
                    // New Playlist tile
                    ListTile(
                      leading: Container(
                        width: 48.0,
                        height: 48.0,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHighest,
                          borderRadius: AppRadius.radiusMd,
                        ),
                        child: const Icon(Icons.add, color: AppColors.primary),
                      ),
                      title: Text(
                        'New Playlist',
                        style: AppTypography.labelMedium
                            .copyWith(color: AppColors.onSurface),
                      ),
                      onTap: () async {
                        Navigator.of(context).pop();
                        final id = await showCreatePlaylistDialog(context);
                        if (id != null && context.mounted) {
                          await ref
                              .read(playlistControllerProvider.notifier)
                              .addTrack(id, track);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Added to new playlist'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                    ),

                    if (playlists.isNotEmpty) const Divider(height: 8),

                    // Existing playlists
                    ...playlists.map((playlist) {
                      final alreadyIn =
                          playlist.tracks.any((t) => t.id == track.id);
                      return ListTile(
                        leading: Container(
                          width: 48.0,
                          height: 48.0,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHighest,
                            borderRadius: AppRadius.radiusMd,
                          ),
                          child: Icon(
                            Icons.queue_music,
                            color: alreadyIn
                                ? AppColors.primary
                                : AppColors.onSurfaceVariant,
                          ),
                        ),
                        title: Text(
                          playlist.name,
                          style: AppTypography.labelMedium
                              .copyWith(color: AppColors.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${playlist.songCount} songs',
                          style: AppTypography.labelSmall
                              .copyWith(color: AppColors.onSurfaceVariant),
                        ),
                        trailing: alreadyIn
                            ? const Icon(Icons.check_circle,
                                color: AppColors.primary, size: 20.0)
                            : null,
                        onTap: alreadyIn
                            ? null
                            : () async {
                                await ref
                                    .read(playlistControllerProvider.notifier)
                                    .addTrack(playlist.id, track);
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Added to "${playlist.name}"'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
