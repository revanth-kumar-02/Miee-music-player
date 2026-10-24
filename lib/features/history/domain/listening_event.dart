/// Represents a recorded listening session stored in `users/{uid}/listeningHistory`.
class ListeningEvent {
  final String id;
  final String trackId;
  final String title;
  final String artist;
  final String? artistId;
  final String? imageUrl;
  final String source; // 'youtube' | 'local'
  final DateTime timestamp;
  final int durationSec;
  final int listenedSec;
  final double completionRatio;

  const ListeningEvent({
    required this.id,
    required this.trackId,
    required this.title,
    required this.artist,
    this.artistId,
    this.imageUrl,
    required this.source,
    required this.timestamp,
    required this.durationSec,
    required this.listenedSec,
    required this.completionRatio,
  });

  factory ListeningEvent.fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      try {
        final dynamic ts = val;
        return ts.toDate() as DateTime;
      } catch (_) {
        return DateTime.now();
      }
    }

    return ListeningEvent(
      id: id,
      trackId: data['trackId'] as String? ?? '',
      title: data['title'] as String? ?? 'Unknown Title',
      artist: data['artist'] as String? ?? 'Unknown Artist',
      artistId: data['artistId'] as String?,
      imageUrl: data['imageUrl'] as String? ?? data['image_url'] as String?,
      source: data['source'] as String? ?? 'youtube',
      timestamp: parseDate(data['timestamp']),
      durationSec: (data['durationSec'] as num?)?.toInt() ?? 0,
      listenedSec: (data['listenedSec'] as num?)?.toInt() ?? 0,
      completionRatio: (data['completionRatio'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'trackId': trackId,
      'title': title,
      'artist': artist,
      'artistId': artistId,
      'imageUrl': imageUrl,
      'image_url': imageUrl,
      'source': source,
      'timestamp': timestamp.toIso8601String(),
      'durationSec': durationSec,
      'listenedSec': listenedSec,
      'completionRatio': completionRatio,
    };
  }
}
