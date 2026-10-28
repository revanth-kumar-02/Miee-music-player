/// Domain models for Realtime Listening Rooms in Miee.

class ListeningRoom {
  final String id;
  final String hostId;
  final String joinCode;
  final String name;
  final String status; // 'active', 'ended', 'paused'
  final int capacity; // 1-5
  final DateTime createdAt;
  final DateTime updatedAt;

  const ListeningRoom({
    required this.id,
    required this.hostId,
    required this.joinCode,
    required this.name,
    this.status = 'active',
    this.capacity = 5,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ListeningRoom.fromMap(Map<String, dynamic> map) {
    return ListeningRoom(
      id: map['id'] as String,
      hostId: map['host_id'] as String,
      joinCode: map['join_code'] as String,
      name: map['name'] as String,
      status: map['status'] as String? ?? 'active',
      capacity: (map['capacity'] as num?)?.toInt() ?? 5,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'host_id': hostId,
      'join_code': joinCode,
      'name': name,
      'status': status,
      'capacity': capacity,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class RoomMember {
  final String id;
  final String roomId;
  final String userId;
  final String role; // 'host' or 'listener'
  final String? displayName;
  final String? username;
  final String? avatarUrl;
  final DateTime joinedAt;
  final DateTime lastSeenAt;

  const RoomMember({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.role,
    this.displayName,
    this.username,
    this.avatarUrl,
    required this.joinedAt,
    required this.lastSeenAt,
  });

  factory RoomMember.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    return RoomMember(
      id: map['id'] as String,
      roomId: map['room_id'] as String,
      userId: map['user_id'] as String,
      role: map['role'] as String? ?? 'listener',
      displayName: (profile?['display_name'] ?? map['display_name']) as String?,
      username: (profile?['username'] ?? map['username']) as String?,
      avatarUrl: (profile?['avatar_url'] ?? map['avatar_url']) as String?,
      joinedAt: map['joined_at'] != null
          ? DateTime.parse(map['joined_at'] as String)
          : DateTime.now(),
      lastSeenAt: map['last_seen_at'] != null
          ? DateTime.parse(map['last_seen_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'room_id': roomId,
      'user_id': userId,
      'role': role,
      'display_name': displayName,
      'username': username,
      'avatar_url': avatarUrl,
      'joined_at': joinedAt.toIso8601String(),
      'last_seen_at': lastSeenAt.toIso8601String(),
    };
  }

  RoomMember copyWith({
    String? id,
    String? roomId,
    String? userId,
    String? role,
    String? displayName,
    String? username,
    String? avatarUrl,
    DateTime? joinedAt,
    DateTime? lastSeenAt,
  }) {
    return RoomMember(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      joinedAt: joinedAt ?? this.joinedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}

class RoomPlaybackState {
  final String roomId;
  final String? currentTrackId;
  final String? title;
  final String? artist;
  final String? imageUrl;
  final int durationMs;
  final bool isYoutube;
  final List<Map<String, dynamic>> queue;
  final String playbackStatus; // 'playing', 'paused', 'buffering', 'stopped'
  final int positionMs;
  final int revision;
  final DateTime updatedAt;
  final String? updatedBy;

  const RoomPlaybackState({
    required this.roomId,
    this.currentTrackId,
    this.title,
    this.artist,
    this.imageUrl,
    this.durationMs = 0,
    this.isYoutube = true,
    this.queue = const [],
    this.playbackStatus = 'paused',
    this.positionMs = 0,
    this.revision = 1,
    required this.updatedAt,
    this.updatedBy,
  });

  factory RoomPlaybackState.fromMap(Map<String, dynamic> map) {
    return RoomPlaybackState(
      roomId: map['room_id'] as String,
      currentTrackId: map['current_track_id'] as String?,
      title: map['title'] as String?,
      artist: map['artist'] as String?,
      imageUrl: map['image_url'] as String?,
      durationMs: (map['duration_ms'] as num?)?.toInt() ?? 0,
      isYoutube: map['is_youtube'] as bool? ?? true,
      queue: (map['queue'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      playbackStatus: map['playback_status'] as String? ?? 'paused',
      positionMs: (map['position_ms'] as num?)?.toInt() ?? 0,
      revision: (map['revision'] as num?)?.toInt() ?? 1,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : DateTime.now(),
      updatedBy: map['updated_by'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'room_id': roomId,
      'current_track_id': currentTrackId,
      'title': title,
      'artist': artist,
      'image_url': imageUrl,
      'duration_ms': durationMs,
      'is_youtube': isYoutube,
      'queue': queue,
      'playback_status': playbackStatus,
      'position_ms': positionMs,
      'revision': revision,
      'updated_at': updatedAt.toIso8601String(),
      'updated_by': updatedBy,
    };
  }

  RoomPlaybackState copyWith({
    String? currentTrackId,
    String? title,
    String? artist,
    String? imageUrl,
    int? durationMs,
    bool? isYoutube,
    List<Map<String, dynamic>>? queue,
    String? playbackStatus,
    int? positionMs,
    int? revision,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return RoomPlaybackState(
      roomId: roomId,
      currentTrackId: currentTrackId ?? this.currentTrackId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      imageUrl: imageUrl ?? this.imageUrl,
      durationMs: durationMs ?? this.durationMs,
      isYoutube: isYoutube ?? this.isYoutube,
      queue: queue ?? this.queue,
      playbackStatus: playbackStatus ?? this.playbackStatus,
      positionMs: positionMs ?? this.positionMs,
      revision: revision ?? this.revision,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}

class RoomMessage {
  final String id;
  final String roomId;
  final String userId;
  final String? userName;
  final String? userAvatar;
  final String content;
  final String type; // 'text' or 'song_suggestion'
  final String? trackId;
  final String? trackTitle;
  final String? trackArtist;
  final String? trackImageUrl;
  final bool isYoutube;
  final DateTime createdAt;

  const RoomMessage({
    required this.id,
    required this.roomId,
    required this.userId,
    this.userName,
    this.userAvatar,
    required this.content,
    this.type = 'text',
    this.trackId,
    this.trackTitle,
    this.trackArtist,
    this.trackImageUrl,
    this.isYoutube = true,
    required this.createdAt,
  });

  bool get isSongSuggestion => type == 'song_suggestion' && trackId != null && trackId!.isNotEmpty;

  factory RoomMessage.fromMap(Map<String, dynamic> map) {
    return RoomMessage(
      id: map['id'] as String,
      roomId: map['room_id'] as String,
      userId: map['user_id'] as String,
      userName: map['user_name'] as String?,
      userAvatar: map['user_avatar'] as String?,
      content: map['content'] as String? ?? '',
      type: map['type'] as String? ?? 'text',
      trackId: map['track_id'] as String?,
      trackTitle: map['track_title'] as String?,
      trackArtist: map['track_artist'] as String?,
      trackImageUrl: map['track_image_url'] as String?,
      isYoutube: map['is_youtube'] as bool? ?? true,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'room_id': roomId,
      'user_id': userId,
      'user_name': userName,
      'user_avatar': userAvatar,
      'content': content,
      'type': type,
      'track_id': trackId,
      'track_title': trackTitle,
      'track_artist': trackArtist,
      'track_image_url': trackImageUrl,
      'is_youtube': isYoutube,
      'created_at': createdAt.toIso8601String(),
    };
  }

  RoomMessage copyWith({
    String? id,
    String? roomId,
    String? userId,
    String? userName,
    String? userAvatar,
    String? content,
    String? type,
    String? trackId,
    String? trackTitle,
    String? trackArtist,
    String? trackImageUrl,
    bool? isYoutube,
    DateTime? createdAt,
  }) {
    return RoomMessage(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
      content: content ?? this.content,
      type: type ?? this.type,
      trackId: trackId ?? this.trackId,
      trackTitle: trackTitle ?? this.trackTitle,
      trackArtist: trackArtist ?? this.trackArtist,
      trackImageUrl: trackImageUrl ?? this.trackImageUrl,
      isYoutube: isYoutube ?? this.isYoutube,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

