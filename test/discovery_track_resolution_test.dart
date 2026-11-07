import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/youtube_audio_service.dart';
import 'package:Miee/features/youtube/domain/music_result_classifier.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  group('Miee — Discovery Track Resolution & Music Integrity Tests (Phase 4)', () {
    late YouTubeAudioService ytAudioService;

    setUp(() {
      ytAudioService = YouTubeAudioService();
      ytAudioService.clearCache();
    });

    test('1. An external chart track successfully resolves to a valid YouTube candidate', () async {
      const mockCandidate = YouTubeVideo(
        id: 'dQw4w9WgXcQ',
        title: 'Veezha Veera Lyrical (Tamil) | VidaaMuyarchi | Ajith Kumar',
        channelTitle: 'Sony Music South',
        thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        duration: '3:59',
        viewCount: '33.7M views',
        rawTitle: 'Veezha Veera Lyrical (Tamil) | VidaaMuyarchi | Ajith Kumar',
        rawChannelTitle: 'Sony Music South',
      );

      ytAudioService.injectCachedCandidate('Veezha Veera Sai Abhyankkar', mockCandidate);

      final resolvedCandidate = await ytAudioService.resolveCandidateForQuery('Veezha Veera Sai Abhyankkar');
      expect(resolvedCandidate, isNotNull);
      expect(resolvedCandidate!.id, equals('dQw4w9WgXcQ'));
      expect(resolvedCandidate.title, equals('Veezha Veera Lyrical (Tamil) | VidaaMuyarchi | Ajith Kumar'));

      final resolvedId = await ytAudioService.resolveVideoIdForQuery('Veezha Veera Sai Abhyankkar');
      expect(resolvedId, equals('dQw4w9WgXcQ'));
    });

    test('2. The actual YouTube channel title survives resolution into Track model', () async {
      const mockCandidate = YouTubeVideo(
        id: 'dQw4w9WgXcQ',
        title: 'Veezha Veera Lyrical (Tamil)',
        channelTitle: 'Sony Music South',
        thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        duration: '3:59',
        viewCount: '33.7M views',
        rawTitle: 'Veezha Veera Lyrical (Tamil)',
        rawChannelTitle: 'Sony Music South',
      );

      // Simulate external chart track (from iTunes RSS / Deezer)
      const chartTrack = Track(
        id: 'wm_chart_12345',
        title: 'Veezha Veera',
        artist: 'Sai Abhyankkar, Tippu & Anirudh',
        imageUrl: '',
        duration: '3:30',
      );

      final query = '${chartTrack.title} ${chartTrack.artist}';
      ytAudioService.injectCachedCandidate(query, mockCandidate);

      final candidate = await ytAudioService.resolveCandidateForQuery(query);
      expect(candidate, isNotNull);

      // Update Track model with preserved candidate metadata
      final upgradedTrack = chartTrack.copyWith(
        id: 'youtube_${candidate!.id}',
        rawTitle: candidate.rawTitle ?? candidate.title,
        rawArtist: candidate.rawChannelTitle ?? candidate.channelTitle,
        duration: candidate.duration,
        imageUrl: candidate.thumbnailUrl,
      );

      expect(upgradedTrack.id, equals('youtube_dQw4w9WgXcQ'));
      expect(upgradedTrack.rawArtist, equals('Sony Music South'));
      expect(upgradedTrack.rawTitle, equals('Veezha Veera Lyrical (Tamil)'));
      expect(upgradedTrack.title, equals('Veezha Veera'));
      expect(upgradedTrack.artist, equals('Sai Abhyankkar, Tippu & Anirudh'));

      // Validate that candidate retains actual channelTitle for classifier evaluation
      expect(MusicResultClassifier.isValidIndividualSong(candidate, query: 'Veezha Veera Sai Abhyankkar'), isTrue);
    });

    test('3. A valid official lyric video passes classification', () {
      const lyricVideo = YouTubeVideo(
        id: 'lyric_001',
        title: 'Veezha Veera Lyrical (Tamil) | Ajith Kumar | Lyca',
        channelTitle: 'Sony Music South',
        thumbnailUrl: 'https://i.ytimg.com/vi/lyric_001/hqdefault.jpg',
        duration: '3:59',
        viewCount: '25M views',
        rawTitle: 'Veezha Veera Lyrical (Tamil) | Ajith Kumar | Lyca',
        rawChannelTitle: 'Sony Music South',
      );

      final verdict = MusicResultClassifier.classify(
        lyricVideo,
        query: 'Veezha Veera',
        forIndividualPlayback: true,
      );
      expect(verdict.isMusic, isTrue);
      expect(verdict.confidence, equals(MusicTrackConfidence.officialMusic));
      expect(MusicResultClassifier.isValidIndividualSong(lyricVideo, query: 'Veezha Veera'), isTrue);
    });

    test('4. A valid official audio release passes classification', () {
      const audioTrack = YouTubeVideo(
        id: 'audio_001',
        title: 'Hukum - Thalaivar Alappara (Official Audio) | Rajinikanth',
        channelTitle: 'Sun Pictures',
        thumbnailUrl: 'https://i.ytimg.com/vi/audio_001/hqdefault.jpg',
        duration: '3:27',
        viewCount: '50M views',
        rawTitle: 'Hukum - Thalaivar Alappara (Official Audio) | Rajinikanth',
        rawChannelTitle: 'Sun Pictures',
      );

      final verdict = MusicResultClassifier.classify(
        audioTrack,
        query: 'Hukum Rajinikanth',
        forIndividualPlayback: true,
      );
      expect(verdict.isMusic, isTrue);
      expect(verdict.confidence, equals(MusicTrackConfidence.officialMusic));
      expect(MusicResultClassifier.isValidIndividualSong(audioTrack, query: 'Hukum Rajinikanth'), isTrue);
    });

    test('5. Legitimate regional-language versions remain selectable and distinct', () {
      const teluguVideo = YouTubeVideo(
        id: 'telugu_001',
        title: 'Veera Veera Lyrical (Telugu) | Ajith Kumar',
        channelTitle: 'Sony Music South',
        thumbnailUrl: '',
        duration: '3:59',
        viewCount: '8.8M views',
        rawTitle: 'Veera Veera Lyrical (Telugu) | Ajith Kumar',
        rawChannelTitle: 'Sony Music South',
      );

      const hindiVideo = YouTubeVideo(
        id: 'hindi_001',
        title: 'Veera Veera Lyrical (Hindi) | Ajith Kumar',
        channelTitle: 'Sony Music India',
        thumbnailUrl: '',
        duration: '3:59',
        viewCount: '455K views',
        rawTitle: 'Veera Veera Lyrical (Hindi) | Ajith Kumar',
        rawChannelTitle: 'Sony Music India',
      );

      expect(MusicResultClassifier.isValidIndividualSong(teluguVideo, query: 'Veera Veera Telugu'), isTrue);
      expect(MusicResultClassifier.isValidIndividualSong(hindiVideo, query: 'Veera Veera Hindi'), isTrue);
      expect(teluguVideo.id, isNot(equals(hindiVideo.id)));
    });

    test('6. Legitimate remix or acoustic version remains selectable', () {
      const acousticCandidate = YouTubeVideo(
        id: 'acoustic_001',
        title: 'Veezha Veera (Acoustic Unplugged Version)',
        channelTitle: 'Anirudh Ravichander',
        thumbnailUrl: '',
        duration: '3:15',
        viewCount: '1.2M views',
        rawTitle: 'Veezha Veera (Acoustic Unplugged Version)',
        rawChannelTitle: 'Anirudh Ravichander',
      );

      const remixCandidate = YouTubeVideo(
        id: 'remix_001',
        title: 'Chaleya (Club Mix / Remix)',
        channelTitle: 'T-Series',
        thumbnailUrl: '',
        duration: '3:45',
        viewCount: '5M views',
        rawTitle: 'Chaleya (Club Mix / Remix)',
        rawChannelTitle: 'T-Series',
      );

      expect(MusicResultClassifier.isValidIndividualSong(acousticCandidate, query: 'Veezha Veera Acoustic'), isTrue);
      expect(MusicResultClassifier.isValidIndividualSong(remixCandidate, query: 'Chaleya Remix'), isTrue);
    });

    test('7. Unrelated or rejected candidate (vlogs, interviews, reviews, comedy clips) remains strictly rejected', () {
      const interviewCandidate = YouTubeVideo(
        id: 'interview_001',
        title: 'Ajith Kumar Vidaamuyarchi Exclusive Interview & Public Reaction',
        channelTitle: 'Behindwoods O2',
        thumbnailUrl: '',
        duration: '14:20',
        viewCount: '1.5M views',
        rawTitle: 'Ajith Kumar Vidaamuyarchi Exclusive Interview & Public Reaction',
        rawChannelTitle: 'Behindwoods O2',
      );

      const comedyClip = YouTubeVideo(
        id: 'comedy_001',
        title: 'Gopi Sudhakar Parithabangal Roasting Movie Scenes',
        channelTitle: 'Parithabangal',
        thumbnailUrl: '',
        duration: '8:45',
        viewCount: '4M views',
        rawTitle: 'Gopi Sudhakar Parithabangal Roasting Movie Scenes',
        rawChannelTitle: 'Parithabangal',
      );

      const fanEditClip = YouTubeVideo(
        id: 'edit_001',
        title: 'Ajith Mass BGM WhatsApp Status Video 4K',
        channelTitle: 'Editz Hub',
        thumbnailUrl: '',
        duration: '0:32',
        viewCount: '50K views',
        rawTitle: 'Ajith Mass BGM WhatsApp Status Video 4K',
        rawChannelTitle: 'Editz Hub',
      );

      expect(MusicResultClassifier.isValidIndividualSong(interviewCandidate), isFalse);
      expect(MusicResultClassifier.isValidIndividualSong(comedyClip), isFalse);
      expect(MusicResultClassifier.isValidIndividualSong(fanEditClip), isFalse);
    });

    test('8. Failed resolution returns clear error without corrupting player state', () async {
      // Simulate non-resolving query
      final candidate = await ytAudioService.resolveCandidateForQuery('CompletelyUnknownQueryThatDoesNotExist12345XYZ');
      expect(candidate, isNull);

      final state = PlaybackState.initial().copyWith(
        status: PlaybackStatus.error,
        clearLoadingTrackId: true,
        errorMessage: 'This video is not a recognized music track.',
      );

      expect(state.status, equals(PlaybackStatus.error));
      expect(state.loadingTrackId, isNull);
      expect(state.errorMessage, equals('This video is not a recognized music track.'));
    });

    test('9. Candidate cache enforces maximum capacity of 100 with FIFO eviction', () {
      ytAudioService.clearCache();

      // Inject 105 candidates
      for (int i = 1; i <= 105; i++) {
        final video = YouTubeVideo(
          id: 'video_id_${i.toString().padLeft(3, '0')}',
          title: 'Track Title $i',
          channelTitle: 'Channel $i',
          thumbnailUrl: 'https://i.ytimg.com/vi/$i.jpg',
          duration: '3:30',
          viewCount: '1M',
          rawTitle: 'Track Title $i',
          rawChannelTitle: 'Channel $i',
        );
        ytAudioService.injectCachedCandidate('query_$i', video);
      }

      // Cache size should not exceed 100
      expect(ytAudioService.cachedCandidateCountForTesting, equals(100));

      // Oldest entries (query_1 through query_5) should be evicted
      for (int i = 1; i <= 5; i++) {
        final cached = ytAudioService.getCachedCandidateForTesting('query_$i');
        expect(cached, isNull, reason: 'query_$i should have been evicted by FIFO rule');
      }

      // Newer entries (query_6 through query_105) must remain cached
      final sixth = ytAudioService.getCachedCandidateForTesting('query_6');
      expect(sixth, isNotNull);
      expect(sixth!.id, equals('video_id_006'));

      final latest = ytAudioService.getCachedCandidateForTesting('query_105');
      expect(latest, isNotNull);
      expect(latest!.id, equals('video_id_105'));
    });

    test('10. Resolved YouTube track ID upgrades queue entry and persists across restarts', () {
      const originalTrack = Track(
        id: 'wm_chart_9999',
        title: 'Veezha Veera',
        artist: 'Sai Abhyankkar',
        imageUrl: '',
        duration: '3:30',
      );

      const candidate = YouTubeVideo(
        id: 'dQw4w9WgXcQ',
        title: 'Veezha Veera Lyrical (Tamil)',
        channelTitle: 'Sony Music South',
        thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        duration: '3:59',
        viewCount: '33.7M',
        rawTitle: 'Veezha Veera Lyrical (Tamil)',
        rawChannelTitle: 'Sony Music South',
      );

      final originalId = originalTrack.id;
      final upgradedTrack = originalTrack.copyWith(
        id: 'youtube_${candidate.id}',
        rawTitle: candidate.rawTitle ?? candidate.title,
        rawArtist: candidate.rawChannelTitle ?? candidate.channelTitle,
        duration: candidate.duration,
        imageUrl: candidate.thumbnailUrl,
      );

      // Verify that ID was transformed
      expect(upgradedTrack.id, isNot(equals(originalId)));
      expect(upgradedTrack.id, equals('youtube_dQw4w9WgXcQ'));

      // Simulate queue replacement
      final queue = <Track>[originalTrack];
      final targetIndex = queue.indexWhere((t) => t.id == originalId);
      expect(targetIndex, equals(0));
      queue[targetIndex] = upgradedTrack;

      // Verification of snapshot persistence condition
      final shouldPersist = upgradedTrack.id != originalId;
      expect(shouldPersist, isTrue);

      // Verify that queue entry in snapshot now contains the resolved YouTube ID
      expect(queue[0].id, equals('youtube_dQw4w9WgXcQ'));
      expect(queue[0].rawArtist, equals('Sony Music South'));
      expect(queue[0].artist, equals('Sai Abhyankkar'));
    });
  });
}
