import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/audio/providers.dart';
import '../../../shared/models/track.dart';
import '../../media/domain/models.dart';
import '../../media/providers/media_providers.dart';
import '../../library/providers/library_providers.dart';
import '../domain/playlist_model.dart';
import '../providers/playlist_providers.dart';
import 'widgets/create_playlist_dialog.dart';

/// Recreated "Your Library" screen matching the reference design:
/// - Cocoa Plum sidebar + Vanilla Cream canvas
/// - "Your Library" serif heading with Search and "Recently Added ∨" sort pill
/// - Filter chips: Playlists (selected in Dusty Rose), Artists, Albums, Songs
/// - Grid Cards: Liked Songs (Dusty Rose card with white heart), Chill Vibes, Focus, + Create Playlist
/// - Structured list table: Name, Type, Added, options menu
class PlaylistsPage extends ConsumerStatefulWidget {
  const PlaylistsPage({super.key});

  @override
  ConsumerState<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends ConsumerState<PlaylistsPage> {
  String _selectedFilter = 'Playlists';
  final String _sortOption = 'Recently Added';

  final List<String> _filters = const [
    'Playlists',
    'Artists',
    'Albums',
    'Songs',
  ];

  void _showPlaylistOptions(
      BuildContext context, WidgetRef ref, PlaylistModel playlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
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
                style: GoogleFonts.playfairDisplay(
                  fontSize: 18,
                  color: AppColors.cocoaPlum,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(color: AppColors.oatBeige),
            ListTile(
              leading:
                  const Icon(Icons.edit_outlined, color: AppColors.cocoaPlum),
              title: Text('Rename Playlist',
                  style: GoogleFonts.geist(color: AppColors.cocoaPlum)),
              onTap: () {
                Navigator.pop(context);
                showCreatePlaylistDialog(
                  context,
                  existingId: playlist.id,
                  initialName: playlist.name,
                );
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.image_outlined, color: AppColors.cocoaPlum),
              title: Text('Change Cover',
                  style: GoogleFonts.geist(color: AppColors.cocoaPlum)),
              onTap: () {
                Navigator.pop(context);
                _pickPlaylistCover(context, ref, playlist.id);
              },
            ),
            if (playlist.customCoverPath != null)
              ListTile(
                leading: const Icon(Icons.hide_image_outlined,
                    color: AppColors.mutedMauve),
                title: Text('Remove Custom Cover',
                    style: GoogleFonts.geist(color: AppColors.mutedMauve)),
                onTap: () {
                  Navigator.pop(context);
                  ref
                      .read(playlistControllerProvider.notifier)
                      .updateCoverPath(playlist.id, null);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text('Delete Playlist',
                  style: GoogleFonts.geist(color: Colors.red)),
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

  void _confirmDelete(
      BuildContext context, WidgetRef ref, PlaylistModel playlist) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.oatBeige),
        ),
        title: Text('Delete Playlist',
            style: GoogleFonts.playfairDisplay(
                fontWeight: FontWeight.bold, color: AppColors.cocoaPlum)),
        content: Text(
          'Are you sure you want to delete "${playlist.name}"? This action cannot be undone.',
          style: GoogleFonts.geist(color: AppColors.mutedMauve),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.geist(color: AppColors.mutedMauve)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref
                  .read(playlistControllerProvider.notifier)
                  .deletePlaylist(playlist.id);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(allPlaylistsProvider);
    final favorites = ref.watch(favoritesProvider);
    final localSongs = ref.watch(songsProvider);
    final localArtists = ref.watch(artistsProvider);
    final localAlbums = ref.watch(albumsProvider);

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 960;

    return Scaffold(
      backgroundColor: AppColors.vanillaCream,
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 28.0 : AppSpacing.marginMobile,
          vertical: 12.0,
        ),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Header Row: "Your Library" + Search + Sort ──
            Row(
              children: [
                Text(
                  'Your Library',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                const Spacer(),

                // Search Icon Button
                IconButton(
                  icon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.cocoaPlum,
                    size: 22,
                  ),
                  onPressed: () => context.go('/search'),
                ),

                const SizedBox(width: 8),

                // "Recently Added ∨" Dropdown Pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.oatBeige),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _sortOption,
                        style: GoogleFonts.geist(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.cocoaPlum,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AppColors.cocoaPlum,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Filter Pills: Playlists, Artists, Albums, Songs ──
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final f = _filters[index];
                  final isSelected = _selectedFilter == f;

                  return InkWell(
                    onTap: () {
                      setState(() => _selectedFilter = f);
                    },
                    borderRadius: BorderRadius.circular(17),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.dustyRose
                            : AppColors.white,
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.dustyRose
                              : AppColors.oatBeige,
                          width: 1.0,
                        ),
                      ),
                      child: Text(
                        f,
                        style: GoogleFonts.geist(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? AppColors.white
                              : AppColors.cocoaPlum,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // ── Grid Cards: Liked Songs, User Playlists, + Create Playlist ──
            _buildGridCardsRow(context, playlists, favorites),

            const SizedBox(height: 32),

            // ── Structured Table: Name, Type, Added, Options ──
            _buildStructuredTable(
              context,
              playlists,
              localSongs,
              localArtists,
              localAlbums,
              favorites,
            ),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  // ── GRID CARDS ROW ─────────────────────────────────────────────────────────

  Widget _buildGridCardsRow(
    BuildContext context,
    List<PlaylistModel> playlists,
    List<Track> favorites,
  ) {
    return SizedBox(
      height: 180,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          // 1. Liked Songs Card (Solid Dusty Rose with white heart)
          InkWell(
            onTap: () => context.push('/liked-songs'),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 146,
              height: 180,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.dustyRose,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.dustyRose.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Icon(
                        Icons.favorite_rounded,
                        size: 44,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Liked Songs',
                        style: GoogleFonts.geist(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${favorites.length} songs',
                        style: GoogleFonts.geist(
                          fontSize: 11.5,
                          color: AppColors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Real User Playlists
          for (final playlist in playlists) ...[
            _buildCoverCard(
              title: playlist.name,
              subtitle: '${playlist.songCount} songs',
              imageUrl: playlist.effectiveCoverUrl,
              onTap: () => context.push('/playlist/${playlist.id}'),
            ),
            const SizedBox(width: 14),
          ],

          // "+ Create Playlist" Card
          InkWell(
            onTap: () => showCreatePlaylistDialog(context),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 146,
              height: 180,
              decoration: BoxDecoration(
                color: AppColors.white.withOpacity(0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.oatBeige,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.softClay.withOpacity(0.4),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 26,
                      color: AppColors.cocoaPlum,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Create Playlist',
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
        ],
      ),
    );
  }

  Widget _buildCoverCard({
    required String title,
    required String subtitle,
    String? imageUrl,
    required VoidCallback onTap,
  }) {
    final hasImage = imageUrl != null && imageUrl.trim().isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 146,
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.oatBeige),
          color: AppColors.softClay.withOpacity(0.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasImage)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildFallbackCover(),
              )
            else
              _buildFallbackCover(),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.cocoaPlum.withOpacity(0.85),
                  ],
                  stops: const [0.4, 1.0],
                ),
              ),
              padding: const EdgeInsets.all(12),
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.geist(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.white,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.geist(
                      fontSize: 11,
                      color: AppColors.softClay,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackCover() {
    return Container(
      color: AppColors.cocoaPlum,
      alignment: Alignment.center,
      child: const Icon(
        Icons.music_note_rounded,
        size: 40,
        color: AppColors.softClay,
      ),
    );
  }

  // ── STRUCTURED TABLE (Name, Type, Added) ───────────────────────────────────

  Widget _buildStructuredTable(
    BuildContext context,
    List<PlaylistModel> playlists,
    List<MediaSong> songs,
    List<MediaArtist> artists,
    List<MediaAlbum> albums,
    List<Track> favorites,
  ) {
    final List<Map<String, dynamic>> rows = [];

    if (_selectedFilter == 'Playlists') {
      rows.add({
        'title': 'Liked Songs',
        'type': 'Playlist',
        'added': '${favorites.length} songs',
        'image': null,
        'item': null,
        'isLikedSongs': true,
      });
      for (final p in playlists) {
        rows.add({
          'title': p.name,
          'type': 'Playlist',
          'added': '${p.songCount} songs',
          'image': p.effectiveCoverUrl,
          'item': p,
          'isLikedSongs': false,
        });
      }
    } else if (_selectedFilter == 'Artists') {
      for (final a in artists) {
        rows.add({
          'title': a.name,
          'type': 'Artist',
          'added': '${a.trackCount} songs',
          'image': a.artworkPath,
          'item': a,
          'isLikedSongs': false,
        });
      }
    } else if (_selectedFilter == 'Albums') {
      for (final al in albums) {
        rows.add({
          'title': al.title,
          'type': 'Album',
          'added': '${al.trackCount} tracks',
          'image': al.artworkPath,
          'item': al,
          'isLikedSongs': false,
        });
      }
    } else if (_selectedFilter == 'Songs') {
      for (final s in songs) {
        rows.add({
          'title': s.title,
          'type': 'Song',
          'added': s.artist,
          'image': s.artworkPath,
          'item': s,
          'isLikedSongs': false,
        });
      }
      if (rows.isEmpty) {
        for (final f in favorites) {
          rows.add({
            'title': f.title,
            'type': 'Song',
            'added': f.artist,
            'image': f.imageUrl,
            'item': f,
            'isLikedSongs': false,
          });
        }
      }
    }

    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        alignment: Alignment.center,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.softClay.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.library_music_rounded,
                color: AppColors.cocoaPlum,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No ${_selectedFilter.toLowerCase()} found',
              style: GoogleFonts.playfairDisplay(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.cocoaPlum,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _selectedFilter == 'Playlists'
                  ? 'Create your first playlist using the card above.'
                  : 'Explore search or home to discover music for your library.',
              textAlign: TextAlign.center,
              style: GoogleFonts.geist(
                fontSize: 13,
                color: AppColors.mutedMauve,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Table Headers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Text(
                  'Name',
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedMauve,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Type',
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedMauve,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Added',
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedMauve,
                  ),
                ),
              ),
              const SizedBox(width: 32),
            ],
          ),
        ),
        const Divider(color: AppColors.oatBeige, height: 1),

        // Rows
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rows.length,
          separatorBuilder: (_, __) =>
              const Divider(color: AppColors.oatBeige, height: 1),
          itemBuilder: (context, index) {
            final row = rows[index];
            final title = row['title'] as String;
            final type = row['type'] as String;
            final added = row['added'] as String;
            final img = row['image'] as String?;
            final item = row['item'];
            final isLikedSongs = row['isLikedSongs'] as bool? ?? false;

            return InkWell(
              onTap: () {
                if (isLikedSongs) {
                  context.push('/liked-songs');
                } else if (item is PlaylistModel) {
                  context.push('/playlist/${item.id}');
                } else if (item is MediaSong) {
                  ref
                      .read(playerControllerProvider.notifier)
                      .selectTrack(item, songs, playingFrom: 'Your Library');
                } else if (item is Track) {
                  ref
                      .read(playerControllerProvider.notifier)
                      .selectTrack(item, favorites, playingFrom: 'Liked Songs');
                } else if (item is MediaArtist) {
                  context.push('/search');
                } else if (item is MediaAlbum) {
                  context.push('/search');
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    // Artwork Thumbnail + Name
                    Expanded(
                      flex: 5,
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: isLikedSongs
                                ? Container(
                                    width: 36,
                                    height: 36,
                                    color: AppColors.dustyRose,
                                    child: const Icon(
                                      Icons.favorite_rounded,
                                      size: 18,
                                      color: AppColors.white,
                                    ),
                                  )
                                : (img != null && img.isNotEmpty)
                                    ? Image.network(
                                        img,
                                        width: 36,
                                        height: 36,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          width: 36,
                                          height: 36,
                                          color: AppColors.softClay,
                                          child: const Icon(
                                            Icons.music_note_rounded,
                                            size: 18,
                                            color: AppColors.cocoaPlum,
                                          ),
                                        ),
                                      )
                                    : Container(
                                        width: 36,
                                        height: 36,
                                        color: AppColors.softClay,
                                        child: const Icon(
                                          Icons.music_note_rounded,
                                          size: 18,
                                          color: AppColors.cocoaPlum,
                                        ),
                                      ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.geist(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.cocoaPlum,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Type
                    Expanded(
                      flex: 3,
                      child: Text(
                        type,
                        style: GoogleFonts.geist(
                          fontSize: 12.5,
                          color: AppColors.mutedMauve,
                        ),
                      ),
                    ),

                    // Added
                    Expanded(
                      flex: 3,
                      child: Text(
                        added,
                        style: GoogleFonts.geist(
                          fontSize: 12.5,
                          color: AppColors.mutedMauve,
                        ),
                      ),
                    ),

                    // Three dots options
                    if (item is PlaylistModel)
                      IconButton(
                        icon: const Icon(
                          Icons.more_vert_rounded,
                          size: 18,
                          color: AppColors.mutedMauve,
                        ),
                        onPressed: () {
                          _showPlaylistOptions(context, ref, item);
                        },
                      )
                    else
                      const SizedBox(width: 40),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
