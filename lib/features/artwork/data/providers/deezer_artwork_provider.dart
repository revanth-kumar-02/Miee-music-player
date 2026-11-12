import 'dart:convert';
import 'package:dio/dio.dart';
import '../../domain/artwork_provider_interface.dart';
import '../../domain/artwork_query.dart';
import '../../domain/artwork_source.dart';
import '../../domain/resolved_artwork.dart';
import '../artwork_match_validator.dart';

/// Secondary online artwork provider querying Deezer's public search API.
class DeezerArtworkProvider implements ArtworkProvider {
  final Dio dio;
  final ArtworkMatchValidator validator;
  @override
  final bool isEnabled;

  DeezerArtworkProvider({
    Dio? dio,
    ArtworkMatchValidator? validator,
    this.isEnabled = true,
  })  : dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
              ),
            ),
        validator = validator ?? const ArtworkMatchValidator();

  @override
  String get id => 'deezer';

  @override
  ArtworkSource get source => ArtworkSource.deezer;

  @override
  int get priority => 4;

  @override
  Future<ResolvedArtwork?> resolve(ArtworkQuery query) async {
    if (!isEnabled) return null;

    final title = query.title.trim();
    final isrc = query.isrc?.trim();
    if (title.isEmpty && (isrc == null || isrc.isEmpty)) return null;

    try {
      // Direct ISRC lookup when available for exact catalog matching
      if (isrc != null && isrc.isNotEmpty) {
        final isrcResp = await dio.get<dynamic>(
          'https://api.deezer.com/2.0/track/isrc:${Uri.encodeComponent(isrc)}',
        );
        if (isrcResp.statusCode == 200 && isrcResp.data != null) {
          final Map<String, dynamic> isrcData = isrcResp.data is String
              ? jsonDecode(isrcResp.data as String) as Map<String, dynamic>
              : Map<String, dynamic>.from(isrcResp.data as Map);
          if (isrcData['error'] == null) {
            final albumObj = isrcData['album'] as Map<String, dynamic>?;
            final coverUrl = (albumObj?['cover_xl'] as String?) ??
                (albumObj?['cover_big'] as String?) ??
                (albumObj?['cover_medium'] as String?);
            if (coverUrl != null && coverUrl.isNotEmpty) {
              return ResolvedArtwork(
                imageUrl: coverUrl,
                source: ArtworkSource.deezer,
                confidence: 1.0,
                attribution: 'Deezer',
                width: 1000,
                height: 1000,
                resolvedAt: DateTime.now(),
              );
            }
          }
        }
      }

      if (title.isEmpty) return null;

      final cleanTitle = ArtworkMatchValidator.normalize(title);
      final cleanArtist = ArtworkMatchValidator.isMissingArtist(query.artist)
          ? ''
          : ArtworkMatchValidator.normalize(query.artist);
      final searchQuery = '$cleanArtist $cleanTitle'.trim();
      if (searchQuery.isEmpty) return null;

      final response = await dio.get<dynamic>(
        'https://api.deezer.com/search',
        queryParameters: {
          'q': searchQuery,
          'limit': 5,
        },
      );

      if (response.statusCode != 200 || response.data == null) {
        return null;
      }

      final Map<String, dynamic> responseData = response.data is String
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : Map<String, dynamic>.from(response.data as Map);

      if (responseData['error'] != null) {
        return null;
      }

      final dataList = responseData['data'] as List<dynamic>?;
      if (dataList == null || dataList.isEmpty) {
        return null;
      }

      ResolvedArtwork? bestArtwork;
      double highestConfidence = 0.0;

      for (final item in dataList) {
        if (item is! Map<String, dynamic>) continue;

        final candidateTitle = item['title'] as String? ?? '';
        final artistObj = item['artist'] as Map<String, dynamic>?;
        final candidateArtist = artistObj?['name'] as String? ?? '';
        final albumObj = item['album'] as Map<String, dynamic>?;
        final candidateAlbum = albumObj?['title'] as String? ?? '';
        final candidateDurationSec = (item['duration'] as num?)?.toInt();
        final candidateDurationMs = candidateDurationSec != null ? candidateDurationSec * 1000 : null;

        final confidence = validator.validateMatch(
          query: query,
          candidateTitle: candidateTitle,
          candidateArtist: candidateArtist,
          candidateAlbum: candidateAlbum,
          candidateDurationMs: candidateDurationMs,
        );

        if (confidence > highestConfidence && confidence >= 0.75) {
          // Extract highest resolution cover available
          final coverUrl = (albumObj?['cover_xl'] as String?) ??
              (albumObj?['cover_big'] as String?) ??
              (albumObj?['cover_medium'] as String?);

          if (coverUrl != null && coverUrl.isNotEmpty) {
            highestConfidence = confidence;
            bestArtwork = ResolvedArtwork(
              imageUrl: coverUrl,
              source: ArtworkSource.deezer,
              confidence: confidence,
              attribution: 'Deezer',
              width: 1000,
              height: 1000,
              resolvedAt: DateTime.now(),
            );
          }
        }
      }

      return bestArtwork;
    } on DioException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }
}

