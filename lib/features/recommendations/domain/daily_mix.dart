import '../../../shared/models/track.dart';

/// Represents a single deterministic personalized Daily Mix.
class DailyMix {
  final String id;
  final String title;
  final String subtitle;
  final List<Track> tracks;
  final String? coverImageUrl;
  final String primaryColorHex;
  final double familiarRatio;

  const DailyMix({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tracks,
    this.coverImageUrl,
    this.primaryColorHex = '#6C5CE7',
    this.familiarRatio = 0.70,
  });

  int get trackCount => tracks.length;

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'coverImageUrl': coverImageUrl,
        'primaryColorHex': primaryColorHex,
        'familiarRatio': familiarRatio,
        'tracks': tracks.map((t) => {
          'id': t.id,
          'title': t.title,
          'artist': t.artist,
          'imageUrl': t.imageUrl,
          'duration': t.duration,
          'filePath': t.filePath,
        }).toList(),
      };

  factory DailyMix.fromMap(Map<dynamic, dynamic> map) {
    final rawTracks = map['tracks'] as List<dynamic>? ?? const [];
    final tracks = rawTracks.map((item) {
      if (item is Map) {
        return Track(
          id: item['id']?.toString() ?? '',
          title: item['title']?.toString() ?? '',
          artist: item['artist']?.toString() ?? '',
          imageUrl: item['imageUrl']?.toString() ?? '',
          duration: item['duration']?.toString() ?? '3:00',
          filePath: item['filePath']?.toString(),
        );
      }
      return const Track(id: '', title: '', artist: '', imageUrl: '', duration: '3:00');
    }).where((t) => t.id.isNotEmpty).toList();

    return DailyMix(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      subtitle: map['subtitle']?.toString() ?? '',
      coverImageUrl: map['coverImageUrl']?.toString(),
      primaryColorHex: map['primaryColorHex']?.toString() ?? '#6C5CE7',
      familiarRatio: (map['familiarRatio'] as num?)?.toDouble() ?? 0.70,
      tracks: tracks,
    );
  }
}

/// Represents the persistent snapshot of Daily Mixes generated for a specific user on a specific calendar day.
class DailyMixSnapshot {
  final String userId;
  final String localDate; // YYYY-MM-DD
  final DateTime generatedAt;
  final List<DailyMix> mixes;
  final int version;

  const DailyMixSnapshot({
    required this.userId,
    required this.localDate,
    required this.generatedAt,
    required this.mixes,
    this.version = 1,
  });

  /// Formats [dateTime] into a local calendar date string ('YYYY-MM-DD').
  /// Uses the device's local calendar day rather than UTC midnight.
  static String formatLocalDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  bool get isEmpty => mixes.isEmpty;
  bool get isNotEmpty => mixes.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'localDate': localDate,
        'generatedAt': generatedAt.toIso8601String(),
        'version': version,
        'mixes': mixes.map((m) => m.toMap()).toList(),
      };

  factory DailyMixSnapshot.fromMap(Map<dynamic, dynamic> map) {
    final rawMixes = map['mixes'] as List<dynamic>? ?? const [];
    final mixes = rawMixes
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => DailyMix.fromMap(m))
        .toList();

    return DailyMixSnapshot(
      userId: map['userId']?.toString() ?? '',
      localDate: map['localDate']?.toString() ?? '',
      generatedAt: DateTime.tryParse(map['generatedAt']?.toString() ?? '') ?? DateTime.now(),
      version: (map['version'] as num?)?.toInt() ?? 1,
      mixes: mixes,
    );
  }

  factory DailyMixSnapshot.empty(String userId) {
    final now = DateTime.now();
    return DailyMixSnapshot(
      userId: userId,
      localDate: formatLocalDate(now),
      generatedAt: now,
      mixes: const [],
    );
  }
}
