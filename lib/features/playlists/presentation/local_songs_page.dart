import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../core/audio/providers.dart';
import '../../../core/audio/playback_state.dart';
import '../../media/providers/media_providers.dart';
import '../../media/domain/models.dart';
import '../../library/providers/library_providers.dart';
import '../providers/playlist_providers.dart';
import 'widgets/add_to_playlist_sheet.dart';

enum _SortOption { title, artist, duration }

/// Dedicated Local Songs Screen that displays only scanned local device songs.
class LocalSongsPage extends ConsumerStatefulWidget {
  const LocalSongsPage({super.key});

  @override
  ConsumerState<LocalSongsPage> createState() => _LocalSongsPageState();
}

class _LocalSongsPageState extends ConsumerState<LocalSongsPage> {
  final TextEditingController _searchController = TextEditingController();
  _SortOption _sortOption = _SortOption.title;
  bool _isScrolled = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.offset > 10.0 && !_isScrolled) {
      setState(() => _isScrolled = true);
    } else if (_scrollController.offset <= 10.0 && _isScrolled) {
      setState(() => _isScrolled = false);
    }
  }

  int _parseDuration(String d) {
    final parts = d.split(':');
    if (parts.length == 2) {
      final minutes = int.tryParse(parts[0]) ?? 0;
      final seconds = int.tryParse(parts[1]) ?? 0;
      return minutes * 60 + seconds;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final localSongs = ref.watch(songsProvider);
    final playbackState = ref.watch(playerControllerProvider);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final favorites = ref.watch(favoritesProvider);

    // 1. Filter local songs by search query
    final query = _searchController.text.toLowerCase().trim();
    final filteredSongs = localSongs.where((song) {
      return song.title.toLowerCase().contains(query) ||
          song.artist.toLowerCase().contains(query);
    }).toList();

    // 2. Sort filtered local songs
    switch (_sortOption) {
      case _SortOption.title:
        filteredSongs.sort((a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case _SortOption.artist:
        filteredSongs.sort((a, b) =>
            a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case _SortOption.duration:
        filteredSongs.sort((a, b) =>
            _parseDuration(a.duration).compareTo(_parseDuration(b.duration)));
        break;
    }

    return Scaffold(
      extendBody: true,
      backgroundColor: AppColors.background,
      appBar: AppHeader(
        title: 'Local Songs',
        isScrolled: _isScrolled,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
          splashRadius: 20.0,
        ),
      ),
      body: Stack(
        children: [
          // 1. Scrollable List of Songs
          Positioned.fill(
            child: SafeArea(
              top: false,
              bottom: false,
              child: Column(
                children: [
                  // Search & Sorting Controls
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.marginMobile,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: AppTypography.bodyMedium
                                .copyWith(color: AppColors.onSurface),
                            decoration: InputDecoration(
                              hintText: 'Search songs...',
                              hintStyle: AppTypography.bodyMedium
                                  .copyWith(color: AppColors.onSurfaceVariant),
                              prefixIcon: const Icon(Icons.search,
                                  size: 20.0,
                                  color: AppColors.onSurfaceVariant),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear,
                                          size: 18.0,
                                          color: AppColors.onSurfaceVariant),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {});
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: AppColors.surfaceContainerLowest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.0),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          child: PopupMenuButton<_SortOption>(
                            icon: const Icon(Icons.sort,
                                color: AppColors.onSurface),
                            tooltip: 'Sort songs',
                            color: AppColors.surfaceContainerLowest,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                            onSelected: (opt) =>
                                setState(() => _sortOption = opt),
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: _SortOption.title,
                                child: Text('Sort by Title',
                                    style: TextStyle(
                                        color: AppColors.onSurface)),
                              ),
                              const PopupMenuItem(
                                value: _SortOption.artist,
                                child: Text('Sort by Artist',
                                    style: TextStyle(
                                        color: AppColors.onSurface)),
                              ),
                              const PopupMenuItem(
                                value: _SortOption.duration,
                                child: Text('Sort by Duration',
                                    style: TextStyle(
                                        color: AppColors.onSurface)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Song list
                  Expanded(
                    child: filteredSongs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.music_note_outlined,
                                  size: 64.0,
                                  color: AppColors.onSurfaceVariant,
                                ),
                                AppSpacing.heightMd,
                                Text(
                                  _searchController.text.isNotEmpty
                                      ? 'No search results'
                                      : 'No local songs',
                                  style: AppTypography.headlineMedium.copyWith(
                                    color: AppColors.onSurface,
                                  ),
                                ),
                                AppSpacing.heightSm,
                                Text(
                                  _searchController.text.isNotEmpty
                                      ? 'Try a different search query.'
                                      : 'Scanned songs on your device will appear here.',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                                SizedBox(height: 120.0 + bottomInset),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.only(
                              left: AppSpacing.marginMobile,
                              right: AppSpacing.marginMobile,
                              top: AppSpacing.sm,
                              bottom: 120.0 + bottomInset,
                            ),
                            itemCount: filteredSongs.length,
                            itemBuilder: (context, index) {
                              final song = filteredSongs[index];
                              final isCurrentTrack =
                                  playbackState.currentTrack?.id == song.id;

                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2.0),
                                child: SongTile(
                                  title: song.title,
                                  artist: song.artist,
                                  duration: song.duration,
                                  imageUrl: song.artworkPath,
                                  isPlaying: isCurrentTrack,
                                  onTap: () {
                                    ref
                                        .read(playerControllerProvider.notifier)
                                        .selectTrack(song, filteredSongs);
                                    context.push('/player');
                                  },
                                  onMoreTap: () =>
                                      showAddToPlaylistSheet(context, song),
                                  onLongPress: () =>
                                      showAddToPlaylistSheet(context, song),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Floating MiniPlayer (positioned at the bottom since there's no bottom navigation bar)
          Positioned(
            left: AppSpacing.marginMobile,
            right: AppSpacing.marginMobile,
            bottom: bottomInset + AppSpacing.sm,
            child: Consumer(
              builder: (context, ref, child) {
                final playbackState = ref.watch(playerControllerProvider);
                final controller = ref.read(playerControllerProvider.notifier);
                final currentTrack = playbackState.currentTrack;

                if (currentTrack == null) {
                  return const SizedBox.shrink();
                }

                final isPlaying =
                    playbackState.status == PlaybackStatus.playing;
                final total = playbackState.duration.inMilliseconds;
                final pos = playbackState.position.inMilliseconds;
                final progress = total > 0 ? pos / total : 0.0;

                return MiniPlayer(
                  musicItem: currentTrack,
                  progress: progress,
                  isPlaying: isPlaying,
                  isFavorited: favorites.any((t) => t.id == currentTrack.id),
                  isDark: true,
                  onTap: () => context.push('/player'),
                  onPlayPauseTap: () {
                    if (isPlaying) {
                      controller.pause();
                    } else {
                      controller.play();
                    }
                  },
                  onFavoriteTap: () {},
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
