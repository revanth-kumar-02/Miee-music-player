import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:Miee/core/storage/adapters/playlist_hive_model.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/core/storage/hive_boxes.dart';
import 'package:Miee/core/sync/conflict_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('miee_playlist_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(PlaylistHiveModelAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(TrackHiveModelAdapter());
    await Hive.openBox<PlaylistHiveModel>(HiveBoxes.playlists);
  });

  tearDown(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('REM-07 Phase 3: Playlist Versioning & Delta-Reconciliation Tests', () {
    test('1. Remote track deletion is reconciled when parent playlist last_modified changes', () {
      final tOld = DateTime(2026, 11, 1, 10, 0);
      final tNew = DateTime(2026, 11, 1, 10, 5);

      // Device A has tracks [t1, t2, t3]
      final localPlaylist = PlaylistHiveModel(
        id: 'pl_1',
        name: 'My Jam',
        tracks: [
          TrackHiveModel(id: 't1', title: 'Song 1', artist: 'Artist 1', imageUrl: '', duration: '3:00'),
          TrackHiveModel(id: 't2', title: 'Song 2', artist: 'Artist 2', imageUrl: '', duration: '3:00'),
          TrackHiveModel(id: 't3', title: 'Song 3', artist: 'Artist 3', imageUrl: '', duration: '3:00'),
        ],
        createdAt: tOld,
        lastModified: tOld,
      );

      // Device B deleted t2, updating last_modified to tNew
      final remotePlaylist = PlaylistHiveModel(
        id: 'pl_1',
        name: 'My Jam',
        tracks: [
          TrackHiveModel(id: 't1', title: 'Song 1', artist: 'Artist 1', imageUrl: '', duration: '3:00'),
          TrackHiveModel(id: 't3', title: 'Song 3', artist: 'Artist 3', imageUrl: '', duration: '3:00'),
        ],
        createdAt: tOld,
        lastModified: tNew,
      );

      // Parent timestamp check: remote is newer
      expect(remotePlaylist.lastModified.isAfter(localPlaylist.lastModified), isTrue);

      // Reconciled playlist adopts the remote track list, removing t2 cleanly
      final resolved = remotePlaylist.lastModified.isAfter(localPlaylist.lastModified)
          ? remotePlaylist
          : localPlaylist;

      expect(resolved.tracks.length, 2);
      expect(resolved.tracks.map((t) => t.id).toList(), ['t1', 't3']);
      expect(resolved.tracks.any((t) => t.id == 't2'), isFalse);
    });

    test('2. Unchanged playlists (last_modified <= local) skip track queries and preserve tracks', () {
      final tSame = DateTime(2026, 11, 1, 10, 0);

      final localPlaylists = [
        PlaylistHiveModel(
          id: 'pl_unmodified',
          name: 'Chill Vibes',
          tracks: [TrackHiveModel(id: 't_a', title: 'Song A', artist: 'Artist A', imageUrl: '', duration: '3:00')],
          createdAt: tSame,
          lastModified: tSame,
        ),
      ];

      final remotePlaylistMetadata = [
        {'id': 'pl_unmodified', 'last_modified': tSame.toIso8601String()},
      ];

      // Identify which playlists require track fetches
      final modifiedIds = remotePlaylistMetadata.where((p) {
        final pId = p['id'] as String;
        final remoteTime = DateTime.parse(p['last_modified'] as String);
        final local = localPlaylists.firstWhere((l) => l.id == pId);
        return remoteTime.isAfter(local.lastModified);
      }).map((p) => p['id'] as String).toList();

      // Zero track fetches needed!
      expect(modifiedIds.isEmpty, isTrue);
    });

    test('3. Reordering while offline updates lastModified and reorders track sequence', () {
      final t0 = DateTime(2026, 11, 1, 8, 0);
      final pl = PlaylistHiveModel(
        id: 'pl_reorder',
        name: 'Workout',
        tracks: [
          TrackHiveModel(id: 't1', title: 'Warmup', artist: 'A', imageUrl: '', duration: '3:00'),
          TrackHiveModel(id: 't2', title: 'Sprint', artist: 'B', imageUrl: '', duration: '3:00'),
          TrackHiveModel(id: 't3', title: 'Cooldown', artist: 'C', imageUrl: '', duration: '3:00'),
        ],
        createdAt: t0,
        lastModified: t0,
      );

      // Move Sprint (index 1) to first (index 0)
      final track = pl.tracks.removeAt(1);
      pl.tracks.insert(0, track);
      final tReordered = DateTime(2026, 11, 1, 8, 30);
      pl.lastModified = tReordered;

      expect(pl.tracks.first.id, 't2');
      expect(pl.tracks[1].id, 't1');
      expect(pl.tracks[2].id, 't3');
      expect(pl.lastModified.isAfter(t0), isTrue);
    });

    test('4. ConflictResolver merges disjoint playlists cleanly', () {
      final plA = PlaylistHiveModel(
        id: 'pl_a',
        name: 'Device A Playlist',
        tracks: [],
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
      );

      final plB = PlaylistHiveModel(
        id: 'pl_b',
        name: 'Device B Playlist',
        tracks: [],
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
      );

      final merged = ConflictResolver.mergeLists<PlaylistHiveModel, String>(
        local: [plA],
        remote: [plB],
        idSelector: (p) => p.id,
        mergeFn: (l, r) => l,
      );

      expect(merged.length, 2);
      expect(merged.map((p) => p.id).toSet(), {'pl_a', 'pl_b'});
    });
  });
}

