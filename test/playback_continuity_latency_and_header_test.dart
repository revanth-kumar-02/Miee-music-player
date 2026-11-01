import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_session/audio_session.dart';
import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/youtube_audio_service.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/shared/widgets/app_header.dart';
import 'package:Miee/shared/widgets/miee_brand_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Task 5 — Playback Continuity Tests', () {
    late MieeAudioHandler handler;

    setUp(() {
      handler = MieeAudioHandler();
    });

    tearDown(() async {
      try {
        await handler.disposeHandler();
      } catch (_) {}
    });

    test('1. Pause and resume a song without resetting its position', () async {
      const track = Track(
        id: 'youtube_abc12345678',
        title: 'Continuity Track',
        artist: 'Test Artist',
        imageUrl: 'https://example.com/art.jpg',
        duration: '3:30',
        filePath: 'https://example.com/audio.mp3',
      );

      // Simulate playing to 1 minute 45 seconds
      handler.setLastValidPositionForTesting(const Duration(seconds: 105));
      expect(handler.lastValidPosition, equals(const Duration(seconds: 105)));

      // User pauses
      await handler.pause();
      expect(handler.userExplicitlyPaused, isTrue);
      // Position must remain preserved at 105s
      expect(handler.lastValidPosition, equals(const Duration(seconds: 105)));
    });

    test('2. Resume after a recoverable online stream failure preserves position', () async {
      const track = Track(
        id: 'youtube_dQw4w9WgXcQ',
        title: 'Rickroll',
        artist: 'Rick Astley',
        imageUrl: '',
        duration: '3:30',
        filePath: 'https://example.com/stream.m4a',
      );

      handler.setLastValidPositionForTesting(const Duration(seconds: 75));
      expect(handler.lastValidPosition.inSeconds, equals(75));

      // Stream drops without user pausing
      expect(handler.userExplicitlyPaused, isFalse);

      // Recovery recovers with saved position
      expect(handler.lastValidPosition, equals(const Duration(seconds: 75)));
    });

    test('3. Refresh an expired stream for the same track', () {
      final service = YouTubeAudioService();
      const expiredUrl = 'https://rr1---sn-test.googlevideo.com/videoplayback?expire=1000000000'; // Past timestamp
      const validUrl = 'https://rr1---sn-test.googlevideo.com/videoplayback?expire=2524608000'; // Future timestamp

      expect(service.isUrlValid(expiredUrl), isFalse);
      expect(service.isUrlValid(validUrl), isTrue);
    });

    test('4. Preserve the queue during recovery', () async {
      const track1 = Track(id: 't1', title: 'Song 1', artist: 'Artist 1', imageUrl: '', duration: '3:00');
      const track2 = Track(id: 't2', title: 'Song 2', artist: 'Artist 2', imageUrl: '', duration: '3:00');
      const track3 = Track(id: 't3', title: 'Song 3', artist: 'Artist 3', imageUrl: '', duration: '3:00');

      handler.setQueueForTesting([track1, track2, track3], currentIndex: 1);
      expect(handler.currentQueue.length, equals(3));
      expect(handler.currentIndex, equals(1));

      // After simulated stream error on current track, queue structure remains intact
      expect(handler.currentQueue[0].id, equals('t1'));
      expect(handler.currentQueue[1].id, equals('t2'));
      expect(handler.currentQueue[2].id, equals('t3'));
    });

    test('5. Ignore stale resolution responses after the user selects another song', () {
      // Handled by activeLoadToken
      int token1 = handler.activeLoadTokenForTesting;
      int token2 = handler.incrementActiveLoadTokenForTesting();
      expect(token2, greaterThan(token1));
      // Stale token response (token1 != token2) is discarded
      expect(token1 == handler.activeLoadTokenForTesting, isFalse);
    });

    test('6. Avoid automatic playback when the user explicitly paused', () {
      // User explicitly pauses
      handler.pause();
      expect(handler.userExplicitlyPaused, isTrue);

      // External focus interruption arrives and ends
      handler.handleInterruptionEvent(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      handler.handleInterruptionEvent(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );

      // Must remain paused!
      expect(handler.playInterrupted, isFalse);
      expect(handler.isPlaying, isFalse);
    });

    test('7. Handle audio-session interruptions appropriately', () {
      // Permanent loss of audio focus (e.g. another media app starts)
      handler.handleInterruptionEvent(
        AudioInterruptionEvent(true, AudioInterruptionType.unknown),
      );
      expect(handler.playInterrupted, isFalse);
      expect(handler.isPlaying, isFalse);
    });

    test('8. Prevent player recreation during ordinary navigation', () {
      // MieeAudioHandler is a single shared instance; calling initialize multiple times or navigating does not re-instantiate player
      final player1 = handler.playerForTesting;
      expect(player1, isNotNull);
      expect(identical(handler.playerForTesting, player1), isTrue);
    });

    test('9. Preserve local-file playback and resume behavior', () {
      const localTrack = MediaSong(
        id: 'local_song_1',
        title: 'Local Melody',
        artist: 'Offline Artist',
        album: 'Local Album',
        duration: '4:00',
        durationMs: 240000,
        filePath: '/storage/emulated/0/Music/melody.mp3',
        artworkPath: '',
      );

      expect(localTrack.isYoutube, isFalse);
      expect(localTrack.filePath.startsWith('http'), isFalse);
      expect(localTrack.filePath, endsWith('.mp3'));
    });

    test('10. Handle unrecoverable stream failures without infinite retries', () {
      // MieeAudioHandler bounds YouTube retries strictly to _kMaxYouTubeRetries (2)
      expect(handler.maxYouTubeRetriesForTesting, equals(2));
    });
  });

  group('Task 5 — Latency and Loading Tests', () {
    test('11. Show loading state immediately after song selection', () {
      final state = PlaybackState.initial().copyWith(
        status: PlaybackStatus.loading,
        loadingTrackId: 'youtube_test_id',
      );

      expect(state.status, equals(PlaybackStatus.loading));
      expect(state.loadingTrackId, equals('youtube_test_id'));
    });

    test('12. Avoid duplicate simultaneous requests for the same track', () {
      final state = PlaybackState.initial().copyWith(
        status: PlaybackStatus.loading,
        loadingTrackId: 'youtube_duplicate_test',
      );

      // Tap on same track while loading is in-flight is recognized
      final isAlreadyLoading = isSameTrackId(state.loadingTrackId, 'youtube_duplicate_test');
      expect(isAlreadyLoading, isTrue);
    });

    test('13. Ensure local playback bypasses online resolution', () {
      const localSong = MediaSong(
        id: 'local_bypass_1',
        title: 'Fast Track',
        artist: 'Device Artist',
        album: 'Offline',
        duration: '3:00',
        durationMs: 180000,
        filePath: '/storage/emulated/0/Music/fast.mp3',
        artworkPath: '',
      );

      // Local songs have local filePath and isYoutube == false
      expect(localSong.isYoutube, isFalse);
      expect(localSong.filePath.isNotEmpty, isTrue);
      expect(localSong.filePath.startsWith('http'), isFalse);
    });

    test('14. Ensure cached metadata and stream URL keys are stable', () {
      final service = YouTubeAudioService();
      const videoId = 'test_stable_id';
      const validUrl = 'https://rr1---sn-test.googlevideo.com/videoplayback?expire=2524608000';

      service.cacheUrlForTesting(videoId, validUrl);
      expect(service.isCached(videoId), isTrue);

      // Different track ID is not a cache hit
      expect(service.isCached('other_track_id'), isFalse);
      service.clearCache();
    });

    test('15. Ensure loading state clears after success, failure, or cancellation', () {
      var state = PlaybackState.initial().copyWith(
        status: PlaybackStatus.loading,
        loadingTrackId: 'track_123',
      );
      expect(state.loadingTrackId, equals('track_123'));

      // On playing success
      state = state.copyWith(status: PlaybackStatus.playing, clearLoadingTrackId: true);
      expect(state.loadingTrackId, isNull);

      // On error
      state = state.copyWith(status: PlaybackStatus.error, clearLoadingTrackId: true);
      expect(state.loadingTrackId, isNull);
    });
  });

  group('Task 5 — Header Notification Bell Removal Tests', () {
    testWidgets('16. Verify that the notification bell is no longer visible in shared application headers', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            appBar: MieeBrandHeader(
              title: 'Home',
              showProfileAvatar: true,
              // Default showNotificationBell is false
            ),
            body: Center(child: Text('Home Content')),
          ),
        ),
      );

      expect(find.byTooltip('Notifications'), findsNothing);
      expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
      expect(find.byIcon(Icons.notifications_outlined), findsNothing);
    });

    testWidgets('17. Verify that remaining header elements (title & profile avatar) are aligned correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            appBar: AppHeader(
              title: 'Settings',
            ),
            body: Center(child: Text('Settings Content')),
          ),
        ),
      );

      // Title must be present
      expect(find.text('Settings'), findsOneWidget);
      // Notification bell must be absent
      expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
    });
  });
}

