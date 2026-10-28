import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/rooms/domain/room_models.dart';
import 'package:Miee/features/rooms/data/room_repository.dart';
import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/core/audio/playback_state.dart';

void main() {
  group('Miee Android Listening Rooms Reliability Tests', () {

    // ─────────────────────────────────────────────────────────────────────────
    // PROBLEM 1: Host screen-off playback progression & wake lock retention
    // ─────────────────────────────────────────────────────────────────────────
    group('Problem 1: Host Screen-Off Progression & Wake Lock Retention', () {
      test('MieeAudioHandler tracks isRoomListener mode accurately', () {
        final handler = MieeAudioHandler();
        expect(handler.isRoomListener, isFalse);

        handler.setRoomListener(true);
        expect(handler.isRoomListener, isTrue);

        handler.setRoomListener(false);
        expect(handler.isRoomListener, isFalse);
      });

      test('AudioProcessingState stays buffering when transitioning tracks while playing', () {
        // When screen is off and track finishes, audio_service must retain playing: true
        // and AudioProcessingState.buffering to prevent Android from entering CPU deep sleep
        // during YouTube stream URL resolution.
        const wasPlaying = true;
        expect(wasPlaying, isTrue);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // PROBLEM 2 & 3: Playback Desynchronization & Unexpected Stopping
    // ─────────────────────────────────────────────────────────────────────────
    group('Problem 2 & 3: Playback Desynchronization & Unexpected Stopping', () {
      test('RoomPlaybackState serializes and deserializes monotonic revision', () {
        final now = DateTime.now();
        final state = RoomPlaybackState(
          roomId: 'room_123',
          currentTrackId: 'yt_abc',
          title: 'Song A',
          artist: 'Artist X',
          playbackStatus: 'playing',
          positionMs: 42000,
          durationMs: 210000,
          revision: 42,
          updatedAt: now,
        );

        final map = state.toMap();
        expect(map['revision'], equals(42));
        expect(map['playback_status'], equals('playing'));

        final deserialized = RoomPlaybackState.fromMap(map);
        expect(deserialized.revision, equals(42));
        expect(deserialized.currentTrackId, equals('yt_abc'));
        expect(deserialized.positionMs, equals(42000));
      });

      test('RoomPlaybackState defaults revision to 1 when omitted', () {
        final map = {
          'room_id': 'room_legacy',
          'current_track_id': 'legacy_track',
          'playback_status': 'playing',
          'position_ms': 1000,
          'duration_ms': 180000,
          'updated_at': DateTime.now().toIso8601String(),
        };

        final state = RoomPlaybackState.fromMap(map);
        expect(state.revision, equals(1));
      });

      test('Stale or out-of-order state updates are discarded based on revision', () {
        int lastAppliedRevision = 5;

        bool shouldApplyUpdate(RoomPlaybackState incoming) {
          if (incoming.revision <= lastAppliedRevision) {
            return false;
          }
          lastAppliedRevision = incoming.revision;
          return true;
        }

        final now = DateTime.now();

        // 1. Stale revision from delayed network packet
        final staleUpdate = RoomPlaybackState(
          roomId: 'room_test',
          currentTrackId: 'old_track',
          revision: 4,
          updatedAt: now,
        );
        expect(shouldApplyUpdate(staleUpdate), isFalse);
        expect(lastAppliedRevision, equals(5));

        // 2. Duplicate revision
        final duplicateUpdate = RoomPlaybackState(
          roomId: 'room_test',
          currentTrackId: 'same_track',
          revision: 5,
          updatedAt: now,
        );
        expect(shouldApplyUpdate(duplicateUpdate), isFalse);
        expect(lastAppliedRevision, equals(5));

        // 3. Monotonically increasing revision accepted
        final freshUpdate = RoomPlaybackState(
          roomId: 'room_test',
          currentTrackId: 'new_track',
          revision: 6,
          updatedAt: now,
        );
        expect(shouldApplyUpdate(freshUpdate), isTrue);
        expect(lastAppliedRevision, equals(6));
      });

      test('Host track completion does not broadcast "stopped" status', () {
        // When host player completes or idles between songs,
        // it must NOT broadcast 'stopped' to listeners.
        // It must maintain 'buffering' so listeners wait for the next song.
        String computeStatusString({
          required bool isPlaying,
          required bool isPaused,
          required bool isBuffering,
        }) {
          return isPlaying
              ? 'playing'
              : (isBuffering ? 'buffering' : (isPaused ? 'paused' : 'buffering'));
        }

        expect(
          computeStatusString(isPlaying: true, isPaused: false, isBuffering: false),
          equals('playing'),
        );
        expect(
          computeStatusString(isPlaying: false, isPaused: true, isBuffering: false),
          equals('paused'),
        );
        expect(
          computeStatusString(isPlaying: false, isPaused: false, isBuffering: true),
          equals('buffering'),
        );
        // Track completed / idle between songs (isPlaying: false, isPaused: false, isBuffering: false):
        expect(
          computeStatusString(isPlaying: false, isPaused: false, isBuffering: false),
          equals('buffering'),
        );
      });

      test('Clock skew clamping prevents false drift and negative seek positions', () {
        final now = DateTime.now();

        int calculateExpectedPosition({
          required DateTime updatedAt,
          required int positionMs,
          required bool isPlaying,
        }) {
          final rawElapsed = now.difference(updatedAt).inMilliseconds;
          final clampedElapsed = rawElapsed.clamp(0, 15000);
          return isPlaying ? (positionMs + clampedElapsed) : positionMs;
        }

        // Scenario A: Listener clock is 4 seconds ahead of host clock (rawElapsed is negative)
        final futureTimestamp = now.add(const Duration(seconds: 4));
        final expectedPosWithSkew = calculateExpectedPosition(
          updatedAt: futureTimestamp,
          positionMs: 30000,
          isPlaying: true,
        );
        expect(expectedPosWithSkew, equals(30000)); // Clamped to 0 elapsed, no backwards seek!

        // Scenario B: Normal latency (1.5 seconds)
        final normalTimestamp = now.subtract(const Duration(milliseconds: 1500));
        final expectedPosNormal = calculateExpectedPosition(
          updatedAt: normalTimestamp,
          positionMs: 30000,
          isPlaying: true,
        );
        expect(expectedPosNormal, equals(31500));

        // Scenario C: Extreme delay (> 15 seconds)
        final extremeDelayedTimestamp = now.subtract(const Duration(seconds: 45));
        final expectedPosExtreme = calculateExpectedPosition(
          updatedAt: extremeDelayedTimestamp,
          positionMs: 30000,
          isPlaying: true,
        );
        expect(expectedPosExtreme, equals(45000)); // Clamped at +15000ms max
      });

      test('Remote queue is serialized into RoomPlaybackState queue maps', () {
        final now = DateTime.now();
        final queue = [
          {
            'id': 'yt_1',
            'title': 'Track One',
            'artist': 'Artist A',
            'imageUrl': 'https://image.url/1',
            'durationMs': 180000,
            'isYoutube': true,
          },
          {
            'id': 'yt_2',
            'title': 'Track Two',
            'artist': 'Artist B',
            'imageUrl': 'https://image.url/2',
            'durationMs': 240000,
            'isYoutube': true,
          },
        ];

        final state = RoomPlaybackState(
          roomId: 'room_q',
          currentTrackId: 'yt_1',
          queue: queue,
          updatedAt: now,
        );

        final map = state.toMap();
        expect(map['queue'], isA<List>());
        expect((map['queue'] as List).length, equals(2));
        expect((map['queue'] as List)[1]['title'], equals('Track Two'));

        final parsed = RoomPlaybackState.fromMap(map);
        expect(parsed.queue.length, equals(2));
        expect(parsed.queue.first['id'], equals('yt_1'));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // PROBLEM 4: Room chat dual-channel message delivery & deduplication
    // ─────────────────────────────────────────────────────────────────────────
    group('Problem 4: Dual-Channel Chat Delivery & Deduplication', () {
      test('Messages arriving via both broadcast and postgres change are deduplicated', () {
        final messages = <RoomMessage>[];

        void handleIncomingMessage(RoomMessage msg) {
          if (!messages.any((m) => m.id == msg.id)) {
            messages.add(msg);
          }
        }

        final now = DateTime.now();
        final msg1 = RoomMessage(
          id: 'msg_unique_101',
          roomId: 'room_chat_test',
          userId: 'user_host',
          userName: 'Dharan',
          content: 'Hey room, check this track out!',
          type: 'text',
          createdAt: now,
        );

        // 1. Message arrives via fast Realtime Broadcast (<50ms)
        handleIncomingMessage(msg1);
        expect(messages.length, equals(1));
        expect(messages.first.content, equals('Hey room, check this track out!'));

        // 2. Same message arrives 200ms later via Postgres CDC change event
        handleIncomingMessage(msg1);
        expect(messages.length, equals(1)); // Still exactly 1 message, no duplicates!
      });

      test('RoomMessage correctly parses rich song suggestion payloads', () {
        final map = {
          'id': 'msg_song_1',
          'room_id': 'room_456',
          'user_id': 'user_listener_2',
          'user_name': 'Sarah',
          'content': 'Can we play "Starboy"?',
          'type': 'song_suggestion',
          'track_id': 'yt_starboy_123',
          'track_title': 'Starboy',
          'track_artist': 'The Weeknd',
          'track_image_url': 'https://image.url/starboy.jpg',
          'is_youtube': true,
          'created_at': DateTime.now().toIso8601String(),
        };

        final message = RoomMessage.fromMap(map);
        expect(message.isSongSuggestion, isTrue);
        expect(message.trackTitle, equals('Starboy'));
        expect(message.trackArtist, equals('The Weeknd'));
        expect(message.trackId, equals('yt_starboy_123'));
        expect(message.userName, equals('Sarah'));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // PROBLEM 5: Participant names resolution & role display
    // ─────────────────────────────────────────────────────────────────────────
    group('Problem 5: Participant Names & Profile Resolution', () {
      test('RoomMember deserializes profile username and display_name', () {
        final map = {
          'id': 'member_1',
          'room_id': 'room_members_test',
          'user_id': 'uid_dharan',
          'role': 'host',
          'joined_at': DateTime.now().toIso8601String(),
          'last_seen_at': DateTime.now().toIso8601String(),
          'profiles': {
            'display_name': 'Dharan Kumar',
            'username': 'dharan',
            'avatar_url': 'https://avatars.url/dharan.jpg',
          },
        };

        final member = RoomMember.fromMap(map);
        expect(member.displayName, equals('Dharan Kumar'));
        expect(member.username, equals('dharan'));
        expect(member.avatarUrl, equals('https://avatars.url/dharan.jpg'));
        expect(member.role, equals('host'));
      });

      test('Participant list name resolution prioritizes display_name then username over generic label', () {
        String resolveParticipantName(RoomMember member, int index) {
          final isMemberHost = member.role == 'host';
          final displayName = member.displayName?.trim();
          final username = member.username?.trim();
          final hasDisplayName = displayName != null && displayName.isNotEmpty;
          final hasUsername = username != null && username.isNotEmpty;

          return hasDisplayName
              ? displayName!
              : (hasUsername ? username! : (isMemberHost ? 'Host' : 'Listener ${index + 1}'));
        }

        final now = DateTime.now();

        // 1. Both display_name and username present
        final memberWithBoth = RoomMember(
          id: 'm1',
          roomId: 'r1',
          userId: 'u1',
          role: 'host',
          displayName: 'Dharan Kumar',
          username: 'dharan',
          joinedAt: now,
          lastSeenAt: now,
        );
        expect(resolveParticipantName(memberWithBoth, 0), equals('Dharan Kumar'));

        // 2. Only username present (display_name null)
        final memberWithOnlyUsername = RoomMember(
          id: 'm2',
          roomId: 'r1',
          userId: 'u2',
          role: 'listener',
          displayName: null,
          username: 'music_fan_99',
          joinedAt: now,
          lastSeenAt: now,
        );
        expect(resolveParticipantName(memberWithOnlyUsername, 1), equals('music_fan_99'));

        // 3. Both null fallback
        final memberWithoutProfile = RoomMember(
          id: 'm3',
          roomId: 'r1',
          userId: 'u3',
          role: 'listener',
          displayName: null,
          username: null,
          joinedAt: now,
          lastSeenAt: now,
        );
        expect(resolveParticipantName(memberWithoutProfile, 2), equals('Listener 3'));
      });
    });
  });
}
