import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yte;
import '../../../core/network/network_request_coordinator.dart';
import '../domain/youtube_model.dart';
import '../domain/youtube_metadata_cleaner.dart';
import '../domain/youtube_failures.dart';
import '../domain/music_result_classifier.dart';
import '../../search/domain/search_deduplicator.dart';
import '../../search/domain/artist_classifier.dart';
import '../../search/domain/online_playlist.dart';
import '../../onboarding/domain/artist_model.dart';
import '../../recommendations/domain/music_language_service.dart';
import 'youtube_data_source.dart';
import 'web_music_discovery_source.dart';

/// Repository responsible for searching YouTube via YouTube Data API v3,
/// falling back to WebMusicDiscoverySource on web (to respect browser CORS),
/// or falling back to YoutubeExplode on native platforms when no API key is configured.
class YouTubeRepository {
  final YouTubeDataSource _dataSource;
  final WebMusicDiscoverySource _webDiscoverySource;

  /// In-memory search cache (bounded to 50 queries, keyed lowercase)
  final Map<String, List<YouTubeVideo>> _searchCache = {};
  final Map<String, Future<List<YouTubeVideo>>> _inFlightSearches = {};
  final Map<String, List<ArtistModel>> _artistSearchCache = {};
  final Map<String, List<OnlinePlaylist>> _playlistSearchCache = {};
  final Map<String, List<YouTubeVideo>> _playlistVideosCache = {};
  static const int _maxCacheSize = 50;

  /// Circuit breaker state for structural YoutubeExplode InnerTube parse failures
  /// (e.g. NoSuchMethodError: getT). Transient network errors do not trip it.
  final Duration explodeCircuitCooldown;
  final DateTime Function() _now;
  final Future<List<YouTubeVideo>> Function(String query, {int page})?
      _explodeSearchOverride;
  DateTime? _explodeCircuitOpenUntil;

  /// Whether the YoutubeExplode search circuit breaker is currently open.
  bool get isExplodeCircuitOpen =>
      _explodeCircuitOpenUntil != null &&
      _now().isBefore(_explodeCircuitOpenUntil!);

  /// Active search lists to support continuous pagination across batches
  final Map<String, yte.VideoSearchList> _activeSearchLists = {};
  yte.YoutubeExplode? _sharedYt;
  yte.YoutubeExplode get _yt => _sharedYt ??= yte.YoutubeExplode();

  YouTubeRepository({
    YouTubeDataSource? dataSource,
    WebMusicDiscoverySource? webDiscoverySource,
    this.explodeCircuitCooldown = const Duration(minutes: 5),
    DateTime Function()? now,
    Future<List<YouTubeVideo>> Function(String query, {int page})?
        explodeSearchOverride,
  })  : _dataSource = dataSource ?? YouTubeDataSource(),
        _webDiscoverySource = webDiscoverySource ?? WebMusicDiscoverySource(),
        _now = now ?? DateTime.now,
        _explodeSearchOverride = explodeSearchOverride;

  /// Searches for music tracks matching [query].
  ///
  /// Supports progressive pagination via [page]:
  /// - page 1 checks in-memory cache or performs initial search.
  /// - page > 1 advances pagination via [SearchList.nextPage] or query continuation variants,
  ///   bypassing the initial page-1 cache.
  Future<List<YouTubeVideo>> search(
    String query, {
    int page = 1,
    bool forceFresh = false,
    NetworkPriority priority = NetworkPriority.userSearch,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final normQuery = cleanQuery.toLowerCase();
    final cacheKey = page == 1 ? normQuery : '$normQuery:p$page';

    if (!forceFresh && _searchCache.containsKey(cacheKey)) {
      debugPrint('YouTubeRepository: Cache hit for "$cleanQuery" (p$page)');
      final cached = _searchCache[cacheKey]!;
      if (page == 1) {
        final validCached = MusicResultClassifier.filterAndRankMusicTracks(
            cached,
            query: cleanQuery,
            individualOnly: true);
        if (validCached.isNotEmpty) {
          return validCached;
        }
        _searchCache.remove(cacheKey);
      } else if (cached.isNotEmpty) {
        return cached;
      } else {
        _searchCache.remove(cacheKey);
      }
    }

    if (!forceFresh && _inFlightSearches.containsKey(cacheKey)) {
      return await _inFlightSearches[cacheKey]!;
    }

    final future = NetworkRequestCoordinator.instance.run<List<YouTubeVideo>>(
      () => _executeSearch(cleanQuery, page: page, cacheKey: cacheKey),
      priority: priority,
    );
    _inFlightSearches[cacheKey] = future;

    try {
      return await future;
    } finally {
      _inFlightSearches.remove(cacheKey);
    }
  }

  Future<List<YouTubeVideo>> _executeSearch(
    String cleanQuery, {
    required int page,
    required String cacheKey,
  }) async {
    List<YouTubeVideo> results = [];

    // 1. Primary: YouTube Data API v3 if configured
    if (_dataSource.isConfigured) {
      try {
        debugPrint(
            'YouTubeRepository: Searching YouTube Data API v3 for "$cleanQuery" (p$page)');
        results = await _searchWithDataApi(cleanQuery);
      } catch (e) {
        debugPrint(
            'YouTubeRepository: Data API search failed ($e), falling back to alternative discovery');
        results = [];
      }
    }

    // 2. Secondary: WebMusicDiscoverySource on web (CORS-safe) or YoutubeExplode on native
    if (results.isEmpty) {
      if (kIsWeb) {
        debugPrint(
            '[YouTubeRepository] Web environment detected. Direct browser scraping of youtube.com is restricted by browser CORS policy.');
        try {
          debugPrint(
              '[YouTubeRepository] Querying WebMusicDiscoverySource for "$cleanQuery"');
          results = await _webDiscoverySource.searchVideos(cleanQuery);
        } catch (e) {
          debugPrint(
              '[YouTubeRepository] WebMusicDiscoverySource search failed ($e)');
          throw YouTubeSearchFailure(
              'Web music discovery failed for "$cleanQuery": $e');
        }
      } else {
        final bypassExplode = isExplodeCircuitOpen;
        if (bypassExplode) {
          debugPrint(
              '[YouTubeRepository] Explode circuit open; bypassing to WebMusicDiscoverySource for "$cleanQuery"');
        } else {
          if (_explodeCircuitOpenUntil != null) {
            // Cooldown expired: allow controlled retry
            _explodeCircuitOpenUntil = null;
          }
          try {
            debugPrint(
                'YouTubeRepository: Searching YouTube via YoutubeExplode for "$cleanQuery" (p$page)');
            results = await _searchWithExplode(cleanQuery, page: page);
          } catch (e, stack) {
            debugPrint('YouTubeRepository: YoutubeExplode search failed ($e)');
            if (kDebugMode) debugPrintStack(stackTrace: stack);
          }
        }

        // Fallback to WebMusicDiscoverySource if Explode returned 0 candidates or circuit is open
        if (results.isEmpty) {
          try {
            debugPrint(
                'YouTubeRepository: Falling back to WebMusicDiscoverySource for "$cleanQuery"');
            results = await _webDiscoverySource.searchVideos(cleanQuery);
          } catch (e) {
            debugPrint(
                'YouTubeRepository: WebMusicDiscoverySource fallback failed: $e');
          }
        }
      }
    }

    // Filter out non-music entertainment and prioritize verified music releases
    final validResults = MusicResultClassifier.filterAndRankMusicTracks(results,
        query: cleanQuery, individualOnly: true);

    if (validResults.isNotEmpty) {
      if (_searchCache.length >= _maxCacheSize) {
        _searchCache.remove(_searchCache.keys.first);
      }
      _searchCache[cacheKey] = validResults;
    }

    return validResults;
  }

  /// Fetches an un-exhausted batch of verified music tracks for [artistName].
  ///
  /// Supports progressive pagination via [page]. Each subsequent page
  /// retrieves fresh tracks via provider continuation or curated artist discovery
  /// without repeating the initial 15 songs.
  Future<List<YouTubeVideo>> getArtistTracks(
    String artistName, {
    int page = 1,
    int limit = 15,
    List<String> preferredLanguages = const [],
  }) async {
    final cleanArtist = artistName.trim();
    if (cleanArtist.isEmpty) return const [];

    final candidateVideos = <YouTubeVideo>[];
    final topLang =
        preferredLanguages.isNotEmpty ? preferredLanguages.first : null;

    // 1. Language-targeted query on page 1 if artist is known to perform in preferred language
    if (page == 1 &&
        topLang != null &&
        MusicLanguageService.isArtistMultilingualInLang(cleanArtist, topLang)) {
      final langVideos = await search('$cleanArtist $topLang songs', page: 1);
      candidateVideos.addAll(langVideos);
    }

    // 2. Fetch page of artist songs
    final mainVideos =
        await search('$cleanArtist songs', page: page, forceFresh: page > 1);
    candidateVideos.addAll(mainVideos);

    // 3. If page > 1, filter out tracks already returned in earlier pages for this artist
    List<YouTubeVideo> filteredCandidates = candidateVideos;
    if (page > 1) {
      final priorIds = <String>{};
      for (int p = 1; p < page; p++) {
        final priorKey = '$cleanArtist songs:p$p';
        final priorList = _searchCache[priorKey] ??
            (p == 1 ? _searchCache['$cleanArtist songs'] : null);
        if (priorList != null) {
          priorIds.addAll(priorList.map((v) => v.id));
        }
      }
      if (priorIds.isNotEmpty) {
        filteredCandidates =
            candidateVideos.where((v) => !priorIds.contains(v.id)).toList();
      }
    }

    // 4. If page > 1 and candidate count is small, supplement with query variant
    if (page > 1 && filteredCandidates.length < (limit ~/ 2)) {
      final variantQuery = _getQueryVariantForPage(cleanArtist, page);
      final variantVideos = await search(variantQuery, page: 1);
      filteredCandidates.addAll(variantVideos);
    }

    // Deduplicate and rank for this artist
    final deduplicated = SearchDeduplicator.deduplicateAndRank(
      filteredCandidates,
      query: cleanArtist,
      config: const SearchRankingConfig(filterDerivativeEdits: true),
    );

    return deduplicated.take(limit).toList();
  }

  /// Fetches diverse, high-relevance upcoming tracks seeded by [seedVideo].
  ///
  /// Excludes the seed track itself and any redundant uploads of the same canonical song.
  /// Deduplicates upcoming recommendations so the user receives a varied listening queue.
  Future<List<YouTubeVideo>> getRelatedTracks(
    YouTubeVideo seedVideo, {
    int limit = 15,
  }) async {
    final candidateTracks = <YouTubeVideo>[];

    // 1. Primary: Try YouTubeExplode getRelatedVideos on native platforms
    if (!kIsWeb) {
      final yt = yte.YoutubeExplode();
      try {
        final video = await yt.videos.get(seedVideo.id);
        final related = await yt.videos.getRelatedVideos(video);
        if (related != null && related.isNotEmpty) {
          for (final rel in related) {
            final relId = rel.id.value;
            if (relId.isEmpty || relId == seedVideo.id) continue;

            final durationStr = rel.duration != null
                ? '${rel.duration!.inMinutes}:${(rel.duration!.inSeconds % 60).toString().padLeft(2, '0')}'
                : '';

            final cleaned = YouTubeMetadataCleaner.clean(
              rawTitle: rel.title,
              rawChannel: rel.author,
            );

            final candidate = YouTubeVideo(
              id: relId,
              title: cleaned.title,
              channelTitle: cleaned.artist,
              thumbnailUrl: rel.thumbnails.highResUrl.isNotEmpty
                  ? rel.thumbnails.highResUrl
                  : (rel.thumbnails.mediumResUrl.isNotEmpty
                      ? rel.thumbnails.mediumResUrl
                      : 'https://i.ytimg.com/vi/$relId/hqdefault.jpg'),
              duration: durationStr,
              viewCount: _formatViewCount(rel.engagement.viewCount),
              rawTitle: rel.title,
              rawChannelTitle: rel.author,
              rawViewCount: rel.engagement.viewCount,
            );

            if (MusicResultClassifier.isValidIndividualSong(candidate)) {
              candidateTracks.add(candidate);
            }
          }
        }
      } catch (e) {
        debugPrint(
            '[YouTubeRepository] getRelatedVideos failed ($e), proceeding to query-based discovery');
      } finally {
        yt.close();
      }
    }

    // 2. Secondary fallback: Search for related music by artist if we need more candidates.
    // Strictly do NOT search for the song title alone, as that returns unrelated songs by different artists.
    if (candidateTracks.length < 5) {
      try {
        final artistQuery = seedVideo.channelTitle.isNotEmpty
            ? seedVideo.channelTitle
            : seedVideo.artist;
        if (artistQuery.isNotEmpty) {
          final query = '$artistQuery songs';
          final searchResults = await search(query);
          candidateTracks.addAll(searchResults);
        }
      } catch (e) {
        debugPrint('[YouTubeRepository] Related search fallback failed: $e');
      }
    }

    final seedBaseTitle = SearchDeduplicator.normalizeBaseTitle(
      seedVideo.title,
      rawTitle: seedVideo.rawTitle,
      artist: seedVideo.channelTitle,
    ).toLowerCase().trim();
    final seedArtistNorm = SearchDeduplicator.normalizeArtist(
      seedVideo.channelTitle.isNotEmpty
          ? seedVideo.channelTitle
          : seedVideo.artist,
    );

    // 3. Filter out the seed track, duplicate uploads, and any different artists' tracks merely sharing the title
    final filtered = candidateTracks.where((track) {
      if (track.id == seedVideo.id) return false;
      if (SearchDeduplicator.isSameCanonicalSong(track, seedVideo))
        return false;
      if (!MusicResultClassifier.isValidMusicTrack(track)) return false;

      // Do NOT add different artists' tracks merely because they share the selected track's title
      final trackBaseTitle = SearchDeduplicator.normalizeBaseTitle(
        track.title,
        rawTitle: track.rawTitle,
        artist: track.channelTitle,
      ).toLowerCase().trim();
      final trackArtistNorm = SearchDeduplicator.normalizeArtist(
        track.channelTitle.isNotEmpty ? track.channelTitle : track.artist,
      );
      if (seedBaseTitle.isNotEmpty &&
          trackBaseTitle == seedBaseTitle &&
          trackArtistNorm != seedArtistNorm) {
        return false;
      }

      // Exclude derivative edits (karaoke, slowed+reverb, sped up, bass boosted, compilation mix)
      final intent = QueryIntent.fromQuery(seedVideo.channelTitle.isNotEmpty
          ? seedVideo.channelTitle
          : seedVideo.artist);
      final editType = SearchDeduplicator.detectEditType(track, intent);
      if (editType == EditType.karaokeVersion ||
          editType == EditType.slowedReverb ||
          editType == EditType.spedUpNightcore ||
          editType == EditType.audioModified ||
          editType == EditType.compilationMix ||
          editType == EditType.coverSong) {
        return false;
      }

      // Exclude non-music broadcast networks, TV channels, serial promos
      final chLower =
          (track.rawChannelTitle ?? track.channelTitle).toLowerCase();
      if (chLower.contains('sun tv') ||
          chLower.contains('globtamil') ||
          chLower.contains('zee tv') ||
          chLower.contains('vijay tv') ||
          chLower.contains('polimer') ||
          chLower.contains('etv') ||
          chLower.contains('colorstv') ||
          chLower.contains('news')) {
        return false;
      }

      return true;
    }).toList();

    // 4. Run deduplication on upcoming candidates so Next Up itself contains distinct songs
    final deduplicated = SearchDeduplicator.deduplicateAndRank(
      filtered,
      query: seedVideo.channelTitle.isNotEmpty
          ? seedVideo.channelTitle
          : seedVideo.title,
      config: const SearchRankingConfig(filterDerivativeEdits: true),
    );

    return deduplicated.take(limit).toList();
  }

  Future<List<YouTubeVideo>> _searchWithExplode(String cleanQuery,
      {int page = 1}) async {
    if (_explodeSearchOverride != null) {
      try {
        return await _explodeSearchOverride!(cleanQuery, page: page);
      } catch (e) {
        if (e is NoSuchMethodError || e is TypeError || e is FormatException) {
          _explodeCircuitOpenUntil = _now().add(explodeCircuitCooldown);
          debugPrint(
              '[YouTubeRepository] Structural Explode failure ($e); circuit open for ${explodeCircuitCooldown.inSeconds}s');
        } else {
          debugPrint('[YouTubeRepository] _searchWithExplode transient error: $e');
        }
        return const [];
      }
    }

    final candidateVideos = <YouTubeVideo>[];
    final seenVideoIds = <String>{};

    try {
      if (page <= 1) {
        final searchList = await _yt.search.search(cleanQuery);
        _activeSearchLists[cleanQuery] = searchList;

        for (final video in searchList) {
          if (video.id.value.isEmpty || !seenVideoIds.add(video.id.value))
            continue;
          final candidate = _processVideo(video, cleanQuery);
          if (MusicResultClassifier.isValidMusicTrack(candidate,
              query: cleanQuery)) {
            candidateVideos.add(candidate);
          }
        }
      } else {
        // Page > 1 continuation:
        if (_activeSearchLists.containsKey(cleanQuery)) {
          try {
            final nextList = await _activeSearchLists[cleanQuery]!.nextPage();
            if (nextList != null && nextList.isNotEmpty) {
              _activeSearchLists[cleanQuery] = nextList;
              for (final video in nextList) {
                if (video.id.value.isEmpty || !seenVideoIds.add(video.id.value))
                  continue;
                final candidate = _processVideo(video, cleanQuery);
                if (MusicResultClassifier.isValidMusicTrack(candidate,
                    query: cleanQuery)) {
                  candidateVideos.add(candidate);
                }
              }
            }
          } catch (e) {
            debugPrint('[YouTubeRepository] Pagination nextPage() error: $e');
          }
        }

        // If pagination list was empty or exhausted, use query variant
        if (candidateVideos.isEmpty) {
          final variantQuery = _getQueryVariantForPage(cleanQuery, page);
          debugPrint(
              '[YouTubeRepository] Using continuation query variant: "$variantQuery"');
          final variantList = await _yt.search.search(variantQuery);
          for (final video in variantList) {
            if (video.id.value.isEmpty || !seenVideoIds.add(video.id.value))
              continue;
            final candidate = _processVideo(video, variantQuery);
            if (MusicResultClassifier.isValidMusicTrack(candidate,
                query: variantQuery)) {
              candidateVideos.add(candidate);
            }
          }
        }
      }
    } catch (e) {
      if (e is NoSuchMethodError || e is TypeError || e is FormatException) {
        _explodeCircuitOpenUntil = _now().add(explodeCircuitCooldown);
        debugPrint(
            '[YouTubeRepository] Structural Explode parse error ($e); opening circuit for ${explodeCircuitCooldown.inSeconds}s');
      } else {
        debugPrint('[YouTubeRepository] _searchWithExplode error: $e');
      }
    }

    return candidateVideos;
  }

  YouTubeVideo _processVideo(yte.Video video, String cleanQuery) {
    final videoId = video.id.value;
    final title = video.title;
    final channelTitle = video.author;
    final channelId = video.channelId.value;

    final durationStr = video.duration != null
        ? '${video.duration!.inMinutes}:${(video.duration!.inSeconds % 60).toString().padLeft(2, '0')}'
        : '';

    final rawViews = video.engagement.viewCount;
    final viewCountStr = _formatViewCount(rawViews);

    String thumbnailUrl = video.thumbnails.highResUrl;
    if (thumbnailUrl.isEmpty) {
      thumbnailUrl = video.thumbnails.mediumResUrl;
    }
    if (thumbnailUrl.isEmpty) {
      thumbnailUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    }

    final cleaned = YouTubeMetadataCleaner.clean(
      rawTitle: title,
      rawChannel: channelTitle,
    );

    return YouTubeVideo(
      id: videoId,
      title: cleaned.title,
      channelTitle: cleaned.artist,
      thumbnailUrl: thumbnailUrl,
      duration: durationStr,
      viewCount: viewCountStr,
      rawTitle: title,
      rawChannelTitle: channelTitle,
      rawViewCount: rawViews,
      channelId: channelId.isNotEmpty ? channelId : null,
    );
  }

  String _getQueryVariantForPage(String query, int page) {
    final clean = query
        .replaceAll(' songs', '')
        .replaceAll(' song', '')
        .replaceAll(' tracks', '')
        .trim();
    switch (page) {
      case 2:
        return '$clean top hits';
      case 3:
        return '$clean popular songs';
      case 4:
        return '$clean albums songs';
      case 5:
        return '$clean discography';
      case 6:
        return '$clean official audio';
      default:
        return '$clean hit tracks';
    }
  }

  Future<List<YouTubeVideo>> _searchWithDataApi(String cleanQuery) async {
    final rawItems = await _dataSource.searchVideos(cleanQuery, maxResults: 35);
    if (rawItems.isEmpty) return [];

    // Extract video IDs to fetch duration & statistics
    final videoIds = <String>[];
    for (final item in rawItems) {
      final idObj = item['id'];
      if (idObj is Map && idObj['kind'] == 'youtube#video') {
        final videoId = idObj['videoId'] as String?;
        if (videoId != null && videoId.isNotEmpty) {
          videoIds.add(videoId);
        }
      }
    }

    // Fetch details (duration & stats)
    final detailsMap = await _dataSource.getVideoDetails(videoIds);

    final excludedKeywords = [
      'live',
      'livestream',
      'podcast',
      'interview',
      'full movie',
      'documentary',
      'compilation',
      'reaction',
      'karaoke',
      '8d',
      'lyrics',
    ];

    final candidateVideos = <YouTubeVideo>[];

    for (final item in rawItems) {
      final idObj = item['id'];
      if (idObj is! Map || idObj['kind'] != 'youtube#video') continue;
      final videoId = idObj['videoId'] as String?;
      if (videoId == null || videoId.isEmpty) continue;

      final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
      final title = snippet['title'] as String? ?? '';
      final channelTitle = snippet['channelTitle'] as String? ?? '';
      final description = snippet['description'] as String? ?? '';
      final liveBroadcast =
          snippet['liveBroadcastContent'] as String? ?? 'none';

      // 1. Exclude live streams
      if (liveBroadcast != 'none') continue;

      // 2. Exclude non-music keyword matches
      final titleLower = title.toLowerCase();
      final channelLower = channelTitle.toLowerCase();
      final descLower = description.toLowerCase();

      final hasExcluded = excludedKeywords.any((kw) =>
          titleLower.contains(kw) ||
          channelLower.contains(kw) ||
          descLower.contains(kw));

      if (hasExcluded) continue;

      // Extract thumbnails
      final thumbnails = snippet['thumbnails'] as Map<String, dynamic>? ?? {};
      String thumbnailUrl = '';
      if (thumbnails['high'] != null) {
        thumbnailUrl = thumbnails['high']['url'] as String? ?? '';
      } else if (thumbnails['medium'] != null) {
        thumbnailUrl = thumbnails['medium']['url'] as String? ?? '';
      } else if (thumbnails['default'] != null) {
        thumbnailUrl = thumbnails['default']['url'] as String? ?? '';
      }
      if (thumbnailUrl.isEmpty) {
        thumbnailUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
      }

      // Details metadata
      final detail = detailsMap[videoId];
      String durationStr = '';
      String viewCountStr = '';
      int? viewsRaw;

      if (detail != null) {
        final contentDetails =
            detail['contentDetails'] as Map<String, dynamic>?;
        final statistics = detail['statistics'] as Map<String, dynamic>?;

        if (contentDetails != null) {
          final isoDuration = contentDetails['duration'] as String?;
          durationStr = _parseIso8601Duration(isoDuration);
        }

        if (statistics != null) {
          viewsRaw = int.tryParse(statistics['viewCount'] as String? ?? '');
          if (viewsRaw != null) {
            viewCountStr = _formatViewCount(viewsRaw);
          }
        }
      }

      final cleaned = YouTubeMetadataCleaner.clean(
        rawTitle: title,
        rawChannel: channelTitle,
      );

      final candidate = YouTubeVideo(
        id: videoId,
        title: cleaned.title,
        channelTitle: cleaned.artist,
        thumbnailUrl: thumbnailUrl,
        duration: durationStr,
        viewCount: viewCountStr,
        rawTitle: title,
        rawChannelTitle: channelTitle,
        rawViewCount: viewsRaw,
        channelId: snippet['channelId'] as String?,
      );

      if (MusicResultClassifier.isValidMusicTrack(candidate,
          query: cleanQuery)) {
        candidateVideos.add(candidate);
      }
    }

    // Heuristic scoring to prioritize official audio / releases
    int calculateScore(YouTubeVideo video) {
      int score = 0;
      final titleLower = video.title.toLowerCase();
      final channelLower = video.channelTitle.toLowerCase();

      if (channelLower.contains('- topic')) score += 100;
      if (channelLower.contains('vevo')) score += 90;
      if (channelLower.contains('official')) score += 50;

      if (titleLower.contains('official audio')) score += 80;
      if (titleLower.contains('official music video') ||
          titleLower.contains('official video')) score += 75;
      if (titleLower.contains('music video') || titleLower.contains('mv'))
        score += 40;
      if (titleLower.contains('audio')) score += 30;

      return score;
    }

    candidateVideos
        .sort((a, b) => calculateScore(b).compareTo(calculateScore(a)));
    return candidateVideos;
  }

  String _parseIso8601Duration(String? isoDuration) {
    if (isoDuration == null || isoDuration.isEmpty) return '0:00';
    final regex = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?');
    final match = regex.firstMatch(isoDuration);
    if (match == null) return '0:00';

    final hours = int.tryParse(match.group(1) ?? '') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '') ?? 0;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatViewCount(int views) {
    if (views >= 1000000000) {
      return '${(views / 1000000000).toStringAsFixed(1)}B views';
    } else if (views >= 1000000) {
      return '${(views / 1000000).toStringAsFixed(1)}M views';
    } else if (views >= 1000) {
      return '${(views / 1000).toStringAsFixed(0)}K views';
    }
    return '$views views';
  }

  /// Fetches online search query suggestions via YoutubeExplode.
  Future<List<String>> getSuggestions(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];
    try {
      return await _yt.search.getQuerySuggestions(cleanQuery);
    } catch (e) {
      debugPrint('YouTubeRepository: Failed to fetch query suggestions: $e');
      return const [];
    }
  }

  /// Searches for verified artist / channel entities matching [query].
  Future<List<ArtistModel>> searchArtists(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    final cacheKey = cleanQuery.toLowerCase();
    if (_artistSearchCache.containsKey(cacheKey)) {
      return _artistSearchCache[cacheKey]!;
    }

    final candidates = <ArtistModel>[];

    // 1. Primary: YouTube Data API v3 if configured
    if (_dataSource.isConfigured) {
      try {
        final rawChannels = await _dataSource.searchChannels(cleanQuery);
        for (final item in rawChannels) {
          final idObj = item['id'];
          final channelId =
              (idObj is Map ? idObj['channelId'] : null) as String?;
          if (channelId == null || channelId.isEmpty) continue;

          final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
          final rawTitle = snippet['title'] as String? ?? '';
          if (isExcludedArtistChannel(rawTitle, cleanQuery)) continue;

          final cleanName = cleanArtistName(rawTitle);
          final thumbnails =
              snippet['thumbnails'] as Map<String, dynamic>? ?? {};
          String imgUrl = '';
          if (thumbnails['high'] != null) {
            imgUrl = thumbnails['high']['url'] as String? ?? '';
          } else if (thumbnails['medium'] != null) {
            imgUrl = thumbnails['medium']['url'] as String? ?? '';
          } else if (thumbnails['default'] != null) {
            imgUrl = thumbnails['default']['url'] as String? ?? '';
          }

          candidates.add(
            ArtistModel(
              id: channelId,
              name: cleanName,
              imageUrl: normalizeImageUrl(imgUrl),
            ),
          );
        }
      } catch (e) {
        debugPrint('YouTubeRepository: Data API searchChannels error: $e');
      }
    }

    // 2. Secondary: YoutubeExplode on native platforms
    if (candidates.isEmpty && !kIsWeb) {
      try {
        final searchResults = await _yt.search.searchContent(
          cleanQuery,
          filter: yte.TypeFilters.channel,
        );

        for (final item in searchResults) {
          if (item is yte.SearchChannel) {
            final rawName = item.name.trim();
            if (isExcludedArtistChannel(rawName, cleanQuery)) continue;

            final cleanName = cleanArtistName(rawName);
            String imgUrl = '';
            for (final t in item.thumbnails) {
              if (t.url.toString().isNotEmpty) {
                imgUrl = t.url.toString();
              }
            }

            candidates.add(
              ArtistModel(
                id: item.id.value,
                name: cleanName,
                imageUrl: normalizeImageUrl(imgUrl),
              ),
            );
          }
        }
      } catch (e) {
        debugPrint(
            'YouTubeRepository: YoutubeExplode searchChannels error: $e');
      }
    }

    final deduped = _deduplicateArtistEntities(candidates);

    if (deduped.isNotEmpty) {
      if (_artistSearchCache.length >= _maxCacheSize) {
        _artistSearchCache.remove(_artistSearchCache.keys.first);
      }
      _artistSearchCache[cacheKey] = deduped;
    }

    return deduped;
  }

  static bool isExcludedArtistChannel(String rawName, String query) {
    if (!ArtistClassifier.isLegitimateMusicArtist(rawName, query: query)) {
      return true;
    }

    final lower = rawName.toLowerCase();
    final queryLower = query.toLowerCase();

    // Canonical artist search exclusions (fan channels, lyric uploaders, status edits)
    final excludedKeywords = [
      'fanpage',
      'fan page',
      'fan club',
      'fans club',
      'fangirl',
      'fangurl',
      'fanbase',
      'fp',
      'lyrics',
      'lyric',
      'edits',
      'edit',
      'status',
      'tribute',
      'all india',
      'official fan',
      'unofficial',
      'reaction',
      'hub',
    ];

    for (final kw in excludedKeywords) {
      if (!queryLower.contains(kw) && lower.contains(kw)) {
        return true;
      }
    }

    return false;
  }

  static String cleanArtistName(String rawName) {
    var name = rawName.trim();
    // Strip YouTube Music Topic channel indicator
    name =
        name.replaceFirst(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '');
    // Strip leading @ handle indicator
    if (name.startsWith('@')) {
      name = name.substring(1);
    }
    return name.trim();
  }

  static String normalizeImageUrl(String url) {
    var clean = url.trim();
    if (clean.startsWith('https:https://')) {
      clean = clean.replaceFirst('https:https://', 'https://');
    }
    return clean;
  }

  static List<ArtistModel> _deduplicateArtistEntities(
      List<ArtistModel> candidates) {
    final seenIds = <String>{};
    final seenNames = <String>{};
    final result = <ArtistModel>[];

    for (final artist in candidates) {
      if (artist.id.isEmpty) continue;
      final normName =
          artist.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (seenIds.add(artist.id) &&
          (normName.isEmpty || seenNames.add(normName))) {
        result.add(artist);
      }
    }

    return result;
  }

  /// Searches for playlists matching [query].
  Future<List<OnlinePlaylist>> searchPlaylists(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    final cacheKey = cleanQuery.toLowerCase();
    if (_playlistSearchCache.containsKey(cacheKey)) {
      return _playlistSearchCache[cacheKey]!;
    }

    final playlists = <OnlinePlaylist>[];

    if (!kIsWeb) {
      try {
        final searchResults = await _yt.search.searchContent(
          cleanQuery,
          filter: yte.TypeFilters.playlist,
        );

        for (final item in searchResults) {
          if (item is yte.SearchPlaylist) {
            String thumb = '';
            if (item.thumbnails.isNotEmpty) {
              thumb = item.thumbnails.last.url.toString();
            }
            playlists.add(
              OnlinePlaylist(
                id: item.id.value,
                title: item.title,
                author: 'Playlist',
                thumbnailUrl: normalizeImageUrl(thumb),
                trackCount: item.videoCount,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('YouTubeRepository: searchPlaylists error: $e');
      }
    }

    if (playlists.isNotEmpty) {
      if (_playlistSearchCache.length >= _maxCacheSize) {
        _playlistSearchCache.remove(_playlistSearchCache.keys.first);
      }
      _playlistSearchCache[cacheKey] = playlists;
    }

    return playlists;
  }

  /// Fetches the actual videos belonging to an online YouTube playlist.
  ///
  /// Queries YouTube Music Innertube (`WEB_REMIX`) for verified tracks, titles,
  /// artists, durations, and playable video IDs, with fallback to Explode.
  Future<List<YouTubeVideo>> getPlaylistVideos(
    String playlistId, {
    int limit = 50,
  }) async {
    final cleanId = playlistId.trim();
    if (cleanId.isEmpty) return const [];

    if (_playlistVideosCache.containsKey(cleanId)) {
      return _playlistVideosCache[cleanId]!;
    }

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
      ),
    );

    try {
      final browseId = cleanId.startsWith('VL') ? cleanId : 'VL$cleanId';
      final response = await dio.post<dynamic>(
        'https://music.youtube.com/youtubei/v1/browse',
        data: {
          'context': {
            'client': {
              'clientName': 'WEB_REMIX',
              'clientVersion': '1.20240101.01.00',
              'hl': 'en',
              'gl': 'US',
            }
          },
          'browseId': browseId,
        },
        options: Options(headers: {
          'Content-Type': 'application/json',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        }),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        final items = <Map<String, dynamic>>[];
        void scan(dynamic obj) {
          if (obj is Map<String, dynamic>) {
            if (obj.containsKey('musicResponsiveListItemRenderer')) {
              items.add(obj['musicResponsiveListItemRenderer'] as Map<String, dynamic>);
            }
            for (final v in obj.values) {
              scan(v);
            }
          } else if (obj is List) {
            for (final item in obj) {
              scan(item);
            }
          }
        }

        scan(data);

        final videos = <YouTubeVideo>[];
        for (final item in items) {
          final flexCols = item['flexColumns'] as List?;
          String? title;
          String? artist;
          if (flexCols != null && flexCols.isNotEmpty) {
            final col0 = flexCols[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
            if (col0 != null && col0 is List && col0.isNotEmpty) {
              title = col0[0]?['text']?.toString();
            }
            if (flexCols.length > 1) {
              final col1 = flexCols[1]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs'];
              if (col1 != null && col1 is List && col1.isNotEmpty) {
                artist = col1.map((r) => r['text']).join('');
              }
            }
          }

          final fixedCols = item['fixedColumns'] as List?;
          String? duration;
          if (fixedCols != null && fixedCols.isNotEmpty) {
            final col0 = fixedCols[0]?['musicResponsiveListItemFixedColumnRenderer']?['text']?['runs'];
            if (col0 != null && col0 is List && col0.isNotEmpty) {
              duration = col0[0]?['text']?.toString();
            }
          }

          final playlistItemData = item['playlistItemData'];
          final videoId = playlistItemData?['videoId']?.toString() ??
              item['doubleTapCommand']?['watchEndpoint']?['videoId']?.toString();

          if (videoId != null && videoId.isNotEmpty && title != null && title.isNotEmpty) {
            final cleaned = YouTubeMetadataCleaner.clean(
              rawTitle: title,
              rawChannel: artist ?? '',
            );

            final video = YouTubeVideo(
              id: videoId,
              title: cleaned.title,
              channelTitle: cleaned.artist,
              thumbnailUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
              duration: duration ?? '',
              viewCount: 'YouTube Music',
              rawTitle: title,
              rawChannelTitle: artist ?? '',
              canonicalTitle: cleaned.title,
              canonicalArtist: cleaned.artist,
            );
            videos.add(video);
            if (videos.length >= limit) break;
          }
        }

        if (videos.isNotEmpty) {
          if (_playlistVideosCache.length >= _maxCacheSize) {
            _playlistVideosCache.remove(_playlistVideosCache.keys.first);
          }
          _playlistVideosCache[cleanId] = videos;
          return videos;
        }
      }
    } catch (e) {
      debugPrint('[YouTubeRepository] getPlaylistVideos Innertube error: $e');
    }

    // Fallback: Explode playlist stream if Innertube did not yield results
    if (!kIsWeb) {
      try {
        final videos = <YouTubeVideo>[];
        final stream = _yt.playlists.getVideos(cleanId);
        await for (final video in stream.take(limit)) {
          videos.add(_processVideo(video, ''));
        }
        if (videos.isNotEmpty) {
          if (_playlistVideosCache.length >= _maxCacheSize) {
            _playlistVideosCache.remove(_playlistVideosCache.keys.first);
          }
          _playlistVideosCache[cleanId] = videos;
          return videos;
        }
      } catch (e) {
        debugPrint('[YouTubeRepository] getPlaylistVideos Explode error: $e');
      }
    }

    return const [];
  }

  void clearCache() {
    _searchCache.clear();
    _artistSearchCache.clear();
    _playlistSearchCache.clear();
    _playlistVideosCache.clear();
    _activeSearchLists.clear();
  }
}
