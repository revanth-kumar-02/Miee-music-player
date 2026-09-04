import 'dart:async';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'online_playback_service.dart';

class PlatformYouTubePlaybackService implements OnlinePlaybackService {
  static final PlatformYouTubePlaybackService _instance =
      PlatformYouTubePlaybackService._internal();
  factory PlatformYouTubePlaybackService() => _instance;
  PlatformYouTubePlaybackService._internal();

  YoutubePlayerController? _controller;
  StreamSubscription<YoutubePlayerValue>? _sub;

  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _isPlayingController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String?>.broadcast();

  String? _videoId;
  String? _pendingVideoId;
  bool _pendingPlay = false;

  void attachController(YoutubePlayerController controller) {
    _sub?.cancel();
    _controller = controller;
    _sub = _controller?.stream.listen((value) {
      if (value.playerState == PlayerState.playing) {
        _isPlayingController.add(true);
      } else if (value.playerState == PlayerState.paused ||
          value.playerState == PlayerState.ended) {
        _isPlayingController.add(false);
      }

      if (value.hasError) {
        _errorController.add('Playback Error: ${value.error}');
      }
    });

    if (_pendingVideoId != null) {
      _controller?.loadVideoById(videoId: _pendingVideoId!);
      _pendingVideoId = null;
      if (_pendingPlay) {
        _controller?.playVideo();
        _pendingPlay = false;
      }
    }
  }

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
    if (_controller != null) {
      _controller!.loadVideoById(videoId: videoId);
    } else {
      _pendingVideoId = videoId;
    }
  }

  @override
  Future<void> play() async {
    if (_controller != null) {
      _controller!.playVideo();
    } else {
      _pendingPlay = true;
    }
  }

  @override
  Future<void> pause() async {
    _controller?.pauseVideo();
  }

  @override
  Future<void> stop() async {
    _controller?.pauseVideo();
  }

  @override
  Future<void> seek(Duration position) async {
    _controller?.seekTo(seconds: position.inSeconds.toDouble());
  }

  @override
  Future<void> setVolume(double volume) async {
    _controller?.setVolume((volume * 100).clamp(0, 100).toInt());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _positionController.close();
    _durationController.close();
    _isPlayingController.close();
    _errorController.close();
  }
}

Widget buildPlatformYouTubeWidget({
  required String videoId,
  double? width,
  double? height,
}) {
  return MobileYouTubeWidget(videoId: videoId, width: width, height: height);
}

class MobileYouTubeWidget extends StatefulWidget {
  final String videoId;
  final double? width;
  final double? height;

  const MobileYouTubeWidget({
    super.key,
    required this.videoId,
    this.width,
    this.height,
  });

  @override
  State<MobileYouTubeWidget> createState() => _MobileYouTubeWidgetState();
}

class _MobileYouTubeWidgetState extends State<MobileYouTubeWidget> {
  late YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: false,
        mute: false,
      ),
    );
    PlatformYouTubePlaybackService().attachController(_controller);
  }

  @override
  void didUpdateWidget(covariant MobileYouTubeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _controller.loadVideoById(videoId: widget.videoId);
    }
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width ?? double.infinity,
      height: widget.height ?? 220,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: YoutubePlayer(
          controller: _controller,
          aspectRatio: 16 / 9,
        ),
      ),
    );
  }
}
