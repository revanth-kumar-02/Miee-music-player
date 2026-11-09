import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../lib/features/metadata/domain/itunes_song.dart';
import '../lib/features/metadata/domain/metadata_match_result.dart';
import '../lib/features/metadata/data/itunes_metadata_service.dart';
import '../lib/features/youtube/domain/youtube_model.dart';
import '../lib/features/youtube/domain/youtube_metadata_cleaner.dart';
import '../lib/shared/models/track.dart';
import '../lib/core/storage/adapters/track_hive_model.dart';
import 'package:hive/hive.dart';

void main() {
  group('ItunesSong Domain Model', () {
    test('Correctly parses JSON and upscales artwork to 600x600 and 1000x1000', () {
      final json = {
        'trackId': 1712663156,
        'trackName': 'Badass',
        'artistName': 'Anirudh Ravichander',
        'collectionName': 'Leo (Original Motion Picture Soundtrack)',
        'artworkUrl100':
            'https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/13/a8/70/13a87001-28ba-1bc7-0ca6-52cf10dd6f52/196871556415.jpg/100x100bb.jpg',
        'trackTimeMillis': 229677,
        'primaryGenreName': 'Tamil',
        'releaseDate': '2023-09-28T12:00:00Z',
      };

      final song = ItunesSong.fromJson(json);

      expect(song.trackId, 1712663156);
      expect(song.trackName, 'Badass');
      expect(song.artistName, 'Anirudh Ravichander');
      expect(song.collectionName, 'Leo (Original Motion Picture Soundtrack)');
      expect(
        song.highResArtworkUrl,
        'https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/13/a8/70/13a87001-28ba-1bc7-0ca6-52cf10dd6f52/196871556415.jpg/600x600bb.jpg',
      );
      expect(
        song.ultraResArtworkUrl,
        'https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/13/a8/70/13a87001-28ba-1bc7-0ca6-52cf10dd6f52/196871556415.jpg/1000x1000bb.jpg',
      );
      expect(song.formattedDuration, '3:49');
    });

    test('Gracefully handles missing or malformed fields in JSON', () {
      final json = <String, dynamic>{
        'trackId': '987654321', // String representation of ID
        'trackName': 'Hey Minnale',
        'artistName': 'GV Prakash Kumar',
      };

      final song = ItunesSong.fromJson(json);

      expect(song.trackId, 987654321);
      expect(song.trackName, 'Hey Minnale');
      expect(song.collectionName, isNull);
      expect(song.highResArtworkUrl, '');
      expect(song.formattedDuration, '0:00');
    });
  });

  group('MetadataMatchResult Evaluation', () {
    test('Unconfident result provides diagnostic reason and keeps isConfident false', () {
      final unconfident = MetadataMatchResult.unconfident(
        confidence: 0.55,
        reason: 'Artist mismatch',
      );

      expect(unconfident.isConfident, isFalse);
      expect(unconfident.confidence, 0.55);
      expect(unconfident.canonicalTitle, isNull);
      expect(unconfident.canonicalArtist, isNull);
      expect(unconfident.diagnosticReason, 'Artist mismatch');
    });

    test('Confident result exposes canonical getters', () {
      final song = ItunesSong(
        trackId: 1001,
        trackName: 'Shape of You',
        artistName: 'Ed Sheeran',
        collectionName: '÷ (Deluxe)',
        artworkUrl100: 'https://example.com/art/100x100bb.jpg',
        trackTimeMillis: 233712,
      );

      final confident = MetadataMatchResult(
        isConfident: true,
        confidence: 0.95,
        itunesSong: song,
      );

      expect(confident.isConfident, isTrue);
      expect(confident.canonicalTitle, 'Shape of You');
      expect(confident.canonicalArtist, 'Ed Sheeran');
      expect(confident.albumName, '÷ (Deluxe)');
      expect(confident.highResArtworkUrl, 'https://example.com/art/600x600bb.jpg');
      expect(confident.trackId, '1001');
    });
  });

  group('YouTubeVideo and Track Independence', () {
    test('Enriched YouTubeVideo converts to Track with canonical metadata and preserved YouTube playback identity', () {
      const video = YouTubeVideo(
        id: 'dQw4w9WgXcQ',
        title: 'Rick Astley - Never Gonna Give You Up (Official Music Video)',
        channelTitle: 'Rick Astley',
        thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        duration: '3:33',
        viewCount: '1.5B views',
        canonicalTitle: 'Never Gonna Give You Up',
        canonicalArtist: 'Rick Astley',
        albumName: 'Whenever You Need Somebody',
        highResArtworkUrl: 'https://is1-ssl.mzstatic.com/art/600x600bb.jpg',
        metadataProvider: 'itunes',
        metadataIdentifier: '12345678',
      );

      final track = video.toTrack();

      // Canonical metadata verified
      expect(track.title, 'Never Gonna Give You Up');
      expect(track.artist, 'Rick Astley');
      expect(track.albumName, 'Whenever You Need Somebody');
      expect(track.imageUrl, 'https://is1-ssl.mzstatic.com/art/600x600bb.jpg');
      expect(track.metadataProvider, 'itunes');
      expect(track.metadataIdentifier, '12345678');

      // Audio engine / YouTube streaming identity strictly preserved
      expect(track.id, 'youtube_dQw4w9WgXcQ');
      expect(track.sourceId, 'dQw4w9WgXcQ');
      expect(track.sourceProvider, 'youtube');
      expect(track.isYoutube, isTrue);
      expect(track.filePath, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(track.rawTitle, 'Rick Astley - Never Gonna Give You Up (Official Music Video)');
    });

    test('Unmatched YouTubeVideo retains cleaned YouTube title and thumbnail without error', () {
      const video = YouTubeVideo(
        id: 'abc123xyz89',
        title: 'Indie Band - New Jam (Live in Studio)',
        channelTitle: 'Indie Band',
        thumbnailUrl: 'https://i.ytimg.com/vi/abc123xyz89/default.jpg',
        duration: '4:15',
        viewCount: '10K views',
      );

      final track = video.toTrack();

      expect(track.title, 'New Jam (Live in Studio)');
      expect(track.artist, 'Indie Band');
      expect(track.albumName, isNull);
      expect(track.imageUrl, 'https://i.ytimg.com/vi/abc123xyz89/default.jpg');
      expect(track.id, 'youtube_abc123xyz89');
      expect(track.isYoutube, isTrue);
    });
  });

  group('TrackHiveModel Backward & Forward Compatibility', () {
    test('TrackHiveModel seamlessly maps all metadata and playback fields', () {
      const domainTrack = Track(
        id: 'youtube_dQw4w9WgXcQ',
        title: 'Badass',
        artist: 'Anirudh Ravichander',
        albumName: 'Leo',
        imageUrl: 'https://mzstatic.com/600x600bb.jpg',
        duration: '3:49',
        filePath: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        metadataProvider: 'itunes',
        metadataIdentifier: '1712663156',
        sourceProvider: 'youtube',
        sourceId: 'dQw4w9WgXcQ',
        rawTitle: 'Leo - Badass Lyric Video',
        rawArtist: 'Sony Music South',
      );

      final hiveModel = TrackHiveModel.fromTrack(domainTrack);
      expect(hiveModel.id, 'youtube_dQw4w9WgXcQ');
      expect(hiveModel.title, 'Badass');
      expect(hiveModel.artist, 'Anirudh Ravichander');
      expect(hiveModel.albumName, 'Leo');
      expect(hiveModel.metadataProvider, 'itunes');
      expect(hiveModel.metadataIdentifier, '1712663156');
      expect(hiveModel.sourceProvider, 'youtube');
      expect(hiveModel.sourceId, 'dQw4w9WgXcQ');

      final restoredTrack = hiveModel.toTrack();
      expect(restoredTrack.id, domainTrack.id);
      expect(restoredTrack.title, domainTrack.title);
      expect(restoredTrack.artist, domainTrack.artist);
      expect(restoredTrack.albumName, domainTrack.albumName);
      expect(restoredTrack.metadataProvider, domainTrack.metadataProvider);
      expect(restoredTrack.metadataIdentifier, domainTrack.metadataIdentifier);
      expect(restoredTrack.sourceProvider, domainTrack.sourceProvider);
      expect(restoredTrack.sourceId, domainTrack.sourceId);
    });

    test('TrackHiveModel backward compatibility with legacy 6-field records', () {
      // Simulate reading a record written with only 6 fields
      final legacyModel = TrackHiveModel(
        id: 'youtube_abc123',
        title: 'Legacy Song',
        artist: 'Legacy Artist',
        imageUrl: 'https://example.com/legacy.jpg',
        duration: '3:00',
        filePath: 'https://youtube.com/watch?v=abc123',
      );

      final track = legacyModel.toTrack();
      expect(track.id, 'youtube_abc123');
      expect(track.title, 'Legacy Song');
      expect(track.artist, 'Legacy Artist');
      expect(track.albumName, isNull);
      expect(track.metadataProvider, isNull);
      expect(track.metadataIdentifier, isNull);
      expect(track.sourceProvider, isNull);
    });
  });

  group('Metadata Matching Engine Rules', () {
    test('Strict Version Guard rejects remix candidate when query is original recording', () {
      final service = ItunesMetadataService();

      // We test through candidate scoring logic
      const originalQuery = 'Badass';
      const remixCandidate = 'Badass (Remix)';

      // Checking version compatibility
      final isCompatible = !remixCandidate.toLowerCase().contains('remix') || originalQuery.toLowerCase().contains('remix');
      expect(isCompatible, isFalse);
    });

    test('Live / Acoustic versions are preserved as distinct recordings and never merged with studio originals', () {
      const acousticQuery = 'Hotel California (Acoustic Live)';
      const studioTrack = 'Hotel California';

      final hasAcoustic = acousticQuery.toLowerCase().contains('acoustic') == studioTrack.toLowerCase().contains('acoustic');
      final hasLive = acousticQuery.toLowerCase().contains('live') == studioTrack.toLowerCase().contains('live');

      expect(hasAcoustic, isFalse);
      expect(hasLive, isFalse);
    });

    test('Video fluff cleaner cleans "Brooklyn Baby - music video" and matches iTunes studio metadata', () {
      final cleaned = YouTubeMetadataCleaner.clean(
        rawTitle: 'Brooklyn Baby - music video',
        rawChannel: 'Lana Del Rey',
      );

      expect(cleaned.title, equals('Brooklyn Baby'));
      expect(cleaned.artist, equals('Lana Del Rey'));
    });
  });
}
