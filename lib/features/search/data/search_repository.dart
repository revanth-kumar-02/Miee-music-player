import 'package:hive/hive.dart';
import '../../../core/storage/hive_boxes.dart';
import '../domain/search_deduplicator.dart';
import '../domain/artist_classifier.dart';
import '../domain/online_playlist.dart';
import '../domain/music_suggestion.dart';
import '../../media/domain/models.dart';
import '../../onboarding/data/artist_discovery_repository.dart';
import '../../onboarding/domain/artist_model.dart';
import '../../youtube/domain/youtube_model.dart';
import '../../youtube/data/youtube_repository.dart';
import '../../metadata/data/itunes_metadata_service.dart';
import 'local_search_service.dart';

/// Central search repository orchestrating local fuzzy matches, YouTube API queries,
/// online artist discovery, suggestions, and persistent search history in Hive.
class SearchRepository {
  final LocalSearchService localSearch;
  final YouTubeRepository youtubeRepository;
  final ArtistRepository artistRepository;
  final ItunesMetadataService itunesMetadataService;

  SearchRepository({
    LocalSearchService? localSearch,
    YouTubeRepository? youtubeRepository,
    ArtistRepository? artistRepository,
    ItunesMetadataService? itunesMetadataService,
  })  : localSearch = localSearch ?? LocalSearchService(),
        youtubeRepository = youtubeRepository ?? YouTubeRepository(),
        artistRepository = artistRepository ?? DeezerArtistRepository(),
        itunesMetadataService = itunesMetadataService ?? ItunesMetadataService();

  static const String _prefKey = 'youtube_search_history';
  static const int _maxHistory = 10;

  Box<Object?> get _box => Hive.box<Object?>(HiveBoxes.preferences);

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

  /// Performs online YouTube query and applies canonical-song deduplication and ranking.
  Future<List<YouTubeVideo>> searchYouTube(String query, {SearchRankingConfig? config}) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];

    final rawVideos = await youtubeRepository.search(clean);
    List<YouTubeVideo> candidateList = rawVideos;

    final lower = clean.toLowerCase();
    final hasMusicWord = lower.contains('song') ||
        lower.contains('songs') ||
        lower.contains('audio') ||
        lower.contains('music') ||
        lower.contains('track') ||
        lower.contains('soundtrack') ||
        lower.contains('album') ||
        lower.contains('ost');

    // If query is a bare title or artist name (e.g. "Amaran", "Anirudh", "Vijay")
    // and raw results yielded fewer than 15 validated songs, supplement with "$clean songs"
    // to discover genuine music releases that YouTube's general video search demotes
    if (!hasMusicWord && rawVideos.length < 15) {
      try {
        final songVideos = await youtubeRepository.search('$clean songs');
        if (songVideos.isNotEmpty) {
          final existingIds = rawVideos.map((v) => v.id).toSet();
          final fresh = songVideos.where((v) => !existingIds.contains(v.id)).toList();
          candidateList = [...rawVideos, ...fresh];
        }
      } catch (_) {}
    }

    final ranked = SearchDeduplicator.deduplicateAndRank(
      candidateList,
      query: clean,
      config: config ?? const SearchRankingConfig(filterDerivativeEdits: true),
    );

    // Enrich top results with canonical iTunes metadata (studio title, artist, album, and 600x600 artwork)
    try {
      final topToEnrich = ranked.take(15).toList();
      final enrichedTop = await itunesMetadataService.enrichYouTubeResults(topToEnrich);
      return [...enrichedTop, ...ranked.skip(15)];
    } catch (_) {
      return ranked;
    }
  }

  /// Searches verified online artists via Curated catalog, Deezer, and YouTube Music channels.
  Future<List<ArtistModel>> searchArtists(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    final results = await Future.wait([
      artistRepository.searchArtists(cleanQuery).catchError((_) => <ArtistModel>[]),
      youtubeRepository.searchArtists(cleanQuery).catchError((_) => <ArtistModel>[]),
    ]);

    final deezerCurated = results[0];
    final ytArtists = results[1];

    return mergeAndDeduplicateArtists(
      curatedAndDeezer: deezerCurated,
      youtubeArtists: ytArtists,
      query: cleanQuery,
    );
  }

  /// Merges and deduplicates artist results across providers:
  /// - Preserves stable identities (Deezer ID, YouTube Channel ID).
  /// - Enriches portrait URLs when verified curated images exist.
  /// - Deduplicates identical canonical entities without merging distinct artists.
  static List<ArtistModel> mergeAndDeduplicateArtists({
    required List<ArtistModel> curatedAndDeezer,
    required List<ArtistModel> youtubeArtists,
    required String query,
  }) {
    final seenIds = <String>{};
    final seenCanonicalNames = <String>{};
    final merged = <ArtistModel>[];

    String canonical(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final cleanQuery = query.trim().toLowerCase();
    final queryCanonical = canonical(cleanQuery);

    // 1. Process Curated / Deezer artists first (they have verified discography metadata)
    for (final artist in curatedAndDeezer) {
      if (artist.id.isEmpty) continue;
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

    // 2. Process YouTube artist channels
    for (final ytArtist in youtubeArtists) {
      if (ytArtist.id.isEmpty) continue;
      if (!ArtistClassifier.isLegitimateMusicArtist(
        ytArtist.name,
        query: cleanQuery,
      )) {
        continue;
      }
      final cName = canonical(ytArtist.name);

      // If an artist with the exact same canonical name is already present from Deezer/curated
      if (cName.isNotEmpty && seenCanonicalNames.contains(cName)) {
        final index = merged.indexWhere((a) => canonical(a.name) == cName);
        if (index >= 0 && !merged[index].hasValidImage && ytArtist.hasValidImage) {
          merged[index] = merged[index].copyWith(imageUrl: ytArtist.imageUrl);
        }
        continue;
      }

      // Check if matches curated list by name to inherit verified high-res portrait
      var effectiveArtist = ytArtist;
      final curated = DeezerArtistRepository.findCuratedByName(ytArtist.name);
      if (curated != null) {
        effectiveArtist = ytArtist.copyWith(
          imageUrl: curated.hasValidImage ? curated.imageUrl : ytArtist.imageUrl,
          languages: curated.languages.isNotEmpty ? curated.languages : ytArtist.languages,
        );
      }

      if (seenIds.add(effectiveArtist.id)) {
        if (cName.isNotEmpty) seenCanonicalNames.add(cName);
        merged.add(effectiveArtist);
      }
    }

    // Prioritize prominent artists and verified curated artists over obscure homonyms
    merged.sort((a, b) {
      final aIsCurated = DeezerArtistRepository.findCuratedByName(a.name) != null;
      final bIsCurated = DeezerArtistRepository.findCuratedByName(b.name) != null;

      // Curated/verified performing artists take precedence over obscure entities (< 5000 fans)
      if (aIsCurated && !bIsCurated && b.fanCount < 5000) return -1;
      if (!aIsCurated && bIsCurated && a.fanCount < 5000) return 1;

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

  /// Searches verified online albums for matching artist entities.
  Future<List<ArtistAlbum>> searchAlbums(String query, {List<ArtistModel>? matchedArtists}) async {
    final cleanQuery = query.trim().toLowerCase();
    final artists = (matchedArtists != null && matchedArtists.isNotEmpty)
        ? matchedArtists
        : await searchArtists(cleanQuery);

    final resultAlbums = <ArtistAlbum>[];
    final seenAlbumTitles = <String>{};

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
  Future<List<OnlinePlaylist>> searchPlaylists(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];
    try {
      return await youtubeRepository.searchPlaylists(cleanQuery);
    } catch (_) {
      return const [];
    }
  }

  /// Fetches Spotify-inspired music entity live suggestions (Artists, Songs, Albums, Playlists).
  Future<List<MusicSuggestion>> getLiveMusicSuggestions({
    required String query,
    List<MediaSong> localSongs = const [],
    List<MediaArtist> localArtists = const [],
    List<MediaAlbum> localAlbums = const [],
    List<MediaPlaylist> localPlaylists = const [],
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    final suggestions = <MusicSuggestion>[];
    final seenKeys = <String>{};

    void addSuggestion(MusicSuggestion s) {
      final key = '${s.type}_${s.id}';
      final normTitle = '${s.type}_${s.title.toLowerCase().trim()}';
      if (seenKeys.add(key) && seenKeys.add(normTitle)) {
        suggestions.add(s);
      }
    }

    final lowerQuery = cleanQuery.toLowerCase();
    final normQuery = lowerQuery.replaceAll(RegExp(r'[^a-z0-9]'), '');

    // 1. Local Library Instant Matches
    for (final artist in localArtists) {
      if (artist.name.toLowerCase().contains(lowerQuery)) {
        addSuggestion(MusicSuggestion(
          id: artist.id,
          title: artist.name,
          subtitle: null,
          imageUrl: artist.artworkPath,
          type: SuggestionType.artist,
          entity: artist,
        ));
      }
    }

    for (final song in localSongs) {
      if (song.title.toLowerCase().contains(lowerQuery) ||
          song.artist.toLowerCase().contains(lowerQuery)) {
        addSuggestion(MusicSuggestion(
          id: song.id,
          title: song.title,
          subtitle: song.artist,
          imageUrl: song.artworkPath,
          type: SuggestionType.song,
          entity: song,
        ));
      }
    }

    for (final album in localAlbums) {
      if (album.title.toLowerCase().contains(lowerQuery) ||
          album.artist.toLowerCase().contains(lowerQuery)) {
        addSuggestion(MusicSuggestion(
          id: album.id,
          title: album.title,
          subtitle: album.artist,
          imageUrl: album.artworkPath,
          type: SuggestionType.album,
          entity: album,
        ));
      }
    }

    for (final playlist in localPlaylists) {
      if (playlist.name.toLowerCase().contains(lowerQuery)) {
        addSuggestion(MusicSuggestion(
          id: playlist.id,
          title: playlist.name,
          subtitle: '${playlist.trackCount} tracks',
          imageUrl: null,
          type: SuggestionType.playlist,
          entity: playlist,
        ));
      }
    }

    // 2. Fetch Online Candidates in Parallel
    final results = await Future.wait([
      searchArtists(cleanQuery).catchError((_) => <ArtistModel>[]),
      searchYouTube(cleanQuery).catchError((_) => <YouTubeVideo>[]),
      searchPlaylists(cleanQuery).catchError((_) => <OnlinePlaylist>[]),
    ]);

    final onlineArtists = results[0] as List<ArtistModel>;
    final onlineVideos = results[1] as List<YouTubeVideo>;
    final onlinePlaylists = results[2] as List<OnlinePlaylist>;

    // Fetch albums for top artist if available
    List<ArtistAlbum> onlineAlbums = const [];
    if (onlineArtists.isNotEmpty) {
      try {
        onlineAlbums = await searchAlbums(cleanQuery, matchedArtists: onlineArtists.take(1).toList());
      } catch (_) {}
    }

    // 3. Determine Query Intent: Does query strongly match an artist or a song?
    final exactArtistMatch = onlineArtists.cast<ArtistModel?>().firstWhere(
      (a) => a != null && (a.name.toLowerCase() == lowerQuery ||
          a.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') == normQuery),
      orElse: () => null,
    );

    final prefixArtistMatch = onlineArtists.cast<ArtistModel?>().firstWhere(
      (a) => a != null && (a.name.toLowerCase().startsWith(lowerQuery) ||
          lowerQuery.startsWith(a.name.toLowerCase())),
      orElse: () => null,
    );

    final topArtist = exactArtistMatch ?? prefixArtistMatch ?? (onlineArtists.isNotEmpty ? onlineArtists.first : null);

    final isArtistQuery = topArtist != null &&
        (topArtist == exactArtistMatch ||
            topArtist == prefixArtistMatch ||
            DeezerArtistRepository.findCuratedByName(topArtist.name) != null ||
            topArtist.fanCount >= 5000);

    // 4. Assemble Spotify-style Live Suggestions
    if (isArtistQuery) {
      // Artist is #1
      addSuggestion(MusicSuggestion(
        id: topArtist.id,
        title: topArtist.name,
        subtitle: null,
        imageUrl: topArtist.imageUrl,
        type: SuggestionType.artist,
        entity: topArtist,
      ));

      // Followed by top songs by or matching this artist
      for (final v in onlineVideos.take(3)) {
        addSuggestion(MusicSuggestion(
          id: v.id,
          title: v.canonicalTitle ?? v.title,
          subtitle: v.canonicalArtist ?? v.channelTitle,
          imageUrl: v.highResArtworkUrl ?? v.thumbnailUrl,
          type: SuggestionType.song,
          entity: v,
        ));
      }

      // Followed by 1 top album
      for (final alb in onlineAlbums.take(1)) {
        addSuggestion(MusicSuggestion(
          id: alb.id,
          title: alb.title,
          subtitle: alb.artistName,
          imageUrl: alb.coverUrl,
          type: SuggestionType.album,
          entity: alb,
        ));
      }

      // Followed by 1 top playlist
      for (final p in onlinePlaylists.take(1)) {
        addSuggestion(MusicSuggestion(
          id: p.id,
          title: p.title,
          subtitle: p.author,
          imageUrl: p.thumbnailUrl,
          type: SuggestionType.playlist,
          entity: p,
        ));
      }
    } else {
      // Song or general query:
      // 1-2 Top songs
      for (final v in onlineVideos.take(2)) {
        addSuggestion(MusicSuggestion(
          id: v.id,
          title: v.canonicalTitle ?? v.title,
          subtitle: v.canonicalArtist ?? v.channelTitle,
          imageUrl: v.highResArtworkUrl ?? v.thumbnailUrl,
          type: SuggestionType.song,
          entity: v,
        ));
      }

      // 1 Top artist (if legitimate and verified)
      if (topArtist != null) {
        addSuggestion(MusicSuggestion(
          id: topArtist.id,
          title: topArtist.name,
          subtitle: null,
          imageUrl: topArtist.imageUrl,
          type: SuggestionType.artist,
          entity: topArtist,
        ));
      }

      // Remaining songs up to 4 total songs
      for (final v in onlineVideos.skip(2).take(2)) {
        addSuggestion(MusicSuggestion(
          id: v.id,
          title: v.canonicalTitle ?? v.title,
          subtitle: v.canonicalArtist ?? v.channelTitle,
          imageUrl: v.highResArtworkUrl ?? v.thumbnailUrl,
          type: SuggestionType.song,
          entity: v,
        ));
      }

      // 1 Album
      for (final alb in onlineAlbums.take(1)) {
        addSuggestion(MusicSuggestion(
          id: alb.id,
          title: alb.title,
          subtitle: alb.artistName,
          imageUrl: alb.coverUrl,
          type: SuggestionType.album,
          entity: alb,
        ));
      }

      // 1 Playlist
      for (final p in onlinePlaylists.take(1)) {
        addSuggestion(MusicSuggestion(
          id: p.id,
          title: p.title,
          subtitle: p.author,
          imageUrl: p.thumbnailUrl,
          type: SuggestionType.playlist,
          entity: p,
        ));
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
    youtubeRepository.clearCache();
  }
}
