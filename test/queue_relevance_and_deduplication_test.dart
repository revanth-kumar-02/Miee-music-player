import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/youtube/domain/music_result_classifier.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  group('Miee — Queue Relevance, Duplicate Songs & Unrelated YouTube Results Tests', () {
    // 1. The exact scenario from user screenshot: "One Sun One Moon" search and queue playback
    test('1. "One Sun One Moon" queue deduplicates alternate uploads, excludes Batman fan edit, and preserves distinct songs', () {
      final sunTvNowPlaying = const YouTubeVideo(
        id: 'yt_sun_one_sun',
        title: 'One Sun One Moon',
        channelTitle: 'Sun TV',
        thumbnailUrl: 'https://img.youtube.com/vi/yt_sun_one_sun/hqdefault.jpg',
        duration: '3:30',
        viewCount: '15M views',
        rawTitle: 'One Sun One Moon | Sun TV',
        rawChannelTitle: 'Sun TV',
        rawViewCount: 15000000,
      );

      final lyricalRedDuplicate = const YouTubeVideo(
        id: 'yt_lyrical_red',
        title: 'One Sun One Moon',
        channelTitle: 'LyricalRed',
        thumbnailUrl: 'https://img.youtube.com/vi/yt_lyrical_red/hqdefault.jpg',
        duration: '3:30',
        viewCount: '500K views',
        rawTitle: 'One Sun One Moon',
        rawChannelTitle: 'LyricalRed',
        rawViewCount: 500000,
      );

      final sunGeminiLyricVideo = const YouTubeVideo(
        id: 'yt_sun_gemini',
        title: 'One Sun One Moon - Lyric Video',
        channelTitle: 'Sun Gemini',
        thumbnailUrl: 'https://img.youtube.com/vi/yt_sun_gemini/hqdefault.jpg',
        duration: '3:36',
        viewCount: '2M views',
        rawTitle: 'One Sun One Moon - Lyric Video | Sun Gemini',
        rawChannelTitle: 'Sun Gemini',
        rawViewCount: 2000000,
      );

      final toono1CutUpload = const YouTubeVideo(
        id: 'yt_toono1',
        title: 'One Sun One Moon - Jailer',
        channelTitle: 'HellO MR.TooNO1',
        thumbnailUrl: 'https://img.youtube.com/vi/yt_toono1/hqdefault.jpg',
        duration: '2:34',
        viewCount: '100K views',
        rawTitle: 'One Sun One Moon - Jailer BGM Scene',
        rawChannelTitle: 'HellO MR.TooNO1',
        rawViewCount: 100000,
      );

      final batmanFanEdit = const YouTubeVideo(
        id: 'yt_batman_edit',
        title: 'BATMAN ft:- One Sun One Moon',
        channelTitle: 'RBob_Editz',
        thumbnailUrl: 'https://img.youtube.com/vi/yt_batman_edit/hqdefault.jpg',
        duration: '3:30',
        viewCount: '80K views',
        rawTitle: 'BATMAN ft:- One Sun One Moon | 4K Edit',
        rawChannelTitle: 'RBob_Editz',
        rawViewCount: 80000,
      );

      final oneNameSong = const YouTubeVideo(
        id: 'yt_one_name',
        title: 'One Name',
        channelTitle: 'Sun TV',
        thumbnailUrl: 'https://img.youtube.com/vi/yt_one_name/hqdefault.jpg',
        duration: '3:25',
        viewCount: '8M views',
        rawTitle: 'One Name | Sun TV',
        rawChannelTitle: 'Sun TV',
        rawViewCount: 8000000,
      );

      final jailerHukumSong = const YouTubeVideo(
        id: 'yt_jailer_hukum',
        title: 'JAILER - Hukum',
        channelTitle: 'Sun TV',
        thumbnailUrl: 'https://img.youtube.com/vi/yt_jailer_hukum/hqdefault.jpg',
        duration: '3:27',
        viewCount: '250M views',
        rawTitle: 'JAILER - Hukum | Sun TV',
        rawChannelTitle: 'Sun TV',
        rawViewCount: 250000000,
      );

      final alaSong = const YouTubeVideo(
        id: 'yt_ala_song',
        title: 'Ala Pole',
        channelTitle: 'Sun TV',
        thumbnailUrl: 'https://img.youtube.com/vi/yt_ala_song/hqdefault.jpg',
        duration: '4:02',
        viewCount: '12M views',
        rawTitle: 'Ala Pole | Sun TV',
        rawChannelTitle: 'Sun TV',
        rawViewCount: 12000000,
      );

      final searchResults = [
        sunTvNowPlaying,
        lyricalRedDuplicate,
        sunGeminiLyricVideo,
        toono1CutUpload,
        batmanFanEdit,
        oneNameSong,
        jailerHukumSong,
        alaSong,
      ];

      // A. Verify Classifier rejects the Batman fan edit
      expect(
        MusicResultClassifier.isValidIndividualSong(batmanFanEdit, query: 'One Sun One Moon'),
        isFalse,
      );

      // B. Verify EditType detects fan edit / mashup
      final intent = QueryIntent.fromQuery('One Sun One Moon');
      expect(
        SearchDeduplicator.detectEditType(batmanFanEdit, intent),
        anyOf(
          equals(EditType.fanEdit),
          equals(EditType.mashupRemake),
          equals(EditType.nonMusicEntertainment),
        ),
      );

      // C. Simulate queue construction from SearchPage
      final validVideos = searchResults.where((v) {
        if (!MusicResultClassifier.isValidIndividualSong(v, query: 'One Sun One Moon')) {
          return false;
        }
        final editType = SearchDeduplicator.detectEditType(v, intent);
        return editType != EditType.fanEdit &&
            editType != EditType.fourKEdit &&
            editType != EditType.statusVideo &&
            editType != EditType.compilationMix &&
            editType != EditType.mashupRemake &&
            editType != EditType.nonMusicEntertainment;
      }).toList();

      final targetTrack = sunTvNowPlaying.toTrack();
      final queueTracks = <MusicItem>[targetTrack];
      final seenKeys = <String>{SearchDeduplicator.computeRecordingKey(targetTrack)};
      final seenIds = <String>{sunTvNowPlaying.id};

      for (final v in validVideos) {
        if (v.id == sunTvNowPlaying.id || seenIds.contains(v.id)) continue;
        final track = v.toTrack();
        final recKey = SearchDeduplicator.computeRecordingKey(track);
        if (seenKeys.add(recKey)) {
          seenIds.add(v.id);
          queueTracks.add(track);
        }
      }

      // Check results
      // 1. Now Playing must be the selected track: "One Sun One Moon" (Sun TV)
      expect(queueTracks.first.title, 'One Sun One Moon');
      expect(queueTracks.first.id, 'youtube_yt_sun_one_sun');
      expect(queueTracks.first.artist, 'Sun TV');

      // 2. Next Up MUST NOT contain duplicate uploads of "One Sun One Moon"
      final nextUpTracks = queueTracks.skip(1).toList();
      final nextUpTitles = nextUpTracks.map((t) => t.title.toLowerCase()).toList();
      final nextUpIds = nextUpTracks.map((t) => t.id).toList();

      expect(nextUpIds, isNot(contains('youtube_yt_lyrical_red')));
      expect(nextUpIds, isNot(contains('youtube_yt_sun_gemini')));
      expect(nextUpIds, isNot(contains('youtube_yt_toono1')));
      expect(nextUpIds, isNot(contains('youtube_yt_batman_edit')));

      // 3. Next Up MUST preserve distinct legitimate songs from the search results
      expect(nextUpTitles, contains('one name'));
      expect(nextUpTitles, contains('jailer - hukum'));
      expect(nextUpTitles, contains('ala pole'));

      // Total queue size should be 4 (1 now playing + 3 distinct songs)
      expect(queueTracks.length, 4);
    });

    // 2. QueueManager order, Next advance, and exact track identity preservation
    test('2. Queue advances cleanly through distinct songs without repeating recordings', () {
      final queueManager = QueueManager();

      final track1 = const Track(
        id: 'youtube_track_1',
        title: 'One Sun One Moon',
        artist: 'Sun TV',
        imageUrl: '',
        duration: '3:30',
      );
      final track2 = const Track(
        id: 'youtube_track_2',
        title: 'One Name',
        artist: 'Sun TV',
        imageUrl: '',
        duration: '3:25',
      );
      final track3 = const Track(
        id: 'youtube_track_3',
        title: 'JAILER - Hukum',
        artist: 'Sun TV',
        imageUrl: '',
        duration: '3:27',
      );

      queueManager.setQueue([track1, track2, track3], startIndex: 0);

      expect(queueManager.currentTrack?.id, 'youtube_track_1');
      expect(queueManager.currentIndex, 0);

      // Advance to next
      final next1 = queueManager.next();
      expect(next1?.id, 'youtube_track_2');
      expect(next1?.title, 'One Name');

      // Advance to next again
      final next2 = queueManager.next();
      expect(next2?.id, 'youtube_track_3');
      expect(next2?.title, 'JAILER - Hukum');

      // Previous returns to One Name
      final prev1 = queueManager.previous();
      expect(prev1?.id, 'youtube_track_2');
      expect(prev1?.title, 'One Name');
    });

    // 3. Different songs sharing the same title by different genuine artists are preserved
    test('3. Songs with the same title by different non-generic artists are not merged', () {
      final adeleHello = const Track(
        id: 'yt_adele_hello',
        title: 'Hello',
        artist: 'Adele',
        imageUrl: '',
        duration: '4:55',
      );

      final lionelHello = const Track(
        id: 'yt_lionel_hello',
        title: 'Hello',
        artist: 'Lionel Richie',
        imageUrl: '',
        duration: '5:07',
      );

      expect(
        SearchDeduplicator.isSameCanonicalRecording(adeleHello, lionelHello),
        isFalse,
      );

      final keyAdele = SearchDeduplicator.computeRecordingKey(adeleHello);
      final keyLionel = SearchDeduplicator.computeRecordingKey(lionelHello);
      expect(keyAdele, isNot(equals(keyLionel)));
    });

    // 4. Legitimate version variations (Remix, Live, Acoustic, Cover) are preserved
    test('4. Legitimate artistic variations (Remix, Live, Acoustic, Cover) are preserved', () {
      final standard = const Track(
        id: 'track_std',
        title: 'One Sun One Moon',
        artist: 'Sun TV',
        imageUrl: '',
        duration: '3:30',
      );

      final remix = const Track(
        id: 'track_remix',
        title: 'One Sun One Moon (Club Remix)',
        artist: 'Sun TV',
        imageUrl: '',
        duration: '3:15',
      );

      final live = const Track(
        id: 'track_live',
        title: 'One Sun One Moon (Live in Concert)',
        artist: 'Sun TV',
        imageUrl: '',
        duration: '4:10',
      );

      final acoustic = const Track(
        id: 'track_acoustic',
        title: 'One Sun One Moon (Acoustic)',
        artist: 'Sun TV',
        imageUrl: '',
        duration: '3:20',
      );

      expect(SearchDeduplicator.isSameCanonicalRecording(standard, remix), isFalse);
      expect(SearchDeduplicator.isSameCanonicalRecording(standard, live), isFalse);
      expect(SearchDeduplicator.isSameCanonicalRecording(standard, acoustic), isFalse);

      final keyStd = SearchDeduplicator.computeRecordingKey(standard);
      final keyRemix = SearchDeduplicator.computeRecordingKey(remix);
      final keyLive = SearchDeduplicator.computeRecordingKey(live);
      final keyAcoustic = SearchDeduplicator.computeRecordingKey(acoustic);

      expect(keyStd, isNot(equals(keyRemix)));
      expect(keyStd, isNot(equals(keyLive)));
      expect(keyStd, isNot(equals(keyAcoustic)));
    });

    // 5. Alternate uploads of the same recording are recognized as duplicates
    test('5. Alternate uploads (official video, lyric video, broadcaster audio) are recognized as duplicates', () {
      final broadcastUpload = const Track(
        id: 'yt_sun_1',
        title: 'One Sun One Moon',
        artist: 'Sun TV',
        imageUrl: '',
        duration: '3:30',
      );

      final lyricUpload = const Track(
        id: 'yt_lyrical_2',
        title: 'One Sun One Moon',
        artist: 'LyricalRed',
        imageUrl: '',
        duration: '3:30',
      );

      final lyricVideoUpload = const Track(
        id: 'yt_sun_gemini_3',
        title: 'One Sun One Moon - Lyric Video',
        artist: 'Sun Gemini',
        imageUrl: '',
        duration: '3:36',
      );

      expect(SearchDeduplicator.isSameCanonicalRecording(broadcastUpload, lyricUpload), isTrue);
      expect(SearchDeduplicator.isSameCanonicalRecording(broadcastUpload, lyricVideoUpload), isTrue);
    });
  });
}
