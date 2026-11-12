import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../../shared/models/music_item.dart';
import '../../shared/models/track.dart';
import '../../features/media/domain/models.dart';
import '../../features/youtube/data/web_music_discovery_source.dart';
import 'youtube_audio_service.dart';
import 'playback_diagnostics.dart';
import 'playback_state.dart' show isSameTrackId;
import 'preloading/next_track_preloader.dart';
import 'preloading/preload_models.dart';

/// Duration for fast-forward and rewind operations.
const _kSkipDuration = Duration(seconds: 10);

/// Maximum number of fresh-URL retries before treating a YouTube track as non-recoverable.
const _kMaxYouTubeRetries = 2;

/// [MieeAudioHandler] is the single audio engine for Miee.
///
/// Subclasses [BaseAudioHandler] from `audio_service` to:
/// - Provide a persistent foreground service with a media-style notification.
/// - Route system/Bluetooth/headset media button events.
/// - Expose the current [MediaItem] (title, artist, artwork) to the OS.
/// - Maintain audio focus via `audio_session`.
///
/// IMPORTANT: [PlayerController] must NOT call skipToNext/skipToPrevious on
/// [ProcessingState.completed] because this handler already does so in
/// [_onPlayerStateChanged]. Doing both causes a double-skip.
class MieeAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;

  /// Current ordered queue of tracks.
  final List<MusicItem> _queue = [];
  int _currentIndex = -1;

  /// Stable track ID of the audio source that is verified and currently loaded in [_player].
  /// Null if loading, in-flight, failed, or stopped.
  String? _loadedAudioTrackId;
  String? get loadedAudioTrackId => _loadedAudioTrackId;

  /// Remembers the last valid playback position across interruptions, stream refreshes,
  /// and app lifecycle transitions to prevent unwanted resets to 00:00.
  Duration _lastValidPosition = Duration.zero;
  Duration get lastValidPosition => _lastValidPosition;

  /// Remembers the last track ID loaded to distinguish same-track reload from new-track selection.
  String? _lastTrackId;
  String? get lastTrackId => _lastTrackId;

  /// Tracks whether the user explicitly initiated a pause/stop action.
  /// When false, mid-stream pauses are treated as unexpected stalls or errors,
  /// enabling seamless stream recovery without losing playback intent.
  bool _userExplicitlyPaused = false;
  bool get userExplicitlyPaused => _userExplicitlyPaused;

  /// Indicates whether a track source load or transition is actively underway.
  /// Prevents transient pause states from demoting the Android foreground service.
  bool _isLoadingTrack = false;
  bool get isLoadingTrack => _isLoadingTrack;

  /// Tracks whether an automatic stream recovery is actively in progress.
  /// Prevents redundant, overlapping recovery attempts across error and watchdog triggers.
  bool _isRecovering = false;
  bool get isRecovering => _isRecovering;

  /// Watchdog timer to detect silent stalls where ExoPlayer buffers indefinitely
  /// without throwing a fatal exception (e.g. half-open TCP connections, cellular handover).
  Timer? _bufferingWatchdogTimer;
  Duration? _bufferingStartPosition;
  String? _bufferingTrackId;
  int? _bufferingStartToken;
  static const Duration _kBufferingWatchdogTimeout = Duration(seconds: 12);

  /// Tracks whether playback was interrupted mid-stream by a transient system
  /// interruption (e.g. phone call). If the user explicitly pauses/stops the
  /// song, or if the song was already paused when an interruption occurred,
  /// this is ALWAYS false. This guarantees Miee NEVER resumes playback when
  /// external apps (like Instagram Reels, TikTok, YouTube, Twitter) lose or
  /// yield audio focus.
  bool _playInterrupted = false;

  @visibleForTesting
  bool get playInterrupted => _playInterrupted;

  @visibleForTesting
  void setLastValidPositionForTesting(Duration pos) {
    _lastValidPosition = pos;
  }

  @visibleForTesting
  void setQueueForTesting(List<MusicItem> tracks, {int currentIndex = 0}) {
    _queue.clear();
    _queue.addAll(tracks);
    _currentIndex = currentIndex;
  }

  @visibleForTesting
  int get activeLoadTokenForTesting => _activeLoadToken;

  @visibleForTesting
  int incrementActiveLoadTokenForTesting() => ++_activeLoadToken;

  @visibleForTesting
  bool get isRecoveringForTesting => _isRecovering;

  @visibleForTesting
  Timer? get bufferingWatchdogTimerForTesting => _bufferingWatchdogTimer;

  @visibleForTesting
  void startBufferingWatchdogForTesting() => _startBufferingWatchdog();

  @visibleForTesting
  void cancelBufferingWatchdogForTesting() => _cancelBufferingWatchdog();

  @visibleForTesting
  Future<void> triggerBufferingWatchdogForTesting() => _onBufferingWatchdogFired();

  @visibleForTesting
  void setBufferingWatchdogDetailsForTesting({
    String? trackId,
    int? token,
    Duration? startPosition,
  }) {
    _bufferingTrackId = trackId;
    _bufferingStartToken = token;
    _bufferingStartPosition = startPosition;
  }

  @visibleForTesting
  AudioPlayer get playerForTesting => _player;

  @visibleForTesting
  int get maxYouTubeRetriesForTesting => _kMaxYouTubeRetries;

  /// Indicates whether this device is a listener in a shared listening room.
  /// When true, track completion NEVER autonomously advances playback
  /// via [skipToNext]. Instead, the listener waits for the host's authoritative
  /// room state update.
  bool _isRoomListener = false;
  bool get isRoomListener => _isRoomListener;

  void setRoomListener(bool value) {
    debugPrint('[AudioHandler] setRoomListener: $value');
    _isRoomListener = value;
  }

  /// Optional callback invoked when playback approaches the end of the queue
  /// to dynamically replenish upcoming tracks without interrupting playback.
  Future<void> Function()? onQueueApproachingEnd;

  /// Rolling two-track audio preloader for upcoming queue items.
  final NextTrackPreloader _preloader;

  /// Exposes the preloader instance for diagnostics and testing.
  NextTrackPreloader get preloader => _preloader;

  /// Guards against concurrent [skipToNext] invocations (e.g. rapid taps or
  /// completion re-entrancy).
  bool _isSkippingNext = false;
  bool _isCompletionSkip = false;
  int _activeSkipToken = 0;
  int _lastHandledCompletionToken = -1;

  /// Tracks recent stream errors to debounce duplicate emissions across
  /// `errorStream`, `PlaybackEvent.errorCode`, and `playbackEventStream.onError`.
  String? _lastHandledErrorSignature;
  String? _lastHandledErrorTrackId;
  DateTime? _lastHandledErrorAt;
  static const Duration _kErrorDebounceWindow = Duration(seconds: 2);
  static const Duration _kCrossChannelCooldown = Duration(milliseconds: 500);

  /// Monotonically increasing token to discard stale in-flight loads
  /// when a user rapidly selects a different song.
  int _activeLoadToken = 0;

  @visibleForTesting
  bool get isSkippingNextForTesting => _isSkippingNext;

  /// Controller to stream playback errors to PlayerController.
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  // Stream subscriptions
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<PlayerException>? _playerErrorSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;

  /// Sanitized descriptor of the currently configured audio source (never logs signed URLs).
  String _currentSourceSummary = 'none';
  DateTime _lastDiagHeartbeat = DateTime.fromMillisecondsSinceEpoch(0);

  String _ts() => DateTime.now().toIso8601String();

  String _sanitizeSourceDescriptor(String rawSource, {MusicItem? track}) {
    final prefix = track != null
        ? 'trackId=${track.id},isYt=${track.isYoutube}'
        : 'trackId=unknown';
    if (rawSource.isEmpty) return '$prefix,src=empty';
    final uri = Uri.tryParse(rawSource);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final host = uri.host;
      final itag = uri.queryParameters['itag'] ?? '';
      final client = uri.queryParameters['c'] ?? '';
      final expire = uri.queryParameters['expire'] ?? '';
      return '$prefix,src=http://$host(itag=$itag,c=$client,exp=$expire)';
    }
    final fileName = rawSource.split(RegExp(r'[/\\]')).last;
    return '$prefix,src=file($fileName)';
  }

  void _logDiagnosticTransition(
    String event, {
    PlayerState? playerState,
    String? extra,
    bool includeStack = false,
  }) {
    final playing = playerState?.playing ?? _player.playing;
    final proc = playerState?.processingState ?? _player.processingState;
    final posMs = _player.position.inMilliseconds;
    final bufMs = _player.bufferedPosition.inMilliseconds;
    final durMs = _player.duration?.inMilliseconds;
    debugPrint(
      '[PlaybackDiag ${_ts()}] $event | '
      'playing=$playing proc=$proc pos=${posMs}ms buf=${bufMs}ms dur=${durMs}ms '
      'loading=$_isLoadingTrack recovering=$_isRecovering userPaused=$_userExplicitlyPaused '
      'interrupted=$_playInterrupted token=$_activeLoadToken | $_currentSourceSummary'
      '${extra != null ? ' | $extra' : ''}',
    );
    if (includeStack) {
      debugPrintStack(
        stackTrace: StackTrace.current,
        label: '[PlaybackDiag ${_ts()}] Call stack for $event',
        maxFrames: 10,
      );
    }
  }

  /// Whether `just_audio` should spin up its Dart loopback HTTP proxy for request headers.
  ///
  /// Disabled on native Android so ExoPlayer's `DefaultHttpDataSource` streams HTTPS
  /// directly with `User-Agent` headers and native cross-protocol redirects.
  static bool get shouldUseProxyForRequestHeaders =>
      kIsWeb || defaultTargetPlatform != TargetPlatform.android;

  MieeAudioHandler({AudioPlayer? player, NextTrackPreloader? preloader})
      : _preloader = preloader ?? NextTrackPreloader(),
        _player = player ??
            AudioPlayer(
              handleInterruptions: false,
              useProxyForRequestHeaders: shouldUseProxyForRequestHeaders,
            ) {
    _listenToPlayerStreams();
    queue.add([]);
    debugPrint('[AudioHandler] MieeAudioHandler() constructed');
  }

  /// Configures the audio session for music playback and wires up interruptions.
  Future<void> initialize() async {
    if (kIsWeb) {
      debugPrint('[BackgroundAudio] Web platform: skipping native AudioSession');
      return;
    }
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          // Do NOT pause music when transient ducking sounds (lock clicks, GPS chimes) occur
          androidWillPauseWhenDucked: false,
        ),
      );

      _interruptionSub = session.interruptionEventStream.listen(handleInterruptionEvent);

      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        debugPrint('[BackgroundAudio] Becoming noisy (headset removed) — pausing');
        _logDiagnosticTransition(
          'INTERRUPTION_BECOMING_NOISY_PAUSE',
          includeStack: true,
        );
        _playInterrupted = false;
        if (_player.position > Duration.zero) {
          _lastValidPosition = _player.position;
        }
        _player.pause();
      });

      debugPrint('[BackgroundAudio] AudioSession initialized for music playback (androidWillPauseWhenDucked: false)');
    } catch (e) {
      debugPrint('[AudioHandler] initialize() error: $e');
    }
  }

  /// Handles incoming audio interruption events from the system audio session.
  @visibleForTesting
  void handleInterruptionEvent(AudioInterruptionEvent event) {
    _logDiagnosticTransition(
      'INTERRUPTION_EVENT',
      extra: 'begin=${event.begin},type=${event.type}',
    );
    debugPrint(
      '[BackgroundAudio] Audio interruption event: begin=${event.begin}, type=${event.type}, '
      'player.playing=${_player.playing}, playInterrupted=$_playInterrupted',
    );

    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          if (_player.playing) {
            _player.setVolume((_player.volume * 0.3).clamp(0.1, 1.0));
          }
          break;
        case AudioInterruptionType.pause:
          // Transient interruption (e.g. incoming phone call).
          if (_player.playing) {
            debugPrint(
              '[BackgroundAudio] Audio interruption began while playing — pausing with resume intent',
            );
            _playInterrupted = true;
            if (_player.position > Duration.zero) {
              _lastValidPosition = _player.position;
            }
            _logDiagnosticTransition('INTERRUPTION_PAUSE_PLAYER', extra: 'type=pause', includeStack: true);
            _player.pause();
          } else {
            debugPrint(
              '[BackgroundAudio] Audio interruption began while already paused — will NOT resume',
            );
            _playInterrupted = false;
          }
          break;
        case AudioInterruptionType.unknown:
          // Audio focus loss:
          // When switching to another application or when the device plays notification sounds,
          // Android can fire AudioManager.AUDIOFOCUS_LOSS or transient loss.
          // If Miee was actively playing and the user did not click pause, allow auto-resume!
          if (_player.playing) {
            debugPrint(
              '[BackgroundAudio] Audio focus loss (unknown) while playing — pausing with resume capability',
            );
            _playInterrupted = true;
            if (_player.position > Duration.zero) {
              _lastValidPosition = _player.position;
            }
            _logDiagnosticTransition('INTERRUPTION_PAUSE_PLAYER', extra: 'type=unknown', includeStack: true);
            _player.pause();
          } else {
            _playInterrupted = false;
          }
          break;
      }
    } else {
      // Interruption ended / audio focus returned to Miee
      switch (event.type) {
        case AudioInterruptionType.duck:
          if (_player.playing) {
            _player.setVolume(1.0);
          }
          _playInterrupted = false;
          break;
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          if (_playInterrupted && !_userExplicitlyPaused) {
            debugPrint(
              '[BackgroundAudio] Audio interruption ended — resuming prior playing state',
            );
            _playInterrupted = false;
            play();
          } else {
            debugPrint(
              '[BackgroundAudio] Audio interruption ended — staying paused (user had paused or stopped)',
            );
            _playInterrupted = false;
          }
          break;
      }
    }
  }

  void _listenToPlayerStreams() {
    _playerStateSub =
        _player.playerStateStream.listen(_onPlayerStateChanged);
    _positionSub = _player.positionStream.listen(_onPositionChanged);
    _durationSub = _player.durationStream.listen(_onDurationChanged);

    // Primary error channel in just_audio on Android: ExoPlayer native failures
    // arrive via errorStream and PlaybackEvent.errorCode (not playbackEventStream.onError).
    _playerErrorSub = _player.errorStream.listen((PlayerException pe) {
      _logDiagnosticTransition(
        'PLAYER_ERROR_STREAM_EXCEPTION',
        extra: 'code=${pe.code},msg=${pe.message},idx=${pe.index}',
      );
      unawaited(_handleStreamFailure(
        sourceChannel: 'errorStream',
        code: pe.code.toString(),
        message: pe.message,
      ));
    });

    // playbackEventStream carries PlaybackEvent.errorCode on Android and may receive
    // onError in mocked/legacy tests.
    _playbackEventSub = _player.playbackEventStream.listen(
      (PlaybackEvent event) {
        if (event.errorCode != null) {
          _logDiagnosticTransition(
            'PLAYBACK_EVENT_WITH_ERROR_CODE',
            extra: 'code=${event.errorCode},msg=${event.errorMessage},eventProc=${event.processingState}',
          );
          unawaited(_handleStreamFailure(
            sourceChannel: 'playbackEvent.errorCode',
            code: event.errorCode.toString(),
            message: event.errorMessage,
          ));
        }
      },
      onError: (Object e, StackTrace stack) async {
        _logDiagnosticTransition(
          'PLAYBACK_EVENT_ON_ERROR',
          extra: 'type=${e.runtimeType}',
        );
        debugPrint('[Playback] playbackEventStream error: $e');
        await _handleStreamFailure(
          sourceChannel: 'playbackEvent.onError',
          message: e.toString(),
        );
      },
    );
  }

  Future<void> _handleStreamFailure({
    required String sourceChannel,
    String? code,
    String? message,
  }) async {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    final current = _queue[_currentIndex];

    // Synchronous initial loads own their own retry catch inside _loadYouTubeTrack.
    if (_isLoadingTrack) {
      _logDiagnosticTransition(
        'STREAM_FAILURE_IGNORED_LOADING',
        extra: 'channel=$sourceChannel,code=$code',
      );
      return;
    }

    if (_isRecovering) {
      _logDiagnosticTransition(
        'STREAM_FAILURE_SUPPRESSED_RECOVERING',
        extra: 'channel=$sourceChannel,code=$code',
      );
      return;
    }

    final now = DateTime.now();
    final signature = '${current.id}|${code ?? ''}|${message ?? ''}';
    final sameSig = _lastHandledErrorSignature == signature &&
        _lastHandledErrorAt != null &&
        now.difference(_lastHandledErrorAt!) < _kErrorDebounceWindow;
    final rapidSameTrack = _lastHandledErrorTrackId == current.id &&
        _lastHandledErrorAt != null &&
        now.difference(_lastHandledErrorAt!) < _kCrossChannelCooldown;
    if (sameSig || rapidSameTrack) {
      _logDiagnosticTransition(
        'STREAM_FAILURE_DEBOUNCED',
        extra: 'channel=$sourceChannel,code=$code',
      );
      return;
    }
    _lastHandledErrorSignature = signature;
    _lastHandledErrorTrackId = current.id;
    _lastHandledErrorAt = now;

    if (current.isYoutube) {
      final videoId = _extractYouTubeVideoId(current.id);
      debugPrint(
        '[StreamCache] Invalidating cache for $videoId due to $sourceChannel failure (code=$code)',
      );
      YouTubeAudioService().invalidateCache(videoId);
      final wasPlaying = !_userExplicitlyPaused;
      // Hold recovery lock and buffering state synchronously before async resolution
      // so ExoPlayer's ProcessingState.idle cannot demote AudioService.
      _isRecovering = true;
      _pushPlaybackState(
        playerState: PlayerState(wasPlaying, ProcessingState.buffering),
      );
        try {
          await _recoverYouTubePlayback(
            videoId: videoId,
            track: current,
            retryCount: 0,
            resumePlayback: wasPlaying,
            ownsRecoveryLock: true,
          );
        } finally {
          _isRecovering = false;
          if (!_isLoadingTrack &&
              _player.processingState == ProcessingState.ready) {
            _pushPlaybackState();
          }
        }
    } else {
      final msg = (message ?? code ?? 'Playback error')
          .replaceFirst('Exception: ', '');
      _errorController.add(msg);
    }
  }

  void _onPlayerStateChanged(PlayerState playerState) {
    _logDiagnosticTransition(
      'PLAYER_STATE_CHANGED',
      playerState: playerState,
    );
    debugPrint(
      '[Playback] State → playing=${playerState.playing} '
      'processing=${playerState.processingState}',
    );

    // If a track load or recovery is actively underway, preserve foreground buffering state
    // so audio_service does not demote the Android foreground service on transient pause/idle.
    if (_isLoadingTrack || _isRecovering) {
      if (_isRecovering &&
          playerState.playing &&
          playerState.processingState == ProcessingState.ready) {
        // Recovery succeeded and playback resumed — allow ready state to publish immediately.
      } else {
        final intendedPlaying =
            _isRecovering ? !_userExplicitlyPaused : playbackState.value.playing;
        _pushPlaybackState(
          playerState: PlayerState(intendedPlaying, ProcessingState.buffering),
        );
        return;
      }
    }

    // Handle track completion — advance to next track (or repeat in LoopMode.one).
    // NOTE: PlayerController must NOT also handle completed, as that causes double-skip or race.
    if (playerState.processingState == ProcessingState.completed) {
      _cancelBufferingWatchdog();
      final completedTrackId =
          (_currentIndex >= 0 && _currentIndex < _queue.length)
              ? _queue[_currentIndex].id
              : 'none';
      if (_isRoomListener) {
        debugPrint('[Queue] Room listener reached track completion; waiting for host update.');
        _pushPlaybackState(playerState: playerState);
        return;
      }
      if (_player.loopMode == LoopMode.one) {
        _logDiagnosticTransition(
          'LOOP_ONE_REPEAT',
          playerState: playerState,
          extra: 'completedTrackId=$completedTrackId,index=$_currentIndex',
        );
        debugPrint('[Queue] LoopMode.one active at completion; repeating current track');
        _lastValidPosition = Duration.zero;
        unawaited(() async {
          try {
            await _player.seek(Duration.zero);
            if (!_userExplicitlyPaused) {
              await _player.play();
            }
          } catch (e) {
            debugPrint('[Queue] LoopMode.one repeat failed: $e');
          }
        }());
        return;
      }
      if (_lastHandledCompletionToken == _activeLoadToken) {
        _logDiagnosticTransition(
          'COMPLETION_DUPLICATE_IGNORED',
          playerState: playerState,
          extra: 'completedTrackId=$completedTrackId,index=$_currentIndex,alreadyHandled=true',
        );
        return;
      }
      _lastHandledCompletionToken = _activeLoadToken;
      _logDiagnosticTransition(
        'TRACK_COMPLETED',
        playerState: playerState,
        extra: 'completedTrackId=$completedTrackId,indexBefore=$_currentIndex,alreadyHandled=false',
      );
      debugPrint('[Queue] Track completed at index $_currentIndex, advancing queue');
      unawaited(skipToNext(fromCompletion: true));
      return;
    }

    _pushPlaybackState(playerState: playerState);

    // Record confirmed playing latency metric
    if (playerState.playing && playerState.processingState == ProcessingState.ready) {
      if (_currentIndex >= 0 && _currentIndex < _queue.length) {
        PlaybackDiagnostics().recordConfirmedPlaying(_queue[_currentIndex].id);
      }
    }

    // Buffering watchdog management:
    // If player starts buffering while not explicitly paused and not recovering, schedule 12s stall watchdog.
    // If buffering resolves or transitions to another state, cancel watchdog immediately.
    if (playerState.processingState == ProcessingState.buffering) {
      if (!_userExplicitlyPaused && !_isLoadingTrack && !_isRecovering) {
        _startBufferingWatchdog();
      }
    } else {
      _cancelBufferingWatchdog();
    }
  }

  void _onPositionChanged(Duration position) {
    if (_isLoadingTrack ||
        _isRecovering ||
        _player.processingState == ProcessingState.completed) {
      return;
    }
    if (position > Duration.zero) {
      _lastValidPosition = position;
    }
    final now = DateTime.now();
    if (now.difference(_lastDiagHeartbeat) >= const Duration(seconds: 10)) {
      _lastDiagHeartbeat = now;
      _logDiagnosticTransition(
        'POSITION_HEARTBEAT',
        extra: 'streamPosMs=${position.inMilliseconds}',
      );
    }
    _pushPlaybackState();
  }

  void _syncRollingPreload() {
    if (_queue.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= _queue.length) {
      _preloader.markPlayingTrack(null);
    } else {
      _preloader.markPlayingTrack(_queue[_currentIndex]);
    }
    unawaited(
      _preloader.syncWindow(
        queue: _queue,
        currentIndex: _currentIndex,
        loopMode: _player.loopMode,
      ),
    );
  }

  void _onDurationChanged(Duration? duration) {
    if (duration != null) {
      _logDiagnosticTransition(
        'DURATION_CHANGED',
        extra: 'newDurationMs=${duration.inMilliseconds}',
      );
    }
    final current = mediaItem.value;
    if (current != null && duration != null) {
      debugPrint('[Playback] Duration resolved: ${duration.inSeconds}s');
      mediaItem.add(current.copyWith(duration: duration));
    }
  }

  void _pushPlaybackState({PlayerState? playerState}) {
    final ps =
        playerState ?? PlayerState(_player.playing, _player.processingState);
    final isPlaying = ps.playing;
    final processingState = ps.processingState;

    AudioProcessingState audioProcessingState;
    switch (processingState) {
      case ProcessingState.idle:
        audioProcessingState = AudioProcessingState.idle;
        break;
      case ProcessingState.loading:
        audioProcessingState = AudioProcessingState.loading;
        break;
      case ProcessingState.buffering:
        audioProcessingState = AudioProcessingState.buffering;
        break;
      case ProcessingState.ready:
        audioProcessingState = AudioProcessingState.ready;
        break;
      case ProcessingState.completed:
        audioProcessingState = AudioProcessingState.completed;
        break;
    }

    final isShuffle = _player.shuffleModeEnabled;
    AudioServiceRepeatMode repeatMode;
    switch (_player.loopMode) {
      case LoopMode.one:
        repeatMode = AudioServiceRepeatMode.one;
        break;
      case LoopMode.all:
        repeatMode = AudioServiceRepeatMode.all;
        break;
      case LoopMode.off:
        repeatMode = AudioServiceRepeatMode.none;
        break;
    }
    final shuffleMode = isShuffle
        ? AudioServiceShuffleMode.all
        : AudioServiceShuffleMode.none;

    final controls = [
      MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      MediaControl(
        androidIcon: 'drawable/ic_widget_shuffle',
        label: isShuffle ? 'Shuffle On' : 'Shuffle Off',
        action: MediaAction.custom,
        customAction: const CustomMediaAction(name: 'toggleShuffle'),
      ),
      MediaControl(
        androidIcon: 'drawable/ic_widget_repeat',
        label: repeatMode == AudioServiceRepeatMode.one
            ? 'Repeat One'
            : (repeatMode == AudioServiceRepeatMode.all ? 'Repeat All' : 'Repeat Off'),
        action: MediaAction.custom,
        customAction: const CustomMediaAction(name: 'cycleRepeat'),
      ),
    ];

    const systemActions = {
      MediaAction.seek,
      MediaAction.seekForward,
      MediaAction.seekBackward,
      MediaAction.setRepeatMode,
      MediaAction.setShuffleMode,
      MediaAction.play,
      MediaAction.pause,
      MediaAction.skipToNext,
      MediaAction.skipToPrevious,
      MediaAction.stop,
    };

    playbackState.add(
      PlaybackState(
        controls: controls,
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: systemActions,
        processingState: audioProcessingState,
        playing: isPlaying,
        updatePosition: _player.position > Duration.zero
            ? _player.position
            : (_lastValidPosition > Duration.zero ? _lastValidPosition : Duration.zero),
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex,
        repeatMode: repeatMode,
        shuffleMode: shuffleMode,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------

  Future<void> loadQueue(
    List<MusicItem> tracks, {
    int startIndex = 0,
    Duration? initialPosition,
  }) async {
    _playInterrupted = false;
    _queue.clear();
    _queue.addAll(tracks);
    _currentIndex = startIndex.clamp(0, tracks.length - 1);
    queue.add(_queue.map(_trackToMediaItem).toList());
    debugPrint('[Queue] Loaded ${tracks.length} tracks, starting at index $_currentIndex (initialPos=${initialPosition?.inSeconds}s)');
    await _loadCurrentTrack(initialPosition: initialPosition, reason: 'loadQueue');
  }

  Future<void> appendTrack(MusicItem track) async {
    _queue.add(track);
    queue.add(_queue.map(_trackToMediaItem).toList());
    debugPrint('[Queue] Appended track "${track.title}" (queue size: ${_queue.length})');
    _syncRollingPreload();
  }

  Future<void> appendTracks(List<MusicItem> tracks) async {
    if (tracks.isEmpty) return;
    _queue.addAll(tracks);
    queue.add(_queue.map(_trackToMediaItem).toList());
    debugPrint('[Queue] Appended ${tracks.length} tracks (queue size: ${_queue.length})');
    _syncRollingPreload();
  }

  Future<void> removeTrackAt(int index) async {
    if (index >= 0 && index < _queue.length) {
      _queue.removeAt(index);
      if (_currentIndex >= _queue.length) {
        _currentIndex = _queue.length - 1;
      }
      queue.add(_queue.map(_trackToMediaItem).toList());
      debugPrint('[Queue] Removed track at index $index (queue size: ${_queue.length})');
      _syncRollingPreload();
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _queue.length ||
        newIndex < 0 ||
        newIndex > _queue.length) {
      return;
    }

    final playingTrack = _queue[_currentIndex];

    final item = _queue.removeAt(oldIndex);
    final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
    _queue.insert(insertAt.clamp(0, _queue.length), item);

    _currentIndex = _queue.indexOf(playingTrack);
    queue.add(_queue.map(_trackToMediaItem).toList());
    debugPrint('[Queue] Reordered: $oldIndex → $insertAt, now playing index $_currentIndex');
    _syncRollingPreload();
  }

  /// Synchronizes the handler's queue order (e.g. after shuffle/unshuffle or queue clear)
  /// without interrupting or reloading the currently playing track.
  Future<void> syncQueueOrder(List<MusicItem> tracks, int currentIndex) async {
    _queue.clear();
    _queue.addAll(tracks);
    if (_queue.isEmpty) {
      _currentIndex = -1;
    } else {
      _currentIndex = currentIndex.clamp(0, _queue.length - 1);
    }
    queue.add(_queue.map(_trackToMediaItem).toList());
    debugPrint('[Queue] Synced queue order (${_queue.length} tracks, index=$_currentIndex)');
    _syncRollingPreload();
  }

  // ---------------------------------------------------------------------------
  // Core track loading
  // ---------------------------------------------------------------------------

  Future<bool> _loadCurrentTrack({
    Duration? initialPosition,
    String reason = 'unspecified',
  }) async {
    _cancelBufferingWatchdog();
    if (_queue.isEmpty || _currentIndex < 0) return false;

    final token = ++_activeLoadToken;
    _lastHandledCompletionToken = -1;
    final track = _queue[_currentIndex];
    _preloader.markPlayingTrack(track);
    _logDiagnosticTransition(
      'LOAD_CURRENT_TRACK',
      extra: 'reason=$reason,trackId=${track.id},index=$_currentIndex,initialPosMs=${initialPosition?.inMilliseconds}',
    );
    debugPrint('[Playback] Loading track: "${track.title}" by "${track.artist}" (id=${track.id}, token=$token, reason=$reason, initialPos=${initialPosition?.inSeconds}s)');

    // 1. Clear stale pause intent for the newly requested track load, fade out prior audio,
    // and invalidate loaded track identity so the previous track transitions cleanly.
    _userExplicitlyPaused = false;
    final wasPlaying = _player.playing || playbackState.value.playing;
    _isLoadingTrack = true;
    try {
      _lastTrackId = track.id;
      _loadedAudioTrackId = null;

      if (initialPosition != null && initialPosition > Duration.zero) {
        _lastValidPosition = initialPosition;
      } else {
        _lastValidPosition = Duration.zero;
      }

      try {
        if (kIsWeb) {
          // On Web, immediately stop the previous HTML5 AudioElement to prevent background bleeding
          await _player.stop();
        } else if (_player.playing &&
            _player.processingState != ProcessingState.completed) {
          await fadeOutAndPause(duration: const Duration(milliseconds: 120));
        }
        // Note: On native Android, do NOT call _player.stop() here. Calling stop unloads ExoPlayer and
        // signals the Android OS that media playback is inactive, which drops media wake locks
        // and causes Android to suspend YouTube network resolution when the screen is turned off.
      } catch (_) {}

      if (token != _activeLoadToken) {
        debugPrint('[Playback] Load superseded before source resolution (token $token vs $_activeLoadToken)');
        return false;
      }

      // 2. Push buffering state for OS, lock screen, and UI.
      // Retain playing: wasPlaying so audio_service retains Android media playback wake locks while screen is off.
      _pushPlaybackState(playerState: PlayerState(wasPlaying, ProcessingState.buffering));

      try {
        final startPos = _lastValidPosition > Duration.zero ? _lastValidPosition : null;
        if (track.isYoutube) {
          await _loadYouTubeTrack(track, token, initialPosition: startPos);
        } else {
          await _loadLocalTrack(track, token, initialPosition: startPos);
        }

        if (token != _activeLoadToken) {
          debugPrint('[Playback] Load completed but superseded (token $token vs $_activeLoadToken)');
          return false;
        }

        // Restore position if specified and not already prepared at startPos
        if (_lastValidPosition > Duration.zero && (_player.position - _lastValidPosition).abs() > const Duration(seconds: 1)) {
          debugPrint('[Playback] Restoring position to ${_lastValidPosition.inSeconds}s for "${track.title}"');
          await _player.seek(_lastValidPosition);
        }

        if (token != _activeLoadToken) {
          debugPrint('[Playback] Load superseded after position seek (token $token vs $_activeLoadToken)');
          return false;
        }

        _loadedAudioTrackId = track.id;
        _isLoadingTrack = false;

        // 3. ONLY commit mediaItem after audio source has been prepared and verified successfully!
        mediaItem.add(_trackToMediaItem(track));
        _syncRollingPreload();
        return true;
      } catch (e, stack) {
        if (token != _activeLoadToken) {
          debugPrint('[Playback] Ignoring error for superseded track (token $token vs $_activeLoadToken)');
          return false;
        }
        _isLoadingTrack = false;
        debugPrint('[Playback] _loadCurrentTrack failed for "${track.title}": $e');
        if (kDebugMode) debugPrintStack(stackTrace: stack);
        _loadedAudioTrackId = null;
        try {
          await _player.stop();
        } catch (_) {}
        playbackState.add(
          playbackState.value.copyWith(processingState: AudioProcessingState.error),
        );
        _errorController.add(e.toString().replaceFirst('Exception: ', ''));
        rethrow;
      }
    } finally {
      if (token == _activeLoadToken) {
        _isLoadingTrack = false;
      }
    }
  }

  /// Loads a YouTube track with bounded retry (up to [_kMaxYouTubeRetries] fresh resolutions).
  Future<void> _loadYouTubeTrack(MusicItem track, int token, {Duration? initialPosition}) async {
    // 0. Consume a preloaded cached file or prepared stream URL if valid.
    final prepared = await _preloader.getPreparedEntry(track);
    if (token != _activeLoadToken) return;
    if (prepared != null) {
      if (!kIsWeb &&
          prepared.state == PreloadState.fullyCached &&
          prepared.cachedFilePath != null) {
        debugPrint('[PreloadDiag] Consuming fullyCached file for "${track.title}"');
        PlaybackDiagnostics().recordPlayerLoadStart(track.id);
        try {
          _currentSourceSummary = _sanitizeSourceDescriptor(
            prepared.cachedFilePath!,
            track: track,
          );
          _logDiagnosticTransition(
            'SOURCE_SET_PRELOAD_FILE',
            extra: 'fromPreloadCache=true,preloadState=fullyCached,initialPosMs=${initialPosition?.inMilliseconds}',
          );
          await _player.setAudioSource(
            AudioSource.file(prepared.cachedFilePath!),
            initialPosition: initialPosition,
          );
          if (token != _activeLoadToken) {
            try {
              await _player.stop();
            } catch (_) {}
            return;
          }
          _loadedAudioTrackId = track.id;
          PlaybackDiagnostics().recordPlayerLoadEnd(track.id, success: true);
          return;
        } catch (e) {
          debugPrint('[PreloadDiag] Prepared file load failed, falling back to stream: $e');
          await _preloader.invalidateTrack(
            track.id,
            isYoutube: true,
            deleteCachedFile: true,
          );
        }
      } else if (prepared.state == PreloadState.streamReady &&
          prepared.streamUrl != null &&
          prepared.streamUrl!.isNotEmpty) {
        debugPrint('[PreloadDiag] Consuming streamReady URL for "${track.title}" (client=${prepared.clientName})');
        _logDiagnosticTransition(
          'PRELOAD_STREAM_CONSUMED',
          extra: 'fromPreloadCache=true,preloadState=streamReady,trackId=${track.id}',
        );
        PlaybackDiagnostics().recordPlayerLoadStart(track.id);
        try {
          await _setAudioSourceUrl(
            prepared.streamUrl!,
            userAgent: prepared.userAgent ??
                YouTubeAudioService.inferUserAgentForUrl(prepared.streamUrl!),
            clientName: prepared.clientName ?? 'PRELOAD',
            initialPosition: initialPosition,
          );
          if (token != _activeLoadToken) {
            try {
              await _player.stop();
            } catch (_) {}
            return;
          }
          _loadedAudioTrackId = track.id;
          PlaybackDiagnostics().recordPlayerLoadEnd(track.id, success: true);
          return;
        } catch (e) {
          debugPrint('[PreloadDiag] Prepared streamReady URL failed ($e); refreshing');
          await _preloader.invalidateTrack(track.id, isYoutube: true);
        }
      }
    }

    // 1. If track already has a direct playable full audio stream URL, load immediately.
    // Do NOT bypass full stream resolution for iTunes preview URLs or generic preview clips.
    final isPreviewUrl = track.filePath.contains('itunes.apple.com') ||
        track.filePath.contains('/AudioPreview') ||
        track.filePath.contains('preview');

    if (track.filePath.isNotEmpty &&
        track.filePath.startsWith('http') &&
        !track.filePath.contains('youtube.com/watch') &&
        !track.filePath.contains('youtu.be') &&
        !isPreviewUrl) {
      debugPrint('[AudioHandler] Playing direct audio stream URL for "${track.title}"');
      if (token != _activeLoadToken) return;
      PlaybackDiagnostics().recordPlayerLoadStart(track.id);
      try {
        await _setAudioSourceUrl(
          track.filePath,
          userAgent: YouTubeAudioService.inferUserAgentForUrl(track.filePath),
          initialPosition: initialPosition,
        );
        if (token != _activeLoadToken) {
          try {
            await _player.stop();
          } catch (_) {}
          return;
        }
        _loadedAudioTrackId = track.id;
        PlaybackDiagnostics().recordPlayerLoadEnd(track.id, success: true);
        debugPrint('[Playback] Direct stream loaded successfully for "${track.title}"');
        return;
      } catch (e) {
        debugPrint('[Playback] Direct stream load error: $e, falling back to stream resolution');
      }
    }

    var videoId = _extractYouTubeVideoId(track.id);
    // If ID is from discovery metadata catalog (e.g. wm_1440818780), resolve real YouTube video ID for "$title $artist"
    if (videoId.startsWith('wm_') || videoId.length != 11 || !RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(videoId)) {
      final query = '${track.title} ${track.artist}'.trim();
      debugPrint('[AudioHandler] Resolving YouTube video ID for metadata track "$query"');
      final resolvedId = await YouTubeAudioService().resolveVideoIdForQuery(query);
      if (resolvedId != null && resolvedId.isNotEmpty && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(resolvedId)) {
        videoId = resolvedId;
      } else {
        debugPrint('[AudioHandler] Pre-search failed to find verified music video for "$query"');
        throw Exception('No verified music stream available for "$query"');
      }
    }

    debugPrint('[AudioHandler] Loading YouTube track: videoId=$videoId ("${track.title}", token=$token)');

    PlaybackDiagnostics().recordStreamResolutionStart(track.id);
    ResolvedYouTubeStream? resolved = await YouTubeAudioService().getAudioStream(
      videoId,
      title: track.title,
      artist: track.artist,
    );

    if (token != _activeLoadToken) {
      debugPrint('[AudioHandler] Discarding stale YouTube resolution for $videoId ($token vs $_activeLoadToken)');
      return;
    }

    if (resolved == null ||
        resolved.url.isEmpty ||
        !YouTubeAudioService().isUrlValid(resolved.url)) {
      debugPrint('[AudioHandler] Initial resolution failed for $videoId, retrying fresh (attempt 2/2)');
      resolved = await YouTubeAudioService().getAudioStream(
        videoId,
        forceRefresh: true,
        title: track.title,
        artist: track.artist,
      );
      if (token != _activeLoadToken) return;
    }

    // Web fallback: resolve full stream via WebMusicDiscoverySource
    if ((resolved == null ||
            resolved.url.isEmpty ||
            !YouTubeAudioService().isUrlValid(resolved.url)) &&
        kIsWeb) {
      debugPrint('[AudioHandler] Falling back to WebMusicDiscoverySource for "${track.title}"');
      final webUrl = await WebMusicDiscoverySource().resolveStreamForTrack(track.title, track.artist);
      if (token != _activeLoadToken) return;
      if (webUrl != null && webUrl.isNotEmpty) {
        resolved = ResolvedYouTubeStream(
          url: webUrl,
          userAgent: YouTubeAudioService.inferUserAgentForUrl(webUrl),
          clientName: 'WEB_DISCOVERY',
        );
      }
    }

    // Fallback: If direct stream resolution for this videoId failed (e.g. video deleted, cipher error, or geo-restricted),
    // attempt verified search fallback using track title and artist to locate an authentic alternate recording.
    if ((resolved == null ||
            resolved.url.isEmpty ||
            !YouTubeAudioService().isUrlValid(resolved.url)) &&
        track.title.isNotEmpty) {
      final query = '${track.title} ${track.artist}'.trim();
      debugPrint('[AudioHandler] Direct resolution for $videoId failed. Attempting verified search fallback for "$query"');
      final fallbackId = await YouTubeAudioService().resolveVideoIdForQuery(query);
      if (fallbackId != null && fallbackId.isNotEmpty && fallbackId != videoId) {
        debugPrint('[AudioHandler] Resolved alternate verified video ID $fallbackId for "${track.title}"');
        videoId = fallbackId;
        resolved = await YouTubeAudioService().getAudioStream(
          fallbackId,
          forceRefresh: true,
          title: track.title,
          artist: track.artist,
        );
      }
      if (token != _activeLoadToken) return;
    }
    if (resolved == null ||
        resolved.url.isEmpty ||
        !YouTubeAudioService().isUrlValid(resolved.url)) {
      PlaybackDiagnostics().recordError(track.id, 'Unable to resolve audio stream');
      throw Exception('Unable to resolve audio stream for "${track.title}". Please try again.');
    }

    if (token != _activeLoadToken) return;

    PlaybackDiagnostics().recordPlayerLoadStart(track.id);
    try {
      await _setAudioSourceUrl(
        resolved.url,
        userAgent: resolved.userAgent,
        clientName: resolved.clientName,
        initialPosition: initialPosition,
      );
      if (token != _activeLoadToken) {
        debugPrint('[AudioHandler] Discarding stale player load for $videoId ($token vs $_activeLoadToken)');
        try {
          await _player.stop();
        } catch (_) {}
        return;
      }
      _loadedAudioTrackId = track.id;
      PlaybackDiagnostics().recordPlayerLoadEnd(track.id, success: true);
      debugPrint('[Playback] YouTube audio source loaded successfully for $videoId');
    } on PlayerException catch (pe) {
      if (token != _activeLoadToken) return;
      debugPrint('[Playback] PlayerException on first load (code=${pe.code}): ${pe.message}');
      debugPrint('[StreamCache] Invalidating and re-resolving for $videoId (retry 1/$_kMaxYouTubeRetries)');
      YouTubeAudioService().invalidateCache(videoId);

      final fresh = await YouTubeAudioService()
          .getAudioStream(videoId, forceRefresh: true);
      if (token != _activeLoadToken) return;

      if (fresh != null &&
          fresh.url.isNotEmpty &&
          YouTubeAudioService().isUrlValid(fresh.url)) {
        await _setAudioSourceUrl(
          fresh.url,
          userAgent: fresh.userAgent,
          clientName: fresh.clientName,
          initialPosition: initialPosition,
        );
        if (token != _activeLoadToken) {
          try {
            await _player.stop();
          } catch (_) {}
          return;
        }
        _loadedAudioTrackId = track.id;
        PlaybackDiagnostics().recordPlayerLoadEnd(track.id, success: true);
        debugPrint('[Playback] YouTube audio source loaded on retry for $videoId');
      } else {
        _loadedAudioTrackId = null;
        PlaybackDiagnostics().recordError(track.id, pe.message ?? 'PlayerException');
        throw Exception(
          'Playback failed for "${track.title}": ${pe.message ?? "network stream error"} (code ${pe.code})',
        );
      }
    } catch (e) {
      if (token != _activeLoadToken) return;
      _loadedAudioTrackId = null;
      PlaybackDiagnostics().recordPlayerLoadEnd(track.id, success: false);
      rethrow;
    }
  }

  /// Loads a local or remote non-YouTube source.
  Future<void> _loadLocalTrack(MusicItem track, int token, {Duration? initialPosition}) async {
    PlaybackDiagnostics().recordPlayerLoadStart(track.id);
    final path = track.filePath;

    // Reject 30-second preview URLs and web discovery IDs from playing local snippets
    final isPreviewUrl = path.contains('itunes.apple.com') ||
        path.contains('/AudioPreview') ||
        path.contains('preview');
    if (isPreviewUrl || track.id.startsWith('wm_')) {
      debugPrint('[Playback] Track "${track.title}" is an online discovery track — routing to _loadYouTubeTrack for full stream');
      await _loadYouTubeTrack(track, token, initialPosition: initialPosition);
      return;
    }

    try {
      if (!kIsWeb && path.isNotEmpty && !path.startsWith('http')) {
        debugPrint('[Playback] Loading local file: $path (token=$token)');
        if (token != _activeLoadToken) return;
        _currentSourceSummary = _sanitizeSourceDescriptor(path, track: track);
        _logDiagnosticTransition('SOURCE_SET_LOCAL', extra: 'initialPosMs=${initialPosition?.inMilliseconds}');
        await _player.setAudioSource(AudioSource.file(path), initialPosition: initialPosition);
        if (token != _activeLoadToken) {
          try {
            await _player.stop();
          } catch (_) {}
          return;
        }
        _loadedAudioTrackId = track.id;
        PlaybackDiagnostics().recordPlayerLoadEnd(track.id, success: true);
        debugPrint('[Playback] Local file loaded successfully');
      } else if (path.isNotEmpty && path.startsWith('http')) {
        if (!kIsWeb) {
          final prepared = await _preloader.getPreparedEntry(track);
          if (token != _activeLoadToken) return;
          if (prepared != null &&
              prepared.state == PreloadState.fullyCached &&
              prepared.cachedFilePath != null) {
            debugPrint('[PreloadDiag] Consuming cached remote file for "${track.title}"');
            try {
              _currentSourceSummary = _sanitizeSourceDescriptor(
                prepared.cachedFilePath!,
                track: track,
              );
              _logDiagnosticTransition(
                'SOURCE_SET_PRELOAD_FILE',
                extra: 'fromPreloadCache=true,preloadState=fullyCached,initialPosMs=${initialPosition?.inMilliseconds}',
              );
              await _player.setAudioSource(
                AudioSource.file(prepared.cachedFilePath!),
                initialPosition: initialPosition,
              );
              if (token != _activeLoadToken) {
                try {
                  await _player.stop();
                } catch (_) {}
                return;
              }
              _loadedAudioTrackId = track.id;
              PlaybackDiagnostics().recordPlayerLoadEnd(track.id, success: true);
              return;
            } catch (e) {
              debugPrint('[PreloadDiag] Cached remote file failed ($e); falling back to URL');
              await _preloader.invalidateTrack(
                track.id,
                deleteCachedFile: true,
              );
            }
          }
        }
        debugPrint('[Playback] Loading remote URL: $path (token=$token)');
        if (token != _activeLoadToken) return;
        _currentSourceSummary = _sanitizeSourceDescriptor(path, track: track);
        _logDiagnosticTransition('SOURCE_SET_REMOTE_URL', extra: 'initialPosMs=${initialPosition?.inMilliseconds}');
        await _player.setUrl(path, initialPosition: initialPosition);
        if (token != _activeLoadToken) {
          try {
            await _player.stop();
          } catch (_) {}
          return;
        }
        _loadedAudioTrackId = track.id;
        PlaybackDiagnostics().recordPlayerLoadEnd(track.id, success: true);
        debugPrint('[Playback] Remote URL loaded successfully');
      } else {
        _loadedAudioTrackId = null;
        PlaybackDiagnostics().recordError(track.id, 'No valid file path or source');
        throw Exception('Track "${track.title}" has no valid file path or source');
      }
    } catch (e) {
      if (token != _activeLoadToken) return;
      _loadedAudioTrackId = null;
      PlaybackDiagnostics().recordPlayerLoadEnd(track.id, success: false);
      rethrow;
    }
  }

  bool _crossfadeEnabled = false;

  void setCrossfade(bool enabled) {
    _crossfadeEnabled = enabled;
  }

  /// Sets the audio source from a URL with the required headers and optional initial position.
  Future<void> _setAudioSourceUrl(
    String url, {
    String userAgent = kYouTubeVisionOsUserAgent,
    String clientName = 'VISIONOS',
    Duration? initialPosition,
  }) async {
    final currentTrack = (_currentIndex >= 0 && _currentIndex < _queue.length)
        ? _queue[_currentIndex]
        : null;
    _currentSourceSummary = _sanitizeSourceDescriptor(url, track: currentTrack);
    _logDiagnosticTransition(
      'SOURCE_SET_YOUTUBE_URL',
      extra: 'initialPosMs=${initialPosition?.inMilliseconds},client=$clientName',
    );
    if (_crossfadeEnabled && _player.playing) {
      for (double v = 1.0; v >= 0.1; v -= 0.3) {
        await _player.setVolume(v.clamp(0.0, 1.0));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    }

    await _player.setAudioSource(
      AudioSource.uri(
        Uri.parse(url),
        headers: kIsWeb
            ? null
            : {
                'User-Agent': userAgent,
              },
      ),
      initialPosition: initialPosition,
    );

    if (_crossfadeEnabled) {
      await _player.setVolume(0.1);
      for (double v = 0.2; v <= 1.0; v += 0.2) {
        await _player.setVolume(v.clamp(0.0, 1.0));
        await Future<void>.delayed(const Duration(milliseconds: 35));
      }
    } else {
      await _player.setVolume(1.0);
    }
  }

  /// Recovery path called when a playback event stream error occurs mid-playback
  /// or when the 12-second buffering watchdog detects a silent connection stall.
  Future<void> _recoverYouTubePlayback({
    required String videoId,
    required MusicItem track,
    required int retryCount,
    required bool resumePlayback,
    bool ownsRecoveryLock = false,
  }) async {
    if (retryCount == 0 && !ownsRecoveryLock) {
      if (_isRecovering) {
        debugPrint('[Playback] Recovery already in progress for $videoId — ignoring duplicate request');
        return;
      }
      _isRecovering = true;
    }

    try {
      await _executeYouTubeRecovery(
        videoId: videoId,
        track: track,
        retryCount: retryCount,
        resumePlayback: resumePlayback,
      );
    } finally {
      if (retryCount == 0 && !ownsRecoveryLock) {
        _isRecovering = false;
      }
    }
  }

  Future<void> _executeYouTubeRecovery({
    required String videoId,
    required MusicItem track,
    required int retryCount,
    required bool resumePlayback,
  }) async {
    _cancelBufferingWatchdog();
    final token = _activeLoadToken;
    if (retryCount >= _kMaxYouTubeRetries) {
      debugPrint(
        '[Playback] Recovery failed after $retryCount retries for $videoId — non-recoverable',
      );
      _loadedAudioTrackId = null;
      if (token == _activeLoadToken) {
        _isLoadingTrack = false;
      }
      _errorController.add(
        'Playback failed for "${track.title}" after $_kMaxYouTubeRetries retries.',
      );
      playbackState.add(
        playbackState.value.copyWith(processingState: AudioProcessingState.error),
      );
      return;
    }

    if (_currentIndex < 0 || _currentIndex >= _queue.length) {
      if (token == _activeLoadToken) _isLoadingTrack = false;
      return;
    }
    if (_extractYouTubeVideoId(_queue[_currentIndex].id) != videoId) {
      if (token == _activeLoadToken) _isLoadingTrack = false;
      debugPrint('[Playback] Aborting recovery: track changed ($videoId vs ${_queue[_currentIndex].id})');
      return;
    }

    debugPrint(
      '[Playback] Recovery attempt ${retryCount + 1}/$_kMaxYouTubeRetries for $videoId (resume=$resumePlayback)',
    );

    final savedPosition = _player.position > Duration.zero
        ? _player.position
        : (_lastValidPosition > Duration.zero ? _lastValidPosition : Duration.zero);

    try {
      _isLoadingTrack = true;
      _pushPlaybackState(playerState: PlayerState(resumePlayback, ProcessingState.buffering));
      final fresh = await YouTubeAudioService()
          .getAudioStream(videoId, forceRefresh: true);

      if (token != _activeLoadToken) {
        debugPrint('[Playback] Recovery discarded: superseded by newer track (token $token vs $_activeLoadToken)');
        return;
      }

      if (_currentIndex < 0 ||
          _currentIndex >= _queue.length ||
          _extractYouTubeVideoId(_queue[_currentIndex].id) != videoId) {
        _isLoadingTrack = false;
        return;
      }

      if (fresh == null || fresh.url.isEmpty) {
        _isLoadingTrack = false;
        debugPrint('[YouTubeResolver] Fresh URL still null on retry ${retryCount + 1}');
        await _executeYouTubeRecovery(
          videoId: videoId,
          track: track,
          retryCount: retryCount + 1,
          resumePlayback: resumePlayback,
        );
        return;
      }

      await _setAudioSourceUrl(
        fresh.url,
        userAgent: fresh.userAgent,
        clientName: fresh.clientName,
        initialPosition: savedPosition,
      );
      if (token != _activeLoadToken) {
        return;
      }

      _loadedAudioTrackId = track.id;

      if (savedPosition > Duration.zero) {
        _lastValidPosition = savedPosition;
      }
      _isLoadingTrack = false;
      debugPrint('[Playback] Recovery succeeded: audio source reloaded for $videoId at ${savedPosition.inSeconds}s');

      if (resumePlayback && !_userExplicitlyPaused) {
        await play();
        debugPrint('[Playback] Playback resumed after recovery for $videoId');
      }
    } catch (e) {
      if (token != _activeLoadToken) return;
      _isLoadingTrack = false;
      debugPrint('[Playback] Recovery error (attempt ${retryCount + 1}) for $videoId: $e');
      await _executeYouTubeRecovery(
        videoId: videoId,
        track: track,
        retryCount: retryCount + 1,
        resumePlayback: resumePlayback,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Buffering Watchdog (Stall Detection & Recovery)
  // ---------------------------------------------------------------------------

  void _startBufferingWatchdog() {
    if (_bufferingWatchdogTimer != null && _bufferingWatchdogTimer!.isActive) {
      return;
    }
    _cancelBufferingWatchdog();
    if (_userExplicitlyPaused || _isLoadingTrack || _isRecovering) return;
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;

    final currentTrack = _queue[_currentIndex];
    if (!currentTrack.isYoutube) return;

    _bufferingTrackId = currentTrack.id;
    _bufferingStartToken = _activeLoadToken;
    _bufferingStartPosition = _player.position > Duration.zero
        ? _player.position
        : (_lastValidPosition > Duration.zero ? _lastValidPosition : Duration.zero);

    debugPrint(
      '[PlaybackWatchdog] Buffering stall watchdog scheduled for "${currentTrack.title}" '
      '(timeout: ${_kBufferingWatchdogTimeout.inSeconds}s, at ${_bufferingStartPosition?.inSeconds}s)',
    );

    _bufferingWatchdogTimer = Timer(_kBufferingWatchdogTimeout, () async {
      await _onBufferingWatchdogFired();
    });
  }

  void _cancelBufferingWatchdog() {
    if (_bufferingWatchdogTimer != null) {
      _bufferingWatchdogTimer?.cancel();
      _bufferingWatchdogTimer = null;
      debugPrint('[PlaybackWatchdog] Buffering watchdog cancelled');
    }
    _bufferingStartPosition = null;
    _bufferingTrackId = null;
    _bufferingStartToken = null;
  }

  Future<void> _onBufferingWatchdogFired() async {
    _bufferingWatchdogTimer = null;

    if (_userExplicitlyPaused) {
      debugPrint('[PlaybackWatchdog] Stalled buffering ignored: user explicitly paused');
      return;
    }

    if (_isRecovering || _isLoadingTrack) {
      debugPrint('[PlaybackWatchdog] Stalled buffering ignored: recovery or track load already in progress');
      return;
    }

    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    final currentTrack = _queue[_currentIndex];
    if (_bufferingTrackId != currentTrack.id || _bufferingStartToken != _activeLoadToken) {
      debugPrint('[PlaybackWatchdog] Stalled buffering ignored: track changed since buffering started');
      return;
    }

    final isStillBuffering = _player.processingState == ProcessingState.buffering ||
        playbackState.value.processingState == AudioProcessingState.buffering;
    if (!isStillBuffering) {
      debugPrint('[PlaybackWatchdog] Stalled buffering ignored: player is no longer buffering');
      return;
    }

    final currentPos = _player.position;
    if (_bufferingStartPosition != null &&
        (currentPos - _bufferingStartPosition!).abs() > const Duration(seconds: 1)) {
      debugPrint('[PlaybackWatchdog] Stalled buffering ignored: position progressed while buffering');
      return;
    }

    if (currentTrack.isYoutube) {
      final videoId = _extractYouTubeVideoId(currentTrack.id);
      debugPrint(
        '[PlaybackWatchdog] Buffering stall detected (>12s) on "$videoId" at '
        '${_bufferingStartPosition?.inSeconds}s — initiating automatic stream recovery',
      );
      YouTubeAudioService().invalidateCache(videoId);
      await _recoverYouTubePlayback(
        videoId: videoId,
        track: currentTrack,
        retryCount: 0,
        resumePlayback: true,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _extractYouTubeVideoId(String trackId) {
    var id = trackId.trim();
    if (id.startsWith('youtube_')) {
      id = id.substring('youtube_'.length);
    }
    if (id.contains('watch?v=')) {
      id = Uri.tryParse(id)?.queryParameters['v'] ?? id;
    } else if (id.contains('youtu.be/')) {
      final segs = Uri.tryParse(id)?.pathSegments ?? [];
      if (segs.isNotEmpty) id = segs.last;
    }
    return id;
  }

  MediaItem _trackToMediaItem(MusicItem track) {
    Uri? artUri;
    String rawImg = track.imageUrl.trim();
    if (rawImg.isEmpty && track.isYoutube) {
      final vid = _extractYouTubeVideoId(track.id);
      if (vid.isNotEmpty && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(vid)) {
        rawImg = 'https://i.ytimg.com/vi/$vid/hqdefault.jpg';
      }
    }
    if (rawImg.isNotEmpty) {
      if (rawImg.startsWith('http://') || rawImg.startsWith('https://')) {
        artUri = Uri.parse(rawImg);
      } else {
        artUri = Uri.file(rawImg);
      }
    }
    Duration? parsedDuration;
    if (track.duration.isNotEmpty) {
      final parts = track.duration.split(':');
      if (parts.length == 2) {
        final m = int.tryParse(parts[0]) ?? 0;
        final s = int.tryParse(parts[1]) ?? 0;
        parsedDuration = Duration(minutes: m, seconds: s);
      } else if (parts.length == 3) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final s = int.tryParse(parts[2]) ?? 0;
        parsedDuration = Duration(hours: h, minutes: m, seconds: s);
      }
    }
    String albumTitle = 'Miee Music';
    if (track is Track && track.albumName != null && track.albumName!.isNotEmpty) {
      albumTitle = track.albumName!;
    } else if (track is MediaSong && track.album.isNotEmpty) {
      albumTitle = track.album;
    }

    return MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist,
      album: albumTitle,
      duration: parsedDuration,
      artUri: artUri,
      extras: {'filePath': track.filePath},
    );
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    debugPrint('[AudioHandler] customAction received from system: $name');
    switch (name) {
      case 'toggleShuffle':
        final current = _player.shuffleModeEnabled;
        await setShuffleMode(current ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all);
        break;
      case 'cycleRepeat':
        final current = _player.loopMode;
        AudioServiceRepeatMode nextMode;
        if (current == LoopMode.off) {
          nextMode = AudioServiceRepeatMode.all;
        } else if (current == LoopMode.all) {
          nextMode = AudioServiceRepeatMode.one;
        } else {
          nextMode = AudioServiceRepeatMode.none;
        }
        await setRepeatMode(nextMode);
        break;
      default:
        await super.customAction(name, extras);
    }
  }

  // ---------------------------------------------------------------------------
  // BaseAudioHandler overrides
  // ---------------------------------------------------------------------------

  @override
  Future<void> play() async {
    _playInterrupted = false;
    _userExplicitlyPaused = false;
    if (_currentIndex < 0 || _currentIndex >= _queue.length) {
      debugPrint('[Playback] play() ignored: queue is empty or index invalid');
      return;
    }
    final playToken = _activeLoadToken;
    final current = _queue[_currentIndex];
    if (_loadedAudioTrackId == null || !isSameTrackId(_loadedAudioTrackId, current.id)) {
      debugPrint(
        '[Playback] play() unblocking: active track "${current.title}" (${current.id}) '
        'is not prepared in player (loaded: $_loadedAudioTrackId) — reloading from lastValidPosition: ${_lastValidPosition.inSeconds}s',
      );
      final loaded = await _loadCurrentTrack(
        initialPosition: _lastValidPosition,
        reason: 'play_reload',
      );
      if (!loaded) {
        debugPrint('[Playback] play() aborted: track load failed or superseded');
        return;
      }
      final postLoadToken = _activeLoadToken;
      if (!kIsWeb) {
        try {
          final session = await AudioSession.instance;
          await session.setActive(true);
        } catch (_) {}
      }
      if (postLoadToken != _activeLoadToken) {
        debugPrint('[Playback] play() aborted: superseded during AudioSession activation');
        return;
      }
      await _player.play();
      return;
    }
    try {
      if (!kIsWeb) {
        try {
          final session = await AudioSession.instance;
          await session.setActive(true);
        } catch (_) {}
      }
      if (playToken != _activeLoadToken) {
        debugPrint('[Playback] play() aborted: superseded before start ($playToken vs $_activeLoadToken)');
        return;
      }
      await _player.play();
      debugPrint('[Playback] play() called for ${current.title}');
    } catch (e, stack) {
      debugPrint('[Playback] play() failed: $e');
      if (kDebugMode) debugPrintStack(stackTrace: stack);
      _errorController.add(e.toString().replaceFirst('Exception: ', ''));
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    _logDiagnosticTransition('APP_PAUSE_CALLED', includeStack: true);
    _cancelBufferingWatchdog();
    _playInterrupted = false;
    _userExplicitlyPaused = true;
    if (_player.position > Duration.zero) {
      _lastValidPosition = _player.position;
    }
    await _player.pause();
    debugPrint('[Playback] pause() called (userExplicitlyPaused=true, lastValidPos=${_lastValidPosition.inSeconds}s)');
  }

  @override
  Future<void> stop() async {
    _logDiagnosticTransition('APP_STOP_CALLED', includeStack: true);
    _cancelBufferingWatchdog();
    _playInterrupted = false;
    _userExplicitlyPaused = true;
    _loadedAudioTrackId = null;
    await _player.stop();
    _pushPlaybackState(playerState: PlayerState(false, ProcessingState.idle));
    debugPrint('[Playback] stop() called');
  }

  @override
  Future<void> seek(Duration position) async {
    _cancelBufferingWatchdog();
    _lastValidPosition = position;
    if (position == Duration.zero) {
      _lastHandledCompletionToken = -1;
    }
    await _player.seek(position);
    debugPrint('[Playback] seek(${position.inSeconds}s)');
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  double get volume => _player.volume;

  /// Smoothly fades out active audio over [duration] and pauses the player,
  /// preventing jarring clicks or sudden cuts when switching songs.
  Future<void> fadeOutAndPause({
    Duration duration = const Duration(milliseconds: 180),
  }) async {
    _logDiagnosticTransition('APP_FADEOUT_AND_PAUSE_CALLED', includeStack: true);
    if (!_player.playing) {
      try {
        await _player.pause();
      } catch (_) {}
      return;
    }

    try {
      final initialVolume = _player.volume;
      if (initialVolume <= 0.05) {
        await _player.pause();
        return;
      }
      const steps = 6;
      final stepDelay = Duration(
        milliseconds: (duration.inMilliseconds / steps).round().clamp(10, 40),
      );
      final stepSize = initialVolume / steps;

      for (int i = 1; i <= steps; i++) {
        final targetVol = (initialVolume - (stepSize * i)).clamp(0.0, 1.0);
        await _player.setVolume(targetVol);
        await Future<void>.delayed(stepDelay);
      }
      await _player.pause();
      // Restore volume so the upcoming track starts at proper level
      await _player.setVolume(initialVolume);
    } catch (_) {
      try {
        await _player.pause();
      } catch (_) {}
    }
  }

  Future<void> _loadAndPlayCurrentTrack(String callerLabel) async {
    try {
      final loaded = await _loadCurrentTrack(reason: callerLabel);
      if (loaded) {
        await play();
      } else {
        debugPrint('[Queue] $callerLabel skipped play(): load was superseded or aborted');
      }
    } catch (e) {
      debugPrint('[Queue] $callerLabel failed: $e');
    }
  }

  @override
  Future<void> skipToNext({bool fromCompletion = false}) async {
    if (_isSkippingNext) {
      if (fromCompletion || !_isCompletionSkip) {
        debugPrint('[Queue] skipToNext ignored: already in progress');
        _logDiagnosticTransition('SKIP_TO_NEXT_IGNORED_CONCURRENT');
        return;
      }
      // Manual skip pressed while an automatic completion transition is loading:
      // supersede the in-flight completion load and advance immediately.
      _activeLoadToken++;
      debugPrint('[Queue] Manual skipToNext superseding in-flight completion transition');
    }
    final skipToken = ++_activeSkipToken;
    _isSkippingNext = true;
    _isCompletionSkip = fromCompletion;
    try {
      _playInterrupted = false;
      if (_queue.isEmpty) return;
      if (!fromCompletion &&
          _player.playing &&
          _player.processingState != ProcessingState.completed) {
        await fadeOutAndPause(duration: const Duration(milliseconds: 140));
      }

      // If approaching the end of the queue, notify queue expansion listener in background
      if (!_isRoomListener && _currentIndex >= _queue.length - 3) {
        unawaited(onQueueApproachingEnd?.call());
      }

      final indexBefore = _currentIndex;
      if (_currentIndex < _queue.length - 1) {
        _currentIndex++;
        final nextTrack = _queue[_currentIndex];
        _logDiagnosticTransition(
          'SKIP_TO_NEXT',
          extra: 'fromCompletion=$fromCompletion,indexBefore=$indexBefore,indexAfter=$_currentIndex,nextTrackId=${nextTrack.id}',
        );
        debugPrint('[Queue] skipToNext → index $_currentIndex');
        await _preloader.prioritizeImmediatePlayback(
          () => _loadAndPlayCurrentTrack(fromCompletion ? 'completion_skipToNext' : 'manual_skipToNext'),
        );
      } else if (!_isRoomListener && onQueueApproachingEnd != null) {
        // At the end of queue: await dynamic expansion before giving up
        debugPrint('[Queue] skipToNext: at last track, awaiting dynamic queue replenishment...');
        try {
          await onQueueApproachingEnd!();
        } catch (e) {
          debugPrint('[Queue] onQueueApproachingEnd failed: $e');
        }
        if (_currentIndex < _queue.length - 1) {
          _currentIndex++;
          final nextTrack = _queue[_currentIndex];
          _logDiagnosticTransition(
            'SKIP_TO_NEXT',
            extra: 'fromCompletion=$fromCompletion,indexBefore=$indexBefore,indexAfter=$_currentIndex,nextTrackId=${nextTrack.id},expanded=true',
          );
          debugPrint('[Queue] skipToNext: queue expanded successfully → advancing to index $_currentIndex');
          await _preloader.prioritizeImmediatePlayback(
            () => _loadAndPlayCurrentTrack(fromCompletion ? 'completion_skipToNext_expanded' : 'manual_skipToNext_expanded'),
          );
          return;
        }

        // If repeat all is on, wrap around; otherwise stop
        if (_player.loopMode == LoopMode.all && _queue.isNotEmpty) {
          _currentIndex = 0;
          final nextTrack = _queue[_currentIndex];
          _logDiagnosticTransition(
            'SKIP_TO_NEXT',
            extra: 'fromCompletion=$fromCompletion,indexBefore=$indexBefore,indexAfter=0,nextTrackId=${nextTrack.id},wrap=true',
          );
          debugPrint('[Queue] skipToNext: LoopMode.all wrap-around → index 0');
          await _preloader.prioritizeImmediatePlayback(
            () => _loadAndPlayCurrentTrack(fromCompletion ? 'completion_skipToNext_wrap' : 'manual_skipToNext_wrap'),
          );
        } else {
          _logDiagnosticTransition(
            'SKIP_TO_NEXT_QUEUE_END',
            extra: 'fromCompletion=$fromCompletion,indexBefore=$indexBefore,indexAfter=$_currentIndex,nextTrackId=none',
          );
          debugPrint('[Queue] skipToNext: no further tracks available, stopping');
          _loadedAudioTrackId = null;
          _lastValidPosition = Duration.zero;
          await _player.stop();
        }
      } else if (_player.loopMode == LoopMode.all && _queue.isNotEmpty) {
        _currentIndex = 0;
        final nextTrack = _queue[_currentIndex];
        _logDiagnosticTransition(
          'SKIP_TO_NEXT',
          extra: 'fromCompletion=$fromCompletion,indexBefore=$indexBefore,indexAfter=0,nextTrackId=${nextTrack.id},wrap=true',
        );
        debugPrint('[Queue] skipToNext: LoopMode.all wrap-around → index 0');
        await _preloader.prioritizeImmediatePlayback(
          () => _loadAndPlayCurrentTrack(fromCompletion ? 'completion_skipToNext_wrap' : 'manual_skipToNext_wrap'),
        );
      } else {
        _logDiagnosticTransition(
          'SKIP_TO_NEXT_QUEUE_END',
          extra: 'fromCompletion=$fromCompletion,indexBefore=$indexBefore,indexAfter=$_currentIndex,nextTrackId=none',
        );
        debugPrint('[Queue] skipToNext: already at last track, stopping');
        _loadedAudioTrackId = null;
        _lastValidPosition = Duration.zero;
        await _player.stop();
      }
    } finally {
      if (skipToken == _activeSkipToken) {
        _isSkippingNext = false;
        _isCompletionSkip = false;
      }
    }
  }

  @override
  Future<void> skipToPrevious() async {
    _playInterrupted = false;
    if (_queue.isEmpty) return;
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      debugPrint('[Queue] skipToPrevious: position >3s, seeking to start');
      return;
    }
    if (_currentIndex > 0) {
      if (_player.playing &&
          _player.processingState != ProcessingState.completed) {
        await fadeOutAndPause(duration: const Duration(milliseconds: 140));
      }
      _currentIndex--;
      debugPrint('[Queue] skipToPrevious → index $_currentIndex');
      await _preloader.prioritizeImmediatePlayback(
        () => _loadAndPlayCurrentTrack('skipToPrevious'),
      );
    } else if (_player.loopMode == LoopMode.all && _queue.isNotEmpty) {
      _currentIndex = _queue.length - 1;
      debugPrint('[Queue] skipToPrevious: LoopMode.all wrap-around → index $_currentIndex');
      await _preloader.prioritizeImmediatePlayback(
        () => _loadAndPlayCurrentTrack('skipToPrevious wrap'),
      );
    } else {
      await _player.seek(Duration.zero);
      debugPrint('[Queue] skipToPrevious: already at first track, seeking to start');
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    _playInterrupted = false;
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    debugPrint('[Queue] skipToQueueItem → index $index');
    await _loadAndPlayCurrentTrack('skipToQueueItem');
  }

  @override
  Future<void> fastForward() async {
    final target = _player.position + _kSkipDuration;
    final duration = _player.duration ?? Duration.zero;
    final pos = target < duration ? target : duration;
    _lastValidPosition = pos;
    await _player.seek(pos);
  }

  @override
  Future<void> rewind() async {
    final target = _player.position - _kSkipDuration;
    final pos = target > Duration.zero ? target : Duration.zero;
    _lastValidPosition = pos;
    await _player.seek(pos);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    LoopMode loopMode;
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        loopMode = LoopMode.off;
        break;
      case AudioServiceRepeatMode.one:
        loopMode = LoopMode.one;
        break;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        loopMode = LoopMode.all;
        break;
    }
    await _player.setLoopMode(loopMode);
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
    debugPrint('[Playback] Repeat mode set to $repeatMode');
    _syncRollingPreload();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    await _player.setShuffleModeEnabled(enabled);
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
    debugPrint('[Playback] Shuffle mode set to $shuffleMode');
    _syncRollingPreload();
  }

  // ---------------------------------------------------------------------------
  // Exposed streams and getters (used by PlayerController)
  // ---------------------------------------------------------------------------

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  int get currentIndex => _currentIndex;
  List<MusicItem> get currentQueue => List.unmodifiable(_queue);

  void jumpToIndex(int index) {
    if (index >= 0 && index < _queue.length) {
      _currentIndex = index;
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    _logDiagnosticTransition('ON_TASK_REMOVED_STOP', includeStack: true);
    return stop();
  }

  Future<void> disposeHandler() async {
    _cancelBufferingWatchdog();
    await _preloader.dispose();
    await _playerStateSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _playbackEventSub?.cancel();
    await _playerErrorSub?.cancel();
    await _interruptionSub?.cancel();
    await _becomingNoisySub?.cancel();
    await _errorController.close();
    await _player.dispose();
    debugPrint('[AudioHandler] Disposed');
  }
}
