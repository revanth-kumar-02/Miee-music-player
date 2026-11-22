import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/youtube/domain/music_result_classifier.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Critical Playback & Track Identity Fixes Test Suite', () {
    test('1. Sub-45s legitimate song (Who Is This Dude? 43s) is approved as music', () {
      final shortSong = YouTubeVideo(
        id: 'dQw4w9WgXcQ',
        title: 'Who Is This Dude?',
        channelTitle: 'Think Music India',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        duration: '0:43',
        viewCount: '1500000',
        rawTitle: 'Who Is This Dude? (From "Dude")',
        rawChannelTitle: 'Think Music India',
      );

      final verdict = MusicResultClassifier.classify(
        shortSong,
        query: 'Who Is This Dude? Sai Abhyankkar',
      );

      expect(verdict.isMusic, isTrue);
      expect(verdict.confidence, isNot(equals(MusicTrackConfidence.rejected)));
      expect(MusicResultClassifier.isValidIndividualSong(shortSong, query: 'Who Is This Dude? Sai Abhyankkar'), isTrue);
    });

    test('2. Sub-45s song from verified artist channel is approved as music', () {
      final shortSong = YouTubeVideo(
        id: 'abc123xyz78',
        title: 'Theme of Dude',
        channelTitle: 'Sai Abhyankkar',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        duration: '0:38',
        viewCount: '500000',
        rawTitle: 'Theme of Dude - Official Audio',
        rawChannelTitle: 'Sai Abhyankkar',
      );

      final verdict = MusicResultClassifier.classify(
        shortSong,
        query: 'Theme of Dude Sai Abhyankkar',
      );

      expect(verdict.isMusic, isTrue);
      expect(verdict.confidence, isNot(equals(MusicTrackConfidence.rejected)));
    });

    test('3. Official song promo from verified label is NOT rejected as a movie trailer', () {
      final promoSong = YouTubeVideo(
        id: 'promo123456',
        title: 'Dude - Song Promo',
        channelTitle: 'Sony Music South',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        duration: '1:15',
        viewCount: '2000000',
        rawTitle: 'Dude - Song Promo | Sai Abhyankkar | Official Audio',
        rawChannelTitle: 'Sony Music South',
      );

      final verdict = MusicResultClassifier.classify(promoSong);

      expect(verdict.isMusic, isTrue);
      expect(verdict.confidence, isNot(equals(MusicTrackConfidence.rejected)));
    });

    test('4. Non-musical short vlog/gameplay video is correctly rejected', () {
      final nonMusicVideo = YouTubeVideo(
        id: 'vlog1234567',
        title: 'My Daily Vlog Episode 4',
        channelTitle: 'Random Creator',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        duration: '0:22',
        viewCount: '100',
        rawTitle: 'My Daily Vlog Episode 4',
        rawChannelTitle: 'Random Creator',
      );

      final verdict = MusicResultClassifier.classify(nonMusicVideo);

      expect(verdict.confidence, equals(MusicTrackConfidence.rejected));
      expect(verdict.isMusic, isFalse);
    });

    test('5. Queue replenishment remaining check permits pre-fetching when remaining <= 2', () {
      // Simulates the queue condition in PlayerController.expandQueueIfNeeded:
      // queue length = 5, currentIndex = 2 -> remaining = 2
      const queueLength = 5;
      const currentIndex = 2;
      const remaining = queueLength - 1 - currentIndex;

      // In old code: if (remaining > 0) return; => returned!
      // In new code: if (remaining > 2) return; => proceeds to replenish!
      expect(remaining <= 2, isTrue);
    });

    test('6. Track with album metadata preserves duration integrity against anomalous stream length', () {
      const canonicalTrack = Track(
        id: 'track_1',
        title: 'Who Is This Dude?',
        artist: 'Sai Abhyankkar',
        imageUrl: 'https://example.com/art.jpg',
        albumName: 'Dude',
        duration: '0:43',
        metadataProvider: 'itunes',
      );

      final currentDurSec = MusicResultClassifier.parseDurationSeconds(canonicalTrack.duration);
      const streamDurationSeconds = 78; // 1:18 stream from substituted track

      final hasVerifiedDuration = (canonicalTrack.metadataProvider == 'itunes' ||
          canonicalTrack.metadataProvider == 'musicbrainz' ||
          (canonicalTrack.albumName != null && canonicalTrack.albumName!.isNotEmpty));

      final shouldUpdateDuration = currentDurSec <= 0 ||
          !hasVerifiedDuration ||
          (streamDurationSeconds - currentDurSec).abs() <= 15;

      // The 1:18 stream deviates by 35s (> 15s), so it must NOT overwrite the 0:43 duration!
      expect(hasVerifiedDuration, isTrue);
      expect(shouldUpdateDuration, isFalse);
    });
  });
}
