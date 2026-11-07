import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../../core/storage/adapters/playback_history_entry.dart';
import '../../../core/storage/adapters/track_hive_model.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../../shared/models/music_item.dart';
import '../../../shared/models/track.dart';
import '../../recommendations/domain/music_language_service.dart';
import '../domain/listening_event.dart';
import '../domain/listening_history_repository.dart';

class SupabaseListeningHistoryRepository implements ListeningHistoryRepository {
  Box<PlaybackHistoryEntry> get _localBox =>
      Hive.box<PlaybackHistoryEntry>(HiveBoxes.playbackHistory);

  @override
  Future<void> recordListeningEvent({
    required String? uid,
    required MusicItem track,
    required int listenedSec,
    required int durationSec,
  }) async {
    // Only record genuine listening sessions of at least 3 seconds (excludes 0-2s misclicks / stream stalls)
    if (listenedSec < 3) return;

    final ratio = durationSec > 0 ? (listenedSec / durationSec).clamp(0.0, 1.0) : 0.0;
    final now = DateTime.now();

    // Ensure durable artwork
    String resolvedImageUrl = track.imageUrl;
    final normId = track.id.replaceFirst('youtube_', '');
    if (track.isYoutube && (resolvedImageUrl.isEmpty || !resolvedImageUrl.startsWith('http'))) {
      if (normId.isNotEmpty) {
        resolvedImageUrl = 'https://i.ytimg.com/vi/$normId/hqdefault.jpg';
      }
    }

    final durableTrack = Track(
      id: track.id,
      title: track.title,
      artist: track.artist,
      imageUrl: resolvedImageUrl,
      duration: track.duration,
      filePath: track.filePath,
    );

    // Record to local Hive box with account isolation (uid)
    try {
      await _localBox.add(
        PlaybackHistoryEntry(
          track: TrackHiveModel.fromTrack(durableTrack),
          startTime: now,
          completionPercent: ratio,
          userId: uid,
        ),
      );
    } catch (e) {
      debugPrint('[ListeningHistory] Local record error: $e');
    }
  }

  @override
  Future<List<ListeningEvent>> getRecentHistory({
    required String? uid,
    int limit = 30,
  }) async {
    var localEntries = _localBox.values.toList();

    // Strict account isolation: filter by authenticated user
    if (uid != null) {
      localEntries = localEntries.where((e) => e.userId == uid).toList();
    }

    localEntries.sort((a, b) => b.startTime.compareTo(a.startTime));

    return localEntries.take(limit).map((entry) {
      int parsedDurationSec = 180;
      if (entry.track.duration.isNotEmpty) {
        final parts = entry.track.duration.split(':');
        if (parts.length == 2) {
          final m = int.tryParse(parts[0]) ?? 0;
          final s = int.tryParse(parts[1]) ?? 0;
          parsedDurationSec = m * 60 + s;
        } else if (parts.length == 3) {
          final h = int.tryParse(parts[0]) ?? 0;
          final m = int.tryParse(parts[1]) ?? 0;
          final s = int.tryParse(parts[2]) ?? 0;
          parsedDurationSec = h * 3600 + m * 60 + s;
        }
      }

      final listenedSec = (parsedDurationSec * entry.completionPercent).round();
      final language = MusicLanguageService.detectLanguage(
        entry.track.title,
        artist: entry.track.artist,
      );

      return ListeningEvent(
        id: entry.key?.toString() ?? UniqueKey().toString(),
        trackId: entry.track.id,
        title: entry.track.title,
        artist: entry.track.artist,
        imageUrl: entry.track.imageUrl,
        source: entry.track.id.startsWith('youtube_') ? 'youtube' : 'local',
        timestamp: entry.startTime,
        durationSec: parsedDurationSec > 0 ? parsedDurationSec : 180,
        listenedSec: listenedSec,
        completionRatio: entry.completionPercent,
        language: language,
        userId: entry.userId ?? uid,
      );
    }).toList();
  }

  @override
  Future<void> clearHistory(String? uid) async {
    if (uid != null) {
      final keysToDelete = <dynamic>[];
      for (final key in _localBox.keys) {
        final entry = _localBox.get(key);
        if (entry != null && entry.userId == uid) {
          keysToDelete.add(key);
        }
      }
      await _localBox.deleteAll(keysToDelete);
    } else {
      await _localBox.clear();
    }
  }
}
