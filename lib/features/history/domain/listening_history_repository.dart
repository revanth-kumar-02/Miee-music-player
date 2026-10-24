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
