import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/lyrics/domain/lyrics_model.dart';
import 'package:Miee/features/lyrics/providers/lyrics_providers.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:hive/hive.dart';
import 'package:Miee/core/storage/hive_boxes.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/core/storage/adapters/queue_snapshot.dart';
import 'package:Miee/features/library/data/queue_state_repository.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  group('Lyrics Engine & LRCLIB Resolution', () {
    test('LyricParser cleanly parses standard LRC timestamps and text', () {
      const lrcContent = '''
[00:12.50] Hello world from Miee
[00:15.80] Beautiful music player
[00:20.00] Testing synchronized lyrics
''';

      final parsed = LyricParser.parse(lrcContent);
      expect(parsed.length, 3);
      expect(parsed[0].text, 'Hello world from Miee');
      expect(parsed[0].time, const Duration(seconds: 12, milliseconds: 500));
      expect(parsed[1].text, 'Beautiful music player');
      expect(parsed[1].time, const Duration(seconds: 15, milliseconds: 800));
      expect(parsed[2].text, 'Testing synchronized lyrics');
      expect(parsed[2].time, const Duration(seconds: 20));
    });

    test('lyricsProvider handles null track gracefully', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final lyrics = await container.read(lyricsProvider(null).future);
      expect(lyrics, isEmpty);
    });

    test('lyricsProvider resolves live synchronized lyrics for a global hit from LRCLIB', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const track = Track(
        id: 'coldplay_yellow',
        title: 'Yellow',
        artist: 'Coldplay',
        imageUrl: 'https://example.com/yellow.jpg',
        duration: '4:27',
      );

      final lyrics = await container.read(lyricsProvider(track).future);
      // LRCLIB has verified synced lyrics for Coldplay Yellow
      expect(lyrics, isNotEmpty);
      expect(lyrics.any((l) => l.text.toLowerCase().contains('yellow')), isTrue);
    });
  });

  group('Queue Persistence Verification', () {
    test('QueueStateRepository correctly converts, stores, and restores queue snapshot', () async {
      final tempDir = await Directory.systemTemp.createTemp('miee_hive_test_');
      addTearDown(() async {
        await Hive.close();
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(TrackHiveModelAdapter());
      if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(QueueSnapshotAdapter());

      await Hive.openBox<QueueSnapshot>(HiveBoxes.queueState);

      final repo = QueueStateRepository();
      const track1 = Track(
        id: 't1',
        title: 'Song One',
        artist: 'Artist A',
        imageUrl: 'https://example.com/1.jpg',
        duration: '3:00',
      );
      const track2 = Track(
        id: 't2',
        title: 'Song Two',
        artist: 'Artist B',
        imageUrl: 'https://example.com/2.jpg',
        duration: '4:00',
      );

      await repo.saveSnapshot(
        queue: [track1, track2],
        currentIndex: 1,
        positionMs: 45000,
        isShuffleEnabled: true,
        repeatMode: 'all',
      );

      final snapshot = repo.loadSnapshot();
      expect(snapshot, isNotNull);
      expect(snapshot!.currentIndex, 1);
      expect(snapshot.positionMs, 45000);
      expect(snapshot.isShuffleEnabled, isTrue);
      expect(snapshot.repeatMode, 'all');

      final restoredTracks = repo.loadQueueTracks();
      expect(restoredTracks, isNotNull);
      expect(restoredTracks!.length, 2);
      expect(restoredTracks[0].title, 'Song One');
      expect(restoredTracks[1].title, 'Song Two');

      await repo.clear();
      expect(repo.loadSnapshot(), isNull);
    });
  });
}
