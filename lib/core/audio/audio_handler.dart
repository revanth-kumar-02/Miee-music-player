import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../../shared/models/music_item.dart';
import 'youtube_audio_service.dart';

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
  final AudioPlayer _player = AudioPlayer();

  /// Current ordered queue of tracks.
  final List<MusicItem> _queue = [];
  int _currentIndex = -1;

  /// Guards against concurrent _loadCurrentTrack calls for the same index.
  bool _isLoading = false;

  /// Controller to stream playback errors to PlayerController.
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  // Stream subscriptions
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlaybackEvent>? _playbackEventSub;

  MieeAudioHandler() {
    _listenToPlayerStreams();
    queue.add([]);
    debugPrint('[AudioHandler] MieeAudioHandler() constructed');
  }

  /// Configures the audio session for music playback and wires up interruptions.
  Future<void> initialize() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          debugPrint('[BackgroundAudio] Audio interruption began — pausing');
          _player.pause();
        } else {
          if (event.type == AudioInterruptionType.pause ||
              event.type == AudioInterruptionType.duck) {
            debugPrint('[BackgroundAudio] Audio interruption ended — resuming');
            _player.play();
          }
        }
      });

      session.becomingNoisyEventStream.listen((_) {
        debugPrint('[BackgroundAudio] Becoming noisy (headset removed) — pausing');
        _player.pause();
      });

      debugPrint('[BackgroundAudio] AudioSession initialized for music playback');
    } catch (e) {
      debugPrint('[AudioHandler] initialize() error: $e');
    }
  }

  void _listenToPlayerStreams() {
    _playerStateSub =
        _player.playerStateStream.listen(_onPlayerStateChanged);
    _positionSub = _player.positionStream.listen(_onPositionChanged);
    _durationSub = _player.durationStream.listen(_onDurationChanged);

    // playbackEventStream carries player errors (source errors, HTTP 403, etc.)
    _playbackEventSub = _player.playbackEventStream.listen(
      (_) {
        // Normal events — state is pushed via _playerStateSub
      },
      onError: (Object e, StackTrace stack) async {
        debugPrint('[Playback] playbackEventStream error: $e');
        if (_isLoading) {
          debugPrint('[Playback] Already loading — skipping event-stream recovery');
          return;
        }
        if (_currentIndex >= 0 && _currentIndex < _queue.length) {
          final current = _queue[_currentIndex];
          if (current.isYoutube) {
            final videoId = _extractYouTubeVideoId(current.id);
            debugPrint('[StreamCache] Invalidating cache for $videoId due to stream error');
            YouTubeAudioService().invalidateCache(videoId);
            await _recoverYouTubePlayback(
              videoId: videoId,
              track: current,
              retryCount: 0,
              resumePlayback: _player.playing,
            );
          } else {
            final msg = e.toString().replaceFirst('Exception: ', '');
            _errorController.add(msg);
          }
        }
      },
    );
  }

  void _onPlayerStateChanged(PlayerState playerState) {
    debugPrint(
      '[Playback] State → playing=${playerState.playing} '
      'processing=${playerState.processingState}',
    );
    _pushPlaybackState(playerState: playerState);

    // Handle track completion — advance to next track.
    // NOTE: PlayerController must NOT also handle completed, as that causes double-skip.
    if (playerState.processingState == ProcessingState.completed) {
      debugPrint('[Queue] Track completed at index $_currentIndex, advancing queue');
      skipToNext();
    }
  }

  void _onPositionChanged(Duration position) {
    _pushPlaybackState();
  }

  void _onDurationChanged(Duration? duration) {
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

    final controls = [
      MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
    ];

    const systemActions = {
      MediaAction.seek,
      MediaAction.seekForward,
      MediaAction.seekBackward,
      MediaAction.setRepeatMode,
      MediaAction.setShuffleMode,
    };

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: systemActions,
        processingState: audioProcessingState,
        playing: isPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------

  Future<void> loadQueue(List<MusicItem> tracks, {int startIndex = 0}) async {
    _queue.clear();
    _queue.addAll(tracks);
    _currentIndex = startIndex.clamp(0, tracks.length - 1);
    queue.add(_queue.map(_trackToMediaItem).toList());
    debugPrint('[Queue] Loaded ${tracks.length} tracks, starting at index $_currentIndex');
    await _loadCurrentTrack();
  }

  Future<void> appendTrack(MusicItem track) async {
    _queue.add(track);
    queue.add(_queue.map(_trackToMediaItem).toList());
    debugPrint('[Queue] Appended track "${track.title}" (queue size: ${_queue.length})');
  }

  Future<void> removeTrackAt(int index) async {
    if (index >= 0 && index < _queue.length) {
      _queue.removeAt(index);
      if (_currentIndex >= _queue.length) {
        _currentIndex = _queue.length - 1;
      }
      queue.add(_queue.map(_trackToMediaItem).toList());
      debugPrint('[Queue] Removed track at index $index (queue size: ${_queue.length})');
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
  }

  // ---------------------------------------------------------------------------
  // Core track loading
  // ---------------------------------------------------------------------------

  Future<void> _loadCurrentTrack() async {
    if (_queue.isEmpty || _currentIndex < 0) return;
    if (_isLoading) {
      debugPrint('[AudioHandler] _loadCurrentTrack skipped — already loading');
      return;
    }

    final track = _queue[_currentIndex];
    debugPrint('[Playback] Loading track: "${track.title}" by "${track.artist}" (id=${track.id})');
    mediaItem.add(_trackToMediaItem(track));
    _pushPlaybackState(playerState: PlayerState(false, ProcessingState.loading));

    _isLoading = true;
    try {
      if (track.isYoutube) {
        await _loadYouTubeTrack(track);
      } else {
        await _loadLocalTrack(track);
      }
    } catch (e, stack) {
      debugPrint('[Playback] _loadCurrentTrack failed for "${track.title}": $e');
      if (kDebugMode) debugPrintStack(stackTrace: stack);
      playbackState.add(
        playbackState.value.copyWith(processingState: AudioProcessingState.error),
      );
      _errorController.add(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      _isLoading = false;
    }
  }

  /// Loads a YouTube track with bounded retry (up to [_kMaxYouTubeRetries] fresh resolutions).
  Future<void> _loadYouTubeTrack(MusicItem track) async {
    final videoId = _extractYouTubeVideoId(track.id);
    debugPrint('[YouTubeResolver] START loading videoId=$videoId');

    String? streamUrl =
        await YouTubeAudioService().getAudioStreamUrl(videoId);

    if (streamUrl == null || streamUrl.isEmpty) {
      debugPrint('[YouTubeResolver] Initial resolution failed for $videoId, retrying fresh');
      streamUrl = await YouTubeAudioService()
          .getAudioStreamUrl(videoId, forceRefresh: true);
    }

    if (streamUrl == null || streamUrl.isEmpty) {
      throw Exception('Unable to resolve audio stream for "${track.title}" (videoId=$videoId)');
    }

    debugPrint('[YouTubeResolver] Loading audio source for $videoId');
    try {
      await _setAudioSourceUrl(streamUrl);
      debugPrint('[Playback] YouTube audio source loaded successfully for $videoId');
    } on PlayerException catch (pe) {
      debugPrint('[Playback] PlayerException on first load (code=${pe.code}): ${pe.message}');
      debugPrint('[StreamCache] Invalidating and re-resolving for $videoId (retry 1/$_kMaxYouTubeRetries)');
      YouTubeAudioService().invalidateCache(videoId);

      final freshUrl = await YouTubeAudioService()
          .getAudioStreamUrl(videoId, forceRefresh: true);

      if (freshUrl != null && freshUrl.isNotEmpty) {
        debugPrint('[YouTubeResolver] Retry 1: loading fresh URL for $videoId');
        await _setAudioSourceUrl(freshUrl);
        debugPrint('[Playback] YouTube audio source loaded on retry for $videoId');
      } else {
        throw Exception(
          'YouTube stream failed after retry for "${track.title}" '
          '(PlayerException code=${pe.code})',
        );
      }
    }
  }

  /// Loads a local or remote non-YouTube source.
  Future<void> _loadLocalTrack(MusicItem track) async {
    final path = track.filePath;
    if (!kIsWeb && path.isNotEmpty && !path.startsWith('http')) {
      debugPrint('[Playback] Loading local file: $path');
      await _player.setAudioSource(AudioSource.file(path));
      debugPrint('[Playback] Local file loaded successfully');
    } else if (path.isNotEmpty && path.startsWith('http')) {
      debugPrint('[Playback] Loading remote URL: $path');
      await _player.setUrl(path);
      debugPrint('[Playback] Remote URL loaded successfully');
    } else {
      throw Exception('Track "${track.title}" has no valid file path or source');
    }
  }

  /// Sets the audio source from a URL with the required YouTube headers.
  Future<void> _setAudioSourceUrl(String url) async {
    await _player.setAudioSource(
      AudioSource.uri(
        Uri.parse(url),
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36',
          'Referer': 'https://www.youtube.com/',
          'Origin': 'https://www.youtube.com',
        },
      ),
    );
  }

  /// Recovery path called when a playback event stream error occurs mid-playback.
  /// This is separate from the initial load retry path.
  Future<void> _recoverYouTubePlayback({
    required String videoId,
    required MusicItem track,
    required int retryCount,
    required bool resumePlayback,
  }) async {
    if (retryCount >= _kMaxYouTubeRetries) {
      debugPrint(
        '[Playback] Recovery failed after $retryCount retries for $videoId — non-recoverable',
      );
      _errorController.add(
        'Playback failed for "${track.title}" after $_kMaxYouTubeRetries retries.',
      );
      playbackState.add(
        playbackState.value.copyWith(processingState: AudioProcessingState.error),
      );
      return;
    }

    debugPrint(
      '[Playback] Recovery attempt ${retryCount + 1}/$_kMaxYouTubeRetries for $videoId',
    );

    try {
      _pushPlaybackState(playerState: PlayerState(false, ProcessingState.loading));
      final freshUrl = await YouTubeAudioService()
          .getAudioStreamUrl(videoId, forceRefresh: true);

      if (freshUrl == null || freshUrl.isEmpty) {
        debugPrint('[YouTubeResolver] Fresh URL still null on retry ${retryCount + 1}');
        await _recoverYouTubePlayback(
          videoId: videoId,
          track: track,
          retryCount: retryCount + 1,
          resumePlayback: resumePlayback,
        );
        return;
      }

      await _setAudioSourceUrl(freshUrl);
      debugPrint('[Playback] Recovery succeeded: audio source reloaded for $videoId');

      if (resumePlayback) {
        await play();
        debugPrint('[Playback] Playback resumed after recovery for $videoId');
      }
    } catch (e) {
      debugPrint('[Playback] Recovery error (attempt ${retryCount + 1}) for $videoId: $e');
      await _recoverYouTubePlayback(
        videoId: videoId,
        track: track,
        retryCount: retryCount + 1,
        resumePlayback: resumePlayback,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _extractYouTubeVideoId(String trackId) {
    return trackId.startsWith('youtube_')
        ? trackId.replaceFirst('youtube_', '')
        : trackId;
  }

  MediaItem _trackToMediaItem(MusicItem track) {
    Uri? artUri;
    if (track.imageUrl.isNotEmpty) {
      if (track.imageUrl.startsWith('http')) {
        artUri = Uri.parse(track.imageUrl);
      } else {
        artUri = Uri.file(track.imageUrl);
      }
    }
    return MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist,
      artUri: artUri,
      extras: {'filePath': track.filePath},
    );
  }

  // ---------------------------------------------------------------------------
  // BaseAudioHandler overrides
  // ---------------------------------------------------------------------------

  @override
  Future<void> play() async {
    try {
      await _player.play();
      debugPrint('[Playback] play() called');
    } catch (e, stack) {
      debugPrint('[Playback] play() failed: $e');
      if (kDebugMode) debugPrintStack(stackTrace: stack);
      _errorController.add(e.toString().replaceFirst('Exception: ', ''));
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    debugPrint('[Playback] pause() called');
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
    debugPrint('[Playback] stop() called');
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    debugPrint('[Playback] seek(${position.inSeconds}s)');
  }

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;
    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      debugPrint('[Queue] skipToNext → index $_currentIndex');
      try {
        await _loadCurrentTrack();
        await play();
      } catch (e) {
        debugPrint('[Queue] skipToNext failed: $e');
      }
    } else {
      debugPrint('[Queue] skipToNext: already at last track, stopping');
      await _player.stop();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      debugPrint('[Queue] skipToPrevious: position >3s, seeking to start');
      return;
    }
    if (_currentIndex > 0) {
      _currentIndex--;
      debugPrint('[Queue] skipToPrevious → index $_currentIndex');
      try {
        await _loadCurrentTrack();
        await play();
      } catch (e) {
        debugPrint('[Queue] skipToPrevious failed: $e');
      }
    } else {
      await _player.seek(Duration.zero);
      debugPrint('[Queue] skipToPrevious: already at first track, seeking to start');
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    debugPrint('[Queue] skipToQueueItem → index $index');
    try {
      await _loadCurrentTrack();
      await play();
    } catch (e) {
      debugPrint('[Queue] skipToQueueItem failed: $e');
    }
  }

  @override
  Future<void> fastForward() async {
    final target = _player.position + _kSkipDuration;
    final duration = _player.duration ?? Duration.zero;
    await _player.seek(target < duration ? target : duration);
  }

  @override
  Future<void> rewind() async {
    final target = _player.position - _kSkipDuration;
    await _player.seek(target > Duration.zero ? target : Duration.zero);
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
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    await _player.setShuffleModeEnabled(enabled);
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
    debugPrint('[Playback] Shuffle mode set to $shuffleMode');
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
  Future<void> onTaskRemoved() async => stop();

  Future<void> disposeHandler() async {
    await _playerStateSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _playbackEventSub?.cancel();
    await _errorController.close();
    await _player.dispose();
    debugPrint('[AudioHandler] Disposed');
  }
}
