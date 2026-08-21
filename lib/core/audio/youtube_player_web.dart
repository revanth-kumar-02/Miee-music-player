import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'online_playback_service.dart';

class PlatformYouTubePlaybackService implements OnlinePlaybackService {
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _isPlayingController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String?>.broadcast();

  String? _videoId;
  bool _isPlaying = false;
  Timer? _positionTimer;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;

  html.IFrameElement? _iframe;

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
    _isPlaying = false;
    _isPlayingController.add(false);

    // If iframe exists, postMessage or reload src
    if (_iframe != null) {
      _iframe!.src = _getEmbedUrl(videoId);
    }
  }

  String _getEmbedUrl(String videoId) {
    return 'https://www.youtube.com/embed/$videoId?enablejsapi=1&autoplay=1&controls=1&modestbranding=1&rel=0';
  }

  void attachIFrame(html.IFrameElement iframe) {
    _iframe = iframe;
  }

  @override
  Future<void> play() async {
    _isPlaying = true;
    _isPlayingController.add(true);
    _sendCommand('playVideo');
    _startPositionTimer();
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    _isPlayingController.add(false);
    _sendCommand('pauseVideo');
    _positionTimer?.cancel();
  }

  @override
  Future<void> stop() async {
    await pause();
    _sendCommand('stopVideo');
    _pos = Duration.zero;
    _positionController.add(_pos);
  }

  @override
  Future<void> seek(Duration position) async {
    _pos = position;
    _positionController.add(_pos);
    _sendCommand('seekTo', [position.inSeconds, true]);
  }

  @override
  Future<void> setVolume(double volume) async {
    final volInt = (volume * 100).clamp(0, 100).toInt();
    _sendCommand('setVolume', [volInt]);
  }

  void _sendCommand(String func, [List<dynamic>? args]) {
    if (_iframe?.contentWindow == null) return;
    final payload = {
      'event': 'command',
      'func': func,
      'args': args ?? [],
    };
    _iframe!.contentWindow!.postMessage(payload, '*');
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPlaying) return;
      _pos += const Duration(seconds: 1);
      _positionController.add(_pos);
    });
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _positionController.close();
    _durationController.close();
    _isPlayingController.close();
    _errorController.close();
  }
}

Widget buildPlatformYouTubeWidget({required String videoId, double? width, double? height}) {
  final viewId = 'miee-yt-player-$videoId';

  ui_web.platformViewRegistry.registerViewFactory(
    viewId,
    (int id) {
      final iframe = html.IFrameElement()
        ..src = 'https://www.youtube.com/embed/$videoId?enablejsapi=1&autoplay=1&controls=1&modestbranding=1&rel=0'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture';
      return iframe;
    },
  );

  return SizedBox(
    width: width ?? double.infinity,
    height: height ?? double.infinity,
    child: HtmlElementView(viewType: viewId),
  );
}
