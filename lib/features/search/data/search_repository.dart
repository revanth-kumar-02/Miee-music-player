import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import '../../../core/storage/hive_boxes.dart';
import '../domain/search_deduplicator.dart';
import '../domain/canonical_music_ranker.dart';
import '../domain/query_relevance_evaluator.dart';
import '../domain/artist_classifier.dart';
import '../domain/online_playlist.dart';
import '../domain/music_suggestion.dart';
import '../../media/domain/models.dart';
import '../../onboarding/data/artist_discovery_repository.dart';
import '../../onboarding/domain/artist_model.dart';
import '../../youtube/domain/youtube_model.dart';
import '../../youtube/domain/music_result_classifier.dart';
import '../../youtube/data/youtube_repository.dart';
import '../../metadata/data/itunes_metadata_service.dart';
import '../../metadata/domain/itunes_song.dart';
import '../../metadata/data/musicbrainz_service.dart';
import '../../metadata/domain/musicbrainz_models.dart';
import 'playback_source_resolver.dart';
import 'local_search_service.dart';

class _CachedSearchResults {
  final List<YouTubeVideo> results;
  final DateTime timestamp;

  const _CachedSearchResults(this.results, this.timestamp);

  bool isExpired(Duration ttl) => DateTime.now().difference(timestamp) > ttl;
}

/// Central search repository orchestrating local fuzzy matches, music-first discovery,
/// online artist discovery, suggestions, and persistent search history in Hive.
class SearchRepository {
  final LocalSearchService localSearch;
  final YouTubeRepository youtubeRepository;
  final ArtistRepository artistRepository;
  final ItunesMetadataService itunesMetadataService;
  final MusicBrainzService musicBrainzService;
  final PlaybackSourceResolver playbackSourceResolver;

  static const Duration _cacheTtl = Duration(minutes: 10);
  static const int _maxCacheEntries = 100;

  /// In-memory LRU cache for online search results with 10-minute TTL.
  final Map<String, _CachedSearchResults> _searchCache = {};
  final Map<String, ({List<ArtistModel> data, DateTime ts})>
      _artistSearchCache = {};
  final Map<String, ({List<ArtistAlbum> data, DateTime ts})> _albumSearchCache =
      {};
  final Map<String, ({List<OnlinePlaylist> data, DateTime ts})>
      _playlistSearchCache = {};

  /// In-flight deduplication to avoid redundant parallel network requests.
  final Map<String, Future<List<YouTubeVideo>>> _inFlightYouTubeSearches = {};
  final Map<String, Future<List<ArtistModel>>> _inFlightArtistSearches = {};
  final Map<String, Future<List<ArtistAlbum>>> _inFlightAlbumSearches = {};
  final Map<String, Future<List<OnlinePlaylist>>> _inFlightPlaylistSearches =
      {};

  SearchRepository({
    LocalSearchService? localSearch,
    YouTubeRepository? youtubeRepository,
    ArtistRepository? artistRepository,
    ItunesMetadataService? itunesMetadataService,
    MusicBrainzService? musicBrainzService,
    PlaybackSourceResolver? playbackSourceResolver,
  })  : localSearch = localSearch ?? LocalSearchService(),
        youtubeRepository = youtubeRepository ?? YouTubeRepository(),
        artistRepository = artistRepository ?? DeezerArtistRepository(),
        itunesMetadataService =
            itunesMetadataService ?? ItunesMetadataService(),
        musicBrainzService = musicBrainzService ?? MusicBrainzService(),
        playbackSourceResolver =
            playbackSourceResolver ?? PlaybackSourceResolver();

  /// Checks if valid unexpired search results are cached for [query].
  bool isCached(String query) {
    final clean = query.trim().toLowerCase();
    final cached = _searchCache[clean];
    return cached != null && !cached.isExpired(_cacheTtl);
  }

  /// Updates or overwrites cached results for [query] (e.g. after background enrichment).
  void updateCachedResults(String query, List<YouTubeVideo> results) {
    final key = query.trim().toLowerCase();
    if (key.isNotEmpty && results.isNotEmpty) {
      _cacheResults(key, results);
    }
  }

  static const String _prefKey = 'youtube_search_history';
  static const int _maxHistory = 10;

  Box<dynamic> get _box => Hive.box<dynamic>(HiveBoxes.preferences);

  /// Load persistent search history.
  List<String> getRecentSearches() {
    try {
      final raw = _box.get(_prefKey);
      if (raw == null) return const [];
      if (raw is List) {
        return raw.whereType<String>().toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Add query to history, maintaining a limit of 10 searches.
  Future<void> addRecentSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final list = List<String>.from(getRecentSearches())
      ..removeWhere((q) => q.toLowerCase() == trimmed.toLowerCase())
      ..insert(0, trimmed);

    if (list.length > _maxHistory) {
      list.removeRange(_maxHistory, list.length);
    }

    await _box.put(_prefKey, list);
  }

  /// Remove single query entry.
  Future<void> removeRecentSearch(String query) async {
    final list = List<String>.from(getRecentSearches())
      ..removeWhere((q) => q == query);
    await _box.put(_prefKey, list);
  }

  /// Destructively clear entire history database.
  Future<void> clearRecentSearches() async {
    await _box.delete(_prefKey);
  }

  /// Performs online YouTube query with caching, in-flight deduplication, and canonical-song ranking.
  ///
  /// Emits ranked results immediately (<800ms) without blocking on external iTunes metadata
  /// enrichment, enabling instantaneous UI rendering and interactive tap responsiveness.
  Future<List<YouTubeVideo>> searchYouTube(
    String query, {
    SearchRankingConfig? config,
    bool enrichSynchronously = false,
    CancelToken? cancelToken,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty || (cancelToken?.isCancelled ?? false)) return const [];
    final cacheKey = clean.toLowerCase();

    // 1. Check in-memory cache
    if (_searchCache.containsKey(cacheKey)) {
      final cached = _searchCache[cacheKey]!;
      if (!cached.isExpired(_cacheTtl)) {
        return cached.results;
      }
      _searchCache.remove(cacheKey);
    }

    // 2. Prevent duplicate in-flight requests for identical queries
    if (_inFlightYouTubeSearches.containsKey(cacheKey)) {
      return await _inFlightYouTubeSearches[cacheKey]!;
    }

    final searchFuture = _executeYouTubeSearch(
      clean,
      config: config,
      enrichSynchronously: enrichSynchronously,
      cancelToken: cancelToken,
    );
    _inFlightYouTubeSearches[cacheKey] = searchFuture;

    try {
      final results = await searchFuture;
      if (!(cancelToken?.isCancelled ?? false) && results.isNotEmpty) {
        _cacheResults(cacheKey, results);
      }
      return results;
    } finally {
      _inFlightYouTubeSearches.remove(cacheKey); // ignore: unawaited_futures
    }
  }

  void _cacheResults(String key, List<YouTubeVideo> results) {
    if (_searchCache.length >= _maxCacheEntries) {
      final oldestKey = _searchCache.keys.first;
      _searchCache.remove(oldestKey);
    }
    _searchCache[key] = _CachedSearchResults(results, DateTime.now());
  }

  Future<List<YouTubeVideo>> _executeYouTubeSearch(
    String clean, {
    SearchRankingConfig? config,
    bool enrichSynchronously = false,
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled ?? false) return const [];
    // 1. Stage B: Dual-Authority Music Discovery (MusicBrainz + Apple iTunes + Deezer Curated Artists)
    // Run structured metadata lookups concurrently to discover both open canonical metadata (MBID/CAA)
    // and commercial popularity / studio release prominence signals.
    final mbFuture = musicBrainzService
        .searchRecordings(clean, limit: 15)
        .catchError((_) => <MusicBrainzRecording>[]);
    final itunesFuture = itunesMetadataService
        .searchSongs(clean, limit: 15)
        .catchError((_) => <ItunesSong>[]);
    final artistsFuture =
        searchArtists(clean).catchError((_) => <ArtistModel>[]);
    final albumsFuture = itunesMetadataService
        .searchAlbums(clean, limit: 3)
        .catchError((_) => <ArtistAlbum>[]);

    final discovery = await Future.wait(
        [mbFuture, itunesFuture, artistsFuture, albumsFuture]);
    final mbRecordings = discovery[0] as List<MusicBrainzRecording>;
    final itunesSongs = List<ItunesSong>.from(discovery[1] as List<ItunesSong>);
    final artists = discovery[2] as List<ArtistModel>;
    final albums = discovery[3] as List<ArtistAlbum>;

    // Detect whether the user query specifically targets a verified artist entity
    final targetedArtist =
        QueryRelevanceEvaluator.detectTargetedArtist(clean, artists);

    // Bridge strongly relevant album tracks into itunesSongs (guarding against
    // substring-matching unrelated albums or Various Artists compilation tracks)
    final stronglyRelevantAlbums = <ArtistAlbum>[];
    for (final alb in albums) {
      final albTitle = alb.title.toLowerCase();
      final matchesTargetedArtist = targetedArtist == null ||
          QueryRelevanceEvaluator.matchesCreditedArtist(
            alb.artistName,
            targetedArtist,
          );
      if (!matchesTargetedArtist) continue;
      if (albTitle == clean.toLowerCase() ||
          albTitle.contains(clean.toLowerCase()) ||
          QueryRelevanceEvaluator.hasFullQueryCoverage(
            YouTubeVideo(
              id: '',
              title: alb.title,
              channelTitle: alb.artistName,
              thumbnailUrl: '',
              duration: '',
              viewCount: '',
            ),
            query: clean,
          )) {
        stronglyRelevantAlbums.add(alb);
        if (stronglyRelevantAlbums.length >= 3) break;
      }
    }

    if (stronglyRelevantAlbums.isNotEmpty) {
      final collectionIds = stronglyRelevantAlbums
          .map((a) => a.id.replaceFirst('itunes_', ''))
          .where((id) => id.isNotEmpty)
          .toSet();

      if (collectionIds.isNotEmpty) {
        try {
          final trackFutures = collectionIds
              .map((id) => itunesMetadataService.getAlbumTracks(id));
          final trackLists = await Future.wait(trackFutures).timeout(
            const Duration(milliseconds: 1800),
            onTimeout: () => <List<ItunesSong>>[],
          );
          for (final tracks in trackLists) {
            for (final song in tracks) {
              if (targetedArtist != null &&
                  !QueryRelevanceEvaluator.matchesCreditedArtist(
                    song.artistName,
                    targetedArtist,
                    titleOrCredits: song.trackName,
                  )) {
                continue;
              }
              if (!itunesSongs.any((s) => s.trackId == song.trackId)) {
                itunesSongs.add(song);
              }
            }
          }
        } catch (_) {}
      }
    }

    if (mbRecordings.isNotEmpty || itunesSongs.isNotEmpty) {
      final candidatePool = <YouTubeVideo>[];

      // Convert MusicBrainz recordings that pass strict relevance & artist check
      for (final rec in mbRecordings) {
        final mbVideo = YouTubeVideo.fromMusicBrainzRecording(rec);
        if (QueryRelevanceEvaluator.isCandidateRelevant(
          mbVideo,
          query: clean,
          expectedArtist: targetedArtist,
        )) {
          candidatePool.add(mbVideo);
        }
      }

      // Convert iTunes songs that pass strict relevance & artist check
      for (final song in itunesSongs) {
        final itVideo = YouTubeVideo.fromItunesSong(song);
        if (QueryRelevanceEvaluator.isCandidateRelevant(
          itVideo,
          query: clean,
          expectedArtist: targetedArtist,
        )) {
          candidatePool.add(itVideo);
        }
      }

      // Check whether structured discovery yielded full query coverage candidates
      final hasFullCoverage = candidatePool.any(
          (c) => QueryRelevanceEvaluator.hasFullQueryCoverage(c, query: clean));

      // If candidatePool has no candidates matching the full query context,
      // query YouTube to discover authentic verified recordings matching the complete user query.
      if (!hasFullCoverage ||
          (targetedArtist != null && candidatePool.length < 3)) {
        try {
          final ytVideos = await youtubeRepository.search(clean);
          for (final yt in ytVideos) {
            if (MusicResultClassifier.isValidMusicTrack(yt, query: clean) &&
                QueryRelevanceEvaluator.isCandidateRelevant(
                  yt,
                  query: clean,
                  expectedArtist: targetedArtist,
                )) {
              candidatePool.add(yt);
            }
          }
        } catch (_) {}
      }

      if (candidatePool.isNotEmpty) {
        // Pick canonicalArtist from targetedArtist first, else corroborated fullMatchCandidate
        YouTubeVideo? fullMatchCandidate;
        for (final c in candidatePool) {
          if (QueryRelevanceEvaluator.hasFullQueryCoverage(c, query: clean)) {
            fullMatchCandidate = c;
            break;
          }
        }
        final String? canonicalArtist = targetedArtist ??
            fullMatchCandidate?.canonicalArtist ??
            (hasFullCoverage ? candidatePool.first.canonicalArtist : null);

        // Rank using CanonicalMusicRanker: prioritizes canonical studio recordings,
        // elevates prominent performing artists, and heavily penalizes unrequested tribute/cover acts
        final rankedRecordings = CanonicalMusicRanker.rankVideos(
          candidatePool,
          query: clean,
          canonicalArtist: canonicalArtist,
          prominentArtists: artists,
        );

        // Launch non-blocking background cover art resolution from Cover Art Archive
        if (!(cancelToken?.isCancelled ?? false)) {
          _enrichRecordingsWithCoverArt(clean, mbRecordings, rankedRecordings);
        }

        // Controlled Supplemental Search:
        // If the query explicitly seeks an alternate version (e.g. "live", "remix", "acoustic", "unplugged", "cover")
        // or if discovery returned fewer than 3 candidates, or if no full coverage candidate is present yet,
        // supplement with verified YouTube recordings
        final cleanLower = clean.toLowerCase();
        final isSpecificVersionQuery = cleanLower.contains('live') ||
            cleanLower.contains('remix') ||
            cleanLower.contains('acoustic') ||
            cleanLower.contains('unplugged') ||
            cleanLower.contains('cover');
        final lacksFullMatch = !rankedRecordings.any((r) =>
            QueryRelevanceEvaluator.hasFullQueryCoverage(r, query: clean));

        if (rankedRecordings.length < 3 ||
            isSpecificVersionQuery ||
            lacksFullMatch) {
          try {
            final supplemental = await youtubeRepository.search(clean);
            final validSupplemental = supplemental
                .where((yt) {
                  if (!MusicResultClassifier.isValidMusicTrack(yt,
                      query: clean)) return false;
                  if (!QueryRelevanceEvaluator.isCandidateRelevant(
                    yt,
                    query: clean,
                    expectedArtist: targetedArtist,
                  )) return false;
                  for (final r in rankedRecordings) {
                    if (SearchDeduplicator.isSameCanonicalSong(yt, r))
                      return false;
                  }
                  return true;
                })
                .take(4)
                .toList();

            if (validSupplemental.isNotEmpty) {
              return CanonicalMusicRanker.rankVideos(
                [...rankedRecordings, ...validSupplemental],
                query: clean,
                canonicalArtist: canonicalArtist,
                prominentArtists: artists,
              );
            }
          } catch (_) {}
        }

        return rankedRecordings;
      }
    }

    // 2. Stage B Fallback: If structured open metadata discovery had 0 relevant recordings,
    // fall back to YouTube search with strict music, artist, and query relevance filtering
    final rawVideos = await youtubeRepository.search(clean);
    final validYt = rawVideos
        .where(
            (yt) => MusicResultClassifier.isValidMusicTrack(yt, query: clean))
        .where((yt) => QueryRelevanceEvaluator.isCandidateRelevant(
              yt,
              query: clean,
              expectedArtist: targetedArtist,
            ))
        .toList();

    if (validYt.isNotEmpty) {
      final ranked = CanonicalMusicRanker.rankVideos(
        validYt,
        query: clean,
        canonicalArtist: targetedArtist,
        prominentArtists: artists,
      );

      if (enrichSynchronously) {
        return await enrichYouTubeResults(ranked);
      }
      return ranked;
    }

    final ranked = SearchDeduplicator.deduplicateAndRank(
      rawVideos
          .where(
              (yt) => MusicResultClassifier.isValidMusicTrack(yt, query: clean))
          .where((yt) => QueryRelevanceEvaluator.isCandidateRelevant(
                yt,
                query: clean,
                expectedArtist: targetedArtist,
              ))
          .toList(),
      query: clean,
      config: config ?? const SearchRankingConfig(filterDerivativeEdits: true),
    );

    if (enrichSynchronously) {
      return await enrichYouTubeResults(ranked);
    }

    return ranked;
  }

  void _enrichRecordingsWithCoverArt(
    String query,
    List<MusicBrainzRecording> recordings,
    List<YouTubeVideo> videos,
  ) {
    if (recordings.isEmpty || videos.isEmpty) return;
    Future<void>(() async {
      bool updated = false;
      final updatedList = List<YouTubeVideo>.from(videos);

      for (var i = 0; i < updatedList.length && i < 5; i++) {
        final video = updatedList[i];
        if (video.metadataProvider == 'musicbrainz' &&
            (video.mbid != null && video.mbid!.isNotEmpty)) {
          MusicBrainzRecording? rec;
          for (final r in recordings) {
            if (r.mbid == video.mbid) {
              rec = r;
              break;
            }
          }
          if (rec != null) {
            final coverUrl = await musicBrainzService.resolveCoverArtUrl(rec);
            if (coverUrl != null && coverUrl.isNotEmpty) {
              updatedList[i] = updatedList[i].copyWith(
                highResArtworkUrl: coverUrl,
                thumbnailUrl: coverUrl,
              );
              updated = true;
            }
          }
        }
      }

      if (updated) {
        updateCachedResults(query, updatedList);
      }
    }).catchError((_) {});
  }

  /// Asynchronously enriches top YouTube results with studio iTunes metadata and 600x600 artwork.
  Future<List<YouTubeVideo>> enrichYouTubeResults(
      List<YouTubeVideo> videos) async {
    if (videos.isEmpty) return videos;
    try {
      final topToEnrich = videos.take(15).toList();
      final enrichedTop =
          await itunesMetadataService.enrichYouTubeResults(topToEnrich);
      return [...enrichedTop, ...videos.skip(15)];
    } catch (_) {
      return videos;
    }
  }

  /// Searches verified online artists via Curated catalog, MusicBrainz, Deezer, and Apple iTunes.
  ///
  /// Completely eliminates random YouTube channel uploaders from artist discovery.
  Future<List<ArtistModel>> searchArtists(
    String query, {
    CancelToken? cancelToken,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty || (cancelToken?.isCancelled ?? false)) {
      return const [];
    }
    final cacheKey = cleanQuery.toLowerCase();

    final cached = _artistSearchCache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.ts) <= _cacheTtl) {
      return cached.data;
    }

    if (_inFlightArtistSearches.containsKey(cacheKey)) {
      return await _inFlightArtistSearches[cacheKey]!;
    }

    final future = _executeSearchArtists(cleanQuery);
    _inFlightArtistSearches[cacheKey] = future;
    try {
      final results = await future;
      if (results.isNotEmpty) {
        if (_artistSearchCache.length >= _maxCacheEntries) {
          _artistSearchCache.remove(_artistSearchCache.keys.first);
        }
        _artistSearchCache[cacheKey] = (data: results, ts: DateTime.now());
      }
      return results;
    } finally {
      _inFlightArtistSearches.remove(cacheKey);
    }
  }

  Future<List<ArtistModel>> _executeSearchArtists(String cleanQuery) async {
    final results = await Future.wait([
      artistRepository
          .searchArtists(cleanQuery)
          .catchError((_) => <ArtistModel>[]),
      musicBrainzService
          .searchArtistsAsArtistModels(cleanQuery)
          .catchError((_) => <ArtistModel>[]),
      itunesMetadataService
          .searchArtists(cleanQuery)
          .catchError((_) => <ArtistModel>[]),
    ]);

    final deezerCurated = results[0];
    final mbArtists = results[1];
    final itunesArtists = results[2];

    // Infer performing artist from canonical song discovery if query is a song title (e.g. "brooklyn baby")
    // Use iTunes song search for instantaneous artist inference to preserve MusicBrainz rate limiter for main track discovery
    final inferredSongArtists = <ArtistModel>[];
    final verifiedInferredIds = <String>{};

    if (!QueryRelevanceEvaluator.isCollectionQuery(cleanQuery)) {
      try {
        final itunesTop =
            await itunesMetadataService.searchSongs(cleanQuery, limit: 3);
        for (final song in itunesTop) {
          final itVideo = YouTubeVideo.fromItunesSong(song);
          if (song.artistName.isNotEmpty &&
              QueryRelevanceEvaluator.isCandidateRelevant(itVideo,
                  query: cleanQuery)) {
            final curated =
                DeezerArtistRepository.findCuratedByName(song.artistName);
            if (curated != null) {
              inferredSongArtists.add(curated);
              verifiedInferredIds.add(curated.id);
            } else {
              final resolved = await artistRepository
                  .searchArtists(song.artistName)
                  .catchError((_) => <ArtistModel>[]);
              if (resolved.isNotEmpty) {
                inferredSongArtists.add(resolved.first);
                verifiedInferredIds.add(resolved.first.id);
              }
            }
          }
        }
      } catch (_) {}
    }

    return mergeAndDeduplicateArtists(
      curatedAndDeezer: [
        ...inferredSongArtists,
        ...deezerCurated,
        ...mbArtists
      ],
      itunesArtists: itunesArtists,
      query: cleanQuery,
      verifiedInferredArtistIds: verifiedInferredIds,
    );
  }

  /// Merges and deduplicates artist results across providers:
  /// - Preserves stable identities (Deezer ID, iTunes ID).
  /// - Enriches portrait URLs when verified curated images exist.
  /// - Deduplicates identical canonical entities without merging distinct artists.
  static List<ArtistModel> mergeAndDeduplicateArtists({
    required List<ArtistModel> curatedAndDeezer,
    List<ArtistModel> itunesArtists = const [],
    List<ArtistModel> youtubeArtists = const [],
    required String query,
    Set<String> verifiedInferredArtistIds = const {},
  }) {
    final seenIds = <String>{};
    final seenCanonicalNames = <String>{};
    final merged = <ArtistModel>[];

    String canonical(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final cleanQuery = query.trim().toLowerCase();
    final queryCanonical = canonical(cleanQuery);

    // 1. Process Curated / Deezer artists first (they have verified discography metadata & fan counts)
    for (final artist in curatedAndDeezer) {
      if (artist.id.isEmpty) continue;
      final isCurated =
          DeezerArtistRepository.findCuratedByName(artist.name) != null;
      if (!isCurated &&
          !verifiedInferredArtistIds.contains(artist.id) &&
          !QueryRelevanceEvaluator.isArtistRelevant(artist.name,
              query: cleanQuery)) {
        continue;
      }
      if (!ArtistClassifier.isLegitimateMusicArtist(
        artist.name,
        fanCount: artist.fanCount,
        query: cleanQuery,
      )) {
        continue;
      }
      final cName = canonical(artist.name);

      var effectiveArtist = artist;
      if (!artist.hasValidImage) {
        final curated = DeezerArtistRepository.findCuratedByName(artist.name);
        if (curated != null && curated.hasValidImage) {
          effectiveArtist = artist.copyWith(imageUrl: curated.imageUrl);
        }
      }

      if (seenIds.add(effectiveArtist.id)) {
        if (cName.isNotEmpty) seenCanonicalNames.add(cName);
        merged.add(effectiveArtist);
      }
    }

    // 2. Process Apple iTunes artists
    for (final itArtist in itunesArtists) {
      if (itArtist.id.isEmpty) continue;
      if (!verifiedInferredArtistIds.contains(itArtist.id) &&
          !QueryRelevanceEvaluator.isArtistRelevant(itArtist.name,
              query: cleanQuery)) {
        continue;
      }
      if (!ArtistClassifier.isLegitimateMusicArtist(
        itArtist.name,
        query: cleanQuery,
      )) {
        continue;
      }
      final cName = canonical(itArtist.name);

      // If an artist with the exact same canonical name is already present from Deezer/curated
      if (cName.isNotEmpty && seenCanonicalNames.contains(cName)) {
        final index = merged.indexWhere((a) => canonical(a.name) == cName);
        if (index >= 0 &&
            !merged[index].hasValidImage &&
            itArtist.hasValidImage) {
          merged[index] = merged[index].copyWith(imageUrl: itArtist.imageUrl);
        }
        continue;
      }

      var effectiveArtist = itArtist;
      final curated = DeezerArtistRepository.findCuratedByName(itArtist.name);
      if (curated != null) {
        effectiveArtist = itArtist.copyWith(
          imageUrl:
              curated.hasValidImage ? curated.imageUrl : itArtist.imageUrl,
          languages: curated.languages.isNotEmpty
              ? curated.languages
              : itArtist.languages,
          fanCount: curated.fanCount > 0 ? curated.fanCount : itArtist.fanCount,
        );
      }

      if (seenIds.add(effectiveArtist.id)) {
        if (cName.isNotEmpty) seenCanonicalNames.add(cName);
        merged.add(effectiveArtist);
      }
    }

    // 3. Process any legacy YouTube artists (only if valid music artists)
    for (final ytArtist in youtubeArtists) {
      if (ytArtist.id.isEmpty) continue;
      if (!ArtistClassifier.isLegitimateMusicArtist(
        ytArtist.name,
        query: cleanQuery,
      )) {
        continue;
      }
      final cName = canonical(ytArtist.name);
      if (cName.isNotEmpty && seenCanonicalNames.contains(cName)) {
        continue;
      }
      if (seenIds.add(ytArtist.id)) {
        if (cName.isNotEmpty) seenCanonicalNames.add(cName);
        merged.add(ytArtist);
      }
    }

    // Prioritize prominent artists and verified curated artists over obscure homonyms
    merged.sort((a, b) {
      final aIsCurated =
          DeezerArtistRepository.findCuratedByName(a.name) != null;
      final bIsCurated =
          DeezerArtistRepository.findCuratedByName(b.name) != null;

      // Curated/verified performing artists take precedence over obscure entities (< 5000 fans)
      if (aIsCurated && !bIsCurated && b.fanCount < 5000) return -1;
      if (!aIsCurated && bIsCurated && a.fanCount < 5000) return 1;

      // Prominent artists with significant fan base (e.g. >= 50,000 fans) take priority over obscure homonyms (< 1,000 fans)
      if (a.fanCount >= 50000 && b.fanCount < 1000) return -1;
      if (b.fanCount >= 50000 && a.fanCount < 1000) return 1;

      final aName = a.name.toLowerCase();
      final bName = b.name.toLowerCase();
      final aExact = aName == cleanQuery || canonical(aName) == queryCanonical;
      final bExact = bName == cleanQuery || canonical(bName) == queryCanonical;

      final aEligibleExact = aExact && (aIsCurated || a.fanCount >= 1000);
      final bEligibleExact = bExact && (bIsCurated || b.fanCount >= 1000);
      if (aEligibleExact && !bEligibleExact) return -1;
      if (!aEligibleExact && bEligibleExact) return 1;

      final aStarts = aName.startsWith(cleanQuery);
      final bStarts = bName.startsWith(cleanQuery);
      final aEligibleStarts = aStarts && (aIsCurated || a.fanCount >= 1000);
      final bEligibleStarts = bStarts && (bIsCurated || b.fanCount >= 1000);
      if (aEligibleStarts && !bEligibleStarts) return -1;
      if (!aEligibleStarts && bEligibleStarts) return 1;

      if (aIsCurated && !bIsCurated) return -1;
      if (!aIsCurated && bIsCurated) return 1;

      if (aExact && !bExact) return -1;
      if (!aExact && bExact) return 1;

      if (aStarts && !bStarts) return -1;
      if (!aStarts && bStarts) return 1;

      return b.fanCount.compareTo(a.fanCount);
    });

    return merged;
  }

  /// Searches verified online albums for matching artist entities via Apple iTunes and Deezer.
  Future<List<ArtistAlbum>> searchAlbums(
    String query, {
    List<ArtistModel>? matchedArtists,
    CancelToken? cancelToken,
  }) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty || (cancelToken?.isCancelled ?? false)) {
      return const [];
    }

    final cached = _albumSearchCache[cleanQuery];
    if (cached != null && DateTime.now().difference(cached.ts) <= _cacheTtl) {
      return cached.data;
    }

    if (_inFlightAlbumSearches.containsKey(cleanQuery)) {
      return await _inFlightAlbumSearches[cleanQuery]!;
    }

    final future = _executeSearchAlbums(
      cleanQuery,
      matchedArtists: matchedArtists,
    );
    _inFlightAlbumSearches[cleanQuery] = future;
    try {
      final results = await future;
      if (results.isNotEmpty) {
        if (_albumSearchCache.length >= _maxCacheEntries) {
          _albumSearchCache.remove(_albumSearchCache.keys.first);
        }
        _albumSearchCache[cleanQuery] = (data: results, ts: DateTime.now());
      }
      return results;
    } finally {
      _inFlightAlbumSearches.remove(cleanQuery);
    }
  }

  Future<List<ArtistAlbum>> _executeSearchAlbums(
    String cleanQuery, {
    List<ArtistModel>? matchedArtists,
  }) async {
    final artists = (matchedArtists != null && matchedArtists.isNotEmpty)
        ? matchedArtists
        : await searchArtists(cleanQuery);

    final resultAlbums = <ArtistAlbum>[];
    final seenAlbumTitles = <String>{};

    // 1. Direct Apple iTunes Album Search for verified studio releases
    try {
      final itunesAlbums =
          await itunesMetadataService.searchAlbums(cleanQuery, limit: 6);
      for (final alb in itunesAlbums) {
        if (seenAlbumTitles.add(alb.title.toLowerCase())) {
          resultAlbums.add(alb);
        }
      }
    } catch (_) {}

    // 2. Artist Discography Albums via Deezer
    for (final artist in artists.take(2)) {
      try {
        final deezerId = (int.tryParse(artist.id) != null)
            ? artist.id
            : (DeezerArtistRepository.findCuratedByName(artist.name)?.id ?? '');
        if (deezerId.isNotEmpty) {
          final albums = await artistRepository.getArtistAlbums(deezerId);
          for (final alb in albums) {
            if (seenAlbumTitles.add(alb.title.toLowerCase())) {
              resultAlbums.add(alb);
            }
          }
        }
      } catch (_) {}
    }

    return resultAlbums;
  }

  /// Searches online YouTube Music playlists.
  Future<List<OnlinePlaylist>> searchPlaylists(
    String query, {
    CancelToken? cancelToken,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty || (cancelToken?.isCancelled ?? false)) {
      return const [];
    }
    final cacheKey = cleanQuery.toLowerCase();

    final cached = _playlistSearchCache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.ts) <= _cacheTtl) {
      return cached.data;
    }

    if (_inFlightPlaylistSearches.containsKey(cacheKey)) {
      return await _inFlightPlaylistSearches[cacheKey]!;
    }

    final future = youtubeRepository
        .searchPlaylists(cleanQuery)
        .then(
          (items) => MusicResultClassifier.filterAndRankMusicPlaylists(
            items,
            query: cleanQuery,
          ),
        )
        .catchError((_) => <OnlinePlaylist>[]);
    _inFlightPlaylistSearches[cacheKey] = future;
    try {
      final results = await future;
      if (results.isNotEmpty) {
        if (_playlistSearchCache.length >= _maxCacheEntries) {
          _playlistSearchCache.remove(_playlistSearchCache.keys.first);
        }
        _playlistSearchCache[cacheKey] = (data: results, ts: DateTime.now());
      }
      return results;
    } finally {
      _inFlightPlaylistSearches.remove(cacheKey);
    }
  }

  /// In-memory cache for live music suggestions (query -> suggestions).
  final Map<String, List<MusicSuggestion>> _liveSuggestionsCache = {};
  static const int _maxLiveCache = 50;

  /// Fetches Spotify-inspired music entity live suggestions (Artists, Songs, Albums, Playlists).
  Future<List<MusicSuggestion>> getLiveMusicSuggestions({
    required String query,
    List<MediaSong> localSongs = const [],
    List<MediaArtist> localArtists = const [],
    List<MediaAlbum> localAlbums = const [],
    List<MediaPlaylist> localPlaylists = const [],
    CancelToken? cancelToken,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty || (cancelToken?.isCancelled ?? false)) {
      return const [];
    }

    final cacheKey = cleanQuery.toLowerCase();
    if (_liveSuggestionsCache.containsKey(cacheKey)) {
      return _liveSuggestionsCache[cacheKey]!;
    }

    final lowerQuery = cleanQuery.toLowerCase();
    final normQuery = lowerQuery.replaceAll(RegExp(r'[^a-z0-9]'), '');

    // 1. Local Library Instant Matches
    final localArtistSuggestions = <MusicSuggestion>[];
    for (final artist in localArtists) {
      if (artist.name.toLowerCase().contains(lowerQuery)) {
        localArtistSuggestions.add(MusicSuggestion(
          id: artist.id,
          title: artist.name,
          subtitle: null,
          imageUrl: artist.artworkPath,
          type: SuggestionType.artist,
          isOnline: false,
          source: 'Local',
          entity: artist,
        ));
      }
    }

    final localSongSuggestions = <MusicSuggestion>[];
    for (final song in localSongs) {
      if (song.title.toLowerCase().contains(lowerQuery) ||
          song.artist.toLowerCase().contains(lowerQuery)) {
        localSongSuggestions.add(MusicSuggestion(
          id: song.id,
          title: song.title,
          subtitle: song.artist,
          imageUrl: song.artworkPath,
          type: SuggestionType.song,
          isOnline: false,
          source: 'Local',
          entity: song,
        ));
      }
    }

    final localAlbumSuggestions = <MusicSuggestion>[];
    for (final album in localAlbums) {
      if (album.title.toLowerCase().contains(lowerQuery) ||
          album.artist.toLowerCase().contains(lowerQuery)) {
        localAlbumSuggestions.add(MusicSuggestion(
          id: album.id,
          title: album.title,
          subtitle: album.artist,
          imageUrl: album.artworkPath,
          type: SuggestionType.album,
          isOnline: false,
          source: 'Local',
          entity: album,
        ));
      }
    }

    final localPlaylistSuggestions = <MusicSuggestion>[];
    for (final playlist in localPlaylists) {
      if (playlist.name.toLowerCase().contains(lowerQuery)) {
        localPlaylistSuggestions.add(MusicSuggestion(
          id: playlist.id,
          title: playlist.name,
          subtitle: '${playlist.trackCount} tracks',
          imageUrl: null,
          type: SuggestionType.playlist,
          isOnline: false,
          source: 'Local',
          entity: playlist,
        ));
      }
    }

    // 2. Fetch Online Candidates in Parallel (fast search with timeouts)
    List<ArtistModel> onlineArtists = const [];
    List<YouTubeVideo> onlineVideos = const [];
    List<OnlinePlaylist> onlinePlaylists = const [];

    try {
      final results = await Future.wait([
        searchArtists(cleanQuery)
            .timeout(
              const Duration(milliseconds: 2500),
              onTimeout: () => <ArtistModel>[],
            )
            .catchError((_) => <ArtistModel>[]),
        youtubeRepository
            .search(cleanQuery)
            .timeout(
              const Duration(milliseconds: 3000),
              onTimeout: () => <YouTubeVideo>[],
            )
            .catchError((_) => <YouTubeVideo>[]),
        searchPlaylists(cleanQuery)
            .timeout(
              const Duration(milliseconds: 2000),
              onTimeout: () => <OnlinePlaylist>[],
            )
            .catchError((_) => <OnlinePlaylist>[]),
      ]);

      onlineArtists = results[0] as List<ArtistModel>;
      onlineVideos = results[1] as List<YouTubeVideo>;
      onlinePlaylists = results[2] as List<OnlinePlaylist>;
    } catch (_) {}

    // Fetch albums for top artist if available and artist matches
    List<ArtistAlbum> onlineAlbums = const [];
    if (onlineArtists.isNotEmpty) {
      try {
        onlineAlbums = await searchAlbums(cleanQuery,
                matchedArtists: onlineArtists.take(1).toList())
            .timeout(const Duration(milliseconds: 1500),
                onTimeout: () => <ArtistAlbum>[]);
      } catch (_) {}
    }

    // 3. Determine Query Intent & Map Online Candidates
    final exactArtistMatch = onlineArtists.cast<ArtistModel?>().firstWhere(
          (a) =>
              a != null &&
              (a.name.toLowerCase() == lowerQuery ||
                  a.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') ==
                      normQuery),
          orElse: () => null,
        );

    final prefixArtistMatch = onlineArtists.cast<ArtistModel?>().firstWhere(
          (a) =>
              a != null &&
              (a.name.toLowerCase().startsWith(lowerQuery) ||
                  lowerQuery.startsWith(a.name.toLowerCase())),
          orElse: () => null,
        );

    final topArtist = exactArtistMatch ??
        prefixArtistMatch ??
        (onlineArtists.isNotEmpty ? onlineArtists.first : null);

    final isArtistQuery = topArtist != null &&
        (topArtist == exactArtistMatch ||
            topArtist == prefixArtistMatch ||
            DeezerArtistRepository.findCuratedByName(topArtist.name) != null ||
            topArtist.fanCount >= 5000);
    final targetedArtist = isArtistQuery ? topArtist.name : null;

    if (cancelToken?.isCancelled ?? false) return const [];

    final onlineArtistSuggestions = <MusicSuggestion>[];
    if (topArtist != null) {
      onlineArtistSuggestions.add(MusicSuggestion(
        id: topArtist.id,
        title: topArtist.name,
        subtitle: null,
        imageUrl: topArtist.imageUrl,
        type: SuggestionType.artist,
        isOnline: true,
        source: 'YouTube',
        entity: topArtist,
      ));
    }

    final filteredOnlineVideos = onlineVideos
        .where((v) =>
            MusicResultClassifier.isValidMusicTrack(v, query: cleanQuery))
        .where((v) => QueryRelevanceEvaluator.isCandidateRelevant(
              v,
              query: cleanQuery,
              expectedArtist: targetedArtist,
            ))
        .toList();

    final onlineSongSuggestions = <MusicSuggestion>[];
    for (final v in filteredOnlineVideos.take(8)) {
      onlineSongSuggestions.add(MusicSuggestion(
        id: v.id,
        title: v.canonicalTitle ?? v.title,
        subtitle: v.canonicalArtist ?? v.channelTitle,
        imageUrl: v.highResArtworkUrl ?? v.thumbnailUrl,
        type: SuggestionType.song,
        isOnline: true,
        source: 'YouTube',
        entity: v,
      ));
    }

    final onlineAlbumSuggestions = <MusicSuggestion>[];
    for (final alb in onlineAlbums) {
      if (targetedArtist != null &&
          !QueryRelevanceEvaluator.matchesCreditedArtist(
            alb.artistName,
            targetedArtist,
          )) {
        continue;
      }
      if (!QueryRelevanceEvaluator.isCandidateRelevant(
        YouTubeVideo(
          id: alb.id,
          title: alb.title,
          channelTitle: alb.artistName,
          thumbnailUrl: alb.coverUrl,
          duration: '',
          viewCount: '',
        ),
        query: cleanQuery,
        expectedArtist: targetedArtist,
      )) {
        continue;
      }
      onlineAlbumSuggestions.add(MusicSuggestion(
        id: alb.id,
        title: alb.title,
        subtitle: alb.artistName,
        imageUrl: alb.coverUrl,
        type: SuggestionType.album,
        isOnline: true,
        source: 'YouTube',
        entity: alb,
      ));
      if (onlineAlbumSuggestions.length >= 2) break;
    }

    final onlinePlaylistSuggestions = <MusicSuggestion>[];
    for (final p in onlinePlaylists.take(1)) {
      onlinePlaylistSuggestions.add(MusicSuggestion(
        id: p.id,
        title: p.title,
        subtitle: p.author,
        imageUrl: p.thumbnailUrl,
        type: SuggestionType.playlist,
        isOnline: true,
        source: 'YouTube',
        entity: p,
      ));
    }

    // 4. Combined Assembly with Stable Source-Specific Keys
    final suggestions = <MusicSuggestion>[];
    final seenKeys = <String>{};

    void addSuggestion(MusicSuggestion s) {
      final key = '${s.sourceLabel}_${s.type.name}_${s.id}';
      if (seenKeys.add(key)) {
        suggestions.add(s);
      }
    }

    // Priority A: Top Artist (if artist query intent)
    if (isArtistQuery && onlineArtistSuggestions.isNotEmpty) {
      addSuggestion(onlineArtistSuggestions.first);
    } else if (localArtistSuggestions.isNotEmpty) {
      addSuggestion(localArtistSuggestions.first);
    }

    // Priority B: Songs (Fairly merge Local and Online YouTube Music)
    final localIter = localSongSuggestions.iterator;
    final onlineIter = onlineSongSuggestions.iterator;

    int localAdded = 0;
    int onlineAdded = 0;
    const maxSongs = 5;

    while ((localAdded + onlineAdded) < maxSongs && suggestions.length < 5) {
      bool advanced = false;

      // Online YouTube song
      if (onlineIter.moveNext()) {
        addSuggestion(onlineIter.current);
        onlineAdded++;
        advanced = true;
      }

      // Local song
      if (localIter.moveNext()) {
        addSuggestion(localIter.current);
        localAdded++;
        advanced = true;
      }

      if (!advanced) break;
    }

    // If remaining slots and query was not primarily artist, add top artist
    if (!isArtistQuery && suggestions.length < 5) {
      if (onlineArtistSuggestions.isNotEmpty) {
        addSuggestion(onlineArtistSuggestions.first);
      } else if (localArtistSuggestions.isNotEmpty) {
        addSuggestion(localArtistSuggestions.first);
      }
    }

    // Priority C: Albums / Playlists (1 slot if space)
    if (suggestions.length < 6) {
      if (localAlbumSuggestions.isNotEmpty) {
        addSuggestion(localAlbumSuggestions.first);
      } else if (onlineAlbumSuggestions.isNotEmpty) {
        addSuggestion(onlineAlbumSuggestions.first);
      } else if (localPlaylistSuggestions.isNotEmpty) {
        addSuggestion(localPlaylistSuggestions.first);
      } else if (onlinePlaylistSuggestions.isNotEmpty) {
        addSuggestion(onlinePlaylistSuggestions.first);
      }
    }

    // Cap suggestions at 6 music entities to keep UI compact and scannable
    final capped = suggestions.take(6).toList();

    // 5. Append secondary Search Query action at the bottom
    capped.add(MusicSuggestion(
      id: 'search_query_$cleanQuery',
      title: 'Search for "$cleanQuery"',
      subtitle: null,
      imageUrl: null,
      type: SuggestionType.searchQuery,
      entity: cleanQuery,
    ));

    if (cancelToken?.isCancelled ?? false) return const [];

    // Cache the result
    if (_liveSuggestionsCache.length >= _maxLiveCache) {
      _liveSuggestionsCache.remove(_liveSuggestionsCache.keys.first);
    }
    _liveSuggestionsCache[cacheKey] = capped;

    return capped;
  }

  /// Fetches auto-complete suggestions from history and online provider.
  Future<List<String>> getSuggestions(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final lower = trimmed.toLowerCase();
    final history = getRecentSearches()
        .where((s) => s.toLowerCase().contains(lower))
        .toList();
    if (history.length >= 5) return history.take(5).toList();

    try {
      final online = await youtubeRepository.getSuggestions(trimmed);
      final combined = <String>{...history, ...online}.toList();
      return combined.take(6).toList();
    } catch (_) {
      return history;
    }
  }

  void dispose() {
    _searchCache.clear();
    _inFlightYouTubeSearches.clear();
    _liveSuggestionsCache.clear();
    playbackSourceResolver.clearCache();
    youtubeRepository.clearCache();
    musicBrainzService.clearCache();
  }
}
