import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:Miee/core/storage/hive_boxes.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/core/storage/adapters/history_entry.dart';
import 'package:Miee/features/artwork/data/artwork_cache.dart';
import 'package:Miee/features/artwork/data/artwork_resolver_impl.dart';
import 'package:Miee/features/artwork/domain/artwork_query.dart';
import 'package:Miee/features/artwork/domain/artwork_source.dart';
import 'package:Miee/features/artwork/domain/resolved_artwork.dart';
import 'package:Miee/features/artwork/presentation/artwork_providers.dart';
import 'package:Miee/features/artwork/presentation/miee_artwork_image.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/shared/widgets/song_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late Box<dynamic> artworkBox;
  late Box<HistoryEntry> historyBox;

  setUpAll(() {
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(TrackHiveModelAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(HistoryEntryAdapter());
    }
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('miee_artwork_test_');
    Hive.init(tempDir.path);
    artworkBox = await Hive.openBox<dynamic>(HiveBoxes.artworkCache);
    historyBox = await Hive.openBox<HistoryEntry>(HiveBoxes.recentlyPlayed);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('YouTube Music & Local Track Artwork Pipeline Tests', () {
    // 1. Local song with embedded artwork
    test('1. Local song with embedded artwork resolves from disk with source=local', () async {
      // Create a temporary dummy image file with valid PNG header bytes
      final dummyArtFile = File('${tempDir.path}/test_cover.png');
      await dummyArtFile.writeAsBytes([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG magic
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        ...List.filled(150, 0),
      ]);

      final localSong = MediaSong(
        id: 'local_song_1',
        title: 'Local Melody',
        artist: 'Local Artist',
        album: 'Local Album',
        duration: '3:20',
        durationMs: 200000,
        filePath: '/music/local_melody.mp3',
        artworkPath: dummyArtFile.path,
      );

      final resolver = ArtworkResolver(cache: ArtworkCache(hiveBox: artworkBox));
      final query = ArtworkQuery.fromMusicItem(localSong);

      expect(query.isYoutube, isFalse);
      expect(query.cacheKey, startsWith('loc_local_song_1_'));

      final resolved = await resolver.resolve(query);
      expect(resolved.isLocal, isTrue);
      expect(resolved.source, equals(ArtworkSource.local));
      expect(resolved.imageUrl, equals(dummyArtFile.path));
    });

    // 2. YouTube Music song with multiple thumbnail resolutions
    test('2. YouTube Music song with studio highResArtworkUrl selects high-res and avoids 404', () async {
      const video = YouTubeVideo(
        id: '7wtfhZwyrcc',
        title: 'Believer',
        channelTitle: 'Imagine Dragons',
        thumbnailUrl: 'https://img.youtube.com/vi/7wtfhZwyrcc/hqdefault.jpg',
        highResArtworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/believer_600x600bb.jpg',
        duration: '3:36',
        viewCount: '2B views',
      );

      final track = video.toTrack();
      expect(track.imageUrl, equals('https://is1-ssl.mzstatic.com/image/thumb/believer_600x600bb.jpg'));

      final query = ArtworkQuery.fromMusicItem(track);
      expect(query.isYoutube, isTrue);
      expect(query.youtubeVideoId, equals('7wtfhZwyrcc'));
      expect(query.fallbackThumbnailUrl, equals('https://is1-ssl.mzstatic.com/image/thumb/believer_600x600bb.jpg'));

      final resolver = ArtworkResolver(cache: ArtworkCache(hiveBox: artworkBox));
      final resolved = await resolver.resolve(query);

      expect(resolved.imageUrl, equals('https://is1-ssl.mzstatic.com/image/thumb/believer_600x600bb.jpg'));
      expect(resolved.isNeutralFallback, isFalse);
    });

    // 3. YouTube Music song with missing artwork automatically derives deterministic thumbnail
    test('3. YouTube Music song with missing artwork derives valid YouTube thumbnail from video ID', () async {
      const track = Track(
        id: 'youtube_dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        imageUrl: '', // Missing / blank artwork
        duration: '3:32',
      );

      final query = ArtworkQuery.fromMusicItem(track);
      expect(query.isYoutube, isTrue);
      expect(query.youtubeVideoId, equals('dQw4w9WgXcQ'));
      // Must automatically populate fallback thumbnail from video ID
      expect(query.fallbackThumbnailUrl, equals('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'));

      final resolver = ArtworkResolver(cache: ArtworkCache(hiveBox: artworkBox));
      final resolved = await resolver.resolve(query);

      expect(resolved.imageUrl, equals('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'));
      expect(resolved.source, equals(ArtworkSource.youtube));
      expect(resolved.isNeutralFallback, isFalse);
    });

    // 4. Same song appearing in Search and Queue uses distinct source-specific cache key
    test('4. Same song in Search and Queue preserves stable identity without title collision', () {
      const localTrack = Track(
        id: 'loc_99',
        title: 'Yellow',
        artist: 'Coldplay',
        imageUrl: '/storage/coldplay_yellow.jpg',
        duration: '4:29',
        filePath: '/storage/coldplay_yellow.mp3',
      );

      const youtubeTrack = Track(
        id: 'youtube_yKNxeF4KMsY',
        title: 'Yellow',
        artist: 'Coldplay',
        imageUrl: 'https://i.ytimg.com/vi/yKNxeF4KMsY/hqdefault.jpg',
        duration: '4:29',
      );

      final localQuery = ArtworkQuery.fromMusicItem(localTrack);
      final ytQuery = ArtworkQuery.fromMusicItem(youtubeTrack);

      expect(localQuery.cacheKey, startsWith('loc_loc_99_'));
      expect(ytQuery.cacheKey, startsWith('yt_yKNxeF4KMsY_'));
      expect(localQuery.cacheKey, isNot(equals(ytQuery.cacheKey)),
          reason: 'Local and online tracks must never collide on cache keys');
    });

    // 5. Queue track switching correctly associates artwork with each track
    test('5. Queue track items maintain distinct query representations', () {
      final queue = [
        const Track(
          id: 'youtube_track_1',
          title: 'Song One',
          artist: 'Artist A',
          imageUrl: 'https://i.ytimg.com/vi/track_1/hqdefault.jpg',
          duration: '3:10',
        ),
        const Track(
          id: 'youtube_track_2',
          title: 'Song Two',
          artist: 'Artist B',
          imageUrl: 'https://i.ytimg.com/vi/track_2/hqdefault.jpg',
          duration: '3:45',
        ),
      ];

      final q1 = ArtworkQuery.fromMusicItem(queue[0]);
      final q2 = ArtworkQuery.fromMusicItem(queue[1]);

      expect(q1.fallbackThumbnailUrl, equals('https://i.ytimg.com/vi/track_1/hqdefault.jpg'));
      expect(q2.fallbackThumbnailUrl, equals('https://i.ytimg.com/vi/track_2/hqdefault.jpg'));
      expect(q1.cacheKey, isNot(equals(q2.cacheKey)));
    });

    // 6. Compact player widget renders artwork via MieeArtworkImage
    testWidgets('6. Compact player renders MieeArtworkImage with YouTube artwork', (tester) async {
      const ytTrack = Track(
        id: 'youtube_7wtfhZwyrcc',
        title: 'Believer',
        artist: 'Imagine Dragons',
        imageUrl: 'https://img.youtube.com/vi/7wtfhZwyrcc/hqdefault.jpg',
        duration: '3:24',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            resolvedArtworkProvider.overrideWith((ref, query) async {
              return ResolvedArtwork(
                imageUrl: query.fallbackThumbnailUrl ?? '',
                source: ArtworkSource.youtube,
                confidence: 0.85,
                resolvedAt: DateTime.now(),
              );
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MieeArtworkImage(
                musicItem: ytTrack,
                explicitUrl: ytTrack.imageUrl,
                width: 44,
                height: 44,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify widget hierarchy mounts properly without crashing
      expect(find.byType(MieeArtworkImage), findsOneWidget);
    });

    // 7. Now Playing screen renders large artwork widget
    testWidgets('7. Now Playing screen builds prominent MieeArtworkImage', (tester) async {
      const ytTrack = Track(
        id: 'youtube_ktvTqknDobU',
        title: 'Radioactive',
        artist: 'Imagine Dragons',
        imageUrl: 'https://img.youtube.com/vi/ktvTqknDobU/hqdefault.jpg',
        duration: '4:21',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            resolvedArtworkProvider.overrideWith((ref, query) async {
              return ResolvedArtwork(
                imageUrl: query.fallbackThumbnailUrl ?? '',
                source: ArtworkSource.youtube,
                confidence: 0.85,
                resolvedAt: DateTime.now(),
              );
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MieeArtworkImage(
                musicItem: ytTrack,
                explicitUrl: ytTrack.imageUrl,
                width: 320,
                height: 320,
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byType(MieeArtworkImage), findsOneWidget);
    });

    // 8. Recently Played artwork persists and restores durable image URL
    test('8. Recently Played persists durable YouTube thumbnail URL in Hive', () async {
      const track = Track(
        id: 'youtube_7wtfhZwyrcc',
        title: 'Believer',
        artist: 'Imagine Dragons',
        imageUrl: '', // initially empty
        duration: '3:36',
      );

      final hiveModel = TrackHiveModel.fromTrack(track);
      expect(hiveModel.imageUrl, equals('https://i.ytimg.com/vi/7wtfhZwyrcc/hqdefault.jpg'));

      final restoredTrack = hiveModel.toTrack();
      expect(restoredTrack.imageUrl, equals('https://i.ytimg.com/vi/7wtfhZwyrcc/hqdefault.jpg'));
    });

    // 9. Playlist artwork persistence serializes and deserializes correctly
    test('9. Playlist track serialization retains online artwork URL', () {
      const track = Track(
        id: 'youtube_abc12345678',
        title: 'Shape of You',
        artist: 'Ed Sheeran',
        imageUrl: 'https://is1-ssl.mzstatic.com/image/thumb/shape_600x600.jpg',
        duration: '3:53',
        sourceProvider: 'youtube',
        sourceId: 'abc12345678',
      );

      final hiveModel = TrackHiveModel.fromTrack(track);
      expect(hiveModel.imageUrl, equals('https://is1-ssl.mzstatic.com/image/thumb/shape_600x600.jpg'));
      expect(hiveModel.sourceProvider, equals('youtube'));
      expect(hiveModel.sourceId, equals('abc12345678'));

      final restored = hiveModel.toTrack();
      expect(restored.imageUrl, equals(track.imageUrl));
    });

    // 10. App restart and artwork cache restoration hits Hive cache without network
    test('10. App restart and artwork cache restoration returns cached entry immediately', () async {
      final cache = ArtworkCache(hiveBox: artworkBox);
      const testKey = 'yt_7wtfhZwyrcc_imagine dragons_believer';
      final artwork = ResolvedArtwork(
        imageUrl: 'https://img.youtube.com/vi/7wtfhZwyrcc/hqdefault.jpg',
        source: ArtworkSource.youtube,
        confidence: 0.85,
        attribution: 'YouTube Music',
        resolvedAt: DateTime.now(),
      );

      await cache.put(testKey, artwork);

      // Simulate app restart with a fresh memory cache backed by same Hive box
      final restartedCache = ArtworkCache(hiveBox: artworkBox);
      final cachedItem = restartedCache.get(testKey);

      expect(cachedItem, isNotNull);
      expect(cachedItem!.imageUrl, equals('https://img.youtube.com/vi/7wtfhZwyrcc/hqdefault.jpg'));
      expect(cachedItem.source, equals(ArtworkSource.youtube));
    });

    // 11. Offline behaviour falls back gracefully to YouTube thumbnail without failing
    test('11. Offline behaviour returns authentic YouTube thumbnail from query', () async {
      const track = Track(
        id: 'youtube_offline_test',
        title: 'Offline Track',
        artist: 'Offline Artist',
        imageUrl: 'https://i.ytimg.com/vi/offline_test/hqdefault.jpg',
        duration: '3:00',
      );

      final query = ArtworkQuery.fromMusicItem(track);
      final resolver = ArtworkResolver(cache: ArtworkCache(hiveBox: artworkBox));
      final resolved = await resolver.resolve(query);

      expect(resolved.imageUrl, equals('https://i.ytimg.com/vi/offline_test/hqdefault.jpg'));
      expect(resolved.isNeutralFallback, isFalse);
    });

    // 12. Rapidly switching between online tracks deduplicates in-flight calls
    test('12. In-flight deduplication handles simultaneous requests for the same track', () async {
      const track = Track(
        id: 'youtube_7wtfhZwyrcc',
        title: 'Believer',
        artist: 'Imagine Dragons',
        imageUrl: 'https://img.youtube.com/vi/7wtfhZwyrcc/hqdefault.jpg',
        duration: '3:36',
      );

      final query = ArtworkQuery.fromMusicItem(track);
      final resolver = ArtworkResolver(cache: ArtworkCache(hiveBox: artworkBox));

      // Dispatch 3 concurrent resolutions for the same track query
      final results = await Future.wait([
        resolver.resolve(query),
        resolver.resolve(query),
        resolver.resolve(query),
      ]);

      expect(results[0].imageUrl, equals(results[1].imageUrl));
      expect(results[1].imageUrl, equals(results[2].imageUrl));
      expect(results[0].imageUrl, equals('https://img.youtube.com/vi/7wtfhZwyrcc/hqdefault.jpg'));
    });
  });
}
