import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/metadata/domain/musicbrainz_models.dart';
import 'package:Miee/features/metadata/data/musicbrainz_rate_limiter.dart';
import 'package:Miee/features/metadata/data/musicbrainz_service.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/features/youtube/domain/music_result_classifier.dart';

void main() {
  group('MusicBrainz & Free Music Discovery Architecture Tests', () {
    test('1. MusicBrainzRateLimiter enforces sequential spacing between requests', () async {
      final limiter = MusicBrainzRateLimiter(minInterval: const Duration(milliseconds: 50));
      final timestamps = <DateTime>[];

      await Future.wait([
        limiter.schedule(() async {
          timestamps.add(DateTime.now());
          return 1;
        }),
        limiter.schedule(() async {
          timestamps.add(DateTime.now());
          return 2;
        }),
        limiter.schedule(() async {
          timestamps.add(DateTime.now());
          return 3;
        }),
      ]);

      expect(timestamps.length, equals(3));
      final diff1 = timestamps[1].difference(timestamps[0]).inMilliseconds;
      final diff2 = timestamps[2].difference(timestamps[1]).inMilliseconds;

      expect(diff1, greaterThanOrEqualTo(40),
          reason: 'Second call must be delayed by at least ~50ms from first call');
      expect(diff2, greaterThanOrEqualTo(40),
          reason: 'Third call must be delayed by at least ~50ms from second call');
    });

    test('2. MusicBrainzRecording.fromJson parses full structured recording metadata', () {
      final json = {
        'id': 'b8d4e92b-8a8b-4b2a-89a1-0268a731efc1',
        'title': 'Brooklyn Baby',
        'length': 351000,
        'artist-credit': [
          {
            'name': 'Lana Del Rey',
            'artist': {
              'id': 'b7539c32-53e7-4908-bda3-81449c367da6',
              'name': 'Lana Del Rey',
              'sort-name': 'Del Rey, Lana',
            },
            'joinphrase': '',
          }
        ],
        'releases': [
          {
            'id': '9a13b5e4-7d52-45e3-9781-a7fc1c55bc78',
            'title': 'Ultraviolence',
            'release-group': {
              'id': '34e022f4-e51c-4b68-b3ee-3fca3bb5f2b8',
              'title': 'Ultraviolence',
              'primary-type': 'Album',
            },
            'date': '2014-06-13',
            'country': 'US',
          }
        ],
        'isrcs': ['USUM71407335'],
      };

      final rec = MusicBrainzRecording.fromJson(json);

      expect(rec.mbid, equals('b8d4e92b-8a8b-4b2a-89a1-0268a731efc1'));
      expect(rec.title, equals('Brooklyn Baby'));
      expect(rec.artistCredit, equals('Lana Del Rey'));
      expect(rec.primaryArtist, equals('Lana Del Rey'));
      expect(rec.primaryArtistMbid, equals('b7539c32-53e7-4908-bda3-81449c367da6'));
      expect(rec.durationMs, equals(351000));
      expect(rec.formattedDuration, equals('5:51'));
      expect(rec.albumTitle, equals('Ultraviolence'));
      expect(rec.releaseMbid, equals('9a13b5e4-7d52-45e3-9781-a7fc1c55bc78'));
      expect(rec.releaseGroupMbid, equals('34e022f4-e51c-4b68-b3ee-3fca3bb5f2b8'));
      expect(rec.isrc, equals('USUM71407335'));
    });

    test('3. MusicBrainzArtist.fromJson parses structured artist entity', () {
      final json = {
        'id': 'b7539c32-53e7-4908-bda3-81449c367da6',
        'name': 'Lana Del Rey',
        'sort-name': 'Del Rey, Lana',
        'type': 'Person',
        'country': 'US',
        'disambiguation': 'American singer-songwriter',
        'score': 100,
      };

      final artist = MusicBrainzArtist.fromJson(json);

      expect(artist.mbid, equals('b7539c32-53e7-4908-bda3-81449c367da6'));
      expect(artist.name, equals('Lana Del Rey'));
      expect(artist.sortName, equals('Del Rey, Lana'));
      expect(artist.type, equals('Person'));
      expect(artist.country, equals('US'));
      expect(artist.disambiguation, equals('American singer-songwriter'));
      expect(artist.score, equals(100));
    });

    test('4. YouTubeVideo.fromMusicBrainzRecording transforms canonical recording to playback candidate', () {
      const rec = MusicBrainzRecording(
        mbid: 'b8d4e92b-8a8b-4b2a-89a1-0268a731efc1',
        title: 'Brooklyn Baby',
        artistCredit: 'Lana Del Rey',
        primaryArtist: 'Lana Del Rey',
        primaryArtistMbid: 'b7539c32-53e7-4908-bda3-81449c367da6',
        durationMs: 351000,
        albumTitle: 'Ultraviolence',
        releaseMbid: '9a13b5e4-7d52-45e3-9781-a7fc1c55bc78',
        releaseGroupMbid: '34e022f4-e51c-4b68-b3ee-3fca3bb5f2b8',
        isrc: 'USUM71407335',
      );

      final video = YouTubeVideo.fromMusicBrainzRecording(rec);

      expect(video.id, equals('mb_b8d4e92b-8a8b-4b2a-89a1-0268a731efc1'));
      expect(video.title, equals('Brooklyn Baby'));
      expect(video.channelTitle, equals('Lana Del Rey'));
      expect(video.duration, equals('5:51'));
      expect(video.albumName, equals('Ultraviolence'));
      expect(video.metadataProvider, equals('musicbrainz'));
      expect(video.mbid, equals('b8d4e92b-8a8b-4b2a-89a1-0268a731efc1'));
      expect(video.recordingMbid, equals('b8d4e92b-8a8b-4b2a-89a1-0268a731efc1'));
      expect(video.releaseMbid, equals('9a13b5e4-7d52-45e3-9781-a7fc1c55bc78'));

      // Check conversion to Track model
      final track = video.toTrack();
      expect(track.id, equals('youtube_mb_b8d4e92b-8a8b-4b2a-89a1-0268a731efc1'));
      expect(track.title, equals('Brooklyn Baby'));
      expect(track.artist, equals('Lana Del Rey'));
      expect(track.albumName, equals('Ultraviolence'));
      expect(track.mbid, equals('b8d4e92b-8a8b-4b2a-89a1-0268a731efc1'));
      expect(track.recordingMbid, equals('b8d4e92b-8a8b-4b2a-89a1-0268a731efc1'));
      expect(track.releaseMbid, equals('9a13b5e4-7d52-45e3-9781-a7fc1c55bc78'));
    });

    test('5. Track model preserves MBID fields across copyWith and conversions', () {
      final track = Track(
        id: 't1',
        title: 'All The Stars',
        artist: 'Kendrick Lamar, SZA',
        albumName: 'Black Panther: The Album',
        imageUrl: 'https://example.com/cover.jpg',
        duration: '3:55',
        mbid: 'rec_mbid_123',
        recordingMbid: 'rec_mbid_123',
        releaseMbid: 'rel_mbid_456',
        artistMbid: 'art_mbid_789',
      );

      final copied = track.copyWith(title: 'All The Stars (Remastered)');
      expect(copied.title, equals('All The Stars (Remastered)'));
      expect(copied.mbid, equals('rec_mbid_123'));
      expect(copied.recordingMbid, equals('rec_mbid_123'));
      expect(copied.releaseMbid, equals('rel_mbid_456'));
      expect(copied.artistMbid, equals('art_mbid_789'));
    });

    test('6. TrackHiveModel backward-compatible serialization with MBID fields (indices 17, 18, 19)', () {
      final track = Track(
        id: 't_hive',
        title: 'Starboy',
        artist: 'The Weeknd',
        albumName: 'Starboy',
        imageUrl: 'https://example.com/starboy.jpg',
        duration: '3:50',
        mbid: 'mbid_starboy',
        recordingMbid: 'rec_starboy',
        releaseMbid: 'rel_starboy',
      );

      final hiveModel = TrackHiveModel.fromTrack(track);
      expect(hiveModel.mbid, equals('mbid_starboy'));
      expect(hiveModel.recordingMbid, equals('rec_starboy'));
      expect(hiveModel.releaseMbid, equals('rel_starboy'));

      final restored = hiveModel.toTrack();
      expect(restored.mbid, equals('mbid_starboy'));
      expect(restored.recordingMbid, equals('rec_starboy'));
      expect(restored.releaseMbid, equals('rel_starboy'));
    });

    test('7. Cover Art Archive front URL formation handles release and release-group endpoints', () {
      final service = MusicBrainzService();

      final releaseUrl = service.buildCoverArtArchiveUrl(releaseMbid: '9a13b5e4-7d52-45e3-9781-a7fc1c55bc78');
      expect(releaseUrl, equals('https://coverartarchive.org/release/9a13b5e4-7d52-45e3-9781-a7fc1c55bc78/front-500'));

      final releaseGroupUrl = service.buildCoverArtArchiveUrl(releaseGroupMbid: '34e022f4-e51c-4b68-b3ee-3fca3bb5f2b8');
      expect(releaseGroupUrl, equals('https://coverartarchive.org/release-group/34e022f4-e51c-4b68-b3ee-3fca3bb5f2b8/front-500'));

      final fallbackUrl = service.buildCoverArtArchiveUrl();
      expect(fallbackUrl, isNull);
    });

    test('8. MusicResultClassifier recognizes musicbrainz metadata provider as verified music', () {
      const mbCandidate = YouTubeVideo(
        id: 'mb_sample_1',
        title: 'A.R. Rahman - Urvasi Urvasi',
        channelTitle: 'A.R. Rahman',
        thumbnailUrl: '',
        duration: '5:42',
        viewCount: '10M views',
        metadataProvider: 'musicbrainz',
      );

      final verdict = MusicResultClassifier.classify(mbCandidate);
      expect(verdict.isMusic, isTrue);
      expect(verdict.confidence, equals(MusicTrackConfidence.officialMusic));
    });
  });
}
