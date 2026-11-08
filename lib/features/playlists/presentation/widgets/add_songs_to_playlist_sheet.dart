import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../shared/models/music_item.dart';
import '../../../../shared/models/track.dart';
import '../../../library/providers/library_providers.dart';
import '../../../media/providers/media_providers.dart';
import '../../../search/data/search_repository.dart';
import '../../../search/providers/search_providers.dart';
import '../../domain/playlist_model.dart';
import '../../providers/playlist_providers.dart';

/// Opens the multi-song selection sheet to add songs to [playlist].
Future<void> showAddSongsToPlaylistSheet(
  BuildContext context,
  PlaylistModel playlist,
) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AddSongsToPlaylistSheet(playlist: playlist),
  );
}

class AddSongsToPlaylistSheet extends ConsumerStatefulWidget {
  final PlaylistModel playlist;

  const AddSongsToPlaylistSheet({
    super.key,
    required this.playlist,
  });

  @override
  ConsumerState<AddSongsToPlaylistSheet> createState() =>
      _AddSongsToPlaylistSheetState();
}

class _AddSongsToPlaylistSheetState
    extends ConsumerState<AddSongsToPlaylistSheet>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _searchController;
  late final TabController _tabController;
  final Set<String> _selectedTrackIds = <String>{};
  final Map<String, MusicItem> _selectedTracksMap = <String, MusicItem>{};

  Timer? _debounceTimer;
  bool _isSearchingOnline = false;
  List<MusicItem> _onlineSearchResults = [];
  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    setState(() {
      _currentQuery = trimmed;
    });

    if (trimmed.isEmpty) {
      setState(() {
        _isSearchingOnline = false;
        _onlineSearchResults = [];
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _isSearchingOnline = true);
      try {
        final repo = ref.read(searchRepositoryProvider);
        final results = await repo.searchYouTube(trimmed);
        if (mounted && _currentQuery == trimmed) {
          setState(() {
            _onlineSearchResults = results.map((v) => v.toTrack()).toList();
            _isSearchingOnline = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isSearchingOnline = false);
        }
      }
    });
  }

  bool _isAlreadyInPlaylist(String id) {
    final cleanId = id.startsWith('youtube_') ? id.substring(8) : id;
    return widget.playlist.tracks.any((t) {
      final tClean = t.id.startsWith('youtube_') ? t.id.substring(8) : t.id;
      return tClean == cleanId || t.id == id;
    });
  }

  void _toggleSelection(MusicItem track) {
    if (_isAlreadyInPlaylist(track.id)) return;

    setState(() {
      if (_selectedTrackIds.contains(track.id)) {
        _selectedTrackIds.remove(track.id);
        _selectedTracksMap.remove(track.id);
      } else {
        _selectedTrackIds.add(track.id);
        _selectedTracksMap[track.id] = track;
      }
    });
  }

  Future<void> _addSelectedSongs() async {
    if (_selectedTracksMap.isEmpty) return;

    final songsToAdd = _selectedTracksMap.values.toList();
    final count = await ref
        .read(playlistControllerProvider.notifier)
        .addTracks(widget.playlist.id, songsToAdd);

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? 'Added 1 song to "${widget.playlist.name}"'
                : 'Added $count songs to "${widget.playlist.name}"',
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final safeBottom = mediaQuery.padding.bottom;
    final sheetHeight = mediaQuery.size.height * 0.88;

    final likedSongs = ref.watch(favoritesProvider);
    final localSongs = ref.watch(songsProvider);

    return Container(
      height: sheetHeight,
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
            child: Container(
              width: 40.0,
              height: 4.0,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: AppRadius.radiusFull,
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.marginMobile,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Songs',
                        style: GoogleFonts.geist(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.playlist.name,
                        style: GoogleFonts.geist(
                          fontSize: 13,
                          color: AppColors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.marginMobile,
              vertical: 8.0,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Search songs, artists, or albums...',
                hintStyle: GoogleFonts.geist(
                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
                prefixIcon: const Icon(Icons.search, color: AppColors.onSurfaceVariant),
                suffixIcon: _currentQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onQueryChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: AppRadius.radiusMd,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Tabs (Only if not searching)
          if (_currentQuery.isEmpty) ...[
            TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.onSurfaceVariant,
              labelStyle: GoogleFonts.geist(fontWeight: FontWeight.w600, fontSize: 13),
              tabs: [
                Tab(text: 'Liked Songs (${likedSongs.length})'),
                Tab(text: 'Device Music (${localSongs.length})'),
              ],
            ),
          ],

          // Content
          Expanded(
            child: _currentQuery.isNotEmpty
                ? _buildSearchResults(localSongs)
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTrackList(likedSongs, 'No liked songs found.'),
                      _buildTrackList(localSongs, 'No device music found.'),
                    ],
                  ),
          ),

          // Sticky Bottom Bar for Adding Songs
          SafeArea(
            top: false,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.marginMobile,
                12.0,
                AppSpacing.marginMobile,
                safeBottom > 0 ? safeBottom : 12.0,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                border: Border(
                  top: BorderSide(
                    color: AppColors.outlineVariant.withValues(alpha: 0.3),
                    width: 1.0,
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 48.0,
                child: FilledButton.icon(
                  onPressed: _selectedTrackIds.isEmpty ? null : _addSelectedSongs,
                  icon: const Icon(Icons.playlist_add, size: 20),
                  label: Text(
                    _selectedTrackIds.isEmpty
                        ? 'Select songs to add'
                        : 'Add ${_selectedTrackIds.length} ${_selectedTrackIds.length == 1 ? 'Song' : 'Songs'}',
                    style: GoogleFonts.geist(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor:
                        AppColors.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.radiusMd,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(List<MusicItem> localSongs) {
    final lowerQuery = _currentQuery.toLowerCase();
    final matchingLocal = localSongs.where((t) {
      return t.title.toLowerCase().contains(lowerQuery) ||
          t.artist.toLowerCase().contains(lowerQuery);
    }).toList();

    if (_isSearchingOnline && matchingLocal.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(
            strokeWidth: 2.0,
            color: AppColors.primary,
          ),
        ),
      );
    }

    final combined = <MusicItem>[...matchingLocal];
    for (final online in _onlineSearchResults) {
      if (!combined.any((c) => c.id == online.id)) {
        combined.add(online);
      }
    }

    if (combined.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 48, color: AppColors.outlineVariant),
              const SizedBox(height: 12),
              Text(
                'No songs found for "$_currentQuery"',
                style: GoogleFonts.geist(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: combined.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        return _buildSongSelectTile(combined[index]);
      },
    );
  }

  Widget _buildTrackList(List<MusicItem> tracks, String emptyMessage) {
    if (tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            emptyMessage,
            style: GoogleFonts.geist(
              color: AppColors.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: tracks.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        return _buildSongSelectTile(tracks[index]);
      },
    );
  }

  Widget _buildSongSelectTile(MusicItem track) {
    final inPlaylist = _isAlreadyInPlaylist(track.id);
    final isSelected = _selectedTrackIds.contains(track.id);

    return InkWell(
      onTap: inPlaylist ? null : () => _toggleSelection(track),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.marginMobile,
          vertical: 8.0,
        ),
        color: isSelected
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        child: Row(
          children: [
            // Selection indicator / checkmark
            Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: inPlaylist
                    ? AppColors.surfaceContainerHighest
                    : isSelected
                        ? AppColors.primary
                        : Colors.transparent,
                border: Border.all(
                  color: inPlaylist
                      ? AppColors.outlineVariant
                      : isSelected
                          ? AppColors.primary
                          : AppColors.outlineVariant,
                  width: 1.5,
                ),
              ),
              child: inPlaylist
                  ? const Icon(Icons.check, size: 14, color: AppColors.onSurfaceVariant)
                  : isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
            ),

            // Artwork
            ClipRRect(
              borderRadius: BorderRadius.circular(6.0),
              child: SizedBox(
                width: 44,
                height: 44,
                child: track.imageUrl != null && track.imageUrl!.isNotEmpty
                    ? Image.network(
                        track.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _defaultArtwork(),
                      )
                    : _defaultArtwork(),
              ),
            ),
            const SizedBox(width: 12),

            // Title & Artist
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: GoogleFonts.geist(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: inPlaylist
                          ? AppColors.onSurfaceVariant
                          : AppColors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    style: GoogleFonts.geist(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Status or Duration
            if (inPlaylist)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Added',
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              )
            else
              Text(
                track.duration,
                style: GoogleFonts.geist(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _defaultArtwork() {
    return Container(
      color: AppColors.surfaceContainerHighest,
      child: const Icon(
        Icons.music_note,
        size: 22,
        color: AppColors.outlineVariant,
      ),
    );
  }
}
