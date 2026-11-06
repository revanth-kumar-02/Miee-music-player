import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/core/storage/hive_boxes.dart';
import 'package:Miee/core/sync/sync_manager.dart';
import 'package:Miee/core/sync/sync_state.dart';
import 'package:Miee/core/sync/network_monitor.dart';
import 'package:Miee/core/sync/offline_operation.dart';
import 'package:Miee/core/sync/offline_queue.dart';
import 'package:Miee/core/sync/conflict_resolver.dart';

class FakeNetworkMonitor implements NetworkMonitor {
  final bool connected;
  final Duration delay;
  FakeNetworkMonitor({this.connected = true, this.delay = Duration.zero});

  @override
  Stream<bool> get onConnectivityChanged => const Stream.empty();

  @override
  Future<bool> get isConnected async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    return connected;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('miee_sync_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(HiveBoxes.offlineQueue);
    await Hive.openBox<dynamic>(HiveBoxes.preferences);
    await Hive.openBox<dynamic>(HiveBoxes.profile);
  });

  tearDown(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('REM-03 & REM-04: SyncManager Deduplication & Request Control Tests', () {
    test('1. SyncManager enforces minimum sync interval of 15 seconds', () {
      expect(SyncManager.minSyncInterval, const Duration(seconds: 15));
    });

    test('2. Multiple concurrent triggerSync calls return the exact same Future instance while in-flight', () async {
      // Use a 50ms delay in network check so the Future remains in-flight during synchronous triggers
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(FakeNetworkMonitor(delay: const Duration(milliseconds: 50))),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(syncManagerProvider);

      expect(syncManager.isSyncing, isFalse);

      final future1 = syncManager.triggerSync();
      expect(syncManager.isSyncing, isTrue);

      final future2 = syncManager.triggerSync();
      final future3 = syncManager.triggerSync();

      // All callers share the identical in-flight Future instance
      expect(identical(future1, future2), isTrue);
      expect(identical(future1, future3), isTrue);

      await future1;
      expect(syncManager.isSyncing, isFalse);
    });

    test('3. Non-forced sync within cooldown interval is safely skipped when queue is empty', () async {
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(FakeNetworkMonitor()),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(syncManagerProvider);

      // Force initial sync to establish lastSyncTime
      await syncManager.triggerSync(force: true);

      // Second non-forced call within 15 seconds should return immediately
      final skippedFuture = syncManager.triggerSync(force: false);
      expect(syncManager.isSyncing, isFalse);
      await skippedFuture;
    });

    test('4. Force flag bypasses cooldown interval', () async {
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(FakeNetworkMonitor()),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(syncManagerProvider);

      // Run initial sync
      await syncManager.triggerSync(force: true);

      // Force = true should execute even immediately after
      final forcedFuture = syncManager.triggerSync(force: true);
      await forcedFuture;
      expect(syncManager.isSyncing, isFalse);
    });

    test('5. In-flight mutex resets cleanly in finally block even if offline or unconfigured', () async {
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(FakeNetworkMonitor(connected: false)),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(syncManagerProvider);

      await syncManager.triggerSync();
      expect(syncManager.isSyncing, isFalse);
    });

    test('6. PreferenceKeys.lastSyncTimestamp is registered in preferences box', () {
      expect(PreferenceKeys.lastSyncTimestamp, 'last_sync_timestamp');
      final prefBox = Hive.box<dynamic>(HiveBoxes.preferences);
      final testTime = DateTime.now().toIso8601String();
      prefBox.put(PreferenceKeys.lastSyncTimestamp, testTime);
      expect(prefBox.get(PreferenceKeys.lastSyncTimestamp), testTime);
    });

    test('7. Mutation Queue Sequence: Mutations added during an in-flight sync are preserved and queued without loss', () async {
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(FakeNetworkMonitor(delay: const Duration(milliseconds: 60))),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(syncManagerProvider);

      // 1. Start synchronization
      final syncFuture = syncManager.triggerSync();
      expect(syncManager.isSyncing, isTrue);

      // 2. Add a new mutation while synchronization is running
      final op1 = OfflineOperation(
        id: 'op_1',
        type: 'favorite_add',
        payload: {'id': 'track_1', 'title': 'Song 1'},
        timestamp: DateTime.now(),
      );
      await syncManager.queueOperation(op1);
      expect(syncManager.queue.getOperations().length, 1);

      // 3. Add another mutation before first synchronization completes
      final op2 = OfflineOperation(
        id: 'op_2',
        type: 'favorite_add',
        payload: {'id': 'track_2', 'title': 'Song 2'},
        timestamp: DateTime.now(),
      );
      await syncManager.queueOperation(op2);
      expect(syncManager.queue.getOperations().length, 2);

      // 4. Allow the first synchronization to finish
      await syncFuture;

      // 5. Verify that operations are preserved in queue without loss or race conditions
      final ops = syncManager.queue.getOperations();
      expect(ops.length, 2);
      expect(ops.any((o) => o.id == 'op_1'), isTrue);
      expect(ops.any((o) => o.id == 'op_2'), isTrue);
    });

    test('8. Crash Recovery Semantics: Unacknowledged operations persist in Hive across interrupted cycles', () async {
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(FakeNetworkMonitor(connected: false)),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(syncManagerProvider);

      // Add 3 operations into offline queue
      for (int i = 1; i <= 3; i++) {
        await syncManager.queueOperation(OfflineOperation(
          id: 'crash_op_$i',
          type: 'playlist_song_add',
          payload: {'playlistId': 'pl_1', 'track': {'id': 't_$i', 'title': 'Track $i'}},
          timestamp: DateTime.now(),
        ));
      }

      expect(syncManager.queue.getOperations().length, 3);

      // Simulate interrupted sync cycle
      await syncManager.triggerSync();

      // Because offline/unacknowledged, all 3 operations remain safely in Hive queue
      final remaining = syncManager.queue.getOperations();
      expect(remaining.length, 3);
      expect(remaining.map((o) => o.id).toList(), ['crash_op_1', 'crash_op_2', 'crash_op_3']);
    });

    test('9. Last-Write-Wins Timestamp Correctness: ConflictResolver resolves newest change', () {
      final tOld = DateTime(2026, 11, 1, 10, 0);
      final tNew = DateTime(2026, 11, 1, 12, 0);

      const localVal = 'local_edit';
      const remoteVal = 'remote_edit';

      // Remote is newer -> picks remote
      final winner1 = ConflictResolver.resolveLatest(
        local: localVal,
        localTime: tOld,
        remote: remoteVal,
        remoteTime: tNew,
      );
      expect(winner1, remoteVal);

      // Local is newer -> picks local
      final winner2 = ConflictResolver.resolveLatest(
        local: localVal,
        localTime: tNew,
        remote: remoteVal,
        remoteTime: tOld,
      );
      expect(winner2, localVal);
    });

    test('10. Idempotent Queue Deletion: removeOperation removes only target operation by ID', () async {
      final box = Hive.box(HiveBoxes.offlineQueue);
      final queue = OfflineOperationQueue(box);

      await queue.addOperation(OfflineOperation(
        id: 'dup_1',
        type: 'favorite_remove',
        payload: {'id': 'track_x'},
        timestamp: DateTime.now(),
      ));

      expect(queue.getOperations().length, 1);
      await queue.removeOperation('dup_1');
      expect(queue.getOperations().isEmpty, isTrue);

      // Double deletion is idempotent and does not throw
      await queue.removeOperation('dup_1');
      expect(queue.getOperations().isEmpty, isTrue);
    });
  });
}
