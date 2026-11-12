import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/adapters/history_entry.dart';
import '../../core/storage/adapters/playlist_hive_model.dart';
import '../../features/artwork/data/artwork_cache.dart';
import '../../features/artwork/data/artwork_resolver_impl.dart';
import '../../features/artwork/domain/artwork_query.dart';
import '../../features/artwork/presentation/artwork_providers.dart';
import '../../features/library/providers/library_providers.dart';
import '../../shared/models/music_item.dart';
import '../../shared/models/track.dart';
import '../audio/playback_state.dart';
import '../audio/providers.dart';

final widgetSyncServiceProvider = Provider<MieeWidgetSyncService>((ref) {
  final service = MieeWidgetSyncService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Normalized artwork payload fields sent to the native Android widget bridge.
class WidgetArtworkFields {
  /// Local image file path on disk (never an audio file path).
  final String artworkPath;

  /// Remote HTTP/HTTPS image URL (never a local file path).
  final String artworkUrl;

  /// Local audio file path for native MediaMetadataRetriever fallback when
  /// [artworkPath] is empty or no longer exists.
  final String audioFilePath;

  const WidgetArtworkFields({
    required this.artworkPath,
    required this.artworkUrl,
    required this.audioFilePath,
  });

  String get signature => '$artworkPath|$artworkUrl|$audioFilePath';
}

/// Derives clean [WidgetArtworkFields] from any [MusicItem] without confusing
/// audio file paths (`track.filePath`) with image file paths (`track.imageUrl`).
WidgetArtworkFields extractWidgetArtworkFields({
  required String trackId,
  required String imageUrl,
  required String filePath,
  required bool isYoutube,
  String? sourceId,
  String? customCoverPath,
  String? resolvedArtwork,
}) {
  String artworkPath = '';
  String artworkUrl = '';

  final candidates = <String>[
    if (customCoverPath != null && customCoverPath.trim().isNotEmpty)
      customCoverPath.trim(),
    if (resolvedArtwork != null && resolvedArtwork.trim().isNotEmpty)
      resolvedArtwork.trim(),
    if (imageUrl.trim().isNotEmpty) imageUrl.trim(),
  ];

  for (final raw in candidates) {
    final lower = raw.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      if (artworkUrl.isEmpty) artworkUrl = raw;
    } else {
      final cleanPath = _stripFileUri(raw);
      if (cleanPath.isNotEmpty && artworkPath.isEmpty) {
        artworkPath = cleanPath;
      }
    }
  }

  // Fallback for YouTube tracks that have not yet populated imageUrl.
  if (isYoutube && artworkUrl.isEmpty) {
    final vid = _extractYouTubeId(sourceId ?? trackId);
    if (vid != null) {
      artworkUrl = 'https://i.ytimg.com/vi/$vid/hqdefault.jpg';
    }
  }

  // Only pass audioFilePath for local tracks so native Android can extract
  // embedded album art if artworkPath is missing or purged.
  String audioFilePath = '';
  if (!isYoutube && filePath.trim().isNotEmpty) {
    final trimmed = filePath.trim();
    final lower = trimmed.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      audioFilePath = _stripFileUri(trimmed);
    }
  }

  return WidgetArtworkFields(
    artworkPath: artworkPath,
    artworkUrl: artworkUrl,
    audioFilePath: audioFilePath,
  );
}

String _stripFileUri(String raw) {
  if (raw.startsWith('file://')) {
    try {
      return Uri.parse(raw).toFilePath();
    } catch (_) {
      return raw.replaceFirst('file://', '');
    }
  }
  return raw;
}

String? _extractYouTubeId(String rawId) {
  final clean = rawId.replaceFirst('youtube_', '').trim();
  if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(clean)) {
    return clean;
  }
  return null;
}

/// Bridges Flutter application state with native Android Homescreen Widgets.
class MieeWidgetSyncService {
  static const _channel = MethodChannel('com.example.miee/widget');
  final Ref? _ref;
  final MethodChannel _methodChannel;
  final ArtworkResolver? _artworkResolverOverride;
  final bool Function(String path)? _fileExistsOverride;
  final bool _autoListen;

  GoRouter? _router;
  DateTime _lastPositionPush = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastTrackId;
  bool _lastPlayingState = false;
  String _lastArtworkSignature = '';
  int _artworkResolveEpoch = 0;

  MieeWidgetSyncService(
    this._ref, {
    MethodChannel? channel,
    ArtworkResolver? artworkResolver,
    bool Function(String path)? fileExistsProvider,
    bool autoListen = true,
  })  : _methodChannel = channel ?? _channel,
        _artworkResolverOverride = artworkResolver,
        _fileExistsOverride = fileExistsProvider,
        _autoListen = autoListen {
    _methodChannel.setMethodCallHandler(_handleMethodCall);
    if (_autoListen) {
      _initListeners();
      _syncAll();
    }
  }

  void attachRouter(GoRouter router) {
    _router = router;
  }

  void dispose() {
    _artworkResolveEpoch++;
    _methodChannel.setMethodCallHandler(null);
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
        final ref = _ref;
        if (ref == null) break;
        final track = ref.read(playerControllerProvider).currentTrack;
        if (track is Track) {
          final favNotifier = ref.read(favoritesProvider.notifier);
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
    final ref = _ref;
    if (ref == null) return;
    final recent = ref.read(recentlyPlayedProvider).asData?.value;
    if (recent != null && recent.isNotEmpty) {
      final trackList = recent.map((e) => e.track.toTrack()).toList();
      for (final track in trackList) {
        if (track.id == trackId) {
          ref
              .read(playerControllerProvider.notifier)
              .selectTrack(track, trackList, playingFrom: 'Recently Played');
          return;
        }
      }
    }

    final favs = ref.read(favoritesProvider);
    if (favs.isNotEmpty) {
      for (final track in favs) {
        if (track.id == trackId) {
          ref
              .read(playerControllerProvider.notifier)
              .selectTrack(track, favs, playingFrom: 'Favorites');
          return;
        }
      }
    }
  }

  void _initListeners() {
    final ref = _ref;
    if (ref == null) return;
    ref.listen<PlaybackState>(playerControllerProvider, (prev, next) {
      syncNowPlayingState(next);
    });

    ref.listen<List<Track>>(favoritesProvider, (prev, next) {
      syncFavourites(next);
    });

    ref.listen<List<PlaylistHiveModel>>(userPlaylistsProvider, (prev, next) {
      syncPlaylists(next);
    });

    ref.listen<AsyncValue<List<HistoryEntry>>>(recentlyPlayedProvider,
        (prev, next) {
      if (next.asData?.value != null) {
        syncRecentlyPlayed(next.asData!.value);
      }
    });
  }

  void _syncAll() {
    final ref = _ref;
    if (ref == null) return;
    final state = ref.read(playerControllerProvider);
    syncNowPlayingState(state, force: true);

    final favs = ref.read(favoritesProvider);
    syncFavourites(favs);

    final playlists = ref.read(userPlaylistsProvider);
    syncPlaylists(playlists);

    final recent = ref.read(recentlyPlayedProvider).asData?.value;
    if (recent != null) {
      syncRecentlyPlayed(recent);
    }
  }

  @visibleForTesting
  void syncNowPlayingState(
    PlaybackState state, {
    bool force = false,
    bool isFavoriteOverride = false,
  }) {
    final track = state.currentTrack;
    final isPlaying = state.status == PlaybackStatus.playing;
    final durMs = state.duration.inMilliseconds;
    final posMs = state.position.inMilliseconds;
    final progress = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;

    final fields = track != null
        ? extractWidgetArtworkFields(
            trackId: track.id,
            imageUrl: track.imageUrl,
            filePath: track.filePath,
            isYoutube: track.isYoutube,
            sourceId: track is Track ? track.sourceId : null,
          )
        : const WidgetArtworkFields(
            artworkPath: '',
            artworkUrl: '',
            audioFilePath: '',
          );

    final now = DateTime.now();
    final isTrackSame = track?.id == _lastTrackId;
    final isPlayStateSame = isPlaying == _lastPlayingState;
    final isArtworkSame = fields.signature == _lastArtworkSignature;

    if (!force &&
        isTrackSame &&
        isPlayStateSame &&
        isArtworkSame &&
        now.difference(_lastPositionPush).inSeconds < 2) {
      return;
    }

    final trackChanged = !isTrackSame;
    _lastPositionPush = now;
    _lastTrackId = track?.id;
    _lastPlayingState = isPlaying;
    _lastArtworkSignature = fields.signature;

    bool isFav = isFavoriteOverride;
    final ref = _ref;
    if (!isFavoriteOverride && track != null && _autoListen && ref != null) {
      isFav = ref.read(favoritesProvider.notifier).isFavorite(track.id);
    }

    _pushNowPlayingPayload(
      trackId: track?.id ?? '',
      title: track?.title ?? 'Miee Music',
      artist: track?.artist ?? 'Ready to play',
      fields: fields,
      isPlaying: isPlaying,
      isFav: isFav,
      progress: progress,
      posMs: posMs,
      durMs: durMs,
    );

    if (track != null && (trackChanged || force || _needsArtworkEnrichment(fields))) {
      unawaited(
        _resolveAndRefreshNowPlayingArtwork(
          track: track,
          initialFields: fields,
          isPlaying: isPlaying,
          isFav: isFav,
          progress: progress,
          posMs: posMs,
          durMs: durMs,
        ),
      );
    }
  }

  bool _needsArtworkEnrichment(WidgetArtworkFields fields) {
    if (fields.artworkPath.isNotEmpty) {
      final exists = _fileExistsOverride?.call(fields.artworkPath) ??
          File(fields.artworkPath).existsSync();
      if (exists) return false;
    }
    return true;
  }

  Future<void> _resolveAndRefreshNowPlayingArtwork({
    required MusicItem track,
    required WidgetArtworkFields initialFields,
    required bool isPlaying,
    required bool isFav,
    required double progress,
    required int posMs,
    required int durMs,
  }) async {
    final epoch = ++_artworkResolveEpoch;
    try {
      final resolver =
          _artworkResolverOverride ?? _ref?.read(artworkResolverProvider);
      if (resolver == null) return;
      final query = ArtworkQuery.fromMusicItem(track);
      final resolved = await resolver.resolve(query);

      // Guard against stale async completion after rapid track switches.
      if (epoch != _artworkResolveEpoch || _lastTrackId != track.id) {
        return;
      }

      final hasLocalCache = ArtworkCache.hasValidLocalFile(resolved.localCachedPath);
      final preferredArt = hasLocalCache
          ? resolved.localCachedPath!
          : resolved.imageUrl.trim();
      if (preferredArt.isEmpty) return;

      final enrichedFields = extractWidgetArtworkFields(
        trackId: track.id,
        imageUrl: resolved.imageUrl.trim().isNotEmpty
            ? resolved.imageUrl.trim()
            : track.imageUrl,
        filePath: track.filePath,
        isYoutube: track.isYoutube,
        sourceId: track is Track ? track.sourceId : null,
        resolvedArtwork: preferredArt,
      );

      if (enrichedFields.signature == initialFields.signature) return;

      _lastArtworkSignature = enrichedFields.signature;
      _pushNowPlayingPayload(
        trackId: track.id,
        title: track.title,
        artist: track.artist,
        fields: enrichedFields,
        isPlaying: isPlaying,
        isFav: isFav,
        progress: progress,
        posMs: posMs,
        durMs: durMs,
      );
    } catch (e) {
      debugPrint('[MieeWidgetSyncService] Artwork resolution error: $e');
    }
  }

  void _pushNowPlayingPayload({
    required String trackId,
    required String title,
    required String artist,
    required WidgetArtworkFields fields,
    required bool isPlaying,
    required bool isFav,
    required double progress,
    required int posMs,
    required int durMs,
  }) {
    _methodChannel.invokeMethod('updateNowPlaying', {
      'trackId': trackId,
      'title': title,
      'artist': artist,
      'artworkPath': fields.artworkPath,
      'artworkUrl': fields.artworkUrl,
      'audioFilePath': fields.audioFilePath,
      'isPlaying': isPlaying,
      'isFavorited': isFav,
      'progress': progress,
      'positionMs': posMs,
      'durationMs': durMs,
    }).catchError((Object e) {
      debugPrint('[MieeWidgetSyncService] updateNowPlaying error: $e');
    });
  }

  @visibleForTesting
  void syncFavourites(List<Track> favs) {
    final top4 = favs.take(4).map((t) {
      final fields = extractWidgetArtworkFields(
        trackId: t.id,
        imageUrl: t.imageUrl,
        filePath: t.filePath,
        isYoutube: t.isYoutube,
        sourceId: t.sourceId,
      );
      return {
        'title': t.title,
        'artist': t.artist,
        'trackId': t.id,
        'artworkPath': fields.artworkPath,
        'artworkUrl': fields.artworkUrl,
        'audioFilePath': fields.audioFilePath,
      };
    }).toList();

    _methodChannel.invokeMethod('updateFavourites', {
      'itemsJson': jsonEncode(top4),
    }).catchError((Object e) {
      debugPrint('[MieeWidgetSyncService] updateFavourites error: $e');
    });
  }

  @visibleForTesting
  void syncRecentlyPlayed(List<HistoryEntry> entries) {
    final top4 = entries.take(4).map((e) {
      final t = e.track;
      final isYt = t.id.startsWith('youtube_') ||
          t.id.startsWith('wm_') ||
          t.sourceProvider == 'youtube' ||
          (t.filePath?.contains('youtube.com') ?? false) ||
          (t.filePath?.startsWith('http') ?? false);
      final fields = extractWidgetArtworkFields(
        trackId: t.id,
        imageUrl: t.imageUrl,
        filePath: t.filePath ?? '',
        isYoutube: isYt,
        sourceId: t.sourceId,
      );
      return {
        'title': t.title,
        'artist': t.artist,
        'trackId': t.id,
        'artworkPath': fields.artworkPath,
        'artworkUrl': fields.artworkUrl,
        'audioFilePath': fields.audioFilePath,
      };
    }).toList();

    _methodChannel.invokeMethod('updateRecentlyPlayed', {
      'itemsJson': jsonEncode(top4),
    }).catchError((Object e) {
      debugPrint('[MieeWidgetSyncService] updateRecentlyPlayed error: $e');
    });
  }

  @visibleForTesting
  void syncPlaylists(List<PlaylistHiveModel> playlists) {
    final top3 = playlists.take(3).map((p) {
      final firstTrack = p.tracks.isNotEmpty ? p.tracks.first : null;
      final isYt = firstTrack != null &&
          (firstTrack.id.startsWith('youtube_') ||
              firstTrack.id.startsWith('wm_') ||
              firstTrack.sourceProvider == 'youtube' ||
              (firstTrack.filePath?.contains('youtube.com') ?? false) ||
              (firstTrack.filePath?.startsWith('http') ?? false));
      final fields = extractWidgetArtworkFields(
        trackId: firstTrack?.id ?? p.id,
        imageUrl: firstTrack?.imageUrl ?? '',
        filePath: firstTrack?.filePath ?? '',
        isYoutube: isYt,
        sourceId: firstTrack?.sourceId,
        customCoverPath: p.customCoverPath,
      );
      return {
        'title': p.name,
        'trackCount': p.tracks.length,
        'playlistId': p.id,
        'artworkPath': fields.artworkPath,
        'artworkUrl': fields.artworkUrl,
        'audioFilePath': fields.audioFilePath,
      };
    }).toList();

    _methodChannel.invokeMethod('updatePlaylists', {
      'itemsJson': jsonEncode(top3),
    }).catchError((Object e) {
      debugPrint('[MieeWidgetSyncService] updatePlaylists error: $e');
    });
  }
}
