import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/core/audio/audio_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaItem & Player Duration Synchronization Tests', () {
    test('1. Genuine duration takes precedence over 3:30 placeholder in MediaItem conversion', () {
      final handler = MieeAudioHandler();

      // Track with dummy 3:30 duration
      final dummyTrack = Track(
        id: 'youtube_video_123',
        title: 'Kadhal En Kadhal - 8K',
        artist: 'Dhanush',
        duration: '3:30',
        imageUrl: 'https://i.ytimg.com/vi/video_123/hqdefault.jpg',
        filePath: '',
      );

      // Convert with ground-truth override from audio container (5:36 = 336s)
      final mediaItem = handler.trackToMediaItemForTesting(
        dummyTrack,
        overrideDuration: const Duration(minutes: 5, seconds: 36),
      );

      expect(mediaItem.id, equals('youtube_video_123'));
      expect(mediaItem.title, equals('Kadhal En Kadhal - 8K'));
      expect(mediaItem.artist, equals('Dhanush'));
      expect(mediaItem.duration, equals(const Duration(minutes: 5, seconds: 36)),
          reason: 'MediaItem duration must be 5:36 and not the 3:30 placeholder');
    });

    test('1b. Unresolved 3:30 placeholder does not leak into MediaItem.duration', () {
      final handler = MieeAudioHandler();

      final dummyTrack = Track(
        id: 'youtube_video_placeholder',
        title: 'Kadhal En Kadhal - 8K',
        artist: 'Dhanush',
        duration: '3:30',
        imageUrl: '',
        filePath: '',
      );

      // Convert without overrideDuration or loaded player
      final mediaItem = handler.trackToMediaItemForTesting(dummyTrack);

      expect(mediaItem.duration, isNull,
          reason: 'Dummy 3:30 placeholder must NEVER become MediaItem.duration');
    });

    test('2. Real duration is preserved when track has explicit duration like 5:36', () {
      final handler = MieeAudioHandler();

      final fullTrack = Track(
        id: 'youtube_video_456',
        title: 'Rowdy Baby',
        artist: 'Dhanush',
        duration: '5:36',
        imageUrl: 'https://i.ytimg.com/vi/video_456/hqdefault.jpg',
        filePath: '',
      );

      final mediaItem = handler.trackToMediaItemForTesting(fullTrack);
      expect(mediaItem.duration, equals(const Duration(minutes: 5, seconds: 36)));
    });

    test('3. Local MediaSong duration is converted accurately to MediaItem duration', () {
      final handler = MieeAudioHandler();

      final localSong = MediaSong(
        id: 'local_789',
        title: 'Mayakkam Enna',
        artist: 'Dhanush',
        album: 'Mayakkam Enna',
        durationMs: 336000, // 5:36
        duration: '5:36',
        artworkPath: '/music/artwork.jpg',
        filePath: '/storage/emulated/0/Music/mayakkam.mp3',
      );

      final mediaItem = handler.trackToMediaItemForTesting(localSong);
      expect(mediaItem.duration, equals(const Duration(minutes: 5, seconds: 36)));
      expect(mediaItem.album, equals('Mayakkam Enna'));
    });

    test('4. Duration update updates MediaItem stream value without losing metadata', () {
      final handler = MieeAudioHandler();

      final initialItem = MediaItem(
        id: 'youtube_111',
        title: 'Kadhal En Kadhal - 8K',
        artist: 'Dhanush',
        album: 'Mayakkam Enna',
        duration: const Duration(minutes: 3, seconds: 30),
      );
      handler.mediaItem.add(initialItem);

      // Simulate player resolving true 5:36 duration
      handler.onDurationChangedForTesting(const Duration(minutes: 5, seconds: 36));

      final updated = handler.mediaItem.value;
      expect(updated, isNotNull);
      expect(updated!.title, equals('Kadhal En Kadhal - 8K'));
      expect(updated.artist, equals('Dhanush'));
      expect(updated.album, equals('Mayakkam Enna'));
      expect(updated.duration, equals(const Duration(minutes: 5, seconds: 36)),
          reason: 'MediaItem stream value must reflect the resolved 5:36 duration');
    });

    test('5. Switching tracks resets and synchronizes duration for the new track', () {
      final handler = MieeAudioHandler();

      // Track A (5:36)
      final trackA = Track(
        id: 'track_A',
        title: 'Song A',
        artist: 'Artist A',
        duration: '5:36',
        imageUrl: '',
        filePath: '',
      );
      handler.mediaItem.add(handler.trackToMediaItemForTesting(
        trackA,
        overrideDuration: const Duration(minutes: 5, seconds: 36),
      ));
      expect(handler.mediaItem.value!.duration, equals(const Duration(minutes: 5, seconds: 36)));

      // Track B (3:45)
      final trackB = Track(
        id: 'track_B',
        title: 'Song B',
        artist: 'Artist B',
        duration: '3:45',
        imageUrl: '',
        filePath: '',
      );
      handler.mediaItem.add(handler.trackToMediaItemForTesting(
        trackB,
        overrideDuration: const Duration(minutes: 3, seconds: 45),
      ));

      expect(handler.mediaItem.value!.id, equals('track_B'));
      expect(handler.mediaItem.value!.duration, equals(const Duration(minutes: 3, seconds: 45)),
          reason: 'Track B duration must not retain Track A 5:36 duration');
    });

    test('6. Formatted placeholder variations (" 3:30 ", "03:30") are rejected from MediaItem.duration', () {
      final handler = MieeAudioHandler();

      final variants = [' 3:30 ', '03:30', '03:30 ', ' 03:30', '3:30\n', '0:00', '00:00'];
      for (final v in variants) {
        final track = Track(
          id: 'test_variant_$v',
          title: 'Kadhal En Kadhal',
          artist: 'Dhanush',
          duration: v,
          imageUrl: '',
          filePath: '',
        );
        final item = handler.trackToMediaItemForTesting(track);
        expect(item.duration, isNull,
            reason: 'Variant "$v" must be identified as placeholder and rejected');
      }
    });

    test('7. Resolved container ground truth updates mediaItem even if mediaItem initially held old track', () {
      final handler = MieeAudioHandler();

      // Initial mediaItem points to old track
      final oldItem = MediaItem(
        id: 'old_track',
        title: 'Old Song',
        artist: 'Old Artist',
        duration: const Duration(minutes: 3, seconds: 30),
      );
      handler.mediaItem.add(oldItem);

      // Now set up active queue with new track
      final newTrack = Track(
        id: 'new_track_yt',
        title: 'Kadhal En Kadhal - 8K',
        artist: 'Dhanush',
        duration: '',
        imageUrl: '',
        filePath: '',
      );
      handler.setQueueForTesting([newTrack], currentIndex: 0);

      // Ground truth duration resolves (5:36)
      handler.onDurationChangedForTesting(const Duration(minutes: 5, seconds: 36));

      // MediaItem must now be updated with the active track (Kadhal En Kadhal - 8K) and 5:36!
      final updated = handler.mediaItem.value;
      expect(updated, isNotNull);
      expect(updated!.id, equals('new_track_yt'));
      expect(updated.title, equals('Kadhal En Kadhal - 8K'));
      expect(updated.artist, equals('Dhanush'));
      expect(updated.duration, equals(const Duration(minutes: 5, seconds: 36)),
          reason: 'MediaItem must rebind to active track and real 5:36 duration');
    });
  });
}
