import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/music_result_classifier.dart';
import 'package:Miee/features/search/data/playback_source_resolver.dart';
import 'package:Miee/shared/models/track.dart';

class _MockYouTubeRepository extends YouTubeRepository {
  final Map<String, List<YouTubeVideo>> mockedResponses;

  _MockYouTubeRepository(this.mockedResponses);

  @override
  Future<List<YouTubeVideo>> search(String query, {int page = 1, bool forceFresh = false}) async {
    final qLower = query.toLowerCase();
    for (final entry in mockedResponses.entries) {
      if (qLower.contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return const [];
  }
}

void main() {
  group('Phase 1.1: Playback Resolution & Search Accuracy Tests', () {
    test('1. All The Stars — Kendrick Lamar & SZA resolves authentic Topic/Official Audio over scene clip and cover', () async {
      const vTopic = YouTubeVideo(
        id: 'GfCqMv--ncA',
        title: 'All The Stars',
        channelTitle: 'Kendrick Lamar - Topic',
        thumbnailUrl: '',
        duration: '3:53',
        viewCount: '150M views',
      );

      const vVevo = YouTubeVideo(
        id: 'JQbjS0_ZfJ0',
        title: 'Kendrick Lamar, SZA - All The Stars (Official Music Video)',
        channelTitle: 'KendrickLamarVEVO',
        thumbnailUrl: '',
        duration: '3:55',
        viewCount: '550M views',
      );

      const vSceneClip = YouTubeVideo(
        id: 'sceneClip123',
        title: '[BLACK PANTHER] (2018) All The Stars Scene Clip',
        channelTitle: 'Kshitiz Singh',
        thumbnailUrl: '',
        duration: '2:51',
        viewCount: '3.1M views',
      );

      const vCover = YouTubeVideo(
        id: 'cover999',
        title: 'All The Stars - Kendrick Lamar & SZA (Acoustic Cover)',
        channelTitle: 'CoversBySam',
        thumbnailUrl: '',
        duration: '3:45',
        viewCount: '12K views',
      );

      final repo = _MockYouTubeRepository({
        'All The Stars': [vSceneClip, vCover, vTopic, vVevo],
      });
      final resolver = PlaybackSourceResolver.withRepository(repo);

      final resolvedId = await resolver.resolveVideoId(
        title: 'All The Stars',
        artist: 'Kendrick Lamar, SZA',
        durationStr: '3:52',
      );

      expect(resolvedId, equals('GfCqMv--ncA'),
          reason: 'Kendrick Lamar - Topic must be chosen over the scene clip and cover');
    });

    test('2. I Thought I Saw Your Face Today — She & Him resolves authentic duo recording', () async {
      const vOfficialAudio = YouTubeVideo(
        id: 'sheHim12345',
        title: 'I Thought I Saw Your Face Today (Official Audio)',
        channelTitle: 'She & Him - Topic',
        thumbnailUrl: '',
        duration: '2:53',
        viewCount: '500K views',
      );

      const vCover = YouTubeVideo(
        id: 'coverXyz',
        title: 'I Thought I Saw Your Face Today - She and Him Cover',
        channelTitle: 'Indie Covers',
        thumbnailUrl: '',
        duration: '3:05',
        viewCount: '2K views',
      );

      final repo = _MockYouTubeRepository({
        'I Thought I Saw Your Face Today': [vCover, vOfficialAudio],
      });
      final resolver = PlaybackSourceResolver.withRepository(repo);

      final resolvedId = await resolver.resolveVideoId(
        title: 'I Thought I Saw Your Face Today',
        artist: 'She & Him',
        durationStr: '2:53',
      );

      expect(resolvedId, equals('sheHim12345'));
    });

    test('3. Song with featured artists matches channel of primary or featured collaborator', () async {
      const vCollab = YouTubeVideo(
        id: 'collab11111',
        title: 'Levitating (feat. DaBaby) [Official Audio]',
        channelTitle: 'Dua Lipa',
        thumbnailUrl: '',
        duration: '3:23',
        viewCount: '80M views',
      );

      final repo = _MockYouTubeRepository({
        'Levitating': [vCollab],
      });
      final resolver = PlaybackSourceResolver.withRepository(repo);

      final resolvedId = await resolver.resolveVideoId(
        title: 'Levitating',
        artist: 'Dua Lipa feat. DaBaby',
        durationStr: '3:23',
      );

      expect(resolvedId, equals('collab11111'));
    });

    test('4. Song with multiple legitimate versions selects version matching requested type', () async {
      const vStudio = YouTubeVideo(
        id: 'studioVer11',
        title: 'Shape of You (Official Audio)',
        channelTitle: 'Ed Sheeran - Topic',
        thumbnailUrl: '',
        duration: '3:53',
        viewCount: '200M views',
      );

      const vAcoustic = YouTubeVideo(
        id: 'acoustic111',
        title: 'Shape of You (Acoustic)',
        channelTitle: 'Ed Sheeran',
        thumbnailUrl: '',
        duration: '3:45',
        viewCount: '50M views',
      );

      final repo = _MockYouTubeRepository({
        'Shape of You': [vAcoustic, vStudio],
      });
      final resolver = PlaybackSourceResolver.withRepository(repo);

      // 4a. Default studio search resolves to studio audio
      final studioId = await resolver.resolveVideoId(
        title: 'Shape of You',
        artist: 'Ed Sheeran',
        durationStr: '3:53',
      );
      expect(studioId, equals('studioVer11'));
    });

    test('5. Live version versus studio recording prioritizes live version only when requested', () async {
      const vStudio = YouTubeVideo(
        id: 'hotelStudio',
        title: 'Hotel California',
        channelTitle: 'Eagles - Topic',
        thumbnailUrl: '',
        duration: '6:31',
        viewCount: '100M views',
      );

      const vLive = YouTubeVideo(
        id: 'hotelLive88',
        title: 'Hotel California (Live On MTV 1994)',
        channelTitle: 'Eagles',
        thumbnailUrl: '',
        duration: '7:12',
        viewCount: '400M views',
      );

      final repo = _MockYouTubeRepository({
        'Hotel California': [vLive, vStudio],
      });

      // When seeking studio recording (duration 6:31), studio version wins
      final studioResolver = PlaybackSourceResolver.withRepository(repo);
      final resolvedStudio = await studioResolver.resolveVideoId(
        title: 'Hotel California',
        artist: 'Eagles',
        durationStr: '6:31',
      );
      expect(resolvedStudio, equals('hotelStudio'));

      // When seeking explicitly live recording, live version wins
      final liveResolver = PlaybackSourceResolver.withRepository(repo);
      final resolvedLive = await liveResolver.resolveVideoId(
        title: 'Hotel California (Live)',
        artist: 'Eagles',
        durationStr: '7:12',
      );
      expect(resolvedLive, equals('hotelLive88'));
    });

    test('6. Cover or karaoke candidate is penalized and rejected for canonical studio search', () async {
      const vKaraoke = YouTubeVideo(
        id: 'karaoke1234',
        title: 'Someone Like You (Karaoke Version)',
        channelTitle: 'Sing King Karaoke',
        thumbnailUrl: '',
        duration: '4:45',
        viewCount: '5M views',
      );

      const vCover = YouTubeVideo(
        id: 'cover987654',
        title: 'Someone Like You - Adele Cover',
        channelTitle: 'Guitar Covers',
        thumbnailUrl: '',
        duration: '4:40',
        viewCount: '100K views',
      );

      final repo = _MockYouTubeRepository({
        'Someone Like You': [vKaraoke, vCover],
      });
      final resolver = PlaybackSourceResolver.withRepository(repo);

      final resolvedId = await resolver.resolveVideoId(
        title: 'Someone Like You',
        artist: 'Adele',
        durationStr: '4:45',
      );

      expect(resolvedId, isNull,
          reason: 'Karaoke and Cover must be rejected when searching for Adele studio track');
    });

    test('7. Movie scene clip with song title in title is penalized and rejected', () async {
      const vMovieScene = YouTubeVideo(
        id: 'sceneClip99',
        title: '[BLACK PANTHER] (2018) Car Chase Ending Scene Clip Full HD',
        channelTitle: 'Movie Vault Scenes',
        thumbnailUrl: '',
        duration: '3:50',
        viewCount: '10M views',
      );

      final repo = _MockYouTubeRepository({
        'All The Stars': [vMovieScene],
      });
      final resolver = PlaybackSourceResolver.withRepository(repo);

      final resolvedId = await resolver.resolveVideoId(
        title: 'All The Stars',
        artist: 'Kendrick Lamar, SZA',
        durationStr: '3:52',
      );

      expect(resolvedId, isNull,
          reason: 'Movie scene clip must never be resolved as playback source');
    });

    test('8. MusicBrainz result with no valid YouTube match safely returns null without random fallback', () async {
      const vRandomUnrelated = YouTubeVideo(
        id: 'randomVlog1',
        title: 'My Morning Routine In Brooklyn with Baby',
        channelTitle: 'Daily Vlogger',
        thumbnailUrl: '',
        duration: '15:20', // huge duration discrepancy!
        viewCount: '10K views',
      );

      final repo = _MockYouTubeRepository({
        'Brooklyn Baby': [vRandomUnrelated],
      });
      final resolver = PlaybackSourceResolver.withRepository(repo);

      final resolvedId = await resolver.resolveVideoId(
        title: 'Brooklyn Baby',
        artist: 'Lana Del Rey',
        durationStr: '5:51',
      );

      expect(resolvedId, isNull,
          reason: 'Resolver must return null when only unrelated videos exist instead of picking arbitrary video');
    });

    test('9. Valid MusicBrainz result passes MusicResultClassifier without false rejection', () {
      const mbCandidate = YouTubeVideo(
        id: 'mb_rec_12345',
        title: 'Brooklyn Baby',
        channelTitle: 'Lana Del Rey',
        thumbnailUrl: '',
        duration: '5:51',
        viewCount: '',
        metadataProvider: 'musicbrainz',
      );

      final verdict = MusicResultClassifier.classify(mbCandidate);
      expect(verdict.isMusic, isTrue);
      expect(verdict.confidence, equals(MusicTrackConfidence.officialMusic));
      expect(MusicResultClassifier.isValidIndividualSong(mbCandidate), isTrue);
      expect(MusicResultClassifier.isValidMusicTrack(mbCandidate), isTrue);

      final track = mbCandidate.toTrack();
      expect(track.metadataProvider, equals('musicbrainz'));
    });
  });
}
