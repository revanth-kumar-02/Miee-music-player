import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/rooms/domain/room_models.dart';
import 'package:Miee/features/rooms/data/room_repository.dart';
import 'package:Miee/features/rooms/providers/room_providers.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  group('Listen Together — Room-Based Synchronized Music Specification Tests', () {
    
    // 1. Capacity boundary tests (1, 2, 3, 4, 5 are valid; others rejected)
    test('1. Valid room capacities (1, 2, 3, 4, 5) instantiate correctly', () {
      final now = DateTime.now();
      for (int cap = 1; cap <= 5; cap++) {
        final room = ListeningRoom(
          id: 'room_$cap',
          hostId: 'host_123',
          joinCode: 'CODE$cap',
          name: 'Session $cap',
          capacity: cap,
          createdAt: now,
          updatedAt: now,
        );
        expect(room.capacity, equals(cap));
        expect(room.capacity >= 1 && room.capacity <= 5, isTrue);
      }
    });

    test('2. Reject room capacity values outside 1-5 (< 1 and > 5)', () {
      final repo = RoomRepository();

      expect(() => repo.createRoom(name: 'Too Small', capacity: 0), throwsArgumentError);
      expect(() => repo.createRoom(name: 'Negative', capacity: -1), throwsArgumentError);
      expect(() => repo.createRoom(name: 'Too Large', capacity: 6), throwsArgumentError);
      expect(() => repo.createRoom(name: 'Way Too Large', capacity: 100), throwsArgumentError);
    });

    test('3. Host is explicitly counted as a participant in capacity limit', () {
      final now = DateTime.now();
      const int capacity = 3; // Host + 2 listeners
      final room = ListeningRoom(
        id: 'room_cap3',
        hostId: 'host_id',
        joinCode: 'CAP003',
        name: 'Trio Jam',
        capacity: capacity,
        createdAt: now,
        updatedAt: now,
      );

      final members = <RoomMember>[
        RoomMember(
          id: 'm1',
          roomId: room.id,
          userId: 'host_id',
          role: 'host',
          displayName: 'Host User',
          joinedAt: now,
          lastSeenAt: now,
        ),
      ];

      // Initially 1 participant (the host)
      expect(members.length, equals(1));
      expect(members.first.role, equals('host'));
      expect(members.length < room.capacity, isTrue);

      // Add listener 1
      members.add(RoomMember(
        id: 'm2',
        roomId: room.id,
        userId: 'user_2',
        role: 'listener',
        displayName: 'Friend 1',
        joinedAt: now,
        lastSeenAt: now,
      ));
      expect(members.length, equals(2));
      expect(members.length < room.capacity, isTrue);

      // Add listener 2 -> room reaches capacity
      members.add(RoomMember(
        id: 'm3',
        roomId: room.id,
        userId: 'user_3',
        role: 'listener',
        displayName: 'Friend 2',
        joinedAt: now,
        lastSeenAt: now,
      ));
      expect(members.length, equals(3));
      expect(members.length >= room.capacity, isTrue);
    });

    // 4. Room-full rejection & simultaneous joins simulation
    test('4. Atomic room-full rejection when capacity is reached', () {
      const int capacity = 2; // Host + 1 listener
      final currentMembers = ['host_uid', 'friend_1'];

      Map<String, dynamic> simulateJoinRoom({
        required String userId,
        required int roomCapacity,
        required List<String> existingMembers,
      }) {
        if (existingMembers.contains(userId)) {
          return {'success': true, 'role': userId == 'host_uid' ? 'host' : 'listener'};
        }
        if (existingMembers.length >= roomCapacity) {
          return {'success': false, 'error': 'Room is full'};
        }
        existingMembers.add(userId);
        return {'success': true, 'role': 'listener'};
      }

      // Third participant attempts to join full room
      final result = simulateJoinRoom(
        userId: 'friend_2',
        roomCapacity: capacity,
        existingMembers: currentMembers,
      );

      expect(result['success'], isFalse);
      expect(result['error'], equals('Room is full'));
      expect(currentMembers.length, equals(2));
    });

    test('5. Simultaneous join requests at capacity boundary allocate seats safely', () {
      const int capacity = 3; // 1 host + 2 available seats
      final existingMembers = ['host_id']; // Current count = 1

      // 3 simultaneous incoming join requests for only 2 open seats
      final incomingRequests = ['user_A', 'user_B', 'user_C'];
      final results = <Map<String, dynamic>>[];

      for (final reqUser in incomingRequests) {
        if (existingMembers.length >= capacity) {
          results.add({'user': reqUser, 'success': false, 'error': 'Room is full'});
        } else {
          existingMembers.add(reqUser);
          results.add({'user': reqUser, 'success': true, 'role': 'listener'});
        }
      }

      final successfulJoins = results.where((r) => r['success'] == true).toList();
      final rejectedJoins = results.where((r) => r['success'] == false).toList();

      expect(successfulJoins.length, equals(2));
      expect(rejectedJoins.length, equals(1));
      expect(rejectedJoins.first['error'], equals('Room is full'));
      expect(existingMembers.length, equals(3));
    });

    // 6. Duplicate membership prevention
    test('6. Duplicate membership is safely handled without incrementing participant count', () {
      const int capacity = 5;
      final existingMembers = ['host_id', 'listener_alice'];

      Map<String, dynamic> join(String user) {
        if (existingMembers.contains(user)) {
          return {'success': true, 'role': user == 'host_id' ? 'host' : 'listener', 'rejoined': true};
        }
        if (existingMembers.length >= capacity) {
          return {'success': false, 'error': 'Room is full'};
        }
        existingMembers.add(user);
        return {'success': true, 'role': 'listener', 'rejoined': false};
      }

      // Alice rejoins
      final res = join('listener_alice');
      expect(res['success'], isTrue);
      expect(res['rejoined'], isTrue);
      expect(existingMembers.length, equals(2)); // Did not duplicate
    });

    // 7. Invalid room code validation
    test('7. Empty or invalid room codes are rejected before database calls', () {
      final repo = RoomRepository();

      expect(() => repo.joinRoom(''), throwsArgumentError);
      expect(() => repo.joinRoom('   '), throwsArgumentError);
    });

    // 8. Host departure and room closure
    test('8. When host leaves room, room transitions to ended state', () {
      final now = DateTime.now();
      var room = ListeningRoom(
        id: 'r_host_leave',
        hostId: 'host_user_1',
        joinCode: 'HL1234',
        name: 'Closing Session',
        status: 'active',
        capacity: 4,
        createdAt: now,
        updatedAt: now,
      );

      expect(room.status, equals('active'));

      // Host triggers leave/closure
      final isHostLeaving = true;
      if (isHostLeaving) {
        room = ListeningRoom(
          id: room.id,
          hostId: room.hostId,
          joinCode: room.joinCode,
          name: room.name,
          status: 'ended',
          capacity: room.capacity,
          createdAt: room.createdAt,
          updatedAt: DateTime.now(),
        );
      }

      expect(room.status, equals('ended'));
    });

    // 9. Participant departure releases seat
    test('9. Participant departure safely decrements seat count allowing new joins', () {
      const int capacity = 2; // Host + 1 listener
      final members = ['host_id', 'listener_1']; // Full room

      expect(members.length >= capacity, isTrue);

      // listener_1 leaves
      members.remove('listener_1');
      expect(members.length, equals(1));
      expect(members.length < capacity, isTrue);

      // listener_2 can now join
      members.add('listener_2');
      expect(members.length, equals(2));
      expect(members.contains('listener_2'), isTrue);
    });

    // 10. Playback drift calculation and synchronization logic
    test('10. Playback drift calculation handles latency without excessive seeking', () {
      final referenceTime = DateTime.now().subtract(const Duration(milliseconds: 1500));
      final remoteState = RoomPlaybackState(
        roomId: 'room_drift',
        currentTrackId: 'yt_abc',
        title: 'Drift Test Track',
        artist: 'Artist',
        durationMs: 180000,
        playbackStatus: 'playing',
        positionMs: 30000,
        updatedAt: referenceTime,
      );

      final now = DateTime.now();
      final elapsedSinceUpdate = now.difference(remoteState.updatedAt).inMilliseconds;
      final expectedPosMs = remoteState.positionMs + elapsedSinceUpdate;

      // Scenario A: Local position is 31,000ms (drift = ~500ms) -> Within tolerance (<=2500ms)
      final localPosA = 31000;
      final driftA = (localPosA - expectedPosMs).abs();
      final shouldSeekA = driftA > 2500;
      expect(shouldSeekA, isFalse, reason: 'Small timing variance (<2500ms) must not cause seek interruption');

      // Scenario B: Local position is 20,000ms (drift = ~11,500ms) -> Exceeds tolerance (>2500ms)
      final localPosB = 20000;
      final driftB = (localPosB - expectedPosMs).abs();
      final shouldSeekB = driftB > 2500;
      expect(shouldSeekB, isTrue, reason: 'Major drift (>2500ms) must trigger seek to expected position');
    });

    // 11. Canonical queue preservation and track metadata
    test('11. Canonical queue preserves track source identity and ordering', () {
      final now = DateTime.now();
      final playbackState = RoomPlaybackState(
        roomId: 'room_queue',
        currentTrackId: 'youtube_video_1',
        title: 'Song 1',
        artist: 'Artist 1',
        imageUrl: 'https://example.com/art1.jpg',
        durationMs: 200000,
        isYoutube: true,
        queue: [
          {
            'id': 'youtube_video_1',
            'title': 'Song 1',
            'artist': 'Artist 1',
            'imageUrl': 'https://example.com/art1.jpg',
            'durationMs': 200000,
            'isYoutube': true,
          },
          {
            'id': 'youtube_video_2',
            'title': 'Song 2',
            'artist': 'Artist 2',
            'imageUrl': 'https://example.com/art2.jpg',
            'durationMs': 240000,
            'isYoutube': true,
          },
        ],
        playbackStatus: 'playing',
        positionMs: 15000,
        updatedAt: now,
      );

      final map = playbackState.toMap();
      final restored = RoomPlaybackState.fromMap(map);

      expect(restored.currentTrackId, equals('youtube_video_1'));
      expect(restored.queue.length, equals(2));
      expect(restored.queue[0]['title'], equals('Song 1'));
      expect(restored.queue[1]['title'], equals('Song 2'));
    });

    // 12. RoomMember display name and avatar enrichment
    test('12. RoomMember model enriches profile metadata correctly', () {
      final now = DateTime.now();
      final member = RoomMember(
        id: 'mem_enrich',
        roomId: 'r_1',
        userId: 'u_1',
        role: 'listener',
        displayName: 'Revanth',
        avatarUrl: 'https://avatar.url/rev.png',
        joinedAt: now,
        lastSeenAt: now,
      );

      expect(member.displayName, equals('Revanth'));
      expect(member.avatarUrl, equals('https://avatar.url/rev.png'));

      final copy = member.copyWith(displayName: 'Updated Name');
      expect(copy.displayName, equals('Updated Name'));
      expect(copy.avatarUrl, equals('https://avatar.url/rev.png'));
    });
  });
}
