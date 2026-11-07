/// Supported deterministic listening behavior event types.
enum ListeningEventType {
  /// User completed >= 75% of the track.
  completedPlay,

  /// User completed >= 30% and < 75% of the track.
  partialPlay,

  /// User skipped: listened < 20 seconds AND completion < 20%.
  skip,

  /// Neither completed, partial, nor skip (e.g. 20-29% completion).
  unclassified;

  /// Classifies listening behavior based on actual listening duration and track duration.
  static ListeningEventType classify({
    required int listenedSec,
    required int durationSec,
    required double completionRatio,
  }) {
    if (completionRatio >= 0.75) {
      return ListeningEventType.completedPlay;
    } else if (completionRatio >= 0.30) {
      return ListeningEventType.partialPlay;
    } else if (listenedSec < 20 && completionRatio < 0.20) {
      return ListeningEventType.skip;
    }
    return ListeningEventType.unclassified;
  }

  /// Deterministic feedback weight for this event type.
  double get weight {
    switch (this) {
      case ListeningEventType.completedPlay:
        return 1.0;
      case ListeningEventType.partialPlay:
        return 0.5;
      case ListeningEventType.skip:
        return -0.8;
      case ListeningEventType.unclassified:
        return 0.0;
    }
  }
}

/// Represents a recorded listening session stored in local Hive and optionally user profile history.
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

  /// Detected music language (e.g. 'Tamil', 'Telugu', 'Hindi', 'English', etc.)
  final String? language;

  /// Deterministic listening event type.
  final ListeningEventType eventType;

  /// Event weight: +1.0 (completed), +0.5 (partial), -0.8 (skip), 0.0 (unclassified).
  final double weight;

  /// Authenticated user ID (ensures strict account isolation).
  final String? userId;

  ListeningEvent({
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
    this.language,
    ListeningEventType? eventType,
    double? weight,
    this.userId,
  })  : eventType = eventType ??
            ListeningEventType.classify(
              listenedSec: listenedSec,
              durationSec: durationSec,
              completionRatio: completionRatio,
            ),
        weight = weight ??
            (eventType != null
                ? eventType.weight
                : ListeningEventType.classify(
                    listenedSec: listenedSec,
                    durationSec: durationSec,
                    completionRatio: completionRatio,
                  ).weight);

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

    final durationSec = (data['durationSec'] as num?)?.toInt() ?? 0;
    final listenedSec = (data['listenedSec'] as num?)?.toInt() ?? 0;
    final ratio = (data['completionRatio'] as num?)?.toDouble() ??
        (durationSec > 0 ? (listenedSec / durationSec).clamp(0.0, 1.0) : 0.0);

    ListeningEventType? parsedType;
    if (data['eventType'] is String) {
      final typeStr = data['eventType'] as String;
      for (final t in ListeningEventType.values) {
        if (t.name == typeStr) {
          parsedType = t;
          break;
        }
      }
    }

    final parsedWeight = (data['weight'] as num?)?.toDouble();

    return ListeningEvent(
      id: id,
      trackId: data['trackId'] as String? ?? '',
      title: data['title'] as String? ?? 'Unknown Title',
      artist: data['artist'] as String? ?? 'Unknown Artist',
      artistId: data['artistId'] as String?,
      imageUrl: data['imageUrl'] as String? ?? data['image_url'] as String?,
      source: data['source'] as String? ?? 'youtube',
      timestamp: parseDate(data['timestamp']),
      durationSec: durationSec,
      listenedSec: listenedSec,
      completionRatio: ratio,
      language: data['language'] as String?,
      eventType: parsedType,
      weight: parsedWeight,
      userId: data['userId'] as String? ?? data['uid'] as String?,
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
      if (language != null) 'language': language,
      'eventType': eventType.name,
      'weight': weight,
      if (userId != null) 'userId': userId,
    };
  }

  bool get isCompletedPlay => eventType == ListeningEventType.completedPlay;
  bool get isPartialPlay => eventType == ListeningEventType.partialPlay;
  bool get isSkip => eventType == ListeningEventType.skip;
}
