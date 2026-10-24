import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yte;
import '../domain/youtube_model.dart';
import '../domain/youtube_metadata_cleaner.dart';
import '../domain/youtube_failures.dart';
import '../../search/domain/search_deduplicator.dart';
import '../../onboarding/domain/artist_model.dart';
import 'youtube_data_source.dart';
import 'web_music_discovery_source.dart';

/// Repository responsible for searching YouTube via YouTube Data API v3,
/// falling back to WebMusicDiscoverySource on web (to respect browser CORS),
/// or falling back to YoutubeExplode on native platforms when no API key is configured.
class YouTubeRepository {
  final YouTubeDataSource _dataSource;
  final WebMusicDiscoverySource _webDiscoverySource;

  /// In-memory search cache (bounded to 50 queries)
  final Map<String, List<YouTubeVideo>> _searchCache = {};
  final Map<String, List<ArtistModel>> _artistSearchCache = {};
  static const int _maxCacheSize = 50;

  YouTubeRepository({
    YouTubeDataSource? dataSource,
    WebMusicDiscoverySource? webDiscoverySource,
  })  : _dataSource = dataSource ?? YouTubeDataSource(),
        _webDiscoverySource = webDiscoverySource ?? WebMusicDiscoverySource();

  /// Searches for music tracks matching [query].
  Future<List<YouTubeVideo>> search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    if (_searchCache.containsKey(cleanQuery)) {
      debugPrint('YouTubeRepository: Cache hit for "$cleanQuery"');
      return _searchCache[cleanQuery]!;
    }

    List<YouTubeVideo> results = [];

    // 1. Primary: YouTube Data API v3 if configured
    if (_dataSource.isConfigured) {
      try {
        debugPrint('YouTubeRepository: Searching YouTube Data API v3 for "$cleanQuery"');
        results = await _searchWithDataApi(cleanQuery);
      } catch (e) {
        debugPrint('YouTubeRepository: Data API search failed ($e), falling back to alternative discovery');
        results = [];
      }
    }

    // 2. Secondary: WebMusicDiscoverySource on web (CORS-safe) or YoutubeExplode on native
    if (results.isEmpty) {
      if (kIsWeb) {
        debugPrint('[YouTubeRepository] Web environment detected. Direct browser scraping of youtube.com is restricted by browser CORS policy.');
        try {
          debugPrint('[YouTubeRepository] Querying WebMusicDiscoverySource for "$cleanQuery"');
          results = await _webDiscoverySource.searchVideos(cleanQuery);
        } catch (e) {
          debugPrint('[YouTubeRepository] WebMusicDiscoverySource search failed ($e)');
          throw YouTubeSearchFailure('Web music discovery failed for "$cleanQuery": $e');
        }
      } else {
        try {
          debugPrint('YouTubeRepository: Searching YouTube via YoutubeExplode for "$cleanQuery"');
          results = await _searchWithExplode(cleanQuery);
        } catch (e, stack) {
          debugPrint('YouTubeRepository: YoutubeExplode search failed ($e)');
          if (kDebugMode) debugPrintStack(stackTrace: stack);
          // Fallback to WebMusicDiscoverySource on native if explode fails
          try {
            debugPrint('YouTubeRepository: Falling back to WebMusicDiscoverySource for "$cleanQuery"');
            results = await _webDiscoverySource.searchVideos(cleanQuery);
          } catch (_) {
            rethrow;
          }
        }
      }
    }

    if (results.isNotEmpty) {
      if (_searchCache.length >= _maxCacheSize) {
        _searchCache.remove(_searchCache.keys.first);
      }
      _searchCache[cleanQuery] = results;
    }

    return results;
  }

  Future<List<YouTubeVideo>> _searchWithExplode(String cleanQuery) async {
    final yt = yte.YoutubeExplode();
    try {
      final searchList = await yt.search.search(cleanQuery);
      final candidateVideos = <YouTubeVideo>[];

      void processBatch(Iterable<yte.Video> batch) {
        for (final video in batch) {
          final videoId = video.id.value;
          if (videoId.isEmpty) continue;

          final title = video.title;
          final channelTitle = video.author;

          final durationStr = video.duration != null
              ? '${video.duration!.inMinutes}:${(video.duration!.inSeconds % 60).toString().padLeft(2, '0')}'
              : '3:30';

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

          candidateVideos.add(
            YouTubeVideo(
              id: videoId,
              title: cleaned.title,
              channelTitle: cleaned.artist,
              thumbnailUrl: thumbnailUrl,
              duration: durationStr,
              viewCount: viewCountStr,
              rawTitle: title,
              rawChannelTitle: channelTitle,
              rawViewCount: rawViews,
            ),
          );
        }
      }

      processBatch(searchList);

      // Fetch additional candidates if early results contain mostly edits or fewer than 20 candidates
      if (candidateVideos.length < 20 || SearchDeduplicator.hasHighEditRatio(candidateVideos, cleanQuery)) {
        try {
          final nextPage = await searchList.nextPage();
          if (nextPage != null && nextPage.isNotEmpty) {
            processBatch(nextPage);
          }
        } catch (_) {}
      }

      return candidateVideos;
    } finally {
      yt.close();
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
      final liveBroadcast = snippet['liveBroadcastContent'] as String? ?? 'none';

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
      String durationStr = '3:30';
      String viewCountStr = '';
      int? viewsRaw;

      if (detail != null) {
        final contentDetails = detail['contentDetails'] as Map<String, dynamic>?;
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

      candidateVideos.add(
        YouTubeVideo(
          id: videoId,
          title: cleaned.title,
          channelTitle: cleaned.artist,
          thumbnailUrl: thumbnailUrl,
          duration: durationStr,
          viewCount: viewCountStr,
          rawTitle: title,
          rawChannelTitle: channelTitle,
          rawViewCount: viewsRaw,
        ),
      );
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
      if (titleLower.contains('official music video') || titleLower.contains('official video')) score += 75;
      if (titleLower.contains('music video') || titleLower.contains('mv')) score += 40;
      if (titleLower.contains('audio')) score += 30;

      return score;
    }

    candidateVideos.sort((a, b) => calculateScore(b).compareTo(calculateScore(a)));
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
    final yt = yte.YoutubeExplode();
    try {
      return await yt.search.getQuerySuggestions(cleanQuery);
    } catch (e) {
      debugPrint('YouTubeRepository: Failed to fetch query suggestions: $e');
      return const [];
    } finally {
      yt.close();
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
          final channelId = (idObj is Map ? idObj['channelId'] : null) as String?;
          if (channelId == null || channelId.isEmpty) continue;

          final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
          final rawTitle = snippet['title'] as String? ?? '';
          if (isExcludedArtistChannel(rawTitle, cleanQuery)) continue;

          final cleanName = cleanArtistName(rawTitle);
          final thumbnails = snippet['thumbnails'] as Map<String, dynamic>? ?? {};
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
      final yt = yte.YoutubeExplode();
      try {
        final searchResults = await yt.search.searchContent(
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
        debugPrint('YouTubeRepository: YoutubeExplode searchChannels error: $e');
      } finally {
        yt.close();
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
    name = name.replaceFirst(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '');
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

  static List<ArtistModel> _deduplicateArtistEntities(List<ArtistModel> candidates) {
    final seenIds = <String>{};
    final seenNames = <String>{};
    final result = <ArtistModel>[];

    for (final artist in candidates) {
      if (artist.id.isEmpty) continue;
      final normName = artist.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (seenIds.add(artist.id) && (normName.isEmpty || seenNames.add(normName))) {
        result.add(artist);
      }
    }

    return result;
  }

  void clearCache() {
    _searchCache.clear();
    _artistSearchCache.clear();
  }
}
