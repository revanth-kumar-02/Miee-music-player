import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/history/domain/listening_event.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/onboarding/providers/onboarding_providers.dart';
import 'package:Miee/features/profile/domain/user_profile.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';

void main() {
  group('ArtistModel & ArtistSummary Tests', () {
    test('Deezer JSON parsing produces valid ArtistModel', () {
      final json = {
        'id': 142,
        'name': 'Coldplay',
        'picture_medium': 'https://e-cdns-images.dzcdn.net/images/artist/coldplay.jpg',
        'picture_big': 'https://e-cdns-images.dzcdn.net/images/artist/coldplay_big.jpg',
      };

      final artist = ArtistModel.fromDeezer(json);
      expect(artist.id, equals('142'));
      expect(artist.name, equals('Coldplay'));
      expect(artist.imageUrl, equals('https://e-cdns-images.dzcdn.net/images/artist/coldplay_big.jpg'));

      final summary = artist.toSummary();
      expect(summary.id, equals('142'));
      expect(summary.name, equals('Coldplay'));
      expect(summary.imageUrl, equals('https://e-cdns-images.dzcdn.net/images/artist/coldplay_big.jpg'));
    });

    test('ArtistSummary Firestore map serialization and deserialization', () {
      const summary = ArtistSummary(
        id: '27',
        name: 'Daft Punk',
        imageUrl: 'https://cdn.example.com/daftpunk.jpg',
      );

      final map = summary.toMap();
      expect(map['id'], equals('27'));
      expect(map['name'], equals('Daft Punk'));
      expect(map['imageUrl'], equals('https://cdn.example.com/daftpunk.jpg'));

      final reconstructed = ArtistSummary.fromMap(map);
      expect(reconstructed.id, equals('27'));
      expect(reconstructed.name, equals('Daft Punk'));
      expect(reconstructed.imageUrl, equals('https://cdn.example.com/daftpunk.jpg'));
    });
  });

  group('UserProfile Tests', () {
    test('UserProfile serialization round-trip matches Firestore schema', () {
      final now = DateTime.now();
      final profile = UserProfile(
        uid: 'user_123',
        email: 'listener@example.com',
        displayName: 'Aura',
        avatarUrl: 'https://avatar.example.com/aura.png',
        onboardingCompleted: true,
        selectedArtists: const [
          ArtistSummary(id: '1', name: 'Coldplay', imageUrl: ''),
          ArtistSummary(id: '2', name: 'Radiohead', imageUrl: ''),
          ArtistSummary(id: '3', name: 'Oasis', imageUrl: ''),
        ],
        createdAt: now,
        updatedAt: now,
        schemaVersion: 1,
      );

      final firestoreMap = profile.toMap();
      expect(firestoreMap['displayName'], equals('Aura'));
      expect(firestoreMap['email'], equals('listener@example.com'));
      expect(firestoreMap['onboardingCompleted'], isTrue);
      expect(firestoreMap['selectedArtists'], hasLength(3));
      expect(firestoreMap['schemaVersion'], equals(1));

      final restored = UserProfile.fromMap('user_123', firestoreMap);
      expect(restored.uid, equals('user_123'));
      expect(restored.displayName, equals('Aura'));
      expect(restored.onboardingCompleted, isTrue);
      expect(restored.selectedArtists, hasLength(3));
      expect(restored.selectedArtists.first.name, equals('Coldplay'));
    });

    test('UserProfile handles missing/legacy fields gracefully', () {
      final legacyMap = <String, dynamic>{
        'displayName': 'Legacy User',
      };

      final profile = UserProfile.fromMap('legacy_uid', legacyMap);
      expect(profile.uid, equals('legacy_uid'));
      expect(profile.displayName, equals('Legacy User'));
      expect(profile.onboardingCompleted, isFalse);
      expect(profile.selectedArtists, isEmpty);
      expect(profile.schemaVersion, equals(1));
    });
  });

  group('Onboarding State & Artist Selection Validation', () {
    test('Enforces minimum 3 and maximum 5 artists', () {
      const a1 = ArtistSummary(id: '1', name: 'Artist 1', imageUrl: '');
      const a2 = ArtistSummary(id: '2', name: 'Artist 2', imageUrl: '');
      const a3 = ArtistSummary(id: '3', name: 'Artist 3', imageUrl: '');
      const a4 = ArtistSummary(id: '4', name: 'Artist 4', imageUrl: '');
      const a5 = ArtistSummary(id: '5', name: 'Artist 5', imageUrl: '');

      // 0 artists
      var state = const OnboardingState(selectedArtists: []);
      expect(state.canContinue, isFalse);
      expect(state.counterText, equals('0 of 5 selected'));

      // 2 artists (< 3)
      state = const OnboardingState(selectedArtists: [a1, a2]);
      expect(state.canContinue, isFalse);
      expect(state.counterText, equals('2 of 5 selected'));

      // 3 artists (Valid)
      state = const OnboardingState(selectedArtists: [a1, a2, a3]);
      expect(state.canContinue, isTrue);
      expect(state.counterText, equals('3 of 5 selected'));

      // 5 artists (Valid max)
      state = const OnboardingState(selectedArtists: [a1, a2, a3, a4, a5]);
      expect(state.canContinue, isTrue);
      expect(state.counterText, equals('5 of 5 selected'));
    });
  });

  group('ListeningEvent Tests', () {
    test('ListeningEvent model serialization and deserialization', () {
      final event = ListeningEvent(
        id: 'evt_1',
        trackId: 'yt_abc',
        source: 'youtube',
        title: 'Clocks',
        artist: 'Coldplay',
        listenedSec: 180,
        durationSec: 300,
        completionRatio: 0.6,
        timestamp: DateTime.now(),
      );

      final map = event.toMap();
      expect(map['trackId'], equals('yt_abc'));
      expect(map['title'], equals('Clocks'));
      expect(map['artist'], equals('Coldplay'));
      expect(map['completionRatio'], closeTo(0.6, 0.01));

      final restored = ListeningEvent.fromMap('evt_1', map);
      expect(restored.id, equals('evt_1'));
      expect(restored.title, equals('Clocks'));
      expect(restored.durationSec, equals(300));
      expect(restored.completionRatio, closeTo(0.6, 0.01));
    });
  });

  group('Recommendation Aggregator Tests', () {
    test('RecommendationSections holds separate deduplicated shelves', () {
      const coldplay = ArtistSummary(id: '1', name: 'Coldplay', imageUrl: '');
      const oasis = ArtistSummary(id: '2', name: 'Oasis', imageUrl: '');

      final sections = RecommendationSections(
        favoriteArtists: const [coldplay, oasis],
        fromYourArtists: const [],
        relatedArtists: const [],
        discoverMore: const [],
        recentlyPlayed: const [],
      );

      expect(sections.favoriteArtists, hasLength(2));
      expect(sections.fromYourArtists, isEmpty);
      expect(sections.discoverMore, isEmpty);
    });
  });
}
