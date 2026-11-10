import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../audio/providers.dart';
import '../audio/playback_state.dart';
import '../../features/library/providers/library_providers.dart';
import '../../core/storage/adapters/history_entry.dart';
import '../../core/storage/adapters/playlist_hive_model.dart';
import '../../shared/models/track.dart';

final widgetSyncServiceProvider = Provider<MieeWidgetSyncService>((ref) {
  final service = MieeWidgetSyncService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Bridges Flutter application state with native Android Homescreen Widgets.
class MieeWidgetSyncService {
  static const _channel = MethodChannel('com.example.miee/widget');
  final Ref _ref;
  GoRouter? _router;
  DateTime _lastPositionPush = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastTrackId;
  bool _lastPlayingState = false;

  MieeWidgetSyncService(this._ref) {
    _channel.setMethodCallHandler(_handleMethodCall);
    _initListeners();
    // Initial sync
    _syncAll();
  }

  void attachRouter(GoRouter router) {
    _router = router;
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    debugPrint('[MieeWidgetSyncService] Received native call: ${call.method}');
    switch (call.method) {
      case 'onPlayTrack':
        final trackId = call.arguments as String?;
        if (trackId != null && trackId.isNotEmpty) {
          _playTrackById(trackId);
        }
        break;
      case 'onOpenPlaylist':
        final playlistId = call.arguments as String?;
        if (playlistId != null && playlistId.isNotEmpty) {
          unawaited(_router?.push('/playlist/$playlistId'));
        }
        break;
      case 'onNavigate':
        final route = call.arguments as String?;
        if (route != null && route.isNotEmpty) {
          final target = _normalizeRoute(route);
          unawaited(_router?.push(target));
        }
        break;
      case 'onToggleFavorite':
        final track = _ref.read(playerControllerProvider).currentTrack;
        if (track is Track) {
          final favNotifier = _ref.read(favoritesProvider.notifier);
          if (favNotifier.isFavorite(track.id)) {
            unawaited(favNotifier.removeFavorite(track.id));
          } else {
            unawaited(favNotifier.addFavorite(track));
          }
        }
        break;
    }
  }

  String _normalizeRoute(String route) {
    switch (route) {
      case '/now-playing':
        return '/player';
      case '/favorites':
        return '/liked-songs';
      case '/recently-played':
        return '/home';
      case '/create-playlist':
        return '/playlists';
      default:
        return route;
    }
  }

  void _playTrackById(String trackId) {
    // 1. Search recently played
    final recent = _ref.read(recentlyPlayedProvider).asData?.value;
    if (recent != null && recent.isNotEmpty) {
      final trackList = recent.map((e) => e.track.toTrack()).toList();
      for (final track in trackList) {
        if (track.id == trackId) {
          _ref.read(playerControllerProvider.notifier).selectTrack(track, trackList, playingFrom: 'Recently Played');
          return;
        }
      }
    }

    // 2. Search favorites
    final favs = _ref.read(favoritesProvider);
    if (favs.isNotEmpty) {
      for (final track in favs) {
        if (track.id == trackId) {
          _ref.read(playerControllerProvider.notifier).selectTrack(track, favs, playingFrom: 'Favorites');
          return;
        }
      }
    }
  }

  void _initListeners() {
    // 1. Playback state updates
    _ref.listen<PlaybackState>(playerControllerProvider, (prev, next) {
      _syncNowPlaying(next);
    });

    // 2. Favorites updates
    _ref.listen<List<Track>>(favoritesProvider, (prev, next) {
      _syncFavourites(next);
    });

    // 3. Playlists updates
    _ref.listen<List<PlaylistHiveModel>>(userPlaylistsProvider, (prev, next) {
      _syncPlaylists(next);
    });

    // 4. Recently played updates
    _ref.listen<AsyncValue<List<HistoryEntry>>>(recentlyPlayedProvider, (prev, next) {
      if (next.asData?.value != null) {
        _syncRecentlyPlayed(next.asData!.value);
      }
    });
  }

  void _syncAll() {
    final state = _ref.read(playerControllerProvider);
    _syncNowPlaying(state, force: true);

    final favs = _ref.read(favoritesProvider);
    _syncFavourites(favs);

    final playlists = _ref.read(userPlaylistsProvider);
    _syncPlaylists(playlists);

    final recent = _ref.read(recentlyPlayedProvider).asData?.value;
    if (recent != null) {
      _syncRecentlyPlayed(recent);
    }
  }

  void _syncNowPlaying(PlaybackState state, {bool force = false}) {
    final track = state.currentTrack;
    final isPlaying = state.status == PlaybackStatus.playing;
    final durMs = state.duration.inMilliseconds;
    final posMs = state.position.inMilliseconds;
    final progress = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;

    // Rate-limit progress events during playback to avoid Android Binder saturation
    final now = DateTime.now();
    final isTrackSame = track?.id == _lastTrackId;
    final isPlayStateSame = isPlaying == _lastPlayingState;

    if (!force && isTrackSame && isPlayStateSame && now.difference(_lastPositionPush).inSeconds < 2) {
      return;
    }

    _lastPositionPush = now;
    _lastTrackId = track?.id;
    _lastPlayingState = isPlaying;

    final isFav = track != null
        ? _ref.read(favoritesProvider.notifier).isFavorite(track.id)
        : false;

    _channel.invokeMethod('updateNowPlaying', {
      'title': track?.title ?? 'Miee Music',
      'artist': track?.artist ?? 'Ready to play',
      'artworkPath': track?.filePath ?? '',
      'artworkUrl': track?.imageUrl ?? '',
      'isPlaying': isPlaying,
      'isFavorited': isFav,
      'progress': progress,
      'positionMs': posMs,
      'durationMs': durMs,
    }).catchError((Object e) {
      debugPrint('[MieeWidgetSyncService] updateNowPlaying error: $e');
    });
  }

  void _syncFavourites(List<Track> favs) {
    final top4 = favs.take(4).map((t) => {
      'title': t.title,
      'artist': t.artist,
      'trackId': t.id,
      'artworkPath': t.filePath,
      'artworkUrl': t.imageUrl,
    }).toList();

    _channel.invokeMethod('updateFavourites', {
      'itemsJson': jsonEncode(top4),
    }).catchError((Object e) {
      debugPrint('[MieeWidgetSyncService] updateFavourites error: $e');
    });
  }

  void _syncRecentlyPlayed(List<HistoryEntry> entries) {
    final top4 = entries.take(4).map((e) => {
      'title': e.track.title,
      'artist': e.track.artist,
      'trackId': e.track.id,
      'artworkPath': e.track.filePath ?? '',
      'artworkUrl': e.track.imageUrl,
    }).toList();

    _channel.invokeMethod('updateRecentlyPlayed', {
      'itemsJson': jsonEncode(top4),
    }).catchError((Object e) {
      debugPrint('[MieeWidgetSyncService] updateRecentlyPlayed error: $e');
    });
  }

  void _syncPlaylists(List<PlaylistHiveModel> playlists) {
    final top3 = playlists.take(3).map((p) {
      final firstTrack = p.tracks.isNotEmpty ? p.tracks.first : null;
      return {
        'title': p.name,
        'trackCount': p.tracks.length,
        'playlistId': p.id,
        'artworkPath': p.customCoverPath ?? firstTrack?.filePath ?? '',
        'artworkUrl': firstTrack?.imageUrl ?? '',
      };
    }).toList();

    _channel.invokeMethod('updatePlaylists', {
      'itemsJson': jsonEncode(top3),
    }).catchError((Object e) {
      debugPrint('[MieeWidgetSyncService] updatePlaylists error: $e');
    });
  }
}
