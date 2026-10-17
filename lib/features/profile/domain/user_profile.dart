import '../../onboarding/domain/artist_model.dart';

/// Represents a persistent cloud user profile in Firestore.
class UserProfile {
  final String uid;
  final String displayName;
  final String email;
  final String? avatarUrl;
  final bool onboardingCompleted;
  final List<String> selectedArtistIds;
  final List<ArtistSummary> selectedArtists;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int schemaVersion;

  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    this.avatarUrl,
    this.onboardingCompleted = false,
    this.selectedArtistIds = const [],
    this.selectedArtists = const [],
    required this.createdAt,
    required this.updatedAt,
    this.schemaVersion = 1,
  });

  factory UserProfile.initial({
    required String uid,
    required String email,
    required String displayName,
  }) {
    final now = DateTime.now();
    return UserProfile(
      uid: uid,
      displayName: displayName.trim().isNotEmpty ? displayName.trim() : 'Miee Listener',
      email: email,
      onboardingCompleted: false,
      selectedArtistIds: const [],
      selectedArtists: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      // Handle Firestore Timestamp dynamically
      try {
        final dynamic ts = val;
        return ts.toDate() as DateTime;
      } catch (_) {
        return DateTime.now();
      }
    }

    final rawArtists = data['selectedArtists'] as List<dynamic>? ?? [];
    final artists = rawArtists
        .map((a) => ArtistSummary.fromMap(Map<String, dynamic>.from(a as Map)))
        .toList();

    final rawIds = data['selectedArtistIds'] as List<dynamic>? ?? [];
    final ids = rawIds.map((e) => e.toString()).toList();

    return UserProfile(
      uid: uid,
      displayName: data['displayName'] as String? ?? 'Miee Listener',
      email: data['email'] as String? ?? '',
      avatarUrl: data['avatarUrl'] as String?,
      onboardingCompleted: data['onboardingCompleted'] as bool? ?? false,
      selectedArtistIds: ids,
      selectedArtists: artists,
      createdAt: parseDate(data['createdAt']),
      updatedAt: parseDate(data['updatedAt']),
      schemaVersion: (data['schemaVersion'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'email': email,
      'avatarUrl': avatarUrl,
      'onboardingCompleted': onboardingCompleted,
      'selectedArtistIds': selectedArtistIds,
      'selectedArtists': selectedArtists.map((a) => a.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'schemaVersion': schemaVersion,
    };
  }

  UserProfile copyWith({
    String? displayName,
    String? email,
    String? avatarUrl,
    bool? onboardingCompleted,
    List<String>? selectedArtistIds,
    List<ArtistSummary>? selectedArtists,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      uid: uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      selectedArtistIds: selectedArtistIds ?? this.selectedArtistIds,
      selectedArtists: selectedArtists ?? this.selectedArtists,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      schemaVersion: schemaVersion,
    );
  }
}
