import 'package:dio/dio.dart';
import '../../domain/artwork_query.dart';
import '../artwork_match_validator.dart';
import '../artwork_rate_limiter.dart';

/// Resolved candidate from MusicBrainz containing the verified Release MBID.
class MusicBrainzMatch {
  final String releaseMbid;
  final String recordingTitle;
  final String artistName;
  final String releaseTitle;
  final double confidence;

  const MusicBrainzMatch({
    required this.releaseMbid,
    required this.recordingTitle,
    required this.artistName,
    required this.releaseTitle,
    required this.confidence,
  });
}

/// Communicates with MusicBrainz API v2 with rate limiting and strict User-Agent.
class MusicBrainzProvider {
  final Dio dio;
  final ArtworkRateLimiter rateLimiter;
  final ArtworkMatchValidator validator;

  static const String userAgent = 'Miee/2.0.0 ( https://github.com/revanth-kumar-02/Miee )';

  MusicBrainzProvider({
    Dio? dio,
    ArtworkRateLimiter? rateLimiter,
    ArtworkMatchValidator? validator,
  })  : dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
                headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
              ),
            ),
        rateLimiter = rateLimiter ?? ArtworkRateLimiter(),
        validator = validator ?? const ArtworkMatchValidator();

  /// Searches MusicBrainz for the track and returns the best matching release MBID.
  Future<MusicBrainzMatch?> findReleaseMatch(ArtworkQuery query) async {
    final title = query.title.trim();
    final hasIsrc = query.isrc != null && query.isrc!.trim().isNotEmpty;

    if (title.isEmpty && !hasIsrc) {
      return null;
    }

    return rateLimiter.run<MusicBrainzMatch?>(() async {
      try {
        final luceneQuery = _buildLuceneQuery(query);
        final response = await dio.get<Map<String, dynamic>>(
          'https://musicbrainz.org/ws/2/recording/',
          queryParameters: {
            'query': luceneQuery,
            'fmt': 'json',
            'limit': 5,
          },
        );

        if (response.statusCode != 200 || response.data == null) {
          return null;
        }

        final recordings = response.data!['recordings'] as List<dynamic>?;
        if (recordings == null || recordings.isEmpty) {
          return null;
        }

        MusicBrainzMatch? bestMatch;
        double highestConfidence = 0.0;

        for (final rec in recordings) {
          if (rec is! Map<String, dynamic>) continue;

          final recTitle = rec['title'] as String? ?? '';
          final artistCredit = rec['artist-credit'] as List<dynamic>?;
          final recArtist = artistCredit != null && artistCredit.isNotEmpty
              ? (artistCredit[0]['name'] as String? ?? '')
              : '';

          final releases = rec['releases'] as List<dynamic>?;
          if (releases == null || releases.isEmpty) continue;

          for (final rel in releases) {
            if (rel is! Map<String, dynamic>) continue;
            final releaseMbid = rel['id'] as String?;
            final releaseTitle = rel['title'] as String? ?? '';
            if (releaseMbid == null || releaseMbid.isEmpty) continue;

            final candidateDuration = (rec['length'] as num?)?.toInt();
            final confidence = validator.validateMatch(
              query: query,
              candidateTitle: recTitle,
              candidateArtist: recArtist,
              candidateAlbum: releaseTitle,
              candidateDurationMs: candidateDuration,
            );

            if (confidence > highestConfidence && confidence >= 0.75) {
              highestConfidence = confidence;
              bestMatch = MusicBrainzMatch(
                releaseMbid: releaseMbid,
                recordingTitle: recTitle,
                artistName: recArtist,
                releaseTitle: releaseTitle,
                confidence: confidence,
              );
            }
          }
        }

        return bestMatch;
      } on DioException catch (_) {
        // Handle 404, 429, 503, timeouts gracefully
        return null;
      } catch (_) {
        return null;
      }
    });
  }

  String _buildLuceneQuery(ArtworkQuery query) {
    final cleanTitle = _escapeLucene(ArtworkMatchValidator.normalize(query.title));
    final missingArtist = ArtworkMatchValidator.isMissingArtist(query.artist);
    final cleanArtist = missingArtist
        ? ''
        : _escapeLucene(ArtworkMatchValidator.normalize(query.artist));

    if (query.isrc != null && query.isrc!.isNotEmpty) {
      return 'isrc:${_escapeLucene(query.isrc!)}';
    }

    if (query.album != null && query.album!.isNotEmpty) {
      final cleanAlbum = _escapeLucene(ArtworkMatchValidator.normalize(query.album!));
      if (cleanArtist.isNotEmpty) {
        return 'recording:"$cleanTitle" AND artist:"$cleanArtist" AND release:"$cleanAlbum"';
      }
      return 'recording:"$cleanTitle" AND release:"$cleanAlbum"';
    }

    if (cleanArtist.isNotEmpty) {
      return 'recording:"$cleanTitle" AND artist:"$cleanArtist"';
    }
    return 'recording:"$cleanTitle"';
  }

  String _escapeLucene(String text) {
    // Escape Lucene special characters: + - && || ! ( ) { } [ ] ^ " ~ * ? : \ /
    return text.replaceAll(RegExp(r'[\+\-\&\|\!\(\)\{\}\[\]\^\"~\*\?\:\\\/]'), ' ').trim();
  }
}

