import 'dart:async';
import 'package:flutter/material.dart';
import 'online_playback_service.dart';

class PlatformYouTubePlaybackService implements OnlinePlaybackService {
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _isPlayingController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String?>.broadcast();

  String? _videoId;
  bool _isPlaying = false;
  Timer? _ticker;
  Duration _pos = Duration.zero;
  Duration _dur = const Duration(minutes: 3, seconds: 30);

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Stream<bool> get isPlayingStream => _isPlayingController.stream;

  @override
  Stream<String?> get errorStream => _errorController.stream;

  @override
  String? get currentVideoId => _videoId;

  @override
  Future<void> loadVideo(String videoId) async {
    _videoId = videoId;
    _pos = Duration.zero;
    _positionController.add(_pos);
    _durationController.add(_dur);
    _isPlaying = false;
    _isPlayingController.add(false);
  }

  @override
  Future<void> play() async {
    _isPlaying = true;
    _isPlayingController.add(true);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPlaying) return;
      _pos += const Duration(seconds: 1);
      _positionController.add(_pos);
      if (_pos >= _dur) {
        pause();
      }
    });
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    _isPlayingController.add(false);
    _ticker?.cancel();
  }

  @override
  Future<void> stop() async {
    await pause();
    _pos = Duration.zero;
    _positionController.add(_pos);
  }

  @override
  Future<void> seek(Duration position) async {
    _pos = position;
    _positionController.add(_pos);
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  void dispose() {
    _ticker?.cancel();
    _positionController.close();
    _durationController.close();
    _isPlayingController.close();
    _errorController.close();
  }
}

Widget buildPlatformYouTubeWidget({required String videoId, double? width, double? height}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Colors.black,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.play_circle_fill, color: Colors.white, size: 48),
        const SizedBox(height: 8),
        Text(
          'YouTube Video: $videoId',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    ),
  );
}
