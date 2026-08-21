import 'package:flutter/material.dart';
import 'online_playback_service.dart';

import 'youtube_player_stub.dart'
    if (dart.library.html) 'youtube_player_web.dart' as platform;

/// Factory function to get the platform-specific OnlinePlaybackService.
OnlinePlaybackService createOnlinePlaybackService() {
  return platform.PlatformYouTubePlaybackService();
}

/// Visible embedded YouTube player widget.
///
/// On Web, this renders an [HtmlElementView] embedding the official YouTube IFrame player.
/// On Mobile, this renders the platform video container widget.
class MieeYouTubePlayerWidget extends StatelessWidget {
  final String videoId;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const MieeYouTubePlayerWidget({
    super.key,
    required this.videoId,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final player = platform.buildPlatformYouTubeWidget(
      videoId: videoId,
      width: width,
      height: height,
    );

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: player,
      );
    }

    return player;
  }
}
