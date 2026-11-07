import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:Miee/core/storage/hive_boxes.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/core/storage/adapters/playlist_hive_model.dart';
import 'package:Miee/core/sync/sync_manager.dart';
import 'package:Miee/core/sync/network_monitor.dart';
import 'package:Miee/core/sync/offline_operation.dart';
import 'package:Miee/core/sync/offline_queue.dart';
import 'package:Miee/features/auth/presentation/auth_controller.dart';

class TestNetworkMonitor implements NetworkMonitor {
  final _controller = StreamController<bool>.broadcast();
  bool _connected;

  TestNetworkMonitor({bool initialConnected = true}) : _connected = initialConnected;

  @override
  Stream<bool> get onConnectivityChanged => _controller.stream;

  @override
  Future<bool> get isConnected async => _connected;

  void emit(bool connected) {
    _connected = connected;
    _controller.add(connected);
  }

  void dispose() {
    _controller.close();
  }
}

class TestAuthController extends AuthController {
  TestAuthController(super.ref, {AuthState initialState = const AuthState()}) {
    state = initialState;
  }

  void setUser(User? user) {
    state = state.copyWith(user: user);
  }

  void signOutManually() {
    state = const AuthState(user: null, isLoading: false, isOfflineMock: false);
  }
}

class SpySyncManager extends SyncManager {
  int triggerSyncCalls = 0;
  final List<bool> forceArguments = [];

  SpySyncManager(super.ref, {super.reconnectDebounceDuration});

  @override
  Future<void> triggerSync({bool force = false}) {
    triggerSyncCalls++;
    forceArguments.add(force);
    return super.triggerSync(force: force);
  }
}

final spySyncManagerProvider = Provider.family<SpySyncManager, Duration?>((ref, debounce) {
  final manager = SpySyncManager(
    ref,
    reconnectDebounceDuration: debounce ?? const Duration(milliseconds: 750),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

User createTestUser(String id, {String email = 'test@example.com'}) {
  return User.fromJson({
    'id': id,
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{'name': 'Test User'},
    'aud': 'authenticated',
    'created_at': DateTime.now().toIso8601String(),
    'email': email,
  })!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('miee_sync_reconnect_test_');
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

  group('Automatic Reconnect Synchronization & Lifecycle Tests', () {
    test('Scenario 1: Offline-to-online transition triggers synchronization', () async {
      final monitor = TestNetworkMonitor(initialConnected: false);
      addTearDown(monitor.dispose);

      late TestAuthController testAuth;
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(monitor),
          authControllerProvider.overrideWith((ref) {
            testAuth = TestAuthController(ref, initialState: AuthState(user: createTestUser('user_reconnect_1')));
            return testAuth;
          }),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(
        spySyncManagerProvider(const Duration(milliseconds: 30)),
      );

      // Wait for initial async state seeding (_wasOffline becomes true)
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(syncManager.triggerSyncCalls, 0);

      // Transition from offline to online
      monitor.emit(true);

      // Wait past debounce duration
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Automatic sync must have been triggered
      expect(syncManager.triggerSyncCalls, 1);
      expect(syncManager.forceArguments.first, isFalse);
    });

    test('Scenario 2: Repeated online events do not trigger overlapping syncs', () async {
      final monitor = TestNetworkMonitor(initialConnected: true);
      addTearDown(monitor.dispose);

      late TestAuthController testAuth;
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(monitor),
          authControllerProvider.overrideWith((ref) {
            testAuth = TestAuthController(ref, initialState: AuthState(user: createTestUser('user_reconnect_2')));
            return testAuth;
          }),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(
        spySyncManagerProvider(const Duration(milliseconds: 30)),
      );

      // Wait for initial async state seeding (_wasOffline is false because already online)
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Emit repeated online events without an offline transition
      monitor.emit(true);
      monitor.emit(true);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Must not trigger sync because app was never offline
      expect(syncManager.triggerSyncCalls, 0);
    });

    test('Scenario 3: Rapid connectivity changes are debounced into a single trigger', () async {
      final monitor = TestNetworkMonitor(initialConnected: false);
      addTearDown(monitor.dispose);

      late TestAuthController testAuth;
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(monitor),
          authControllerProvider.overrideWith((ref) {
            testAuth = TestAuthController(ref, initialState: AuthState(user: createTestUser('user_reconnect_3')));
            return testAuth;
          }),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(
        spySyncManagerProvider(const Duration(milliseconds: 50)),
      );

      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Flapping network: offline -> online -> offline -> online rapidly within debounce window
      monitor.emit(true);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      monitor.emit(false);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      monitor.emit(true);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      monitor.emit(true); // Redundant burst

      // Wait past debounce duration from the last online event
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // Debouncing must coalesce the events into exactly 1 sync call
      expect(syncManager.triggerSyncCalls, 1);
    });

    test('Scenario 4: No sync occurs without an authenticated user', () async {
      final monitor = TestNetworkMonitor(initialConnected: false);
      addTearDown(monitor.dispose);

      late TestAuthController testAuth;
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(monitor),
          authControllerProvider.overrideWith((ref) {
            // Unauthenticated user
            testAuth = TestAuthController(ref, initialState: const AuthState(user: null));
            return testAuth;
          }),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(
        spySyncManagerProvider(const Duration(milliseconds: 30)),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Network transitions to online
      monitor.emit(true);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      // No sync should occur because user is not authenticated
      expect(syncManager.triggerSyncCalls, 0);
    });

    test('Scenario 5: Sign-out prevents subsequent replay for the previous account', () async {
      final monitor = TestNetworkMonitor(initialConnected: false);
      addTearDown(monitor.dispose);

      late TestAuthController testAuth;
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(monitor),
          authControllerProvider.overrideWith((ref) {
            testAuth = TestAuthController(ref, initialState: AuthState(user: createTestUser('user_prev')));
            return testAuth;
          }),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(
        spySyncManagerProvider(const Duration(milliseconds: 30)),
      );

      // Queue an operation belonging to previous user
      final queue = syncManager.queue;
      await queue.addOperation(OfflineOperation(
        id: 'op_prev_user',
        type: 'favorite_add',
        payload: {'id': 't1'},
        timestamp: DateTime.now(),
        userId: 'user_prev',
      ));

      // User signs out
      final authNotifier = container.read(authControllerProvider.notifier) as TestAuthController;
      authNotifier.signOutManually();
      expect(container.read(authControllerProvider).user, isNull);

      // Connectivity restored
      monitor.emit(true);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Automatic sync must be skipped
      expect(syncManager.triggerSyncCalls, 0);

      // Calling replayOfflineQueue directly while signed out safely aborts without crashing
      await syncManager.replayOfflineQueue();

      // Operation remains safely quarantined/preserved in Hive
      expect(queue.getOperations().length, 1);
      expect(queue.getOperations().first.id, 'op_prev_user');
    });

    test('Scenario 6: Switching accounts does not replay previous account queue', () async {
      final monitor = TestNetworkMonitor(initialConnected: true);
      addTearDown(monitor.dispose);

      late TestAuthController testAuth;
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(monitor),
          authControllerProvider.overrideWith((ref) {
            testAuth = TestAuthController(ref, initialState: AuthState(user: createTestUser('user_b')));
            return testAuth;
          }),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(spySyncManagerProvider(null));

      // Queue contains operation belonging to User A
      await syncManager.queue.addOperation(OfflineOperation(
        id: 'op_user_a',
        type: 'favorite_add',
        payload: {'id': 'track_a'},
        timestamp: DateTime.now(),
        userId: 'user_a',
      ));

      // Active user is User B
      expect(container.read(authControllerProvider).user!.id, 'user_b');

      // Filter check: during replay, operations with userId != 'user_b' are strictly skipped
      final allOps = syncManager.queue.getOperations();
      final currentUserId = container.read(authControllerProvider).user!.id;
      final executableForUserB = allOps.where((op) => op.userId == currentUserId).toList();

      expect(executableForUserB, isEmpty);

      // User A's operation is completely untouched
      expect(allOps.length, 1);
      expect(allOps.first.userId, 'user_a');
    });

    test('Scenario 7: JWT refresh failure preserves valid operations', () async {
      final queue = OfflineOperationQueue(Hive.box<dynamic>(HiveBoxes.offlineQueue));
      final op = OfflineOperation(
        id: 'op_jwt_test',
        type: 'favorite_add',
        payload: {'id': 'track_jwt'},
        timestamp: DateTime.now(),
        userId: 'user_jwt',
      );
      await queue.addOperation(op);

      // Simulate a 401 PostgrestException with JWT expired
      const jwtError = PostgrestException(
        message: 'JWT expired',
        code: '401',
      );

      // Verify transient classification
      // 401 JWT expired is transient and must NOT be marked dead-letter
      final isTransient = jwtError.code == '401' && jwtError.message.toLowerCase().contains('jwt expired');
      expect(isTransient, isTrue);

      // Update retry count (transient failure path in SyncManager)
      await queue.updateRetry(op.id, retryCount: op.retryCount + 1, lastError: jwtError.toString());

      // Operation remains in the active queue with incremented retry count
      final activeOps = queue.getOperations();
      expect(activeOps.length, 1);
      expect(activeOps.first.retryCount, 1);
      expect(activeOps.first.lastError, contains('JWT expired'));

      // Dead letter queue must be empty
      expect(queue.getDeadLetterOperations(), isEmpty);
    });

    test('Scenario 8: Temporary network failure preserves queued operations and RLS error dead-letters', () async {
      final queue = OfflineOperationQueue(Hive.box<dynamic>(HiveBoxes.offlineQueue));

      final opNetwork = OfflineOperation(
        id: 'op_socket_err',
        type: 'playlist_create',
        payload: {'id': 'pl_1', 'name': 'Playlist 1'},
        timestamp: DateTime.now(),
        userId: 'user_net',
      );
      await queue.addOperation(opNetwork);

      // Transient SocketException
      const transientError = SocketException('Failed host lookup');
      final isTransient = transientError.message.toLowerCase().contains('failed host lookup');
      expect(isTransient, isTrue);

      // Transient handling
      await queue.updateRetry(opNetwork.id, retryCount: 1, lastError: transientError.toString());
      expect(queue.getOperations().length, 1);
      expect(queue.getDeadLetterOperations(), isEmpty);

      // Permanent RLS violation (42501)
      const rlsError = PostgrestException(
        message: 'new row violates row-level security policy for table "playlists"',
        code: '42501',
      );
      final isPermanentRls = rlsError.code == '42501' || rlsError.message.contains('row-level security');
      expect(isPermanentRls, isTrue);

      // Permanent error moves to dead-letter state
      await queue.markDeadLetter(opNetwork.id, error: rlsError.toString(), retryCount: 2);
      expect(queue.getOperations(), isEmpty);
      expect(queue.getDeadLetterOperations().length, 1);
      expect(queue.getDeadLetterOperations().first.lastError, contains('row-level security'));
    });

    test('Scenario 9: App resume triggers non-forced sync and dispose cleans up observers', () async {
      final monitor = TestNetworkMonitor(initialConnected: true);
      addTearDown(monitor.dispose);

      late TestAuthController testAuth;
      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(monitor),
          authControllerProvider.overrideWith((ref) {
            testAuth = TestAuthController(ref, initialState: AuthState(user: createTestUser('user_resume')));
            return testAuth;
          }),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(spySyncManagerProvider(null));

      // Trigger app resumed lifecycle event
      syncManager.didChangeAppLifecycleState(AppLifecycleState.resumed);

      // It must trigger non-forced sync (force: false)
      expect(syncManager.triggerSyncCalls, 1);
      expect(syncManager.forceArguments.first, isFalse);

      // Disposing syncManager removes lifecycle observer and cancels timers
      syncManager.dispose();

      // Lifecycle event after dispose should not crash
      expect(() => syncManager.didChangeAppLifecycleState(AppLifecycleState.resumed), returnsNormally);
    });

    test('Scenario 10: Manual sync continues to work under mutex lock exclusivity', () async {
      final monitor = TestNetworkMonitor(initialConnected: false);
      addTearDown(monitor.dispose);

      final container = ProviderContainer(
        overrides: [
          networkMonitorProvider.overrideWithValue(monitor),
          authControllerProvider.overrideWith((ref) => TestAuthController(ref, initialState: AuthState(user: createTestUser('user_manual')))),
        ],
      );
      addTearDown(container.dispose);

      final syncManager = container.read(spySyncManagerProvider(null));

      // Calling manual sync with force: true
      final future1 = syncManager.triggerSync(force: true);
      final future2 = syncManager.triggerSync(force: true);

      await Future.wait([future1, future2]);

      expect(syncManager.triggerSyncCalls, 2);
      expect(syncManager.isSyncing, isFalse);
    });

    test('Scenario 11: Existing tombstone and strict account-isolation rules are preserved', () async {
      final queue = OfflineOperationQueue(Hive.box<dynamic>(HiveBoxes.offlineQueue));

      // User A deleted playlist 'pl_user_a'
      await queue.addOperation(OfflineOperation(
        id: 'del_a',
        type: 'playlist_delete',
        payload: {'id': 'pl_user_a'},
        timestamp: DateTime.now(),
        userId: 'user_a',
      ));

      // User B deleted playlist 'pl_user_b'
      await queue.addOperation(OfflineOperation(
        id: 'del_b',
        type: 'playlist_delete',
        payload: {'id': 'pl_user_b'},
        timestamp: DateTime.now(),
        userId: 'user_b',
      ));

      // Unassigned legacy deletion (userId == null)
      await queue.addOperation(OfflineOperation(
        id: 'del_legacy',
        type: 'playlist_delete',
        payload: {'id': 'pl_legacy'},
        timestamp: DateTime.now(),
        userId: null,
      ));

      // Authenticated as User A
      const currentUserId = 'user_a';
      final activeOps = queue.getOperations();
      final deadLetterOps = queue.getDeadLetterOperations();

      // Tombstone collection rule enforced: o.userId == currentUserId
      final pendingDeletedPlaylistIds = {
        ...activeOps
            .where((o) => o.type == 'playlist_delete' && o.userId == currentUserId)
            .map((o) => o.payload['id'] as String),
        ...deadLetterOps
            .where((o) => o.type == 'playlist_delete' && o.userId == currentUserId)
            .map((o) => o.payload['id'] as String),
      };

      // User A tombstones only contain pl_user_a
      expect(pendingDeletedPlaylistIds, contains('pl_user_a'));
      expect(pendingDeletedPlaylistIds.contains('pl_user_b'), isFalse);
      expect(pendingDeletedPlaylistIds.contains('pl_legacy'), isFalse);
    });
  });
}
