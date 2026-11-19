import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/midnight_velvet_tokens.dart';
import '../../../../core/audio/playback_state.dart';
import '../../../../core/audio/providers.dart';
import '../../../../features/artwork/presentation/miee_artwork_image.dart';
import '../../../../features/library/providers/library_providers.dart';
import '../../../../shared/models/track.dart';
import 'studio_audio_output_modal.dart';

class MasterTransportDeck extends ConsumerWidget {
  final VoidCallback? onToggleQueue;
  final VoidCallback? onToggleOutput;

  const MasterTransportDeck({
    super.key,
    this.onToggleQueue,
    this.onToggleOutput,
  });

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackState = ref.watch(playerControllerProvider);
    final currentTrack = playbackState.currentTrack;
    final isPlaying = playbackState.status == PlaybackStatus.playing;
    final position = playbackState.position;
    final duration = playbackState.duration;
    final controller = ref.read(playerControllerProvider.notifier);
    final favorites = ref.watch(favoritesProvider);
    final isFavorite = currentTrack != null && favorites.any((t) => t.id == currentTrack.id);

    final posMs = position.inMilliseconds.toDouble();
    final durMs = duration.inMilliseconds.toDouble();
    final clampedPos = durMs > 0 ? posMs.clamp(0.0, durMs) : 0.0;

    return Container(
      height: MidnightVelvetTokens.masterDeckHeight,
      margin: const EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MidnightVelvetTokens.masterDeckBottomMargin,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: MidnightVelvetTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MidnightVelvetTokens.hairlineRimHighlight,
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: MidnightVelvetTokens.glassBlurSigma,
            sigmaY: MidnightVelvetTokens.glassBlurSigma,
          ),
          child: Row(
            children: [
              // 1. Current Track Meta & Cover (Left)
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    // 52px Album Sleeve
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: currentTrack != null
                            ? MieeArtworkImage(
                                musicItem: currentTrack,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: MidnightVelvetTokens.surfaceCard,
                                child: const Icon(
                                  Icons.music_note_rounded,
                                  color: MidnightVelvetTokens.textSecondary,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentTrack?.displayTitle ?? 'No Active Master',
                            style: MidnightVelvetTokens.fontSectionTitle.copyWith(
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            currentTrack?.artist ?? 'Select a session track',
                            style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                              fontSize: 12,
                              color: MidnightVelvetTokens.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: isFavorite
                            ? MidnightVelvetTokens.primaryEmber
                            : MidnightVelvetTokens.textSecondary,
                        size: 20,
                      ),
                      onPressed: (currentTrack != null && currentTrack is Track)
                          ? () {
                              final favNotifier = ref.read(favoritesProvider.notifier);
                              if (isFavorite) {
                                favNotifier.removeFavorite(currentTrack.id);
                              } else {
                                favNotifier.addFavorite(currentTrack);
                              }
                            }
                          : null,
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),

              // 2. Transport & Playback Scrubbing (Center)
              Expanded(
                flex: 5,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Buttons Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.shuffle_rounded),
                          color: MidnightVelvetTokens.textSecondary,
                          iconSize: 18,
                          onPressed: () => controller.toggleShuffle(),
                          splashRadius: 18,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.skip_previous_rounded),
                          color: MidnightVelvetTokens.textDisplay,
                          iconSize: 22,
                          onPressed: () => controller.previous(),
                          splashRadius: 20,
                        ),
                        const SizedBox(width: 12),
                        // Central Ember Capsule
                        GestureDetector(
                          onTap: () => controller.togglePlayPause(),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: MidnightVelvetTokens.emberButton(
                              radius: 22,
                              isHovered: false,
                            ),
                            child: Icon(
                              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded),
                          color: MidnightVelvetTokens.textDisplay,
                          iconSize: 22,
                          onPressed: () => controller.next(),
                          splashRadius: 20,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.repeat_rounded),
                          color: MidnightVelvetTokens.textSecondary,
                          iconSize: 18,
                          onPressed: () => controller.toggleRepeatMode(),
                          splashRadius: 18,
                        ),
                      ],
                    ),

                    // Timecode and Slider Scrub Line
                    Row(
                      children: [
                        Text(
                          _formatDuration(position),
                          style: MidnightVelvetTokens.fontMonoTimecode.copyWith(fontSize: 10),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SliderTheme(
                            data: const SliderThemeData(
                              trackHeight: 3.0,
                              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5.0),
                              overlayShape: RoundSliderOverlayShape(overlayRadius: 10.0),
                              activeTrackColor: MidnightVelvetTokens.amberChampagne,
                              inactiveTrackColor: MidnightVelvetTokens.hairlineRimHighlight,
                              thumbColor: MidnightVelvetTokens.textDisplay,
                              overlayColor: MidnightVelvetTokens.glowAmberLow,
                            ),
                            child: Slider(
                              value: clampedPos,
                              min: 0.0,
                              max: durMs > 0 ? durMs : 1.0,
                              onChanged: durMs > 0
                                  ? (val) => controller.seek(Duration(milliseconds: val.toInt()))
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDuration(duration),
                          style: MidnightVelvetTokens.fontMonoTimecode.copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 3. Audio Routing & Volume (Right)
              Expanded(
                flex: 3,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.queue_music_rounded),
                      color: MidnightVelvetTokens.textSecondary,
                      iconSize: 20,
                      tooltip: 'Session Queue',
                      onPressed: onToggleQueue,
                      splashRadius: 18,
                    ),
                    IconButton(
                      icon: const Icon(Icons.speaker_group_outlined),
                      color: MidnightVelvetTokens.textSecondary,
                      iconSize: 20,
                      tooltip: 'Audio Output & DAC',
                      onPressed: () {
                        if (onToggleOutput != null) {
                          onToggleOutput!();
                        } else {
                          StudioAudioOutputModal.show(context);
                        }
                      },
                      splashRadius: 18,
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.volume_up_rounded,
                      size: 18,
                      color: MidnightVelvetTokens.textSecondary,
                    ),
                    SizedBox(
                      width: 90,
                      child: SliderTheme(
                        data: const SliderThemeData(
                          trackHeight: 3.0,
                          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 4.0),
                          overlayShape: RoundSliderOverlayShape(overlayRadius: 8.0),
                          activeTrackColor: MidnightVelvetTokens.textDisplay,
                          inactiveTrackColor: MidnightVelvetTokens.hairlineRim,
                          thumbColor: MidnightVelvetTokens.textDisplay,
                        ),
                        child: Slider(
                          value: playbackState.volume.clamp(0.0, 1.0),
                          min: 0.0,
                          max: 1.0,
                          onChanged: (val) {
                            controller.setVolume(val);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
