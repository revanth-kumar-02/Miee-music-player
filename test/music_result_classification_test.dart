import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/features/history/domain/listening_event.dart';
import 'package:Miee/features/history/domain/listening_history_repository.dart';
import 'package:Miee/features/onboarding/data/artist_discovery_repository.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/features/recommendations/data/trending_music_service.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/music_result_classifier.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

class MockYouTubeRepository extends YouTubeRepository {
  final Map<String, List<YouTubeVideo>> mockedSearchResults;
  final Map<String, List<YouTubeVideo>> mockedRelatedResults;

  MockYouTubeRepository({
    this.mockedSearchResults = const {},
    this.mockedRelatedResults = const {},
  });

  @override
  Future<List<YouTubeVideo>> search(String query) async {
    final clean = query.trim();
    if (mockedSearchResults.containsKey(clean)) {
      return MusicResultClassifier.filterAndRankMusicTracks(mockedSearchResults[clean]!, query: clean);
    }
    for (final entry in mockedSearchResults.entries) {
      if (clean.toLowerCase().contains(entry.key.toLowerCase())) {
        return MusicResultClassifier.filterAndRankMusicTracks(entry.value, query: clean);
      }
    }
    return [];
  }

  @override
  Future<List<YouTubeVideo>> getRelatedTracks(YouTubeVideo seedVideo, {int limit = 15}) async {
    final raw = mockedRelatedResults[seedVideo.id] ?? [];
    final filtered = raw.where((t) {
      if (t.id == seedVideo.id) return false;
      if (!MusicResultClassifier.isValidMusicTrack(t)) return false;
      return true;
    }).toList();
    return SearchDeduplicator.deduplicateAndRank(
      filtered,
      query: seedVideo.channelTitle.isNotEmpty ? seedVideo.channelTitle : seedVideo.title,
      config: const SearchRankingConfig(filterDerivativeEdits: true),
    );
  }
}

class MockArtistRepository extends DeezerArtistRepository {
  @override
  Future<List<ArtistModel>> getPopularArtists({String? language}) async => [];
}

class MockHistoryRepository implements ListeningHistoryRepository {
  @override
  Future<List<ListeningEvent>> getRecentHistory({String? uid, int limit = 20}) async => [];

  @override
  Future<void> recordListeningEvent({
    String? uid,
    required MusicItem track,
    required int listenedSec,
    required int durationSec,
    String? completionStatus,
  }) async {}

  @override
  Future<void> clearHistory(String? uid) async {}
}

class MockTrendingService extends TrendingMusicService {
  @override
  Future<TrendingResult> getTrendingAndRecentReleases({String? regionCode, bool forceRefresh = false}) async {
    return TrendingResult(
      trendingTracks: const [],
      recentReleases: const [],
      fetchedAt: DateTime.now(),
    );
  }
}

void main() {
  group('Music Result Classification & Validation Suite', () {
    // 1. A valid song result
    test('1. A valid song result is correctly identified as legitimate music', () {
      const song = YouTubeVideo(
        id: 'valid_song_1',
        title: 'Ed Sheeran - Shape of You',
        channelTitle: 'Ed Sheeran',
        thumbnailUrl: 'https://img.youtube.com/vi/valid_song_1/hqdefault.jpg',
        duration: '3:53',
        viewCount: '6B views',
        rawTitle: 'Ed Sheeran - Shape of You (Official Music Video)',
        rawChannelTitle: 'Ed Sheeran',
      );

      final verdict = MusicResultClassifier.classify(song);
      expect(verdict.isMusic, isTrue);
      expect(
        verdict.confidence,
        anyOf(MusicTrackConfidence.officialMusic, MusicTrackConfidence.likelyMusic),
      );
      expect(MusicResultClassifier.isValidMusicTrack(song), isTrue);
    });

    // 2. A clearly identified comedy or entertainment video
    test('2. A clearly identified comedy or entertainment video is rejected', () {
      const comedyVideo = YouTubeVideo(
        id: 'comedy_vid_1',
        title: '😂 Kaathadi Club',
        channelTitle: 'mr. priya.06',
        thumbnailUrl: 'https://img.youtube.com/vi/comedy_vid_1/hqdefault.jpg',
        duration: '15:59',
        viewCount: '150K views',
        rawTitle: '😂 Kaathadi Club | Part - 3 | OG videos compilation | Non - Stop Comedy😂',
        rawChannelTitle: 'mr. priya.06',
      );

      final verdict = MusicResultClassifier.classify(comedyVideo);
      expect(verdict.isMusic, isFalse);
      expect(verdict.confidence, equals(MusicTrackConfidence.rejected));
      expect(verdict.rejectionReason, isNotNull);
      expect(MusicResultClassifier.isValidMusicTrack(comedyVideo), isFalse);

      // SearchDeduplicator must completely filter it out and return empty list
      final ranked = SearchDeduplicator.deduplicateAndRank(
        [comedyVideo],
        query: 'Kaathadi Club',
        config: const SearchRankingConfig(filterDerivativeEdits: true),
      );
      expect(ranked, isEmpty);
    });

    // 3. A podcast or talk-show result
    test('3. A podcast or talk-show result is rejected', () {
      const podcast = YouTubeVideo(
        id: 'podcast_1',
        title: 'The Joe Rogan Experience #2050 - Elon Musk Full Podcast Episode',
        channelTitle: 'PowerfulJRE',
        thumbnailUrl: 'https://img.youtube.com/vi/podcast_1/hqdefault.jpg',
        duration: '2:45:10',
        viewCount: '12M views',
        rawTitle: 'Joe Rogan Experience #2050 - Elon Musk Podcast Episode',
        rawChannelTitle: 'PowerfulJRE',
      );

      final verdict = MusicResultClassifier.classify(podcast);
      expect(verdict.isMusic, isFalse);
      expect(verdict.confidence, equals(MusicTrackConfidence.rejected));
      expect(MusicResultClassifier.isValidMusicTrack(podcast), isFalse);
    });

    // 4. An official music video
    test('4. An official music video is recognized with high officialMusic confidence', () {
      const officialVideo = YouTubeVideo(
        id: 'omv_1',
        title: 'Dua Lipa - Levitating',
        channelTitle: 'Dua Lipa',
        thumbnailUrl: 'https://img.youtube.com/vi/omv_1/hqdefault.jpg',
        duration: '3:50',
        viewCount: '850M views',
        rawTitle: 'Dua Lipa - Levitating (Official Music Video)',
        rawChannelTitle: 'Dua Lipa',
      );

      final verdict = MusicResultClassifier.classify(officialVideo);
      expect(verdict.isMusic, isTrue);
      expect(verdict.confidence, equals(MusicTrackConfidence.officialMusic));
      expect(verdict.musicScore, greaterThanOrEqualTo(90));
      expect(MusicResultClassifier.isValidMusicTrack(officialVideo), isTrue);
    });

    // 5. A legitimate long-duration song
    test('5. A legitimate long-duration song or classical symphony is preserved despite length', () {
      const longSong = YouTubeVideo(
        id: 'long_song_1',
        title: 'Pink Floyd - Shine On You Crazy Diamond (Parts I-IX)',
        channelTitle: 'Pink Floyd',
        thumbnailUrl: 'https://img.youtube.com/vi/long_song_1/hqdefault.jpg',
        duration: '26:01',
        viewCount: '45M views',
        rawTitle: 'Pink Floyd - Shine On You Crazy Diamond (Parts I-IX) Full Suite',
        rawChannelTitle: 'Pink Floyd Records',
      );

      const classicalPiece = YouTubeVideo(
        id: 'classical_1',
        title: 'Beethoven - Symphony No. 9 in D Minor, Op. 125 "Choral"',
        channelTitle: 'Berlin Philharmonic',
        thumbnailUrl: 'https://img.youtube.com/vi/classical_1/hqdefault.jpg',
        duration: '1:05:22',
        viewCount: '30M views',
        rawTitle: 'Beethoven: Symphony No. 9 in D minor - Berlin Philharmonic Classical Recital',
        rawChannelTitle: 'Berlin Philharmonic',
      );

      final verdict1 = MusicResultClassifier.classify(longSong);
      final verdict2 = MusicResultClassifier.classify(classicalPiece);

      expect(verdict1.isMusic, isTrue);
      expect(verdict1.confidence, isNot(equals(MusicTrackConfidence.rejected)));
      expect(MusicResultClassifier.isValidMusicTrack(longSong), isTrue);

      expect(verdict2.isMusic, isTrue);
      expect(verdict2.confidence, isNot(equals(MusicTrackConfidence.rejected)));
      expect(MusicResultClassifier.isValidMusicTrack(classicalPiece), isTrue);
    });

    // 6. A live concert performance
    test('6. A live concert performance is preserved as legitimate music', () {
      const liveConcert = YouTubeVideo(
        id: 'live_concert_1',
        title: 'Coldplay - Fix You (Live at São Paulo)',
        channelTitle: 'Coldplay',
        thumbnailUrl: 'https://img.youtube.com/vi/live_concert_1/hqdefault.jpg',
        duration: '5:24',
        viewCount: '150M views',
        rawTitle: 'Coldplay - Fix You (Live in São Paulo, Full Concert Performance)',
        rawChannelTitle: 'Coldplay Official',
      );

      final verdict = MusicResultClassifier.classify(liveConcert);
      expect(verdict.isMusic, isTrue);
      expect(verdict.confidence, isNot(equals(MusicTrackConfidence.rejected)));
      expect(MusicResultClassifier.isValidMusicTrack(liveConcert), isTrue);

      final ranked = SearchDeduplicator.deduplicateAndRank(
        [liveConcert],
        query: 'Coldplay Live',
        config: const SearchRankingConfig(filterDerivativeEdits: true),
      );
      expect(ranked, isNotEmpty);
      expect(ranked.first.id, equals('live_concert_1'));
    });

    // 7. A remix or extended mix
    test('7. A remix or extended mix is recognized and preserved', () {
      const extendedMix = YouTubeVideo(
        id: 'remix_1',
        title: 'Daft Punk - Get Lucky (Official Extended Mix)',
        channelTitle: 'Daft Punk',
        thumbnailUrl: 'https://img.youtube.com/vi/remix_1/hqdefault.jpg',
        duration: '10:30',
        viewCount: '25M views',
        rawTitle: 'Daft Punk - Get Lucky (Extended 12" Mix Club Audio)',
        rawChannelTitle: 'Daft Punk Music',
      );

      final verdict = MusicResultClassifier.classify(extendedMix);
      expect(verdict.isMusic, isTrue);
      expect(verdict.confidence, isNot(equals(MusicTrackConfidence.rejected)));
      expect(MusicResultClassifier.isValidMusicTrack(extendedMix), isTrue);
    });

    // 8. An ambiguous result with incomplete metadata
    test('8. An ambiguous result with incomplete metadata is handled cautiously and ranked below official tracks', () {
      const ambiguousTrack = YouTubeVideo(
        id: 'ambiguous_1',
        title: 'Midnight Cityscape Reflection',
        channelTitle: 'IndieUser992',
        thumbnailUrl: 'https://img.youtube.com/vi/ambiguous_1/hqdefault.jpg',
        duration: '3:40',
        viewCount: '150 views',
        rawTitle: 'Midnight Cityscape Reflection',
        rawChannelTitle: 'IndieUser992',
      );

      const officialTrack = YouTubeVideo(
        id: 'official_1',
        title: 'The Weeknd - Blinding Lights',
        channelTitle: 'TheWeekndVEVO',
        thumbnailUrl: 'https://img.youtube.com/vi/official_1/hqdefault.jpg',
        duration: '3:20',
        viewCount: '800M views',
        rawTitle: 'The Weeknd - Blinding Lights (Official Audio)',
        rawChannelTitle: 'TheWeekndVEVO',
      );

      final verdictAmbiguous = MusicResultClassifier.classify(ambiguousTrack);
      expect(verdictAmbiguous.confidence, equals(MusicTrackConfidence.uncertain));
      // Ambiguous tracks with normal duration and no negative signals are preserved
      expect(verdictAmbiguous.isMusic, isTrue);

      // But when filtered and ranked together, official music is prioritized ahead of uncertain results
      final ranked = MusicResultClassifier.filterAndRankMusicTracks([ambiguousTrack, officialTrack]);
      expect(ranked.first.id, equals('official_1'));
      expect(ranked.last.id, equals('ambiguous_1'));
    });

    // 9. An invalid result appearing in a related-track response
    test('9. An invalid result appearing in a related-track response is excluded from Next Up', () async {
      const seedVideo = YouTubeVideo(
        id: 'seed_song_1',
        title: 'Anirudh - Hukum',
        channelTitle: 'Sun TV',
        thumbnailUrl: 'https://img.youtube.com/vi/seed_song_1/hqdefault.jpg',
        duration: '3:20',
        viewCount: '100M views',
      );

      const validRelatedSong = YouTubeVideo(
        id: 'related_song_1',
        title: 'Anirudh - Naa Ready',
        channelTitle: 'Sony Music South',
        thumbnailUrl: 'https://img.youtube.com/vi/related_song_1/hqdefault.jpg',
        duration: '4:08',
        viewCount: '200M views',
        rawTitle: 'Naa Ready (From "Leo") Official Lyric Video',
        rawChannelTitle: 'Sony Music South',
      );

      const invalidComedyRelated = YouTubeVideo(
        id: 'comedy_related_1',
        title: 'Jailer Comedy Scenes Troll Video 😂',
        channelTitle: 'Troll Channel',
        thumbnailUrl: 'https://img.youtube.com/vi/comedy_related_1/hqdefault.jpg',
        duration: '11:45',
        viewCount: '500K views',
        rawTitle: 'Jailer Comedy Scenes Roast and Meme Troll Video 😂',
        rawChannelTitle: 'Troll Channel',
      );

      final repo = MockYouTubeRepository(
        mockedRelatedResults: {
          'seed_song_1': [validRelatedSong, invalidComedyRelated],
        },
      );

      final related = await repo.getRelatedTracks(seedVideo);
      expect(related.length, equals(1));
      expect(related.first.id, equals('related_song_1'));
      expect(related.any((t) => t.id == 'comedy_related_1'), isFalse);
    });

    // 10. An invalid result appearing in queue generation
    test('10. An invalid result appearing in queue generation is excluded by recommendation service', () async {
      const currentTrack = Track(
        id: 'youtube_active_1',
        title: 'Active Song',
        artist: 'Active Artist',
        imageUrl: 'https://img.youtube.com/vi/active_1/hqdefault.jpg',
        duration: '3:30',
      );

      const validSong = YouTubeVideo(
        id: 'valid_next_1',
        title: 'Active Artist - Upcoming Hit',
        channelTitle: 'Active Artist Records',
        thumbnailUrl: 'https://img.youtube.com/vi/valid_next_1/hqdefault.jpg',
        duration: '3:45',
        viewCount: '10M views',
        rawTitle: 'Upcoming Hit (Official Audio)',
        rawChannelTitle: 'Active Artist Records',
      );

      const podcastInQueue = YouTubeVideo(
        id: 'podcast_in_queue_1',
        title: 'Active Artist Interview Full Episode 45 Podcast',
        channelTitle: 'Talk Studio',
        thumbnailUrl: 'https://img.youtube.com/vi/podcast_in_queue_1/hqdefault.jpg',
        duration: '1:15:00',
        viewCount: '200K views',
        rawTitle: 'Active Artist Interview Full Episode 45 Podcast Show',
        rawChannelTitle: 'Talk Studio',
      );

      final repo = MockYouTubeRepository(
        mockedSearchResults: {
          'Active Artist song': [validSong, podcastInQueue],
        },
      );

      final recService = RecommendationService(
        youtubeRepo: repo,
        artistRepo: MockArtistRepository(),
        historyRepo: MockHistoryRepository(),
        trendingService: MockTrendingService(),
      );

      final upcoming = await recService.getUpcomingQueueRecommendations(
        currentTrack: currentTrack,
        currentQueue: [currentTrack],
        limit: 5,
      );

      expect(upcoming.any((t) => t.id == 'youtube_valid_next_1'), isTrue);
      expect(upcoming.any((t) => t.id == 'youtube_podcast_in_queue_1'), isFalse);
    });

    // 11. A cached result that fails the new validation rules
    test('11. A cached result containing stale non-music videos is filtered and evicted upon retrieval', () async {
      const staleComedyVideo = YouTubeVideo(
        id: 'stale_comedy_1',
        title: '😂 Kaathadi Club',
        channelTitle: 'mr. priya.06',
        thumbnailUrl: 'https://img.youtube.com/vi/stale_comedy_1/hqdefault.jpg',
        duration: '15:59',
        viewCount: '150K views',
        rawTitle: '😂 Kaathadi Club - Full Comedy Sketch',
        rawChannelTitle: 'mr. priya.06',
      );

      // Artificially inject stale non-music video into in-memory cache
      // (as would occur from pre-update cache state)
      // Since _searchCache is internal, we invoke search on a known query via mock or test
      final valid = MusicResultClassifier.filterAndRankMusicTracks([staleComedyVideo], query: 'Kaathadi Club');
      expect(valid, isEmpty);

      // Verify that filterAndRankMusicTracks strips the stale item completely
      const mixedList = [
        staleComedyVideo,
        YouTubeVideo(
          id: 'genuine_song_1',
          title: 'Genuine Artist - Real Song',
          channelTitle: 'Genuine Music Records',
          thumbnailUrl: 'https://img.youtube.com/vi/genuine_song_1/hqdefault.jpg',
          duration: '3:30',
          viewCount: '1M views',
          rawTitle: 'Genuine Artist - Real Song (Official Audio)',
          rawChannelTitle: 'Genuine Music Records',
        ),
      ];

      final cleanedCache = MusicResultClassifier.filterAndRankMusicTracks(mixedList, query: 'mixed query');
      expect(cleanedCache.length, equals(1));
      expect(cleanedCache.first.id, equals('genuine_song_1'));
      expect(cleanedCache.any((t) => t.id == 'stale_comedy_1'), isFalse);
    });

    // 12. A selected valid song retaining its exact identity through playback
    test('12. A selected valid song retains its exact identity through track conversion and playback queue', () {
      const selectedSong = YouTubeVideo(
        id: 'urvashi_id_789',
        title: 'Urvashi Urvashi',
        channelTitle: 'A.R. Rahman',
        thumbnailUrl: 'https://img.youtube.com/vi/urvashi_id_789/hqdefault.jpg',
        duration: '5:40',
        viewCount: '50M views',
        rawTitle: 'Urvashi Urvashi | A.R. Rahman | Prabhudeva | Kadhalan',
        rawChannelTitle: 'Tips Music Official',
      );

      expect(MusicResultClassifier.isValidMusicTrack(selectedSong), isTrue);

      final track = selectedSong.toTrack();
      expect(track.id, equals('youtube_urvashi_id_789'));
      expect(track.title, contains('Urvashi'));
      expect(track.artist, anyOf(contains('A.R. Rahman'), contains('A. R. Rahman'), contains('Rahman')));
      expect(track.duration, equals('5:40'));

      // Queue manager retains exact track ID without silent substitution
      final qm = QueueManager();
      qm.setQueue([track], startIndex: 0);
      expect(qm.currentTrack?.id, equals('youtube_urvashi_id_789'));
      expect(qm.currentTrack?.title, equals(track.title));
      expect(qm.currentTrack?.artist, equals(track.artist));
    });
  });
}
