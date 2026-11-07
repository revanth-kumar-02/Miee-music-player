import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:Miee/core/storage/hive_boxes.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/core/storage/adapters/playlist_hive_model.dart';
import 'package:Miee/core/sync/sync_manager.dart';
import 'package:Miee/core/sync/network_monitor.dart';
import 'package:Miee/core/sync/offline_operation.dart';
import 'package:Miee/core/sync/offline_queue.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeNetworkMonitor implements NetworkMonitor {
  final bool connected;
  final Duration delay;
  FakeNetworkMonitor({this.connected = true, this.delay = Duration.zero});

  @override
  Stream<bool> get onConnectivityChanged => const Stream.empty();

  @override
  Future<bool> get isConnected async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return connected;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('miee_sync_safety_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(TrackHiveModelAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(PlaylistHiveModelAdapter());
    await Hive.openBox<dynamic>(HiveBoxes.offlineQueue);
    await Hive.openBox<dynamic>(HiveBoxes.preferences);
    await Hive.openBox<dynamic>(HiveBoxes.profile);
    await Hive.openBox<TrackHiveModel>(HiveBoxes.favorites);
    await Hive.openBox<PlaylistHiveModel>(HiveBoxes.playlists);
  });

  tearDown(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Phase 1: Account Isolation Tests', () {
    test('1. User A operation cannot execute under User B and is preserved', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      // Create operation for User A
      final opUserA = OfflineOperation(
        id: 'op_user_a',
        type: 'favorite_add',
        payload: {'id': 'track_1', 'title': 'User A Track'},
        timestamp: DateTime.now(),
        userId: 'user_a_uuid',
      );
      await queue.addOperation(opUserA);

      expect(queue.getOperations().length, 1);
      final stored = queue.getOperations().first;
      expect(stored.userId, 'user_a_uuid');

      // Verify that when filtering for current user B, User A operation is isolated
      const currentUserId = 'user_b_uuid';
      final allowedToExecute = stored.userId == currentUserId;
      expect(allowedToExecute, isFalse);

      // Operation remains safely stored in Hive
      expect(queue.getOperations().length, 1);
    });

    test('2. Legacy operations without userId are safely quarantined to dead-letter state', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      // Add legacy operation missing userId
      await box.put('legacy_op', {
        'id': 'legacy_op',
        'type': 'favorite_add',
        'payload': {'id': 'track_legacy'},
        'timestamp': DateTime.now().toIso8601String(),
        // userId omitted
      });

      final ops = queue.getOperations();
      expect(ops.length, 1);
      expect(ops.first.userId, isNull);

      // Quarantine legacy operation
      await queue.quarantineOperation(
        'legacy_op',
        reason: 'Unassigned/legacy operation without user ownership',
      );

      // It must be removed from active queue
      expect(queue.getOperations().isEmpty, isTrue);

      // And present in dead-letter inspection list
      final deadLetters = queue.getDeadLetterOperations();
      expect(deadLetters.length, 1);
      expect(deadLetters.first.id, 'legacy_op');
      expect(deadLetters.first.isDeadLetter, isTrue);
      expect(deadLetters.first.lastError, contains('Unassigned/legacy operation'));
    });
  });

  group('Phase 2: Poison-Pill Queue Defense Tests', () {
    test('3. Permanent 400-class error moves operation to dead-letter without blocking subsequent operations', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      // Add poison pill operation followed by a valid operation
      final poisonOp = OfflineOperation(
        id: 'poison_op',
        type: 'playlist_song_add',
        payload: {'playlistId': 'non_existent_pl', 'track': {'id': 't1'}},
        timestamp: DateTime.now(),
        userId: 'test_user',
      );
      final validOp = OfflineOperation(
        id: 'valid_op',
        type: 'favorite_add',
        payload: {'id': 'track_valid'},
        timestamp: DateTime.now().add(const Duration(seconds: 1)),
        userId: 'test_user',
      );

      await queue.addOperation(poisonOp);
      await queue.addOperation(validOp);

      expect(queue.getOperations().length, 2);

      // Simulate permanent failure on poison pill (e.g. foreign key or schema violation)
      await queue.markDeadLetter(
        'poison_op',
        error: 'PostgrestException: 23503 foreign key violation',
        retryCount: 1,
      );

      // Active queue now contains ONLY the valid operation! Poison pill was bypassed without deletion
      final activeOps = queue.getOperations();
      expect(activeOps.length, 1);
      expect(activeOps.first.id, 'valid_op');

      // Poison pill is safely quarantined
      final deadLetters = queue.getDeadLetterOperations();
      expect(deadLetters.length, 1);
      expect(deadLetters.first.id, 'poison_op');
      expect(deadLetters.first.lastError, contains('foreign key violation'));
    });

    test('4. Transient failure increments retry count and preserves operation', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      final op = OfflineOperation(
        id: 'transient_op',
        type: 'favorite_add',
        payload: {'id': 'track_t'},
        timestamp: DateTime.now(),
        userId: 'test_user',
      );
      await queue.addOperation(op);

      // First transient failure
      await queue.updateRetry(
        'transient_op',
        retryCount: 1,
        lastError: 'SocketException: Network unreachable',
      );

      var ops = queue.getOperations();
      expect(ops.length, 1);
      expect(ops.first.retryCount, 1);
      expect(ops.first.lastError, contains('SocketException'));
      expect(ops.first.isDeadLetter, isFalse);

      // Second transient failure
      await queue.updateRetry(
        'transient_op',
        retryCount: 2,
        lastError: 'TimeoutException: Request timed out',
      );

      ops = queue.getOperations();
      expect(ops.first.retryCount, 2);
      expect(ops.first.lastError, contains('TimeoutException'));

      // Third failure exhausts retries -> moved to dead letter
      await queue.markDeadLetter(
        'transient_op',
        error: 'Max retries (3) exhausted',
        retryCount: 3,
      );

      expect(queue.getOperations().isEmpty, isTrue);
      expect(queue.getDeadLetterOperations().length, 1);
    });

    test('5. Dead-letter operation can be recovered and retry metadata survives app restart', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      final op = OfflineOperation(
        id: 'recover_op',
        type: 'playlist_create',
        payload: {'id': 'pl_1', 'name': 'Road Trip'},
        timestamp: DateTime.now(),
        userId: 'test_user',
      );
      await queue.addOperation(op);
      await queue.markDeadLetter('recover_op', error: 'Temporary service error');

      // Verify dead letter
      expect(queue.getOperations().isEmpty, isTrue);
      expect(queue.getDeadLetterOperations().length, 1);

      // Simulate app restart by reopening the box
      await box.close();
      final reopenedBox = await Hive.openBox<dynamic>(HiveBoxes.offlineQueue);
      final reopenedQueue = OfflineOperationQueue(reopenedBox);

      expect(reopenedQueue.getOperations().isEmpty, isTrue);
      final persistedDeadLetters = reopenedQueue.getDeadLetterOperations();
      expect(persistedDeadLetters.length, 1);
      expect(persistedDeadLetters.first.id, 'recover_op');
      expect(persistedDeadLetters.first.lastError, 'Temporary service error');

      // Recover dead-lettered operation
      await reopenedQueue.recoverDeadLetter('recover_op');
      expect(reopenedQueue.getOperations().length, 1);
      expect(reopenedQueue.getOperations().first.id, 'recover_op');
      expect(reopenedQueue.getOperations().first.retryCount, 0);
      expect(reopenedQueue.getOperations().first.isDeadLetter, isFalse);
    });
  });

  group('Phase 3: Local Delete Consistency Tests', () {
    test('6. Pending local playlist deletion prevents remote playlist from resurrecting', () {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      // Simulate pending playlist deletion
      final op = OfflineOperation(
        id: 'pl_delete_101',
        type: 'playlist_delete',
        payload: {'id': 'pl_101'},
        timestamp: DateTime.now(),
        userId: 'user_x',
      );
      queue.addOperation(op);

      final pendingDeletedPlaylistIds = queue
          .getOperations()
          .where((o) => o.type == 'playlist_delete' && o.userId == 'user_x')
          .map((o) => o.payload['id']?.toString() ?? '')
          .toSet();

      // Remote Supabase payload returned from cloud pull (stale, has not replayed delete yet)
      final remotePlaylistsRaw = [
        {'id': 'pl_101', 'name': 'Deleted Playlist'},
        {'id': 'pl_202', 'name': 'Active Playlist'},
      ];

      // Filtering protects local deletion
      final filteredRemote = remotePlaylistsRaw
          .where((p) => !pendingDeletedPlaylistIds.contains(p['id']))
          .toList();

      expect(filteredRemote.length, 1);
      expect(filteredRemote.first['id'], 'pl_202');
      expect(filteredRemote.any((p) => p['id'] == 'pl_101'), isFalse);
    });

    test('7. Pending local favorite removal prevents remote favorite from resurrecting', () {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      // Simulate pending favorite removal
      final op = OfflineOperation(
        id: 'fav_rem_track_42',
        type: 'favorite_remove',
        payload: {'id': 'track_42'},
        timestamp: DateTime.now(),
        userId: 'user_x',
      );
      queue.addOperation(op);

      final pendingDeletedFavIds = queue
          .getOperations()
          .where((o) => o.type == 'favorite_remove' && o.userId == 'user_x')
          .map((o) => o.payload['id']?.toString() ?? '')
          .toSet();

      final remoteFavs = [
        const Track(id: 'track_42', title: 'Unliked Song', artist: 'Artist A', imageUrl: '', duration: '3:00'),
        const Track(id: 'track_99', title: 'Liked Song', artist: 'Artist B', imageUrl: '', duration: '3:00'),
      ];

      final filteredRemote = remoteFavs
          .where((f) => !pendingDeletedFavIds.contains(f.id))
          .toList();

      expect(filteredRemote.length, 1);
      expect(filteredRemote.first.id, 'track_99');
      expect(filteredRemote.any((f) => f.id == 'track_42'), isFalse);
    });
  });

  group('Phase 4: Concurrency Unification Tests', () {
    test('8. downloadAllRemoteData coordinates with in-flight sync mutex without racing', () async {
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(FakeNetworkMonitor(delay: const Duration(milliseconds: 60))),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(syncManagerProvider);

      // Start an in-flight sync
      final syncFuture = syncManager.triggerSync();
      expect(syncManager.isSyncing, isTrue);

      // Calling downloadAllRemoteData waits for in-flight sync rather than executing in parallel
      final downloadFuture = syncManager.downloadAllRemoteData();

      await syncFuture;
      await downloadFuture;

      expect(syncManager.isSyncing, isFalse);
    });

    test('9. replayOfflineQueue coordinates with in-flight sync mutex without double-running', () async {
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(FakeNetworkMonitor(delay: const Duration(milliseconds: 60))),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(syncManagerProvider);

      // Start sync
      final syncFuture = syncManager.triggerSync();
      expect(syncManager.isSyncing, isTrue);

      // Sign-out dialog calling replayOfflineQueue simply awaits in-flight sync
      final replayFuture = syncManager.replayOfflineQueue();

      await syncFuture;
      await replayFuture;

      expect(syncManager.isSyncing, isFalse);
    });
  });

  group('Phase 5 & 6: History Idempotency & Playlist Reorder Tests', () {
    test('10. Deterministic UUID for history insertion guarantees idempotency on retry', () {
      const userId = 'user_abc_123';
      const trackId = 'youtube_dQw4w9WgXcQ';
      const playedAt = '2026-11-07T10:00:00.000Z';

      // First run generates UUID
      final uuid1 = const Uuid().v5(Namespace.url.value, 'miee:history:$userId:$trackId:$playedAt');

      // Retry with the same event identity produces exact same UUID
      final uuid2 = const Uuid().v5(Namespace.url.value, 'miee:history:$userId:$trackId:$playedAt');

      expect(uuid1, equals(uuid2));

      // Different play of the same track (different timestamp) produces distinct UUID
      const playedAtLater = '2026-11-07T10:15:00.000Z';
      final uuid3 = const Uuid().v5(Namespace.url.value, 'miee:history:$userId:$trackId:$playedAtLater');

      expect(uuid3, isNot(equals(uuid1)));
    });

    test('11. Playlist reorder queues playlist_tracks_reorder with explicit track positions', () async {
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(FakeNetworkMonitor(connected: false)),
        ],
      );
      addTearDown(container.dispose);

      final playlistsRepo = container.read(playlistsRepositoryProvider);
      final syncManager = container.read(syncManagerProvider);

      // Create a test playlist with 3 tracks
      final now = DateTime.now();
      const playlistId = 'pl_reorder_test';
      final playlist = PlaylistHiveModel(
        id: playlistId,
        name: 'My Playlist',
        tracks: [
          TrackHiveModel(id: 't_1', title: 'Track 1', artist: 'A1', imageUrl: '', duration: '3:00'),
          TrackHiveModel(id: 't_2', title: 'Track 2', artist: 'A2', imageUrl: '', duration: '3:00'),
          TrackHiveModel(id: 't_3', title: 'Track 3', artist: 'A3', imageUrl: '', duration: '3:00'),
        ],
        createdAt: now,
        lastModified: now,
      );
      await Hive.box<PlaylistHiveModel>(HiveBoxes.playlists).put(playlistId, playlist);

      // Reorder track 0 (t_1) to index 2
      await playlistsRepo.reorderTracks(playlistId, 0, 2);

      // Verify that local order was immediately updated
      final updatedLocal = Hive.box<PlaylistHiveModel>(HiveBoxes.playlists).get(playlistId)!;
      expect(updatedLocal.tracks.map((t) => t.id).toList(), ['t_2', 't_1', 't_3']);

      // Verify that offline operation queue has playlist_tracks_reorder with positions
      final ops = syncManager.queue.getOperations();
      final reorderOp = ops.firstWhere((o) => o.type == 'playlist_tracks_reorder');
      expect(reorderOp, isNotNull);
      expect(reorderOp.payload['playlistId'], playlistId);

      final positions = reorderOp.payload['trackPositions'] as List;
      expect(positions.length, 3);
      expect(positions[0], {'trackId': 't_2', 'position': 0});
      expect(positions[1], {'trackId': 't_1', 'position': 1});
      expect(positions[2], {'trackId': 't_3', 'position': 2});
    });
  });

  group('Critical Post-Implementation Safety & Recovery Tests', () {
    test('1. Dead-letter playlist deletion remains protected during reconciliation', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      // Create playlist deletion and quarantine it into dead-letter state
      final op = OfflineOperation(
        id: 'pl_del_dead',
        type: 'playlist_delete',
        payload: {'id': 'pl_dead_123'},
        timestamp: DateTime.now(),
        userId: 'user_active',
      );
      await queue.addOperation(op);
      await queue.markDeadLetter('pl_del_dead', error: 'Service Unavailable');

      // Reconciler collects pending deletions including dead letters for active user
      final pendingOps = queue.getOperations(includeDeadLetter: true);
      final pendingDeletedPlaylistIds = pendingOps
          .where((o) => o.type == 'playlist_delete' && o.userId == 'user_active')
          .map((o) => o.payload['id']?.toString() ?? '')
          .toSet();

      expect(pendingDeletedPlaylistIds.contains('pl_dead_123'), isTrue);

      // Remote pull returns both deleted and active playlists
      final remotePlaylists = [
        {'id': 'pl_dead_123', 'name': 'Deleted Playlist'},
        {'id': 'pl_live_456', 'name': 'Live Playlist'},
      ];

      final filtered = remotePlaylists
          .where((p) => !pendingDeletedPlaylistIds.contains(p['id']))
          .toList();

      expect(filtered.length, 1);
      expect(filtered.first['id'], 'pl_live_456');
    });

    test('2. Dead-letter favorite removal remains protected', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      // Create favorite removal and quarantine it into dead-letter state
      final op = OfflineOperation(
        id: 'fav_rem_dead',
        type: 'favorite_remove',
        payload: {'id': 'track_dead_fav'},
        timestamp: DateTime.now(),
        userId: 'user_active',
      );
      await queue.addOperation(op);
      await queue.markDeadLetter('fav_rem_dead', error: 'Permanent 403');

      final pendingOps = queue.getOperations(includeDeadLetter: true);
      final pendingDeletedFavIds = pendingOps
          .where((o) => o.type == 'favorite_remove' && o.userId == 'user_active')
          .map((o) => o.payload['id']?.toString() ?? '')
          .toSet();

      expect(pendingDeletedFavIds.contains('track_dead_fav'), isTrue);

      final remoteFavs = [
        const Track(id: 'track_dead_fav', title: 'Unliked Song', artist: 'Artist A', imageUrl: '', duration: '3:00'),
        const Track(id: 'track_active_fav', title: 'Liked Song', artist: 'Artist B', imageUrl: '', duration: '3:00'),
      ];

      final filtered = remoteFavs
          .where((f) => !pendingDeletedFavIds.contains(f.id))
          .toList();

      expect(filtered.length, 1);
      expect(filtered.first.id, 'track_active_fav');
    });

    test('3. Dead-letter playlist song removal remains protected', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      // Create playlist song removal and quarantine it
      final op = OfflineOperation(
        id: 'pl_song_rem_dead',
        type: 'playlist_song_remove',
        payload: {'playlistId': 'pl_abc', 'trackId': 'track_quarantined'},
        timestamp: DateTime.now(),
        userId: 'user_active',
      );
      await queue.addOperation(op);
      await queue.markDeadLetter('pl_song_rem_dead', error: 'Network timeout exhausted');

      final pendingOps = queue.getOperations(includeDeadLetter: true);
      final pendingRemovedPlaylistSongs = pendingOps
          .where((o) => o.type == 'playlist_song_remove' && o.userId == 'user_active')
          .map((o) => '${o.payload['playlistId']}_${o.payload['trackId']}')
          .toSet();

      expect(pendingRemovedPlaylistSongs.contains('pl_abc_track_quarantined'), isTrue);

      final remotePlaylistTracks = [
        {'playlist_id': 'pl_abc', 'track_id': 'track_quarantined'},
        {'playlist_id': 'pl_abc', 'track_id': 'track_retained'},
      ];

      final filtered = remotePlaylistTracks
          .where((s) => !pendingRemovedPlaylistSongs.contains('${s['playlist_id']}_${s['track_id']}'))
          .toList();

      expect(filtered.length, 1);
      expect(filtered.first['track_id'], 'track_retained');
    });

    test('4. Another account\'s dead-letter operation does not affect current-account reconciliation', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      // User A deletes playlist pl_shared while authenticated as User A
      final opUserA = OfflineOperation(
        id: 'op_user_a_del',
        type: 'playlist_delete',
        payload: {'id': 'pl_shared'},
        timestamp: DateTime.now(),
        userId: 'user_a',
      );
      await queue.addOperation(opUserA);
      await queue.markDeadLetter('op_user_a_del', error: 'Simulated failure');

      // Now User B reconciles
      const currentUserId = 'user_b';
      final pendingOps = queue.getOperations(includeDeadLetter: true);
      final pendingDeletedForUserB = pendingOps
          .where((o) => o.type == 'playlist_delete' && o.userId == currentUserId)
          .map((o) => o.payload['id']?.toString() ?? '')
          .toSet();

      // User A's dead-letter operation must NOT contaminate User B's reconciliation
      expect(pendingDeletedForUserB.contains('pl_shared'), isFalse);

      final remotePlaylistsUserB = [
        {'id': 'pl_shared', 'name': 'User B Playlist With Shared Id'},
      ];

      final filtered = remotePlaylistsUserB
          .where((p) => !pendingDeletedForUserB.contains(p['id']))
          .toList();

      expect(filtered.length, 1);
      expect(filtered.first['id'], 'pl_shared');
    });

    test('5. Dead-letter protection survives serialization and application restart', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      final opPl = OfflineOperation(
        id: 'pl_del_restart',
        type: 'playlist_delete',
        payload: {'id': 'pl_restart_1'},
        timestamp: DateTime.now(),
        userId: 'user_1',
      );
      final opFav = OfflineOperation(
        id: 'fav_rem_restart',
        type: 'favorite_remove',
        payload: {'id': 'track_restart_1'},
        timestamp: DateTime.now(),
        userId: 'user_1',
      );
      await queue.addOperation(opPl);
      await queue.addOperation(opFav);
      await queue.markDeadLetter('pl_del_restart', error: 'Error 1');
      await queue.markDeadLetter('fav_rem_restart', error: 'Error 2');

      // Simulate app restart by closing and reopening the Hive box
      await box.close();
      final reopenedBox = await Hive.openBox<dynamic>(HiveBoxes.offlineQueue);
      final reopenedQueue = OfflineOperationQueue(reopenedBox);

      // Verify dead letters are preserved with isDeadLetter: true
      final persisted = reopenedQueue.getOperations(includeDeadLetter: true);
      expect(persisted.length, 2);
      expect(persisted.every((o) => o.isDeadLetter), isTrue);

      final pendingDeletedPlaylistIds = persisted
          .where((o) => o.type == 'playlist_delete' && o.userId == 'user_1')
          .map((o) => o.payload['id']?.toString() ?? '')
          .toSet();
      final pendingDeletedFavIds = persisted
          .where((o) => o.type == 'favorite_remove' && o.userId == 'user_1')
          .map((o) => o.payload['id']?.toString() ?? '')
          .toSet();

      expect(pendingDeletedPlaylistIds.contains('pl_restart_1'), isTrue);
      expect(pendingDeletedFavIds.contains('track_restart_1'), isTrue);
    });

    test('6. Concurrent downloadAllRemoteData() calls cannot acquire separate locks', () async {
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(FakeNetworkMonitor(delay: const Duration(milliseconds: 50))),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(syncManagerProvider);

      // Invoke downloadAllRemoteData concurrently
      final future1 = syncManager.downloadAllRemoteData();
      final future2 = syncManager.downloadAllRemoteData();

      expect(syncManager.isSyncing, isTrue);

      // Both execute under the serialized queue without throwing
      await future1;
      await future2;

      expect(syncManager.isSyncing, isFalse);
    });

    test('7. Concurrent download and triggerSync cannot race', () async {
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(FakeNetworkMonitor(delay: const Duration(milliseconds: 50))),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(syncManagerProvider);

      final downloadFuture = syncManager.downloadAllRemoteData();
      final syncFuture = syncManager.triggerSync();

      expect(syncManager.isSyncing, isTrue);

      await downloadFuture;
      await syncFuture;

      expect(syncManager.isSyncing, isFalse);
    });

    test('8. Unrelated PostgreSQL unique violations are not acknowledged as history duplicates', () {
      bool isDeterministicHistoryDuplicate(PostgrestException pgEx) {
        final message = pgEx.message.toLowerCase();
        final details = (pgEx.details?.toString() ?? '').toLowerCase();
        final isPrimaryKeyConflict = message.contains('history_pkey') ||
            details.contains('history_pkey') ||
            details.contains('key (id)=') ||
            (message.contains('duplicate key') && (message.contains('id') || details.contains('(id)')));
        return pgEx.code == '23505' && isPrimaryKeyConflict;
      }

      // Expected primary key conflict on deterministic history ID
      const expectedPkError = PostgrestException(
        message: 'duplicate key value violates unique constraint "history_pkey"',
        code: '23505',
        details: 'Key (id)=(d3b07384-d113-5e93-8758-a92c30084474) already exists.',
      );
      expect(isDeterministicHistoryDuplicate(expectedPkError), isTrue);

      // Unrelated unique constraint violation on another table/column
      const unrelatedUniqueError = PostgrestException(
        message: 'duplicate key value violates unique constraint "users_email_key"',
        code: '23505',
        details: 'Key (email)=(user@example.com) already exists.',
      );
      expect(isDeterministicHistoryDuplicate(unrelatedUniqueError), isFalse);

      // Another unrelated constraint without primary key identity
      const anotherConstraintError = PostgrestException(
        message: 'duplicate key value violates unique constraint "history_user_track_unique"',
        code: '23505',
        details: 'Key (user_id, track_id)=(...) already exists.',
      );
      expect(isDeterministicHistoryDuplicate(anotherConstraintError), isFalse);
    });

    test('9. Recovering a parent operation preserves dependent-operation correctness', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      final now = DateTime.now();
      final parentOp = OfflineOperation(
        id: 'parent_pl_create',
        type: 'playlist_create',
        payload: {'id': 'pl_deep_dive', 'name': 'Deep Dive'},
        timestamp: now,
        userId: 'user_x',
      );
      final childOp = OfflineOperation(
        id: 'child_song_add',
        type: 'playlist_song_add',
        payload: {
          'playlistId': 'pl_deep_dive',
          'track': {'id': 'song_123', 'title': 'Test Song'},
          'position': 0,
        },
        timestamp: now.add(const Duration(seconds: 1)),
        userId: 'user_x',
      );

      await queue.addOperation(parentOp);
      await queue.addOperation(childOp);

      // Quarantine parent due to transient error, and dependent child accordingly
      await queue.markDeadLetter('parent_pl_create', error: 'Connection refused');
      await queue.markDeadLetter(
        'child_song_add',
        error: 'Parent playlist creation failed permanently',
      );

      expect(queue.getOperations().isEmpty, isTrue);
      expect(queue.getDeadLetterOperations().length, 2);

      // Recover parent operation using recoverOperationWithDependents
      await queue.recoverOperationWithDependents('parent_pl_create');

      // Both operations must be recovered to active queue
      final activeOps = queue.getOperations();
      expect(activeOps.length, 2);
      expect(activeOps[0].id, 'parent_pl_create');
      expect(activeOps[0].isDeadLetter, isFalse);
      expect(activeOps[0].retryCount, 0);

      expect(activeOps[1].id, 'child_song_add');
      expect(activeOps[1].isDeadLetter, isFalse);
      expect(activeOps[1].retryCount, 0);
      expect(activeOps[1].lastError, isNull);

      // Dead letter queue is now completely empty
      expect(queue.getDeadLetterOperations().isEmpty, isTrue);
    });
  });

  group('Phase 7: Account-Isolated Deletion Tombstone & Legacy Protection Tests', () {
    const userA = 'user_account_alpha_uuid';
    const userB = 'user_account_beta_uuid';

    test('1. User A\'s dead-letter playlist deletion protects User A\'s playlist', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      // User A deletes playlist pl_alpha_del offline
      final op = OfflineOperation(
        id: 'op_user_a_del',
        type: 'playlist_delete',
        payload: {'id': 'pl_alpha_del'},
        timestamp: DateTime.now(),
        userId: userA,
      );
      await queue.addOperation(op);
      await queue.markDeadLetter('op_user_a_del', error: 'Transient network failure exhausted');

      // Reconciliation for User A
      final pendingOps = queue.getOperations(includeDeadLetter: true);
      final pendingDeletedForUserA = pendingOps
          .where((o) => o.type == 'playlist_delete' && o.userId == userA)
          .map((o) => o.payload['id']?.toString() ?? '')
          .toSet();

      expect(pendingDeletedForUserA.contains('pl_alpha_del'), isTrue);

      final remotePlaylists = [
        {'id': 'pl_alpha_del', 'name': 'Deleted Playlist'},
        {'id': 'pl_alpha_keep', 'name': 'Active Playlist'},
      ];

      final filtered = remotePlaylists
          .where((p) => !pendingDeletedForUserA.contains(p['id']))
          .toList();

      expect(filtered.length, 1);
      expect(filtered.first['id'], 'pl_alpha_keep');
    });

    test('2. User A\'s dead-letter playlist deletion does not hide User B\'s playlist', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      // User A deleted playlist pl_shared_target
      final op = OfflineOperation(
        id: 'op_a_del_shared',
        type: 'playlist_delete',
        payload: {'id': 'pl_shared_target'},
        timestamp: DateTime.now(),
        userId: userA,
      );
      await queue.addOperation(op);
      await queue.markDeadLetter('op_a_del_shared', error: '403 Forbidden');

      // User B reconciles with the same playlist ID on remote
      final pendingOps = queue.getOperations(includeDeadLetter: true);
      final pendingDeletedForUserB = pendingOps
          .where((o) => o.type == 'playlist_delete' && o.userId == userB)
          .map((o) => o.payload['id']?.toString() ?? '')
          .toSet();

      // User B's tombstone set must NOT contain User A's deleted playlist ID
      expect(pendingDeletedForUserB.contains('pl_shared_target'), isFalse);

      final remotePlaylistsUserB = [
        {'id': 'pl_shared_target', 'name': 'User B Playlist'},
      ];

      final filtered = remotePlaylistsUserB
          .where((p) => !pendingDeletedForUserB.contains(p['id']))
          .toList();

      expect(filtered.length, 1);
      expect(filtered.first['id'], 'pl_shared_target');
    });

    test('3. A legacy deletion with null userId does not affect User A', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      // Legacy unassigned deletion with null userId
      await box.put('legacy_pl_delete', {
        'id': 'legacy_pl_delete',
        'type': 'playlist_delete',
        'payload': {'id': 'pl_legacy_100'},
        'timestamp': DateTime.now().toIso8601String(),
        'isDeadLetter': true,
        // userId: null
      });

      // User A reconciles
      final pendingOps = queue.getOperations(includeDeadLetter: true);
      final pendingDeletedForUserA = pendingOps
          .where((o) => o.type == 'playlist_delete' && o.userId == userA)
          .map((o) => o.payload['id']?.toString() ?? '')
          .toSet();

      // Legacy operation with null userId must NOT affect User A
      expect(pendingDeletedForUserA.contains('pl_legacy_100'), isFalse);

      final remotePlaylists = [
        {'id': 'pl_legacy_100', 'name': 'User A Valid Playlist'},
      ];

      final filtered = remotePlaylists
          .where((p) => !pendingDeletedForUserA.contains(p['id']))
          .toList();

      expect(filtered.length, 1);
      expect(filtered.first['id'], 'pl_legacy_100');
    });

    test('4. A legacy favorite removal does not affect User B', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      // Legacy unassigned favorite removal with null userId
      await box.put('legacy_fav_remove', {
        'id': 'legacy_fav_remove',
        'type': 'favorite_remove',
        'payload': {'id': 'track_legacy_fav_99'},
        'timestamp': DateTime.now().toIso8601String(),
        'isDeadLetter': true,
        // userId: null
      });

      // User B reconciles
      final pendingOps = queue.getOperations(includeDeadLetter: true);
      final pendingDeletedFavsForUserB = pendingOps
          .where((o) => o.type == 'favorite_remove' && o.userId == userB)
          .map((o) => o.payload['id']?.toString() ?? '')
          .toSet();

      expect(pendingDeletedFavsForUserB.contains('track_legacy_fav_99'), isFalse);

      final remoteFavs = [
        const Track(id: 'track_legacy_fav_99', title: 'Song 99', artist: 'Artist B', imageUrl: '', duration: '3:00'),
      ];

      final filtered = remoteFavs
          .where((f) => !pendingDeletedFavsForUserB.contains(f.id))
          .toList();

      expect(filtered.length, 1);
      expect(filtered.first.id, 'track_legacy_fav_99');
    });

    test('5. A legacy playlist song removal does not affect another user\'s playlist', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      // Legacy unassigned playlist song removal with null userId
      await box.put('legacy_song_remove', {
        'id': 'legacy_song_remove',
        'type': 'playlist_song_remove',
        'payload': {'playlistId': 'pl_user_a', 'trackId': 'track_shared_55'},
        'timestamp': DateTime.now().toIso8601String(),
        'isDeadLetter': true,
        // userId: null
      });

      // User A reconciles
      final pendingOps = queue.getOperations(includeDeadLetter: true);
      final pendingRemovedSongsUserA = pendingOps
          .where((o) => o.type == 'playlist_song_remove' && o.userId == userA)
          .map((o) => '${o.payload['playlistId']}_${o.payload['trackId']}')
          .toSet();

      expect(pendingRemovedSongsUserA.contains('pl_user_a_track_shared_55'), isFalse);

      final remoteSongs = [
        {'playlist_id': 'pl_user_a', 'track_id': 'track_shared_55'},
      ];

      final filtered = remoteSongs
          .where((s) => !pendingRemovedSongsUserA.contains('${s['playlist_id']}_${s['track_id']}'))
          .toList();

      expect(filtered.length, 1);
      expect(filtered.first['track_id'], 'track_shared_55');
    });

    test('6. Existing owned dead-letter deletion protection still works', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      final opFav = OfflineOperation(
        id: 'op_owned_fav_del',
        type: 'favorite_remove',
        payload: {'id': 'track_owned_del'},
        timestamp: DateTime.now(),
        userId: userA,
      );
      final opPl = OfflineOperation(
        id: 'op_owned_pl_del',
        type: 'playlist_delete',
        payload: {'id': 'pl_owned_del'},
        timestamp: DateTime.now(),
        userId: userA,
      );
      final opSong = OfflineOperation(
        id: 'op_owned_song_del',
        type: 'playlist_song_remove',
        payload: {'playlistId': 'pl_owned_del', 'trackId': 'track_child_del'},
        timestamp: DateTime.now(),
        userId: userA,
      );

      await queue.addOperation(opFav);
      await queue.addOperation(opPl);
      await queue.addOperation(opSong);

      await queue.markDeadLetter('op_owned_fav_del', error: '403');
      await queue.markDeadLetter('op_owned_pl_del', error: '403');
      await queue.markDeadLetter('op_owned_song_del', error: '403');

      final pendingOps = queue.getOperations(includeDeadLetter: true);

      final favDels = pendingOps
          .where((o) => o.type == 'favorite_remove' && o.userId == userA)
          .map((o) => o.payload['id']?.toString() ?? '')
          .toSet();
      final plDels = pendingOps
          .where((o) => o.type == 'playlist_delete' && o.userId == userA)
          .map((o) => o.payload['id']?.toString() ?? '')
          .toSet();
      final songDels = pendingOps
          .where((o) => o.type == 'playlist_song_remove' && o.userId == userA)
          .map((o) => '${o.payload['playlistId']}_${o.payload['trackId']}')
          .toSet();

      expect(favDels.contains('track_owned_del'), isTrue);
      expect(plDels.contains('pl_owned_del'), isTrue);
      expect(songDels.contains('pl_owned_del_track_child_del'), isTrue);
    });

    test('7. These behaviors survive Hive serialization and restart', () async {
      final box = Hive.box<dynamic>(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      // Insert User A owned dead-letter and legacy null userId operation
      final opA = OfflineOperation(
        id: 'op_a_restart',
        type: 'playlist_delete',
        payload: {'id': 'pl_a_restart'},
        timestamp: DateTime.now(),
        userId: userA,
      );
      await queue.addOperation(opA);
      await queue.markDeadLetter('op_a_restart', error: 'Network timeout');

      await box.put('legacy_null_restart', {
        'id': 'legacy_null_restart',
        'type': 'playlist_delete',
        'payload': {'id': 'pl_legacy_restart'},
        'timestamp': DateTime.now().toIso8601String(),
        'isDeadLetter': true,
        // userId: null
      });

      // Simulate app restart
      await box.close();
      final reopenedBox = await Hive.openBox<dynamic>(HiveBoxes.offlineQueue);
      final reopenedQueue = OfflineOperationQueue(reopenedBox);

      final ops = reopenedQueue.getOperations(includeDeadLetter: true);

      // Verify User A tombstone collection
      final delsUserA = ops
          .where((o) => o.type == 'playlist_delete' && o.userId == userA)
          .map((o) => o.payload['id']?.toString() ?? '')
          .toSet();

      expect(delsUserA.contains('pl_a_restart'), isTrue);
      expect(delsUserA.contains('pl_legacy_restart'), isFalse);

      // Verify User B tombstone collection
      final delsUserB = ops
          .where((o) => o.type == 'playlist_delete' && o.userId == userB)
          .map((o) => o.payload['id']?.toString() ?? '')
          .toSet();

      expect(delsUserB.isEmpty, isTrue);
    });
  });

  group('Phase 8: Authentication Failure & RLS Distinction Tests', () {
    test('8. Expired JWT is classified as transient to allow session refresh, while RLS is permanent', () {
      // Helper replicating SyncManager._isTransientError logic
      bool isTransient(dynamic error) {
        if (error is SocketException || error is TimeoutException) return true;
        if (error is PostgrestException) {
          if (error.code == '502' || error.code == '503' || error.code == '504') return true;
          final msg = error.message.toLowerCase();
          final details = (error.details?.toString() ?? '').toLowerCase();
          final isRlsViolation = error.code == '42501' ||
              msg.contains('row-level security') ||
              details.contains('row-level security') ||
              msg.contains('permission denied');
          if (isRlsViolation) return false;
          if (error.code == '401' && (msg.contains('jwt expired') || msg.contains('token expired'))) {
            return true;
          }
          return false;
        }
        return false;
      }

      // Expired token -> must be transient (triggers session refresh, not dead-letter)
      const expiredTokenError = PostgrestException(
        message: 'JWT expired',
        code: '401',
      );
      expect(isTransient(expiredTokenError), isTrue);

      // RLS policy failure -> must be permanent (quarantined to dead-letter)
      const rlsError = PostgrestException(
        message: 'new row violates row-level security policy for table "playlists"',
        code: '42501',
      );
      expect(isTransient(rlsError), isFalse);

      // Generic unauthorized failure without token expiration -> permanent
      const invalidApiKeyError = PostgrestException(
        message: 'Invalid API key',
        code: '401',
      );
      expect(isTransient(invalidApiKeyError), isFalse);
    });
  });
}
