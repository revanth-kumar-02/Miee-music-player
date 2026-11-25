import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/midnight_velvet_tokens.dart';
import '../../../../core/audio/providers.dart';
import '../../../../features/media/providers/media_providers.dart';
import '../../../artwork/presentation/miee_artwork_image.dart';

/// The Desktop "Master Albums" view.
/// Shows albums collection in an audiophile vinyl slipcase grid
/// strictly adhering to Midnight Velvet design tokens.
class DesktopMasterAlbumsView extends ConsumerWidget {
  const DesktopMasterAlbumsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);
    final songs = ref.watch(songsProvider);

    return Scaffold(
      backgroundColor: MidnightVelvetTokens.canvasBase,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Studio Header ─────────────────────────────────────────
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MASTER ALBUMS',
                      style: MidnightVelvetTokens.fontDisplayLarge.copyWith(
                        fontSize: 26,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${albums.length} Complete album master editions discovered',
                      style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                        color: MidnightVelvetTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 28),

            // ── Albums Grid ───────────────────────────────────────────
            if (albums.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.album_outlined,
                        size: 48,
                        color: MidnightVelvetTokens.textMuted,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Master Albums Discovered',
                        style: MidnightVelvetTokens.fontSectionTitle,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Add music directories in Studio Catalog to scan album pressings.',
                        style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                          color: MidnightVelvetTokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 24,
                  childAspectRatio: 0.76,
                ),
                itemCount: albums.length,
                itemBuilder: (context, index) {
                  final album = albums[index];
                  final albumSongs =
                      songs.where((s) => s.album == album.title).toList();

                  return InkWell(
                    onTap: () {
                      if (albumSongs.isNotEmpty) {
                        ref.read(playerControllerProvider.notifier).setQueue(
                              albumSongs,
                              startIndex: 0,
                              playingFrom: 'Album: ${album.title}',
                            );
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: MidnightVelvetTokens.surfaceCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: MidnightVelvetTokens.hairlineRim,
                          width: 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                color: MidnightVelvetTokens.surfaceElevated,
                                width: double.infinity,
                                child: album.artworkPath.isNotEmpty
                                    ? MieeArtworkImage(
                                        explicitUrl: album.artworkPath,
                                        fit: BoxFit.cover,
                                      )
                                    : const Center(
                                        child: Icon(
                                          Icons.album_rounded,
                                          size: 40,
                                          color: MidnightVelvetTokens
                                              .amberChampagne,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            album.title,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: MidnightVelvetTokens.textDisplay,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            album.artist,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: MidnightVelvetTokens.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${album.trackCount} Tracks',
                            style:
                                MidnightVelvetTokens.fontMonoTelemetry.copyWith(
                              fontSize: 10,
                              color: MidnightVelvetTokens.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
