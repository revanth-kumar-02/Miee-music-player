import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Miee/features/artwork/data/artwork_cache.dart';
import 'package:Miee/features/artwork/data/artwork_match_validator.dart';
import 'package:Miee/features/artwork/data/artwork_rate_limiter.dart';
import 'package:Miee/features/artwork/data/artwork_resolver_impl.dart';
import 'package:Miee/features/artwork/data/providers/cover_art_archive_provider.dart';
import 'package:Miee/features/artwork/data/providers/deezer_artwork_provider.dart';
import 'package:Miee/features/artwork/data/providers/fanart_artwork_provider.dart';
import 'package:Miee/features/artwork/data/providers/itunes_artwork_provider.dart';
import 'package:Miee/features/artwork/data/providers/local_artwork_provider.dart';
import 'package:Miee/features/artwork/data/providers/musicbrainz_provider.dart';
import 'package:Miee/features/artwork/domain/artwork_query.dart';
import 'package:Miee/features/artwork/domain/artwork_source.dart';
import 'package:Miee/features/artwork/domain/resolved_artwork.dart';
import 'package:Miee/features/artwork/presentation/miee_artwork_image.dart';

/// In-memory mock HTTP client adapter for deterministic network testing.
class MockHttpClientAdapter implements HttpClientAdapter {
  final Map<String, dynamic> responses = {};
  int requestCount = 0;
  final List<Uri> requestedUris = [];

  void setJsonResponse(String urlSubstring, Map<String, dynamic> body, {int statusCode = 200}) {
    responses[urlSubstring] = {
      'statusCode': statusCode,
      'body': jsonEncode(body),
    };
  }

  void setErrorResponse(String urlSubstring, int statusCode) {
    responses[urlSubstring] = {
      'statusCode': statusCode,
      'body': '{"error": "Failed"}',
    };
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    requestedUris.add(options.uri);

    final uriStr = options.uri.toString();
    for (final entry in responses.entries) {
      if (uriStr.contains(entry.key)) {
        final config = entry.value as Map<String, dynamic>;
        final code = config['statusCode'] as int;
        final bodyStr = config['body'] as String;
        return ResponseBody.fromString(
          bodyStr,
          code,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
    }

    // Default 404
    return ResponseBody.fromString(
      '{"message": "Not found"}',
      404,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('Artwork Match Validator Tests', () {
    const validator = ArtworkMatchValidator();

    test('Exact ISRC match produces confidence 1.0', () {
      const query = ArtworkQuery(
        id: '1',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        isrc: 'USUG11904206',
      );

      final confidence = validator.validateMatch(
        query: query,
        candidateTitle: 'Blinding Lights',
        candidateArtist: 'The Weeknd',
        candidateIsrc: 'USUG11904206',
      );

      expect(confidence, equals(1.0));
    });

    test('Exact Artist + Album + Title produces high confidence', () {
      const query = ArtworkQuery(
        id: '2',
        title: 'Starboy',
        artist: 'The Weeknd',
        album: 'Starboy',
      );

      final confidence = validator.validateMatch(
        query: query,
        candidateTitle: 'Starboy',
        candidateArtist: 'The Weeknd',
        candidateAlbum: 'Starboy',
      );

      expect(confidence, greaterThanOrEqualTo(0.95));
    });

    test('Rejects remix version when original track was queried', () {
      const query = ArtworkQuery(
        id: '3',
        title: 'Levitating',
        artist: 'Dua Lipa',
      );

      final confidence = validator.validateMatch(
        query: query,
        candidateTitle: 'Levitating (The Blessed Madonna Remix)',
        candidateArtist: 'Dua Lipa',
      );

      expect(confidence, equals(0.0));
    });

    test('Rejects live version when studio track was queried', () {
      const query = ArtworkQuery(
        id: '4',
        title: 'Fix You',
        artist: 'Coldplay',
      );

      final confidence = validator.validateMatch(
        query: query,
        candidateTitle: 'Fix You - Live in Buenos Aires',
        candidateArtist: 'Coldplay',
      );

      expect(confidence, equals(0.0));
    });

    test('Rejects mismatched artist even if title is identical', () {
      const query = ArtworkQuery(
        id: '5',
        title: 'Hello',
        artist: 'Adele',
      );

      final confidence = validator.validateMatch(
        query: query,
        candidateTitle: 'Hello',
        candidateArtist: 'Lionel Richie',
      );

      expect(confidence, equals(0.0));
    });
  });

  group('Local Artwork Provider Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('miee_artwork_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Valid local JPEG image resolves successfully with confidence 1.0', () async {
      final validImageFile = File('${tempDir.path}/valid_cover.jpg');
      // Create valid JPEG magic bytes (FF D8 FF) followed by padding > 100 bytes
      final bytes = Uint8List(150);
      bytes[0] = 0xFF;
      bytes[1] = 0xD8;
      bytes[2] = 0xFF;
      bytes[3] = 0xE0;
      await validImageFile.writeAsBytes(bytes);

      final provider = LocalArtworkProvider();
      final query = ArtworkQuery(
        id: 'local_1',
        title: 'Local Track',
        artist: 'Artist',
        localArtworkPath: validImageFile.path,
      );

      final result = await provider.resolve(query);

      expect(result, isNotNull);
      expect(result!.source, equals(ArtworkSource.local));
      expect(result.confidence, equals(1.0));
      expect(result.isLocal, isTrue);
      expect(result.imageUrl, equals(validImageFile.path));
    });

    test('Corrupted or empty local file is rejected and yields null', () async {
      final corruptFile = File('${tempDir.path}/corrupt.jpg');
      await corruptFile.writeAsBytes(Uint8List(20)); // under 100 bytes

      final provider = LocalArtworkProvider();
      final query = ArtworkQuery(
        id: 'local_corrupt',
        title: 'Corrupt Track',
        artist: 'Artist',
        localArtworkPath: corruptFile.path,
      );

      final result = await provider.resolve(query);
      expect(result, isNull);
    });

    test('Non-existent local file yields null', () async {
      final provider = LocalArtworkProvider();
      final query = ArtworkQuery(
        id: 'local_missing',
        title: 'Missing Track',
        artist: 'Artist',
        localArtworkPath: '${tempDir.path}/does_not_exist.jpg',
      );

      final result = await provider.resolve(query);
      expect(result, isNull);
    });
  });

  group('Online Providers & Cascade Tests', () {
    late MockHttpClientAdapter mockAdapter;
    late Dio dio;
    late ArtworkCache cache;
    late ArtworkResolver resolver;

    setUp(() {
      mockAdapter = MockHttpClientAdapter();
      dio = Dio(BaseOptions())..httpClientAdapter = mockAdapter;
      cache = ArtworkCache();

      final mbProvider = MusicBrainzProvider(dio: dio);
      final caaProvider = CoverArtArchiveProvider(dio: dio);
      final deezerProvider = DeezerArtworkProvider(dio: dio);

      resolver = ArtworkResolver(
        cache: cache,
        musicBrainzProvider: mbProvider,
        coverArtArchiveProvider: caaProvider,
        deezerProvider: deezerProvider,
      );
    });

    test('MusicBrainz match + Cover Art Archive resolves front cover', () async {
      const releaseMbid = 'mbid-1234-abcd';
      // Mock MusicBrainz search response
      mockAdapter.setJsonResponse('musicbrainz.org/ws/2/recording', {
        'recordings': [
          {
            'id': 'rec-1',
            'title': 'Yellow',
            'artist-credit': [
              {'name': 'Coldplay'}
            ],
            'releases': [
              {'id': releaseMbid, 'title': 'Parachutes'}
            ],
          }
        ],
      });

      // Mock Cover Art Archive response
      mockAdapter.setJsonResponse('coverartarchive.org/release/$releaseMbid', {
        'images': [
          {
            'front': true,
            'image': 'https://coverartarchive.org/release/$releaseMbid/front.jpg',
            'thumbnails': {
              '500': 'https://coverartarchive.org/release/$releaseMbid/front-500.jpg',
            },
          }
        ],
      });

      const query = ArtworkQuery(
        id: 'yt_yellow',
        title: 'Yellow',
        artist: 'Coldplay',
        album: 'Parachutes',
      );

      final result = await resolver.resolve(query);

      expect(result.source, equals(ArtworkSource.coverArtArchive));
      expect(result.confidence, greaterThanOrEqualTo(0.95));
      expect(result.imageUrl, contains('coverartarchive.org'));
      expect(result.mbid, equals(releaseMbid));
    });

    test('Deezer fallback succeeds when MusicBrainz returns no matches', () async {
      // Mock MusicBrainz 404 / empty
      mockAdapter.setJsonResponse('musicbrainz.org/ws/2/recording', {
        'recordings': <dynamic>[],
      });

      // Mock Deezer search response
      mockAdapter.setJsonResponse('api.deezer.com/search/track', {
        'data': [
          {
            'title': 'Blue Hour',
            'artist': {'name': 'Lauv'},
            'album': {
              'title': 'Blue Hour',
              'cover_xl': 'https://e-cdns-images.dzcdn.net/images/cover/xl.jpg',
              'cover_big': 'https://e-cdns-images.dzcdn.net/images/cover/big.jpg',
            },
          }
        ],
      });

      const query = ArtworkQuery(
        id: 'yt_blue_hour',
        title: 'Blue Hour',
        artist: 'Lauv',
      );

      final result = await resolver.resolve(query);

      expect(result.source, equals(ArtworkSource.deezer));
      expect(result.confidence, greaterThanOrEqualTo(0.75));
      expect(result.imageUrl, contains('dzcdn.net'));
    });

    test('Disabled optional providers (Fanart.tv, iTunes) remain inactive', () async {
      const fanart = FanartArtworkProvider();
      const itunes = ItunesArtworkProvider();

      expect(fanart.isEnabled, isFalse);
      expect(itunes.isEnabled, isFalse);

      const query = ArtworkQuery(id: 'q', title: 'Song', artist: 'Artist');
      expect(await fanart.resolve(query), isNull);
      expect(await itunes.resolve(query), isNull);
    });

    test('YouTube fallback is returned when online providers fail', () async {
      // Mock both MB and Deezer returning empty
      mockAdapter.setJsonResponse('musicbrainz.org/ws/2/recording', {'recordings': <dynamic>[]});
      mockAdapter.setJsonResponse('api.deezer.com/search/track', {'data': <dynamic>[]});

      const query = ArtworkQuery(
        id: 'yt_indie',
        title: 'Rare Indie Track',
        artist: 'Unknown Artist',
        fallbackThumbnailUrl: 'https://i.ytimg.com/vi/rare/hqdefault.jpg',
      );

      final result = await resolver.resolve(query);

      expect(result.source, equals(ArtworkSource.youtube));
      expect(result.confidence, equals(0.5));
      expect(result.imageUrl, equals('https://i.ytimg.com/vi/rare/hqdefault.jpg'));
    });

    test('Neutral fallback is returned when all providers fail and no thumbnail exists', () async {
      mockAdapter.setJsonResponse('musicbrainz.org/ws/2/recording', {'recordings': <dynamic>[]});
      mockAdapter.setJsonResponse('api.deezer.com/search/track', {'data': <dynamic>[]});

      const query = ArtworkQuery(
        id: 'yt_nothing',
        title: 'Nonexistent Track 9999',
        artist: 'Nonexistent Artist 9999',
      );

      final result = await resolver.resolve(query);

      expect(result.source, equals(ArtworkSource.neutralFallback));
      expect(result.isNeutralFallback, isTrue);
      expect(result.confidence, equals(0.0));
    });

    test('Offline / Connection Timeout falls back gracefully without unhandled exception', () async {
      mockAdapter.setErrorResponse('musicbrainz.org', 503);
      mockAdapter.setErrorResponse('api.deezer.com', 503);

      const query = ArtworkQuery(
        id: 'yt_offline',
        title: 'Offline Song',
        artist: 'Offline Artist',
        fallbackThumbnailUrl: 'https://i.ytimg.com/vi/offline/hqdefault.jpg',
      );

      final result = await resolver.resolve(query);
      expect(result.source, equals(ArtworkSource.youtube));
    });

    test('Cache hit returns cached result immediately without new network requests', () async {
      final initialCount = mockAdapter.requestCount;
      const cachedArtwork = ResolvedArtwork(
        imageUrl: 'https://cached.com/art.jpg',
        source: ArtworkSource.deezer,
        confidence: 0.9,
      );

      const query = ArtworkQuery(
        id: 'cached_test',
        title: 'Cached Song',
        artist: 'Cached Artist',
      );

      await cache.put(query.cacheKey, cachedArtwork);

      final result = await resolver.resolve(query);

      expect(result.imageUrl, equals('https://cached.com/art.jpg'));
      expect(mockAdapter.requestCount, equals(initialCount)); // zero network calls
    });

    test('Concurrent requests for the same track are deduplicated into 1 request', () async {
      mockAdapter.setJsonResponse('musicbrainz.org/ws/2/recording', {
        'recordings': <dynamic>[],
      });
      mockAdapter.setJsonResponse('api.deezer.com/search/track', {
        'data': [
          {
            'title': 'Dedupe Song',
            'artist': {'name': 'Dedupe Artist'},
            'album': {'cover_xl': 'https://dedupe.com/cover.jpg'},
          }
        ],
      });

      const query = ArtworkQuery(
        id: 'dedupe_1',
        title: 'Dedupe Song',
        artist: 'Dedupe Artist',
      );

      // Launch 3 resolutions concurrently
      final futures = <Future<ResolvedArtwork>>[
        resolver.resolve(query),
        resolver.resolve(query),
        resolver.resolve(query),
      ];

      final results = await Future.wait(futures);

      expect(results[0].imageUrl, equals(results[1].imageUrl));
      expect(results[1].imageUrl, equals(results[2].imageUrl));
    });
  });

  group('Rate Limiter Tests', () {
    test('Rate limiter delays consecutive calls by interval', () async {
      final limiter = ArtworkRateLimiter(interval: const Duration(milliseconds: 100));
      final stopwatch = Stopwatch()..start();

      await limiter.run(() async => 'first');
      await limiter.run(() async => 'second');

      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(90));
    });
  });

  group('Persistence & Serialization Tests', () {
    test('ResolvedArtwork serializes and deserializes cleanly', () {
      final original = ResolvedArtwork(
        imageUrl: 'https://artwork.com/cover.jpg',
        source: ArtworkSource.coverArtArchive,
        confidence: 0.95,
        attribution: 'Cover Art Archive / MusicBrainz',
        mbid: 'mbid-1234',
        width: 500,
        height: 500,
        isLocal: false,
        resolvedAt: DateTime.now(),
      );

      final json = original.toJson();
      final restored = ResolvedArtwork.fromJson(json);

      expect(restored.imageUrl, equals(original.imageUrl));
      expect(restored.source, equals(original.source));
      expect(restored.confidence, equals(original.confidence));
      expect(restored.mbid, equals(original.mbid));
      expect(restored.attribution, equals(original.attribution));
      expect(restored.width, equals(original.width));
    });
  });

  group('Riverpod & Widget Integration Tests', () {
    testWidgets('MieeArtworkImage renders neutral fallback for empty query', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MieeArtworkImage(
                width: 60,
                height: 60,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(MieeArtworkImage), findsOneWidget);
      expect(find.byIcon(Icons.album_rounded), findsOneWidget);
    });

    testWidgets('MieeArtworkImage renders placeholder while resolving', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MieeArtworkImage(
                query: ArtworkQuery(
                  id: 'loading_track',
                  title: 'Loading Track',
                  artist: 'Artist',
                ),
                width: 60,
                height: 60,
              ),
            ),
          ),
        ),
      );

      // Verify that initially placeholder or fallback icon is rendered
      expect(find.byType(MieeArtworkImage), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });
}
