import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/audio/playback_state.dart' as pb;
import '../../../core/audio/providers.dart';
import '../../../shared/models/track.dart';
import '../../library/providers/library_providers.dart';
import 'widgets/add_to_playlist_sheet.dart';

/// Full Liked Songs Screen backed by the real persisted [favoritesProvider].
/// Adheres strictly to the Vanilla Cream, Cocoa Plum, Dusty Rose, and Soft Clay design system.
class LikedSongsPage extends ConsumerStatefulWidget {
  const LikedSongsPage({super.key});

  @override
  ConsumerState<LikedSongsPage> createState() => _LikedSongsPageState();
}

class _LikedSongsPageState extends ConsumerState<LikedSongsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritesProvider);
    final activePlayingTrackId = ref.watch(
      playerControllerProvider.select((s) =>
          s.status == pb.PlaybackStatus.playing ? s.currentTrack?.id : null),
    );
    final isDesktop = MediaQuery.of(context).size.width >= 960;

    final filteredTracks = favorites.where((t) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.vanillaCream,
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 28.0 : AppSpacing.marginMobile,
          vertical: 16.0,
        ),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Header Row with Back Button ──
            Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: AppColors.cocoaPlum,
                    size: 24,
                  ),
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/playlists');
                    }
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  'Liked Songs',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.oatBeige),
                  ),
                  child: Text(
                    '${favorites.length} ${favorites.length == 1 ? "song" : "songs"}',
                    style: GoogleFonts.geist(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedMauve,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Editorial Banner Card (Solid Dusty Rose) ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.dustyRose,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.dustyRose.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: AppColors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.favorite_rounded,
                      size: 38,
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Favorites',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          favorites.isEmpty
                              ? 'Songs you like will appear here for easy listening.'
                              : 'All your favorite songs gathered in one place.',
                          style: GoogleFonts.geist(
                            fontSize: 13,
                            color: AppColors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Action Buttons: Play All + Shuffle + Search ──
            if (favorites.isNotEmpty) ...[
              Row(
                children: [
                  // Play All Button
                  Material(
                    color: AppColors.dustyRose,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        if (favorites.isEmpty) return;
                        ref
                            .read(playerControllerProvider.notifier)
                            .selectTrack(
                              favorites.first,
                              favorites,
                              playingFrom: 'Liked Songs',
                            );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.play_arrow_rounded,
                              size: 20,
                              color: AppColors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Play All',
                              style: GoogleFonts.geist(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Shuffle Button
                  Material(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        if (favorites.isEmpty) return;
                        final shuffled = List<Track>.from(favorites)..shuffle();
                        ref
                            .read(playerControllerProvider.notifier)
                            .selectTrack(
                              shuffled.first,
                              shuffled,
                              playingFrom: 'Liked Songs',
                            );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.oatBeige),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.shuffle_rounded,
                              size: 18,
                              color: AppColors.cocoaPlum,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Shuffle',
                              style: GoogleFonts.geist(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.cocoaPlum,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Search within liked songs
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.oatBeige),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val),
                        style: GoogleFonts.geist(
                          fontSize: 13,
                          color: AppColors.cocoaPlum,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search liked songs...',
                          hintStyle: GoogleFonts.geist(
                            fontSize: 12,
                            color: AppColors.mutedMauve,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: AppColors.mutedMauve,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    size: 16,
                                    color: AppColors.mutedMauve,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],

            // ── Track List or Empty State ──
            if (favorites.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.softClay.withOpacity(0.4),
                      ),
                      child: const Icon(
                        Icons.favorite_border_rounded,
                        size: 36,
                        color: AppColors.mutedMauve,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No liked songs yet',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.cocoaPlum,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap the heart icon on any song while listening or browsing to save it here.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.geist(
                        fontSize: 13,
                        color: AppColors.mutedMauve,
                      ),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/search'),
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: Text(
                        'Discover Music',
                        style: GoogleFonts.geist(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.cocoaPlum,
                        side: const BorderSide(color: AppColors.oatBeige),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (filteredTracks.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40),
                alignment: Alignment.center,
                child: Text(
                  'No liked songs matching "$_searchQuery"',
                  style: GoogleFonts.geist(
                    fontSize: 13,
                    color: AppColors.mutedMauve,
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredTracks.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: AppColors.oatBeige, height: 1),
                itemBuilder: (context, index) {
                  final track = filteredTracks[index];
                  final isPlaying = activePlayingTrackId == track.id;

                  return InkWell(
                    onTap: () {
                      ref
                          .read(playerControllerProvider.notifier)
                          .selectTrack(
                            track,
                            filteredTracks,
                            playingFrom: 'Liked Songs',
                          );
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          // Track index / Play indicator
                          SizedBox(
                            width: 28,
                            child: isPlaying
                                ? const Icon(
                                    Icons.equalizer_rounded,
                                    size: 18,
                                    color: AppColors.dustyRose,
                                  )
                                : Text(
                                    '${index + 1}',
                                    style: GoogleFonts.geist(
                                      fontSize: 12,
                                      color: AppColors.mutedMauve,
                                    ),
                                  ),
                          ),

                          // Artwork
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: track.imageUrl.startsWith('http')
                                ? Image.network(
                                    track.imageUrl,
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    cacheWidth: 88,
                                    cacheHeight: 88,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 44,
                                      height: 44,
                                      color: AppColors.softClay,
                                      child: const Icon(
                                        Icons.music_note_rounded,
                                        size: 22,
                                        color: AppColors.cocoaPlum,
                                      ),
                                    ),
                                  )
                                : Image.file(
                                    File(track.imageUrl.startsWith('file://')
                                        ? Uri.parse(track.imageUrl).toFilePath()
                                        : track.imageUrl),
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    cacheWidth: 88,
                                    cacheHeight: 88,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 44,
                                      height: 44,
                                      color: AppColors.softClay,
                                      child: const Icon(
                                        Icons.music_note_rounded,
                                        size: 22,
                                        color: AppColors.cocoaPlum,
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 14),

                          // Title & Artist
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.geist(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isPlaying
                                        ? AppColors.dustyRose
                                        : AppColors.cocoaPlum,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.geist(
                                    fontSize: 12,
                                    color: AppColors.mutedMauve,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Duration
                          Text(
                            track.duration,
                            style: GoogleFonts.geist(
                              fontSize: 12,
                              color: AppColors.mutedMauve,
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Unlike action
                          IconButton(
                            icon: const Icon(
                              Icons.favorite_rounded,
                              size: 20,
                              color: AppColors.dustyRose,
                            ),
                            splashRadius: 18,
                            onPressed: () {
                              ref
                                  .read(favoritesProvider.notifier)
                                  .removeFavorite(track.id);
                            },
                          ),

                          // Overflow menu
                          IconButton(
                            icon: const Icon(
                              Icons.more_vert_rounded,
                              size: 18,
                              color: AppColors.mutedMauve,
                            ),
                            splashRadius: 18,
                            onPressed: () {
                              showAddToPlaylistSheet(context, track);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
