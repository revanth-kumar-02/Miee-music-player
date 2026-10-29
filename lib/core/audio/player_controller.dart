import 'dart:async';

import 'package:audio_service/audio_service.dart' hide PlaybackState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../shared/models/music_item.dart';
import '../../shared/models/track.dart';
import 'audio_handler.dart';
import 'playback_state.dart';
import 'queue_manager.dart';
import '../../features/media/providers/media_providers.dart';
import '../../features/media/domain/models.dart';
import '../../features/youtube/providers/youtube_providers.dart';
import '../../features/youtube/domain/youtube_model.dart';
import '../../features/youtube/domain/music_result_classifier.dart';
import '../../features/library/providers/library_providers.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/history/providers/history_providers.dart';
import '../../features/recommendations/providers/recommendation_providers.dart';
import '../../features/profile/providers/profile_providers.dart';
import '../../features/wrapped/data/playback_analytics_tracker.dart';

import 'playback_diagnostics.dart';

/// Single orchestrator bridging [MieeAudioHandler] with unified Riverpod state.
///
/// CRITICAL DESIGN CONTRACT:
/// [MieeAudioHandler] owns [ProcessingState.completed] and advances the queue
/// via [skipToNext] internally. [PlayerController] must NOT also handle
/// completed → next, as that causes a double-skip (two tracks are skipped).
///
/// [PlayerController] only handles:
/// - RepeatMode.one on completed (seek + play, no skip)
/// - RepeatMode.all wrap-around only when handler signals end-of-queue
class PlayerController extends StateNotifier<PlaybackState> {
  final MieeAudioHandler _handler;
  final QueueManager _queueManager;
  final Ref _ref;
  late final PlaybackAnalyticsTracker _analyticsTracker;

  /// Monotonically increasing token to ignore stale async playTrack calls.
  int _playRequestToken = 0;

  /// Monotonically increasing token to ignore stale async recommendation queue responses.
  int _queueGenerationToken = 0;

  /// Guard to prevent concurrent in-flight queue expansion operations.
  bool _isExpandingQueue = false;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _bufferedSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  StreamSubscription<String>? _errorSub;

  PlayerController(this._handler, this._queueManager, this._ref)
      : super(PlaybackState.initial()) {
    _init();
  }

  String _normalizeTrackId(String id) {
    return id.startsWith('youtube_') ? id.replaceFirst('youtube_', '') : id;
  }

  void _init() {
    try {
      final queueRepo = _ref.read(queueStateRepositoryProvider);
      final snapshot = queueRepo.loadSnapshot();
      if (snapshot != null && snapshot.queue.isNotEmpty) {
        final restoredTracks = snapshot.queue.map((m) => m.toTrack()).toList();
        _queueManager.setQueue(restoredTracks, startIndex: snapshot.currentIndex);
        final current = _queueManager.currentTrack;
        final repeat = snapshot.repeatMode == 'one'
            ? RepeatMode.one
            : (snapshot.repeatMode == 'all' ? RepeatMode.all : RepeatMode.off);
        state = PlaybackState.initial().copyWith(
          currentTrack: current,
          isShuffleEnabled: snapshot.isShuffleEnabled,
          repeatMode: repeat,
          position: Duration(milliseconds: snapshot.positionMs),
        );
      } else {
        _queueManager.setQueue([]);
        state = PlaybackState.initial();
      }
    } catch (e) {
      debugLog('[QueuePersistence] Initial restore error: $e');
      _queueManager.setQueue([]);
      state = PlaybackState.initial();
    }

    // Attach dynamic queue replenishment hook to audio handler
    _handler.onQueueApproachingEnd = () => expandQueueIfNeeded();

    _analyticsTracker = PlaybackAnalyticsTracker(
      historyRepo: _ref.read(listeningHistoryRepositoryProvider),
      getUid: () => _ref.read(currentAuthUserProvider)?.uid,
    );

    // ── Position stream ───────────────────────────────────────────────────────
    // Only auto-recover from error state if the player is actively playing
    // and the position event belongs to the currently selected track.
    _positionSub = _handler.positionStream.listen((pos) {
      if (state.status == PlaybackStatus.error &&
          _handler.isPlaying &&
          pos > Duration.zero) {
        final currentHandlerTrack = _handler.currentQueue.isNotEmpty &&
                _handler.currentIndex >= 0 &&
                _handler.currentIndex < _handler.currentQueue.length
            ? _handler.currentQueue[_handler.currentIndex]
            : null;
        if (currentHandlerTrack != null &&
            state.currentTrack != null &&
            _normalizeTrackId(currentHandlerTrack.id) ==
                _normalizeTrackId(state.currentTrack!.id)) {
          debugLog('[Playback] Position > 0 for active track while in error state — auto-recovering UI');
          state = state.copyWith(
            status: PlaybackStatus.playing,
            clearErrorMessage: true,
          );
        }
      }
      // Guard against transient zero-position emits during buffering, loading, or player recovery
      if (pos == Duration.zero &&
          (state.status == PlaybackStatus.loading ||
              state.status == PlaybackStatus.error ||
              _handler.isLoadingTrack) &&
          state.position > Duration.zero) {
        return;
      }
      state = state.copyWith(position: pos);
      _analyticsTracker.onPositionUpdated(pos, state.duration);
    });

    // ── Duration stream ───────────────────────────────────────────────────────
    _durationSub = _handler.durationStream.listen((dur) {
      if (dur != null && dur > Duration.zero) {
        state = state.copyWith(duration: dur);
      }
    });

    // ── Buffered position stream ──────────────────────────────────────────────
    _bufferedSub = _handler.bufferedPositionStream.listen((buf) {
      state = state.copyWith(bufferedPosition: buf);
    });

    // ── Error stream ──────────────────────────────────────────────────────────
    _errorSub = _handler.errorStream.listen((errorMsg) {
      debugLog('[Playback] Error received in controller: $errorMsg');
      state = state.copyWith(
        status: PlaybackStatus.error,
        errorMessage: errorMsg,
        clearLoadingTrackId: true,
      );
    });

    // ── MediaItem stream (track metadata sync) ────────────────────────────────
    _mediaItemSub = _handler.mediaItem.listen((mediaItem) {
      if (mediaItem != null) {
        final queueList = _queueManager.queue;
        final targetId = _normalizeTrackId(mediaItem.id);
        final index = queueList.indexWhere((t) =>
            t.id == mediaItem.id || _normalizeTrackId(t.id) == targetId);
        if (index >= 0) {
          _queueManager.setIndex(index);
          state = state.copyWith(currentTrack: queueList[index]);
          _persistQueueSnapshot();
          _recordRecentlyPlayed(queueList[index]);
          _analyticsTracker.onTrackChanged(queueList[index]);
          unawaited(expandQueueIfNeeded());
        }
      }
    });

    // ── PlayerState stream (the authoritative playback state source) ──────────
    _playerStateSub = _handler.playerStateStream.listen((playerState) {
      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;

      PlaybackStatus status;
      switch (processingState) {
        case ProcessingState.idle:
          status = PlaybackStatus.idle;
          break;
        case ProcessingState.loading:
          status = PlaybackStatus.loading;
          break;
        case ProcessingState.buffering:
          status = PlaybackStatus.buffering;
          break;
        case ProcessingState.ready:
          status = isPlaying ? PlaybackStatus.playing : PlaybackStatus.paused;
          break;
        case ProcessingState.completed:
          status = PlaybackStatus.completed;
          break;
      }

      final isHealthy = status == PlaybackStatus.playing ||
          status == PlaybackStatus.buffering ||
          status == PlaybackStatus.paused;

      final clearLoading = status == PlaybackStatus.playing ||
          status == PlaybackStatus.paused ||
          status == PlaybackStatus.completed ||
          status == PlaybackStatus.error;

      state = state.copyWith(
        status: status,
        // Clear any stale error message when playback is healthy
        clearErrorMessage: isHealthy,
        clearLoadingTrackId: clearLoading,
      );
      _analyticsTracker.onPlaybackStatusChanged(status, state.currentTrack);

      // ── Completion handling ───────────────────────────────────────────────
      // IMPORTANT: MieeAudioHandler.skipToNext() is already called by the
      // handler on completed. PlayerController must NOT call next() here.
      //
      // The ONLY thing PlayerController handles on completed is RepeatMode.one:
      // seek to start and re-play the same track without involving the handler's
      // skip logic.
      if (status == PlaybackStatus.completed) {
        if (state.repeatMode == RepeatMode.one) {
          debugLog('[Playback] RepeatMode.one — seeking to start');
          seek(Duration.zero);
          play();
        }
        // RepeatMode.all and RepeatMode.off are handled entirely in
        // MieeAudioHandler.skipToNext() — do NOT duplicate here.
      }
    });
  }

  // ── Queue management ─────────────────────────────────────────────────────

  void setQueue(List<MusicItem> tracks, {int startIndex = 0, String? playingFrom}) {
    _queueManager.setQueue(tracks, startIndex: startIndex);
    _persistQueueSnapshot();
    final track = _queueManager.currentTrack;
    if (track != null) {
      playTrack(track, playingFrom: playingFrom);
    }
  }

  void selectTrack(MusicItem track, List<MusicItem> currentList, {String? playingFrom}) {
    if (currentList.isEmpty) return;
    final targetId = _normalizeTrackId(track.id);
    final index = currentList.indexWhere(
      (t) => t.id == track.id || _normalizeTrackId(t.id) == targetId,
    );
    if (index < 0) return;
    setQueue(currentList, startIndex: index, playingFrom: playingFrom);
  }

  /// Starts a new queue with [track] as the initial track and returns a generation token
  /// to guard subsequent asynchronous recommendation responses against race conditions.
  int startNewQueue(MusicItem track, {String? playingFrom}) {
    final token = ++_queueGenerationToken;
    setQueue([track], startIndex: 0, playingFrom: playingFrom);
    return token;
  }

  /// Appends diverse upcoming recommendations to the Next Up queue,
  /// guarded by the generation token and active track ID to prevent stale overwrites.
  Future<void> appendUpcomingTracks(
    List<MusicItem> tracks, {
    required int token,
    required String forTrackId,
  }) async {
    if (token != _queueGenerationToken) {
      debugLog('[Queue] Stale recommendation response ignored (token $token vs $_queueGenerationToken)');
      return;
    }
    if (state.currentTrack == null ||
        _normalizeTrackId(state.currentTrack!.id) != _normalizeTrackId(forTrackId)) {
      debugLog('[Queue] Active track changed, discarding upcoming tracks for $forTrackId');
      return;
    }
    if (tracks.isEmpty) return;

    // Filter out any track already in queue
    final currentIds = _queueManager.queue.map((t) => _normalizeTrackId(t.id)).toSet();
    final freshTracks = tracks.where((t) => !currentIds.contains(_normalizeTrackId(t.id))).toList();
    if (freshTracks.isEmpty) return;

    _queueManager.addTracks(freshTracks);
    await _handler.appendTracks(freshTracks);
    _persistQueueSnapshot();
    state = state.copyWith(currentTrack: _queueManager.currentTrack);
    debugLog('[Queue] Appended ${freshTracks.length} diverse upcoming tracks to Next Up');
  }

  /// Automatically replenishes the playback queue when 2 or fewer tracks remain.
  ///
  /// For Listening Rooms:
  /// - Suppressed for listeners; the room Host alone controls automatic queue replenishment.
  /// - The host's expansion is broadcast to listeners via room state synchronization.
  Future<void> expandQueueIfNeeded() async {
    if (_handler.isRoomListener) {
      return;
    }
    if (_isExpandingQueue) return;

    final queue = _queueManager.queue;
    final currentIndex = _queueManager.currentIndex;
    if (queue.isEmpty || currentIndex < 0) return;

    final remaining = queue.length - 1 - currentIndex;
    if (remaining > 2) return;

    final current = _queueManager.currentTrack;
    if (current == null) return;

    _isExpandingQueue = true;
    debugLog('[QueueExpansion] Queue approaching exhaustion ($remaining tracks remaining). Fetching recommendations...');

    try {
      final recService = _ref.read(recommendationServiceProvider);
      final profile = _ref.read(currentUserProfileProvider);
      final upcoming = await recService.getUpcomingQueueRecommendations(
        currentTrack: current,
        currentQueue: queue,
        profile: profile,
        limit: 10,
      );

      if (upcoming.isNotEmpty) {
        final currentIds = _queueManager.queue.map((t) => _normalizeTrackId(t.id)).toSet();
        final currentKeys = _queueManager.queue
            .map((t) => '${t.title.toLowerCase().trim()}|${t.artist.toLowerCase().trim()}')
            .toSet();

        final freshTracks = upcoming.where((t) {
          final normId = _normalizeTrackId(t.id);
          final key = '${t.title.toLowerCase().trim()}|${t.artist.toLowerCase().trim()}';
          return !currentIds.contains(normId) && !currentKeys.contains(key);
        }).toList();

        if (freshTracks.isNotEmpty) {
          _queueManager.addTracks(freshTracks);
          await _handler.appendTracks(freshTracks);
          _persistQueueSnapshot();
          state = state.copyWith(currentTrack: _queueManager.currentTrack);
          debugLog('[QueueExpansion] Successfully appended ${freshTracks.length} fresh tracks. Total queue size: ${_queueManager.queue.length}');
        }
      }
    } catch (e) {
      debugLog('[QueueExpansion] Dynamic queue expansion failed: $e');
    } finally {
      _isExpandingQueue = false;
    }
  }

  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queueManager.queue.length) return;
    _queueManager.setIndex(index);
    final targetTrack = _queueManager.currentTrack;
    if (targetTrack != null) {
      await playTrack(targetTrack);
    }
  }

  // ── Playback ──────────────────────────────────────────────────────────────

  Future<void> playTrack(
    MusicItem track, {
    String? playingFrom,
    Duration? initialPosition,
  }) async {
    // Prevent duplicate in-flight requests for the same track
    if (state.status == PlaybackStatus.loading &&
        state.loadingTrackId != null &&
        isSameTrackId(state.loadingTrackId, track.id)) {
      debugLog('[Playback] Tap ignored: track ${track.id} is already in-flight');
      return;
    }

    // Validate that online YouTube content represents genuine music
    if (track.isYoutube) {
      final rawT = (track is Track) ? (track.rawTitle ?? track.title) : track.title;
      final rawA = (track is Track) ? (track.rawArtist ?? track.artist) : track.artist;
      final candidate = YouTubeVideo(
        id: track.id.replaceFirst('youtube_', ''),
        title: track.title,
        channelTitle: track.artist,
        thumbnailUrl: track.imageUrl,
        duration: track.duration,
        viewCount: '',
        rawTitle: rawT,
        rawChannelTitle: rawA,
      );
      if (!MusicResultClassifier.isValidMusicTrack(candidate)) {
        debugLog('[Playback] Rejected playback of non-music content: "$rawT" by "$rawA"');
        state = state.copyWith(
          status: PlaybackStatus.error,
          clearLoadingTrackId: true,
          errorMessage: 'This video is not a recognized music track.',
        );
        return;
      }
    }

    final token = ++_playRequestToken;

    PlaybackDiagnostics().recordTap(
      trackId: track.id,
      title: track.title,
      isYoutube: track.isYoutube,
    );

    // Smoothly fade out active audio so Song A fades out cleanly (<180ms)
    // while Song B is resolving over the network, without tearing down the foreground service.
    try {
      if (_handler.isPlaying) {
        await _handler.fadeOutAndPause(duration: const Duration(milliseconds: 180));
      } else {
        await _handler.pause();
      }
    } catch (_) {}

    final isOnline = track.isYoutube;
    final startPosition = initialPosition ?? Duration.zero;

    // 1. Immediately update UI state with selected track and loading status
    state = state.copyWith(
      status: PlaybackStatus.loading,
      currentTrack: track,
      loadingTrackId: isOnline ? track.id : null,
      clearLoadingTrackId: !isOnline,
      position: startPosition,
      playingFrom: playingFrom ?? state.playingFrom,
      clearErrorMessage: true,
    );
    PlaybackDiagnostics().recordSelectedTrackUpdated(track.id);

    try {
      final resolvedTrack = await _resolveSource(track);
      if (token != _playRequestToken) {
        debugLog('[Playback] Superseded by newer track selection (token $token vs $_playRequestToken)');
        return;
      }

      final targetId = _normalizeTrackId(track.id);
      int targetIndex = -1;

      // Check if currentIndex already points to this track (e.g. from skipToQueueItem)
      if (_queueManager.currentIndex >= 0 &&
          _queueManager.currentIndex < _queueManager.queue.length) {
        final currentAtPointer = _queueManager.queue[_queueManager.currentIndex];
        if (currentAtPointer.id == track.id ||
            _normalizeTrackId(currentAtPointer.id) == targetId) {
          targetIndex = _queueManager.currentIndex;
        }
      }

      // If not at currentIndex, find it in the queue
      if (targetIndex == -1) {
        targetIndex = _queueManager.queue.indexWhere(
          (t) => t.id == track.id || _normalizeTrackId(t.id) == targetId,
        );
      }

      if (targetIndex >= 0) {
        _queueManager.setIndex(targetIndex);
        _queueManager.replaceTrackAt(targetIndex, resolvedTrack);
      } else {
        if (_queueManager.queue.isEmpty) {
          _queueManager.setQueue([resolvedTrack], startIndex: 0);
          targetIndex = 0;
        } else {
          final currentIdx = _queueManager.currentIndex;
          if (currentIdx >= 0 && currentIdx < _queueManager.queue.length) {
            _queueManager.replaceTrackAt(currentIdx, resolvedTrack);
            targetIndex = currentIdx;
          } else {
            _queueManager.addTrack(resolvedTrack);
            targetIndex = _queueManager.queue.length - 1;
            _queueManager.setIndex(targetIndex);
          }
        }
      }

      state = state.copyWith(currentTrack: resolvedTrack);

      final queueSnapshot = _queueManager.queue;
      final startIdx = targetIndex >= 0 ? targetIndex : 0;
      await _handler.loadQueue(
        queueSnapshot,
        startIndex: startIdx,
        initialPosition: startPosition > Duration.zero ? startPosition : null,
      );
      if (token != _playRequestToken) return;
      await _handler.play();
      _recordRecentlyPlayed(resolvedTrack);
      unawaited(expandQueueIfNeeded());
    } catch (e) {
      if (token != _playRequestToken) return;
      debugLog('[Playback] playTrack failed: $e');
      state = state.copyWith(
        status: PlaybackStatus.error,
        clearLoadingTrackId: true,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  /// Resolves the best source for [track] based on the user's source preference.
  Future<MusicItem> _resolveSource(MusicItem track) async {
    final mode = _ref.read(sourceSelectionProvider);

    if (mode == 'preferLocal' || mode == 'smart' || mode == 'alwaysLocal') {
      if (!track.isYoutube) return track;
      final localMatch = _findLocalVersion(track.title, track.artist);
      if (localMatch != null) return localMatch;
      return track;
    }

    if (mode == 'preferYouTube' || mode == 'alwaysYouTube') {
      if (track.isYoutube) return track;
      final ytMatch = await _findYouTubeVersion(track.title, track.artist);
      if (ytMatch != null) return ytMatch;
      return track;
    }

    // Default: prefer local
    final localMatch = _findLocalVersion(track.title, track.artist);
    if (localMatch != null) return localMatch;
    return track;
  }

  MediaSong? _findLocalVersion(String title, String artist) {
    try {
      final localSongs = _ref.read(songsProvider);
      final cleanTitle = title.trim().toLowerCase();
      final cleanArtist = artist.trim().toLowerCase();
      for (final song in localSongs) {
        if (song.title.trim().toLowerCase() == cleanTitle &&
            song.artist.trim().toLowerCase() == cleanArtist) {
          return song;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<MusicItem?> _findYouTubeVersion(String title, String artist) async {
    try {
      final repo = _ref.read(youtubeRepositoryProvider);
      final results = await repo.search('$title $artist');
      for (final result in results) {
        if (MusicResultClassifier.isValidMusicTrack(result)) {
          return result;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> play() async {
    if ((state.status == PlaybackStatus.idle || state.status == PlaybackStatus.error) &&
        state.currentTrack != null) {
      final resumePos = state.position > Duration.zero ? state.position : null;
      await playTrack(state.currentTrack!, initialPosition: resumePos);
    } else {
      await _handler.play();
    }
  }

  Future<void> pause() async {
    await _handler.pause();
    if (state.loadingTrackId != null) {
      state = state.copyWith(clearLoadingTrackId: true);
    }
  }

  Future<void> togglePlayPause() async {
    if (state.status == PlaybackStatus.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> stop() async {
    await _handler.stop();
    state = state.copyWith(
      status: PlaybackStatus.idle,
      position: Duration.zero,
      clearLoadingTrackId: true,
    );
  }

  Future<void> seek(Duration position) async {
    await _handler.seek(position);
    state = state.copyWith(position: position);
  }

  Future<void> setVolume(double volume) async {
    await _handler.setVolume(volume);
    state = state.copyWith(volume: volume.clamp(0.0, 1.0));
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  Future<void> next() async {
    // If approaching the end of the queue, begin expansion in background
    if (_queueManager.currentIndex >= _queueManager.queue.length - 2) {
      unawaited(expandQueueIfNeeded());
    }

    final nextTrack = _queueManager.next();
    if (nextTrack != null) {
      await playTrack(nextTrack);
    } else if (state.repeatMode == RepeatMode.all &&
        _queueManager.queue.isNotEmpty) {
      _queueManager.setIndex(0);
      final firstTrack = _queueManager.currentTrack;
      if (firstTrack != null) await playTrack(firstTrack);
    } else if (!_handler.isRoomListener) {
      // Reached queue end in non-repeat mode: attempt replenishment before stopping
      await expandQueueIfNeeded();
      final expandedTrack = _queueManager.next();
      if (expandedTrack != null) {
        await playTrack(expandedTrack);
      }
    }
  }

  Future<void> previous() async {
    if (state.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    final prevTrack = _queueManager.previous();
    if (prevTrack != null) {
      await playTrack(prevTrack);
    } else if (state.repeatMode == RepeatMode.all &&
        _queueManager.queue.isNotEmpty) {
      final lastIdx = _queueManager.queue.length - 1;
      _queueManager.setIndex(lastIdx);
      final lastTrack = _queueManager.currentTrack;
      if (lastTrack != null) await playTrack(lastTrack);
    } else {
      await seek(Duration.zero);
    }
  }

  // ── Modes ──────────────────────────────────────────────────────────────────

  Future<void> toggleShuffle() async {
    final isShuffle = !state.isShuffleEnabled;
    if (isShuffle) {
      _queueManager.enableShuffle();
    } else {
      _queueManager.disableShuffle();
    }
    state = state.copyWith(isShuffleEnabled: isShuffle);
    await _handler.setShuffleMode(
      isShuffle
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    );
    _persistQueueSnapshot();
    debugLog('[Playback] Shuffle toggled: $isShuffle');
  }

  Future<void> toggleRepeatMode() async {
    RepeatMode nextMode;
    AudioServiceRepeatMode serviceMode;

    switch (state.repeatMode) {
      case RepeatMode.off:
        nextMode = RepeatMode.all;
        serviceMode = AudioServiceRepeatMode.all;
        break;
      case RepeatMode.all:
        nextMode = RepeatMode.one;
        serviceMode = AudioServiceRepeatMode.one;
        break;
      case RepeatMode.one:
        nextMode = RepeatMode.off;
        serviceMode = AudioServiceRepeatMode.none;
        break;
    }

    state = state.copyWith(repeatMode: nextMode);
    await _handler.setRepeatMode(serviceMode);
    _persistQueueSnapshot();
    debugLog('[Playback] Repeat mode toggled: $nextMode');
  }

  Future<void> addTrackToQueue(MusicItem track) async {
    _queueManager.addTrack(track);
    await _handler.appendTrack(track);
    _persistQueueSnapshot();
    if (state.currentTrack == null) {
      await playTrack(track);
    }
  }

  Future<void> removeTrackAt(int index) async {
    _queueManager.removeTrackAt(index);
    await _handler.removeTrackAt(index);
    _persistQueueSnapshot();
    if (_queueManager.queue.isEmpty) {
      clearQueue();
    } else {
      final current = _queueManager.currentTrack;
      if (state.currentTrack != current) {
        state = state.copyWith(currentTrack: current);
      }
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    _queueManager.reorder(oldIndex, newIndex);
    await _handler.reorderQueue(oldIndex, newIndex);
    _persistQueueSnapshot();
    state = state.copyWith(currentTrack: _queueManager.currentTrack);
  }

  void clearQueue() {
    _queueManager.clear();
    try {
      _ref.read(queueStateRepositoryProvider).clear();
    } catch (_) {}
    state = state.copyWith(
      currentTrack: null,
      status: PlaybackStatus.idle,
      position: Duration.zero,
      duration: Duration.zero,
    );
  }

  void _persistQueueSnapshot() {
    try {
      final queueRepo = _ref.read(queueStateRepositoryProvider);
      queueRepo.saveSnapshot(
        queue: _queueManager.queue,
        currentIndex: _queueManager.currentIndex,
        positionMs: state.position.inMilliseconds,
        isShuffleEnabled: state.isShuffleEnabled,
        repeatMode: state.repeatMode.name,
      );
    } catch (e) {
      debugLog('[QueuePersistence] Save error: $e');
    }
  }

  void _recordRecentlyPlayed(MusicItem track) {
    try {
      String resolvedImage = track.imageUrl;
      if (track.isYoutube && (resolvedImage.isEmpty || !resolvedImage.startsWith('http'))) {
        final videoId = _normalizeTrackId(track.id);
        if (videoId.isNotEmpty) {
          resolvedImage = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
        }
      } else if (!track.isYoutube && resolvedImage.isEmpty) {
        try {
          final localSongs = _ref.read(songsProvider);
          final match = localSongs.where((s) =>
              s.id == track.id ||
              (s.filePath.isNotEmpty && s.filePath == track.filePath)).firstOrNull;
          if (match != null && match.artworkPath.isNotEmpty) {
            resolvedImage = match.artworkPath;
          }
        } catch (_) {}
      }

      final trackToRecord = Track(
        id: track.id,
        title: track.title,
        artist: track.artist,
        imageUrl: resolvedImage,
        duration: track.duration,
        filePath: track.filePath,
      );
      _ref.read(recentlyPlayedRepositoryProvider).recordPlay(trackToRecord);
    } catch (e) {
      debugLog('[RecentlyPlayed] Record error: $e');
    }
  }

  /// Sets whether the current client is a listener in a listening room.
  /// When true, autonomous completion skips in AudioHandler are suppressed.
  void setRoomListener(bool value) {
    _handler.setRoomListener(value);
  }

  // ── Disposal ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _analyticsTracker.dispose();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferedSub?.cancel();
    _playerStateSub?.cancel();
    _mediaItemSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }
}

// ignore: avoid_print
void debugLog(String msg) => print(msg);
