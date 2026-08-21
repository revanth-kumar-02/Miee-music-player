import 'dart:async';
import 'package:flutter/foundation.dart';

/// Abstract service interface for online YouTube video playback across Web and Mobile.
abstract class OnlinePlaybackService {
  /// Stream of current video playback position.
  Stream<Duration> get positionStream;

  /// Stream of current video total duration.
  Stream<Duration> get durationStream;

  /// Stream of playing state (true = playing, false = paused/stopped).
  Stream<bool> get isPlayingStream;

  /// Stream of playback error messages.
  Stream<String?> get errorStream;

  /// Currently active video ID.
  String? get currentVideoId;

  /// Loads a YouTube video by [videoId] and prepares playback.
  Future<void> loadVideo(String videoId);

  /// Starts or resumes video playback.
  Future<void> play();

  /// Pauses video playback.
  Future<void> pause();

  /// Stops playback and resets state.
  Future<void> stop();

  /// Seeks to [position].
  Future<void> seek(Duration position);

  /// Sets audio volume (0.0 to 1.0).
  Future<void> setVolume(double volume);

  /// Disposes player resources.
  void dispose();
}
