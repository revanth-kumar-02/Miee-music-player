import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/library/data/favorites_repository.dart';
import '../../features/library/data/playlists_repository.dart';
import '../../features/library/data/playback_history_repository.dart';
import '../../features/library/data/most_played_repository.dart';
import '../../features/library/data/search_history_repository.dart';
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
class SyncManager {
  final Ref _ref;
  final OfflineOperationQueue _operationQueue;
  final NetworkMonitor _networkMonitor;
  late final StreamSubscription<bool> _networkSubscription;

  SyncManager(this._ref)
      : _operationQueue = OfflineOperationQueue(Hive.box(HiveBoxes.offlineQueue)),
        _networkMonitor = _ref.read(networkMonitorProvider) {
    // Automatically trigger sync when network returns
    _networkSubscription = _networkMonitor.onConnectivityChanged.listen((isOnline) {
      if (isOnline) {
        triggerSync();
      }
    });
  }

  void dispose() {
    _networkSubscription.cancel();
  }

  OfflineOperationQueue get queue => _operationQueue;

  /// Queues an operation locally if offline, otherwise replays instantly.
  Future<void> queueOperation(OfflineOperation op) async {
    await _operationQueue.addOperation(op);
    // Trigger background sync in the background
    triggerSync();
  }

  /// Replays all queued offline operations to Supabase.
  Future<void> replayOfflineQueue() async {
    final authState = _ref.read(authControllerProvider);
    final isOnline = await _networkMonitor.isConnected;

    if (!isOnline || !SupabaseConfig.hasActiveSupabase || authState.user == null) {
      return;
    }

    final client = Supabase.instance.client;
    final operations = _operationQueue.getOperations();

    for (final op in operations) {
      try {
        final payload = op.payload;
        final userId = authState.user!.id;

        switch (op.type) {
          case 'favorite_add':
            await client.from('favorites').upsert({
              'id': payload['id'],
              'user_id': userId,
              'title': payload['title'],
              'artist': payload['artist'],
              'image_url': payload['imageUrl'],
              'duration': payload['duration'],
              'file_path': payload['filePath'],
              'is_youtube': payload['isYoutube'] ?? false,
              'updated_at': op.timestamp.toIso8601String(),
            });
            break;

          case 'favorite_remove':
            await client
                .from('favorites')
                .delete()
                .eq('id', payload['id'])
                .eq('user_id', userId);
            break;

          case 'playlist_create':
            await client.from('playlists').upsert({
              'id': payload['id'],
              'user_id': userId,
              'name': payload['name'],
              'created_at': payload['createdAt'],
              'last_modified': payload['lastModified'],
              'updated_at': op.timestamp.toIso8601String(),
            });
            break;

          case 'playlist_delete':
            await client
                .from('playlists')
                .delete()
                .eq('id', payload['id'])
                .eq('user_id', userId);
            await client
                .from('playlist_songs')
                .delete()
                .eq('playlist_id', payload['id'])
                .eq('user_id', userId);
            break;

          case 'playlist_rename':
            await client.from('playlists').upsert({
              'id': payload['id'],
              'user_id': userId,
              'name': payload['name'],
              'last_modified': payload['lastModified'],
              'updated_at': op.timestamp.toIso8601String(),
            });
            break;

          case 'playlist_song_add':
            final song = payload['track'];
            await client.from('playlist_songs').upsert({
              'playlist_id': payload['playlistId'],
              'track_id': song['id'],
              'user_id': userId,
              'title': song['title'],
              'artist': song['artist'],
              'image_url': song['imageUrl'],
              'duration': song['duration'],
              'file_path': song['filePath'],
              'is_youtube': song['isYoutube'] ?? false,
              'updated_at': op.timestamp.toIso8601String(),
            });
            break;

          case 'playlist_song_remove':
            await client
                .from('playlist_songs')
                .delete()
                .eq('playlist_id', payload['playlistId'])
                .eq('track_id', payload['trackId'])
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
              'created_date': payload['createdDate'],
              'last_opened': payload['lastOpened'],
              'theme_mode': payload['themeMode'],
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
            await client.from('history').insert({
              'track_id': payload['id'],
              'user_id': userId,
              'title': payload['title'],
              'artist': payload['artist'],
              'image_url': payload['imageUrl'],
              'duration': payload['duration'],
              'file_path': payload['filePath'],
              'is_youtube': payload['isYoutube'] ?? false,
              'played_at': payload['playedAt'],
            });
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
            await client.from('search_history').insert({
              'user_id': userId,
              'query': payload['query'],
              'timestamp': payload['timestamp'],
            });
            break;

          case 'search_remove':
            await client
                .from('search_history')
                .delete()
                .eq('query', payload['query'])
                .eq('user_id', userId);
            break;
        }

        // Remove successfully replayed operation
        await _operationQueue.removeOperation(op.id);
      } catch (e) {
        debugPrint('Failed to replay offline operation ${op.id} (${op.type}): $e');
        // Stop replaying this queue batch to preserve chronological sequencing
        break;
      }
    }
  }

  /// Triggers background offline-first synchronization flow.
  Future<void> triggerSync() async {
    final syncNotifier = _ref.read(syncStateProvider.notifier);
    final authState = _ref.read(authControllerProvider);
    final isOnline = await _networkMonitor.isConnected;

    if (!isOnline || !SupabaseConfig.hasActiveSupabase || authState.user == null) {
      return;
    }

    syncNotifier.setSyncing();

    try {
      final client = Supabase.instance.client;
      final userId = authState.user!.id;

      // 1. Replay local changes to Cloud
      await replayOfflineQueue();

      // 2. Fetch Remote Updates from Cloud
      // A. Profile & Settings Table
      final profileRes = await client.from('profiles').select().eq('id', userId).maybeSingle();
      if (profileRes != null) {
        final localProfile = _ref.read(profileProvider);
        final remoteProfile = ProfileModel(
          displayName: profileRes['display_name'] as String,
          username: profileRes['username'] as String?,
          profilePicturePath: profileRes['profile_picture_path'] as String?,
          favoriteGenre: profileRes['favorite_genre'] as String? ?? 'Acoustic',
          favoriteArtist: profileRes['favorite_artist'] as String? ?? 'Unknown Artist',
          createdDate: DateTime.parse(profileRes['created_date'] as String),
          lastOpened: DateTime.parse(profileRes['last_opened'] as String),
          themeMode: profileRes['theme_mode'] as String? ?? 'system',
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

        final remoteTime = DateTime.parse(profileRes['updated_at'] as String? ?? profileRes['last_opened'] as String);
        final resolved = ConflictResolver.resolveLatest(
          local: localProfile,
          localTime: localProfile.lastOpened,
          remote: remoteProfile,
          remoteTime: remoteTime,
        );

        // Update local profile box synchronously
        final profileBox = Hive.box(HiveBoxes.profile);
        await profileBox.put('active_profile', {
          'displayName': resolved.displayName,
          'username': resolved.username,
          'profilePicturePath': resolved.profilePicturePath,
          'favoriteGenre': resolved.favoriteGenre,
          'favoriteArtist': resolved.favoriteArtist,
          'createdDate': resolved.createdDate.toIso8601String(),
          'lastOpened': resolved.lastOpened.toIso8601String(),
          'themeMode': resolved.themeMode,
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
        _ref.read(profileProvider.notifier).updateProfile(
              displayName: resolved.displayName,
              username: resolved.username,
              profilePicturePath: resolved.profilePicturePath,
              favoriteGenre: resolved.favoriteGenre,
              favoriteArtist: resolved.favoriteArtist,
            );
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
          'created_date': local.createdDate.toIso8601String(),
          'last_opened': local.lastOpened.toIso8601String(),
          'theme_mode': local.themeMode,
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
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      // B. Favorites Table
      final favsRes = await client.from('favorites').select().eq('user_id', userId);
      final List<Track> remoteFavs = (favsRes as List).map((f) {
        return Track(
          id: f['id'] as String,
          title: f['title'] as String,
          artist: f['artist'] as String,
          imageUrl: f['image_url'] as String,
          duration: f['duration'] as String,
          filePath: f['file_path'] as String?,
        );
      }).toList();

      final favsBox = Hive.box<TrackHiveModel>(HiveBoxes.favorites);
      final localFavs = favsBox.values.map((t) => t.toTrack()).toList();

      final mergedFavs = ConflictResolver.mergeLists<Track, String>(
        local: localFavs,
        remote: remoteFavs,
        idSelector: (t) => t.id,
        mergeFn: (l, r) => l, // Keep either
      );

      // Save resolved favorites to Hive
      await favsBox.clear();
      for (final track in mergedFavs) {
        await favsBox.put(track.id, TrackHiveModel.fromTrack(track));
      }

      // C. Playlists & Playlist Songs
      final playlistsRes = await client.from('playlists').select().eq('user_id', userId);
      final playlistSongsRes = await client.from('playlist_songs').select().eq('user_id', userId);

      final playlistsBox = Hive.box<PlaylistHiveModel>(HiveBoxes.playlists);
      final localPlaylists = playlistsBox.values.toList();

      final List<PlaylistHiveModel> remotePlaylists = (playlistsRes as List).map((p) {
        final pId = p['id'] as String;
        final songs = (playlistSongsRes as List)
            .where((s) => s['playlist_id'] == pId)
            .map((s) => TrackHiveModel(
                  id: s['track_id'] as String,
                  title: s['title'] as String,
                  artist: s['artist'] as String,
                  imageUrl: s['image_url'] as String,
                  duration: s['duration'] as String,
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
            imageUrl: h['image_url'] as String,
            duration: h['duration'] as String,
            filePath: h['file_path'] as String?,
          ),
          playedAt: DateTime.parse(h['played_at'] as String),
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
      syncNotifier.setSuccess(DateTime.now());

      // Invalidate UI state providers so list screens redraw instantly
      _ref.invalidate(songsProvider);
      _ref.invalidate(playlistsProvider);
      _ref.invalidate(favoritesProvider);
      _ref.invalidate(recentlyPlayedProvider);
      _ref.invalidate(searchHistoryProvider);

    } catch (e) {
      debugPrint('Sync failed: $e');
      syncNotifier.setError(e.toString());
    }
  }

  /// Downloads all remote data from Supabase, completely replacing local Cache (used on sign-in).
  Future<void> downloadAllRemoteData() async {
    final authState = _ref.read(authControllerProvider);
    final isOnline = await _networkMonitor.isConnected;

    if (!isOnline || !SupabaseConfig.hasActiveSupabase || authState.user == null) {
      return;
    }

    final client = Supabase.instance.client;
    final userId = authState.user!.id;

    // A. Profile
    final profileRes = await client.from('profiles').select().eq('id', userId).maybeSingle();
    if (profileRes != null) {
      final profileBox = Hive.box(HiveBoxes.profile);
      await profileBox.put('active_profile', {
        'displayName': profileRes['display_name'] as String? ?? 'Miee User',
        'username': profileRes['username'] as String?,
        'profilePicturePath': profileRes['profile_picture_path'] as String?,
        'favoriteGenre': profileRes['favorite_genre'] as String? ?? 'Acoustic',
        'favoriteArtist': profileRes['favorite_artist'] as String? ?? 'Unknown Artist',
        'createdDate': profileRes['created_date'] as String,
        'lastOpened': profileRes['last_opened'] as String,
        'themeMode': profileRes['theme_mode'] as String? ?? 'system',
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

    // B. Favorites
    final favsRes = await client.from('favorites').select().eq('user_id', userId);
    final favsBox = Hive.box<TrackHiveModel>(HiveBoxes.favorites);
    await favsBox.clear();
    for (final f in favsRes as List) {
      final track = Track(
        id: f['id'] as String,
        title: f['title'] as String,
        artist: f['artist'] as String,
        imageUrl: f['image_url'] as String,
        duration: f['duration'] as String,
        filePath: f['file_path'] as String?,
      );
      await favsBox.put(track.id, TrackHiveModel.fromTrack(track));
    }

    // C. Playlists & Songs
    final playlistsRes = await client.from('playlists').select().eq('user_id', userId);
    final playlistSongsRes = await client.from('playlist_songs').select().eq('user_id', userId);
    final playlistsBox = Hive.box<PlaylistHiveModel>(HiveBoxes.playlists);
    await playlistsBox.clear();
    for (final p in playlistsRes as List) {
      final pId = p['id'] as String;
      final songs = (playlistSongsRes as List)
          .where((s) => s['playlist_id'] == pId)
          .map((s) => TrackHiveModel(
                id: s['track_id'] as String,
                title: s['title'] as String,
                artist: s['artist'] as String,
                imageUrl: s['image_url'] as String,
                duration: s['duration'] as String,
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
          imageUrl: h['image_url'] as String,
          duration: h['duration'] as String,
          filePath: h['file_path'] as String?,
        ),
        playedAt: DateTime.parse(h['played_at'] as String),
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
