import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/midnight_velvet_tokens.dart';
import '../../../../core/audio/playback_state.dart';
import '../../../../core/audio/player_controller.dart';
import '../../../../core/audio/providers.dart';
import '../../../../features/artwork/presentation/miee_artwork_image.dart';
import '../../../../features/media/domain/models.dart';
import '../../../../features/media/providers/media_providers.dart';

enum CatalogTab {
  tracks,
  albums,
  artists,
  folders,
}

class DesktopLocalLibraryView extends ConsumerStatefulWidget {
  const DesktopLocalLibraryView({super.key});

  @override
  ConsumerState<DesktopLocalLibraryView> createState() =>
      _DesktopLocalLibraryViewState();
}

class _DesktopLocalLibraryViewState
    extends ConsumerState<DesktopLocalLibraryView> {
  CatalogTab _activeTab = CatalogTab.tracks;
  final TextEditingController _filterController = TextEditingController();
  String _filterQuery = '';
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _filterController.addListener(() {
      setState(() {
        _filterQuery = _filterController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _showAddFolderDialog(BuildContext context) {
    final folderController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: MidnightVelvetTokens.canvasBase,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(
                color: MidnightVelvetTokens.hairlineRimHighlight),
          ),
          title: Text(
            'ADD LOCAL MUSIC FOLDER',
            style: MidnightVelvetTokens.fontSectionTitle.copyWith(
              fontSize: 16,
              letterSpacing: 0.05 * 16,
            ),
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter the absolute path to a folder containing audio files on this machine:',
                  style: MidnightVelvetTokens.fontBodyMedium
                      .copyWith(fontSize: 13),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: MidnightVelvetTokens.surfaceCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: MidnightVelvetTokens.hairlineRim),
                  ),
                  child: TextField(
                    controller: folderController,
                    style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                      color: MidnightVelvetTokens.textDisplay,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: Platform.isWindows
                          ? r'e.g. C:\Users\Username\Music'
                          : 'e.g. /home/username/Music',
                      hintStyle: MidnightVelvetTokens.fontBodyMedium.copyWith(
                        color: MidnightVelvetTokens.textMuted,
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'CANCEL',
                style: MidnightVelvetTokens.fontLabelSmall.copyWith(
                  color: MidnightVelvetTokens.textMuted,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: MidnightVelvetTokens.primaryEmber,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final input = folderController.text.trim();
                if (input.isNotEmpty) {
                  Navigator.of(ctx).pop();
                  await ref
                      .read(mediaLibraryServiceProvider.notifier)
                      .includeFolder(input);
                }
              },
              child: Text(
                'ADD & SCAN',
                style: MidnightVelvetTokens.fontLabelSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final songs = ref.watch(songsProvider);
    final albums = ref.watch(albumsProvider);
    final artists = ref.watch(artistsProvider);
    final folders = ref.watch(foldersProvider);
    final isLoading = ref.watch(loadingStateProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final currentTrack =
        ref.watch(playerControllerProvider.select((s) => s.currentTrack));
    final isPlaying = ref.watch(playerControllerProvider
        .select((s) => s.status == PlaybackStatus.playing));

    final filteredSongs = _filterQuery.isEmpty
        ? songs
        : songs.where((s) {
            return s.title.toLowerCase().contains(_filterQuery) ||
                s.artist.toLowerCase().contains(_filterQuery) ||
                s.album.toLowerCase().contains(_filterQuery);
          }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Studio Header & Action Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Text(
                            'STUDIO CATALOG',
                            style:
                                MidnightVelvetTokens.fontDisplayMedium.copyWith(
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: MidnightVelvetTokens.surfaceCard,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: MidnightVelvetTokens.hairlineRim),
                            ),
                            child: Text(
                              '${songs.length} TRACKS • ${albums.length} ALBUMS',
                              style: MidnightVelvetTokens.fontMonoTelemetry
                                  .copyWith(
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Direct host storage audio repository & bit-perfect playback',
                      style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                        color: MidnightVelvetTokens.textSecondary,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Action Buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Rescan Button
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MidnightVelvetTokens.textDisplay,
                      side: const BorderSide(
                          color: MidnightVelvetTokens.hairlineRim),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                    onPressed: isLoading
                        ? null
                        : () => ref
                            .read(mediaLibraryServiceProvider.notifier)
                            .scanDevice(forceRefresh: true),
                    icon: isLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: MidnightVelvetTokens.amberChampagne,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(
                      'RESCAN',
                      style: MidnightVelvetTokens.fontLabelSmall.copyWith(
                        letterSpacing: 0.06 * 11,
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Add Folder Button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MidnightVelvetTokens.primaryEmber,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                    onPressed: () => _showAddFolderDialog(context),
                    icon: const Icon(Icons.folder_open_rounded,
                        size: 16, color: Colors.white),
                    label: Text(
                      'ADD MUSIC FOLDER',
                      style: MidnightVelvetTokens.fontLabelSmall.copyWith(
                        color: Colors.white,
                        letterSpacing: 0.06 * 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 2. Navigation Tabs & Quick Filter
          Row(
            children: [
              // Tabs (horizontal scrollable)
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildTabPill(
                          'TRACKS (${songs.length})', CatalogTab.tracks),
                      const SizedBox(width: 8),
                      _buildTabPill(
                          'ALBUMS (${albums.length})', CatalogTab.albums),
                      const SizedBox(width: 8),
                      _buildTabPill(
                          'ARTISTS (${artists.length})', CatalogTab.artists),
                      const SizedBox(width: 8),
                      _buildTabPill(
                          'FOLDERS (${folders.length})', CatalogTab.folders),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Filter Input
              Container(
                width: 180,
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: MidnightVelvetTokens.surfaceCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: MidnightVelvetTokens.hairlineRim),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.filter_list_rounded,
                      size: 16,
                      color: MidnightVelvetTokens.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _filterController,
                        style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                          fontSize: 12,
                          color: MidnightVelvetTokens.textDisplay,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Filter catalog...',
                          hintStyle:
                              MidnightVelvetTokens.fontBodyMedium.copyWith(
                            fontSize: 12,
                            color: MidnightVelvetTokens.textMuted,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_filterQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () => _filterController.clear(),
                        child: const Icon(
                          Icons.clear_rounded,
                          size: 14,
                          color: MidnightVelvetTokens.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 3. Main Catalog Stage (Table or Grid)
          Expanded(
            child: Container(
              decoration: MidnightVelvetTokens.glassPanel(
                radius: 12.0,
                surfaceColor: MidnightVelvetTokens.surfaceCard,
              ),
              child: _activeTab == CatalogTab.tracks
                  ? _buildTracksTable(
                      filteredSongs, currentTrack, isPlaying, controller)
                  : _activeTab == CatalogTab.albums
                      ? _buildAlbumsGrid(albums, controller)
                      : _activeTab == CatalogTab.artists
                          ? _buildArtistsGrid(artists)
                          : _buildFoldersList(folders),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPill(String title, CatalogTab tab) {
    final isSelected = _activeTab == tab;

    return InkWell(
      onTap: () => setState(() => _activeTab = tab),
      borderRadius: BorderRadius.circular(8),
      hoverColor: MidnightVelvetTokens.surfaceCardHover,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? MidnightVelvetTokens.surfaceElevated
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(
                  color: MidnightVelvetTokens.hairlineRimHighlight, width: 1.0)
              : null,
        ),
        child: Text(
          title,
          style: MidnightVelvetTokens.fontLabelSmall.copyWith(
            fontSize: 11,
            color: isSelected
                ? MidnightVelvetTokens.textDisplay
                : MidnightVelvetTokens.textMuted,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildTracksTable(
    List<MediaSong> songs,
    dynamic currentTrack,
    bool isPlaying,
    PlayerController controller,
  ) {
    if (songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.music_off_rounded,
              size: 48,
              color: MidnightVelvetTokens.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'NO LOCAL TRACKS FOUND',
              style: MidnightVelvetTokens.fontSectionTitle.copyWith(
                fontSize: 14,
                letterSpacing: 0.05 * 14,
                color: MidnightVelvetTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add your PC music folder above to index and play your local files.',
              style: MidnightVelvetTokens.fontBodyMedium.copyWith(fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Table Column Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: MidnightVelvetTokens.hairlineRim),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text('#', style: MidnightVelvetTokens.fontLabelSmall),
              ),
              Expanded(
                flex: 4,
                child:
                    Text('TITLE', style: MidnightVelvetTokens.fontLabelSmall),
              ),
              Expanded(
                flex: 3,
                child:
                    Text('ARTIST', style: MidnightVelvetTokens.fontLabelSmall),
              ),
              Expanded(
                flex: 3,
                child:
                    Text('ALBUM', style: MidnightVelvetTokens.fontLabelSmall),
              ),
              SizedBox(
                width: 80,
                child:
                    Text('FORMAT', style: MidnightVelvetTokens.fontLabelSmall),
              ),
              SizedBox(
                width: 60,
                child: Text('TIME',
                    style: MidnightVelvetTokens.fontLabelSmall,
                    textAlign: TextAlign.right),
              ),
              const SizedBox(width: 50),
            ],
          ),
        ),

        // Scrollable Tracks Rows
        Expanded(
          child: ListView.builder(
            itemCount: songs.length,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemBuilder: (context, index) {
              final song = songs[index];
              final isActive = currentTrack?.id == song.id;
              final isHovered = _hoveredIndex == index;

              return MouseRegion(
                onEnter: (_) => setState(() => _hoveredIndex = index),
                onExit: (_) => setState(() => _hoveredIndex = null),
                child: InkWell(
                  onTap: () {
                    // Play this track and set entire catalog as queue
                    controller.selectTrack(
                      song,
                      songs,
                      playingFrom: 'Studio Catalog',
                    );
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive
                          ? MidnightVelvetTokens.surfaceCardHover
                          : isHovered
                              ? MidnightVelvetTokens.surfaceCardHover
                                  .withValues(alpha: 0.5)
                              : Colors.transparent,
                    ),
                    child: Row(
                      children: [
                        // 1. Index / Active Equalizer
                        SizedBox(
                          width: 36,
                          child: isActive && isPlaying
                              ? const Icon(
                                  Icons.graphic_eq_rounded,
                                  size: 16,
                                  color: MidnightVelvetTokens.amberChampagne,
                                )
                              : Text(
                                  '${index + 1}',
                                  style: MidnightVelvetTokens.fontMonoTimecode
                                      .copyWith(
                                    fontSize: 11,
                                    color: isActive
                                        ? MidnightVelvetTokens.amberChampagne
                                        : MidnightVelvetTokens.textMuted,
                                  ),
                                ),
                        ),

                        // 2. Title + Cover
                        Expanded(
                          flex: 4,
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: MieeArtworkImage(
                                    musicItem: song,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  song.displayTitle,
                                  style: MidnightVelvetTokens.fontBodyMedium
                                      .copyWith(
                                    fontSize: 13,
                                    fontWeight: isActive
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: isActive
                                        ? MidnightVelvetTokens.amberChampagne
                                        : MidnightVelvetTokens.textDisplay,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 3. Artist
                        Expanded(
                          flex: 3,
                          child: Text(
                            song.artist,
                            style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                              fontSize: 12,
                              color: MidnightVelvetTokens.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        // 4. Album
                        Expanded(
                          flex: 3,
                          child: Text(
                            song.album,
                            style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                              fontSize: 12,
                              color: MidnightVelvetTokens.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        // 5. Format Badge
                        SizedBox(
                          width: 80,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: MidnightVelvetTokens.canvasBase,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: MidnightVelvetTokens.hairlineRim),
                            ),
                            child: Text(
                              _resolveFormatLabel(song.filePath),
                              style: MidnightVelvetTokens.fontMonoTelemetry
                                  .copyWith(
                                fontSize: 9,
                                color: MidnightVelvetTokens.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),

                        // 6. Duration
                        SizedBox(
                          width: 60,
                          child: Text(
                            song.duration,
                            style:
                                MidnightVelvetTokens.fontMonoTimecode.copyWith(
                              fontSize: 11,
                              color: MidnightVelvetTokens.textSecondary,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),

                        // 7. Play Button
                        SizedBox(
                          width: 50,
                          child: IconButton(
                            icon: Icon(
                              isActive && isPlaying
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_fill_rounded,
                              size: 20,
                              color: isActive
                                  ? MidnightVelvetTokens.primaryEmber
                                  : MidnightVelvetTokens.textSecondary,
                            ),
                            onPressed: () {
                              if (isActive) {
                                controller.togglePlayPause();
                              } else {
                                controller.selectTrack(song, songs,
                                    playingFrom: 'Studio Catalog');
                              }
                            },
                            splashRadius: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumsGrid(
      List<MediaAlbum> albums, PlayerController controller) {
    if (albums.isEmpty) {
      return Center(
        child: Text(
          'NO ALBUMS FOUND',
          style: MidnightVelvetTokens.fontBodyMedium
              .copyWith(color: MidnightVelvetTokens.textMuted),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.78,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return InkWell(
          onTap: () {
            final allSongs = ref.read(songsProvider);
            final albumSongs = allSongs
                .where((s) =>
                    s.album.trim().toLowerCase() ==
                    album.title.trim().toLowerCase())
                .toList();
            if (albumSongs.isNotEmpty) {
              ref.read(playerControllerProvider.notifier).selectTrack(
                    albumSongs.first,
                    albumSongs,
                    playingFrom: album.title,
                  );
            }
          },
          borderRadius: BorderRadius.circular(10),
          hoverColor: MidnightVelvetTokens.surfaceCardHover,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MidnightVelvetTokens.surfaceCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MidnightVelvetTokens.hairlineRim),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: album.artworkPath.isNotEmpty &&
                            File(album.artworkPath).existsSync()
                        ? Image.file(File(album.artworkPath), fit: BoxFit.cover)
                        : Container(
                            color: MidnightVelvetTokens.canvasBase,
                            child: const Icon(
                              Icons.album_rounded,
                              size: 40,
                              color: MidnightVelvetTokens.textMuted,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  album.title,
                  style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: MidnightVelvetTokens.textDisplay,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${album.trackCount} Tracks',
                  style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                    fontSize: 10,
                    color: MidnightVelvetTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildArtistsGrid(List<MediaArtist> artists) {
    if (artists.isEmpty) {
      return Center(
        child: Text(
          'NO ARTISTS FOUND',
          style: MidnightVelvetTokens.fontBodyMedium
              .copyWith(color: MidnightVelvetTokens.textMuted),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MidnightVelvetTokens.surfaceCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MidnightVelvetTokens.hairlineRim),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: MidnightVelvetTokens.canvasBase,
                child: Text(
                  artist.name.isNotEmpty ? artist.name[0].toUpperCase() : 'A',
                  style: MidnightVelvetTokens.fontDisplayMedium.copyWith(
                    fontSize: 22,
                    color: MidnightVelvetTokens.amberChampagne,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                artist.name,
                style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: MidnightVelvetTokens.textDisplay,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                '${artist.trackCount} Tracks',
                style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                  fontSize: 10,
                  color: MidnightVelvetTokens.textMuted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFoldersList(List<MediaFolder> folders) {
    if (folders.isEmpty) {
      return Center(
        child: Text(
          'NO FOLDERS INDEXED',
          style: MidnightVelvetTokens.fontBodyMedium
              .copyWith(color: MidnightVelvetTokens.textMuted),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folder = folders[index];
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: MidnightVelvetTokens.surfaceCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: MidnightVelvetTokens.hairlineRim),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.folder_rounded,
                color: MidnightVelvetTokens.amberChampagne,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folder.name,
                      style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: MidnightVelvetTokens.textDisplay,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      folder.path,
                      style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                        fontSize: 10,
                        color: MidnightVelvetTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: MidnightVelvetTokens.canvasBase,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${folder.trackCount} Tracks',
                  style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                    fontSize: 10,
                    color: MidnightVelvetTokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _resolveFormatLabel(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.flac')) return 'FLAC 24/96';
    if (lower.endsWith('.wav')) return 'WAV PCM';
    if (lower.endsWith('.m4a')) return 'M4A AAC';
    if (lower.endsWith('.mp3')) return 'MP3 320K';
    if (lower.endsWith('.ogg') || lower.endsWith('.opus')) return 'OGG VORBIS';
    return 'AUDIO';
  }
}
