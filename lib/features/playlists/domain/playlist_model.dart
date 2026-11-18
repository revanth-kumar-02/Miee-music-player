import '../../../shared/models/music_item.dart';

/// Defines the visibility and collaboration mode of a playlist.
enum PlaylistType {
  private,
  shared,
  collaborative;

  static PlaylistType fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'shared':
        return PlaylistType.shared;
      case 'collaborative':
        return PlaylistType.collaborative;
      default:
        return PlaylistType.private;
    }
  }

  String toDbString() => name;
  String get value => name;
}

/// Defines a user's role in a shared or collaborative playlist.
enum PlaylistRole {
  owner,
  editor,
  viewer;

  static PlaylistRole fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'editor':
        return PlaylistRole.editor;
      case 'viewer':
        return PlaylistRole.viewer;
      default:
        return PlaylistRole.owner;
    }
  }

  String toDbString() => name;
  String get value => name;
}

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

  /// Optional description of the playlist.
  final String description;

  /// Visibility and collaboration mode.
  final PlaylistType type;

  /// Auth user ID of the owner.
  final String? ownerId;

  /// Current user's permission role.
  final PlaylistRole role;

  /// Monotonically increasing revision version for conflict resolution.
  final int version;

  const PlaylistModel({
    required this.id,
    required this.name,
    required this.tracks,
    required this.createdAt,
    required this.lastModified,
    this.customCoverPath,
    this.description = '',
    this.type = PlaylistType.private,
    this.ownerId,
    this.role = PlaylistRole.owner,
    this.version = 1,
  });

  // ── Permissions & Capabilities ─────────────────────────────────────────────

  bool get isOwner => role == PlaylistRole.owner;
  bool get canEdit => role == PlaylistRole.owner || role == PlaylistRole.editor;
  bool get isCollaborative => type == PlaylistType.collaborative;
  bool get isShared => type == PlaylistType.shared;
  bool get isPrivate => type == PlaylistType.private;

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
        } else if (parts.length == 3) {
          final hours = int.tryParse(parts[0]) ?? 0;
          final minutes = int.tryParse(parts[1]) ?? 0;
          final seconds = int.tryParse(parts[2]) ?? 0;
          return sum + (hours * 3600 + minutes * 60 + seconds) * 1000;
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

  /// Track in the playlist used as fallback cover artwork source if no custom cover is set.
  /// Prefers the first track that possesses valid artwork.
  MusicItem? get artworkTrack {
    if (tracks.isEmpty) return null;
    for (final t in tracks) {
      if (t.imageUrl.trim().isNotEmpty) {
        return t;
      }
    }
    return tracks.firstOrNull;
  }

  /// Effective cover image URL/path for display, following the priority chain:
  /// 1. User-selected [customCoverPath] (highest priority, stored independently).
  /// 2. Album art of the first track with artwork ([artworkTrack]?.imageUrl).
  /// 3. null — callers should render a placeholder.
  String? get effectiveCoverUrl {
    final custom = customCoverPath;
    if (custom != null && custom.trim().isNotEmpty) {
      return custom.trim();
    }
    final fallback = artworkTrack;
    if (fallback != null) {
      final img = fallback.imageUrl;
      if (img.trim().isNotEmpty) {
        return img.trim();
      }
    }
    return null;
  }

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
    String? description,
    PlaylistType? type,
    String? ownerId,
    PlaylistRole? role,
    int? version,
  }) =>
      PlaylistModel(
        id: id ?? this.id,
        name: name ?? this.name,
        tracks: tracks ?? this.tracks,
        createdAt: createdAt ?? this.createdAt,
        lastModified: lastModified ?? this.lastModified,
        customCoverPath: clearCustomCover ? null : (customCoverPath ?? this.customCoverPath),
        description: description ?? this.description,
        type: type ?? this.type,
        ownerId: ownerId ?? this.ownerId,
        role: role ?? this.role,
        version: version ?? this.version,
      );
}


