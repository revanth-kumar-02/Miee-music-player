import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/widget/miee_widget_sync_service.dart';
import 'package:Miee/features/artwork/data/artwork_cache.dart';
import 'package:Miee/features/artwork/data/artwork_match_validator.dart';
import 'package:Miee/features/artwork/data/artwork_resolver_impl.dart';
import 'package:Miee/features/artwork/data/providers/cover_art_archive_provider.dart';
import 'package:Miee/features/artwork/data/providers/deezer_artwork_provider.dart';
import 'package:Miee/features/artwork/data/providers/itunes_artwork_provider.dart';
import 'package:Miee/features/artwork/data/providers/musicbrainz_provider.dart';
import 'package:Miee/features/artwork/data/providers/youtube_fallback_provider.dart';
import 'package:Miee/features/artwork/domain/artwork_query.dart';
import 'package:Miee/features/artwork/domain/artwork_source.dart';
import 'package:Miee/features/artwork/domain/resolved_artwork.dart';
import 'package:Miee/features/artwork/presentation/artwork_providers.dart';
import 'package:Miee/features/artwork/presentation/miee_artwork_image.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/features/metadata/data/itunes_metadata_service.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/models/track.dart';

class _RouteResponse {
  final int statusCode;
  final dynamic body;
  final Map<String, List<String>> headers;
  final bool isBytes;

  _RouteResponse.json(this.body, {this.statusCode = 200})
      : isBytes = false,
        headers = {
          Headers.contentTypeHeader: ['application/json']
        };

  _RouteResponse.bytes(
    List<int> bytes, {
    this.statusCode = 200,
    String contentType = 'image/jpeg',
    int? contentLength,
  })  : body = Uint8List.fromList(bytes),
        isBytes = true,
        headers = {
          Headers.contentTypeHeader: [contentType],
          if (contentLength != null)
            Headers.contentLengthHeader: [contentLength.toString()],
        };
}

class _MockAdapter implements HttpClientAdapter {
  final Map<String, _RouteResponse Function(RequestOptions)> routes = {};
  final List<String> requestedUrls = [];

  void on(String substring, _RouteResponse Function(RequestOptions) handler) {
    routes[substring] = handler;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requestedUrls.add(url);

    for (final entry in routes.entries) {
      if (url.contains(entry.key)) {
        final res = entry.value(options);
        if (res.isBytes) {
          return ResponseBody.fromBytes(
            res.body as Uint8List,
            res.statusCode,
            headers: res.headers,
          );
        }
        return ResponseBody.fromString(
          jsonEncode(res.body),
          res.statusCode,
          headers: res.headers,
        );
      }
    }

    return ResponseBody.fromString('Not Found', 404);
  }

  @override
  void close({bool force = false}) {}
}

List<int> _fakeJpegBytes({int size = 2048}) {
  final bytes = List<int>.filled(size, 0xAB);
  bytes[0] = 0xFF;
  bytes[1] = 0xD8;
  bytes[2] = 0xFF;
  bytes[3] = 0xE0;
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ArtworkMatchValidator - Accuracy, Unicode & Edge Cases', () {
    const validator = ArtworkMatchValidator();

    test('Preserves Unicode scripts (Tamil/Hindi) instead of wiping to empty', () {
      expect(ArtworkMatchValidator.normalize('நெஞ்சமே நெஞ்சமே'), isNotEmpty);
      final conf = validator.validateMatch(
        query: const ArtworkQuery(
          id: 'u1',
          title: 'நெஞ்சமே நெஞ்சமே',
          artist: 'A. R. Rahman',
        ),
        candidateTitle: 'நெஞ்சமே நெஞ்சமே',
        candidateArtist: 'AR Rahman',
      );
      expect(conf, greaterThanOrEqualTo(0.85));
    });

    test('Word-boundary version guard does not confuse "Alive" with "live"', () {
      final conf = validator.validateMatch(
        query: const ArtworkQuery(
          id: 'v1',
          title: 'Stay Alive',
          artist: 'Jose Gonzalez',
        ),
        candidateTitle: 'Stay Alive',
        candidateArtist: 'Jose Gonzalez',
      );
      expect(conf, greaterThanOrEqualTo(0.85));

      final liveReject = validator.validateMatch(
        query: const ArtworkQuery(
          id: 'v2',
          title: 'Stay Alive',
          artist: 'Jose Gonzalez',
        ),
        candidateTitle: 'Stay Alive (Live)',
        candidateArtist: 'Jose Gonzalez',
      );
      expect(liveReject, equals(0.0));
    });

    test('Missing or unknown artist matches only when title + album/duration match', () {
      final withAlbum = validator.validateMatch(
        query: const ArtworkQuery(
          id: 'm1',
          title: 'Blinding Lights',
          artist: 'Unknown Artist',
          album: 'After Hours',
          durationMs: 200000,
        ),
        candidateTitle: 'Blinding Lights',
        candidateArtist: 'The Weeknd',
        candidateAlbum: 'After Hours',
        candidateDurationMs: 200000,
      );
      expect(withAlbum, greaterThanOrEqualTo(0.80));

      final lowTitleSim = validator.validateMatch(
        query: const ArtworkQuery(
          id: 'm2',
          title: 'Blinding Lights',
          artist: 'Unknown Artist',
        ),
        candidateTitle: 'Completely Different Song',
        candidateArtist: 'The Weeknd',
      );
      expect(lowTitleSim, equals(0.0));
    });
  });

  group('YouTube Thumbnail Selection & Catalog Fallback', () {
    test('Sanitizes bogus placeholder URL and normalizes img.youtube.com', () {
      const provider = YouTubeFallbackProvider();
      final query = ArtworkQuery.fromMusicItem(
        const YouTubeVideo(
          id: 'dQw4w9WgXcQ',
          title: 'Never Gonna Give You Up',
          channelTitle: 'Rick Astley',
          thumbnailUrl: 'https://i.ytimg.com/vi/placeholder/hqdefault.jpg',
          duration: '3:33',
          viewCount: '1B',
        ),
      );
      expect(query.fallbackThumbnailUrl,
          equals('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'));

      final candidates = provider.buildCandidateUrls(query);
      expect(candidates.first,
          equals('https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg'));
      expect(candidates,
          contains('https://i.ytimg.com/vi/dQw4w9WgXcQ/sddefault.jpg'));
      expect(candidates,
          contains('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'));
    });

    test('YouTubeFallbackProvider skips 404 maxresdefault and picks sddefault',
        () async {
      final adapter = _MockAdapter();
      adapter.on('maxresdefault.jpg', (_) => _RouteResponse.bytes([], statusCode: 404));
      adapter.on(
        'sddefault.jpg',
        (_) => _RouteResponse.bytes(_fakeJpegBytes(), contentLength: 2048),
      );

      final dio = Dio()..httpClientAdapter = adapter;
      final provider = YouTubeFallbackProvider(dio: dio);

      const query = ArtworkQuery(
        id: 'youtube_abc12345678',
        title: 'Test Song',
        artist: 'Test Artist',
        source: 'youtube',
      );
      final resolved = await provider.resolve(query);
      expect(resolved, isNotNull);
      expect(resolved!.imageUrl,
          equals('https://i.ytimg.com/vi/abc12345678/sddefault.jpg'));
      expect(resolved.source, equals(ArtworkSource.youtube));
    });

    test('YouTube resolver falls back to Deezer when iTunes fails', () async {
      final adapter = _MockAdapter();
      adapter.on('itunes.apple.com', (_) => _RouteResponse.json({'results': []}));
      adapter.on(
        'api.deezer.com/search',
        (_) => _RouteResponse.json({
          'data': [
            {
              'title': 'Midnight City',
              'duration': 243,
              'artist': {'name': 'M83'},
              'album': {
                'title': 'Hurry Up, We Are Dreaming',
                'cover_xl': 'https://cdn-images.dzcdn.net/images/cover/m83/1000x1000.jpg',
              },
            }
          ],
        }),
      );

      final dio = Dio()..httpClientAdapter = adapter;
      final resolver = ArtworkResolver(
        itunesProvider: ItunesArtworkProvider(
          metadataService: ItunesMetadataService(dio: dio),
        ),
        deezerProvider: DeezerArtworkProvider(dio: dio),
        youtubeFallbackProvider: const YouTubeFallbackProvider(),
      );

      const query = ArtworkQuery(
        id: 'youtube_dX3k_QDnzHE',
        title: 'Midnight City (Official Video)',
        artist: 'M83',
        source: 'youtube',
      );

      final resolved = await resolver.resolve(query);
      expect(resolved.source, equals(ArtworkSource.deezer));
      expect(resolved.imageUrl,
          equals('https://cdn-images.dzcdn.net/images/cover/m83/1000x1000.jpg'));
    });
  });

  group('Image Content Validation, Disk Cache Reuse & Expired URL Refresh', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('miee_art_cache_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Rejects HTML/non-image HTTP 200 payload and does not cache it',
        () async {
      final adapter = _MockAdapter();
      adapter.on(
        'bad-image.example.com',
        (_) => _RouteResponse.bytes(
          utf8.encode('<html><body>Not an image</body></html>'),
          statusCode: 200,
          contentType: 'text/html',
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final cache = ArtworkCache(cacheDirectory: tempDir, dio: dio);

      final path = await cache.cacheImageFromUrl(
        'bad_key',
        'https://bad-image.example.com/cover.jpg',
      );
      expect(path, isNull);
    });

    test('Caches validated image on disk, reuses it, and refreshes on forceRefresh',
        () async {
      var version = 1;
      final adapter = _MockAdapter();
      adapter.on('itunes.apple.com', (_) {
        return _RouteResponse.json({
          'results': [
            {
              'trackId': 100 + version,
              'trackName': 'Starboy',
              'artistName': 'The Weeknd',
              'collectionName': 'Starboy',
              'trackTimeMillis': 230000,
              'artworkUrl100':
                  'https://is1-ssl.mzstatic.com/image/v$version/100x100bb.jpg',
            }
          ]
        });
      });
      adapter.on(
        'mzstatic.com',
        (_) => _RouteResponse.bytes(_fakeJpegBytes(size: 4096)),
      );

      final dio = Dio()..httpClientAdapter = adapter;
      final cache = ArtworkCache(cacheDirectory: tempDir, dio: dio);
      final resolver = ArtworkResolver(
        cache: cache,
        cacheImagesLocally: true,
        itunesProvider: ItunesArtworkProvider(
          metadataService: ItunesMetadataService(dio: dio),
        ),
        deezerProvider: DeezerArtworkProvider(dio: dio, isEnabled: false),
        musicBrainzProvider: MusicBrainzProvider(dio: dio),
        coverArtArchiveProvider: CoverArtArchiveProvider(dio: dio),
      );

      const query = ArtworkQuery(
        id: 'yt_34Na4j8AVgA',
        title: 'Starboy',
        artist: 'The Weeknd',
        source: 'youtube',
      );

      final first = await resolver.resolve(query);
      expect(first.localCachedPath, isNotNull);
      expect(File(first.localCachedPath!).existsSync(), isTrue);
      final requestCountAfterFirst = adapter.requestedUrls.length;

      // Second resolve must reuse cached entry with zero additional network requests
      final second = await resolver.resolve(query);
      expect(second.localCachedPath, equals(first.localCachedPath));
      expect(adapter.requestedUrls.length, equals(requestCountAfterFirst));

      // forceRefresh clears cache and resolves new metadata URL
      version = 2;
      final refreshed = await resolver.resolve(query, forceRefresh: true);
      expect(refreshed.imageUrl, contains('/v2/'));
    });

    test('Re-resolves when cached remote URL is expired and no local file exists',
        () async {
      var expiredCalls = 0;
      final adapter = _MockAdapter();
      adapter.on('expired.example.com', (_) {
        expiredCalls++;
        return _RouteResponse.bytes([], statusCode: 410);
      });
      adapter.on('itunes.apple.com', (_) {
        return _RouteResponse.json({
          'results': [
            {
              'trackId': 555,
              'trackName': 'Numb',
              'artistName': 'Linkin Park',
              'collectionName': 'Meteora',
              'trackTimeMillis': 185000,
              'artworkUrl100':
                  'https://is1-ssl.mzstatic.com/image/fresh/100x100bb.jpg',
            }
          ]
        });
      });
      adapter.on(
        'mzstatic.com',
        (_) => _RouteResponse.bytes(_fakeJpegBytes(size: 3000)),
      );

      final dio = Dio()..httpClientAdapter = adapter;
      final cache = ArtworkCache(cacheDirectory: tempDir, dio: dio);
      const query = ArtworkQuery(
        id: 'yt_kXYiU_JCYtU',
        title: 'Numb',
        artist: 'Linkin Park',
        source: 'youtube',
      );

      // Seed cache with an expired remote URL and no localCachedPath
      await cache.put(
        query.cacheKey,
        const ResolvedArtwork(
          imageUrl: 'https://expired.example.com/old.jpg',
          source: ArtworkSource.itunes,
          confidence: 0.9,
        ),
      );

      final resolver = ArtworkResolver(
        cache: cache,
        cacheImagesLocally: true,
        itunesProvider: ItunesArtworkProvider(
          metadataService: ItunesMetadataService(dio: dio),
        ),
      );

      final resolved = await resolver.resolve(query);
      expect(expiredCalls, equals(1));
      expect(resolved.imageUrl, contains('mzstatic.com/image/fresh/'));
      expect(resolved.localCachedPath, isNotNull);
    });
  });

  group('Unified Local & YouTube Rendering + Android Widget Sync', () {
    testWidgets('Local and YouTube tracks render through MieeArtworkImage',
        (tester) async {
      final tempDir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('miee_widget_render_'),
      );
      final localArtFile = File('${tempDir!.path}/local_art.jpg');
      await tester.runAsync(() => localArtFile.writeAsBytes(_fakeJpegBytes()));

      final localSong = MediaSong(
        id: 'loc_1',
        title: 'Local Track',
        artist: 'Local Artist',
        album: 'Local Album',
        duration: '3:00',
        durationMs: 180000,
        filePath: '/storage/emulated/0/Music/local.mp3',
        artworkPath: localArtFile.path,
      );

      final ytTrack = const YouTubeVideo(
        id: 'dQw4w9WgXcQ',
        title: 'YT Track',
        channelTitle: 'YT Artist',
        thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        duration: '3:30',
        viewCount: '1M',
      ).toTrack();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            artworkResolverProvider.overrideWithValue(
              ArtworkResolver(
                cache: ArtworkCache(),
                itunesProvider: const ItunesArtworkProvider(isEnabled: false),
                deezerProvider: DeezerArtworkProvider(isEnabled: false),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  MieeArtworkImage(musicItem: localSong, width: 64, height: 64),
                  MieeArtworkImage(musicItem: ytTrack, width: 64, height: 64),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      expect(find.byType(MieeArtworkImage), findsNWidgets(2));
      await tester.runAsync(() => tempDir.delete(recursive: true));
    });

    test('Widget sync forwards localCachedPath as artworkPath when resolved',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('miee_widget_sync_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final cachedFile = File('${tempDir.path}/cached_yt.img')
        ..writeAsBytesSync(_fakeJpegBytes());

      final calls = <MethodCall>[];
      const channel = MethodChannel('com.example.miee/widget_overhaul_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final adapter = _MockAdapter();
      final stubResolver = _InlineStubResolver(
        (_) async => ResolvedArtwork(
          imageUrl: 'https://is1-ssl.mzstatic.com/image/600x600bb.jpg',
          localCachedPath: cachedFile.path,
          source: ArtworkSource.itunes,
          confidence: 0.95,
        ),
        dio: Dio()..httpClientAdapter = adapter,
      );

      final syncService = MieeWidgetSyncService(
        null,
        channel: channel,
        artworkResolver: stubResolver,
        autoListen: false,
      );

      const ytTrack = Track(
        id: 'youtube_7wtfhZwyrcc',
        title: 'Believer',
        artist: 'Imagine Dragons',
        imageUrl: 'https://i.ytimg.com/vi/7wtfhZwyrcc/hqdefault.jpg',
        duration: '3:24',
        filePath: 'https://www.youtube.com/watch?v=7wtfhZwyrcc',
        sourceProvider: 'youtube',
        sourceId: '7wtfhZwyrcc',
      );

      syncService.syncNowPlayingState(
        const PlaybackState(
          currentTrack: ytTrack,
          status: PlaybackStatus.playing,
          duration: Duration(minutes: 3, seconds: 24),
        ),
        force: true,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(calls.length, greaterThanOrEqualTo(2));
      final latestArgs = Map<String, dynamic>.from(calls.last.arguments as Map);
      expect(latestArgs['artworkPath'], equals(cachedFile.path));
      expect(latestArgs['artworkUrl'],
          equals('https://is1-ssl.mzstatic.com/image/600x600bb.jpg'));
    });
  });
}

class _InlineStubResolver extends ArtworkResolver {
  final Future<ResolvedArtwork> Function(ArtworkQuery) _fn;
  _InlineStubResolver(this._fn, {required Dio dio})
      : super(
          cache: ArtworkCache(dio: dio),
          deezerProvider: DeezerArtworkProvider(dio: dio, isEnabled: false),
        );

  @override
  Future<ResolvedArtwork> resolve(ArtworkQuery query,
          {bool forceRefresh = false}) =>
      _fn(query);
}
