import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/audio/playback_state.dart';
import '../../../core/audio/providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/widgets.dart';
import '../../media/domain/models.dart';
import '../../media/providers/media_providers.dart';
import '../../onboarding/data/artist_discovery_repository.dart';
import '../../onboarding/domain/artist_model.dart';
import '../../onboarding/providers/onboarding_providers.dart';
import '../../profile/providers/profile_providers.dart';
import '../../recommendations/data/recommendation_service.dart';
import '../../youtube/data/youtube_repository.dart';
import '../../youtube/providers/youtube_providers.dart';

/// Combined state for the shared Artist Profile page.
class ArtistProfileData {
  final ArtistModel artist;
  final List<Track> tracks;
  final List<ArtistAlbum> albums;
  final bool isLocal;
  final bool isLoading;
  final String? errorMessage;
  final bool hasMoreTracks;
  final int currentPage;
  final bool isLoadingMore;

  const ArtistProfileData({
    required this.artist,
    this.tracks = const [],
    this.albums = const [],
    this.isLocal = false,
    this.isLoading = false,
    this.errorMessage,
    this.hasMoreTracks = false,
    this.currentPage = 1,
    this.isLoadingMore = false,
  });

  ArtistProfileData copyWith({
    ArtistModel? artist,
    List<Track>? tracks,
    List<ArtistAlbum>? albums,
    bool? isLocal,
    bool? isLoading,
    String? errorMessage,
    bool? hasMoreTracks,
    int? currentPage,
    bool? isLoadingMore,
  }) {
    return ArtistProfileData(
      artist: artist ?? this.artist,
      tracks: tracks ?? this.tracks,
      albums: albums ?? this.albums,
      isLocal: isLocal ?? this.isLocal,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      hasMoreTracks: hasMoreTracks ?? this.hasMoreTracks,
      currentPage: currentPage ?? this.currentPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// Unified Shared Artist Profile Page.
///
/// Serves as the single artist profile destination across:
/// 1. Home → Your Favourite Artists
/// 2. Home → Explore Related Artists
/// 3. Search → Artists tab/entity cards
/// 4. Library → Local Artists
class ArtistDetailPage extends ConsumerStatefulWidget {
  final String artistId;
  final Object? initialArtist;

  const ArtistDetailPage({
    super.key,
    required this.artistId,
    this.initialArtist,
  });

  @override
  ConsumerState<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends ConsumerState<ArtistDetailPage> {
  ArtistProfileData? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadArtistData();
  }

  ArtistModel? _extractInitialArtist() {
    final extra = widget.initialArtist;
    if (extra is ArtistModel) return extra;
    if (extra is ArtistSummary) {
      return ArtistModel(
        id: extra.id,
        name: extra.name,
        imageUrl: extra.imageUrl,
        languages: extra.languages,
      );
    }
    if (extra is MediaArtist) {
      return ArtistModel(
        id: extra.id,
        name: extra.name,
        imageUrl: extra.artworkPath ?? '',
      );
    }
    return null;
  }

  Future<void> _loadArtistData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final artistRepo = ref.read(artistRepositoryProvider);
      final localArtists = ref.read(artistsProvider);
      final localSongs = ref.read(songsProvider);
      final localAlbums = ref.read(albumsProvider);

      // 1. Resolve Artist Entity
      ArtistModel? artist = _extractInitialArtist();

      // Check local device artist
      final localMatch = localArtists.where((a) => a.id == widget.artistId).firstOrNull;
      final isLocal = localMatch != null;

      if (artist == null) {
        // Try curated match by ID or name
        artist = DeezerArtistRepository.findCuratedById(widget.artistId);
        if (artist == null && localMatch != null) {
          artist = ArtistModel(
            id: localMatch.id,
            name: localMatch.name,
            imageUrl: localMatch.artworkPath ?? '',
          );
        }
        // Try online lookup via Deezer API
        artist ??= await artistRepo.getArtistDetails(widget.artistId);
      }

      // If still not resolved, try curated by name
      artist ??= DeezerArtistRepository.findCuratedByName(widget.artistId);

      // Fallback placeholder if no metadata exists
      artist ??= ArtistModel(
        id: widget.artistId,
        name: widget.artistId,
        imageUrl: '',
      );

      // Ensure verified portrait is used if available from curated catalog
      if (artist.imageUrl.isEmpty || !ArtistAvatar.isValidArtistImageUrl(artist.imageUrl)) {
        final curated = DeezerArtistRepository.findCuratedByName(artist.name);
        if (curated != null && ArtistAvatar.isValidArtistImageUrl(curated.imageUrl)) {
          artist = artist.copyWith(imageUrl: curated.imageUrl);
        }
      }

      // 2. Resolve Tracks
      final tracks = <Track>[];

      // If artist has local device songs
      final matchingLocal = localSongs.where(
        (s) => s.artist.trim().toLowerCase() == artist!.name.trim().toLowerCase(),
      ).toList();

      if (matchingLocal.isNotEmpty) {
        tracks.addAll(matchingLocal.map((s) => Track(
              id: s.id,
              title: s.title,
              artist: s.artist,
              imageUrl: s.artworkPath,
              duration: s.duration,
              filePath: s.filePath,
            )));
      }

      // Online tracks via YouTube search with deduplication & podcast/movie filtering
      bool hasMoreOnlineTracks = false;
      try {
        final ytRepo = ref.read(youtubeRepositoryProvider);
        final rawVideos = await ytRepo.getArtistTracks(artist.name, page: 1, limit: 15);
        hasMoreOnlineTracks = rawVideos.length >= 8 && !isLocal;

        final seenIds = tracks.map((t) => t.id).toSet();
        final seenNormIds = tracks.map((t) => t.id.replaceFirst('youtube_', '')).toSet();
        for (final v in rawVideos) {
          if (!RecommendationService.isLegitimateSong(v)) continue;
          final track = v.toTrack(reliableArtist: artist.name);
          final normId = track.id.replaceFirst('youtube_', '');
          if (!seenIds.contains(track.id) && !seenNormIds.contains(normId)) {
            seenIds.add(track.id);
            seenNormIds.add(normId);
            tracks.add(track);
          }
        }
      } catch (e) {
        debugPrint('[ArtistDetailPage] Online tracks fetch error: $e');
      }

      // 3. Resolve Albums
      final albums = <ArtistAlbum>[];
      if (isLocal) {
        final matchingAlbums = localAlbums.where(
          (a) => a.artist.trim().toLowerCase() == artist!.name.trim().toLowerCase(),
        );
        albums.addAll(matchingAlbums.map((a) => ArtistAlbum(
              id: a.id,
              title: a.title,
              coverUrl: a.artworkPath,
              releaseDate: '',
              trackCount: a.trackCount,
            )));
      } else {
        try {
          final deezerId = (int.tryParse(artist.id) != null)
              ? artist.id
              : (DeezerArtistRepository.findCuratedByName(artist.name)?.id ?? '');
          if (deezerId.isNotEmpty) {
            final onlineAlbums = await artistRepo.getArtistAlbums(deezerId);
            albums.addAll(onlineAlbums);
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _data = ArtistProfileData(
            artist: artist!,
            tracks: tracks,
            albums: albums,
            isLocal: isLocal,
            isLoading: false,
            hasMoreTracks: hasMoreOnlineTracks,
            currentPage: 1,
            isLoadingMore: false,
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Could not load artist profile. Please try again.';
        });
      }
    }
  }

  Future<void> _loadMoreTracks() async {
    final current = _data;
    if (current == null || current.isLoadingMore || !current.hasMoreTracks || current.isLocal) {
      return;
    }

    setState(() {
      _data = current.copyWith(isLoadingMore: true);
    });

    try {
      final nextPage = current.currentPage + 1;
      final ytRepo = ref.read(youtubeRepositoryProvider);
      final profile = ref.read(currentUserProfileProvider);
      final preferredLanguages = profile?.preferredLanguages ?? const [];

      final moreVideos = await ytRepo.getArtistTracks(
        current.artist.name,
        page: nextPage,
        limit: 15,
        preferredLanguages: preferredLanguages,
      );

      final existingNormIds = current.tracks.map((t) => t.id.replaceFirst('youtube_', '')).toSet();
      final newTracks = <Track>[];

      for (final v in moreVideos) {
        if (!RecommendationService.isLegitimateSong(v)) continue;
        final normId = v.id.replaceFirst('youtube_', '');
        if (existingNormIds.add(normId)) {
          newTracks.add(v.toTrack(reliableArtist: current.artist.name));
        }
      }

      final hasMore = moreVideos.length >= 8 && newTracks.isNotEmpty;

      if (mounted) {
        setState(() {
          _data = current.copyWith(
            tracks: [...current.tracks, ...newTracks],
            currentPage: nextPage,
            hasMoreTracks: hasMore,
            isLoadingMore: false,
          );
        });
      }
    } catch (e) {
      debugPrint('[ArtistDetailPage] Error loading more tracks: $e');
      if (mounted) {
        setState(() {
          _data = current.copyWith(isLoadingMore: false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        appBar: MieeBrandHeader(
          title: 'Artist',
        ),
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
          ),
        ),
      );
    }

    if (_error != null || _data == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: const MieeBrandHeader(
          title: 'Artist',
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_outlined, size: 64, color: AppColors.onSurfaceVariant),
              AppSpacing.heightMd,
              Text(
                _error ?? 'Artist not found',
                style: AppTypography.bodyMedium.copyWith(color: AppColors.onSurfaceVariant),
              ),
              AppSpacing.heightLg,
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: _loadArtistData,
              ),
            ],
          ),
        ),
      );
    }

    final data = _data!;
    final artist = data.artist;
    final tracks = data.tracks;
    final albums = data.albums;

    final currentTrack = ref.watch(
      playerControllerProvider.select((s) => s.currentTrack),
    );
    final playerController = ref.read(playerControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // 1. Flexible Portrait Header
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
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (artist.imageUrl.isNotEmpty)
                    artist.imageUrl.startsWith('http')
                        ? Image.network(
                            artist.imageUrl,
                            fit: BoxFit.cover,
                            cacheWidth: 600,
                            cacheHeight: 600,
                            errorBuilder: (_, __, ___) => _buildFallbackHeader(),
                          )
                        : Image.file(
                            File(artist.imageUrl),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildFallbackHeader(),
                          )
                  else
                    _buildFallbackHeader(),
                  // Subtle gradient shadow overlay for readable title
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.2),
                          Colors.transparent,
                          AppColors.background.withValues(alpha: 0.9),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Artist Info & Action Bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.marginMobile),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          artist.name,
                          style: AppTypography.headlineLargeMobile.copyWith(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.verified,
                        color: AppColors.primary,
                        size: 24.0,
                      ),
                    ],
                  ),
                  AppSpacing.heightXs,
                  Text(
                    artist.fanCount > 0
                        ? '${_formatNumber(artist.fanCount)} fans · ${tracks.length} tracks available'
                        : '${tracks.length} tracks available',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  AppSpacing.heightMd,

                  // Play / Shuffle Buttons
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.play_arrow, size: 20.0),
                          label: Text(
                            'Play',
                            style: AppTypography.labelMedium.copyWith(color: Colors.white),
                          ),
                          onPressed: tracks.isEmpty
                              ? null
                              : () {
                                  playerController.setQueue(
                                    tracks,
                                    startIndex: 0,
                                    playingFrom: 'Artist: ${artist.name}',
                                  );
                                  context.push('/player');
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.radiusMd,
                            ),
                          ),
                        ),
                      ),
                      AppSpacing.widthMd,
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.shuffle, size: 20.0),
                          label: Text(
                            'Shuffle',
                            style: AppTypography.labelMedium.copyWith(color: AppColors.onSurface),
                          ),
                          onPressed: tracks.isEmpty
                              ? null
                              : () {
                                  final list = List<Track>.from(tracks)..shuffle();
                                  playerController.setQueue(
                                    list,
                                    startIndex: 0,
                                    playingFrom: 'Artist: ${artist.name}',
                                  );
                                  context.push('/player');
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.onSurface,
                            side: const BorderSide(color: AppColors.outlineVariant),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.radiusMd,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 3. Albums & Releases Shelf (if reliable metadata exists)
          if (albums.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Albums & Releases'),
                    AppSpacing.heightMd,
                    SizedBox(
                      height: 165.0,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: albums.length,
                        separatorBuilder: (_, __) => AppSpacing.widthMd,
                        itemBuilder: (context, index) {
                          final album = albums[index];
                          return SizedBox(
                            width: 120.0,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: AppRadius.radiusMd,
                                  child: album.coverUrl.startsWith('http')
                                      ? Image.network(
                                          album.coverUrl,
                                          width: 120.0,
                                          height: 120.0,
                                          fit: BoxFit.cover,
                                          cacheWidth: 240,
                                          cacheHeight: 240,
                                          errorBuilder: (_, __, ___) => Container(
                                            width: 120.0,
                                            height: 120.0,
                                            color: AppColors.surfaceContainerHigh,
                                            child: const Icon(Icons.album, size: 40),
                                          ),
                                        )
                                      : Image.file(
                                          File(album.coverUrl),
                                          width: 120.0,
                                          height: 120.0,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                            width: 120.0,
                                            height: 120.0,
                                            color: AppColors.surfaceContainerHigh,
                                            child: const Icon(Icons.album, size: 40),
                                          ),
                                        ),
                                ),
                                AppSpacing.heightXs,
                                Text(
                                  album.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.labelSmall.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                                if (album.releaseDate.isNotEmpty)
                                  Text(
                                    album.releaseDate.split('-').first,
                                    style: AppTypography.labelSmall.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    AppSpacing.heightLg,
                  ],
                ),
              ),
            ),
          ],

          // 4. Popular / Best Available Tracks Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    title: 'Popular Tracks',
                    actionLabel: data.isLoadingMore
                        ? 'Loading...'
                        : (data.hasMoreTracks ? 'View All' : null),
                    onActionTap: data.isLoadingMore ? null : _loadMoreTracks,
                    actionColor: AppColors.primary,
                  ),
                  AppSpacing.heightMd,
                ],
              ),
            ),
          ),

          if (tracks.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.marginMobile),
                child: EmptyState(
                  title: 'No tracks found',
                  message: 'No individual tracks are currently available for this artist.',
                  icon: Icons.music_off_outlined,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final track = tracks[index];
                    final isPlaying = currentTrack?.id == track.id;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Consumer(
                        builder: (context, ref, _) {
                          final isTrackLoading = ref.watch(
                            playerControllerProvider.select((s) =>
                                s.loadingTrackId != null &&
                                isSameTrackId(s.loadingTrackId, track.id)),
                          );
                          return SongTile(
                            title: track.title,
                            artist: track.artist,
                            duration: track.duration,
                            imageUrl: track.imageUrl,
                            isPlaying: isPlaying,
                            isLoading: isTrackLoading,
                            onTap: isTrackLoading
                                ? null
                                : () {
                                    playerController.selectTrack(
                                      track,
                                      tracks,
                                      playingFrom: 'Artist: ${artist.name}',
                                    );
                                  },
                          );
                        },
                      ),
                    );
                  },
                  childCount: tracks.length,
                ),
              ),
            ),

          if (data.hasMoreTracks || data.isLoadingMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.marginMobile,
                  vertical: AppSpacing.md,
                ),
                child: Center(
                  child: data.isLoadingMore
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.primary,
                          ),
                        )
                      : OutlinedButton.icon(
                          icon: const Icon(Icons.expand_more, size: 18),
                          label: const Text('Load More Songs'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.onSurface,
                            side: const BorderSide(color: AppColors.outlineVariant),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.radiusMd,
                            ),
                          ),
                          onPressed: _loadMoreTracks,
                        ),
                ),
              ),
            )
          else if (tracks.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(
                  child: Text(
                    'Showing all available tracks (${tracks.length})',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 120.0),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackHeader() {
    return Container(
      color: AppColors.surfaceContainerHigh,
      alignment: Alignment.center,
      child: const Icon(
        Icons.person,
        size: 96.0,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    }
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }
}
