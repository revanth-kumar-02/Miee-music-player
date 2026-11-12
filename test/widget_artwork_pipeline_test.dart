import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/storage/adapters/history_entry.dart';
import 'package:Miee/core/storage/adapters/playlist_hive_model.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/core/widget/miee_widget_sync_service.dart';
import 'package:Miee/features/artwork/data/artwork_cache.dart';
import 'package:Miee/features/artwork/data/artwork_resolver_impl.dart';
import 'package:Miee/features/artwork/domain/artwork_query.dart';
import 'package:Miee/features/artwork/domain/artwork_source.dart';
import 'package:Miee/features/artwork/domain/resolved_artwork.dart';
import 'package:Miee/shared/models/track.dart';

class _StubArtworkResolver extends ArtworkResolver {
  final Future<ResolvedArtwork> Function(ArtworkQuery query) onResolve;

  _StubArtworkResolver(this.onResolve) : super(cache: ArtworkCache());

  @override
  Future<ResolvedArtwork> resolve(ArtworkQuery query, {bool forceRefresh = false}) =>
      onResolve(query);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'com.example.miee/widget_test';
  final List<MethodCall> methodCalls = [];
  late MethodChannel testChannel;

  setUp(() {
    methodCalls.clear();
    testChannel = const MethodChannel(channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(testChannel, (MethodCall call) async {
      methodCalls.add(call);
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(testChannel, null);
  });

  group('Widget Artwork Pipeline', () {
    test('1. Local song with artwork sends image path in artworkPath, not audio .mp3',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('miee_art_test_');
      final artFile = File('${tempDir.path}/cover.png')
        ..writeAsBytesSync([137, 80, 78, 71, 1, 2, 3]);

      final service = MieeWidgetSyncService(
        null,
        channel: testChannel,
        autoListen: false,
        fileExistsProvider: (p) => p == artFile.path,
        artworkResolver: _StubArtworkResolver((q) async => ResolvedArtwork(
              imageUrl: artFile.path,
              source: ArtworkSource.local,
              confidence: 1.0,
              isLocal: true,
              resolvedAt: DateTime.now(),
            )),
      );

      final localTrack = Track(
        id: 'local_1',
        title: 'Local Song',
        artist: 'Local Artist',
        imageUrl: artFile.path,
        duration: '03:10',
        filePath: '/storage/emulated/0/Music/local_song.mp3',
      );

      service.syncNowPlayingState(
        PlaybackState(
          currentTrack: localTrack,
          status: PlaybackStatus.playing,
          duration: const Duration(minutes: 3, seconds: 10),
        ),
        force: true,
      );

      expect(methodCalls.length, 1);
      final args = Map<String, dynamic>.from(methodCalls.single.arguments as Map);
      expect(args['trackId'], 'local_1');
      expect(args['artworkPath'], artFile.path);
      expect(args['artworkUrl'], '');
      expect(args['audioFilePath'], '/storage/emulated/0/Music/local_song.mp3');

      service.dispose();
      await tempDir.delete(recursive: true);
    });

    test('2. Local song without artwork passes audioFilePath for native extraction and handles empty resolution',
        () async {
      final service = MieeWidgetSyncService(
        null,
        channel: testChannel,
        autoListen: false,
        fileExistsProvider: (_) => false,
        artworkResolver: _StubArtworkResolver((q) async => const ResolvedArtwork(
              imageUrl: '',
              source: ArtworkSource.local,
              confidence: 0.0,
            )),
      );

      const localNoArt = Track(
        id: 'local_no_art',
        title: 'No Art Song',
        artist: 'Artist',
        imageUrl: '',
        duration: '02:45',
        filePath: '/storage/emulated/0/Music/no_art.mp3',
      );

      service.syncNowPlayingState(
        const PlaybackState(
          currentTrack: localNoArt,
          status: PlaybackStatus.playing,
        ),
        force: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(methodCalls.length, 1);
      final args = Map<String, dynamic>.from(methodCalls.single.arguments as Map);
      expect(args['artworkPath'], '');
      expect(args['artworkUrl'], '');
      expect(args['audioFilePath'], '/storage/emulated/0/Music/no_art.mp3');

      service.dispose();
    });

    test('3. YouTube song sends thumbnail URL in artworkUrl and upgrades via ArtworkResolver',
        () async {
      final service = MieeWidgetSyncService(
        null,
        channel: testChannel,
        autoListen: false,
        artworkResolver: _StubArtworkResolver((q) async => ResolvedArtwork(
              imageUrl: 'https://is1-ssl.mzstatic.com/image/thumb/cover600.jpg',
              source: ArtworkSource.itunes,
              confidence: 0.95,
              resolvedAt: DateTime.now(),
            )),
      );

      const ytTrack = Track(
        id: 'youtube_dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        imageUrl: '',
        duration: '03:32',
        filePath: '',
        sourceProvider: 'youtube',
        sourceId: 'dQw4w9WgXcQ',
      );

      service.syncNowPlayingState(
        const PlaybackState(
          currentTrack: ytTrack,
          status: PlaybackStatus.playing,
        ),
        force: true,
      );

      // Initial push uses derived YouTube thumbnail URL.
      expect(methodCalls.length, 1);
      final firstArgs = Map<String, dynamic>.from(methodCalls[0].arguments as Map);
      expect(firstArgs['artworkPath'], '');
      expect(firstArgs['artworkUrl'], 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
      expect(firstArgs['audioFilePath'], '');

      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Second push upgrades to studio artwork URL.
      expect(methodCalls.length, 2);
      final secondArgs = Map<String, dynamic>.from(methodCalls[1].arguments as Map);
      expect(secondArgs['artworkUrl'], 'https://is1-ssl.mzstatic.com/image/thumb/cover600.jpg');

      service.dispose();
    });

    test('4. YouTube artwork resolution failure preserves fallback thumbnail without throwing',
        () async {
      final service = MieeWidgetSyncService(
        null,
        channel: testChannel,
        autoListen: false,
        artworkResolver: _StubArtworkResolver((q) async {
          throw Exception('Network timeout');
        }),
      );

      const ytTrack = Track(
        id: 'youtube_o0LydWpBQts',
        title: 'Believer',
        artist: 'Imagine Dragons',
        imageUrl: 'https://i.ytimg.com/vi/o0LydWpBQts/hqdefault.jpg',
        duration: '03:24',
        filePath: '',
      );

      service.syncNowPlayingState(
        const PlaybackState(
          currentTrack: ytTrack,
          status: PlaybackStatus.playing,
        ),
        force: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(methodCalls.length, 1);
      final args = Map<String, dynamic>.from(methodCalls.single.arguments as Map);
      expect(args['artworkUrl'], 'https://i.ytimg.com/vi/o0LydWpBQts/hqdefault.jpg');

      service.dispose();
    });

    test('5 & 6. Switching local -> YouTube -> local clears stale artwork fields cleanly',
        () async {
      final service = MieeWidgetSyncService(
        null,
        channel: testChannel,
        autoListen: false,
        fileExistsProvider: (p) => p == '/data/art/local.png',
        artworkResolver: _StubArtworkResolver((q) async => const ResolvedArtwork(
              imageUrl: '',
              source: ArtworkSource.local,
              confidence: 0.0,
            )),
      );

      const localTrack = Track(
        id: 'local_a',
        title: 'Local A',
        artist: 'Artist A',
        imageUrl: '/data/art/local.png',
        duration: '03:00',
        filePath: '/music/a.mp3',
      );
      const ytTrack = Track(
        id: 'youtube_7wtfhZwyrcc',
        title: 'YT B',
        artist: 'Artist B',
        imageUrl: 'https://i.ytimg.com/vi/7wtfhZwyrcc/hqdefault.jpg',
        duration: '03:20',
        filePath: 'https://redirector.googlevideo.com/stream',
      );

      service.syncNowPlayingState(
        const PlaybackState(currentTrack: localTrack, status: PlaybackStatus.playing),
        force: true,
      );
      service.syncNowPlayingState(
        const PlaybackState(currentTrack: ytTrack, status: PlaybackStatus.playing),
      );
      service.syncNowPlayingState(
        const PlaybackState(currentTrack: localTrack, status: PlaybackStatus.playing),
      );

      expect(methodCalls.length, 3);
      final ytArgs = Map<String, dynamic>.from(methodCalls[1].arguments as Map);
      expect(ytArgs['artworkPath'], '');
      expect(ytArgs['artworkUrl'], 'https://i.ytimg.com/vi/7wtfhZwyrcc/hqdefault.jpg');
      expect(ytArgs['audioFilePath'], '');

      final backToLocalArgs = Map<String, dynamic>.from(methodCalls[2].arguments as Map);
      expect(backToLocalArgs['artworkPath'], '/data/art/local.png');
      expect(backToLocalArgs['artworkUrl'], '');
      expect(backToLocalArgs['audioFilePath'], '/music/a.mp3');

      service.dispose();
    });

    test('7. Rapid track changes discard stale async artwork resolution for previous track',
        () async {
      final gateA = Completer<ResolvedArtwork>();
      final gateB = Completer<ResolvedArtwork>();

      final service = MieeWidgetSyncService(
        null,
        channel: testChannel,
        autoListen: false,
        artworkResolver: _StubArtworkResolver((q) {
          if (q.id == 'youtube_aaaaaaaaaaa') return gateA.future;
          return gateB.future;
        }),
      );

      const trackA = Track(
        id: 'youtube_aaaaaaaaaaa',
        title: 'Track A',
        artist: 'Artist A',
        imageUrl: '',
        duration: '03:00',
      );
      const trackB = Track(
        id: 'youtube_bbbbbbbbbbb',
        title: 'Track B',
        artist: 'Artist B',
        imageUrl: '',
        duration: '03:00',
      );

      service.syncNowPlayingState(
        const PlaybackState(currentTrack: trackA, status: PlaybackStatus.playing),
        force: true,
      );
      service.syncNowPlayingState(
        const PlaybackState(currentTrack: trackB, status: PlaybackStatus.playing),
      );

      // Complete Track A AFTER Track B is already active -> must be ignored!
      gateA.complete(ResolvedArtwork(
        imageUrl: 'https://example.com/stale_A.jpg',
        source: ArtworkSource.itunes,
        confidence: 1.0,
        resolvedAt: DateTime.now(),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      gateB.complete(ResolvedArtwork(
        imageUrl: 'https://example.com/fresh_B.jpg',
        source: ArtworkSource.itunes,
        confidence: 1.0,
        resolvedAt: DateTime.now(),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final urlsSent = methodCalls
          .map((c) => (c.arguments as Map)['artworkUrl'] as String)
          .toList();
      expect(urlsSent.contains('https://example.com/stale_A.jpg'), isFalse);
      expect(urlsSent.last, 'https://example.com/fresh_B.jpg');

      service.dispose();
    });

    test('8. Multi-item widgets (Favourites, Recently Played, Playlists) emit separated artworkPath/artworkUrl/audioFilePath',
        () {
      final service = MieeWidgetSyncService(
        null,
        channel: testChannel,
        autoListen: false,
      );

      const localFav = Track(
        id: 'loc_1',
        title: 'Local Fav',
        artist: 'Artist',
        imageUrl: '/cache/loc_1.png',
        duration: '03:00',
        filePath: '/music/loc_1.mp3',
      );
      const ytFav = Track(
        id: 'youtube_dQw4w9WgXcQ',
        title: 'YT Fav',
        artist: 'Rick',
        imageUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        duration: '03:32',
        filePath: '',
      );

      service.syncFavourites([localFav, ytFav]);
      service.syncRecentlyPlayed([
        HistoryEntry(track: TrackHiveModel.fromTrack(ytFav), playedAt: DateTime.now()),
      ]);
      service.syncPlaylists([
        PlaylistHiveModel(
          id: 'pl_1',
          name: 'Mix',
          tracks: [TrackHiveModel.fromTrack(localFav)],
          createdAt: DateTime.now(),
        ),
      ]);

      expect(methodCalls.length, 3);
      final favJson = jsonDecode(
          (methodCalls[0].arguments as Map)['itemsJson'] as String) as List;
      expect(favJson[0]['artworkPath'], '/cache/loc_1.png');
      expect(favJson[0]['artworkUrl'], '');
      expect(favJson[0]['audioFilePath'], '/music/loc_1.mp3');
      expect(favJson[1]['artworkPath'], '');
      expect(favJson[1]['artworkUrl'], 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
      expect(favJson[1]['audioFilePath'], '');

      final recentJson = jsonDecode(
          (methodCalls[1].arguments as Map)['itemsJson'] as String) as List;
      expect(recentJson[0]['artworkUrl'], 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');

      final playlistJson = jsonDecode(
          (methodCalls[2].arguments as Map)['itemsJson'] as String) as List;
      expect(playlistJson[0]['artworkPath'], '/cache/loc_1.png');
      expect(playlistJson[0]['audioFilePath'], '/music/loc_1.mp3');

      service.dispose();
    });
  });
}
