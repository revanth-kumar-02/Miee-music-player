import 'dart:ui';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/midnight_velvet_tokens.dart';
import '../../../../core/audio/playback_state.dart';
import '../../../../core/audio/providers.dart';
import '../../../../features/artwork/presentation/miee_artwork_image.dart';
import '../../../../features/lyrics/domain/lyrics_model.dart';
import '../../../../features/lyrics/providers/lyrics_providers.dart';
import '../../../../shared/models/music_item.dart';
import '../../../../shared/widgets/desktop_waveform_scrubber.dart';

enum StudioColorPreset {
  dynamicSync('Dynamic Sync', Color(0xFFFF385C)),
  emberRed('Ember Red', Color(0xFFFF385C)),
  champagneGold('Champagne Gold', Color(0xFFF59E0B)),
  neonCyan('Neon Cyan', Color(0xFF06B6D4)),
  nordicViolet('Nordic Violet', Color(0xFF8B5CF6)),
  pureSilver('Pure Silver', Color(0xFFE0D9D5));

  final String label;
  final Color color;
  const StudioColorPreset(this.label, this.color);
}

/// The dedicated Desktop "Now Spinning" Studio Master Stage.
/// Features a steady and sharp ambient perimeter color line, deep optical Ambilight
/// backlight halo, cardless floating playback controls, medium-width tactile waveform scrubber,
/// synchronized lyrics view, and a frosted glass Studio Lighting & Tuner drawer.
class StudioNowSpinningView extends ConsumerStatefulWidget {
  final VoidCallback? onOpenCatalog;

  const StudioNowSpinningView({
    super.key,
    this.onOpenCatalog,
  });

  @override
  ConsumerState<StudioNowSpinningView> createState() => _StudioNowSpinningViewState();
}

class _StudioNowSpinningViewState extends ConsumerState<StudioNowSpinningView> {
  // Studio Tuner State
  bool _isTunerOpen = false;
  double _rimIntensity = 0.85;
  double _lineThickness = 1.5;
  double _haloDiffusion = 60.0;
  StudioColorPreset _selectedPreset = StudioColorPreset.dynamicSync;

  // Lyrics toggle state
  bool _showLyrics = false;
  final ScrollController _lyricsScrollController = ScrollController();

  @override
  void dispose() {
    _lyricsScrollController.dispose();
    super.dispose();
  }

  Color _resolveActiveColor(dynamic track) {
    if (_selectedPreset != StudioColorPreset.dynamicSync) {
      return _selectedPreset.color;
    }
    if (track == null) return MidnightVelvetTokens.amberChampagne;

    final title = track.title.toString().toLowerCase();
    final artist = track.artist.toString().toLowerCase();

    // Deterministic hue mapping from track identity for dynamic sync
    final hash = (title.hashCode ^ artist.hashCode).abs();
    final palette = [
      const Color(0xFFFF385C), // Ember Red
      const Color(0xFFF59E0B), // Champagne Gold
      const Color(0xFF06B6D4), // Neon Cyan
      const Color(0xFF8B5CF6), // Nordic Violet
      const Color(0xFF10B981), // Emerald
    ];
    return palette[hash % palette.length];
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final playbackState = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final currentTrack = playbackState.currentTrack;
    final isPlaying = playbackState.status == PlaybackStatus.playing;
    final position = playbackState.position;
    final duration = playbackState.duration;

    final activeColor = _resolveActiveColor(currentTrack);
    final totalMs = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final progress = (position.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: MidnightVelvetTokens.canvasBase,
      body: Stack(
        children: [
          // 1. Steady & Sharp Ambient Perimeter Rim (Color Line)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: activeColor.withValues(alpha: _rimIntensity),
                    width: _lineThickness,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: activeColor.withValues(alpha: _rimIntensity * 0.45),
                      blurRadius: 20.0,
                      spreadRadius: 1.0,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. Main Centerpiece Stage Area
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Top Status Action Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Back to Catalog Pill
                      InkWell(
                        onTap: widget.onOpenCatalog,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: MidnightVelvetTokens.surfaceCard,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: MidnightVelvetTokens.hairlineRim,
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.grid_view_rounded,
                                size: 14,
                                color: MidnightVelvetTokens.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'STUDIO CATALOG',
                                style: MidnightVelvetTokens.fontMonoTelemetry.copyWith(
                                  fontSize: 10,
                                  color: MidnightVelvetTokens.textSecondary,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Tuner Drawer Toggle Button
                      InkWell(
                        onTap: () => setState(() => _isTunerOpen = !_isTunerOpen),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _isTunerOpen
                                ? activeColor.withValues(alpha: 0.2)
                                : MidnightVelvetTokens.surfaceCard,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isTunerOpen ? activeColor : MidnightVelvetTokens.hairlineRim,
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 14,
                                color: _isTunerOpen ? activeColor : MidnightVelvetTokens.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'STUDIO TUNER',
                                style: MidnightVelvetTokens.fontMonoTelemetry.copyWith(
                                  fontSize: 10,
                                  color: _isTunerOpen ? activeColor : MidnightVelvetTokens.textSecondary,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Center Stage: Album Artwork or Synced Lyrics
                  if (!_showLyrics)
                    _buildAlbumArtworkHero(currentTrack, activeColor)
                  else
                    _buildSyncedLyricsStage(currentTrack, activeColor),

                  const SizedBox(height: 24),

                  // Track Title and Artist Name (Clean, NO badge text below)
                  Text(
                    currentTrack?.title ?? 'No Track Spinning',
                    style: MidnightVelvetTokens.fontDisplayMedium.copyWith(
                      fontSize: 24,
                      color: MidnightVelvetTokens.textDisplay,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    currentTrack?.artist ?? 'Select a record to start session',
                    style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                      fontSize: 14,
                      color: MidnightVelvetTokens.textSecondary,
                      letterSpacing: 0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 22),

                  // Medium-width Balanced Waveform Scrubber with Dual Timecodes
                  SizedBox(
                    width: 520,
                    child: Row(
                      children: [
                        Text(
                          _formatDuration(position),
                          style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                            fontSize: 11,
                            color: MidnightVelvetTokens.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DiscreteWaveformScrubber(
                            progress: progress,
                            isPlaying: isPlaying,
                            height: 30.0,
                            barWidth: 3.2,
                            barSpacing: 2.8,
                            playedColor: activeColor,
                            unplayedColor: MidnightVelvetTokens.hairlineRimHighlight,
                            onSeek: (fraction) {
                              if (duration.inMilliseconds > 0) {
                                final targetMs = (fraction * duration.inMilliseconds).toInt();
                                controller.seek(Duration(milliseconds: targetMs));
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _formatDuration(duration),
                          style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                            fontSize: 11,
                            color: MidnightVelvetTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Seamless Floating Playback Controls (NO Card Box Background)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Shuffle
                      IconButton(
                        icon: const Icon(Icons.shuffle_rounded),
                        color: playbackState.isShuffleEnabled
                            ? activeColor
                            : MidnightVelvetTokens.textMuted,
                        iconSize: 20,
                        onPressed: () => controller.toggleShuffle(),
                        tooltip: 'Shuffle',
                        splashRadius: 20,
                      ),
                      const SizedBox(width: 14),

                      // Previous
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded),
                        color: MidnightVelvetTokens.textDisplay,
                        iconSize: 26,
                        onPressed: () => controller.previous(),
                        tooltip: 'Previous Track',
                        splashRadius: 22,
                      ),
                      const SizedBox(width: 16),

                      // Ember Circular Play/Pause Button
                      GestureDetector(
                        onTap: () => controller.togglePlayPause(),
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: activeColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: activeColor.withValues(alpha: 0.5),
                                blurRadius: 18.0,
                                spreadRadius: 1.0,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Next
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded),
                        color: MidnightVelvetTokens.textDisplay,
                        iconSize: 26,
                        onPressed: () => controller.next(),
                        tooltip: 'Next Track',
                        splashRadius: 22,
                      ),
                      const SizedBox(width: 14),

                      // Repeat
                      IconButton(
                        icon: Icon(
                          playbackState.repeatMode == RepeatMode.one
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                        ),
                        color: playbackState.repeatMode != RepeatMode.off
                            ? activeColor
                            : MidnightVelvetTokens.textMuted,
                        iconSize: 20,
                        onPressed: () => controller.toggleRepeatMode(),
                        tooltip: 'Repeat Mode',
                        splashRadius: 20,
                      ),
                      const SizedBox(width: 18),

                      // Dedicated Lyrics Action Button
                      TextButton.icon(
                        onPressed: () => setState(() => _showLyrics = !_showLyrics),
                        icon: Icon(
                          _showLyrics ? Icons.album_rounded : Icons.lyrics_rounded,
                          size: 16,
                          color: _showLyrics ? activeColor : MidnightVelvetTokens.textDisplay,
                        ),
                        label: Text(
                          _showLyrics ? 'Sleeve' : 'Lyrics',
                          style: MidnightVelvetTokens.fontMonoTelemetry.copyWith(
                            fontSize: 11,
                            color: _showLyrics ? activeColor : MidnightVelvetTokens.textDisplay,
                            letterSpacing: 0.8,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: _showLyrics
                              ? activeColor.withValues(alpha: 0.15)
                              : MidnightVelvetTokens.surfaceCard,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: _showLyrics ? activeColor : MidnightVelvetTokens.hairlineRim,
                              width: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 3. Frosted Glass Studio Lighting & Tuner Drawer (Right Side)
          if (_isTunerOpen)
            Positioned(
              top: 24,
              right: 24,
              bottom: 110,
              width: 320,
              child: _buildStudioTunerDrawer(activeColor),
            ),
        ],
      ),
    );
  }

  Widget _buildAlbumArtworkHero(MusicItem? track, Color activeColor) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Deep Atmospheric Gaussian Halo
        Container(
          width: 280,
          height: 280,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: activeColor.withValues(alpha: 0.35),
                blurRadius: _haloDiffusion,
                spreadRadius: 20.0,
              ),
            ],
          ),
        ),

        // Floating Master Album Sleeve
        Container(
          width: 300,
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: MidnightVelvetTokens.hairlineRimHighlight,
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.65),
                blurRadius: 36.0,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: track != null
                ? MieeArtworkImage(
                    musicItem: track,
                    width: 300,
                    height: 300,
                    fit: BoxFit.cover,
                  )
                : Container(
                    color: MidnightVelvetTokens.surfaceCard,
                    child: const Icon(
                      Icons.album_rounded,
                      size: 96,
                      color: MidnightVelvetTokens.textMuted,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSyncedLyricsStage(MusicItem? track, Color activeColor) {
    if (track == null) {
      return Container(
        width: 480,
        height: 300,
        alignment: Alignment.center,
        child: Text(
          'No track selected for lyrics',
          style: MidnightVelvetTokens.fontBodyMedium.copyWith(color: MidnightVelvetTokens.textMuted),
        ),
      );
    }

    final lyricsAsync = ref.watch(lyricsProvider(track));

    return Container(
      width: 480,
      height: 300,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: MidnightVelvetTokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MidnightVelvetTokens.hairlineRim,
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 24.0,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: lyricsAsync.when(
        data: (LyricsData lyrics) {
          if (lyrics.isEmpty) {
            return Center(
              child: Text(
                'Synchronized lyrics unavailable for this track',
                style: MidnightVelvetTokens.fontBodyMedium.copyWith(color: MidnightVelvetTokens.textMuted),
              ),
            );
          }

          final currentPos = ref.watch(playerControllerProvider).position;

          return ListView.builder(
            controller: _lyricsScrollController,
            itemCount: lyrics.lines.length,
            itemBuilder: (context, index) {
              final line = lyrics.lines[index];
              final isCurrent = index < lyrics.lines.length - 1
                  ? (currentPos >= line.time && currentPos < lyrics.lines[index + 1].time)
                  : currentPos >= line.time;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  line.text,
                  style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                    fontSize: isCurrent ? 17 : 14,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                    color: isCurrent ? activeColor : MidnightVelvetTokens.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: MidnightVelvetTokens.amberChampagne,
          ),
        ),
        error: (_, __) => Center(
          child: Text(
            'Unable to load lyrics',
            style: MidnightVelvetTokens.fontBodyMedium.copyWith(color: MidnightVelvetTokens.textMuted),
          ),
        ),
      ),
    );
  }

  Widget _buildStudioTunerDrawer(Color activeColor) {
    return BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: MidnightVelvetTokens.glassBlurSigma,
        sigmaY: MidnightVelvetTokens.glassBlurSigma,
      ),
      child: Container(
        width: 320,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: MidnightVelvetTokens.surfaceCard.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: MidnightVelvetTokens.hairlineRimHighlight,
            width: 1.0,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 24.0,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drawer Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'STUDIO LIGHTING & TUNER',
                      style: MidnightVelvetTokens.fontSectionTitle.copyWith(
                        fontSize: 12,
                        letterSpacing: 1.4,
                        color: MidnightVelvetTokens.textDisplay,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: MidnightVelvetTokens.textSecondary,
                    onPressed: () => setState(() => _isTunerOpen = false),
                    splashRadius: 16,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Slider 1: Rim Glow Intensity
              Text(
                'Rim Glow Intensity (${(_rimIntensity * 100).toInt()}%)',
                style: MidnightVelvetTokens.fontBodyMedium.copyWith(fontSize: 12, color: MidnightVelvetTokens.textSecondary),
              ),
              Slider(
                value: _rimIntensity,
                min: 0.1,
                max: 1.0,
                activeColor: activeColor,
                inactiveColor: MidnightVelvetTokens.hairlineRim,
                onChanged: (val) => setState(() => _rimIntensity = val),
              ),

              const SizedBox(height: 10),

              // Slider 2: Line Thickness
              Text(
                'Line Thickness (${_lineThickness.toStringAsFixed(1)}px)',
                style: MidnightVelvetTokens.fontBodyMedium.copyWith(fontSize: 12, color: MidnightVelvetTokens.textSecondary),
              ),
              Slider(
                value: _lineThickness,
                min: 1.0,
                max: 3.5,
                activeColor: activeColor,
                inactiveColor: MidnightVelvetTokens.hairlineRim,
                onChanged: (val) => setState(() => _lineThickness = val),
              ),

              const SizedBox(height: 10),

              // Slider 3: Halo Diffusion
              Text(
                'Halo Diffusion (${_haloDiffusion.toInt()}px)',
                style: MidnightVelvetTokens.fontBodyMedium.copyWith(fontSize: 12, color: MidnightVelvetTokens.textSecondary),
              ),
              Slider(
                value: _haloDiffusion,
                min: 10.0,
                max: 90.0,
                activeColor: activeColor,
                inactiveColor: MidnightVelvetTokens.hairlineRim,
                onChanged: (val) => setState(() => _haloDiffusion = val),
              ),

              const SizedBox(height: 16),

              // Color Preset Chips
              Text(
                'Color Presets',
                style: MidnightVelvetTokens.fontBodyMedium.copyWith(fontSize: 12, color: MidnightVelvetTokens.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: StudioColorPreset.values.map((preset) {
                  final isSelected = _selectedPreset == preset;
                  return InkWell(
                    onTap: () => setState(() => _selectedPreset = preset),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? preset.color.withValues(alpha: 0.25)
                            : MidnightVelvetTokens.canvasBase,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? preset.color : MidnightVelvetTokens.hairlineRim,
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: preset.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            preset.label,
                            style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                              fontSize: 10,
                              color: isSelected ? MidnightVelvetTokens.textDisplay : MidnightVelvetTokens.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),

              // Audio Engine DSP Telemetry
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MidnightVelvetTokens.canvasBase,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: MidnightVelvetTokens.hairlineRim,
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AUDIO ENGINE STATUS',
                      style: MidnightVelvetTokens.fontMonoTelemetry.copyWith(
                        fontSize: 9,
                        color: MidnightVelvetTokens.amberChampagne,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '32-bit Float Internal Processing Bus',
                      style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                        fontSize: 10,
                        color: MidnightVelvetTokens.textDisplay,
                      ),
                    ),
                    Text(
                      'Headroom Guard: -0.1 dB Active',
                      style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                        fontSize: 10,
                        color: MidnightVelvetTokens.textMuted,
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
