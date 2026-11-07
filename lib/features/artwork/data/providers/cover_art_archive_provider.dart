import 'package:dio/dio.dart';
import '../../domain/artwork_source.dart';
import '../../domain/resolved_artwork.dart';

/// Fetches album cover artwork from Cover Art Archive using a verified MusicBrainz Release MBID.
class CoverArtArchiveProvider {
  final Dio dio;

  CoverArtArchiveProvider({Dio? dio})
      : dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
                headers: {
                  'User-Agent': 'Miee/2.0.0 ( https://github.com/revanth-kumar-02/Miee )',
                  'Accept': 'application/json',
                },
              ),
            );

  /// Retrieves front cover artwork for the specified [mbid].
  Future<ResolvedArtwork?> fetchCoverArt({
    required String mbid,
    double confidence = 0.95,
  }) async {
    if (mbid.isEmpty) return null;

    try {
      final response = await dio.get<Map<String, dynamic>>(
        'https://coverartarchive.org/release/$mbid',
      );

      if (response.statusCode != 200 || response.data == null) {
        return null;
      }

      final images = response.data!['images'] as List<dynamic>?;
      if (images == null || images.isEmpty) {
        return null;
      }

      String? frontImageUrl;
      int? width;
      int? height;

      // Find the primary front image
      for (final img in images) {
        if (img is! Map<String, dynamic>) continue;
        final isFront = img['front'] as bool? ?? false;
        if (isFront) {
          final thumbnails = img['thumbnails'] as Map<String, dynamic>?;
          // Prefer 500px thumbnail or direct image
          frontImageUrl = (thumbnails?['500'] as String?) ??
              (thumbnails?['large'] as String?) ??
              (img['image'] as String?);
          break;
        }
      }

      // If no image had front==true, fallback to the first available image
      if (frontImageUrl == null && images.isNotEmpty) {
        final first = images[0] as Map<String, dynamic>;
        final thumbnails = first['thumbnails'] as Map<String, dynamic>?;
        frontImageUrl = (thumbnails?['500'] as String?) ??
            (thumbnails?['large'] as String?) ??
            (first['image'] as String?);
      }

      if (frontImageUrl == null || frontImageUrl.isEmpty) {
        return null;
      }

      // Ensure HTTPS
      if (frontImageUrl.startsWith('http://')) {
        frontImageUrl = frontImageUrl.replaceFirst('http://', 'https://');
      }

      return ResolvedArtwork(
        imageUrl: frontImageUrl,
        source: ArtworkSource.coverArtArchive,
        confidence: confidence,
        attribution: 'Cover Art Archive / MusicBrainz',
        mbid: mbid,
        width: width,
        height: height,
        resolvedAt: DateTime.now(),
      );
    } on DioException catch (_) {
      // 404 (no artwork archived for this release) or network error
      return null;
    } catch (_) {
      return null;
    }
  }
}

