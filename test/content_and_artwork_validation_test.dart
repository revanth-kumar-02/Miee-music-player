import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/youtube/domain/music_result_classifier.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/features/artwork/domain/artwork_query.dart';
import 'package:Miee/features/artwork/domain/resolved_artwork.dart';
import 'package:Miee/features/artwork/domain/artwork_source.dart';
import 'package:Miee/features/artwork/data/artwork_resolver_impl.dart';
import 'package:Miee/features/artwork/data/providers/local_artwork_provider.dart';
import 'package:Miee/features/artwork/data/providers/youtube_fallback_provider.dart';
import 'package:Miee/features/playlists/domain/playlist_model.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  group('PHASE 4: Content Validation Suite', () {
    test('1. Normal Tamil song is ACCEPTED', () {
      const video = YouTubeVideo(
        id: 'tam_001',
        title: 'Kaadhalai Solla Mudiyaadha',
        channelTitle: 'Sony Music South',
        thumbnailUrl: 'https://i.ytimg.com/vi/tam_001/hqdefault.jpg',
        duration: '4:50',
        viewCount: '25M views',
        rawTitle: 'Kaadhalai Solla Mudiyaadha Video Song | Galatta Kalyanam | A.R. Rahman',
        rawChannelTitle: 'Sony Music South',
      );

      final verdict = MusicResultClassifier.classify(video, forIndividualPlayback: true);
      expect(verdict.isMusic, isTrue);
      expect(verdict.confidence, equals(MusicTrackConfidence.officialMusic));
      expect(MusicResultClassifier.isValidIndividualSong(video), isTrue);
      expect(MusicResultClassifier.isValidMusicTrack(video), isTrue);
      expect(RecommendationService.isLegitimateSong(video), isTrue);
    });

    test('2. Normal English song is ACCEPTED', () {
      const video = YouTubeVideo(
        id: 'eng_001',
        title: 'Believer',
        channelTitle: 'ImagineDragonsVEVO',
        thumbnailUrl: 'https://i.ytimg.com/vi/eng_001/hqdefault.jpg',
        duration: '3:36',
        viewCount: '2.5B views',
        rawTitle: 'Imagine Dragons - Believer (Official Music Video)',
        rawChannelTitle: 'ImagineDragonsVEVO',
      );

      final verdict = MusicResultClassifier.classify(video, forIndividualPlayback: true);
      expect(verdict.isMusic, isTrue);
      expect(MusicResultClassifier.isValidIndividualSong(video), isTrue);
      expect(MusicResultClassifier.isValidMusicTrack(video), isTrue);
      expect(RecommendationService.isLegitimateSong(video), isTrue);
    });

    test('3. Movie soundtrack / OST is ACCEPTED', () {
      const video = YouTubeVideo(
        id: 'ost_001',
        title: 'Cornfield Chase',
        channelTitle: 'WaterTower Music',
        thumbnailUrl: 'https://i.ytimg.com/vi/ost_001/hqdefault.jpg',
        duration: '2:07',
        viewCount: '45M views',
        rawTitle: 'Hans Zimmer - Cornfield Chase (Interstellar Original Motion Picture Soundtrack)',
        rawChannelTitle: 'WaterTower Music',
      );

      final verdict = MusicResultClassifier.classify(video, forIndividualPlayback: true);
      expect(verdict.isMusic, isTrue);
      expect(MusicResultClassifier.isValidIndividualSong(video), isTrue);
      expect(MusicResultClassifier.isValidMusicTrack(video), isTrue);
      expect(RecommendationService.isLegitimateSong(video), isTrue);
    });

    test('4. Legitimate long-form music (Classical raga / Symphony) is ACCEPTED', () {
      const video = YouTubeVideo(
        id: 'class_001',
        title: 'Raga Bhairavi Alapana',
        channelTitle: 'Sanjay Subrahmanyan',
        thumbnailUrl: 'https://i.ytimg.com/vi/class_001/hqdefault.jpg',
        duration: '14:22',
        viewCount: '250K views',
        rawTitle: 'Raga Bhairavi Alapana | Sanjay Subrahmanyan | Live Concert',
        rawChannelTitle: 'Sanjay Subrahmanyan',
      );

      final verdict = MusicResultClassifier.classify(video, forIndividualPlayback: true);
      expect(verdict.isMusic, isTrue);
      expect(MusicResultClassifier.isValidIndividualSong(video), isTrue);
      expect(MusicResultClassifier.isValidMusicTrack(video), isTrue);
      expect(RecommendationService.isLegitimateSong(video), isTrue);
    });

    test('5. Remix and Acoustic Cover are ACCEPTED', () {
      const video = YouTubeVideo(
        id: 'remix_001',
        title: 'Blinding Lights (Acoustic Cover)',
        channelTitle: 'Acoustic Sessions',
        thumbnailUrl: 'https://i.ytimg.com/vi/remix_001/hqdefault.jpg',
        duration: '3:15',
        viewCount: '500K views',
        rawTitle: 'Blinding Lights - Acoustic Cover by Sarah',
        rawChannelTitle: 'Acoustic Sessions',
      );

      final verdict = MusicResultClassifier.classify(video, forIndividualPlayback: true);
      expect(verdict.isMusic, isTrue);
      expect(MusicResultClassifier.isValidIndividualSong(video), isTrue);
      expect(RecommendationService.isLegitimateSong(video), isTrue);
    });

    test('6. Supplied commentary video (AshTag 16:42) is STRICTLY REJECTED', () {
      const video = YouTubeVideo(
        id: 'ashtag_dark_truth',
        title: 'The Dark Truth of Tamil Music...',
        channelTitle: 'AshTag',
        thumbnailUrl: 'https://i.ytimg.com/vi/ashtag_dark_truth/hqdefault.jpg',
        duration: '16:42',
        viewCount: '450K views',
        rawTitle: 'The Dark Truth of Tamil Music Industry | Paid PR Game',
        rawChannelTitle: 'AshTag',
      );

      final verdict = MusicResultClassifier.classify(video, forIndividualPlayback: true);
      expect(verdict.isMusic, isFalse);
      expect(verdict.confidence, equals(MusicTrackConfidence.rejected));
      expect(MusicResultClassifier.isValidIndividualSong(video), isFalse);
      expect(MusicResultClassifier.isValidMusicTrack(video), isFalse);
      expect(RecommendationService.isLegitimateSong(video), isFalse);
    });

    test('7. Interview and Podcast content is STRICTLY REJECTED', () {
      const interviewVideo = YouTubeVideo(
        id: 'int_001',
        title: 'Exclusive Interview with Anirudh',
        channelTitle: 'Behindwoods Air',
        thumbnailUrl: 'https://i.ytimg.com/vi/int_001/hqdefault.jpg',
        duration: '34:10',
        viewCount: '1.2M views',
        rawTitle: 'Anirudh Ravichander Exclusive Interview | Devara, Vettaiyan Secrets',
        rawChannelTitle: 'Behindwoods Air',
      );

      final verdict1 = MusicResultClassifier.classify(interviewVideo, forIndividualPlayback: true);
      expect(verdict1.isMusic, isFalse);
      expect(MusicResultClassifier.isValidIndividualSong(interviewVideo), isFalse);
      expect(RecommendationService.isLegitimateSong(interviewVideo), isFalse);

      const podcastVideo = YouTubeVideo(
        id: 'pod_001',
        title: 'The Ranveer Show #245',
        channelTitle: 'BeerBiceps',
        thumbnailUrl: 'https://i.ytimg.com/vi/pod_001/hqdefault.jpg',
        duration: '1:12:00',
        viewCount: '900K views',
        rawTitle: 'A.R. Rahman on Spirituality & Music | TRS Podcast',
        rawChannelTitle: 'BeerBiceps',
      );

      final verdict2 = MusicResultClassifier.classify(podcastVideo, forIndividualPlayback: true);
      expect(verdict2.isMusic, isFalse);
      expect(MusicResultClassifier.isValidIndividualSong(podcastVideo), isFalse);
      expect(RecommendationService.isLegitimateSong(podcastVideo), isFalse);
    });

    test('8. Music review and reaction videos are STRICTLY REJECTED', () {
      const reviewVideo = YouTubeVideo(
        id: 'rev_001',
        title: 'Devara Songs Honest Review',
        channelTitle: 'Plip Plip',
        thumbnailUrl: 'https://i.ytimg.com/vi/rev_001/hqdefault.jpg',
        duration: '12:05',
        viewCount: '800K views',
        rawTitle: 'Devara Album Roast & Honest Review | Anirudh',
        rawChannelTitle: 'Plip Plip',
      );

      expect(MusicResultClassifier.isValidIndividualSong(reviewVideo), isFalse);
      expect(RecommendationService.isLegitimateSong(reviewVideo), isFalse);

      const reactionVideo = YouTubeVideo(
        id: 'react_001',
        title: 'First Time Hearing AR Rahman Reacts',
        channelTitle: 'MusicLoversReact',
        thumbnailUrl: 'https://i.ytimg.com/vi/react_001/hqdefault.jpg',
        duration: '8:45',
        viewCount: '300K views',
        rawTitle: 'American Reacts to Kaadhalai Solla Mudiyaadha | First Listen',
        rawChannelTitle: 'MusicLoversReact',
      );

      expect(MusicResultClassifier.isValidIndividualSong(reactionVideo), isFalse);
    });

    test('9. Documentary and Exposé videos are STRICTLY REJECTED', () {
      const docVideo = YouTubeVideo(
        id: 'doc_001',
        title: 'The Rise and Fall of Boy Bands',
        channelTitle: 'Vox',
        thumbnailUrl: 'https://i.ytimg.com/vi/doc_001/hqdefault.jpg',
        duration: '18:30',
        viewCount: '2.1M views',
        rawTitle: 'The Rise and Fall of 90s Pop Music | Video Essay Documentary',
        rawChannelTitle: 'Vox',
      );

      expect(MusicResultClassifier.isValidIndividualSong(docVideo), isFalse);
      expect(MusicResultClassifier.isValidMusicTrack(docVideo), isFalse);
      expect(RecommendationService.isLegitimateSong(docVideo), isFalse);
    });
  });

  group('PHASE 4: Artwork Provider System Audit & Integrity Suite', () {
    test('1. ArtworkQuery implements value equality and hashCode', () {
      const q1 = ArtworkQuery(
        id: 'track-1',
        title: 'Kaadhalai Solla Mudiyaadha',
        artist: 'A. R. Rahman',
        fallbackThumbnailUrl: 'https://example.com/art1.jpg',
      );

      const q2 = ArtworkQuery(
        id: 'track-2',
        title: 'kaadhalai solla mudiyaadha',
        artist: 'A.R. Rahman',
        fallbackThumbnailUrl: 'https://example.com/art2.jpg',
      );

      expect(q1.cacheKey, equals(q2.cacheKey));
      expect(q1, equals(q2));
      expect(q1.hashCode, equals(q2.hashCode));

      final set = <ArtworkQuery>{q1};
      expect(set.contains(q2), isTrue);
    });

    test('2. YouTubeFallbackProvider returns verified fallback thumbnail', () async {
      final provider = YouTubeFallbackProvider();
      const query = ArtworkQuery(
        id: 'yt-1',
        title: 'Chaleya',
        artist: 'Anirudh',
        fallbackThumbnailUrl: 'https://i.ytimg.com/vi/VAdGW7QDJhU/hqdefault.jpg',
      );

      final artwork = await provider.resolve(query);
      expect(artwork, isNotNull);
      expect(artwork!.imageUrl, equals('https://i.ytimg.com/vi/VAdGW7QDJhU/hqdefault.jpg'));
      expect(artwork.source, equals(ArtworkSource.youtube));
    });

    test('3. Neutral fallback is NOT permanently cached into persistent Hive', () async {
      final resolver = ArtworkResolver();
      const query = ArtworkQuery(
        id: 'unknown-999',
        title: 'ZzZz Nonexistent Track',
        artist: 'ZzZz Unknown Artist',
        fallbackThumbnailUrl: null,
      );

      final resolved = await resolver.resolve(query);
      expect(resolved.isNeutralFallback, isTrue);

      // Verify resolver didn't store a neutral fallback in persistent cache
      expect(resolver.cache.get(query.cacheKey), isNull);
    });

    test('4. PlaylistModel.effectiveCoverUrl respects priority order', () {
      const track1 = Track(
        id: 't-1',
        title: 'Song 1',
        artist: 'Artist 1',
        imageUrl: 'https://example.com/song1.jpg',
        duration: '3:30',
      );

      // Playlist with track artwork, but no custom cover
      final p1 = PlaylistModel(
        id: 'pl-1',
        name: 'My Playlist',
        tracks: [track1],
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
      );
      expect(p1.effectiveCoverUrl, equals('https://example.com/song1.jpg'));

      // Playlist with custom cover overrides track artwork
      final p2 = p1.copyWith(customCoverPath: '/data/user/0/covers/custom.jpg');
      expect(p2.effectiveCoverUrl, equals('/data/user/0/covers/custom.jpg'));

      // Empty playlist without custom cover returns null
      final pEmpty = PlaylistModel(
        id: 'pl-empty',
        name: 'Empty Playlist',
        tracks: const [],
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
      );
      expect(pEmpty.effectiveCoverUrl, isNull);
    });
  });
}

