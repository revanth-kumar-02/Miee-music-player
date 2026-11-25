import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/preloading/next_track_preloader.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/youtube_audio_service.dart';
import 'package:Miee/core/storage/adapters/queue_snapshot.dart';
import 'package:Miee/features/artwork/data/artwork_resolver_impl.dart';
import 'package:Miee/features/artwork/domain/artwork_query.dart';
import 'package:Miee/features/artwork/domain/resolved_artwork.dart';
import 'package:Miee/features/artwork/presentation/artwork_providers.dart';
import 'package:Miee/features/history/domain/listening_event.dart';
import 'package:Miee/features/history/domain/listening_history_repository.dart';
import 'package:Miee/features/history/providers/history_providers.dart';
import 'package:Miee/features/library/data/queue_state_repository.dart';
import 'package:Miee/features/library/data/recently_played_repository.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/media/providers/media_providers.dart';
import 'package:Miee/features/search/data/playback_source_resolver.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Deterministic Test Fakes
// ─────────────────────────────────────────────────────────────────────────────

class _DeterministicYouTubeRepository extends YouTubeRepository {
  final Map<String, List<YouTubeVideo>> queryResponses;
  final List<String> executedQueries = [];
  final Map<String, Completer<void>> queryGates;

  _DeterministicYouTubeRepository({
    this.queryResponses = const {},
    this.queryGates = const {},
  });

  @override
  Future<List<YouTubeVideo>> search(
    String query, {
    int page = 1,
    bool forceFresh = false,
  }) async {
    executedQueries.add(query);
    if (queryGates.containsKey(query)) {
      await queryGates[query]!.future;
    }

    if (queryResponses.containsKey(query)) {
      return queryResponses[query]!;
    }
    final qLower = query.toLowerCase();
    for (final entry in queryResponses.entries) {
      if (qLower == entry.key.toLowerCase()) {
        return entry.value;
      }
    }
    for (final entry in queryResponses.entries) {
      if (qLower.contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return const [];
  }
}

class _DeterministicAudioPlayer extends AudioPlayer {
  bool _isPlaying = false;
  ProcessingState _procState = ProcessingState.idle;
  Duration _pos = Duration.zero;
  Duration? _dur;
  double _volume = 1.0;

  Duration nextSetSourceDuration = const Duration(seconds: 43);
  final List<AudioSource> loadedSources = [];
  Completer<void>? setSourceGate;

  final StreamController<PlayerState> _stateCtrl =
      StreamController<PlayerState>.broadcast();
  final StreamController<Duration> _posCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durCtrl =
      StreamController<Duration?>.broadcast();
  final StreamController<PlaybackEvent> _eventCtrl =
      StreamController<PlaybackEvent>.broadcast();
  final StreamController<PlayerException> _errCtrl =
      StreamController<PlayerException>.broadcast();

  _DeterministicAudioPlayer() : super(handleInterruptions: false);

  @override
  bool get playing => _isPlaying;
  @override
  ProcessingState get processingState => _procState;
  @override
  Duration get position => _pos;
  @override
  Duration get bufferedPosition => _pos;
  @override
  Duration? get duration => _dur;
  @override
  double get volume => _volume;

  @override
  Stream<PlayerState> get playerStateStream => _stateCtrl.stream;
  @override
  Stream<Duration> get positionStream => _posCtrl.stream;
  @override
  Stream<Duration?> get durationStream => _durCtrl.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => _eventCtrl.stream;
  @override
  Stream<PlayerException> get errorStream => _errCtrl.stream;
  @override
  Stream<Duration> get bufferedPositionStream => _posCtrl.stream;

  void emitDuration(Duration dur) {
    _dur = dur;
    _durCtrl.add(dur);
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    loadedSources.add(source);
    if (setSourceGate != null) {
      await setSourceGate!.future;
      setSourceGate = null;
    }
    _dur = nextSetSourceDuration;
    _procState = ProcessingState.ready;
    _stateCtrl.add(PlayerState(_isPlaying, _procState));
    _durCtrl.add(_dur);
    return _dur;
  }

  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    return setAudioSource(
      AudioSource.uri(Uri.parse(url), headers: headers, tag: tag),
      initialPosition: initialPosition,
      preload: preload,
    );
  }

  @override
  Future<void> play() async {
    _isPlaying = true;
    _procState = ProcessingState.ready;
    _stateCtrl.add(PlayerState(_isPlaying, _procState));
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    _stateCtrl.add(PlayerState(_isPlaying, _procState));
  }

  @override
  Future<void> stop() async {
    _isPlaying = false;
    _procState = ProcessingState.idle;
    _stateCtrl.add(PlayerState(_isPlaying, _procState));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    final pos = position ?? Duration.zero;
    _pos = pos;
    _posCtrl.add(pos);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {}

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {}

  @override
  Future<void> dispose() async {
    await _stateCtrl.close();
    await _posCtrl.close();
    await _durCtrl.close();
    await _eventCtrl.close();
    await _errCtrl.close();
  }
}

class _FakeQueueStateRepository implements QueueStateRepository {
  @override
  Future<void> clear() async {}

  @override
  List<MusicItem>? loadQueueTracks() => null;

  @override
  QueueSnapshot? loadSnapshot() => null;

  @override
  Future<void> saveSnapshot({
    required List<MusicItem> queue,
    required int currentIndex,
    required int positionMs,
    required bool isShuffleEnabled,
    required String repeatMode,
  }) async {}
}

class _FakeListeningHistoryRepository implements ListeningHistoryRepository {
  @override
  Future<void> clearHistory(String? uid) async {}

  @override
  Future<List<ListeningEvent>> getRecentHistory(
          {required String? uid, int limit = 30}) async =>
      const [];

  @override
  Future<void> recordListeningEvent({
    required String? uid,
    required MusicItem track,
    required int listenedSec,
    required int durationSec,
  }) async {}
}

class _FakeRecentlyPlayedRepository implements RecentlyPlayedRepository {
  final List<Track> recorded = [];

  @override
  Future<void> recordPlay(Track track) async {
    recorded.add(track);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeArtworkResolver extends ArtworkResolver {
  @override
  Future<ResolvedArtwork> resolve(
    ArtworkQuery query, {
    bool forceRefresh = false,
  }) async =>
      ResolvedArtwork.neutralFallback();
}

// ─────────────────────────────────────────────────────────────────────────────
// Fixtures matching the real Dude album scenario
// ─────────────────────────────────────────────────────────────────────────────

const _authenticWhoIsThisDude = YouTubeVideo(
  id: 'JGebNY0X5EY',
  title: 'Who is this Dude?',
  channelTitle: 'Sai Abhyankkar',
  thumbnailUrl: 'https://i.ytimg.com/vi/JGebNY0X5EY/hqdefault.jpg',
  duration: '0:43',
  viewCount: '200K views',
  rawTitle: 'Who is this Dude?',
  rawChannelTitle: 'Sai Abhyankkar',
);

const _oorumBloodUnplugged = YouTubeVideo(
  id: 'AnstAd2bUh8',
  title:
      'Oorum Blood Unplugged | Dude | Pradeep Ranganathan, Mamitha Baiju | Sai Abhyankkar | Keerthiswaran',
  channelTitle: 'Think Music India',
  thumbnailUrl: 'https://i.ytimg.com/vi/AnstAd2bUh8/hqdefault.jpg',
  duration: '1:18',
  viewCount: '3M views',
  rawTitle:
      'Oorum Blood Unplugged | Dude | Pradeep Ranganathan, Mamitha Baiju | Sai Abhyankkar | Keerthiswaran',
  rawChannelTitle: 'Think Music India',
);

const _moochavaPeechava = YouTubeVideo(
  id: 'moochPeech9',
  title: 'Moochava Peechava | Dude | Pradeep Ranganathan | Sai Abhyankkar | Keerthiswaran',
  channelTitle: 'Think Music India',
  thumbnailUrl: 'https://i.ytimg.com/vi/moochPeech9/hqdefault.jpg',
  duration: '1:18',
  viewCount: '2M views',
  rawTitle:
      'Moochava Peechava | Dude | Pradeep Ranganathan | Sai Abhyankkar | Keerthiswaran',
  rawChannelTitle: 'Think Music India',
);

const _kannukullaReprise = YouTubeVideo(
  id: 'eklzrRNfYGk',
  title:
      'Kannukulla (Reprise) - Video Song | Dude | Pradeep, Mamitha Baiju | @SaiAbhyankkar | Keerthiswaran',
  channelTitle: 'Think Music India',
  thumbnailUrl: 'https://i.ytimg.com/vi/eklzrRNfYGk/hqdefault.jpg',
  duration: '4:43',
  viewCount: '5M views',
  rawTitle:
      'Kannukulla (Reprise) - Video Song | Dude | Pradeep, Mamitha Baiju | @SaiAbhyankkar | Keerthiswaran',
  rawChannelTitle: 'Think Music India',
);

const _dudeFullSideA = YouTubeVideo(
  id: '3tf5NSesHsE',
  title:
      'Dude Original Score - Side A | Pradeep Ranganathan, Mamitha Baiju | @SaiAbhyankkar | Keerthiswaran',
  channelTitle: 'Think Music India',
  thumbnailUrl: 'https://i.ytimg.com/vi/3tf5NSesHsE/hqdefault.jpg',
  duration: '41:49',
  viewCount: '1M views',
  rawTitle:
      'Dude Original Score - Side A | Pradeep Ranganathan, Mamitha Baiju | @SaiAbhyankkar | Keerthiswaran',
  rawChannelTitle: 'Think Music India',
);

const _dudeOrchestralSuite = YouTubeVideo(
  id: 'CdwNrYUVs9Q',
  title: 'Dude – Orchestral Suite',
  channelTitle: 'Sai Abhyankkar',
  thumbnailUrl: 'https://i.ytimg.com/vi/CdwNrYUVs9Q/hqdefault.jpg',
  duration: '2:06',
  viewCount: '150K views',
  rawTitle: 'Dude – Orchestral Suite',
  rawChannelTitle: 'Sai Abhyankkar',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Track Identity Resolution & Playback Correctness', () {
    late YouTubeAudioService ytAudioService;

    setUp(() {
      ytAudioService = YouTubeAudioService();
      ytAudioService.clearCache();
      ytAudioService.resetTestingHooks();
    });

    tearDown(() {
      ytAudioService.resetTestingHooks();
      ytAudioService.clearCache();
    });

    test(
        '1. "Who Is This Dude?" — Sai Abhyankkar — 0:43 resolves to JGebNY0X5EY over poor primary results via clean fallback query',
        () async {
      // Simulate real-world behavior where "(Official Audio)" returns only OST siblings/mixes,
      // while the clean query "Sai Abhyankkar Who Is This Dude?" returns the authentic 0:43 track.
      final repo = _DeterministicYouTubeRepository(
        queryResponses: {
          'Sai Abhyankkar - Who Is This Dude? (Official Audio)': [
            _kannukullaReprise,
            _dudeFullSideA,
            _oorumBloodUnplugged,
            _moochavaPeechava,
          ],
          'Sai Abhyankkar Who Is This Dude?': [
            _authenticWhoIsThisDude,
            _oorumBloodUnplugged,
            _moochavaPeechava,
          ],
        },
      );

      final resolver = PlaybackSourceResolver.withRepository(repo);
      final resolvedId = await resolver.resolveVideoId(
        title: 'Who Is This Dude?',
        artist: 'Sai Abhyankkar',
        durationStr: '0:43',
        album: 'Dude',
      );

      expect(resolvedId, equals('JGebNY0X5EY'));
      expect(repo.executedQueries, hasLength(greaterThanOrEqualTo(2)));
      expect(
        repo.executedQueries.first,
        equals('Sai Abhyankkar - Who Is This Dude? (Official Audio)'),
      );
      expect(
        repo.executedQueries[1],
        equals('Sai Abhyankkar Who Is This Dude?'),
      );
    });

    test(
        '2. JGebNY0X5EY is accepted when present alongside unrelated Dude album tracks',
        () async {
      final repo = _DeterministicYouTubeRepository(
        queryResponses: {
          'Who Is This Dude?': [
            _oorumBloodUnplugged,
            _moochavaPeechava,
            _kannukullaReprise,
            _dudeOrchestralSuite,
            _authenticWhoIsThisDude,
          ],
        },
      );

      final resolver = PlaybackSourceResolver.withRepository(repo);
      final resolvedId = await resolver.resolveVideoId(
        title: 'Who Is This Dude?',
        artist: 'Sai Abhyankkar',
        durationStr: '0:43',
        album: 'Dude',
      );

      expect(resolvedId, equals('JGebNY0X5EY'));
    });

    test(
        '3. Unrelated sibling tracks ("Oorum Blood Unplugged", "Moochava Peechava", "Kannukulla (Reprise)", "Dude – Orchestral Suite") are strictly rejected',
        () async {
      final repo = _DeterministicYouTubeRepository(
        queryResponses: {
          'Who Is This Dude?': [
            _oorumBloodUnplugged,
            _moochavaPeechava,
            _kannukullaReprise,
            _dudeOrchestralSuite,
          ],
        },
      );

      final resolver = PlaybackSourceResolver.withRepository(repo);
      final resolvedId = await resolver.resolveVideoId(
        title: 'Who Is This Dude?',
        artist: 'Sai Abhyankkar',
        durationStr: '0:43',
        album: 'Dude',
      );

      expect(resolvedId, isNull);

      // Verify word-boundary matching never falsely matches "this" inside "Keerthiswaran"
      final evalKannukulla = resolver.evaluateCandidateInternal(
        candidate: _kannukullaReprise,
        cleanTitle: 'Who Is This Dude?',
        cleanArtist: 'Sai Abhyankkar',
        targetDurationSec: 43,
        album: 'Dude',
      );
      expect(evalKannukulla.titleScore, lessThan(0));

      final evalOorum = resolver.evaluateCandidateInternal(
        candidate: _oorumBloodUnplugged,
        cleanTitle: 'Who Is This Dude?',
        cleanArtist: 'Sai Abhyankkar',
        targetDurationSec: 43,
        album: 'Dude',
      );
      expect(evalOorum.titleScore, lessThan(0));

      final evalMoochava = resolver.evaluateCandidateInternal(
        candidate: _moochavaPeechava,
        cleanTitle: 'Who Is This Dude?',
        cleanArtist: 'Sai Abhyankkar',
        targetDurationSec: 43,
        album: 'Dude',
      );
      expect(evalMoochava.titleScore, lessThan(0));

      // Verify sharing album keyword "Dude" cannot compensate for missing title words
      final evalSuite = resolver.evaluateCandidateInternal(
        candidate: _dudeOrchestralSuite,
        cleanTitle: 'Who Is This Dude?',
        cleanArtist: 'Sai Abhyankkar',
        targetDurationSec: 43,
        album: 'Dude',
      );
      expect(evalSuite.titleScore, lessThan(0));
    });

    test(
        '4. 78-second candidate is rejected for 43-second target when duration or identity validation fails',
        () async {
      // Case A: 78s unrelated track from same album/artist -> rejected by both title and duration
      final resolver = PlaybackSourceResolver();
      final oorumScore = resolver.evaluateCandidateInternal(
        candidate: _oorumBloodUnplugged,
        cleanTitle: 'Who Is This Dude?',
        cleanArtist: 'Sai Abhyankkar',
        targetDurationSec: 43,
        album: 'Dude',
      );
      expect(oorumScore.titleScore, lessThan(0));

      // Case B: Even an extended 78s clip for a 43s short track fails duration compatibility (>20s diff on <90s track)
      const extendedClip78s = YouTubeVideo(
        id: 'extClip7801',
        title: 'Who Is This Dude? (Extended Scene)',
        channelTitle: 'Sai Abhyankkar',
        thumbnailUrl: '',
        duration: '1:18', // 78 seconds (35s diff vs 43s)
        viewCount: '10K',
      );

      expect(
        PlaybackSourceResolver.isDurationCompatible(
          targetDurationStr: '0:43',
          candidateDurationStr: '1:18',
        ),
        isFalse,
      );

      final repo = _DeterministicYouTubeRepository(
        queryResponses: {
          'Who Is This Dude?': [extendedClip78s],
        },
      );
      final strictResolver = PlaybackSourceResolver.withRepository(repo);
      final resolved = await strictResolver.resolveVideoId(
        title: 'Who Is This Dude?',
        artist: 'Sai Abhyankkar',
        durationStr: '0:43',
      );
      expect(resolved, isNull);

      // Verify short-track scoring gives heavy penalty for >15s deviation vs clean 43s match
      final score78s = strictResolver.evaluateCandidateInternal(
        candidate: extendedClip78s.copyWith(title: 'Who Is This Dude?'),
        cleanTitle: 'Who Is This Dude?',
        cleanArtist: 'Sai Abhyankkar',
        targetDurationSec: 43,
      );
      final score43s = strictResolver.evaluateCandidateInternal(
        candidate: _authenticWhoIsThisDude,
        cleanTitle: 'Who Is This Dude?',
        cleanArtist: 'Sai Abhyankkar',
        targetDurationSec: 43,
      );
      expect(score43s.score - score78s.score, greaterThanOrEqualTo(150));
    });

    test(
        '5. Duration scoring branch ordering handles >120s deviations without unreachable code',
        () {
      final resolver = PlaybackSourceResolver();
      const compilationVideo = YouTubeVideo(
        id: 'comp1234567',
        title: 'All The Stars',
        channelTitle: 'Random',
        thumbnailUrl: '',
        duration: '10:00', // 600s vs 232s -> diff = 368s > 120s
        viewCount: '1K',
      );
      const midDeviatedVideo = YouTubeVideo(
        id: 'mid12345678',
        title: 'All The Stars',
        channelTitle: 'Random',
        thumbnailUrl: '',
        duration: '5:20', // 320s vs 232s -> diff = 88s (60 < diff <= 120)
        viewCount: '1K',
      );

      final scoreOver120 = resolver.evaluateCandidateInternal(
        candidate: compilationVideo,
        cleanTitle: 'All The Stars',
        cleanArtist: 'Kendrick Lamar',
        targetDurationSec: 232,
      );
      final score60To120 = resolver.evaluateCandidateInternal(
        candidate: midDeviatedVideo,
        cleanTitle: 'All The Stars',
        cleanArtist: 'Kendrick Lamar',
        targetDurationSec: 232,
      );

      // Previously `else if (diff > 120)` came after `else if (diff > 60)` and was dead code!
      // Now >120s receives -100 while 60..120s receives -60, resulting in strictly 40 fewer points.
      expect(scoreOver120.score, equals(score60To120.score - 40));
    });

    test(
        '6. YouTubeAudioService.resolveCandidateForQuery rejects generally valid but unrelated music videos and validates identity',
        () async {
      // Previously resolveCandidateForQuery returned the VERY FIRST candidate where isValidIndividualSong was true!
      ytAudioService.searchFetcherForTesting = (query) async {
        return [
          _oorumBloodUnplugged,
          _moochavaPeechava,
          _kannukullaReprise,
        ];
      };

      final rejected = await ytAudioService.resolveCandidateForQuery(
        'Who Is This Dude? Sai Abhyankkar',
        expectedTitle: 'Who Is This Dude?',
        expectedArtist: 'Sai Abhyankkar',
        expectedDuration: '0:43',
        expectedAlbum: 'Dude',
      );
      expect(rejected, isNull);

      // Also test raw-query mode (without explicit named parameters)
      ytAudioService.clearCache();
      final rejectedRaw = await ytAudioService.resolveCandidateForQuery(
        'Who Is This Dude? Sai Abhyankkar',
      );
      expect(rejectedRaw, isNull);

      // When authentic recording appears later in the list, it selects JGebNY0X5EY cleanly
      ytAudioService.clearCache();
      ytAudioService.searchFetcherForTesting = (query) async {
        return [
          _oorumBloodUnplugged,
          _moochavaPeechava,
          _authenticWhoIsThisDude,
        ];
      };

      final accepted = await ytAudioService.resolveCandidateForQuery(
        'Who Is This Dude? Sai Abhyankkar',
        expectedTitle: 'Who Is This Dude?',
        expectedArtist: 'Sai Abhyankkar',
        expectedDuration: '0:43',
        expectedAlbum: 'Dude',
      );
      expect(accepted, isNotNull);
      expect(accepted!.id, equals('JGebNY0X5EY'));
    });

    test(
        '7. Verified selected video ID remains unchanged through AudioHandler and PlayerController playback loading',
        () async {
      final fakePlayer = _DeterministicAudioPlayer()
        ..nextSetSourceDuration = const Duration(seconds: 43);
      final emptyRepo = _DeterministicYouTubeRepository();
      final mockResolver = PlaybackSourceResolver.withRepository(emptyRepo);
      final handler = MieeAudioHandler(
        player: fakePlayer,
        sourceResolver: mockResolver,
      );

      const expectedStreamUrl =
          'https://rr1---sn-test.googlevideo.com/videoplayback?id=JGebNY0X5EY&expire=2524608000';
      ytAudioService.cacheUrlForTesting('JGebNY0X5EY', expectedStreamUrl);

      final recentRepo = _FakeRecentlyPlayedRepository();
      final container = ProviderContainer(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          queueStateRepositoryProvider.overrideWithValue(_FakeQueueStateRepository()),
          listeningHistoryRepositoryProvider
              .overrideWithValue(_FakeListeningHistoryRepository()),
          recentlyPlayedRepositoryProvider.overrideWithValue(recentRepo),
          artworkResolverProvider.overrideWithValue(_FakeArtworkResolver()),
          songsProvider.overrideWithValue(const []),
          sourceSelectionProvider.overrideWithValue('preferYouTube'),
          playerControllerProvider.overrideWith((ref) {
            return PlayerController(
              handler,
              ref.watch(queueManagerProvider),
              ref,
              sourceResolver: mockResolver,
            );
          }),
        ],
      );

      const whoIsThisDudeTrack = Track(
        id: 'youtube_JGebNY0X5EY',
        title: 'Who Is This Dude?',
        artist: 'Sai Abhyankkar',
        albumName: 'Dude',
        imageUrl: 'https://example.com/dude-art.jpg',
        duration: '0:43',
        filePath: 'https://www.youtube.com/watch?v=JGebNY0X5EY',
        sourceId: 'JGebNY0X5EY',
      );
      const oorumTrack = Track(
        id: 'youtube_AnstAd2bUh8',
        title: 'Oorum Blood Unplugged',
        artist: 'Sai Abhyankkar',
        albumName: 'Dude',
        imageUrl: 'https://example.com/dude-art.jpg',
        duration: '1:18',
        filePath: 'https://www.youtube.com/watch?v=AnstAd2bUh8',
        sourceId: 'AnstAd2bUh8',
      );

      final controller = container.read(playerControllerProvider.notifier);
      controller.setQueue([whoIsThisDudeTrack, oorumTrack], startIndex: 0);

      await pumpEventQueue(times: 30);

      final state = container.read(playerControllerProvider);
      expect(state.currentTrack?.id, equals('youtube_JGebNY0X5EY'));
      expect(state.currentTrack?.title, equals('Who Is This Dude?'));
      expect(state.duration, equals(const Duration(seconds: 43)));
      expect(handler.loadedAudioTrackId, equals('youtube_JGebNY0X5EY'));
      expect(handler.mediaItem.value?.id, equals('youtube_JGebNY0X5EY'));
      expect(handler.mediaItem.value?.duration, equals(const Duration(seconds: 43)));
      expect(
        (fakePlayer.loadedSources.last as UriAudioSource).uri.toString(),
        equals(expectedStreamUrl),
      );
      // No search queries were executed because verified 11-char ID JGebNY0X5EY was preserved!
      expect(emptyRepo.executedQueries, isEmpty);

      await handler.disposeHandler();
      container.dispose();
    });

    test(
        '8. Stale asynchronous resolution cannot replace a newer track selection',
        () async {
      final slowTrackAGate = Completer<void>();
      final repo = _DeterministicYouTubeRepository(
        queryGates: {
          'Sai Abhyankkar - Slow Track A (Official Audio)': slowTrackAGate,
        },
        queryResponses: {
          'Sai Abhyankkar - Slow Track A (Official Audio)': [
            const YouTubeVideo(
              id: 'slowVidA111',
              title: 'Slow Track A',
              channelTitle: 'Sai Abhyankkar',
              thumbnailUrl: '',
              duration: '3:00',
              viewCount: '100K',
            ),
          ],
          'Sai Abhyankkar - Fast Track B (Official Audio)': [
            const YouTubeVideo(
              id: 'JGebNY0X5EY',
              title: 'Fast Track B',
              channelTitle: 'Sai Abhyankkar',
              thumbnailUrl: '',
              duration: '0:43',
              viewCount: '200K',
            ),
          ],
        },
      );

      final resolver = PlaybackSourceResolver.withRepository(repo);
      final fakePlayer = _DeterministicAudioPlayer()
        ..nextSetSourceDuration = const Duration(seconds: 43);
      final handler = MieeAudioHandler(
        player: fakePlayer,
        sourceResolver: resolver,
      );

      ytAudioService.cacheUrlForTesting(
        'slowVidA111',
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=slowVidA111&expire=2524608000',
      );
      ytAudioService.cacheUrlForTesting(
        'JGebNY0X5EY',
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=JGebNY0X5EY&expire=2524608000',
      );

      final container = ProviderContainer(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          queueStateRepositoryProvider.overrideWithValue(_FakeQueueStateRepository()),
          listeningHistoryRepositoryProvider
              .overrideWithValue(_FakeListeningHistoryRepository()),
          recentlyPlayedRepositoryProvider
              .overrideWithValue(_FakeRecentlyPlayedRepository()),
          artworkResolverProvider.overrideWithValue(_FakeArtworkResolver()),
          songsProvider.overrideWithValue(const []),
          sourceSelectionProvider.overrideWithValue('preferYouTube'),
          playerControllerProvider.overrideWith((ref) {
            return PlayerController(
              handler,
              ref.watch(queueManagerProvider),
              ref,
              sourceResolver: resolver,
            );
          }),
        ],
      );

      const trackA = Track(
        id: 'youtube_itunes_1111111111',
        title: 'Slow Track A',
        artist: 'Sai Abhyankkar',
        imageUrl: '',
        duration: '3:00',
        metadataProvider: 'itunes',
      );
      const trackB = Track(
        id: 'youtube_itunes_2222222222',
        title: 'Fast Track B',
        artist: 'Sai Abhyankkar',
        imageUrl: '',
        duration: '0:43',
        metadataProvider: 'itunes',
      );

      final controller = container.read(playerControllerProvider.notifier);

      // 1. User taps Slow Track A (stalls inside PlaybackSourceResolver)
      final playAFut = controller.playTrack(trackA);
      await pumpEventQueue(times: 5);

      // 2. Immediately selects Fast Track B while Track A is still resolving
      final playBFut = controller.playTrack(trackB);
      await playBFut;
      await pumpEventQueue(times: 10);

      expect(container.read(playerControllerProvider).currentTrack?.id,
          equals('youtube_JGebNY0X5EY'));
      expect(handler.loadedAudioTrackId, equals('youtube_JGebNY0X5EY'));

      // 3. Now delayed response for Slow Track A arrives! It MUST be discarded.
      slowTrackAGate.complete();
      await playAFut;
      await pumpEventQueue(times: 20);

      final finalState = container.read(playerControllerProvider);
      expect(finalState.currentTrack?.id, equals('youtube_JGebNY0X5EY'));
      expect(finalState.currentTrack?.title, equals('Fast Track B'));
      expect(handler.loadedAudioTrackId, equals('youtube_JGebNY0X5EY'));
      expect(
        (fakePlayer.loadedSources.last as UriAudioSource).uri.toString(),
        contains('id=JGebNY0X5EY'),
      );

      await handler.disposeHandler();
      container.dispose();
    });

    test(
        '9. AudioHandler resolves external catalog ID via PlaybackSourceResolver and updates metadata without leaking lingering duration',
        () async {
      final repo = _DeterministicYouTubeRepository(
        queryResponses: {
          'Sai Abhyankkar - Who Is This Dude? (Official Audio)': [
            _kannukullaReprise,
            _oorumBloodUnplugged,
          ],
          'Sai Abhyankkar Who Is This Dude?': [
            _authenticWhoIsThisDude,
          ],
        },
      );
      final resolver = PlaybackSourceResolver.withRepository(repo);
      final fakePlayer = _DeterministicAudioPlayer()
        ..nextSetSourceDuration = const Duration(minutes: 4, seconds: 29);
      final handler = MieeAudioHandler(
        player: fakePlayer,
        sourceResolver: resolver,
      );

      ytAudioService.cacheUrlForTesting(
        '4Bsc2uI_LsM',
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=4Bsc2uI_LsM&expire=2524608000',
      );
      ytAudioService.cacheUrlForTesting(
        'JGebNY0X5EY',
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=JGebNY0X5EY&expire=2524608000',
      );

      const previousSong = Track(
        id: 'youtube_4Bsc2uI_LsM',
        title: 'Oorum Blood',
        artist: 'Sai Abhyankkar',
        albumName: 'Dude',
        imageUrl: '',
        duration: '4:29',
      );
      const nextUnresolvedTrack = Track(
        id: 'youtube_itunes_987654321',
        title: 'Who Is This Dude?',
        artist: 'Sai Abhyankkar',
        albumName: 'Dude',
        imageUrl: '',
        duration: '0:43',
        metadataProvider: 'itunes',
      );

      // Load previous song (duration 4:29)
      await handler.loadQueue([previousSong, nextUnresolvedTrack], startIndex: 0);
      await handler.play();
      expect(handler.mediaItem.value?.duration, equals(const Duration(minutes: 4, seconds: 29)));

      // Prepare gate so we inspect MediaItem duration WHILE nextUnresolvedTrack is loading
      fakePlayer.setSourceGate = Completer<void>();
      fakePlayer.nextSetSourceDuration = const Duration(seconds: 43);

      final skipFut = handler.skipToNext();
      await handler.mediaItem.stream
          .firstWhere((m) => m?.id == 'youtube_itunes_987654321')
          .timeout(const Duration(seconds: 2));
      await pumpEventQueue(times: 5);

      // During loading, mediaItem MUST NOT show previous song's 4:29 duration!
      expect(handler.mediaItem.value?.id, equals('youtube_itunes_987654321'));
      expect(handler.mediaItem.value?.title, equals('Who Is This Dude?'));
      expect(handler.mediaItem.value?.duration, equals(const Duration(seconds: 43)));

      // Complete loading of verified recording
      fakePlayer.setSourceGate?.complete();
      await skipFut;
      await pumpEventQueue(times: 10);

      expect(
        (fakePlayer.loadedSources.last as UriAudioSource).uri.toString(),
        contains('id=JGebNY0X5EY'),
      );
      expect(handler.loadedAudioTrackId, equals('youtube_itunes_987654321'));
      expect(handler.mediaItem.value?.duration, equals(const Duration(seconds: 43)));

      await handler.disposeHandler();
    });

    test(
        '10. NextTrackPreloader uses PlaybackSourceResolver for unresolved external track IDs',
        () async {
      final repo = _DeterministicYouTubeRepository(
        queryResponses: {
          'Sai Abhyankkar - Who Is This Dude? (Official Audio)': [
            _oorumBloodUnplugged,
          ],
          'Sai Abhyankkar Who Is This Dude?': [
            _authenticWhoIsThisDude,
          ],
        },
      );
      final resolver = PlaybackSourceResolver.withRepository(repo);
      final requestedStreamIds = <String>[];

      final preloader = NextTrackPreloader(
        sourceResolver: resolver,
        resolveYouTubeStream: (id, {forceRefresh = false, title, artist}) async {
          requestedStreamIds.add(id);
          return ResolvedYouTubeStream(
            url: 'https://rr1---sn-test.googlevideo.com/videoplayback?id=$id&expire=2524608000',
            userAgent: kYouTubeVisionOsUserAgent,
            clientName: 'VISIONOS',
          );
        },
      );

      const currentTrack = Track(
        id: 'youtube_4Bsc2uI_LsM',
        title: 'Oorum Blood',
        artist: 'Sai Abhyankkar',
        imageUrl: '',
        duration: '4:29',
      );
      const upcomingTrack = Track(
        id: 'youtube_itunes_99887766',
        title: 'Who Is This Dude?',
        artist: 'Sai Abhyankkar',
        albumName: 'Dude',
        imageUrl: '',
        duration: '0:43',
        metadataProvider: 'itunes',
      );

      await preloader.syncWindow(
        queue: [currentTrack, upcomingTrack],
        currentIndex: 0,
        loopMode: LoopMode.off,
      );
      await pumpEventQueue(times: 20);

      expect(requestedStreamIds, equals(['JGebNY0X5EY']));
      await preloader.dispose();
    });
  });
}
