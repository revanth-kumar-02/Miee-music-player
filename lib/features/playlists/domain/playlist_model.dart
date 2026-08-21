import '../../../shared/models/track.dart';
import '../../../shared/models/music_item.dart';

/// Rich domain model for a user playlist.
///
/// Derived from [PlaylistHiveModel] — computed fields are calculated
/// in-memory and never persisted. All mutation goes through
/// [PlaylistController] which delegates to [PlaylistRepository].
class PlaylistModel {
  final String id;
  final String name;
  final List<MusicItem> tracks;
  final DateTime createdAt;
  final DateTime lastModified;

  /// Optional user-selected custom cover image (local file path).
  /// When set, this takes highest priority as the playlist cover.
  final String? customCoverPath;

  const PlaylistModel({
    required this.id,
    required this.name,
    required this.tracks,
    required this.createdAt,
    required this.lastModified,
    this.customCoverPath,
  });

  // ── Computed properties ───────────────────────────────────────────────────

  int get songCount => tracks.length;

  /// Sum of all track durations in milliseconds.
  int get totalDurationMs => tracks.fold(0, (sum, t) {
        // Parse "m:ss" formatted strings like "3:42".
        final parts = t.duration.split(':');
        if (parts.length == 2) {
          final minutes = int.tryParse(parts[0]) ?? 0;
          final seconds = int.tryParse(parts[1]) ?? 0;
          return sum + (minutes * 60 + seconds) * 1000;
        }
        return sum;
      });

  /// Human-readable total duration: "1h 23m" or "45m" or "< 1m".
  String get totalDurationFormatted {
    final totalSeconds = totalDurationMs ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m';
    return '< 1m';
  }

  /// First track in the playlist, used as fallback cover artwork source.
  MusicItem? get artworkTrack => tracks.isNotEmpty ? tracks.first : null;

  /// Effective cover image URL/path for display, following the priority chain:
  /// 1. User-selected [customCoverPath] (highest priority).
  /// 2. Album art of the first track ([artworkTrack]?.imageUrl).
  /// 3. null — callers should render a placeholder.
  String? get effectiveCoverUrl =>
      customCoverPath?.isNotEmpty == true
          ? customCoverPath
          : (artworkTrack?.imageUrl?.isNotEmpty == true ? artworkTrack!.imageUrl : null);

  bool get isEmpty => tracks.isEmpty;
  bool get isNotEmpty => !isEmpty;

  PlaylistModel copyWith({
    String? id,
    String? name,
    List<MusicItem>? tracks,
    DateTime? createdAt,
    DateTime? lastModified,
    String? customCoverPath,
    bool clearCustomCover = false,
  }) =>
      PlaylistModel(
        id: id ?? this.id,
        name: name ?? this.name,
        tracks: tracks ?? this.tracks,
        createdAt: createdAt ?? this.createdAt,
        lastModified: lastModified ?? this.lastModified,
        customCoverPath: clearCustomCover ? null : (customCoverPath ?? this.customCoverPath),
      );
}


