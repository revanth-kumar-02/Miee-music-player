import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/storage/adapters/playback_history_entry.dart';
import '../../../core/storage/adapters/track_hive_model.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../../shared/models/music_item.dart';
import '../domain/listening_event.dart';

abstract class ListeningHistoryRepository {
  Future<void> recordListeningEvent({
    required String? uid,
    required MusicItem track,
    required int listenedSec,
    required int durationSec,
  });
  Future<List<ListeningEvent>> getRecentHistory({required String? uid, int limit = 30});
  Future<void> clearHistory(String? uid);
}

class FirestoreListeningHistoryRepository implements ListeningHistoryRepository {
  FirebaseFirestore? get _firestore {
    if (!FirebaseService.isConfigured) return null;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  Box<PlaybackHistoryEntry> get _localBox =>
      Hive.box<PlaybackHistoryEntry>(HiveBoxes.playbackHistory);

  @override
  Future<void> recordListeningEvent({
    required String? uid,
    required MusicItem track,
    required int listenedSec,
    required int durationSec,
  }) async {
    // Only record if listened for at least 10 seconds or reached > 20%
    if (listenedSec < 10) return;

    final ratio = durationSec > 0 ? (listenedSec / durationSec).clamp(0.0, 1.0) : 0.0;
    final now = DateTime.now();

    // 1. Record to local Hive box
    try {
      await _localBox.add(
        PlaybackHistoryEntry(
          track: TrackHiveModel.fromTrack(track),
          startTime: now,
          completionPercent: ratio,
        ),
      );
    } catch (e) {
      debugPrint('[ListeningHistory] Local record error: $e');
    }

    // 2. Record to Firestore if user is authenticated
    final db = _firestore;
    if (db == null || uid == null || uid.isEmpty) return;

    try {
      final docRef = db
          .collection('users')
          .doc(uid)
          .collection('listeningHistory')
          .doc();

      await docRef.set({
        'trackId': track.id,
        'title': track.title,
        'artist': track.artist,
        'source': track.isYoutube ? 'youtube' : 'local',
        'timestamp': FieldValue.serverTimestamp(),
        'durationSec': durationSec,
        'listenedSec': listenedSec,
        'completionRatio': ratio,
      });
      debugPrint('[ListeningHistory] Recorded track "${track.title}" to Firestore');
    } catch (e) {
      debugPrint('[ListeningHistory] Cloud record error (ignored): $e');
    }
  }

  @override
  Future<List<ListeningEvent>> getRecentHistory({
    required String? uid,
    int limit = 30,
  }) async {
    final db = _firestore;
    if (db != null && uid != null && uid.isNotEmpty) {
      try {
        final query = await db
            .collection('users')
            .doc(uid)
            .collection('listeningHistory')
            .orderBy('timestamp', descending: true)
            .limit(limit)
            .get();

        if (query.docs.isNotEmpty) {
          return query.docs
              .map((d) => ListeningEvent.fromMap(d.id, d.data()))
              .toList();
        }
      } catch (e) {
        debugPrint('[ListeningHistory] Firestore history fetch error: $e');
      }
    }

    // Fallback to local Hive box
    final localEntries = _localBox.values.toList();
    localEntries.sort((a, b) => b.startTime.compareTo(a.startTime));

    return localEntries.take(limit).map((entry) {
      return ListeningEvent(
        id: entry.key?.toString() ?? UniqueKey().toString(),
        trackId: entry.track.id,
        title: entry.track.title,
        artist: entry.track.artist,
        source: entry.track.id.startsWith('youtube_') ? 'youtube' : 'local',
        timestamp: entry.startTime,
        durationSec: 180,
        listenedSec: (180 * entry.completionPercent).round(),
        completionRatio: entry.completionPercent,
      );
    }).toList();
  }

  @override
  Future<void> clearHistory(String? uid) async {
    await _localBox.clear();
  }
}
