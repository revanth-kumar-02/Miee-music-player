import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/profile/domain/profile_model.dart';
import '../../features/profile/presentation/profile_controller.dart';
import '../../core/storage/hive_boxes.dart';
import '../../core/storage/adapters/track_hive_model.dart';
import '../../core/storage/adapters/playlist_hive_model.dart';
import '../../core/storage/adapters/history_entry.dart';
import '../../shared/models/track.dart';
import '../../features/media/providers/media_providers.dart';
import '../../features/library/providers/library_providers.dart';

import 'network_monitor.dart';
import 'offline_operation.dart';
import 'offline_queue.dart';
import 'conflict_resolver.dart';
import 'sync_state.dart';
import 'supabase_config.dart';

/// Orchestrates background sync, offline replay queues, conflict resolutions, login/logout handshakes.
class SyncManager with WidgetsBindingObserver {
  final Ref _ref;
  final OfflineOperationQueue _operationQueue;
  final NetworkMonitor _networkMonitor;
  late final StreamSubscription<bool> _networkSubscription;

  Future<void>? _currentLock;
  Future<void>? _inFlightSync;
  bool _followUpNeeded = false;
  DateTime? _lastSyncTime;
  static const Duration minSyncInterval = Duration(seconds: 15);

  bool _wasOffline = false;
  Timer? _debounceTimer;
  final Duration reconnectDebounceDuration;

  SyncManager(
    this._ref, {
    this.reconnectDebounceDuration = const Duration(milliseconds: 750),
  })  : _operationQueue = OfflineOperationQueue(Hive.box<dynamic>(HiveBoxes.offlineQueue)),
        _networkMonitor = _ref.read(networkMonitorProvider) {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}

    // Seed initial connectivity state asynchronously
    _networkMonitor.isConnected.then((connected) {
      _wasOffline = !connected;
    });

    // Automatically trigger debounced sync on genuine offline-to-online transitions
    _networkSubscription = _networkMonitor.onConnectivityChanged.listen(_handleConnectivityChanged);
  }

  void _handleConnectivityChanged(bool isOnline) {
    if (!isOnline) {
      _wasOffline = true;
      _debounceTimer?.cancel();
      return;
    }

    // Debounce rapid connectivity events (e.g., cellular/WiFi handoffs or captive portal flaps)
    _debounceTimer?.cancel();
    _debounceTimer = Timer(reconnectDebounceDuration, () async {
      final isReallyConnected = await _networkMonitor.isConnected;
      if (!isReallyConnected) return;

      // Only trigger if we genuinely transitioned from offline to online
      if (_wasOffline) {
        _wasOffline = false;
        final user = _ref.read(authControllerProvider).user;
        if (user != null) {
          debugPrint('[SyncManager] Network restored (offline -> online). Triggering automatic sync.');
          unawaited(triggerSync());
        } else {
          debugPrint('[SyncManager] Network restored but no user authenticated. Skipping automatic sync.');
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleAppResume();
    }
  }

  void _handleAppResume() {
    final user = _ref.read(authControllerProvider).user;
    if (user != null) {
      debugPrint('[SyncManager] App resumed. Triggering non-forced sync (cooldown-guarded).');
      unawaited(triggerSync(force: false));
    }
  }

  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _debounceTimer?.cancel();
    _networkSubscription.cancel();
  }

  OfflineOperationQueue get queue => _operationQueue;

  bool get isSyncing => _inFlightSync != null;
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Executes [action] exclusively under the shared synchronization lock.
  /// Synchronously queues against [_currentLock] to prevent races between callers
  /// observing a null mutex before assignment.
  Future<void> _runExclusive(Future<void> Function() action) {
    final previous = _currentLock;
    final completer = Completer<void>();
    final syncFuture = completer.future;
    _currentLock = syncFuture;
    _inFlightSync = syncFuture;

    () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // Ignore failures in previous operations so subsequent operations are not blocked
        }
      }
      try {
        await action();
        completer.complete();
      } catch (e, st) {
        completer.completeError(e, st);
      } finally {
        if (_currentLock == syncFuture) {
          _currentLock = null;
          _inFlightSync = null;
        }
      }
    }();

    return syncFuture;
  }

  static bool _isTransientError(dynamic error) {
    if (error is SocketException || error is TimeoutException) {
      return true;
    }
    final str = error.toString().toLowerCase();
    if (str.contains('socketexception') ||
        str.contains('clientexception') ||
        str.contains('connection timed out') ||
        str.contains('connection refused') ||
        str.contains('failed host lookup') ||
        str.contains('network is unreachable') ||
        str.contains('software caused connection abort') ||
        str.contains('handshakeexception') ||
        str.contains('timeout')) {
      return true;
    }
    if (error is PostgrestException) {
      // 5xx status codes indicate transient server errors
      if (error.code == '502' || error.code == '503' || error.code == '504') {
        return true;
      }
      final msg = error.message.toLowerCase();
      final details = (error.details?.toString() ?? '').toLowerCase();

      // Row-Level Security (RLS) or permission violations are permanent authorization/policy failures
      final isRlsViolation = error.code == '42501' ||
          msg.contains('row-level security') ||
          details.contains('row-level security') ||
          msg.contains('permission denied');
      if (isRlsViolation) {
        return false; // Permanent RLS violation -> move to dead-letter
      }

      // Expired JWT / token (401) is transient and recoverable via session refresh
      if (error.code == '401' && (msg.contains('jwt expired') || msg.contains('token expired'))) {
        return true; // Transient expired token -> session refreshable
      }
      return false;
    }
    return false;
  }

  /// Queues an operation locally if offline, otherwise replays instantly.
  Future<void> queueOperation(OfflineOperation op) async {
    final currentUserId = _ref.read(authControllerProvider).user?.id;
    final resolvedOp = (op.userId == null && currentUserId != null)
        ? op.copyWith(userId: currentUserId)
        : op;
    await _operationQueue.addOperation(resolvedOp);
    // Trigger background sync in the background
    unawaited(triggerSync());
  }

  /// Replays all queued offline operations to Supabase with unified mutex protection.
  Future<void> replayOfflineQueue() {
    if (_inFlightSync != null) {
      return _inFlightSync!;
    }
    return _runExclusive(() async {
      await _replayQueueInternal();
    });
  }

  /// Internal queue replay implementation executed under the synchronization mutex.
  Future<void> _replayQueueInternal() async {
    final authState = _ref.read(authControllerProvider);
    final isOnline = await _networkMonitor.isConnected;

    if (!isOnline || !SupabaseConfig.hasActiveSupabase || !SupabaseConfig.isInitialized || authState.user == null) {
      return;
    }

    final client = Supabase.instance.client;
    final currentUserId = authState.user!.id;
    final operations = _operationQueue.getOperations();

    // Track permanently failed playlist IDs so dependent operations don't retry fruitlessly
    final Set<String> failedPlaylistCreations = {};

    for (final op in operations) {
      // 1. Account Isolation Validation
      if (op.userId != null && op.userId != currentUserId) {
        debugPrint('[SyncManager] Skipping operation ${op.id} belonging to user ${op.userId} while authenticated as $currentUserId');
        continue;
      }

      if (op.userId == null) {
        // Legacy or unassigned operation without known account identity
        debugPrint('[SyncManager] Quarantining legacy operation ${op.id} without account identity');
        await _operationQueue.quarantineOperation(
          op.id,
          reason: 'Unassigned/legacy operation without user ownership',
        );
        continue;
      }

      // 2. Dependency Check: If parent playlist creation failed permanently, fail dependent operations
      final parentPlaylistId = op.payload['playlistId']?.toString();
      if ((op.type == 'playlist_song_add' ||
              op.type == 'playlist_song_remove' ||
              op.type == 'playlist_tracks_reorder') &&
          parentPlaylistId != null &&
          failedPlaylistCreations.contains(parentPlaylistId)) {
        debugPrint('[SyncManager] Quarantining dependent operation ${op.id} because parent playlist creation failed');
        await _operationQueue.markDeadLetter(
          op.id,
          error: 'Parent playlist creation failed permanently',
        );
        continue;
      }

      try {
        final payload = op.payload;
        final userId = currentUserId;

        switch (op.type) {
          case 'favorite_add':
            await client.from('liked_songs').upsert({
              'user_id': userId,
              'track_id': payload['id'],
              'title': payload['title'] ?? 'Unknown Track',
              'artist': payload['artist'] ?? 'Unknown Artist',
              'image_url': payload['imageUrl'],
              'file_path': payload['filePath'],
              'is_youtube': payload['isYoutube'] ?? false,
              'liked_at': op.timestamp.toIso8601String(),
            }, onConflict: 'user_id,track_id');
            break;

          case 'favorite_remove':
            await client
                .from('liked_songs')
                .delete()
                .eq('track_id', payload['id'] as Object)
                .eq('user_id', userId);
            break;

          case 'playlist_create':
            await client.from('playlists').upsert({
              'id': payload['id'],
              'user_id': userId,
              'name': payload['name'],
              'created_at': payload['createdAt'],
              'last_modified': payload['lastModified'],
            });
            break;

          case 'playlist_delete':
            await client
                .from('playlists')
                .delete()
                .eq('id', payload['id'] as Object)
                .eq('user_id', userId);
            break;

          case 'playlist_rename':
            await client.from('playlists').upsert({
              'id': payload['id'],
              'user_id': userId,
              'name': payload['name'],
              'last_modified': payload['lastModified'],
            });
            break;

          case 'playlist_tracks_reorder':
            // ARCHITECTURAL NOTE — Playlist Reorder Synchronization:
            // 1. Partial-Update Behavior: Each track position is updated sequentially over REST.
            //    If network drops mid-loop (e.g. at index k of N), items 0..k-1 have updated positions
            //    while items k..N retain old positions on remote.
            // 2. Retry Safety: Because the payload contains the complete intended position array,
            //    a subsequent retry re-applies all intended positions from index 0,
            //    eventually restoring the intended order (idempotent convergence).
            // 3. Affected-Row Behavior: PostgREST .update() returns 200 even if 0 rows matched
            //    (e.g. if a track was concurrently removed). The loop continues safely.
            // 4. Future Transactional Solution: To eliminate interim inconsistent states visible
            //    to concurrent clients, implement an atomic PostgreSQL RPC function
            //    (e.g., 'reorder_playlist_tracks(p_playlist_id, p_positions)') that updates all positions
            //    within a single SQL transaction.
            final positions = payload['trackPositions'] as List<dynamic>? ?? [];
            for (final item in positions) {
              if (item is Map) {
                await client
                    .from('playlist_tracks')
                    .update({'position': item['position']})
                    .eq('playlist_id', payload['playlistId'] as Object)
                    .eq('track_id', item['trackId'] as Object)
                    .eq('user_id', userId);
              }
            }
            if (payload['lastModified'] != null) {
              await client.from('playlists').update({
                'last_modified': payload['lastModified'],
              }).eq('id', payload['playlistId'] as Object).eq('user_id', userId);
            }
            break;

          case 'playlist_song_add':
            final song = payload['track'];
            await client.from('playlist_tracks').upsert({
              'playlist_id': payload['playlistId'],
              'track_id': song['id'],
              'user_id': userId,
              'title': song['title'] ?? 'Unknown Track',
              'artist': song['artist'] ?? 'Unknown Artist',
              'image_url': song['imageUrl'],
              'file_path': song['filePath'],
              'is_youtube': song['isYoutube'] ?? false,
              'position': payload['position'] ?? 0,
              'added_at': op.timestamp.toIso8601String(),
            }, onConflict: 'playlist_id,track_id');
            break;

          case 'playlist_song_remove':
            await client
                .from('playlist_tracks')
                .delete()
                .eq('playlist_id', payload['playlistId'] as Object)
                .eq('track_id', payload['trackId'] as Object)
                .eq('user_id', userId);
            break;

          case 'profile_update':
            await client.from('profiles').upsert({
              'id': userId,
              'display_name': payload['displayName'],
              'username': payload['username'],
              'profile_picture_path': payload['profilePicturePath'],
              'favorite_genre': payload['favoriteGenre'],
              'favorite_artist': payload['favoriteArtist'],
              'playback_speed': payload['playbackSpeed'],
              'preferred_source': payload['preferredSource'],
              'default_shuffle': payload['defaultShuffle'],
              'default_repeat': payload['defaultRepeat'],
              'resume_playback': payload['resumePlayback'],
              'background_playback': payload['backgroundPlayback'],
              'media_notification': payload['mediaNotification'],
              'lock_screen_controls': payload['lockScreenControls'],
              'gapless_playback': payload['gaplessPlayback'],
              'crossfade': payload['crossfade'],
              'last_scan_time': payload['lastScanTime'],
              'updated_at': op.timestamp.toIso8601String(),
            });
            break;

          case 'settings_update':
            // Handled dynamically under profiles/settings sync
            break;

          case 'history_add':
            // Generate deterministic UUID for idempotency
            final trackId = payload['id']?.toString() ?? '';
            final playedAtStr = payload['playedAt']?.toString() ?? op.timestamp.toIso8601String();
            final deterministicId = const Uuid().v5(Namespace.url.value, 'miee:history:$userId:$trackId:$playedAtStr');

            try {
              await client.from('history').insert({
                'id': deterministicId,
                'track_id': trackId,
                'user_id': userId,
                'title': payload['title'],
                'artist': payload['artist'],
                'image_url': payload['imageUrl'],
                'duration': payload['duration'],
                'file_path': payload['filePath'],
                'is_youtube': payload['isYoutube'] ?? false,
                'played_at': playedAtStr,
              });
            } on PostgrestException catch (pgEx) {
              // Code '23505' indicates duplicate key violation. Only treat as idempotent success if
              // it is demonstrably the expected deterministic history primary-key conflict.
              final message = pgEx.message.toLowerCase();
              final details = (pgEx.details?.toString() ?? '').toLowerCase();
              final isPrimaryKeyConflict = message.contains('history_pkey') ||
                  details.contains('history_pkey') ||
                  details.contains('key (id)=') ||
                  (message.contains('duplicate key') && (message.contains('id') || details.contains('(id)')));

              if (pgEx.code == '23505' && isPrimaryKeyConflict) {
                debugPrint('[SyncManager] Idempotent history insertion: primary key record $deterministicId already exists on Supabase');
              } else {
                rethrow;
              }
            }
            break;

          case 'most_played_increment':
            await client.from('most_played').upsert({
              'track_id': payload['trackId'],
              'user_id': userId,
              'count': payload['count'],
              'updated_at': op.timestamp.toIso8601String(),
            });
            break;

          case 'search_add':
            await client.from('search_history').upsert({
              'user_id': userId,
              'query': payload['query'],
              'timestamp': payload['timestamp'],
            }, onConflict: 'user_id,query');
            break;

          case 'search_remove':
            await client
                .from('search_history')
                .delete()
                .eq('query', payload['query'] as Object)
                .eq('user_id', userId);
            break;
        }

        // Remove successfully replayed operation
        await _operationQueue.removeOperation(op.id);
      } catch (e) {
        debugPrint('Failed to replay offline operation ${op.id} (${op.type}): $e');
        final isTransient = _isTransientError(e);
        final newRetryCount = op.retryCount + 1;

        if (op.type == 'playlist_create') {
          failedPlaylistCreations.add(op.payload['id']?.toString() ?? '');
        }

        // Attempt session refresh if token expired during replay
        if (e is PostgrestException && (e.code == '401' || e.message.toLowerCase().contains('jwt expired'))) {
          try {
            debugPrint('[SyncManager] Token expired during replay. Attempting session refresh...');
            final refresh = await client.auth.refreshSession();
            if (refresh.session != null) {
              debugPrint('[SyncManager] Session refreshed successfully.');
            }
          } catch (refreshErr) {
            debugPrint('[SyncManager] Session refresh attempt failed: $refreshErr');
          }
        }

        // Only permanent errors (non-transient) should be quarantined to dead-letter immediately.
        // Purely transient connection/network errors (e.g. SocketException, TimeoutException, expired JWT)
        // must NOT be quarantined into dead-letter simply because an outage lasted several retries.
        if (!isTransient) {
          // Permanent failure or schema/constraint violation -> move to dead-letter state so it does not block the queue
          debugPrint('[SyncManager] Moving operation ${op.id} to dead-letter state: $e');
          await _operationQueue.markDeadLetter(
            op.id,
            error: e.toString(),
            retryCount: newRetryCount,
          );
          // Continue to next independent operation!
        } else {
          // Transient failure (network unreachable, timeout, session refresh needed) -> update retry count and break batch to avoid spamming down network
          await _operationQueue.updateRetry(
            op.id,
            retryCount: newRetryCount,
            lastError: e.toString(),
          );
          break;
        }
      }
    }
  }

  /// Triggers background offline-first synchronization flow.
  ///
  /// Protects against duplicate concurrent sync requests via an in-flight Future mutex.
  /// Reuses in-flight synchronization tasks and queues a pending pass if requests arrive during execution.
  /// Enforces a minimum interval ([minSyncInterval]) between automatic background syncs unless [force] is true.
  Future<void> triggerSync({bool force = false}) {
    // 1. In-flight synchronization protection: Reuse active Future directly
    if (_inFlightSync != null) {
      _followUpNeeded = true;
      return _inFlightSync!;
    }

    // 2. Cooldown / debouncing: Skip non-forced runs within minSyncInterval if queue is empty
    if (!force && _lastSyncTime != null && DateTime.now().difference(_lastSyncTime!) < minSyncInterval) {
      if (_operationQueue.getOperations().isEmpty) {
        return Future.value();
      }
    }

    return _runExclusive(() async {
      final didRun = await _performSync(force: force);
      if (didRun && _followUpNeeded && _operationQueue.getOperations().isNotEmpty) {
        _followUpNeeded = false;
        unawaited(triggerSync());
      }
    });
  }

  Future<bool> _performSync({bool force = false}) async {
    final syncNotifier = _ref.read(syncStateProvider.notifier);
    final authState = _ref.read(authControllerProvider);
    final isOnline = await _networkMonitor.isConnected;

    if (!isOnline || !SupabaseConfig.hasActiveSupabase || !SupabaseConfig.isInitialized || authState.user == null) {
      _lastSyncTime = DateTime.now();
      return false;
    }

    syncNotifier.setSyncing();

    try {
      final client = Supabase.instance.client;
      final userId = authState.user!.id;

      // Read last sync timestamp for incremental delta sync
      DateTime? lastSync;
      Box<dynamic>? prefBox;
      if (Hive.isBoxOpen(HiveBoxes.preferences)) {
        prefBox = Hive.box<dynamic>(HiveBoxes.preferences);
        final lastSyncStr = prefBox.get(PreferenceKeys.lastSyncTimestamp) as String?;
        if (lastSyncStr != null && !force) {
          lastSync = DateTime.tryParse(lastSyncStr);
        }
      }

      // 1. Replay local changes to Cloud
      await _replayQueueInternal();

      // Collect pending and dead-letter local deletions to prevent remote resurrection.
      // Strict account isolation: only deletions explicitly owned by the current authenticated
      // user protect against resurrection. Unassigned legacy operations remain quarantined
      // and do not influence any user's cloud data.
      final pendingOps = _operationQueue.getOperations(includeDeadLetter: true);
      final pendingDeletedFavIds = pendingOps
          .where((o) => o.type == 'favorite_remove' && o.userId == userId)
          .map((o) => o.payload['id']?.toString() ?? '')
          .toSet();

      final pendingDeletedPlaylistIds = pendingOps
          .where((o) => o.type == 'playlist_delete' && o.userId == userId)
          .map((o) => o.payload['id']?.toString() ?? '')
          .toSet();

      final pendingRemovedPlaylistSongs = pendingOps
          .where((o) => o.type == 'playlist_song_remove' && o.userId == userId)
          .map((o) => '${o.payload['playlistId']}_${o.payload['trackId']}')
          .toSet();

      // 2. Fetch Remote Updates from Cloud
      // A. Profile & Settings Table
      final profileRes = await client.from('profiles').select().eq('id', userId).maybeSingle();
      if (profileRes != null) {
        final localProfile = _ref.read(profileProvider);
        final remoteCreated = DateTime.tryParse(profileRes['created_at']?.toString() ?? profileRes['created_date']?.toString() ?? '') ?? localProfile.createdDate;
        final remoteUpdated = DateTime.tryParse(profileRes['updated_at']?.toString() ?? profileRes['last_opened']?.toString() ?? '') ?? localProfile.lastOpened;

        final remoteProfile = ProfileModel(
          displayName: profileRes['display_name'] as String? ?? localProfile.displayName,
          username: profileRes['username'] as String? ?? localProfile.username,
          profilePicturePath: profileRes['profile_picture_path'] as String? ?? localProfile.profilePicturePath,
          favoriteGenre: profileRes['favorite_genre'] as String? ?? 'Acoustic',
          favoriteArtist: profileRes['favorite_artist'] as String? ?? 'Unknown Artist',
          createdDate: remoteCreated,
          lastOpened: remoteUpdated,
          playbackSpeed: (profileRes['playback_speed'] as num? ?? 1.0).toDouble(),
          preferredSource: profileRes['preferred_source'] as String? ?? 'preferLocal',
          defaultShuffle: profileRes['default_shuffle'] as bool? ?? false,
          defaultRepeat: profileRes['default_repeat'] as String? ?? 'off',
          resumePlayback: profileRes['resume_playback'] as bool? ?? true,
          backgroundPlayback: profileRes['background_playback'] as bool? ?? true,
          mediaNotification: profileRes['media_notification'] as bool? ?? true,
          lockScreenControls: profileRes['lock_screen_controls'] as bool? ?? true,
          gaplessPlayback: profileRes['gapless_playback'] as bool? ?? true,
          crossfade: profileRes['crossfade'] as bool? ?? false,
          lastScanTime: profileRes['last_scan_time'] as String?,
        );

        final resolved = ConflictResolver.resolveLatest(
          local: localProfile,
          localTime: localProfile.lastOpened,
          remote: remoteProfile,
          remoteTime: remoteUpdated,
        );

        // Update local profile box synchronously
        final profileBox = Hive.box<dynamic>(HiveBoxes.profile);
        await profileBox.put('active_profile', {
          'displayName': resolved.displayName,
          'username': resolved.username,
          'profilePicturePath': resolved.profilePicturePath,
          'favoriteGenre': resolved.favoriteGenre,
          'favoriteArtist': resolved.favoriteArtist,
          'createdDate': resolved.createdDate.toIso8601String(),
          'lastOpened': resolved.lastOpened.toIso8601String(),
          'playbackSpeed': resolved.playbackSpeed,
          'preferredSource': resolved.preferredSource,
          'defaultShuffle': resolved.defaultShuffle,
          'defaultRepeat': resolved.defaultRepeat,
          'resumePlayback': resolved.resumePlayback,
          'backgroundPlayback': resolved.backgroundPlayback,
          'mediaNotification': resolved.mediaNotification,
          'lockScreenControls': resolved.lockScreenControls,
          'gaplessPlayback': resolved.gaplessPlayback,
          'crossfade': resolved.crossfade,
          'lastScanTime': resolved.lastScanTime,
        });

        // Update profile controller state
        unawaited(_ref.read(profileProvider.notifier).updateProfile(
              displayName: resolved.displayName,
              username: resolved.username,
              profilePicturePath: resolved.profilePicturePath,
              favoriteGenre: resolved.favoriteGenre,
              favoriteArtist: resolved.favoriteArtist,
            ));
      } else {
        // Upload local profile to Cloud if none exists
        final local = _ref.read(profileProvider);
        await client.from('profiles').upsert({
          'id': userId,
          'display_name': local.displayName,
          'username': local.username,
          'profile_picture_path': local.profilePicturePath,
          'favorite_genre': local.favoriteGenre,
          'favorite_artist': local.favoriteArtist,
          'playback_speed': local.playbackSpeed,
          'preferred_source': local.preferredSource,
          'default_shuffle': local.defaultShuffle,
          'default_repeat': local.defaultRepeat,
          'resume_playback': local.resumePlayback,
          'background_playback': local.backgroundPlayback,
          'media_notification': local.mediaNotification,
          'lock_screen_controls': local.lockScreenControls,
          'gapless_playback': local.gaplessPlayback,
          'crossfade': local.crossfade,
          'last_scan_time': local.lastScanTime,
          'created_at': local.createdDate.toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      // B. Favorites Table (liked_songs)
      final favsBox = Hive.box<TrackHiveModel>(HiveBoxes.favorites);
      if (lastSync != null) {
        // Delta sync: fetch only newly added/modified records since lastSync
        final deltaRes = await client
            .from('liked_songs')
            .select()
            .eq('user_id', userId)
            .gt('liked_at', lastSync.toIso8601String());

        final List<Track> deltaFavs = (deltaRes as List).map((f) {
          return Track(
            id: f['track_id'] as String,
            title: f['title'] as String,
            artist: f['artist'] as String,
            imageUrl: f['image_url'] as String? ?? '',
            duration: '3:00',
            filePath: f['file_path'] as String?,
          );
        }).where((t) => !pendingDeletedFavIds.contains(t.id)).toList();

        for (final track in deltaFavs) {
          await favsBox.put(track.id, TrackHiveModel.fromTrack(track));
        }
      } else {
        // Full sync: download entire catalog and reconcile
        final favsRes = await client.from('liked_songs').select().eq('user_id', userId);
        final List<Track> remoteFavs = (favsRes as List).map((f) {
          return Track(
            id: f['track_id'] as String,
            title: f['title'] as String,
            artist: f['artist'] as String,
            imageUrl: f['image_url'] as String? ?? '',
            duration: '3:00',
            filePath: f['file_path'] as String?,
          );
        }).where((t) => !pendingDeletedFavIds.contains(t.id)).toList();

        final localFavs = favsBox.values.map((t) => t.toTrack()).toList();

        final mergedFavs = ConflictResolver.mergeLists<Track, String>(
          local: localFavs,
          remote: remoteFavs,
          idSelector: (t) => t.id,
          mergeFn: (l, r) => l, // Keep either
        );

        // Check auth state before persisting to local Hive to prevent cross-account leaks on sign-out
        if (_ref.read(authControllerProvider).user?.id != userId) return false;

        // Save resolved favorites to Hive
        await favsBox.clear();
        for (final track in mergedFavs) {
          await favsBox.put(track.id, TrackHiveModel.fromTrack(track));
        }
      }

      // C. Playlists & Playlist Tracks
      final playlistsRes = await client.from('playlists').select().eq('user_id', userId);
      final playlistTracksRes = await client
          .from('playlist_tracks')
          .select()
          .eq('user_id', userId)
          .order('position', ascending: true);

      final playlistsBox = Hive.box<PlaylistHiveModel>(HiveBoxes.playlists);
      final localPlaylists = playlistsBox.values.toList();

      final List<PlaylistHiveModel> remotePlaylists = (playlistsRes as List)
          .where((p) => !pendingDeletedPlaylistIds.contains(p['id']?.toString() ?? ''))
          .map((p) {
        final pId = p['id'] as String;
        final songs = (playlistTracksRes as List)
            .where((s) => s['playlist_id'] == pId && !pendingRemovedPlaylistSongs.contains('${pId}_${s['track_id']}'))
            .map((s) => TrackHiveModel(
                  id: s['track_id'] as String,
                  title: s['title'] as String,
                  artist: s['artist'] as String,
                  imageUrl: s['image_url'] as String? ?? '',
                  duration: '3:00',
                  filePath: s['file_path'] as String?,
                ))
            .toList();

        return PlaylistHiveModel(
          id: pId,
          name: p['name'] as String,
          tracks: songs,
          createdAt: DateTime.parse(p['created_at'] as String),
          lastModified: DateTime.parse(p['last_modified'] as String),
        );
      }).toList();

      final mergedPlaylists = ConflictResolver.mergeLists<PlaylistHiveModel, String>(
        local: localPlaylists,
        remote: remotePlaylists,
        idSelector: (p) => p.id,
        mergeFn: (localPl, remotePl) {
          // Resolve metadata Conflict
          final resolvedMetadata = ConflictResolver.resolveLatest(
            local: localPl,
            localTime: localPl.lastModified,
            remote: remotePl,
            remoteTime: remotePl.lastModified,
          );
          // Resolve playlist songs Conflict
          final mergedSongs = ConflictResolver.mergeLists<TrackHiveModel, String>(
            local: localPl.tracks,
            remote: remotePl.tracks,
            idSelector: (s) => s.id,
            mergeFn: (l, r) => l,
          );
          return PlaylistHiveModel(
            id: resolvedMetadata.id,
            name: resolvedMetadata.name,
            tracks: mergedSongs,
            createdAt: resolvedMetadata.createdAt,
            lastModified: resolvedMetadata.lastModified,
          );
        },
      );

      // Check auth state before persisting to local Hive to prevent cross-account leaks on sign-out
      if (_ref.read(authControllerProvider).user?.id != userId) return false;

      // Save resolved Playlists to Hive
      await playlistsBox.clear();
      for (final p in mergedPlaylists) {
        await playlistsBox.put(p.id, p);
      }

      // D. Recently Played History
      final historyRes = await client.from('history').select().eq('user_id', userId).order('played_at', ascending: false).limit(100);
      final historyBox = Hive.box<HistoryEntry>(HiveBoxes.recentlyPlayed);
      final localHistory = historyBox.values.toList();

      final List<HistoryEntry> remoteHistory = (historyRes as List).map((h) {
        return HistoryEntry(
          track: TrackHiveModel(
            id: h['track_id'] as String,
            title: h['title'] as String,
            artist: h['artist'] as String,
            imageUrl: h['image_url'] as String? ?? '',
            duration: h['duration'] as String? ?? '3:00',
            filePath: h['file_path'] as String?,
          ),
          playedAt: h['played_at'] != null ? DateTime.tryParse(h['played_at'] as String) ?? DateTime.now() : DateTime.now(),
        );
      }).toList();

      final mergedHistory = ConflictResolver.mergeLists<HistoryEntry, String>(
        local: localHistory,
        remote: remoteHistory,
        idSelector: (h) => '${h.track.id}_${h.playedAt.millisecondsSinceEpoch}',
        mergeFn: (l, r) => l,
      )..sort((a, b) => b.playedAt.compareTo(a.playedAt));

      // Save resolved history
      await historyBox.clear();
      // Keep up to 100 entries to optimize list sizes
      final truncatedHistory = mergedHistory.take(100).toList();
      for (int i = 0; i < truncatedHistory.length; i++) {
        await historyBox.put(i, truncatedHistory[i]);
      }

      // E. Most Played counts
      final mostPlayedRes = await client.from('most_played').select().eq('user_id', userId);
      final mostPlayedBox = Hive.box<int>(HiveBoxes.mostPlayed);
      final localMostPlayed = mostPlayedBox.toMap();

      final Map<String, int> remoteMostPlayed = {
        for (final m in mostPlayedRes as List)
          m['track_id'] as String: m['count'] as int
      };

      // Resolve most played by taking the maximum play count
      final Map<String, int> resolvedMostPlayed = {};
      localMostPlayed.forEach((k, v) {
        final String keyStr = k as String;
        final remoteVal = remoteMostPlayed[keyStr] ?? 0;
        resolvedMostPlayed[keyStr] = v > remoteVal ? v : remoteVal;
      });
      remoteMostPlayed.forEach((k, v) {
        if (!resolvedMostPlayed.containsKey(k)) {
          resolvedMostPlayed[k] = v;
        }
      });

      await mostPlayedBox.clear();
      for (final entry in resolvedMostPlayed.entries) {
        await mostPlayedBox.put(entry.key, entry.value);
      }

      // F. Search History
      final searchRes = await client.from('search_history').select().eq('user_id', userId).order('timestamp', ascending: false).limit(20);
      final searchBox = Hive.box<String>(HiveBoxes.searchHistory);
      final localSearch = searchBox.values.toList();
      final List<String> remoteSearch = (searchRes as List).map((s) => s['query'] as String).toList();

      final Set<String> mergedSearchSet = {...localSearch, ...remoteSearch};
      await searchBox.clear();
      await searchBox.addAll(mergedSearchSet.take(20));

      // 3. Mark success
      final now = DateTime.now();
      _lastSyncTime = now;
      if (prefBox != null) {
        await prefBox.put(PreferenceKeys.lastSyncTimestamp, now.toIso8601String());
      }
      syncNotifier.setSuccess(now);

      // Invalidate UI state providers so list screens redraw instantly
      _ref.invalidate(songsProvider);
      _ref.invalidate(playlistsProvider);
      _ref.invalidate(favoritesProvider);
      _ref.invalidate(recentlyPlayedProvider);
      _ref.invalidate(searchHistoryProvider);
      return true;

    } catch (e, st) {
      debugPrint('[SyncManager] Sync failed: $e\n$st');
      syncNotifier.setError(e.toString());
      return false;
    }
  }

  /// Downloads all remote data from Supabase, completely replacing local Cache (used on sign-in).
  /// Coordinated under the shared synchronization lock to prevent race conditions or collisions with active syncs.
  Future<void> downloadAllRemoteData() {
    return _runExclusive(() async {
      await _performDownloadAllRemoteData();
    });
  }

  Future<void> _performDownloadAllRemoteData() async {
    final authState = _ref.read(authControllerProvider);
    final isOnline = await _networkMonitor.isConnected;

    if (!isOnline || !SupabaseConfig.hasActiveSupabase || !SupabaseConfig.isInitialized || authState.user == null) {
      return;
    }

    final client = Supabase.instance.client;
    final userId = authState.user!.id;

    // Collect pending and dead-letter local deletions so restoring remote data
    // does not resurrect items deleted locally.
    // Strict account isolation: only deletions explicitly owned by the current authenticated user.
    final pendingOps = _operationQueue.getOperations(includeDeadLetter: true);
    final pendingDeletedFavIds = pendingOps
        .where((o) => o.type == 'favorite_remove' && o.userId == userId)
        .map((o) => o.payload['id']?.toString() ?? '')
        .toSet();

    final pendingDeletedPlaylistIds = pendingOps
        .where((o) => o.type == 'playlist_delete' && o.userId == userId)
        .map((o) => o.payload['id']?.toString() ?? '')
        .toSet();

    final pendingRemovedPlaylistSongs = pendingOps
        .where((o) => o.type == 'playlist_song_remove' && o.userId == userId)
        .map((o) => '${o.payload['playlistId']}_${o.payload['trackId']}')
        .toSet();

    // A. Profile
    final profileRes = await client.from('profiles').select().eq('id', userId).maybeSingle();
    if (profileRes != null) {
      final profileBox = Hive.box<dynamic>(HiveBoxes.profile);
      await profileBox.put('active_profile', {
        'displayName': profileRes['display_name'] as String? ?? 'Miee User',
        'username': profileRes['username'] as String?,
        'profilePicturePath': profileRes['profile_picture_path'] as String?,
        'favoriteGenre': profileRes['favorite_genre'] as String? ?? 'Acoustic',
        'favoriteArtist': profileRes['favorite_artist'] as String? ?? 'Unknown Artist',
        'createdDate': profileRes['created_at']?.toString() ?? profileRes['created_date']?.toString() ?? DateTime.now().toIso8601String(),
        'lastOpened': profileRes['updated_at']?.toString() ?? profileRes['last_opened']?.toString() ?? DateTime.now().toIso8601String(),
        'playbackSpeed': (profileRes['playback_speed'] as num? ?? 1.0).toDouble(),
        'preferredSource': profileRes['preferred_source'] as String? ?? 'preferLocal',
        'defaultShuffle': profileRes['default_shuffle'] as bool? ?? false,
        'defaultRepeat': profileRes['default_repeat'] as String? ?? 'off',
        'backgroundPlayback': profileRes['background_playback'] as bool? ?? true,
        'mediaNotification': profileRes['media_notification'] as bool? ?? true,
        'lockScreenControls': profileRes['lock_screen_controls'] as bool? ?? true,
        'gaplessPlayback': profileRes['gapless_playback'] as bool? ?? true,
        'crossfade': profileRes['crossfade'] as bool? ?? false,
        'lastScanTime': profileRes['last_scan_time'] as String?,
      });
      // Invalidate profile controller to load new details
      _ref.invalidate(profileProvider);
    }

    // B. Favorites (liked_songs)
    final favsRes = await client.from('liked_songs').select().eq('user_id', userId);
    final favsBox = Hive.box<TrackHiveModel>(HiveBoxes.favorites);
    await favsBox.clear();
    for (final f in favsRes as List) {
      final trackId = f['track_id'] as String;
      if (pendingDeletedFavIds.contains(trackId)) continue;
      final track = Track(
        id: trackId,
        title: f['title'] as String,
        artist: f['artist'] as String,
        imageUrl: f['image_url'] as String? ?? '',
        duration: '3:00',
        filePath: f['file_path'] as String?,
      );
      await favsBox.put(track.id, TrackHiveModel.fromTrack(track));
    }

    // C. Playlists & Tracks
    final playlistsRes = await client.from('playlists').select().eq('user_id', userId);
    final playlistTracksRes = await client
        .from('playlist_tracks')
        .select()
        .eq('user_id', userId)
        .order('position', ascending: true);
    final playlistsBox = Hive.box<PlaylistHiveModel>(HiveBoxes.playlists);
    await playlistsBox.clear();
    for (final p in playlistsRes as List) {
      final pId = p['id'] as String;
      if (pendingDeletedPlaylistIds.contains(pId)) continue;
      final songs = (playlistTracksRes as List)
          .where((s) => s['playlist_id'] == pId && !pendingRemovedPlaylistSongs.contains('${pId}_${s['track_id']}'))
          .map((s) => TrackHiveModel(
                id: s['track_id'] as String,
                title: s['title'] as String,
                artist: s['artist'] as String,
                imageUrl: s['image_url'] as String? ?? '',
                duration: '3:00',
                filePath: s['file_path'] as String?,
              ))
          .toList();

      final playlist = PlaylistHiveModel(
        id: pId,
        name: p['name'] as String,
        tracks: songs,
        createdAt: DateTime.parse(p['created_at'] as String),
        lastModified: DateTime.parse(p['last_modified'] as String),
      );
      await playlistsBox.put(pId, playlist);
    }

    // D. History
    final historyRes = await client.from('history').select().eq('user_id', userId).order('played_at', ascending: false).limit(100);
    final historyBox = Hive.box<HistoryEntry>(HiveBoxes.recentlyPlayed);
    await historyBox.clear();
    for (int i = 0; i < (historyRes as List).length; i++) {
      final h = historyRes[i];
      final entry = HistoryEntry(
        track: TrackHiveModel(
          id: h['track_id'] as String,
          title: h['title'] as String,
          artist: h['artist'] as String,
          imageUrl: h['image_url'] as String? ?? '',
          duration: h['duration'] as String? ?? '3:00',
          filePath: h['file_path'] as String?,
        ),
        playedAt: h['played_at'] != null ? DateTime.tryParse(h['played_at'] as String) ?? DateTime.now() : DateTime.now(),
      );
      await historyBox.put(i, entry);
    }

    // E. Most Played
    final mostPlayedRes = await client.from('most_played').select().eq('user_id', userId);
    final mostPlayedBox = Hive.box<int>(HiveBoxes.mostPlayed);
    await mostPlayedBox.clear();
    for (final m in mostPlayedRes as List) {
      await mostPlayedBox.put(m['track_id'] as String, m['count'] as int);
    }

    // F. Search History
    final searchRes = await client.from('search_history').select().eq('user_id', userId).order('timestamp', ascending: false).limit(20);
    final searchBox = Hive.box<String>(HiveBoxes.searchHistory);
    await searchBox.clear();
    for (final s in searchRes as List) {
      await searchBox.add(s['query'] as String);
    }

    // Invalidate state providers
    final now = DateTime.now();
    _lastSyncTime = now;
    if (Hive.isBoxOpen(HiveBoxes.preferences)) {
      await Hive.box<dynamic>(HiveBoxes.preferences).put(PreferenceKeys.lastSyncTimestamp, now.toIso8601String());
    }
    _ref.read(syncStateProvider.notifier).setSuccess(now);

    _ref.invalidate(songsProvider);
    _ref.invalidate(playlistsProvider);
    _ref.invalidate(favoritesProvider);
    _ref.invalidate(recentlyPlayedProvider);
    _ref.invalidate(searchHistoryProvider);
  }
}

final syncManagerProvider = Provider<SyncManager>((ref) {
  final manager = SyncManager(ref);
  ref.onDispose(() => manager.dispose());
  return manager;
});
