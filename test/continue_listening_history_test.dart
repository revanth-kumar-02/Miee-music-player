import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/core/storage/adapters/history_entry.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/features/history/domain/listening_event.dart';

/// Pure logic extracted from HomePage for testing the Continue Listening resolution.
MusicItem? resolveContinueListeningTrack({
  required List<HistoryEntry> recentEntries,
  required List<ListeningEvent> cloudHistory,
  required List<MediaSong> localSongs,
}) {
  // 1. Check local Hive recently played entries (sorted newest first)
  if (recentEntries.isNotEmpty) {
    // Sort descending by playedAt to verify newest wins invariant
    final sorted = List<HistoryEntry>.from(recentEntries)
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    final newest = sorted.first.track.toTrack();
    if (!newest.isYoutube) {
      final localMatch = localSongs.where((s) {
        if (s.id == newest.id) return true;
        if (s.filePath.isNotEmpty && s.filePath == newest.filePath) return true;
        return s.id == newest.id.replaceFirst('youtube_', '');
      }).firstOrNull;
      if (localMatch != null) return localMatch;
    }
    return newest;
  }

  // 2. Check cloud listening history
  if (cloudHistory.isNotEmpty) {
    final sortedCloud = List<ListeningEvent>.from(cloudHistory)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final event = sortedCloud.first;
    final localMatch = localSongs.where((s) {
      if (s.id == event.trackId) return true;
      return s.id == event.trackId.replaceFirst('youtube_', '');
    }).firstOrNull;
    if (localMatch != null) return localMatch;

    final m = event.durationSec ~/ 60;
    final s = event.durationSec % 60;
    return Track(
      id: event.trackId.startsWith('youtube_')
          ? event.trackId
          : 'youtube_${event.trackId}',
      title: event.title,
      artist: event.artist,
      imageUrl: '',
      duration: '$m:${s.toString().padLeft(2, '0')}',
    );
  }

  // 3. Fallback to first available local track
  return localSongs.firstOrNull;
}

List<MusicItem> resolveContinueListeningQueue({
  required MusicItem targetTrack,
  required List<HistoryEntry> recentEntries,
  required List<MediaSong> localSongs,
  required List<MusicItem> activeQueue,
}) {
  final normTargetId = targetTrack.id.replaceFirst('youtube_', '');

  // 1. If active player queue contains this track, preserve active queue!
  final activeIndex = activeQueue.indexWhere((t) =>
      t.id == targetTrack.id ||
      t.id.replaceFirst('youtube_', '') == normTargetId);
  if (activeIndex >= 0) {
    return activeQueue;
  }

  // 2. If target is in localSongs, use localSongs queue
  final localIndex = localSongs.indexWhere(
      (s) => s.id == targetTrack.id || s.id == normTargetId);
  if (localIndex >= 0) {
    return localSongs;
  }

  // 3. If recent entries exist, use the recent history queue
  if (recentEntries.isNotEmpty) {
    return recentEntries.map((e) => e.track.toTrack()).toList();
  }

  // 4. Standalone track
  return [targetTrack];
}

void main() {
  group('Continue Listening Track Selection Tests', () {
    const localSong1 = MediaSong(
      id: 'local_1',
      title: 'Midnight City',
      artist: 'M83',
      album: 'Hurry Up',
      duration: '4:03',
      durationMs: 243000,
      filePath: '/storage/music/midnight.mp3',
      artworkPath: '/cache/art_1.png',
    );

    const localSong2 = MediaSong(
      id: 'local_2',
      title: 'Reunion',
      artist: 'M83',
      album: 'Hurry Up',
      duration: '3:55',
      durationMs: 235000,
      filePath: '/storage/music/reunion.mp3',
      artworkPath: '/cache/art_2.png',
    );

    test('Local track in recent history is resolved to local MediaSong with artwork', () {
      final now = DateTime.now();
      final historyEntries = [
        HistoryEntry(
          track: TrackHiveModel(
            id: 'local_2',
            title: 'Reunion',
            artist: 'M83',
            imageUrl: '',
            duration: '3:55',
            filePath: '/storage/music/reunion.mp3',
          ),
          playedAt: now,
        ),
      ];

      final selected = resolveContinueListeningTrack(
        recentEntries: historyEntries,
        cloudHistory: [],
        localSongs: [localSong1, localSong2],
      );

      expect(selected, isNotNull);
      expect(selected!.id, equals('local_2'));
      expect(selected.title, equals('Reunion'));
      // Verified that it resolved to MediaSong and has artworkPath
      expect(selected, isA<MediaSong>());
      expect((selected as MediaSong).artworkPath, equals('/cache/art_2.png'));
    });

    test('YouTube track in recent history is preserved with thumbnail and youtube identity', () {
      final now = DateTime.now();
      final historyEntries = [
        HistoryEntry(
          track: TrackHiveModel(
            id: 'youtube_dQw4w9WgXcQ',
            title: 'Never Gonna Give You Up',
            artist: 'Rick Astley',
            imageUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
            duration: '3:33',
          ),
          playedAt: now,
        ),
      ];

      final selected = resolveContinueListeningTrack(
        recentEntries: historyEntries,
        cloudHistory: [],
        localSongs: [localSong1, localSong2],
      );

      expect(selected, isNotNull);
      expect(selected!.id, equals('youtube_dQw4w9WgXcQ'));
      expect(selected.title, equals('Never Gonna Give You Up'));
      expect(selected.isYoutube, isTrue);
      expect(selected.imageUrl, equals('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'));
    });

    test('History ordering: the actual newest entry wins', () {
      final t1 = DateTime(2026, 10, 22, 10, 0);
      final t2 = DateTime(2026, 10, 22, 11, 0); // Newest
      final t0 = DateTime(2026, 10, 22, 9, 0);

      final historyEntries = [
        HistoryEntry(
          track: TrackHiveModel(
            id: 'local_1',
            title: 'Midnight City',
            artist: 'M83',
            imageUrl: '',
            duration: '4:03',
          ),
          playedAt: t1,
        ),
        HistoryEntry(
          track: TrackHiveModel(
            id: 'youtube_dQw4w9WgXcQ',
            title: 'Never Gonna Give You Up',
            artist: 'Rick Astley',
            imageUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
            duration: '3:33',
          ),
          playedAt: t2,
        ),
        HistoryEntry(
          track: TrackHiveModel(
            id: 'local_2',
            title: 'Reunion',
            artist: 'M83',
            imageUrl: '',
            duration: '3:55',
          ),
          playedAt: t0,
        ),
      ];

      final selected = resolveContinueListeningTrack(
        recentEntries: historyEntries,
        cloudHistory: [],
        localSongs: [localSong1, localSong2],
      );

      expect(selected, isNotNull);
      // Newest is the YouTube track at t2
      expect(selected!.id, equals('youtube_dQw4w9WgXcQ'));
      expect(selected.title, equals('Never Gonna Give You Up'));
    });

    test('Empty history falls back to first local track', () {
      final selected = resolveContinueListeningTrack(
        recentEntries: [],
        cloudHistory: [],
        localSongs: [localSong1, localSong2],
      );

      expect(selected, isNotNull);
      expect(selected!.id, equals('local_1'));
      expect(selected.title, equals('Midnight City'));
    });

    test('Empty history and empty local library returns null without crashing', () {
      final selected = resolveContinueListeningTrack(
        recentEntries: [],
        cloudHistory: [],
        localSongs: [],
      );

      expect(selected, isNull);
    });

    test('Cloud listening history resolves correctly when local box is empty', () {
      final cloudEvent = ListeningEvent(
        id: 'event_1',
        trackId: 'youtube_abc123',
        title: 'Starboy',
        artist: 'The Weeknd',
        source: 'youtube',
        timestamp: DateTime.now(),
        durationSec: 230,
        listenedSec: 230,
        completionRatio: 1.0,
      );

      final selected = resolveContinueListeningTrack(
        recentEntries: [],
        cloudHistory: [cloudEvent],
        localSongs: [localSong1],
      );

      expect(selected, isNotNull);
      expect(selected!.id, equals('youtube_abc123'));
      expect(selected.title, equals('Starboy'));
      expect(selected.duration, equals('3:50'));
    });
  });

  group('Continue Listening Queue Preservation Tests', () {
    const songA = MediaSong(
      id: 'song_a',
      title: 'Song A',
      artist: 'Artist A',
      album: 'Album A',
      duration: '3:00',
      durationMs: 180000,
      filePath: '/music/a.mp3',
      artworkPath: '',
    );
    const songB = MediaSong(
      id: 'song_b',
      title: 'Song B',
      artist: 'Artist B',
      album: 'Album B',
      duration: '3:30',
      durationMs: 210000,
      filePath: '/music/b.mp3',
      artworkPath: '',
    );
    const songC = MediaSong(
      id: 'song_c',
      title: 'Song C',
      artist: 'Artist C',
      album: 'Album C',
      duration: '4:00',
      durationMs: 240000,
      filePath: '/music/c.mp3',
      artworkPath: '',
    );

    test('Preserves active player queue if it already contains the target track', () {
      final activeQueue = [songA, songB, songC];
      final localSongs = [songA];

      final queue = resolveContinueListeningQueue(
        targetTrack: songB,
        recentEntries: [],
        localSongs: localSongs,
        activeQueue: activeQueue,
      );

      expect(queue.length, equals(3));
      expect(queue, equals(activeQueue));
      expect(queue.contains(songB), isTrue);
    });

    test('Uses localSongs queue when target track belongs to local library', () {
      final localSongs = [songA, songB, songC];

      final queue = resolveContinueListeningQueue(
        targetTrack: songC,
        recentEntries: [],
        localSongs: localSongs,
        activeQueue: [], // No active queue
      );

      expect(queue.length, equals(3));
      expect(queue, equals(localSongs));
    });

    test('Uses recent history list as queue when playing YouTube track from history', () {
      final ytTrack1 = Track(
        id: 'youtube_1',
        title: 'YT 1',
        artist: 'Artist 1',
        imageUrl: '',
        duration: '3:00',
      );
      final ytTrack2 = Track(
        id: 'youtube_2',
        title: 'YT 2',
        artist: 'Artist 2',
        imageUrl: '',
        duration: '3:30',
      );

      final recentEntries = [
        HistoryEntry(track: TrackHiveModel.fromTrack(ytTrack1), playedAt: DateTime.now()),
        HistoryEntry(track: TrackHiveModel.fromTrack(ytTrack2), playedAt: DateTime.now().subtract(const Duration(minutes: 5))),
      ];

      final queue = resolveContinueListeningQueue(
        targetTrack: ytTrack1,
        recentEntries: recentEntries,
        localSongs: [songA], // Unrelated local songs
        activeQueue: [],
      );

      expect(queue.length, equals(2));
      expect(queue.first.id, equals('youtube_1'));
      // Verified that user queue was not replaced by unrelated localSongs
      expect(queue.contains(songA), isFalse);
    });
  });
}
