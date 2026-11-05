import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/youtube/domain/music_result_classifier.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';

void main() {
  group('Instrumental, Theme Tracks and Resolution Tests', () {
    test('Dileep Theme (Instrumental) is classified as valid individual song', () {
      final candidate = const YouTubeVideo(
        id: 'vGZYZN5VL8Y',
        title: 'Dileep Theme (Instrumental)',
        channelTitle: 'Anirudh Ravichander',
        thumbnailUrl: '',
        duration: '1:13',
        viewCount: '100K views',
        rawTitle: 'Dileep Theme (Instrumental)',
        rawChannelTitle: 'Anirudh Ravichander',
      );

      final query = 'Dileep Theme (Instrumental) Anirudh Ravichander';
      final verdict = MusicResultClassifier.classify(
        candidate,
        query: query,
        forIndividualPlayback: true,
        enableLogging: true,
      );

      expect(verdict.isMusic, isTrue);
      final isValid = MusicResultClassifier.isValidIndividualSong(candidate, query: query);
      expect(isValid, isTrue, reason: 'Legitimate theme track by composer should be valid for individual playback');
    });

    test('The Wild Theme is classified as valid individual song', () {
      final candidate = const YouTubeVideo(
        id: 'gfD0-JcHaK4',
        title: 'The Wild Theme (From "OM Chapter 1: Udhiram The Blood Wood")',
        channelTitle: 'phanith bhairapuram',
        thumbnailUrl: '',
        duration: '1:56',
        viewCount: '50K views',
        rawTitle: 'The Wild Theme (From "OM Chapter 1: Udhiram The Blood Wood")',
        rawChannelTitle: 'phanith bhairapuram',
      );

      final query = 'The Wild Theme (From OM Chapter 1: Udhiram - The Blood Wood)';
      final verdict = MusicResultClassifier.classify(
        candidate,
        query: query,
        forIndividualPlayback: true,
        enableLogging: true,
      );

      expect(verdict.isMusic, isTrue);
      final isValid = MusicResultClassifier.isValidIndividualSong(candidate, query: query);
      expect(isValid, isTrue, reason: 'Legitimate theme song should be valid for individual playback');
    });

    test('WWE: Voices and wrestling entertainment are rejected from music recommendations', () {
      final wweVoices = const YouTubeVideo(
        id: 'yt_wwe_voices',
        title: 'WWE: Voices (Randy Orton) - Single',
        channelTitle: 'WWE Music',
        thumbnailUrl: '',
        duration: '3:24',
        viewCount: '25M views',
        rawTitle: 'WWE: Voices (Randy Orton) - Single',
        rawChannelTitle: 'WWE Music',
      );

      final verdict = MusicResultClassifier.classify(
        wweVoices,
        query: 'Jailer songs',
        forIndividualPlayback: true,
        enableLogging: true,
      );

      expect(verdict.isMusic, isFalse, reason: 'WWE wrestling promo/show content should be rejected from music queues');
      expect(MusicResultClassifier.isValidIndividualSong(wweVoices), isFalse);
    });

    test('Non-music entertainment and meme comedy clips (e.g. Bad Times) are rejected', () {
      final badTimesClip = const YouTubeVideo(
        id: 'yt_bad_times',
        title: 'Bad Times | Tamil Comedy Scene & Memes',
        channelTitle: 'Tamil Comedy Junction',
        thumbnailUrl: '',
        duration: '2:45',
        viewCount: '500K views',
        rawTitle: 'Bad Times | Tamil Comedy Scene & Memes',
        rawChannelTitle: 'Tamil Comedy Junction',
      );

      final verdict = MusicResultClassifier.classify(
        badTimesClip,
        query: 'Jailer Hukum',
        forIndividualPlayback: true,
        enableLogging: true,
      );

      expect(verdict.isMusic, isFalse);
      expect(MusicResultClassifier.isValidIndividualSong(badTimesClip), isFalse);
    });
  });
}
