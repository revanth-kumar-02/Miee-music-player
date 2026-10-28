import 'package:flutter/foundation.dart';
import '../../../core/audio/playback_state.dart';
import '../../../shared/models/music_item.dart';
import '../../history/domain/listening_history_repository.dart';

/// Accurate listening-time accumulator that guarantees:
/// 1. Only intervals during which playback genuinely progresses are counted.
/// 2. Seeking forward or backward is NOT counted as listened time.
/// 3. Pauses, interruptions, and buffering halt duration accumulation.
/// 4. Flushes safely to [ListeningHistoryRepository] without double-counting.
class PlaybackAnalyticsTracker {
  final ListeningHistoryRepository _historyRepo;
  final String? Function() _getUid;

  String? _activeTrackId;
  MusicItem? _activeTrack;
  DateTime? _sessionStartTime;
  Duration _lastPosition = Duration.zero;
  DateTime _lastWallClock = DateTime.now();
  int _accumulatedListenedSec = 0;
  bool _isPlaying = false;

  DateTime? get sessionStartTime => _sessionStartTime;

  PlaybackAnalyticsTracker({
    required ListeningHistoryRepository historyRepo,
    required String? Function() getUid,
  })  : _historyRepo = historyRepo,
        _getUid = getUid;

  /// Called on playback state changes (playing, paused, buffering, completed, idle).
  void onPlaybackStatusChanged(PlaybackStatus status, MusicItem? currentTrack) {
    final now = DateTime.now();

    if (status == PlaybackStatus.playing) {
      if (!_isPlaying) {
        _isPlaying = true;
        _lastWallClock = now;
      }
      if (currentTrack != null && currentTrack.id != _activeTrackId) {
        // Track switched while playing
        _flushCurrentSession();
        _startNewSession(currentTrack, now);
      }
    } else {
      // Paused, completed, buffering, or idle
      if (_isPlaying) {
        _isPlaying = false;
        if (status == PlaybackStatus.completed || status == PlaybackStatus.idle) {
          _flushCurrentSession();
        }
      }
    }
  }

  /// Called whenever player reports position progression.
  void onPositionUpdated(Duration newPosition, Duration duration) {
    if (!_isPlaying || _activeTrack == null) {
      _lastPosition = newPosition;
      _lastWallClock = DateTime.now();
      return;
    }

    final now = DateTime.now();
    final wallClockDeltaSec = now.difference(_lastWallClock).inMilliseconds / 1000.0;
    final posDeltaSec = (newPosition - _lastPosition).inMilliseconds / 1000.0;

    // Legitimate audio progression: position delta must be positive AND
    // cannot significantly exceed wall-clock time (accounting for small clock jitter).
    // If the user sought 30 seconds ahead in 0.2s, posDeltaSec is ~30s while wallClockDeltaSec is ~0.2s.
    // That means seeking forward must NOT be credited as listening time!
    if (posDeltaSec > 0 && posDeltaSec <= (wallClockDeltaSec + 1.25)) {
      _accumulatedListenedSec += posDeltaSec.round();
    }

    _lastPosition = newPosition;
    _lastWallClock = now;

    // Periodic flush during long sessions (>45s of active listening) to prevent data loss
    if (_accumulatedListenedSec >= 45) {
      _flushCurrentSession(keepSessionActive: true);
    }
  }

  /// Handles track switching explicitly.
  void onTrackChanged(MusicItem? newTrack) {
    final now = DateTime.now();
    if (_activeTrackId != null && _activeTrackId != newTrack?.id) {
      _flushCurrentSession();
    }
    if (newTrack != null) {
      _startNewSession(newTrack, now);
    }
  }

  void _startNewSession(MusicItem track, DateTime now) {
    _activeTrackId = track.id;
    _activeTrack = track;
    _sessionStartTime = now;
    _lastWallClock = now;
    _accumulatedListenedSec = 0;
  }

  void _flushCurrentSession({bool keepSessionActive = false}) {
    if (_activeTrack == null || _accumulatedListenedSec < 5) {
      if (!keepSessionActive) {
        _activeTrackId = null;
        _activeTrack = null;
        _accumulatedListenedSec = 0;
      }
      return;
    }

    final trackToRecord = _activeTrack!;
    final secondsToRecord = _accumulatedListenedSec;
    final durSec = _parseDurationSec(trackToRecord.duration);

    try {
      _historyRepo.recordListeningEvent(
        uid: _getUid(),
        track: trackToRecord,
        listenedSec: secondsToRecord,
        durationSec: durSec > 0 ? durSec : 180,
      );
    } catch (e) {
      debugPrint('[PlaybackAnalyticsTracker] Flush error: $e');
    }

    if (keepSessionActive) {
      _accumulatedListenedSec = 0;
      _lastWallClock = DateTime.now();
    } else {
      _activeTrackId = null;
      _activeTrack = null;
      _accumulatedListenedSec = 0;
    }
  }

  int _parseDurationSec(String dur) {
    if (dur.isEmpty) return 180;
    final parts = dur.split(':');
    if (parts.length == 2) {
      return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    } else if (parts.length == 3) {
      return (int.tryParse(parts[0]) ?? 0) * 3600 +
          (int.tryParse(parts[1]) ?? 0) * 60 +
          (int.tryParse(parts[2]) ?? 0);
    }
    return 180;
  }

  /// Flushes any pending listened time when application is paused, backgrounded, or disposed.
  void dispose() {
    _flushCurrentSession();
  }
}
