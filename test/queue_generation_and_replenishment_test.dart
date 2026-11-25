import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/profile/domain/user_profile.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/models/track.dart';

class _FakeYouTubeRepository extends YouTubeRepository {
  final Map<String, List<YouTubeVideo>> relatedByVideoId;
  final Map<String, List<YouTubeVideo>> artistTracksByArtist;
  final Map<String, List<YouTubeVideo>> searchResultsByQuery;

  _FakeYouTubeRepository({
    this.relatedByVideoId = const {},
    this.artistTracksByArtist = const {},
    this.searchResultsByQuery = const {},
  });

  @override
  Future<List<YouTubeVideo>> getRelatedTracks(
    YouTubeVideo seedVideo, {
    int limit = 10,
  }) async {
    return (relatedByVideoId[seedVideo.id] ?? const []).take(limit).toList();
  }

  @override
  Future<List<YouTubeVideo>> getArtistTracks(
    String artistName, {
    int page = 1,
    int limit = 15,
    List<String> preferredLanguages = const [],
  }) async {
    return (artistTracksByArtist[artistName] ?? const []).take(limit).toList();
  }

  @override
  Future<List<YouTubeVideo>> search(
    String query, {
    int page = 1,
    bool forceFresh = false,
  }) async {
    return searchResultsByQuery[query] ?? const [];
  }
}

YouTubeVideo _video({
  required String id,
  required String title,
  required String artist,
  String duration = '3:45',
}) {
  return YouTubeVideo(
    id: id,
    title: title,
    channelTitle: artist,
    thumbnailUrl: 'https://img.youtube.com/vi/$id/hqdefault.jpg',
    duration: duration,
    viewCount: '1M views',
    rawTitle: title,
    rawChannelTitle: artist,
  );
}

Track _track({
  required String id,
  required String title,
  required String artist,
  String? albumName,
  String? sourceId,
}) {
  return Track(
    id: id,
    title: title,
    artist: artist,
    imageUrl: 'https://example.com/$id.jpg',
    duration: '3:45',
    sourceProvider: 'youtube',
    albumName: albumName,
    sourceId: sourceId,
  );
}

void main() {
  group('QG-01 & QG-02 Queue Generation and Replenishment', () {
    test(
        'QG-01: Onboarding artist preference does not monopolize track-anchored queue',
        () async {
      final profile = UserProfile(
        uid: 'u1',
        displayName: 'Test Listener',
        email: 'test@miee.app',
        onboardingCompleted: true,
        selectedArtists: const [
          ArtistSummary(
            id: 'sai_1',
            name: 'Sai Abhyankkar',
            imageUrl: 'https://example.com/sai.jpg',
          ),
        ],
        preferredLanguages: const ['Tamil'],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      final seedTrack = _track(
        id: 'youtube_radhima0001',
        title: 'Radhima',
        artist: 'Sai Abhyankkar',
      );
      final seedId = seedTrack.id.replaceFirst('youtube_', '');

      final repo = _FakeYouTubeRepository(
        relatedByVideoId: {
          seedId: [
            _video(
                id: 'rel_anirudh1',
                title: 'Kanave Kanave',
                artist: 'Anirudh Ravichander'),
            _video(
                id: 'rel_yuvan001',
                title: 'Pogathey',
                artist: 'Yuvan Shankar Raja'),
            _video(
                id: 'rel_arr00001', title: 'Munbe Vaa', artist: 'A. R. Rahman'),
            _video(
                id: 'rel_pradeep1',
                title: 'Aagayam Theepiditha',
                artist: 'Pradeep Kumar'),
            _video(
                id: 'rel_gv000001',
                title: 'Veyyon Silli',
                artist: 'G. V. Prakash Kumar'),
            _video(
                id: 'rel_harris01',
                title: 'Anbe En Anbe',
                artist: 'Harris Jayaraj'),
            _video(
                id: 'rel_santhosh',
                title: 'Maya Nadhi',
                artist: 'Santhosh Narayanan'),
            _video(
                id: 'rel_sai_0001',
                title: 'Katchi Sera',
                artist: 'Sai Abhyankkar'),
          ],
        },
        artistTracksByArtist: {
          'Sai Abhyankkar': [
            _video(
                id: 'art_sai_0002',
                title: 'Aasa Kooda',
                artist: 'Sai Abhyankkar'),
            _video(
                id: 'art_sai_0003',
                title: 'Sithira Puthiri',
                artist: 'Sai Abhyankkar'),
            _video(
                id: 'art_sai_0004',
                title: 'Vizhi Veekura',
                artist: 'Sai Abhyankkar'),
          ],
        },
      );

      final service = RecommendationService(youtubeRepo: repo);

      final upcoming = await service.getUpcomingQueueRecommendations(
        currentTrack: seedTrack,
        currentQueue: [seedTrack],
        profile: profile,
        limit: 8,
      );

      expect(upcoming.length, greaterThanOrEqualTo(6));
      final saiCount = upcoming
          .where((t) => t.artist.toLowerCase().contains('sai abhyankkar'))
          .length;
      final distinctArtists =
          upcoming.map((t) => t.artist.toLowerCase()).toSet();

      expect(saiCount, lessThanOrEqualTo(2));
      expect(distinctArtists.length, greaterThanOrEqualTo(5));
    });

    test(
        'QG-02: Discovery/non-11-char track ID resolves seed video and generates upcoming queue',
        () async {
      final faFaFa = _track(
        id: 'itunes_123456789',
        title: 'Fa Fa Fa',
        artist: 'Anirudh Ravichander',
      );

      final repo = _FakeYouTubeRepository(
        searchResultsByQuery: {
          'Fa Fa Fa Anirudh Ravichander': [
            _video(
              id: 'fafafa12345',
              title: 'Fa Fa Fa',
              artist: 'Anirudh Ravichander',
            ),
          ],
        },
        relatedByVideoId: {
          'fafafa12345': [
            _video(
              id: 'next_track1',
              title: 'Hukum',
              artist: 'Anirudh Ravichander',
            ),
            _video(
              id: 'next_track2',
              title: 'Kaavaalaa (Official Audio)',
              artist: 'Shilpa Rao',
            ),
            _video(
              id: 'next_track3',
              title: 'Naa Ready (From "Leo")',
              artist: 'Thalapathy Vijay',
            ),
          ],
        },
      );

      final service = RecommendationService(youtubeRepo: repo);

      final upcoming = await service.getUpcomingQueueRecommendations(
        currentTrack: faFaFa,
        currentQueue: [faFaFa],
        limit: 5,
      );

      expect(upcoming, isNotEmpty);
      expect(upcoming.map((t) => t.title), contains('Hukum'));
      expect(upcoming.map((t) => t.title), contains('Kaavaalaa'));
      expect(upcoming.map((t) => t.title), contains('Naa Ready (From "Leo")'));
    });

    test(
        'QG-02: Track with valid sourceId uses sourceId directly without extra search',
        () async {
      final trackWithSourceId = _track(
        id: 'wm_987654',
        title: 'Fa Fa Fa',
        artist: 'Anirudh Ravichander',
        sourceId: 'src12345678',
      );

      final repo = _FakeYouTubeRepository(
        relatedByVideoId: {
          'src12345678': [
            _video(
              id: 'rel_song_01',
              title: 'Arabic Kuthu',
              artist: 'Anirudh Ravichander',
            ),
          ],
        },
      );

      final service = RecommendationService(youtubeRepo: repo);

      final upcoming = await service.getUpcomingQueueRecommendations(
        currentTrack: trackWithSourceId,
        currentQueue: [trackWithSourceId],
        limit: 5,
      );

      expect(upcoming.length, 1);
      expect(upcoming.first.title, 'Arabic Kuthu');
    });

    test(
        'QG-02: Filters non-song content, duplicates, and returns empty gracefully on exhaustion',
        () async {
      final seedTrack = _track(
        id: 'youtube_seed1234567',
        title: 'Fa Fa Fa',
        artist: 'Anirudh Ravichander',
      );

      final repo = _FakeYouTubeRepository(
        relatedByVideoId: {
          'seed1234567': [
            _video(
              id: 'seed1234567',
              title: 'Fa Fa Fa',
              artist: 'Anirudh Ravichander',
            ),
            _video(
              id: 'comedy12345',
              title: 'Vadivelu Comedy Scene Full Video',
              artist: 'Tamil Cinema Vault',
              duration: '14:30',
            ),
            _video(
              id: 'cover123456',
              title: 'Fa Fa Fa (Cover Version)',
              artist: 'Random Cover Channel',
            ),
          ],
        },
      );

      final service = RecommendationService(youtubeRepo: repo);

      final upcoming = await service.getUpcomingQueueRecommendations(
        currentTrack: seedTrack,
        currentQueue: [seedTrack],
        limit: 5,
      );

      expect(upcoming, isEmpty);
    });

    test('Shuffle preserves current track at 0 and appends replenished tracks',
        () {
      final manager = QueueManager();
      final t1 = _track(id: '1', title: 'Track 1', artist: 'Artist 1');
      final t2 = _track(id: '2', title: 'Track 2', artist: 'Artist 2');
      final t3 = _track(id: '3', title: 'Track 3', artist: 'Artist 3');

      manager.setQueue([t1, t2], startIndex: 0);
      manager.enableShuffle();
      expect(manager.currentIndex, 0);
      expect(manager.currentTrack?.id, '1');

      manager.addTracks([t3]);
      expect(manager.queue.length, 3);
      manager.disableShuffle();
      expect(manager.queue.map((t) => t.id).toList(), ['1', '2', '3']);
    });
  });
}
