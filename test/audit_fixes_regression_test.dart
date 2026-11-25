import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/core/storage/adapters/playlist_hive_model.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/core/storage/hive_boxes.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/playlists/data/playlist_repository.dart';
import 'package:Miee/features/search/data/search_repository.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => ['none'],
    );
    tempDir = await Directory.systemTemp.createTemp('miee_audit_reg_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(TrackHiveModelAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(PlaylistHiveModelAdapter());
    await Hive.openBox<dynamic>(HiveBoxes.preferences);
    await Hive.openBox<PlaylistHiveModel>(HiveBoxes.playlists);
    await Hive.openBox<dynamic>(HiveBoxes.offlineQueue);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Audit Fixes Regression Tests', () {
    test('HIGH-02: SearchRepository persists recent searches with Box<dynamic>', () async {
      final repo = SearchRepository();
      await repo.addRecentSearch('Who Is This Dude?');
      expect(repo.getRecentSearches(), contains('Who Is This Dude?'));
    });

    test('HIGH-03: PlaylistRepository preserves untagged tracks and albumName', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final base = container.read(playlistsRepositoryProvider);
      final repo = PlaylistRepository(base);
      final id = await repo.createPlaylist('Audit Untagged Test');

      await repo.addTrack(
        id,
        const Track(
          id: 'local_untagged_1',
          title: 'Untitled Demo',
          artist: '<unknown>',
          imageUrl: '',
          duration: '2:15',
          filePath: '/storage/demo.mp3',
          albumName: 'Dude – Side A',
        ),
      );

      final model = repo.getPlaylist(id);
      expect(model, isNotNull);
      expect(model!.tracks.length, 1);
      expect(model.tracks.first.artist, '<unknown>');
      expect(model.tracks.first.album, 'Dude – Side A');
    });

    test('HIGH-08: QueueManager.setQueue([]) sets currentIndex to -1 and replaceTrackAt syncs _originalQueue', () {
      final qm = QueueManager();
      qm.setQueue(const []);
      expect(qm.currentIndex, -1);
      expect(qm.currentTrack, isNull);

      const t1 = Track(id: '1', title: 'One', artist: 'A', imageUrl: '', duration: '3:00', filePath: 'a');
      const t2 = Track(id: '2', title: 'Two', artist: 'A', imageUrl: '', duration: '3:00', filePath: 'b');
      const t3 = Track(id: '3', title: 'Three', artist: 'A', imageUrl: '', duration: '3:00', filePath: 'c');

      qm.setQueue(const [t1, t2, t3], startIndex: 0);
      qm.enableShuffle();

      final idx2 = qm.queue.indexWhere((t) => t.id == '2');
      expect(idx2, isNot(-1));
      const t2Updated = Track(
        id: '2',
        title: 'Two',
        artist: 'A',
        imageUrl: 'https://example.com/art.jpg',
        duration: '3:00',
        filePath: 'b',
      );
      qm.replaceTrackAt(idx2, t2Updated);
      qm.disableShuffle();

      expect(qm.queue.firstWhere((t) => t.id == '2').imageUrl, 'https://example.com/art.jpg');
    });
  });
}
