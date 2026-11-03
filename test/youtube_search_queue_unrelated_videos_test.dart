import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/features/youtube/domain/music_result_classifier.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  group('YouTube Search & Queue Playback — Unrelated Videos Prevention Suite', () {
    // ─────────────────────────────────────────────────────────────────────────
    // Test 1: User's Exact Reported Bug — Tamil Cinema Vault 14:29 Upload
    // ─────────────────────────────────────────────────────────────────────────
    test('1. Rejects 14:29 comedy scene upload by "Tamil Cinema Vault"', () {
      const comedyClip = YouTubeVideo(
        id: 'vault_clip_1',
        title: 'Goundamani Senthil Chinnathambi Ultimate Comedy Scene | Prabhu Kushboo',
        channelTitle: 'Tamil Cinema Vault',
        thumbnailUrl: 'https://img.youtube.com/vi/vault_clip_1/hqdefault.jpg',
        duration: '14:29',
        viewCount: '2.5M views',
        rawTitle: 'Goundamani Senthil Chinnathambi Ultimate Comedy Scene | Prabhu Kushboo',
        rawChannelTitle: 'Tamil Cinema Vault',
      );

      final verdict = MusicResultClassifier.classify(comedyClip);
      expect(verdict.isMusic, isFalse);
      expect(verdict.confidence, equals(MusicTrackConfidence.rejected));
      expect(
        MusicResultClassifier.isValidIndividualSong(comedyClip),
        isFalse,
      );
      expect(
        RecommendationService.isLegitimateSong(comedyClip),
        isFalse,
      );
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 2: Simulated 10-Selection Reproduction (User Pressed Next 10 Times)
    // ─────────────────────────────────────────────────────────────────────────
    test('2. 10 Consecutive Next navigations play 10/10 legitimate songs and 0 non-music uploads', () {
      final mixedPool = [
        // 1. Valid Tamil Song
        const YouTubeVideo(
          id: 'song_tamil_1',
          title: 'Arabic Kuthu - Video Song | Beast | Thalapathy Vijay | Anirudh Ravichander',
          channelTitle: 'Sun TV',
          thumbnailUrl: 'https://img.youtube.com/vi/song_tamil_1/hqdefault.jpg',
          duration: '4:39',
          viewCount: '450M views',
          rawTitle: 'Arabic Kuthu - Video Song | Beast | Thalapathy Vijay | Sun Pictures | Anirudh | Nelson',
          rawChannelTitle: 'Sun TV',
        ),
        // 2. Unsuitable: Tamil Cinema Vault comedy scene
        const YouTubeVideo(
          id: 'clip_scene_1',
          title: 'Vadivelu Winner Kaipulla Best Comedy Scene',
          channelTitle: 'Tamil Cinema Vault',
          thumbnailUrl: 'https://img.youtube.com/vi/clip_scene_1/hqdefault.jpg',
          duration: '14:29',
          viewCount: '1.2M views',
          rawTitle: 'Vadivelu Winner Kaipulla Best Comedy Scene',
          rawChannelTitle: 'Tamil Cinema Vault',
        ),
        // 3. Valid Telugu Song
        const YouTubeVideo(
          id: 'song_telugu_1',
          title: 'Samajavaragamana - Full Video Song | Ala Vaikunthapurramuloo | Allu Arjun | Sid Sriram',
          channelTitle: 'Aditya Music',
          thumbnailUrl: 'https://img.youtube.com/vi/song_telugu_1/hqdefault.jpg',
          duration: '4:20',
          viewCount: '280M views',
          rawTitle: 'Samajavaragamana - Full Video Song | Ala Vaikunthapurramuloo | Allu Arjun | Thaman S',
          rawChannelTitle: 'Aditya Music',
        ),
        // 4. Unsuitable: Movie Press Meet / Interview
        const YouTubeVideo(
          id: 'clip_interview_1',
          title: 'Leo Success Meet Press Conference Full Video | Thalapathy Vijay Speech',
          channelTitle: 'Galatta Tamil',
          thumbnailUrl: 'https://img.youtube.com/vi/clip_interview_1/hqdefault.jpg',
          duration: '22:15',
          viewCount: '3.4M views',
          rawTitle: 'Leo Success Meet Press Conference Full Video | Thalapathy Vijay Speech',
          rawChannelTitle: 'Galatta Tamil',
        ),
        // 5. Valid Malayalam Song
        const YouTubeVideo(
          id: 'song_malayalam_1',
          title: 'Illuminati - Video Song | Aavesham | Jithu Madhavan | Fahadh Faasil | Sushin Shyam',
          channelTitle: 'Think Music India',
          thumbnailUrl: 'https://img.youtube.com/vi/song_malayalam_1/hqdefault.jpg',
          duration: '3:35',
          viewCount: '110M views',
          rawTitle: 'Illuminati - Video Song | Aavesham | Jithu Madhavan | Fahadh Faasil | Sushin Shyam | Dabzee',
          rawChannelTitle: 'Think Music India',
        ),
        // 6. Unsuitable: 45-Minute Jukebox (multi-song compilation)
        const YouTubeVideo(
          id: 'clip_jukebox_1',
          title: 'A.R. Rahman Evergreen 90s Hits Audio Jukebox | Non Stop Audio Songs',
          channelTitle: 'Sony Music South',
          thumbnailUrl: 'https://img.youtube.com/vi/clip_jukebox_1/hqdefault.jpg',
          duration: '48:30',
          viewCount: '15M views',
          rawTitle: 'A.R. Rahman Evergreen 90s Hits Audio Jukebox | Non Stop Audio Songs',
          rawChannelTitle: 'Sony Music South',
        ),
        // 7. Valid Hindi Song
        const YouTubeVideo(
          id: 'song_hindi_1',
          title: 'Tum Hi Ho - Aashiqui 2 | Arijit Singh | Mithoon',
          channelTitle: 'T-Series',
          thumbnailUrl: 'https://img.youtube.com/vi/song_hindi_1/hqdefault.jpg',
          duration: '4:22',
          viewCount: '800M views',
          rawTitle: 'Tum Hi Ho - Aashiqui 2 | Arijit Singh | Mithoon',
          rawChannelTitle: 'T-Series',
        ),
        // 8. Unsuitable: Fight Scene
        const YouTubeVideo(
          id: 'clip_action_1',
          title: 'Vikram Climax Fight Scene | Kamal Haasan | Rolex Entry BGM Scene',
          channelTitle: 'Movie Scenes Hub',
          thumbnailUrl: 'https://img.youtube.com/vi/clip_action_1/hqdefault.jpg',
          duration: '8:45',
          viewCount: '900K views',
          rawTitle: 'Vikram Climax Fight Scene | Kamal Haasan | Rolex Entry BGM Scene',
          rawChannelTitle: 'Movie Scenes Hub',
        ),
        // 9. Valid English / Global Song
        const YouTubeVideo(
          id: 'song_english_1',
          title: 'The Weeknd - Blinding Lights (Official Audio)',
          channelTitle: 'The Weeknd',
          thumbnailUrl: 'https://img.youtube.com/vi/song_english_1/hqdefault.jpg',
          duration: '3:20',
          viewCount: '1.2B views',
          rawTitle: 'The Weeknd - Blinding Lights (Official Audio)',
          rawChannelTitle: 'The Weeknd',
        ),
        // 10. Unsuitable: Standup Comedy / Roasting
        const YouTubeVideo(
          id: 'clip_roast_1',
          title: 'Tamil Cinema Roasting Video 😂 | Troll and Fun review',
          channelTitle: 'Troll Tamizha',
          thumbnailUrl: 'https://img.youtube.com/vi/clip_roast_1/hqdefault.jpg',
          duration: '11:10',
          viewCount: '400K views',
          rawTitle: 'Tamil Cinema Roasting Video 😂 | Troll and Fun review',
          rawChannelTitle: 'Troll Tamizha',
        ),
        // 11. Valid Tamil Song 2
        const YouTubeVideo(
          id: 'song_tamil_2',
          title: 'Katchi Sera - Lyric Video | Sai Abhyankkar | Think Indie',
          channelTitle: 'Think Music India',
          thumbnailUrl: 'https://img.youtube.com/vi/song_tamil_2/hqdefault.jpg',
          duration: '3:12',
          viewCount: '120M views',
          rawTitle: 'Katchi Sera - Lyric Video | Sai Abhyankkar | Think Indie',
          rawChannelTitle: 'Think Music India',
        ),
        // 12. Valid Kannada Song
        const YouTubeVideo(
          id: 'song_kannada_1',
          title: 'Ra Ra Rakkamma - Lyrical Video | Vikrant Rona | Kichcha Sudeep | Sunidhi Chauhan',
          channelTitle: 'Lahari Music',
          thumbnailUrl: 'https://img.youtube.com/vi/song_kannada_1/hqdefault.jpg',
          duration: '3:45',
          viewCount: '70M views',
          rawTitle: 'Ra Ra Rakkamma - Lyrical Video | Vikrant Rona | Kichcha Sudeep | Sunidhi Chauhan',
          rawChannelTitle: 'Lahari Music',
        ),
        // 13. Valid Punjabi Song
        const YouTubeVideo(
          id: 'song_punjabi_1',
          title: 'Diljit Dosanjh - Lover (Official Music Video)',
          channelTitle: 'Diljit Dosanjh',
          thumbnailUrl: 'https://img.youtube.com/vi/song_punjabi_1/hqdefault.jpg',
          duration: '3:18',
          viewCount: '160M views',
          rawTitle: 'Diljit Dosanjh - Lover (Official Music Video)',
          rawChannelTitle: 'Diljit Dosanjh',
        ),
        // 14. Valid Tamil Song 3
        const YouTubeVideo(
          id: 'song_tamil_3',
          title: 'Hukum - Video Song | Jailer | Superstar Rajinikanth | Anirudh',
          channelTitle: 'Sun TV',
          thumbnailUrl: 'https://img.youtube.com/vi/song_tamil_3/hqdefault.jpg',
          duration: '3:27',
          viewCount: '180M views',
          rawTitle: 'Hukum - Lyric Video | Jailer | Superstar Rajinikanth | Sun Pictures | Anirudh',
          rawChannelTitle: 'Sun TV',
        ),
        // 15. Valid Telugu Song 2
        const YouTubeVideo(
          id: 'song_telugu_2',
          title: 'Butta Bomma - Full Video Song | Ala Vaikunthapurramuloo | Allu Arjun | Armaan Malik',
          channelTitle: 'Aditya Music',
          thumbnailUrl: 'https://img.youtube.com/vi/song_telugu_2/hqdefault.jpg',
          duration: '3:18',
          viewCount: '800M views',
          rawTitle: 'Butta Bomma - Full Video Song | Ala Vaikunthapurramuloo | Allu Arjun | Armaan Malik',
          rawChannelTitle: 'Aditya Music',
        ),
        // 16. Valid Hindi Song 2
        const YouTubeVideo(
          id: 'song_hindi_2',
          title: 'Kesariya - Brahmāstra | Ranbir Kapoor | Alia Bhatt | Pritam | Arijit Singh',
          channelTitle: 'Sony Music India',
          thumbnailUrl: 'https://img.youtube.com/vi/song_hindi_2/hqdefault.jpg',
          duration: '4:28',
          viewCount: '550M views',
          rawTitle: 'Kesariya - Brahmāstra | Ranbir Kapoor | Alia Bhatt | Pritam | Arijit Singh',
          rawChannelTitle: 'Sony Music India',
        ),
      ];

      // Filter the search results into the queue using isValidIndividualSong (like search_page.dart does)
      final queueVideos = mixedPool
          .where((v) => MusicResultClassifier.isValidIndividualSong(v))
          .toList();

      final queueManager = QueueManager();
      queueManager.setQueue(
        queueVideos.map((v) => v.toTrack()).toList(),
        startIndex: 0,
      );

      // Verify that every item entering the queue is a genuine song
      expect(queueVideos.length, equals(11));
      for (final v in queueVideos) {
        expect(MusicResultClassifier.isValidIndividualSong(v), isTrue);
      }

      // Simulate user pressing "Next" 10 times consecutively
      final playedTracks = <MusicItem>[];
      for (int i = 0; i < 10; i++) {
        MusicItem? nextTrack = queueManager.next();
        if (nextTrack != null) {
          final cand = YouTubeVideo(
            id: nextTrack.id.replaceFirst('youtube_', ''),
            title: nextTrack.title,
            channelTitle: nextTrack.artist,
            thumbnailUrl: nextTrack.imageUrl,
            duration: nextTrack.duration,
            viewCount: '',
            rawTitle: (nextTrack is Track) ? (nextTrack.rawTitle ?? nextTrack.title) : nextTrack.title,
            rawChannelTitle: (nextTrack is Track) ? (nextTrack.rawArtist ?? nextTrack.artist) : nextTrack.artist,
          );
          // Confirm candidate passes strict individual song validation
          expect(MusicResultClassifier.isValidIndividualSong(cand), isTrue);
          playedTracks.add(nextTrack);
        }
      }

      // Exact assertion: 10/10 selections were legitimate songs, 0 were comedy/scenes/compilations!
      expect(playedTracks.length, equals(10));
      for (final t in playedTracks) {
        expect(t.title.toLowerCase().contains('comedy'), isFalse);
        expect(t.title.toLowerCase().contains('scene'), isFalse);
        expect(t.title.toLowerCase().contains('roast'), isFalse);
        expect(t.title.toLowerCase().contains('interview'), isFalse);
        expect(t.title.toLowerCase().contains('jukebox'), isFalse);
      }
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 3: Zero Regional / Linguistic Bias
    // ─────────────────────────────────────────────────────────────────────────
    test('3. Regional film songs across Tamil, Telugu, Malayalam, Hindi, Kannada, Punjabi are accepted with high confidence', () {
      final regionalTracks = [
        const YouTubeVideo(
          id: 'reg_1',
          title: 'Hukum - Thalaivar Alappara | Jailer | Superstar Rajinikanth | Anirudh',
          channelTitle: 'Sun TV',
          thumbnailUrl: '',
          duration: '3:27',
          viewCount: '180M views',
          rawTitle: 'Hukum - Video Song | Jailer | Superstar Rajinikanth | Anirudh Ravichander',
          rawChannelTitle: 'Sun TV',
        ),
        const YouTubeVideo(
          id: 'reg_2',
          title: 'Kooch Poove - Video Song | Amaran | Sivakarthikeyan | Sai Pallavi | GV Prakash Kumar',
          channelTitle: 'Saregama Tamil',
          thumbnailUrl: '',
          duration: '4:15',
          viewCount: '50M views',
          rawTitle: 'Kooch Poove - Video Song | Amaran | Sivakarthikeyan | Sai Pallavi | GV Prakash Kumar',
          rawChannelTitle: 'Saregama Tamil',
        ),
        const YouTubeVideo(
          id: 'reg_3',
          title: 'Ramuloo Ramulaa - Full Video Song | Ala Vaikunthapurramuloo | Allu Arjun | Anurag Kulkarni',
          channelTitle: 'Aditya Music',
          thumbnailUrl: '',
          duration: '4:30',
          viewCount: '600M views',
          rawTitle: 'Ramuloo Ramulaa - Full Video Song | Ala Vaikunthapurramuloo | Allu Arjun | Anurag Kulkarni',
          rawChannelTitle: 'Aditya Music',
        ),
        const YouTubeVideo(
          id: 'reg_4',
          title: 'Kadharalz - Video Song | Manjummel Boys | Sushin Shyam | Chidambaram',
          channelTitle: 'Think Music India',
          thumbnailUrl: '',
          duration: '3:10',
          viewCount: '30M views',
          rawTitle: 'Kadharalz - Video Song | Manjummel Boys | Sushin Shyam | Chidambaram',
          rawChannelTitle: 'Think Music India',
        ),
      ];

      for (final song in regionalTracks) {
        final verdict = MusicResultClassifier.classify(song);
        expect(verdict.isMusic, isTrue, reason: 'Failed for ${song.title}');
        expect(
          verdict.confidence == MusicTrackConfidence.officialMusic ||
              verdict.confidence == MusicTrackConfidence.likelyMusic,
          isTrue,
          reason: 'Insufficient confidence for ${song.title}',
        );
        expect(MusicResultClassifier.isValidIndividualSong(song), isTrue);
      }
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 4: Preservation of Legitimate Long Classical & Live Music
    // ─────────────────────────────────────────────────────────────────────────
    test('4. Legitimate long Carnatic ragas and Western classical symphonies are preserved despite length', () {
      const carnaticRaga = YouTubeVideo(
        id: 'carnatic_1',
        title: 'Kalyani Raga Alapana & Kriti - Carnatic Classical Vocal Recital',
        channelTitle: 'Sangeeth Classical',
        thumbnailUrl: '',
        duration: '22:15',
        viewCount: '150K views',
        rawTitle: 'Kalyani Raga Alapana & Kriti - Carnatic Classical Vocal Recital',
        rawChannelTitle: 'Sangeeth Classical',
      );

      final ragaVerdict = MusicResultClassifier.classify(carnaticRaga);
      expect(ragaVerdict.isMusic, isTrue);
      expect(ragaVerdict.confidence != MusicTrackConfidence.rejected, isTrue);

      const symphony = YouTubeVideo(
        id: 'sym_1',
        title: 'Tchaikovsky: Symphony No. 6 "Pathétique" - London Philharmonic Orchestra',
        channelTitle: 'London Philharmonic',
        thumbnailUrl: '',
        duration: '46:30',
        viewCount: '2.1M views',
        rawTitle: 'Tchaikovsky: Symphony No. 6 "Pathétique" - London Philharmonic Orchestra',
        rawChannelTitle: 'London Philharmonic',
      );

      final symVerdict = MusicResultClassifier.classify(symphony);
      expect(symVerdict.isMusic, isTrue);
      expect(symVerdict.confidence != MusicTrackConfidence.rejected, isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 5: Rejection of Jukeboxes for Individual Song Playback
    // ─────────────────────────────────────────────────────────────────────────
    test('5. Multi-song jukebox is rejected for single-track playback but permitted if query asks for jukebox', () {
      const jukebox = YouTubeVideo(
        id: 'jb_1',
        title: 'Anirudh Hit Songs Audio Jukebox | Best of Anirudh Ravichander All Songs',
        channelTitle: 'Sony Music South',
        thumbnailUrl: '',
        duration: '52:10',
        viewCount: '10M views',
        rawTitle: 'Anirudh Hit Songs Audio Jukebox | Best of Anirudh Ravichander All Songs',
        rawChannelTitle: 'Sony Music South',
      );

      // Default / individual playback: must be rejected
      final individualVerdict = MusicResultClassifier.classify(
        jukebox,
        forIndividualPlayback: true,
      );
      expect(individualVerdict.isMusic, isFalse);
      expect(individualVerdict.confidence, equals(MusicTrackConfidence.rejected));
      expect(MusicResultClassifier.isValidIndividualSong(jukebox), isFalse);

      // Explicit search query asking for jukebox: permitted
      final requestedVerdict = MusicResultClassifier.classify(
        jukebox,
        query: 'Anirudh jukebox',
        forIndividualPlayback: false,
      );
      expect(requestedVerdict.isMusic, isTrue);
      expect(requestedVerdict.confidence != MusicTrackConfidence.rejected, isTrue);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 6: Search Deduplicator Non-Music Filtering
    // ─────────────────────────────────────────────────────────────────────────
    test('6. SearchDeduplicator categorizes comedy scene from vault channel as nonMusicEntertainment', () {
      const sceneVideo = YouTubeVideo(
        id: 'scene_test',
        title: 'Super Comedy Scene from Tamil Cinema Vault',
        channelTitle: 'Tamil Cinema Vault',
        thumbnailUrl: '',
        duration: '14:29',
        viewCount: '1M views',
        rawTitle: 'Super Comedy Scene from Tamil Cinema Vault',
        rawChannelTitle: 'Tamil Cinema Vault',
      );

      final editType = SearchDeduplicator.detectEditType(
        sceneVideo,
        const QueryIntent(normalizedQuery: 'arabic kuthu'),
      );
      expect(editType, equals(EditType.nonMusicEntertainment));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 7: Strict Rejection of Current Tamil Influencer Videos & Vlogs
    // ─────────────────────────────────────────────────────────────────────────
    test('7. Strictly rejects current Tamil influencer videos (Irfan, Madan Gowri, Parithabangal, TTF Vasan, Blue Sattai, Village Cooking)', () {
      final influencerVideos = [
        const YouTubeVideo(
          id: 'inf_1',
          title: 'Eating 100 Types of Biryani in Chennai! | Irfan\'s view',
          channelTitle: 'Irfan\'s view',
          thumbnailUrl: '',
          duration: '12:45',
          viewCount: '3.1M views',
          rawTitle: 'Eating 100 Types of Biryani in Chennai! | Irfan\'s view',
          rawChannelTitle: 'Irfan\'s view',
        ),
        const YouTubeVideo(
          id: 'inf_2',
          title: 'What Happened in Tirupati Laddu? | Madan Gowri | Tamil',
          channelTitle: 'Madan Gowri',
          thumbnailUrl: '',
          duration: '8:20',
          viewCount: '1.8M views',
          rawTitle: 'What Happened in Tirupati Laddu? | Madan Gowri | Tamil',
          rawChannelTitle: 'Madan Gowri',
        ),
        const YouTubeVideo(
          id: 'inf_3',
          title: 'Office Parithabangal | Gopi Sudhakar',
          channelTitle: 'Parithabangal',
          thumbnailUrl: '',
          duration: '6:15',
          viewCount: '4.5M views',
          rawTitle: 'Office Parithabangal | Gopi Sudhakar',
          rawChannelTitle: 'Parithabangal',
        ),
        const YouTubeVideo(
          id: 'inf_4',
          title: 'Ladakh Ride with Superbike | TTF Vasan',
          channelTitle: 'TTF Vasan',
          thumbnailUrl: '',
          duration: '15:10',
          viewCount: '900K views',
          rawTitle: 'Ladakh Ride with Superbike | TTF Vasan',
          rawChannelTitle: 'TTF Vasan',
        ),
        const YouTubeVideo(
          id: 'inf_5',
          title: 'Traditional Mutton Biryani Cooking in Village | Village Cooking Channel',
          channelTitle: 'Village Cooking Channel',
          thumbnailUrl: '',
          duration: '14:30',
          viewCount: '12M views',
          rawTitle: 'Traditional Mutton Biryani Cooking in Village | Village Cooking Channel',
          rawChannelTitle: 'Village Cooking Channel',
        ),
        const YouTubeVideo(
          id: 'inf_6',
          title: 'Amaran Movie Public Review | Blue Sattai Maran',
          channelTitle: 'Blue Sattai Maran',
          thumbnailUrl: '',
          duration: '5:40',
          viewCount: '650K views',
          rawTitle: 'Amaran Movie Public Review | Blue Sattai Maran',
          rawChannelTitle: 'Blue Sattai Maran',
        ),
        const YouTubeVideo(
          id: 'inf_7',
          title: 'Bigg Boss Season 8 Today Promo Review | Behindwoods',
          channelTitle: 'Behindwoods TV',
          thumbnailUrl: '',
          duration: '4:10',
          viewCount: '450K views',
          rawTitle: 'Bigg Boss Season 8 Today Promo Review | Behindwoods',
          rawChannelTitle: 'Behindwoods TV',
        ),
      ];

      for (final video in influencerVideos) {
        final verdict = MusicResultClassifier.classify(video);
        expect(verdict.isMusic, isFalse, reason: 'Failed to reject ${video.title}');
        expect(verdict.confidence, equals(MusicTrackConfidence.rejected));
        expect(MusicResultClassifier.isValidIndividualSong(video), isFalse);
      }
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 8: Pipe Separator Alone Does Not Qualify as Music
    // ─────────────────────────────────────────────────────────────────────────
    test('8. Titles with pipe separator but no music evidence are rejected as non-music', () {
      const nonMusicWithPipe = YouTubeVideo(
        id: 'pipe_vlog',
        title: 'Exploring Best Street Food in Madurai | Travel Diaries',
        channelTitle: 'Foodie Nomad',
        thumbnailUrl: '',
        duration: '4:20',
        viewCount: '200K views',
        rawTitle: 'Exploring Best Street Food in Madurai | Travel Diaries',
        rawChannelTitle: 'Foodie Nomad',
      );

      final verdict = MusicResultClassifier.classify(nonMusicWithPipe);
      expect(verdict.isMusic, isFalse);
      expect(verdict.confidence, equals(MusicTrackConfidence.rejected));
      expect(MusicResultClassifier.isValidIndividualSong(nonMusicWithPipe), isFalse);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 9: Universal Structural Rejection of New & Growing Influencers
    // (Zero reliance on hardcoded channel names; works for brand new creators)
    // ─────────────────────────────────────────────────────────────────────────
    test('9. Structural archetypes definitively reject new and growing influencers without hardcoded channel names', () {
      final newGrowingInfluencers = [
        // 1. New vlogger / bike delivery
        const YouTubeVideo(
          id: 'new_inf_1',
          title: 'My New Bike Delivery | Dream Superbike Buying Experience',
          channelTitle: 'Salem Pasanga',
          thumbnailUrl: '',
          duration: '3:45',
          viewCount: '25K views',
          rawTitle: 'My New Bike Delivery | Dream Superbike Buying Experience',
          rawChannelTitle: 'Salem Pasanga',
        ),
        // 2. New food hunter / night food tour
        const YouTubeVideo(
          id: 'new_inf_2',
          title: 'Night Food Hunt in Madurai | Best Kari Dosa Secret Spot',
          channelTitle: 'Madurai Food Hunter',
          thumbnailUrl: '',
          duration: '4:10',
          viewCount: '45K views',
          rawTitle: 'Night Food Hunt in Madurai | Best Kari Dosa Secret Spot',
          rawChannelTitle: 'Madurai Food Hunter',
        ),
        // 3. New lifestyle / home tour vlog
        const YouTubeVideo(
          id: 'new_inf_3',
          title: 'Enga Veedu House Tour! | Chennai Couple Vlogs',
          channelTitle: 'Chennai Couple',
          thumbnailUrl: '',
          duration: '5:20',
          viewCount: '15K views',
          rawTitle: 'Enga Veedu House Tour! | Chennai Couple Vlogs',
          rawChannelTitle: 'Chennai Couple',
        ),
        // 4. New tech reviewer / buying guide
        const YouTubeVideo(
          id: 'new_inf_4',
          title: "Don't Buy This Phone! Honest Review & Camera Test",
          channelTitle: 'Tech Tamizhan 2026',
          thumbnailUrl: '',
          duration: '4:50',
          viewCount: '30K views',
          rawTitle: "Don't Buy This Phone! Honest Review & Camera Test",
          rawChannelTitle: 'Tech Tamizhan 2026',
        ),
        // 5. New challenge / friend vlog
        const YouTubeVideo(
          id: 'new_inf_5',
          title: 'I Tried 24 Hours Challenge with My Friends',
          channelTitle: 'Trichy Nanban',
          thumbnailUrl: '',
          duration: '3:30',
          viewCount: '8K views',
          rawTitle: 'I Tried 24 Hours Challenge with My Friends',
          rawChannelTitle: 'Trichy Nanban',
        ),
        // 6. New routine / GRWM vlog
        const YouTubeVideo(
          id: 'new_inf_6',
          title: 'What I Eat in a Day | Morning Routine Vlog',
          channelTitle: 'Kovai Girl',
          thumbnailUrl: '',
          duration: '4:05',
          viewCount: '12K views',
          rawTitle: 'What I Eat in a Day | Morning Routine Vlog',
          rawChannelTitle: 'Kovai Girl',
        ),
        // 7. Movie gossip / scene breakdown piggybacking on a movie search
        const YouTubeVideo(
          id: 'new_inf_7',
          title: 'Amaran Climax Explained & Hidden Details | Cine Talks',
          channelTitle: 'Cinema Focus',
          thumbnailUrl: '',
          duration: '3:55',
          viewCount: '85K views',
          rawTitle: 'Amaran Climax Explained & Hidden Details | Cine Talks',
          rawChannelTitle: 'Cinema Focus',
        ),
        // 8. Public opinion / theatre reaction
        const YouTubeVideo(
          id: 'new_inf_8',
          title: 'Amaran Public Opinion & Theatre Response',
          channelTitle: 'Subash Talkies',
          thumbnailUrl: '',
          duration: '3:15',
          viewCount: '50K views',
          rawTitle: 'Amaran Public Opinion & Theatre Response',
          rawChannelTitle: 'Subash Talkies',
        ),
        // 9. Family function vlog
        const YouTubeVideo(
          id: 'new_inf_9',
          title: 'Valaikappu Function Highlights & Grand Celebration',
          channelTitle: 'Random Family Vlogs',
          thumbnailUrl: '',
          duration: '4:30',
          viewCount: '5K views',
          rawTitle: 'Valaikappu Function Highlights & Grand Celebration',
          rawChannelTitle: 'Random Family Vlogs',
        ),
        // 10. Trailing question mark clickbait
        const YouTubeVideo(
          id: 'new_inf_10',
          title: 'Buying Gold for Mom Surprise Gift ??! (Emotional Moment)',
          channelTitle: 'New YouTuber',
          thumbnailUrl: '',
          duration: '3:40',
          viewCount: '20K views',
          rawTitle: 'Buying Gold for Mom Surprise Gift ??! (Emotional Moment)',
          rawChannelTitle: 'New YouTuber',
        ),
      ];

      for (final video in newGrowingInfluencers) {
        final verdict = MusicResultClassifier.classify(video);
        expect(
          verdict.isMusic,
          isFalse,
          reason: 'Failed to reject new growing influencer "${video.title}" from "${video.channelTitle}"',
        );
        expect(
          verdict.confidence,
          equals(MusicTrackConfidence.rejected),
          reason: 'Confidence should be rejected for "${video.title}"',
        );
        expect(
          MusicResultClassifier.isValidIndividualSong(video),
          isFalse,
          reason: 'isValidIndividualSong should be false for "${video.title}"',
        );
        expect(
          MusicResultClassifier.isValidMusicTrack(video),
          isFalse,
          reason: 'isValidMusicTrack should be false for "${video.title}"',
        );
        expect(
          SearchDeduplicator.detectEditType(video, const QueryIntent(normalizedQuery: 'amaran')),
          equals(EditType.nonMusicEntertainment),
          reason: 'SearchDeduplicator should mark "${video.title}" as nonMusicEntertainment',
        );
      }
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Test 10: Strict Rejection of Instagram Meme Pages, Reels & Skits
    // (Kaathadi Club, GuySkills, MokkaPostu, Awesome Machi, Chennai Memes, etc.)
    // ─────────────────────────────────────────────────────────────────────────
    test('10. Strictly rejects Instagram meme, reel, skit, and comedy repost channels', () {
      final instaMemeChannels = [
        // 1. Kaathadi Club
        const YouTubeVideo(
          id: 'insta_1',
          title: 'Kaathadi Club Comedy Compilation 2026 | Non Stop Laughter',
          channelTitle: 'Kaathadi Club',
          thumbnailUrl: '',
          duration: '8:30',
          viewCount: '500K views',
          rawTitle: 'Kaathadi Club Comedy Compilation 2026 | Non Stop Laughter',
          rawChannelTitle: 'Kaathadi Club',
        ),
        // 2. GuySkills
        const YouTubeVideo(
          id: 'insta_2',
          title: 'Types of Boys in College Relationship Skit | Guyskills Reels',
          channelTitle: 'GuySkills',
          thumbnailUrl: '',
          duration: '3:10',
          viewCount: '1.2M views',
          rawTitle: 'Types of Boys in College Relationship Skit | Guyskills Reels',
          rawChannelTitle: 'GuySkills',
        ),
        // 3. MokkaPostu
        const YouTubeVideo(
          id: 'insta_3',
          title: 'Instagram Trending Reels Compilation | MokkaPostu Viral Video',
          channelTitle: 'MokkaPostu',
          thumbnailUrl: '',
          duration: '4:45',
          viewCount: '350K views',
          rawTitle: 'Instagram Trending Reels Compilation | MokkaPostu Viral Video',
          rawChannelTitle: 'MokkaPostu',
        ),
        // 4. Awesome Machi
        const YouTubeVideo(
          id: 'insta_4',
          title: 'When You Go to Cinema with Friends | Awesome Machi Comedy Skit',
          channelTitle: 'Awesome Machi',
          thumbnailUrl: '',
          duration: '3:30',
          viewCount: '400K views',
          rawTitle: 'When You Go to Cinema with Friends | Awesome Machi Comedy Skit',
          rawChannelTitle: 'Awesome Machi',
        ),
        // 5. Chennai Memes
        const YouTubeVideo(
          id: 'insta_5',
          title: 'Top 50 Viral Memes of the Month | Chennai Memes',
          channelTitle: 'Chennai Memes',
          thumbnailUrl: '',
          duration: '5:15',
          viewCount: '250K views',
          rawTitle: 'Top 50 Viral Memes of the Month | Chennai Memes',
          rawChannelTitle: 'Chennai Memes',
        ),
        // 6. Karikku
        const YouTubeVideo(
          id: 'insta_6',
          title: 'DoCoMo - Comedy Web Skit | Karikku Official',
          channelTitle: 'Karikku',
          thumbnailUrl: '',
          duration: '12:20',
          viewCount: '5M views',
          rawTitle: 'DoCoMo - Comedy Web Skit | Karikku Official',
          rawChannelTitle: 'Karikku',
        ),
        // 7. Nakkalites
        const YouTubeVideo(
          id: 'insta_7',
          title: 'Alapparais - Middle Class Wedding Skit | Nakkalites',
          channelTitle: 'Nakkalites',
          thumbnailUrl: '',
          duration: '9:40',
          viewCount: '2.5M views',
          rawTitle: 'Alapparais - Middle Class Wedding Skit | Nakkalites',
          rawChannelTitle: 'Nakkalites',
        ),
        // 8. Temple Monkeys
        const YouTubeVideo(
          id: 'insta_8',
          title: 'Kuruvi Talkies - Parody Skit | Temple Monkeys',
          channelTitle: 'Temple Monkeys',
          thumbnailUrl: '',
          duration: '6:10',
          viewCount: '800K views',
          rawTitle: 'Kuruvi Talkies - Parody Skit | Temple Monkeys',
          rawChannelTitle: 'Temple Monkeys',
        ),
        // 9. Generic Instagram Reel Hub
        const YouTubeVideo(
          id: 'insta_9',
          title: 'Tamil Trending Reels Compilation 2026',
          channelTitle: 'Tamil Reels Hub',
          thumbnailUrl: '',
          duration: '3:20',
          viewCount: '150K views',
          rawTitle: 'Tamil Trending Reels Compilation 2026',
          rawChannelTitle: 'Tamil Reels Hub',
        ),
        // 10. Insta Vibes Meme Page
        const YouTubeVideo(
          id: 'insta_10',
          title: 'Instagram Viral Relatable Meme Video | Insta Vibes',
          channelTitle: 'Insta Vibes Official',
          thumbnailUrl: '',
          duration: '2:50',
          viewCount: '90K views',
          rawTitle: 'Instagram Viral Relatable Meme Video | Insta Vibes',
          rawChannelTitle: 'Insta Vibes Official',
        ),
      ];

      for (final video in instaMemeChannels) {
        final verdict = MusicResultClassifier.classify(video);
        expect(
          verdict.isMusic,
          isFalse,
          reason: 'Failed to reject Insta/meme channel "${video.title}" from "${video.channelTitle}"',
        );
        expect(
          verdict.confidence,
          equals(MusicTrackConfidence.rejected),
          reason: 'Confidence should be rejected for "${video.title}"',
        );
        expect(
          MusicResultClassifier.isValidIndividualSong(video),
          isFalse,
          reason: 'isValidIndividualSong should be false for "${video.title}"',
        );
        expect(
          MusicResultClassifier.isValidMusicTrack(video),
          isFalse,
          reason: 'isValidMusicTrack should be false for "${video.title}"',
        );
        expect(
          SearchDeduplicator.detectEditType(video, const QueryIntent(normalizedQuery: 'comedy')),
          equals(EditType.nonMusicEntertainment),
          reason: 'SearchDeduplicator should mark "${video.title}" as nonMusicEntertainment',
        );
      }
    });
  });
}
