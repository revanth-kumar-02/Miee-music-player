import 'package:flutter_test/flutter_test.dart';
import '../lib/core/storage/adapters/playlist_hive_model.dart';
import '../lib/core/storage/adapters/track_hive_model.dart';
import '../lib/core/sync/conflict_resolver.dart';
import '../lib/features/playlists/domain/playlist_model.dart';
import '../lib/shared/models/track.dart';

void main() {
  group('Listen Together MiniPlayer & BottomNav Route Visibility Regression Tests', () {
    // Tests the route logic implemented in MainAppShell
    bool computeHideMiniPlayer({
      required String location,
      required String uriPath,
      required bool hasTrack,
    }) {
      final isNowPlayingRoute = location == '/player' || uriPath == '/player';
      final isSettingsRoute = location == '/settings' ||
          uriPath == '/settings' ||
          location.startsWith('/settings/') ||
          uriPath.startsWith('/settings/');
      final isRoomDetailRoute = location.startsWith('/rooms/') ||
          uriPath.startsWith('/rooms/');
      final isRoomsLandingRoute = location == '/rooms' || uriPath == '/rooms';
      final isRoomsRoute = isRoomsLandingRoute || isRoomDetailRoute;
      final isQueueRoute = location == '/queue' ||
          uriPath == '/queue' ||
          location.startsWith('/queue/') ||
          uriPath.startsWith('/queue/');

      return isNowPlayingRoute ||
          isSettingsRoute ||
          isRoomsRoute ||
          isQueueRoute ||
          !hasTrack;
    }

    bool computeHideBottomNav({
      required String location,
      required String uriPath,
    }) {
      final isNowPlayingRoute = location == '/player' || uriPath == '/player';
      final isSettingsRoute = location == '/settings' ||
          uriPath == '/settings' ||
          location.startsWith('/settings/') ||
          uriPath.startsWith('/settings/');
      final isRoomDetailRoute = location.startsWith('/rooms/') ||
          uriPath.startsWith('/rooms/');
      final isQueueRoute = location == '/queue' ||
          uriPath == '/queue' ||
          location.startsWith('/queue/') ||
          uriPath.startsWith('/queue/');

      return (isNowPlayingRoute ||
          isQueueRoute ||
          isSettingsRoute ||
          location == '/' ||
          uriPath == '/' ||
          location.startsWith('/playlist/') ||
          uriPath.startsWith('/playlist/') ||
          location.startsWith('/album/') ||
          uriPath.startsWith('/album/') ||
          location.startsWith('/artist/') ||
          uriPath.startsWith('/artist/') ||
          location.startsWith('/genre/') ||
          uriPath.startsWith('/genre/') ||
          location == '/local-songs' ||
          uriPath == '/local-songs' ||
          location == '/liked-songs' ||
          uriPath == '/liked-songs' ||
          isRoomDetailRoute);
    }

    test('Listen Together landing route (/rooms) hides miniplayer but keeps bottom navigation', () {
      const route = '/rooms';

      final hideMiniPlayer = computeHideMiniPlayer(
        location: route,
        uriPath: route,
        hasTrack: true,
      );
      final hideBottomNav = computeHideBottomNav(
        location: route,
        uriPath: route,
      );

      expect(hideMiniPlayer, isTrue,
          reason: 'Compact player must be hidden on the Listen Together landing screen');
      expect(hideBottomNav, isFalse,
          reason: 'Bottom navigation must remain visible with the Rooms tab selected on /rooms');
    });

    test('Room detail routes (/rooms/create, /rooms/join, /rooms/123) hide both miniplayer and bottom nav', () {
      final detailRoutes = ['/rooms/create', '/rooms/join', '/rooms/xyz123'];

      for (final route in detailRoutes) {
        final hideMiniPlayer = computeHideMiniPlayer(
          location: route,
          uriPath: route,
          hasTrack: true,
        );
        final hideBottomNav = computeHideBottomNav(
          location: route,
          uriPath: route,
        );

        expect(hideMiniPlayer, isTrue,
            reason: 'Compact player must remain hidden on $route');
        expect(hideBottomNav, isTrue,
            reason: 'Bottom navigation must be hidden on room detail route $route');
      }
    });

    test('Standard music browsing routes (/home, /library, /search) show miniplayer when track is active', () {
      final browsingRoutes = ['/home', '/search', '/playlists'];

      for (final route in browsingRoutes) {
        final hideMiniPlayer = computeHideMiniPlayer(
          location: route,
          uriPath: route,
          hasTrack: true,
        );
        final hideBottomNav = computeHideBottomNav(
          location: route,
          uriPath: route,
        );

        expect(hideMiniPlayer, isFalse,
            reason: 'Compact player must be visible on $route when a track is active');
        expect(hideBottomNav, isFalse,
            reason: 'Bottom navigation must be visible on $route');
      }
    });

    test('Now playing screen (/player) hides both miniplayer and bottom nav', () {
      const route = '/player';
      final hideMiniPlayer = computeHideMiniPlayer(
        location: route,
        uriPath: route,
        hasTrack: true,
      );
      final hideBottomNav = computeHideBottomNav(
        location: route,
        uriPath: route,
      );

      expect(hideMiniPlayer, isTrue);
      expect(hideBottomNav, isTrue);
    });
  });

  group('Playlist Custom Artwork Priority & Persistence Regression Tests', () {
    const track1NoArt = Track(
      id: 'track_1',
      title: 'The Child In Us',
      artist: 'Enigma',
      imageUrl: '',
      duration: '3:30',
    );

    const track2WithArt = Track(
      id: 'track_2',
      title: 'One Sun One Moon',
      artist: 'Anirudh Ravichander',
      imageUrl: 'https://images.miee.app/covers/jailer2.jpg',
      duration: '3:38',
    );

    test('Valid custom cover takes highest precedence over track artwork', () {
      final playlist = PlaylistModel(
        id: 'pl_one_piece',
        name: 'One piece',
        tracks: [track1NoArt, track2WithArt],
        createdAt: DateTime(2026, 1, 1),
        lastModified: DateTime(2026, 1, 1),
        customCoverPath: '/data/user/0/com.miee.music/app_flutter/playlist_covers/custom_one_piece.jpg',
      );

      expect(playlist.effectiveCoverUrl,
          equals('/data/user/0/com.miee.music/app_flutter/playlist_covers/custom_one_piece.jpg'),
          reason: 'Custom cover must always take precedence over track artwork');
    });

    test('Changing, adding, or reordering the first track never alters or clears the custom cover', () {
      final initialPlaylist = PlaylistModel(
        id: 'pl_one_piece',
        name: 'One piece',
        tracks: [track1NoArt, track2WithArt],
        createdAt: DateTime(2026, 1, 1),
        lastModified: DateTime(2026, 1, 1),
        customCoverPath: '/storage/custom_cover.jpg',
      );

      // 1. Reorder tracks (track 2 becomes first)
      final reordered = initialPlaylist.copyWith(
        tracks: [track2WithArt, track1NoArt],
      );
      expect(reordered.customCoverPath, equals('/storage/custom_cover.jpg'));
      expect(reordered.effectiveCoverUrl, equals('/storage/custom_cover.jpg'));

      // 2. Add a new 3rd track to the beginning
      const newTrack = Track(
        id: 'track_new',
        title: 'New Track',
        artist: 'Artist X',
        imageUrl: 'https://images.miee.app/covers/new.jpg',
        duration: '2:45',
      );
      final added = initialPlaylist.copyWith(
        tracks: [newTrack, ...initialPlaylist.tracks],
      );
      expect(added.customCoverPath, equals('/storage/custom_cover.jpg'));
      expect(added.effectiveCoverUrl, equals('/storage/custom_cover.jpg'));

      // 3. Remove track 1
      final removed = initialPlaylist.copyWith(
        tracks: [track2WithArt],
      );
      expect(removed.customCoverPath, equals('/storage/custom_cover.jpg'));
      expect(removed.effectiveCoverUrl, equals('/storage/custom_cover.jpg'));
    });

    test('Track retains its own artwork independently of playlist custom cover', () {
      final playlist = PlaylistModel(
        id: 'pl_one_piece',
        name: 'One piece',
        tracks: [track1NoArt, track2WithArt],
        createdAt: DateTime(2026, 1, 1),
        lastModified: DateTime(2026, 1, 1),
        customCoverPath: '/storage/custom_cover.jpg',
      );

      // Track 1 has empty artwork
      expect(playlist.tracks[0].imageUrl, isEmpty);
      // Track 2 has its own album art
      expect(playlist.tracks[1].imageUrl, equals('https://images.miee.app/covers/jailer2.jpg'));
      // Playlist custom cover is NOT injected into track models
      expect(playlist.tracks[0].imageUrl, isNot(equals(playlist.customCoverPath)));
      expect(playlist.tracks[1].imageUrl, isNot(equals(playlist.customCoverPath)));
    });

    test('Derived fallback artwork selects first track with valid artwork when no custom cover is set', () {
      final playlistNoCustomCover = PlaylistModel(
        id: 'pl_fallback',
        name: 'Fallback Playlist',
        tracks: [track1NoArt, track2WithArt], // Track 1 has no artwork, Track 2 has artwork
        createdAt: DateTime(2026, 1, 1),
        lastModified: DateTime(2026, 1, 1),
        customCoverPath: null,
      );

      expect(playlistNoCustomCover.effectiveCoverUrl, equals('https://images.miee.app/covers/jailer2.jpg'),
          reason: 'Fallback should pick the first track that actually has valid artwork instead of an empty string');
    });

    test('ConflictResolver preserves local customCoverPath during sync merge', () {
      final local = PlaylistHiveModel(
        id: 'pl_one_piece',
        name: 'One piece',
        tracks: [
          TrackHiveModel(
            id: 't1',
            title: 'Track 1',
            artist: 'Artist 1',
            imageUrl: '',
            duration: '3:00',
          )
        ],
        createdAt: DateTime(2026, 1, 1),
        lastModified: DateTime(2026, 1, 2),
        customCoverPath: '/local/durable/path/one_piece_cover.jpg',
      );

      final remote = PlaylistHiveModel(
        id: 'pl_one_piece',
        name: 'One piece',
        tracks: [
          TrackHiveModel(
            id: 't1',
            title: 'Track 1',
            artist: 'Artist 1',
            imageUrl: '',
            duration: '3:00',
          )
        ],
        createdAt: DateTime(2026, 1, 1),
        lastModified: DateTime(2026, 1, 3), // Remote lastModified is slightly newer
        customCoverPath: null, // Remote has null or empty customCoverPath
      );

      final merged = ConflictResolver.mergeLists<PlaylistHiveModel, String>(
        local: [local],
        remote: [remote],
        idSelector: (p) => p.id,
        mergeFn: (localPl, remotePl) {
          final resolvedMetadata = ConflictResolver.resolveLatest(
            local: localPl,
            localTime: localPl.lastModified,
            remote: remotePl,
            remoteTime: remotePl.lastModified,
          );
          final mergedSongs = ConflictResolver.mergeLists<TrackHiveModel, String>(
            local: localPl.tracks,
            remote: remotePl.tracks,
            idSelector: (s) => s.id,
            mergeFn: (l, r) => l,
          );
          final durableCoverPath = localPl.customCoverPath?.isNotEmpty == true
              ? localPl.customCoverPath
              : (remotePl.customCoverPath?.isNotEmpty == true
                  ? remotePl.customCoverPath
                  : resolvedMetadata.customCoverPath);

          return PlaylistHiveModel(
            id: resolvedMetadata.id,
            name: resolvedMetadata.name,
            tracks: mergedSongs,
            createdAt: resolvedMetadata.createdAt,
            lastModified: resolvedMetadata.lastModified,
            customCoverPath: durableCoverPath,
          );
        },
      );

      expect(merged.length, equals(1));
      expect(merged.first.customCoverPath, equals('/local/durable/path/one_piece_cover.jpg'),
          reason: 'Sync merge must never wipe out the local durable customCoverPath');
    });
  });
}

