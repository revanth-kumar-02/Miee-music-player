import 'package:flutter_test/flutter_test.dart';
import 'package:audio_service/audio_service.dart';
import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/core/audio/youtube_audio_service.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Predictive Stream Caching & Prefetch Invariants', () {
    test('YouTubeAudioService prefetchStreamUrl executes safely on empty/invalid input', () async {
      final ytService = YouTubeAudioService();
      
      // Prefetching an empty or invalid ID should safely return without throwing
      await expectLater(ytService.prefetchStreamUrl(''), completes);
      await expectLater(ytService.prefetchStreamUrl('short'), completes);
    });

    test('AudioHandler predictive prefetch algorithm triggers cleanly for upcoming track', () async {
      final handler = MieeAudioHandler();

      const track1 = Track(
        id: 'youtube_dQw4w9WgXcQ',
        title: 'Song 1',
        artist: 'Artist 1',
        imageUrl: '',
        duration: '04:00', // 240 seconds
      );
      const track2 = Track(
        id: 'youtube_oHg5SJYRHA0',
        title: 'Song 2',
        artist: 'Artist 2',
        imageUrl: '',
        duration: '03:30',
      );

      await handler.appendTrack(track1);
      await handler.appendTrack(track2);
      expect(handler.currentQueue.length, 2);

      // Emulate track1 metadata with duration 240 seconds
      handler.mediaItem.add(MediaItem(
        id: track1.id,
        title: track1.title,
        artist: track1.artist,
        duration: const Duration(seconds: 240),
      ));

      // Jump to track 0
      handler.jumpToIndex(0);
      expect(handler.currentIndex, 0);

      // Verify position updates at 50% (120s) and 80% (192s) complete without error
      expect(() {
        handler.playbackState.add(
          handler.playbackState.value.copyWith(
            updatePosition: const Duration(seconds: 120),
          ),
        );
      }, returnsNormally);

      expect(() {
        handler.playbackState.add(
          handler.playbackState.value.copyWith(
            updatePosition: const Duration(seconds: 195),
          ),
        );
      }, returnsNormally);

      await handler.disposeHandler();
    });
  });
}
