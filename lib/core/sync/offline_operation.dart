class OfflineOperation {
  final String id;
  final String type; // 'favorite_add' | 'favorite_remove' | 'playlist_create' | 'playlist_delete' | 'playlist_rename' | 'playlist_tracks_reorder' | 'playlist_song_add' | 'playlist_song_remove' | 'profile_update' | 'settings_update' | 'history_add' | 'most_played_increment' | 'search_add' | 'search_remove'
  final Map<String, dynamic> payload;
  final DateTime timestamp;
  final String? userId;
  final int retryCount;
  final String? lastError;
  final bool isDeadLetter;

  const OfflineOperation({
    required this.id,
    required this.type,
    required this.payload,
    required this.timestamp,
    this.userId,
    this.retryCount = 0,
    this.lastError,
    this.isDeadLetter = false,
  });

  OfflineOperation copyWith({
    String? id,
    String? type,
    Map<String, dynamic>? payload,
    DateTime? timestamp,
    String? userId,
    int? retryCount,
    String? lastError,
    bool clearLastError = false,
    bool? isDeadLetter,
  }) {
    return OfflineOperation(
      id: id ?? this.id,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      timestamp: timestamp ?? this.timestamp,
      userId: userId ?? this.userId,
      retryCount: retryCount ?? this.retryCount,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      isDeadLetter: isDeadLetter ?? this.isDeadLetter,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'payload': payload,
      'timestamp': timestamp.toIso8601String(),
      if (userId != null) 'userId': userId,
      'retryCount': retryCount,
      if (lastError != null) 'lastError': lastError,
      'isDeadLetter': isDeadLetter,
    };
  }

  factory OfflineOperation.fromMap(Map<dynamic, dynamic> map) {
    return OfflineOperation(
      id: map['id'] as String,
      type: map['type'] as String,
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      timestamp: DateTime.parse(map['timestamp'] as String),
      userId: map['userId'] as String?,
      retryCount: (map['retryCount'] as num?)?.toInt() ?? 0,
      lastError: map['lastError'] as String?,
      isDeadLetter: map['isDeadLetter'] as bool? ?? false,
    );
  }
}
