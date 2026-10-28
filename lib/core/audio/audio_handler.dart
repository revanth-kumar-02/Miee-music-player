import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../../shared/models/music_item.dart';
import '../../features/youtube/data/web_music_discovery_source.dart';
import 'youtube_audio_service.dart';
import 'playback_diagnostics.dart';
import 'playback_state.dart' show isSameTrackId;

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

  /// Indicates whether a track source load or transition is actively underway.
  /// Prevents transient pause states from demoting the Android foreground service.
  bool _isLoadingTrack = false;
  bool get isLoadingTrack => _isLoadingTrack;

  /// Tracks whether playback was interrupted mid-stream by a transient system
  /// interruption (e.g. phone call). If the user explicitly pauses/stops the
  /// song, or if the song was already paused when an interruption occurred,
  /// this is ALWAYS false. This guarantees Miee NEVER resumes playback when
  /// external apps (like Instagram Reels, TikTok, YouTube, Twitter) lose or
  /// yield audio focus.
  bool _playInterrupted = false;

  @visibleForTesting
  bool get playInterrupted => _playInterrupted;

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

  /// Monotonically increasing token to discard stale in-flight loads
  /// when a user rapidly selects a different song.
  int _activeLoadToken = 0;

  /// Controller to stream playback errors to PlayerController.
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  // Stream subscriptions
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlaybackEvent>? _playbackEventSub;

  MieeAudioHandler({AudioPlayer? player})
      : _player = player ?? AudioPlayer(handleInterruptions: false) {
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

      session.interruptionEventStream.listen(handleInterruptionEvent);

      session.becomingNoisyEventStream.listen((_) {
        debugPrint('[BackgroundAudio] Becoming noisy (headset removed) — pausing');
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
    debugPrint(
      '[BackgroundAudio] Audio interruption event: begin=${event.begin}, type=${event.type}, '
      'player.playing=${_player.playing}, playInterrupted=$_playInterrupted',
    );

    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          if (_player.playing) {
            _player.setVolume((_player.volume * 0.5).clamp(0.1, 1.0));
          }
          break;
        case AudioInterruptionType.pause:
          // Transient interruption (e.g. incoming phone call).
          // ONLY mark to resume if Miee was actively playing right now!
          if (_player.playing) {
            debugPrint(
              '[BackgroundAudio] Audio interruption began while playing — pausing with resume intent',
            );
            _playInterrupted = true;
            if (_player.position > Duration.zero) {
              _lastValidPosition = _player.position;
            }
            _player.pause();
          } else {
            debugPrint(
              '[BackgroundAudio] Audio interruption began while already paused — will NOT resume',
            );
            _playInterrupted = false;
          }
          break;
        case AudioInterruptionType.unknown:
          // Permanent loss of audio focus (e.g. another media app like Spotify/YouTube/Instagram started playing).
          // Never resume after permanent loss, but record position so manual resume works!
          debugPrint(
            '[BackgroundAudio] Permanent audio focus loss — pausing without auto-resume',
          );
          _playInterrupted = false;
          if (_player.position > Duration.zero) {
            _lastValidPosition = _player.position;
          }
          _player.pause();
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
          if (_playInterrupted) {
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
        case AudioInterruptionType.unknown:
          debugPrint(
            '[BackgroundAudio] Permanent interruption ended — staying paused',
          );
          _playInterrupted = false;
          break;
      }
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
        if (_currentIndex >= 0 && _currentIndex < _queue.length) {
          final current = _queue[_currentIndex];
          if (current.isYoutube) {
            final videoId = _extractYouTubeVideoId(current.id);
            debugPrint('[StreamCache] Invalidating cache for $videoId due to stream error');
            YouTubeAudioService().invalidateCache(videoId);
            final wasPlaying = _player.playing || playbackState.value.playing;
            await _recoverYouTubePlayback(
              videoId: videoId,
              track: current,
              retryCount: 0,
              resumePlayback: wasPlaying,
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

    // If a track load/transition is actively underway, preserve foreground buffering state
    // so audio_service does not demote the Android foreground service during temporary pause
    if (_isLoadingTrack) {
      final wasPlaying = playbackState.value.playing;
      _pushPlaybackState(
        playerState: PlayerState(wasPlaying, ProcessingState.buffering),
      );
      return;
    }

    _pushPlaybackState(playerState: playerState);

    // Record confirmed playing latency metric
    if (playerState.playing && playerState.processingState == ProcessingState.ready) {
      if (_currentIndex >= 0 && _currentIndex < _queue.length) {
        PlaybackDiagnostics().recordConfirmedPlaying(_queue[_currentIndex].id);
      }
    }

    // Handle track completion — advance to next track.
    // NOTE: PlayerController must NOT also handle completed, as that causes double-skip.
    if (playerState.processingState == ProcessingState.completed) {
      if (_isRoomListener) {
        debugPrint('[Queue] Room listener reached track completion; waiting for host update.');
        return;
      }
      debugPrint('[Queue] Track completed at index $_currentIndex, advancing queue');
      skipToNext();
    }
  }

  void _onPositionChanged(Duration position) {
    if (position > Duration.zero) {
      _lastValidPosition = position;
    }
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
    await _loadCurrentTrack(initialPosition: initialPosition);
  }

  Future<void> appendTrack(MusicItem track) async {
    _queue.add(track);
    queue.add(_queue.map(_trackToMediaItem).toList());
    debugPrint('[Queue] Appended track "${track.title}" (queue size: ${_queue.length})');
  }

  Future<void> appendTracks(List<MusicItem> tracks) async {
    if (tracks.isEmpty) return;
    _queue.addAll(tracks);
    queue.add(_queue.map(_trackToMediaItem).toList());
    debugPrint('[Queue] Appended ${tracks.length} tracks (queue size: ${_queue.length})');
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

  Future<void> _loadCurrentTrack({Duration? initialPosition}) async {
    if (_queue.isEmpty || _currentIndex < 0) return;

    final token = ++_activeLoadToken;
    final track = _queue[_currentIndex];
    debugPrint('[Playback] Loading track: "${track.title}" by "${track.artist}" (id=${track.id}, token=$token, initialPos=${initialPosition?.inSeconds}s)');

    // 1. Smoothly fade out prior audio and invalidate loaded track identity so old track transitions cleanly.
    final wasPlaying = _player.playing || playbackState.value.playing;
    _isLoadingTrack = true;
    _loadedAudioTrackId = null;

    if (initialPosition != null && initialPosition > Duration.zero) {
      _lastValidPosition = initialPosition;
    } else {
      _lastValidPosition = Duration.zero;
    }

    try {
      if (_player.playing) {
        await fadeOutAndPause(duration: const Duration(milliseconds: 120));
      }
      // Note: Do NOT call _player.stop() here. Calling stop unloads ExoPlayer and
      // signals the Android OS that media playback is inactive, which drops media wake locks
      // and causes Android to suspend YouTube network resolution when the screen is turned off.
    } catch (_) {}

    // 2. Push buffering state for OS, lock screen, and UI.
    // Retain playing: wasPlaying so audio_service retains Android media playback wake locks while screen is off.
    _pushPlaybackState(playerState: PlayerState(wasPlaying, ProcessingState.buffering));

    try {
      if (track.isYoutube) {
        await _loadYouTubeTrack(track, token);
      } else {
        await _loadLocalTrack(track, token);
      }

      if (token != _activeLoadToken) {
        _isLoadingTrack = false;
        debugPrint('[Playback] Load completed but superseded (token $token vs $_activeLoadToken)');
        return;
      }

      // Restore position if specified
      if (_lastValidPosition > Duration.zero) {
        debugPrint('[Playback] Restoring position to ${_lastValidPosition.inSeconds}s for "${track.title}"');
        await _player.seek(_lastValidPosition);
      }

      _loadedAudioTrackId = track.id;
      _isLoadingTrack = false;

      // 3. ONLY commit mediaItem after audio source has been prepared and verified successfully!
      mediaItem.add(_trackToMediaItem(track));
    } catch (e, stack) {
      _isLoadingTrack = false;
      if (token != _activeLoadToken) {
        debugPrint('[Playback] Ignoring error for superseded track (token $token vs $_activeLoadToken)');
        return;
      }
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
  }

  /// Loads a YouTube track with bounded retry (up to [_kMaxYouTubeRetries] fresh resolutions).
  Future<void> _loadYouTubeTrack(MusicItem track, int token) async {
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
        await _setAudioSourceUrl(track.filePath);
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
        PlaybackDiagnostics().recordError(track.id, 'Unable to resolve YouTube video ID for query: $query');
        throw Exception('Unable to resolve YouTube video for "${track.title}". Please try again.');
      }
    }

    debugPrint('[AudioHandler] Loading YouTube track: videoId=$videoId ("${track.title}", token=$token)');

    PlaybackDiagnostics().recordStreamResolutionStart(track.id);
    String? streamUrl =
        await YouTubeAudioService().getAudioStreamUrl(videoId);

    if (token != _activeLoadToken) {
      debugPrint('[AudioHandler] Discarding stale YouTube resolution for $videoId ($token vs $_activeLoadToken)');
      return;
    }

    if (streamUrl == null || streamUrl.isEmpty || !YouTubeAudioService().isUrlValid(streamUrl)) {
      debugPrint('[AudioHandler] Initial resolution failed for $videoId, retrying fresh (attempt 2/2)');
      streamUrl = await YouTubeAudioService()
          .getAudioStreamUrl(videoId, forceRefresh: true);
      if (token != _activeLoadToken) return;
    }

    // Web fallback: resolve full stream via WebMusicDiscoverySource
    if ((streamUrl == null || streamUrl.isEmpty || !YouTubeAudioService().isUrlValid(streamUrl)) && kIsWeb) {
      debugPrint('[AudioHandler] Falling back to WebMusicDiscoverySource for "${track.title}"');
      streamUrl = await WebMusicDiscoverySource().resolveStreamForTrack(track.title, track.artist);
      if (token != _activeLoadToken) return;
    }

    if (streamUrl == null || streamUrl.isEmpty || !YouTubeAudioService().isUrlValid(streamUrl)) {
      PlaybackDiagnostics().recordError(track.id, 'Unable to resolve audio stream');
      throw Exception('Unable to resolve full audio stream for "${track.title}". Please try again.');
    }

    if (token != _activeLoadToken) return;

    PlaybackDiagnostics().recordPlayerLoadStart(track.id);
    try {
      await _setAudioSourceUrl(streamUrl);
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

      final freshUrl = await YouTubeAudioService()
          .getAudioStreamUrl(videoId, forceRefresh: true);
      if (token != _activeLoadToken) return;

      if (freshUrl != null && freshUrl.isNotEmpty && YouTubeAudioService().isUrlValid(freshUrl)) {
        await _setAudioSourceUrl(freshUrl);
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
  Future<void> _loadLocalTrack(MusicItem track, int token) async {
    PlaybackDiagnostics().recordPlayerLoadStart(track.id);
    final path = track.filePath;
    try {
      if (!kIsWeb && path.isNotEmpty && !path.startsWith('http')) {
        debugPrint('[Playback] Loading local file: $path (token=$token)');
        if (token != _activeLoadToken) return;
        await _player.setAudioSource(AudioSource.file(path));
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
        debugPrint('[Playback] Loading remote URL: $path (token=$token)');
        if (token != _activeLoadToken) return;
        await _player.setUrl(path);
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

  /// Sets the audio source from a URL with the required headers.
  Future<void> _setAudioSourceUrl(String url) async {
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
            : const {
                'User-Agent': kYouTubeVisionOsUserAgent,
              },
      ),
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

  /// Recovery path called when a playback event stream error occurs mid-playback.
  /// This is separate from the initial load retry path.
  Future<void> _recoverYouTubePlayback({
    required String videoId,
    required MusicItem track,
    required int retryCount,
    required bool resumePlayback,
  }) async {
    final token = _activeLoadToken;
    if (retryCount >= _kMaxYouTubeRetries) {
      debugPrint(
        '[Playback] Recovery failed after $retryCount retries for $videoId — non-recoverable',
      );
      _loadedAudioTrackId = null;
      _errorController.add(
        'Playback failed for "${track.title}" after $_kMaxYouTubeRetries retries.',
      );
      playbackState.add(
        playbackState.value.copyWith(processingState: AudioProcessingState.error),
      );
      return;
    }

    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    if (_extractYouTubeVideoId(_queue[_currentIndex].id) != videoId) {
      debugPrint('[Playback] Aborting recovery: track changed ($videoId vs ${_queue[_currentIndex].id})');
      return;
    }

    debugPrint(
      '[Playback] Recovery attempt ${retryCount + 1}/$_kMaxYouTubeRetries for $videoId',
    );

    final savedPosition = _player.position > Duration.zero
        ? _player.position
        : (_lastValidPosition > Duration.zero ? _lastValidPosition : Duration.zero);

    try {
      _isLoadingTrack = true;
      _pushPlaybackState(playerState: PlayerState(resumePlayback, ProcessingState.buffering));
      final freshUrl = await YouTubeAudioService()
          .getAudioStreamUrl(videoId, forceRefresh: true);

      if (token != _activeLoadToken) {
        _isLoadingTrack = false;
        debugPrint('[Playback] Recovery discarded: superseded by newer track (token $token vs $_activeLoadToken)');
        return;
      }

      if (_currentIndex < 0 ||
          _currentIndex >= _queue.length ||
          _extractYouTubeVideoId(_queue[_currentIndex].id) != videoId) {
        _isLoadingTrack = false;
        return;
      }

      if (freshUrl == null || freshUrl.isEmpty) {
        _isLoadingTrack = false;
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
      if (token != _activeLoadToken) {
        _isLoadingTrack = false;
        return;
      }

      _loadedAudioTrackId = track.id;

      if (savedPosition > Duration.zero) {
        _lastValidPosition = savedPosition;
        await _player.seek(savedPosition);
      }
      _isLoadingTrack = false;
      debugPrint('[Playback] Recovery succeeded: audio source reloaded for $videoId at ${savedPosition.inSeconds}s');

      if (resumePlayback) {
        await play();
        debugPrint('[Playback] Playback resumed after recovery for $videoId');
      }
    } catch (e) {
      _isLoadingTrack = false;
      if (token != _activeLoadToken) return;
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
    if (track.imageUrl.isNotEmpty) {
      if (track.imageUrl.startsWith('http')) {
        artUri = Uri.parse(track.imageUrl);
      } else {
        artUri = Uri.file(track.imageUrl);
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
    return MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist,
      duration: parsedDuration,
      artUri: artUri,
      extras: {'filePath': track.filePath},
    );
  }

  // ---------------------------------------------------------------------------
  // BaseAudioHandler overrides
  // ---------------------------------------------------------------------------

  @override
  Future<void> play() async {
    _playInterrupted = false;
    if (_currentIndex < 0 || _currentIndex >= _queue.length) {
      debugPrint('[Playback] play() ignored: queue is empty or index invalid');
      return;
    }
    final current = _queue[_currentIndex];
    if (_loadedAudioTrackId == null || !isSameTrackId(_loadedAudioTrackId, current.id)) {
      debugPrint(
        '[Playback] play() unblocking: active track "${current.title}" (${current.id}) '
        'is not prepared in player (loaded: $_loadedAudioTrackId) — reloading from lastValidPosition: ${_lastValidPosition.inSeconds}s',
      );
      await _loadCurrentTrack(initialPosition: _lastValidPosition);
      if (!kIsWeb) {
        try {
          final session = await AudioSession.instance;
          await session.setActive(true);
        } catch (_) {}
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
    _playInterrupted = false;
    if (_player.position > Duration.zero) {
      _lastValidPosition = _player.position;
    }
    await _player.pause();
    debugPrint('[Playback] pause() called');
  }

  @override
  Future<void> stop() async {
    _playInterrupted = false;
    _loadedAudioTrackId = null;
    await _player.stop();
    _pushPlaybackState(playerState: PlayerState(false, ProcessingState.idle));
    debugPrint('[Playback] stop() called');
  }

  @override
  Future<void> seek(Duration position) async {
    _lastValidPosition = position;
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

  @override
  Future<void> skipToNext() async {
    _playInterrupted = false;
    if (_queue.isEmpty) return;
    if (_player.playing) {
      await fadeOutAndPause(duration: const Duration(milliseconds: 140));
    }

    // If approaching the end of the queue, notify queue expansion listener in background
    if (!_isRoomListener && _currentIndex >= _queue.length - 2) {
      unawaited(onQueueApproachingEnd?.call());
    }

    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      debugPrint('[Queue] skipToNext → index $_currentIndex');
      try {
        await _loadCurrentTrack();
        await play();
      } catch (e) {
        debugPrint('[Queue] skipToNext failed: $e');
      }
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
        debugPrint('[Queue] skipToNext: queue expanded successfully → advancing to index $_currentIndex');
        try {
          await _loadCurrentTrack();
          await play();
          return;
        } catch (e) {
          debugPrint('[Queue] skipToNext expanded track load failed: $e');
        }
      }

      // If repeat all is on, wrap around; otherwise stop
      if (_player.loopMode == LoopMode.all && _queue.isNotEmpty) {
        _currentIndex = 0;
        debugPrint('[Queue] skipToNext: LoopMode.all wrap-around → index 0');
        try {
          await _loadCurrentTrack();
          await play();
        } catch (e) {
          debugPrint('[Queue] skipToNext wrap failed: $e');
        }
      } else {
        debugPrint('[Queue] skipToNext: no further tracks available, stopping');
        await _player.stop();
      }
    } else if (_player.loopMode == LoopMode.all && _queue.isNotEmpty) {
      _currentIndex = 0;
      debugPrint('[Queue] skipToNext: LoopMode.all wrap-around → index 0');
      try {
        await _loadCurrentTrack();
        await play();
      } catch (e) {
        debugPrint('[Queue] skipToNext wrap failed: $e');
      }
    } else {
      debugPrint('[Queue] skipToNext: already at last track, stopping');
      await _player.stop();
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
      if (_player.playing) {
        await fadeOutAndPause(duration: const Duration(milliseconds: 140));
      }
      _currentIndex--;
      debugPrint('[Queue] skipToPrevious → index $_currentIndex');
      try {
        await _loadCurrentTrack();
        await play();
      } catch (e) {
        debugPrint('[Queue] skipToPrevious failed: $e');
      }
    } else if (_player.loopMode == LoopMode.all && _queue.isNotEmpty) {
      _currentIndex = _queue.length - 1;
      debugPrint('[Queue] skipToPrevious: LoopMode.all wrap-around → index $_currentIndex');
      try {
        await _loadCurrentTrack();
        await play();
      } catch (e) {
        debugPrint('[Queue] skipToPrevious wrap failed: $e');
      }
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
