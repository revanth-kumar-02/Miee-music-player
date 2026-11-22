import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/audio/providers.dart';
import '../../../shared/models/track.dart';
import '../../artwork/data/artwork_cache.dart';
import '../../artwork/domain/artwork_query.dart';
import '../../artwork/presentation/artwork_providers.dart';
import '../../artwork/presentation/miee_artwork_image.dart';
import '../../search/domain/online_playlist.dart';
import '../../youtube/domain/youtube_model.dart';
import '../../youtube/presentation/widgets/youtube_options_menu.dart';
import '../../youtube/providers/youtube_providers.dart';

/// Full-screen detail page for an online playlist search result.
///
/// Fetches authentic track items from YouTube Music Innertube, renders playlist
/// artwork, title, curator metadata, action buttons (Play All / Shuffle), and
/// an interactive track list with playback and queue integration.
class OnlinePlaylistDetailPage extends ConsumerStatefulWidget {
  final String playlistId;
  final OnlinePlaylist? initialPlaylist;

  const OnlinePlaylistDetailPage({
    super.key,
    required this.playlistId,
    this.initialPlaylist,
  });

  @override
  ConsumerState<OnlinePlaylistDetailPage> createState() =>
      _OnlinePlaylistDetailPageState();
}

class _OnlinePlaylistDetailPageState
    extends ConsumerState<OnlinePlaylistDetailPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<YouTubeVideo> _videos = [];

  @override
  void initState() {
    super.initState();
    _loadPlaylistVideos();
  }

  Future<void> _loadPlaylistVideos() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(youtubeRepositoryProvider);
      final results = await repo.getPlaylistVideos(widget.playlistId);

      if (mounted) {
        setState(() {
          _videos = results;
          _isLoading = false;
          if (results.isEmpty) {
            _errorMessage = 'No playable tracks found in this playlist.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load playlist tracks: $e';
        });
      }
    }
  }

  void _playAll({bool shuffle = false}) {
    if (_videos.isEmpty) return;

    final tracks = _videos.map((v) => v.toTrack()).toList();
    final effectiveQueue = List<Track>.from(tracks);
    if (shuffle) {
      effectiveQueue.shuffle();
    }

    final playerController = ref.read(playerControllerProvider.notifier);
    playerController.setQueue(
      effectiveQueue,
      startIndex: 0,
      playingFrom: 'Online Playlist: ${widget.initialPlaylist?.title ?? ''}',
    );
  }

  void _playTrack(YouTubeVideo video) {
    final allTracks = _videos.map((v) => v.toTrack()).toList();
    final targetTrack = video.toTrack();
    final index = allTracks.indexWhere((t) => t.id == targetTrack.id);

    final playerController = ref.read(playerControllerProvider.notifier);
    playerController.setQueue(
      allTracks,
      startIndex: index >= 0 ? index : 0,
      playingFrom: 'Online Playlist: ${widget.initialPlaylist?.title ?? ''}',
    );
  }

  void _showVideoOptions(BuildContext context, YouTubeVideo video) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (ctx) => YouTubeOptionsMenu(video: video),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPlayingTrackId = ref.watch(
      playerControllerProvider.select((s) => s.currentTrack?.id),
    );

    final title = widget.initialPlaylist?.title ?? 'Playlist';
    final author = widget.initialPlaylist?.author ?? 'Curated Collection';
    final rawTrackCount = widget.initialPlaylist?.trackCount;
    final trackCountStr = _videos.isNotEmpty
        ? '${_videos.length} tracks'
        : (rawTrackCount != null && rawTrackCount > 0
            ? '$rawTrackCount tracks'
            : '');

    final heroArtwork = widget.initialPlaylist?.thumbnailUrl ??
        (_videos.isNotEmpty ? _videos.first.thumbnailUrl : '');

    // Derive playlist artist: prefer curated author unless it's generic ("Playlist", "YouTube")
    final playlistArtist = (widget.initialPlaylist?.author != null &&
            widget.initialPlaylist!.author.isNotEmpty &&
            widget.initialPlaylist!.author.toLowerCase() != 'playlist' &&
            widget.initialPlaylist!.author.toLowerCase() != 'youtube')
        ? widget.initialPlaylist!.author
        : (_videos.isNotEmpty
            ? (_videos.first.canonicalArtist ?? _videos.first.channelTitle)
            : '');

    final playlistArtworkQuery = ArtworkQuery.forPlaylist(
      id: widget.playlistId,
      title: title,
      artist: playlistArtist,
      thumbnailUrl: heroArtwork,
    );

    final resolvedArtworkAsync = ref.watch(resolvedArtworkProvider(playlistArtworkQuery));
    final resolvedHeroArtwork = resolvedArtworkAsync.valueOrNull;
    final resolvedHeroUrl = (resolvedHeroArtwork != null &&
            !resolvedHeroArtwork.isNeutralFallback &&
            resolvedHeroArtwork.imageUrl.isNotEmpty)
        ? (resolvedHeroArtwork.localCachedPath != null &&
                ArtworkCache.hasValidLocalFile(resolvedHeroArtwork.localCachedPath)
            ? resolvedHeroArtwork.localCachedPath!
            : resolvedHeroArtwork.imageUrl)
        : null;

    final isStudioAlbumArt = resolvedHeroUrl != null &&
        !resolvedHeroUrl.contains('ytimg.com') &&
        !resolvedHeroUrl.contains('youtube.com') &&
        resolvedHeroArtwork != null &&
        resolvedHeroArtwork.confidence >= 0.80;

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Sliver App Bar with cover artwork ───────────────────────────
            SliverAppBar(
              expandedHeight: 280.0,
              pinned: true,
              backgroundColor: AppColors.background,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.cocoaPlum),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/search');
                  }
                },
                splashRadius: 22.0,
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    MieeArtworkImage(
                      query: playlistArtworkQuery,
                      explicitUrl: resolvedHeroUrl ?? heroArtwork,
                      fit: BoxFit.cover,
                      errorWidget: Container(
                        color: AppColors.cocoaPlum,
                        child: const Icon(Icons.queue_music_rounded,
                            size: 72, color: AppColors.softClay),
                      ),
                    ),
                    // Gradient overlay to ensure text contrast and aesthetic depth
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.2),
                              Colors.transparent,
                              AppColors.background.withValues(alpha: 0.8),
                              AppColors.background,
                            ],
                            stops: const [0.0, 0.4, 0.8, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Playlist Metadata Header ─────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.marginMobile, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppColors.cocoaPlum,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          author,
                          style: GoogleFonts.geist(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.dustyRose,
                          ),
                        ),
                        if (trackCountStr.isNotEmpty) ...[
                          Text(
                            ' · $trackCountStr',
                            style: GoogleFonts.geist(
                              fontSize: 13,
                              color: AppColors.mutedMauve,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Action buttons: Play All & Shuffle
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _videos.isNotEmpty ? () => _playAll() : null,
                            icon: const Icon(Icons.play_arrow_rounded,
                                size: 22, color: AppColors.white),
                            label: Text(
                              'Play All',
                              style: GoogleFonts.geist(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.white,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.dustyRose,
                              disabledBackgroundColor:
                                  AppColors.dustyRose.withValues(alpha: 0.4),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _videos.isNotEmpty
                                ? () => _playAll(shuffle: true)
                                : null,
                            icon: const Icon(Icons.shuffle_rounded,
                                size: 20, color: AppColors.cocoaPlum),
                            label: Text(
                              'Shuffle',
                              style: GoogleFonts.geist(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.cocoaPlum,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: AppColors.softClay, width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: AppColors.softClay, height: 1),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            // ── Tracks List / Skeleton / Empty State ─────────────────────────
            if (_isLoading)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildTrackSkeletonTile(),
                  childCount: 6,
                ),
              )
            else if (_errorMessage != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 48, color: AppColors.dustyRose),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.geist(
                            fontSize: 15,
                            color: AppColors.cocoaPlum,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadPlaylistVideos,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.cocoaPlum,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final video = _videos[index];
                    final isPlaying = currentPlayingTrackId == 'youtube_${video.id}';

                    return _buildTrackTile(
                      index: index + 1,
                      video: video,
                      isPlaying: isPlaying,
                      inheritedAlbumArt: isStudioAlbumArt ? resolvedHeroUrl : null,
                      playlistAlbumTitle: title,
                      onTap: () => _playTrack(video),
                      onMoreTap: () => _showVideoOptions(context, video),
                    );
                  },
                  childCount: _videos.length,
                ),
              ),

            // Bottom padding for mini-player clearance
            const SliverToBoxAdapter(
              child: SizedBox(height: 120),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackTile({
    required int index,
    required YouTubeVideo video,
    required bool isPlaying,
    String? inheritedAlbumArt,
    String? playlistAlbumTitle,
    required VoidCallback onTap,
    required VoidCallback onMoreTap,
  }) {
    final trackQuery = ArtworkQuery.fromMusicItem(
      video,
      album: playlistAlbumTitle,
      albumArtworkUrl: inheritedAlbumArt,
      explicitUrl: inheritedAlbumArt,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: [
            // Track Number / Playing indicator
            SizedBox(
              width: 28,
              child: isPlaying
                  ? const Icon(Icons.volume_up_rounded,
                      size: 20, color: AppColors.dustyRose)
                  : Text(
                      '$index',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.geist(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.mutedMauve,
                      ),
                    ),
            ),
            const SizedBox(width: 8),

            // Artwork
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 48,
                height: 48,
                color: AppColors.softClay,
                child: MieeArtworkImage(
                  musicItem: video,
                  query: trackQuery,
                  explicitUrl: inheritedAlbumArt,
                  fit: BoxFit.cover,
                  errorWidget: const Icon(Icons.music_note_rounded,
                      color: AppColors.cocoaPlum, size: 24),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Title & Channel / Artist
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.geist(
                      fontSize: 15,
                      fontWeight:
                          isPlaying ? FontWeight.bold : FontWeight.w600,
                      color: isPlaying
                          ? AppColors.dustyRose
                          : AppColors.cocoaPlum,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    video.channelTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.geist(
                      fontSize: 13,
                      color: AppColors.mutedMauve,
                    ),
                  ),
                ],
              ),
            ),

            // Duration
            if (video.duration.isNotEmpty)
              Text(
                video.duration,
                style: GoogleFonts.geist(
                  fontSize: 12,
                  color: AppColors.mutedMauve,
                ),
              ),

            // Overflow Options Menu
            IconButton(
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.mutedMauve, size: 20),
              onPressed: onMoreTap,
              splashRadius: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackSkeletonTile() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.softClay.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.softClay.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.softClay.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 120,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.softClay.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 32,
            height: 12,
            decoration: BoxDecoration(
              color: AppColors.softClay.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
