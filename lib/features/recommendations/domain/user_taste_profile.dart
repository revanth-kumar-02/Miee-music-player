import 'package:flutter/foundation.dart';
import 'artist_normalizer.dart';

@immutable
class UserTasteProfile {
  final String userId;
  final Map<String, double> artistAffinities;
  final Map<String, double> languageAffinities;
  final DateTime lastUpdated;
  final int eventsProcessedCount;
  final int version;

  const UserTasteProfile({
    required this.userId,
    required this.artistAffinities,
    required this.languageAffinities,
    required this.lastUpdated,
    required this.eventsProcessedCount,
    this.version = 1,
  });

  /// Factory for a fresh, empty profile for a user with neutral affinities.
  factory UserTasteProfile.empty(String userId) {
    return UserTasteProfile(
      userId: userId,
      artistAffinities: const {},
      languageAffinities: const {},
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      eventsProcessedCount: 0,
      version: 1,
    );
  }

  /// Neutral affinity baseline is 0.50 (on a 0.0 - 1.0 scale).
  static const double neutralAffinity = 0.50;

  /// Retrieves the affinity score for a given artist (0.0 to 1.0),
  /// defaulting to 0.50 if the artist has not been encountered.
  /// Automatically normalizes the query artist name for robust matching.
  double getArtistAffinity(String artist) {
    final normalized = ArtistNormalizer.normalize(artist).toLowerCase();
    return artistAffinities[normalized] ?? neutralAffinity;
  }

  /// Retrieves the affinity score for a given language (0.0 to 1.0),
  /// defaulting to 0.50 if the language has not been encountered.
  double getLanguageAffinity(String language) {
    final key = language.trim().toLowerCase();
    return languageAffinities[key] ?? neutralAffinity;
  }

  /// Returns artists sorted by descending affinity score.
  List<MapEntry<String, double>> get rankedArtists {
    final entries = artistAffinities.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  /// Returns languages sorted by descending affinity score.
  List<MapEntry<String, double>> get rankedLanguages {
    final entries = languageAffinities.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  /// Top N preferred artists (affinity > 0.50).
  List<String> topArtists({int limit = 10}) {
    return rankedArtists
        .where((e) => e.value > neutralAffinity)
        .take(limit)
        .map((e) => e.key)
        .toList();
  }

  /// Disliked artists (affinity < 0.50, due to accumulated skips).
  List<String> dislikedArtists({double threshold = 0.45}) {
    return rankedArtists
        .where((e) => e.value < threshold)
        .map((e) => e.key)
        .toList();
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'artistAffinities': artistAffinities,
      'languageAffinities': languageAffinities,
      'lastUpdated': lastUpdated.toIso8601String(),
      'eventsProcessedCount': eventsProcessedCount,
      'version': version,
    };
  }

  factory UserTasteProfile.fromMap(Map<dynamic, dynamic> map) {
    final rawArtist = map['artistAffinities'] as Map<dynamic, dynamic>? ?? {};
    final rawLang = map['languageAffinities'] as Map<dynamic, dynamic>? ?? {};

    final artistMap = <String, double>{};
    for (final entry in rawArtist.entries) {
      artistMap[entry.key.toString()] = (entry.value as num).toDouble();
    }

    final langMap = <String, double>{};
    for (final entry in rawLang.entries) {
      langMap[entry.key.toString()] = (entry.value as num).toDouble();
    }

    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(map['lastUpdated'] as String? ?? '');
    } catch (_) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    return UserTasteProfile(
      userId: map['userId'] as String? ?? '',
      artistAffinities: artistMap,
      languageAffinities: langMap,
      lastUpdated: parsedDate,
      eventsProcessedCount: (map['eventsProcessedCount'] as num?)?.toInt() ?? 0,
      version: (map['version'] as num?)?.toInt() ?? 1,
    );
  }

  UserTasteProfile copyWith({
    String? userId,
    Map<String, double>? artistAffinities,
    Map<String, double>? languageAffinities,
    DateTime? lastUpdated,
    int? eventsProcessedCount,
    int? version,
  }) {
    return UserTasteProfile(
      userId: userId ?? this.userId,
      artistAffinities: artistAffinities ?? this.artistAffinities,
      languageAffinities: languageAffinities ?? this.languageAffinities,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      eventsProcessedCount: eventsProcessedCount ?? this.eventsProcessedCount,
      version: version ?? this.version,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserTasteProfile &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          lastUpdated == other.lastUpdated &&
          eventsProcessedCount == other.eventsProcessedCount &&
          mapEquals(artistAffinities, other.artistAffinities) &&
          mapEquals(languageAffinities, other.languageAffinities);

  @override
  int get hashCode =>
      userId.hashCode ^
      lastUpdated.hashCode ^
      eventsProcessedCount.hashCode ^
      artistAffinities.length.hashCode ^
      languageAffinities.length.hashCode;
}

