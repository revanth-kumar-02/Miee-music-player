import '../../youtube/domain/youtube_model.dart';
import '../../onboarding/domain/artist_model.dart';
import '../../onboarding/data/artist_discovery_repository.dart';
import 'search_deduplicator.dart';

/// Ranks music tracks prioritizing original canonical studio recordings,
/// weighting artist prominence, and penalizing unrequested tribute, cover,
/// and instrumental bands.
class CanonicalMusicRanker {
  /// Known tribute, lullaby, and cover ensembles that frequently clutter
  /// open text-search databases when searching for standard commercial tracks.
  static final List<String> _knownTributeBands = [
    'vitamin string quartet',
    'string quartet',
    'rockabye baby',
    'twinkle twinkle little rock star',
    'lullaby versions',
    'lullaby',
    'midnite string quartet',
    'the string quartet tribute',
    'tribute band',
    'karaoke',
    'karaoke version',
    'ameritz',
    'covers collection',
    'sing2piano',
    'sing2guitar',
    'cover sessions',
    'acoustic cover',
    'piano cover',
    'guitar cover',
    'violin cover',
  ];

  /// Checks if a candidate is an unrequested tribute, cover, or instrumental band.
  static bool isTributeOrCover(YouTubeVideo video, {QueryIntent? intent}) {
    if (intent != null &&
        (intent.wantsCover ||
            intent.wantsInstrumental ||
            intent.wantsKaraoke ||
            intent.normalizedQuery.contains('quartet') ||
            intent.normalizedQuery.contains('lullaby'))) {
      return false;
    }

    final artistLower = (video.canonicalArtist ?? video.channelTitle).toLowerCase();
    final albumLower = (video.albumName ?? '').toLowerCase();
    final titleLower = video.title.toLowerCase();

    // Check if user specifically requested this artist
    if (intent != null && intent.normalizedQuery.isNotEmpty) {
      if (intent.normalizedQuery.contains(artistLower)) {
        return false;
      }
    }

    // 1. Check known tribute artists
    for (final tribute in _knownTributeBands) {
      if (artistLower.contains(tribute)) {
        return true;
      }
    }

    // 2. Check tribute / cover albums
    if (albumLower.contains('performs ') ||
        albumLower.contains('tribute to') ||
        albumLower.contains('covers collection') ||
        albumLower.contains('cover sessions') ||
        albumLower.contains('lullaby versions') ||
        albumLower.contains('string quartet tribute')) {
      return true;
    }

    // 3. Specific tribute soloists (e.g. Caitlin De Ville's "Covers Collection")
    if (artistLower.contains('caitlin de ville') &&
        (albumLower.contains('cover') || titleLower.contains('cover') || albumLower.isEmpty)) {
      return true;
    }

    // 4. Bracketed cover / tribute in title
    if (titleLower.contains('(cover)') ||
        titleLower.contains('[cover]') ||
        titleLower.contains('(tribute)') ||
        titleLower.contains('[tribute]') ||
        titleLower.contains('piano cover') ||
        titleLower.contains('violin cover')) {
      return true;
    }

    return false;
  }

  /// Calculates a holistic canonical score for a candidate recording.
  static double calculateScore(
    YouTubeVideo video, {
    required String query,
    required QueryIntent intent,
    String? canonicalArtist,
    List<ArtistModel> prominentArtists = const [],
  }) {
    double score = 0.0;
    final cleanQuery = query.trim().toLowerCase();
    final normQuery = cleanQuery.replaceAll(RegExp(r'[^a-z0-9]'), '');

    final titleLower = (video.canonicalTitle ?? video.title).trim().toLowerCase();
    final normTitle = titleLower.replaceAll(RegExp(r'[^a-z0-9]'), '');

    final artistLower = (video.canonicalArtist ?? video.channelTitle).trim().toLowerCase();
    final normArtist = artistLower.replaceAll(RegExp(r'[^a-z0-9]'), '');

    // 1. Exact Title Match
    if (titleLower == cleanQuery || (normTitle.isNotEmpty && normTitle == normQuery)) {
      score += 250.0;
    } else if (titleLower.startsWith(cleanQuery)) {
      score += 100.0;
    } else if (titleLower.contains(cleanQuery)) {
      score += 50.0;
    }

    // 2. Canonical Artist Match from Global Popularity (e.g. Apple Music / Curated #1)
    if (canonicalArtist != null && canonicalArtist.isNotEmpty) {
      final canArtistLower = canonicalArtist.trim().toLowerCase();
      final normCanArtist = canArtistLower.replaceAll(RegExp(r'[^a-z0-9]'), '');

      if (artistLower == canArtistLower || (normArtist.isNotEmpty && normArtist == normCanArtist)) {
        score += 400.0;
      } else if (artistLower.contains(canArtistLower) || canArtistLower.contains(artistLower)) {
        score += 200.0;
      }
    }

    // Explicit Artist in User Query (e.g. "Shape of You Caitlin De Ville")
    if (artistLower.isNotEmpty && (cleanQuery.contains(artistLower) || (normArtist.length >= 4 && normQuery.contains(normArtist)))) {
      score += 450.0;
    }

    // 3. Performing Artist Prominence (Fan counts & Curated catalog)
    final curated = DeezerArtistRepository.findCuratedByName(video.canonicalArtist ?? video.channelTitle);
    if (curated != null) {
      score += 250.0;
    }

    ArtistModel? matchingArtist;
    for (final pa in prominentArtists) {
      final pLower = pa.name.trim().toLowerCase();
      if (artistLower == pLower || artistLower.contains(pLower) || pLower.contains(artistLower)) {
        matchingArtist = pa;
        break;
      }
    }

    if (matchingArtist != null) {
      if (matchingArtist.fanCount >= 10000000) {
        score += 350.0; // Mega-stars (Ed Sheeran 20M, etc.)
      } else if (matchingArtist.fanCount >= 1000000) {
        score += 250.0;
      } else if (matchingArtist.fanCount >= 100000) {
        score += 150.0;
      } else if (matchingArtist.fanCount >= 10000) {
        score += 80.0;
      }
    }

    // 4. Heavy Penalty for Unrequested Tribute / Cover / Karaoke Bands
    if (isTributeOrCover(video, intent: intent)) {
      score -= 600.0;
    }

    // 5. Version Intent Alignment
    final isLive = titleLower.contains('live') || (video.albumName?.toLowerCase().contains('live') ?? false);
    final isRemix = titleLower.contains('remix');
    final isAcoustic = titleLower.contains('acoustic') || titleLower.contains('unplugged');

    if (isLive) {
      if (intent.wantsLive) {
        score += 300.0;
      } else {
        score -= 60.0;
      }
    }

    if (isRemix) {
      if (intent.wantsRemix) {
        score += 300.0;
      } else {
        score -= 80.0;
      }
    }

    if (isAcoustic) {
      if (intent.wantsAcoustic) {
        score += 300.0;
      } else {
        score -= 30.0;
      }
    }

    // 6. High Resolution Artwork & Metadata Authority Bonus
    if (video.metadataProvider == 'musicbrainz') {
      score += 120.0; // Open canonical metadata authority
    } else if (video.metadataProvider == 'itunes') {
      score += 100.0; // Verified commercial catalogue
    }

    if (video.highResArtworkUrl != null && video.highResArtworkUrl!.isNotEmpty) {
      score += 40.0;
    }

    return score;
  }

  /// Deduplicates and ranks a candidate pool of [YouTubeVideo] recordings.
  static List<YouTubeVideo> rankVideos(
    List<YouTubeVideo> candidates, {
    required String query,
    String? canonicalArtist,
    List<ArtistModel> prominentArtists = const [],
  }) {
    if (candidates.isEmpty) return const [];

    final intent = QueryIntent.fromQuery(query);

    // 1. Compute scores and track initial discovery indices for stability
    final scored = <({YouTubeVideo video, double score, int initialIndex})>[];
    for (var i = 0; i < candidates.length; i++) {
      final v = candidates[i];
      final s = calculateScore(
        v,
        query: query,
        intent: intent,
        canonicalArtist: canonicalArtist,
        prominentArtists: prominentArtists,
      );
      scored.add((video: v, score: s, initialIndex: i));
    }

    // 2. Sort candidates by score descending, breaking ties by initial discovery order
    scored.sort((a, b) {
      final diff = b.score.compareTo(a.score);
      if (diff != 0) return diff;
      return a.initialIndex.compareTo(b.initialIndex);
    });

    // 3. Deduplicate by canonical signature (same title and same artist)
    // preserving the highest-scored instance while merging rich artwork/MBID
    final seenPairs = <String>{};
    final result = <YouTubeVideo>[];

    for (final item in scored) {
      final v = item.video;
      final normT = (v.canonicalTitle ?? v.title).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final normA = (v.canonicalArtist ?? v.channelTitle).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final key = '$normT::$normA';

      if (key.isNotEmpty && seenPairs.add(key)) {
        result.add(v);
      }
    }

    return result;
  }
}
