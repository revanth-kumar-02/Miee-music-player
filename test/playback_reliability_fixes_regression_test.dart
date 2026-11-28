import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/youtube_audio_service.dart';
import 'package:Miee/core/network/network_request_coordinator.dart';
import 'package:Miee/core/storage/adapters/queue_snapshot.dart';
import 'package:Miee/features/artwork/data/artwork_resolver_impl.dart';
import 'package:Miee/features/artwork/domain/artwork_query.dart';
import 'package:Miee/features/artwork/domain/resolved_artwork.dart';
import 'package:Miee/features/artwork/presentation/artwork_providers.dart';
import 'package:Miee/features/history/domain/listening_event.dart';
import 'package:Miee/features/history/domain/listening_history_repository.dart';
import 'package:Miee/features/history/providers/history_providers.dart';
import 'package:Miee/features/library/data/preferences_repository.dart';
import 'package:Miee/features/library/data/queue_state_repository.dart';
import 'package:Miee/features/library/data/recently_played_repository.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/media/providers/media_providers.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/search/data/playback_source_resolver.dart';
import 'package:Miee/features/search/domain/canonical_music_ranker.dart';
import 'package:Miee/features/youtube/data/web_music_discovery_source.dart';
import 'package:Miee/features/youtube/data/youtube_data_source.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

class _DisabledDataSource extends YouTubeDataSource {
  @override
  bool get isConfigured => false;
}

class _StubWebDiscovery implements WebMusicDiscoverySource {
  final Future<List<YouTubeVideo>> Function(String query) onSearch;
  int callCount = 0;

  _StubWebDiscovery(this.onSearch);

  @override
  Future<List<YouTubeVideo>> searchVideos(
    String query, {
    int limit = 25,
    Duration retryDelay = Duration.zero,
  }) async {
    callCount++;
    return onSearch(query);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubYouTubeRepository extends YouTubeRepository {
  final Map<String, List<YouTubeVideo>> responses;
  final List<String> queriesExecuted = [];
  final Map<String, Completer<void>> gates;

  _StubYouTubeRepository({
    this.responses = const {},
    this.gates = const {},
  });

  @override
  Future<List<YouTubeVideo>> search(
    String query, {
    int page = 1,
    bool forceFresh = false,
    NetworkPriority priority = NetworkPriority.userSearch,
  }) async {
    queriesExecuted.add(query);
    if (gates.containsKey(query)) {
      await gates[query]!.future;
    }
    if (responses.containsKey(query)) {
      return responses[query]!;
    }
    final qLower = query.toLowerCase();
    for (final e in responses.entries) {
      if (e.key.toLowerCase() == qLower) return e.value;
    }
    for (final e in responses.entries) {
      if (qLower.contains(e.key.toLowerCase())) return e.value;
    }
    return const [];
  }
}

class _FakeAudioPlayer extends AudioPlayer {
  bool _playing = false;
  ProcessingState _procState = ProcessingState.idle;
  Duration _position = Duration.zero;
  Duration? _duration;
  double _volume = 1.0;

  Duration nextSetDuration = const Duration(minutes: 4);
  Duration positionAfterSet = Duration.zero;
  Object? throwOnNextSet;
  final List<AudioSource> loadedSources = [];
  final List<Duration?> initialPositions = [];
  Completer<void>? setSourceGate;

  final _stateCtrl = StreamController<PlayerState>.broadcast();
  final _posCtrl = StreamController<Duration>.broadcast();
  final _durCtrl = StreamController<Duration?>.broadcast();
  final _eventCtrl = StreamController<PlaybackEvent>.broadcast();
  final _errCtrl = StreamController<PlayerException>.broadcast();

  _FakeAudioPlayer() : super(handleInterruptions: false);

  @override
  bool get playing => _playing;
  @override
  ProcessingState get processingState => _procState;
  @override
  Duration get position => _position;
  @override
  Duration get bufferedPosition => _position;
  @override
  Duration? get duration => _duration;
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

  void emitPosition(Duration p) {
    _position = p;
    _posCtrl.add(p);
  }

  void emitState(bool playing, ProcessingState proc) {
    _playing = playing;
    _procState = proc;
    _stateCtrl.add(PlayerState(playing, proc));
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    if (throwOnNextSet != null) {
      final err = throwOnNextSet!;
      throwOnNextSet = null;
      throw err;
    }
    loadedSources.add(source);
    initialPositions.add(initialPosition);
    if (setSourceGate != null) {
      await setSourceGate!.future;
      setSourceGate = null;
    }
    _duration = nextSetDuration;
    _position = initialPosition ?? positionAfterSet;
    _procState = ProcessingState.ready;
    _stateCtrl.add(PlayerState(_playing, _procState));
    _durCtrl.add(_duration);
    return _duration;
  }

  @override
  Future<void> play() async {
    _playing = true;
    _procState = ProcessingState.ready;
    _stateCtrl.add(PlayerState(true, _procState));
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _stateCtrl.add(PlayerState(false, _procState));
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _procState = ProcessingState.idle;
    _stateCtrl.add(PlayerState(false, ProcessingState.idle));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (position != null) {
      _position = position;
      _posCtrl.add(position);
    }
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

class _FakeQueueStateRepo implements QueueStateRepository {
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
  @override
  Future<void> clear() async {}
}

class _FakePreferencesRepo implements PreferencesRepository {
  @override
  double getPlaybackSpeed() => 1.0;
  @override
  String getRepeatMode() => 'off';
  @override
  bool getShuffle() => false;
  @override
  String getSourceSelectionMode() => 'smart';
  @override
  bool getResumePlayback() => false;
  @override
  bool getAutoPlayNext() => false;
  @override
  bool getShuffleDefault() => false;
  @override
  String getRepeatDefault() => 'off';
  @override
  bool getCrossfadeEnabled() => false;
  @override
  bool getGaplessPlaybackEnabled() => true;
  @override
  String? getLastScanTime() => null;
  @override
  bool getMediaNotificationEnabled() => true;
  @override
  bool getBackgroundPlaybackEnabled() => true;
  @override
  bool getLockScreenControlsEnabled() => true;
  @override
  String getAudioQuality() => 'high';
  @override
  int? getSleepTimerMinutes() => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeListeningHistoryRepo implements ListeningHistoryRepository {
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

class _FakeRecentlyPlayedRepo implements RecentlyPlayedRepository {
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
  Future<ResolvedArtwork> resolve(ArtworkQuery query,
          {bool forceRefresh = false}) async =>
      ResolvedArtwork.neutralFallback();
}

void _stubAudioSessionChannel() {
  const channel = MethodChannel('com.ryanheise.android_audio_manager');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _stubAudioSessionChannel();

  setUp(() {
    YouTubeAudioService().resetTestingHooks();
    YouTubeAudioService().clearCache();
  });

  tearDown(() {
    YouTubeAudioService().resetTestingHooks();
    YouTubeAudioService().clearCache();
  });

  group('Real-Device Playback Reliability Fix Regression Suite (1-15)', () {
    test('1. YouTube search redirect failures open circuit and use fallback discovery', () async {
      var explodeCalls = 0;
      final webFallback = _StubWebDiscovery((query) async => [
            const YouTubeVideo(
              id: 'sy_-_bczxJA',
              title: 'Nenjukkul Peidhidum',
              channelTitle: 'Hariharan',
              thumbnailUrl: 'https://i.ytimg.com/vi/sy_-_bczxJA/hqdefault.jpg',
              duration: '6:10',
              viewCount: '10M views',
            ),
          ]);
      final repo = YouTubeRepository(
        dataSource: _DisabledDataSource(),
        webDiscoverySource: webFallback,
        explodeRedirectCooldown: const Duration(minutes: 3),
        explodeSearchOverride: (query, {page = 1}) async {
          explodeCalls++;
          throw http.ClientException(
            'Redirect limit exceeded, uri=https://www.youtube.com/results?google_abuse=123',
          );
        },
      );

      final r1 = await repo.search('Hariharan song');
      expect(r1.length, 1);
      expect(explodeCalls, 1);
      expect(repo.isExplodeCircuitOpen, isTrue);

      final r2 = await repo.search('Another song');
      expect(r2.length, 1);
      // Circuit stayed open — Explode was bypassed on second query
      expect(explodeCalls, 1);
      expect(webFallback.callCount, 2);
    });

    test('2. YouTube provider transient failure retries once with backoff then falls back; independent web cooldown', () async {
      var explodeCalls = 0;
      final repo1 = YouTubeRepository(
        dataSource: _DisabledDataSource(),
        webDiscoverySource: _StubWebDiscovery((_) async => const [
              YouTubeVideo(
                id: 'ak0hINihXIM',
                title: 'Vaa Vaathi',
                channelTitle: 'G.V. Prakash Kumar',
                thumbnailUrl: '',
                duration: '3:47',
                viewCount: '5M views',
              ),
            ]),
        explodeRetryDelay: Duration.zero,
        explodeSearchOverride: (query, {page = 1}) async {
          explodeCalls++;
          if (explodeCalls == 1) {
            throw const SocketException('Temporary reset');
          }
          return const [
            YouTubeVideo(
              id: 'ak0hINihXIM',
              title: 'Vaa Vaathi',
              channelTitle: 'G.V. Prakash Kumar',
              thumbnailUrl: '',
              duration: '3:47',
              viewCount: '5M views',
            ),
          ];
        },
      );
      final res1 = await repo1.search('Vaa Vaathi');
      expect(explodeCalls, 2);
      expect(res1.first.id, 'ak0hINihXIM');

      final failingWeb = _StubWebDiscovery((_) async {
        throw Exception('Fallback unavailable');
      });
      final repo2 = YouTubeRepository(
        dataSource: _DisabledDataSource(),
        webDiscoverySource: failingWeb,
        explodeRetryDelay: Duration.zero,
        webDiscoveryCooldown: const Duration(seconds: 30),
        explodeSearchOverride: (_, {page = 1}) async => const [],
      );
      expect(await repo2.search('Query A'), isEmpty);
      expect(repo2.isWebDiscoveryCircuitOpen, isTrue);
      expect(await repo2.search('Query B'), isEmpty);
      expect(failingWeb.callCount, 1);
    });

    test('3. Weak candidate rejection rejects unrelated low-score videos', () async {
      final repo = _StubYouTubeRepository(responses: {
        'A.R. Rahman - Munbe Vaa (Official Audio)': const [
          YouTubeVideo(
            id: 'unrel123456',
            title: 'Tamil Comedy Reactions Part 2',
            channelTitle: 'Random Channel',
            thumbnailUrl: '',
            duration: '6:00',
            viewCount: '1K views',
          ),
        ],
      });
      final resolver = PlaybackSourceResolver.withRepository(repo);
      final match = await resolver.resolveCandidate(
        title: 'Munbe Vaa',
        artist: 'A.R. Rahman',
        durationStr: '5:59',
      );
      expect(match, isNull);
    });

    test('4. Exact Tamil title and artist matching selects authentic studio track', () async {
      final repo = _StubYouTubeRepository(responses: {
        'Ilaiyaraaja, Kamal Haasan & S. Janaki - Kanmani Anbodu Kadhalan (Official Audio)':
            const [
          YouTubeVideo(
            id: 'wrong999999',
            title: 'Kanmani Anbodu Dialogue Scene Only',
            channelTitle: 'Movie Clips',
            thumbnailUrl: '',
            duration: '1:45',
            viewCount: '50K views',
          ),
          YouTubeVideo(
            id: 'TF5TT6F5UuY',
            title: 'Kanmani Anbodu Kadhalan',
            channelTitle: 'Ilaiyaraaja Official',
            thumbnailUrl: '',
            duration: '5:27',
            viewCount: '12M views',
          ),
        ],
      });
      final resolver = PlaybackSourceResolver.withRepository(repo);
      final match = await resolver.resolveCandidate(
        title: 'Kanmani Anbodu Kadhalan (From "Guna")',
        artist: 'Ilaiyaraaja, Kamal Haasan & S. Janaki',
        durationStr: '5:35',
        album: 'Guna',
      );
      expect(match?.id, equals('TF5TT6F5UuY'));
    });

    test('5. Tamil transliteration and single album tokens do not reject Paathi Nee Paathi Naa', () async {
      final repo = _StubYouTubeRepository(responses: {
        'krithika Nelson & Gopi Sundar - Paathi Nee Paathi Naan (Official Audio)':
            const [
          YouTubeVideo(
            id: 'ivY-E3SFIVU',
            title: 'Paathi Nee Paathi Naa',
            channelTitle: 'Gopi Sundar',
            thumbnailUrl: '',
            duration: '6:22',
            viewCount: '4M views',
          ),
        ],
      });
      final resolver = PlaybackSourceResolver.withRepository(repo);
      final match = await resolver.resolveCandidate(
        title: 'Paathi Nee Paathi Naan (From "Nitham Oru Vaanam")',
        artist: 'krithika Nelson & Gopi Sundar',
        durationStr: '6:10',
        album: 'Paathi Nee Paathi Naan (From "Nitham Oru Vaanam") - Single',
      );
      expect(match, isNotNull);
      expect(match!.id, equals('ivY-E3SFIVU'));
    });

    test('6. Wrong-language Telugu dub & Audio Edit rejected; original Kolaveri beats cover in ranker', () async {
      final resolver = PlaybackSourceResolver();
      const teluguDub = YouTubeVideo(
        id: 'g2RQSfzFCCY',
        title: 'Maari 2 [Telugu] - Rowdy Baby',
        channelTitle: 'Wunderbar Studios',
        thumbnailUrl: '',
        duration: '4:43',
        viewCount: '200M views',
      );
      const tamilOrig = YouTubeVideo(
        id: 'x6Q7c9RyMzk',
        title: 'Maari 2 - Rowdy Baby (Video Song) | Dhanush, Sai Pallavi',
        channelTitle: 'Wunderbar Studios',
        thumbnailUrl: '',
        duration: '4:44',
        viewCount: '1.5B views',
      );
      final picked = resolver.selectBestCandidate(
        const [teluguDub, tamilOrig],
        title: 'Rowdy Baby',
        artist: 'Dhanush & Dhee',
        durationStr: '4:41',
        album: 'Maari 2',
      );
      expect(picked?.id, equals('x6Q7c9RyMzk'));
      expect(
        resolver.selectBestCandidate(
          const [teluguDub],
          title: 'Rowdy Baby',
          artist: 'Dhanush & Dhee',
          durationStr: '4:41',
          album: 'Maari 2',
        ),
        isNull,
      );

      // Canonical ranker: original Anirudh/Dhanush "? (The Soup of Love)" beats cover Ankit Love
      final cover = YouTubeVideo(
        id: 'ConiyhtSScQ',
        title: 'Why This Kolaveri Di',
        channelTitle: 'Ankit Love feat. Amit Bhojwani',
        thumbnailUrl: '',
        duration: '3:43',
        viewCount: '50K views',
        canonicalTitle: 'Why This Kolaveri Di',
        canonicalArtist: 'Ankit Love feat. Amit Bhojwani',
        metadataProvider: 'musicbrainz',
      );
      final original = YouTubeVideo(
        id: '5Olm6geycS4',
        title: 'Why This Kolaveri Di ? (The Soup of Love)',
        channelTitle: 'Anirudh Ravichander & Dhanush',
        thumbnailUrl: '',
        duration: '4:19',
        viewCount: '300M views',
        canonicalTitle: 'Why This Kolaveri Di ? (The Soup of Love)',
        canonicalArtist: 'Anirudh Ravichander & Dhanush',
        metadataProvider: 'musicbrainz',
      );
      final ranked = CanonicalMusicRanker.rankVideos(
        [cover, original],
        query: 'Why This Kolaveri Di',
        prominentArtists: const [
          ArtistModel(id: 'anirudh', name: 'Anirudh Ravichander', imageUrl: '', fanCount: 1500000),
        ],
      );
      expect(ranked.first.canonicalArtist, contains('Anirudh'));
    });

    test('7 & 8. Stream resolution failure/PlayerException excludes failed video ID & recovers via alternate upload keeping canonical identity', () async {
      final repo = _StubYouTubeRepository(responses: {
        'Vaseegara': const [
          YouTubeVideo(
            id: 'brokenVid01',
            title: 'Vaseegara',
            channelTitle: 'Bombay Jayashri',
            thumbnailUrl: '',
            duration: '4:58',
            viewCount: '5M views',
          ),
          YouTubeVideo(
            id: 'backupVid02',
            title: 'Vaseegara (Official Audio)',
            channelTitle: 'Bombay Jayashri',
            thumbnailUrl: '',
            duration: '4:59',
            viewCount: '12M views',
          ),
        ],
      });
      final resolver = PlaybackSourceResolver.withRepository(repo);

      YouTubeAudioService().manifestFetcherForTesting = (vid, clients) async {
        if (vid == 'brokenVid01') {
          throw TimeoutException('Stream resolution timed out');
        }
        return StreamManifest([
          AudioOnlyStreamInfo.fromJson({
            'videoId': {'value': vid},
            'tag': 140,
            'url': 'https://rr1---sn-test.googlevideo.com/videoplayback?id=$vid&expire=2524608000',
            'container': {'name': 'mp4'},
            'size': {'totalBytes': 1024000},
            'bitrate': {'bitsPerSecond': 128000},
            'audioCodec': 'mp4a.40.2',
            'qualityLabel': 'medium',
            'fragments': const <dynamic>[],
            'codec': 'audio/mp4',
            'audioTrack': null,
          }),
        ]);
      };

      final player = _FakeAudioPlayer();
      final handler = MieeAudioHandler(player: player, sourceResolver: resolver);
      String? updatedSourceId;
      handler.onPlaybackSourceResolved = (_, vId) => updatedSourceId = vId;

      const track = Track(
        id: 'youtube_brokenVid01',
        title: 'Vaseegara',
        artist: 'Bombay Jayashri',
        imageUrl: '',
        duration: '4:58',
      );
      await handler.loadQueue([track]);

      expect(handler.loadedAudioTrackId, equals('youtube_brokenVid01'));
      expect(updatedSourceId, equals('backupVid02'));
      expect(YouTubeAudioService().isVideoRecentlyFailed('brokenVid01'), isTrue);

      // Subsequent candidate resolution excludes failed brokenVid01 automatically
      final nextResolve = await resolver.resolveCandidate(
        title: 'Vaseegara',
        artist: 'Bombay Jayashri',
        durationStr: '4:58',
      );
      expect(nextResolve?.id, equals('backupVid02'));

      await handler.disposeHandler();
    });

    test('9, 10, 12, 13 & 14. Position resets on new/failed-retry track, stale events rejected, failed load excluded from history, identity & rapid switches safe', () async {
      final slowGate = Completer<void>();
      final repo = _StubYouTubeRepository(
        responses: {
          'Slow Track': const [
            YouTubeVideo(
              id: 'slowA000001',
              title: 'Slow Track',
              channelTitle: 'Artist A',
              thumbnailUrl: '',
              duration: '4:00',
              viewCount: '1M views',
            ),
          ],
          'Munbe Vaa': const [
            YouTubeVideo(
              id: '_Z6wxp-WPjw',
              title: 'Munbe Vaa',
              channelTitle: 'A.R. Rahman',
              thumbnailUrl: '',
              duration: '5:57',
              viewCount: '50M views',
            ),
          ],
        },
        gates: {'A.R. Rahman - Munbe Vaa (Official Audio)': slowGate},
      );

      final resolver = PlaybackSourceResolver.withRepository(repo);
      final player = _FakeAudioPlayer();
      final handler = MieeAudioHandler(player: player, sourceResolver: resolver);
      final recentRepo = _FakeRecentlyPlayedRepo();

      YouTubeAudioService().cacheUrlForTesting(
        'sy_-_bczxJA',
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=sy_-_bczxJA&expire=2524608000',
      );
      YouTubeAudioService().cacheUrlForTesting(
        '_Z6wxp-WPjw',
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=_Z6wxp-WPjw&expire=2524608000',
      );

      final container = ProviderContainer(overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        preferencesRepositoryProvider.overrideWithValue(_FakePreferencesRepo()),
        queueStateRepositoryProvider.overrideWithValue(_FakeQueueStateRepo()),
        listeningHistoryRepositoryProvider.overrideWithValue(_FakeListeningHistoryRepo()),
        recentlyPlayedRepositoryProvider.overrideWithValue(recentRepo),
        artworkResolverProvider.overrideWithValue(_FakeArtworkResolver()),
        songsProvider.overrideWithValue(const []),
        sourceSelectionProvider.overrideWithValue('preferYouTube'),
        playerControllerProvider.overrideWith((ref) => PlayerController(
              handler,
              ref.watch(queueManagerProvider),
              ref,
              sourceResolver: resolver,
            )),
      ]);

      final ctrl = container.read(playerControllerProvider.notifier);

      // Play track 1 to 246s
      const track1 = Track(
        id: 'youtube_sy_-_bczxJA',
        title: 'Nenjukkul Peidhidum',
        artist: 'Hariharan',
        imageUrl: '',
        duration: '6:10',
      );
      await ctrl.playTrack(track1);
      player.emitPosition(const Duration(seconds: 246));
      await pumpEventQueue(times: 5);
      expect(container.read(playerControllerProvider).position, const Duration(seconds: 246));
      expect(recentRepo.recorded.map((t) => t.id), contains('youtube_sy_-_bczxJA'));

      // Tap unresolved track that fails resolution -> must NOT pollute history or leak 246s position
      const unresolvable = Track(
        id: 'youtube_itunes_unresolvable',
        title: 'Nonexistent Recording XYZ',
        artist: 'Nobody',
        imageUrl: '',
        duration: '3:00',
        metadataProvider: 'itunes',
      );
      await ctrl.playTrack(unresolvable);
      await pumpEventQueue(times: 5);
      expect(recentRepo.recorded.any((t) => t.id == unresolvable.id), isFalse);
      expect(container.read(playerControllerProvider).position, Duration.zero);

      // Re-tap unresolvable fails cleanly at 0:00, never carrying 246s!
      await ctrl.playTrack(unresolvable);
      expect(container.read(playerControllerProvider).position, Duration.zero);

      // Rapid switch: start track A waiting in slowGate, then switch to fast track B
      const slowTrackA = Track(
        id: 'youtube_itunes_munbe',
        title: 'Munbe Vaa',
        artist: 'A.R. Rahman',
        imageUrl: '',
        duration: '5:57',
        metadataProvider: 'itunes',
      );
      final slowFut = ctrl.playTrack(slowTrackA);
      await pumpEventQueue(times: 5);
      // Stale position emission from old player must be rejected while loading
      player.emitPosition(const Duration(seconds: 246));
      await pumpEventQueue(times: 5);
      expect(container.read(playerControllerProvider).position, Duration.zero);

      // Select fast track 1 while slowTrackA is still resolving
      await ctrl.playTrack(track1);
      await pumpEventQueue(times: 5);
      slowGate.complete();
      await slowFut;
      await pumpEventQueue(times: 10);

      // Current track stays track1; slowTrackA discarded
      expect(container.read(playerControllerProvider).currentTrack?.id, track1.id);
      expect(handler.loadedAudioTrackId, track1.id);

      await handler.disposeHandler();
      container.dispose();
    });

    test('11. Next and Previous keep queue, mediaItem, and position synchronized', () async {
      final player = _FakeAudioPlayer();
      final handler = MieeAudioHandler(player: player);
      YouTubeAudioService().cacheUrlForTesting(
        'TF5TT6F5UuY',
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=TF5TT6F5UuY&expire=2524608000',
      );
      YouTubeAudioService().cacheUrlForTesting(
        '4O7m1atlBmw',
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=4O7m1atlBmw&expire=2524608000',
      );

      const q0 = Track(
        id: 'youtube_TF5TT6F5UuY',
        title: 'Kanmani Anbodu Kadhalan',
        artist: 'Ilaiyaraaja',
        imageUrl: '',
        duration: '5:27',
      );
      const q1 = Track(
        id: 'youtube_4O7m1atlBmw',
        title: 'Kadhale En Kadhale',
        artist: 'Hiphop Tamizha',
        imageUrl: '',
        duration: '3:50',
      );

      await handler.loadQueue([q0, q1]);
      await handler.play();
      player.emitPosition(const Duration(seconds: 117));
      expect(handler.mediaItem.value?.id, q0.id);

      await handler.skipToNext();
      expect(handler.currentIndex, 1);
      expect(handler.mediaItem.value?.id, q1.id);
      expect(player.initialPositions.last, isNull);

      await handler.skipToPrevious();
      expect(handler.currentIndex, 0);
      expect(handler.mediaItem.value?.id, q0.id);

      await handler.disposeHandler();
    });

    test('15. Multiple simultaneous search requests deduplicate in-flight YouTube & Web discovery calls', () async {
      var explodeInvocations = 0;
      final gate = Completer<void>();
      final repo = YouTubeRepository(
        dataSource: _DisabledDataSource(),
        explodeSearchOverride: (query, {page = 1}) async {
          explodeInvocations++;
          await gate.future;
          return const [
            YouTubeVideo(
              id: 'a3Ue-LN5B9U',
              title: 'Aasa Kooda',
              channelTitle: 'Sai Abhyankkar',
              thumbnailUrl: '',
              duration: '3:48',
              viewCount: '80M views',
            ),
          ];
        },
      );

      final futures = [
        repo.search('Aasa Kooda'),
        repo.search('aasa kooda'),
        repo.search('  Aasa Kooda  '),
      ];
      gate.complete();
      final results = await Future.wait(futures);

      expect(explodeInvocations, 1);
      expect(results.every((r) => r.length == 1 && r.first.id == 'a3Ue-LN5B9U'), isTrue);
    });
  });
}
