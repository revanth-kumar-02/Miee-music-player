class OfflineOperation {
  final String id;
  final String type; // 'favorite_add' | 'favorite_remove' | 'playlist_create' | 'playlist_delete' | 'playlist_rename' | 'playlist_song_add' | 'playlist_song_remove' | 'profile_update' | 'settings_update'
  final Map<String, dynamic> payload;
  final DateTime timestamp;

  const OfflineOperation({
    required this.id,
    required this.type,
    required this.payload,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'payload': payload,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory OfflineOperation.fromMap(Map<dynamic, dynamic> map) {
    return OfflineOperation(
      id: map['id'] as String,
      type: map['type'] as String,
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}
