import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/core/widget/miee_widget_sync_service.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/shared/utils/display_title_normalizer.dart';

void main() {
  group('DisplayTitleNormalizer', () {
    test(
        'strips / Music and promotional source tags while preserving version info',
        () {
      expect(
        DisplayTitleNormalizer.normalize('Who Is This Dude? / Music'),
        'Who Is This Dude?',
      );
      expect(
        DisplayTitleNormalizer.normalize(
            'Oorum Blood (Official Audio) [Lyrics]'),
        'Oorum Blood',
      );
      expect(
        DisplayTitleNormalizer.normalize(
            'Veezha Veera - Official Video (Lyrics)'),
        'Veezha Veera',
      );
      expect(
        DisplayTitleNormalizer.normalize('Oorum Blood (Unplugged)'),
        'Oorum Blood (Unplugged)',
      );
      expect(
        DisplayTitleNormalizer.normalize('Song Name (Remix) [Official Audio]'),
        'Song Name (Remix)',
      );
      expect(
        DisplayTitleNormalizer.normalize('Theme (Live) / Music'),
        'Theme (Live)',
      );
      expect(
        DisplayTitleNormalizer.normalize('Melody (Acoustic)'),
        'Melody (Acoustic)',
      );
      expect(
        DisplayTitleNormalizer.normalize('Score (Instrumental)'),
        'Score (Instrumental)',
      );
      expect(
        DisplayTitleNormalizer.normalize('Kannaana Kanney (Tamil)'),
        'Kannaana Kanney (Tamil)',
      );
    });
  });

  group('No YouTube Thumbnail Fallback', () {
    test('Track.copyWith and TrackHiveModel do not synthesize i.ytimg.com URLs',
        () {
      const track = Track(
        id: 'youtube_JGebNY0X5EY',
        title: 'Who Is This Dude? / Music',
        artist: 'Sai Abhyankkar',
        imageUrl: '',
        duration: '0:43',
      );
      expect(track.displayTitle, 'Who Is This Dude?');
      expect(track.title, 'Who Is This Dude? / Music');
      expect(track.copyWith().imageUrl, '');

      final hive = TrackHiveModel.fromTrack(track);
      expect(hive.imageUrl, '');
      expect(hive.toTrack().imageUrl, '');
    });

    test(
        'extractWidgetArtworkFields rejects YouTube thumbnails and never synthesizes i.ytimg.com',
        () {
      final fields = extractWidgetArtworkFields(
        trackId: 'youtube_JGebNY0X5EY',
        imageUrl: 'https://i.ytimg.com/vi/JGebNY0X5EY/hqdefault.jpg',
        filePath: '',
        isYoutube: true,
        sourceId: 'JGebNY0X5EY',
      );
      expect(fields.artworkUrl, isEmpty);
      expect(fields.artworkPath, isEmpty);
    });
  });
}
