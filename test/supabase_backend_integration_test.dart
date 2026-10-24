import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/rooms/domain/room_models.dart';
import 'package:Miee/features/rooms/data/room_repository.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/profile/data/supabase_user_profile_repository.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  group('Supabase Room Domain & Logic Tests', () {
    test('ListeningRoom model serializes and deserializes correctly', () {
      final now = DateTime.now();
      final room = ListeningRoom(
        id: 'room_101',
        hostId: 'host_uuid',
        joinCode: 'ABC123',
        name: 'Late Night Chill',
        status: 'active',
        capacity: 4,
        createdAt: now,
        updatedAt: now,
      );

      final map = room.toMap();
      expect(map['id'], equals('room_101'));
      expect(map['host_id'], equals('host_uuid'));
      expect(map['join_code'], equals('ABC123'));
      expect(map['name'], equals('Late Night Chill'));
      expect(map['status'], equals('active'));
      expect(map['capacity'], equals(4));

      final restored = ListeningRoom.fromMap(map);
      expect(restored.id, equals(room.id));
      expect(restored.hostId, equals(room.hostId));
      expect(restored.joinCode, equals(room.joinCode));
      expect(restored.capacity, equals(4));
    });

    test('Room capacity boundaries are strictly enforced (1-5)', () {
      final repo = RoomRepository();

      // Test lower boundary violation
      expect(
        () => repo.createRoom(name: 'Invalid Low', capacity: 0),
        throwsArgumentError,
      );

      // Test upper boundary violation
      expect(
        () => repo.createRoom(name: 'Invalid High', capacity: 6),
        throwsArgumentError,
      );

      // Test empty join code
      expect(
        () => repo.joinRoom('   '),
        throwsArgumentError,
      );
    });

    test('RoomMember model validates host and listener roles', () {
      final now = DateTime.now();
      final memberHost = RoomMember(
        id: 'mem_1',
        roomId: 'room_101',
        userId: 'user_host',
        role: 'host',
        joinedAt: now,
        lastSeenAt: now,
      );

      expect(memberHost.role, equals('host'));

      final memberListener = RoomMember.fromMap({
        'id': 'mem_2',
        'room_id': 'room_101',
        'user_id': 'user_listener',
        'role': 'listener',
        'joined_at': now.toIso8601String(),
        'last_seen_at': now.toIso8601String(),
      });

      expect(memberListener.role, equals('listener'));
      expect(memberListener.userId, equals('user_listener'));
    });

    test('RoomPlaybackState handles canonical queue and playback state', () {
      final now = DateTime.now();
      final state = RoomPlaybackState(
        roomId: 'room_101',
        currentTrackId: 'youtube_abc123',
        title: 'Starboy',
        artist: 'The Weeknd',
        imageUrl: 'https://img.youtube.com/vi/abc123/0.jpg',
        durationMs: 230000,
        isYoutube: true,
        queue: [
          {'id': 't1', 'title': 'Blinding Lights'},
          {'id': 't2', 'title': 'Save Your Tears'},
        ],
        playbackStatus: 'playing',
        positionMs: 45000,
        updatedAt: now,
        updatedBy: 'host_uuid',
      );

      final map = state.toMap();
      expect(map['playback_status'], equals('playing'));
      expect(map['position_ms'], equals(45000));
      expect(map['queue'], hasLength(2));

      final restored = RoomPlaybackState.fromMap(map);
      expect(restored.currentTrackId, equals('youtube_abc123'));
      expect(restored.title, equals('Starboy'));
      expect(restored.artist, equals('The Weeknd'));
      expect(restored.queue, hasLength(2));
      expect(restored.playbackStatus, equals('playing'));
    });
  });

  group('Supabase Profile & Onboarding Tests', () {
    test('Onboarding requires between 3 and 5 favorite artists', () {
      final repo = SupabaseUserProfileRepository();

      // Less than 3 artists
      expect(
        () => repo.completeOnboarding(
          uid: 'user_1',
          artists: [
            const ArtistSummary(id: '1', name: 'Queen', imageUrl: ''),
            const ArtistSummary(id: '2', name: 'ABBA', imageUrl: ''),
          ],
        ),
        throwsArgumentError,
      );

      // More than 5 artists
      expect(
        () => repo.completeOnboarding(
          uid: 'user_1',
          artists: List.generate(
            6,
            (i) => ArtistSummary(id: '$i', name: 'Artist $i', imageUrl: ''),
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Track & Liked Songs Model Validation', () {
    test('Track model instantiates correctly for liked songs', () {
      const track = Track(
        id: 'youtube_track_001',
        title: 'Midnight City',
        artist: 'M83',
        imageUrl: 'https://example.com/cover.jpg',
        duration: '4:03',
        filePath: 'https://youtube.com/watch?v=track_001',
      );

      expect(track.id, equals('youtube_track_001'));
      expect(track.title, equals('Midnight City'));
      expect(track.artist, equals('M83'));
      expect(track.isYoutube, isTrue);
    });
  });
}
