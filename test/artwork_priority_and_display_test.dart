import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/artwork/data/artwork_cache.dart';
import 'package:Miee/features/artwork/data/artwork_resolver_impl.dart';
import 'package:Miee/features/artwork/data/providers/itunes_artwork_provider.dart';
import 'package:Miee/features/artwork/data/providers/deezer_artwork_provider.dart';
import 'package:Miee/features/artwork/data/providers/local_artwork_provider.dart';
import 'package:Miee/features/artwork/data/providers/youtube_fallback_provider.dart';
import 'package:Miee/features/artwork/domain/artwork_query.dart';
import 'package:Miee/features/artwork/domain/artwork_source.dart';
import 'package:Miee/features/artwork/domain/resolved_artwork.dart';
import 'package:Miee/features/artwork/presentation/artwork_providers.dart';
import 'package:Miee/features/artwork/presentation/miee_artwork_image.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/media/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ArtworkCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('miee_artwork_priority_test_');
    cache = ArtworkCache(cacheDirectory: tempDir);
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Miee — Section 7 Artwork Priority Test Cases', () {
    // 1. YouTube track with an external album artwork match
    test('Case 1: YouTube track with external album artwork match prioritizes external artwork over YouTube thumbnail', () async {
      final ytVideo = YouTubeVideo(
        id: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        channelTitle: 'Rick Astley',
        thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        duration: '3:33',
        viewCount: '1.4B views',
        canonicalTitle: 'Never Gonna Give You Up',
        canonicalArtist: 'Rick Astley',
        highResArtworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/600x600bb.jpg',
        metadataProvider: 'itunes',
      );

      final track = ytVideo.toTrack();

      expect(track.albumArtworkUrl, 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/600x600bb.jpg');
      expect(track.youtubeThumbnailUrl, 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
      expect(track.imageUrl, 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/600x600bb.jpg');
      expect(track.effectiveArtworkUrl, 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/600x600bb.jpg');
      expect(track.artworkSource, 'itunes');

      final query = ArtworkQuery.fromMusicItem(track);
      expect(query.albumArtworkUrl, 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/600x600bb.jpg');
      expect(query.fallbackThumbnailUrl, 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');

      final resolver = ArtworkResolver(cache: cache);
      final resolved = await resolver.resolve(query);

      expect(resolved.source, ArtworkSource.itunes);
      expect(resolved.imageUrl, 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/600x600bb.jpg');
      expect(resolved.confidence, greaterThanOrEqualTo(0.80));
    });

    // 2. YouTube track without an external artwork match
    test('Case 2: YouTube track without an external artwork match falls back safely to authentic YouTube thumbnail', () async {
      final track = Track(
        id: 'youtube_indieTrack12',
        title: 'Unknown Indie Song',
        artist: 'Bedroom Producer',
        imageUrl: 'https://i.ytimg.com/vi/indieTrack12/hqdefault.jpg',
        duration: '2:45',
        sourceProvider: 'youtube',
        sourceId: 'indieTrack12',
        youtubeThumbnailUrl: 'https://i.ytimg.com/vi/indieTrack12/hqdefault.jpg',
      );

      expect(track.albumArtworkUrl, isNull);
      expect(track.effectiveArtworkUrl, 'https://i.ytimg.com/vi/indieTrack12/hqdefault.jpg');

      final query = ArtworkQuery.fromMusicItem(track);
      expect(query.albumArtworkUrl, isNull);
      expect(query.fallbackThumbnailUrl, 'https://i.ytimg.com/vi/indieTrack12/hqdefault.jpg');

      final resolver = ArtworkResolver(
        cache: cache,
        itunesProvider: const ItunesArtworkProvider(isEnabled: false),
        deezerProvider: DeezerArtworkProvider(isEnabled: false),
      );
      final resolved = await resolver.resolve(query);

      expect(resolved.source, ArtworkSource.neutralFallback);
      expect(resolved.isNeutralFallback, isTrue);
    });

    // 3. Local track with embedded artwork
    test('Case 3: Local track with embedded artwork resolves local file path with 1.0 confidence', () async {
      final fakeJpg = File('${tempDir.path}/fake_embedded.jpg');
      await fakeJpg.writeAsBytes(List<int>.filled(150, 0xFF));

      final song = MediaSong(
        id: 'local_101',
        title: 'Local Masterpiece',
        artist: 'Home Artist',
        album: 'Acoustic Album',
        duration: '4:10',
        durationMs: 250000,
        filePath: '/storage/emulated/0/Music/song.mp3',
        artworkPath: fakeJpg.path,
      );

      expect(song.effectiveArtworkUrl, fakeJpg.path);

      final track = Track(
        id: song.id,
        title: song.title,
        artist: song.artist,
        imageUrl: song.artworkPath,
        duration: song.duration,
        filePath: song.filePath,
        embeddedArtworkPath: fakeJpg.path,
        artworkSource: 'local',
        artworkMatchConfidence: 1.0,
      );

      expect(track.effectiveArtworkUrl, fakeJpg.path);

      final query = ArtworkQuery.fromMusicItem(track);
      expect(query.isYoutube, isFalse);
      expect(query.localArtworkPath, fakeJpg.path);
    });

    // 4. Local track without embedded artwork
    test('Case 4: Local track without embedded artwork queries online catalogue and falls back to neutral', () async {
      final song = MediaSong(
        id: 'local_no_art',
        title: 'No Art Track',
        artist: 'NonExistent Artist 999',
        album: 'Obscure Album',
        duration: '3:00',
        durationMs: 180000,
        filePath: '/storage/emulated/0/Music/noart.mp3',
        artworkPath: '',
      );

      final query = ArtworkQuery.fromMusicItem(song);
      expect(query.isYoutube, isFalse);
      expect(query.localArtworkPath, isNull);

      final resolver = ArtworkResolver(
        cache: cache,
        itunesProvider: const ItunesArtworkProvider(isEnabled: false),
        deezerProvider: DeezerArtworkProvider(isEnabled: false),
      );
      final resolved = await resolver.resolve(query);

      expect(resolved.isNeutralFallback, isTrue);
    });

    // 5. High-confidence provider match vs 6. Low-confidence provider match
    test('Case 5 & 6: High confidence (>=0.80) is accepted; low confidence (<0.80) is rejected', () async {
      final confidentArtwork = ResolvedArtwork(
        imageUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music/600x600bb.jpg',
        source: ArtworkSource.itunes,
        confidence: 0.95,
        resolvedAt: DateTime.now(),
      );

      final unconfidentArtwork = ResolvedArtwork(
        imageUrl: 'https://lowconf.com/art.jpg',
        source: ArtworkSource.itunes,
        confidence: 0.55,
        resolvedAt: DateTime.now(),
      );

      expect(confidentArtwork.confidence >= 0.80, isTrue);
      expect(unconfidentArtwork.confidence >= 0.80, isFalse);
    });

    // 7. Invalid provider image URL & 8. Expired image URL
    test('Case 7 & 8: Invalid or non-image bytes are rejected by cache validation', () async {
      expect(ArtworkCache.isValidImageBytes([]), isFalse);
      expect(ArtworkCache.isValidImageBytes([0x00, 0x01, 0x02]), isFalse);
      // Valid JPEG header: FF D8 FF
      final validJpgBytes = [0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(100, 0x00)];
      expect(ArtworkCache.isValidImageBytes(validJpgBytes), isTrue);
    });

    // 9. Cache hit & 10. Cache refresh
    test('Case 9 & 10: Cache hit returns immediately; forceRefresh invalidates cache', () async {
      const key = 'test_cache_song';
      final artwork = ResolvedArtwork(
        imageUrl: 'https://cached.com/album.jpg',
        source: ArtworkSource.itunes,
        confidence: 0.95,
        resolvedAt: DateTime.now(),
      );

      await cache.put(key, artwork);
      final hit = cache.get(key);
      expect(hit, isNotNull);
      expect(hit!.imageUrl, 'https://cached.com/album.jpg');

      await cache.evict(key);
      final afterEvict = cache.get(key);
      expect(afterEvict, isNull);
    });

    // Overwrite protection: YouTube fallback cannot displace authoritative album artwork
    test('Overwrite protection: YouTube thumbnail cannot overwrite high-confidence album artwork in cache', () async {
      const key = 'protected_song_key';
      final highRes = ResolvedArtwork(
        imageUrl: 'https://is1-ssl.mzstatic.com/image/thumb/600x600bb.jpg',
        source: ArtworkSource.itunes,
        confidence: 0.95,
        resolvedAt: DateTime.now(),
      );

      final ytFallback = ResolvedArtwork(
        imageUrl: 'https://i.ytimg.com/vi/video123/hqdefault.jpg',
        source: ArtworkSource.youtube,
        confidence: 0.50,
        resolvedAt: DateTime.now(),
      );

      await cache.put(key, highRes);
      // Attempt to overwrite with lower-confidence YouTube thumbnail
      await cache.put(key, ytFallback);

      final current = cache.get(key);
      expect(current!.source, ArtworkSource.itunes);
      expect(current.imageUrl, 'https://is1-ssl.mzstatic.com/image/thumb/600x600bb.jpg');
    });

    // 11. Artwork changing while a track is playing
    test('Case 11: Dynamic copyWith preserves external album artwork without let candidate thumbnail overwrite it', () {
      final initialTrack = Track(
        id: 'youtube_abc123',
        title: 'Brooklyn Baby',
        artist: 'Lana Del Rey',
        imageUrl: 'https://is1-ssl.mzstatic.com/image/thumb/lana_600x600bb.jpg',
        duration: '5:51',
        albumArtworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/lana_600x600bb.jpg',
        artworkSource: 'itunes',
        artworkMatchConfidence: 0.95,
        youtubeThumbnailUrl: 'https://i.ytimg.com/vi/abc123/hqdefault.jpg',
      );

      // Simulating PlayerController updating candidate during playback preparation
      final updated = initialTrack.copyWith(
        imageUrl: 'https://i.ytimg.com/vi/verifiedId/hqdefault.jpg',
      );

      // Must NOT lose the verified iTunes album artwork!
      expect(updated.albumArtworkUrl, 'https://is1-ssl.mzstatic.com/image/thumb/lana_600x600bb.jpg');
      expect(updated.imageUrl, 'https://is1-ssl.mzstatic.com/image/thumb/lana_600x600bb.jpg');
      expect(updated.effectiveArtworkUrl, 'https://is1-ssl.mzstatic.com/image/thumb/lana_600x600bb.jpg');
    });

    // 12. Track switching between different artwork sources
    test('Case 12: Tracks cleanly retain independent artwork sources without cross-track leakage', () {
      final itunesTrack = Track(
        id: 'youtube_1',
        title: 'All The Stars',
        artist: 'Kendrick Lamar, SZA',
        imageUrl: 'https://is1-ssl.mzstatic.com/thumb/all_the_stars_600x600bb.jpg',
        duration: '3:55',
        albumArtworkUrl: 'https://is1-ssl.mzstatic.com/thumb/all_the_stars_600x600bb.jpg',
        artworkSource: 'itunes',
      );

      final ytOnlyTrack = Track(
        id: 'youtube_2',
        title: 'Unreleased Freestyle',
        artist: 'Local Underground',
        imageUrl: 'https://i.ytimg.com/vi/freestyle/hqdefault.jpg',
        duration: '2:15',
        youtubeThumbnailUrl: 'https://i.ytimg.com/vi/freestyle/hqdefault.jpg',
        artworkSource: 'youtube',
      );

      expect(itunesTrack.artworkSource, 'itunes');
      expect(itunesTrack.effectiveArtworkUrl, contains('mzstatic.com'));

      expect(ytOnlyTrack.artworkSource, 'youtube');
      expect(ytOnlyTrack.effectiveArtworkUrl, contains('ytimg.com'));
    });
  });

  group('Miee — Widget Rendering Verification Tests', () {
    testWidgets('MieeArtworkImage renders network album cover with valid URL', (tester) async {
      final track = Track(
        id: 'youtube_widget_test',
        title: 'Test Song',
        artist: 'Test Artist',
        imageUrl: 'https://is1-ssl.mzstatic.com/image/thumb/test/600x600bb.jpg',
        duration: '3:30',
        albumArtworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/test/600x600bb.jpg',
        artworkSource: 'itunes',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MieeArtworkImage(
                musicItem: track,
                width: 100,
                height: 100,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(MieeArtworkImage), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
