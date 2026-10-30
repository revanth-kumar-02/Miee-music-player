import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/audio/playback_state.dart';
import '../../../../core/audio/providers.dart';
import '../../../../shared/models/music_item.dart';

/// Interactive Dynamic Island for Miee matching OriginOS / Atomic Island aesthetics.
///
/// Anchors at the top status bar around the front hole-punch camera.
/// - Collapsed State: Sleek 196dp x 36dp black capsule with spinning album disc,
///   scrolling title, and 3-bar animated sound visualizer.
/// - Expanded State: 340dp x 144dp floating card on long-press with full controls.
class MieeDynamicIsland extends ConsumerStatefulWidget {
  const MieeDynamicIsland({super.key});

  @override
  ConsumerState<MieeDynamicIsland> createState() => _MieeDynamicIslandState();
}

class _MieeDynamicIslandState extends ConsumerState<MieeDynamicIsland>
    with TickerProviderStateMixin {
  bool _isExpanded = false;

  late final AnimationController _rotationController;
  late final AnimationController _waveController;

  bool get _isTesting => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    if (!_isTesting) {
      _rotationController.repeat();
      _waveController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  void _expand() {
    HapticFeedback.mediumImpact();
    setState(() => _isExpanded = true);
  }

  void _collapse() {
    HapticFeedback.lightImpact();
    setState(() => _isExpanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(playerControllerProvider);
    final track = playback.currentTrack;
    final isPlaying = playback.status == PlaybackStatus.playing;

    if (track == null) return const SizedBox.shrink();

    // Pause/resume rotational visualizer based on playing state (skipped in widget tests to avoid infinite frames)
    if (!_isTesting) {
      if (!isPlaying && _rotationController.isAnimating) {
        _rotationController.stop();
        _waveController.stop();
      } else if (isPlaying && !_rotationController.isAnimating) {
        _rotationController.repeat();
        _waveController.repeat(reverse: true);
      }
    }

    final topInset = MediaQuery.of(context).padding.top;

    return Center(
      child: GestureDetector(
        onTap: () {
          if (_isExpanded) {
            _collapse();
          } else {
            HapticFeedback.lightImpact();
            context.push('/player');
          }
        },
        onLongPress: _isExpanded ? null : _expand,
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity;
          if (velocity != null) {
            if (velocity > 200 && !_isExpanded) {
              _expand();
            } else if (velocity < -200 && _isExpanded) {
              _collapse();
            }
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          margin: EdgeInsets.only(top: math.max(topInset - 4, 6)),
          width: _isExpanded ? 340 : 196,
          height: _isExpanded ? 144 : 36,
          decoration: BoxDecoration(
            color: const Color(0xFF0F080A),
            borderRadius: BorderRadius.circular(_isExpanded ? 26 : 18),
            border: Border.all(
              color: AppColors.white.withValues(alpha: 0.14),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _isExpanded ? 0.65 : 0.35),
                blurRadius: _isExpanded ? 24 : 12,
                spreadRadius: _isExpanded ? 2 : 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _isExpanded
                ? _buildExpandedContent(track, playback, isPlaying)
                : _buildCollapsedContent(track, isPlaying),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedContent(MusicItem track, bool isPlaying) {
    return Padding(
      key: const ValueKey('collapsed_island'),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Spinning album disc
          RotationTransition(
            turns: _rotationController,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
                border: Border.all(color: Colors.white24, width: 0.8),
              ),
              child: ClipOval(
                child: _buildDiscArtwork(track.imageUrl),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 2. Song Title
          Expanded(
            child: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.geist(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFFFFDF9),
                letterSpacing: 0.1,
              ),
            ),
          ),
          const SizedBox(width: 6),

          // 3. Audio equalizing bars
          _buildVisualizerBars(isPlaying),
        ],
      ),
    );
  }

  Widget _buildVisualizerBars(bool isPlaying) {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, _) {
        final val = _waveController.value;
        final h1 = isPlaying ? 5.0 + (val * 8.0) : 4.0;
        final h2 = isPlaying ? 12.0 - (val * 7.0) : 7.0;
        final h3 = isPlaying ? 6.0 + (val * 6.0) : 4.0;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bar(h1),
            const SizedBox(width: 2),
            _bar(h2),
            const SizedBox(width: 2),
            _bar(h3),
          ],
        );
      },
    );
  }

  Widget _bar(double height) {
    return Container(
      width: 2.2,
      height: height.clamp(3.0, 14.0),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }

  Widget _buildExpandedContent(MusicItem track, PlaybackState playback, bool isPlaying) {
    final playerCtrl = ref.read(playerControllerProvider.notifier);

    final posStr = _formatDuration(playback.position);
    final totalStr = _formatDuration(playback.duration);
    final progress = playback.duration.inMilliseconds > 0
        ? (playback.position.inMilliseconds / playback.duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      key: const ValueKey('expanded_island'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top row: Art, Title/Artist, Close Button
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 44,
                  height: 44,
                  color: AppColors.primary.withValues(alpha: 0.2),
                  child: _buildExpandedArtwork(track.imageUrl),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.geist(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFFFFDF9),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.geist(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFC4A8B0),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white54, size: 24),
                onPressed: _collapse,
              ),
            ],
          ),
          const Spacer(),

          // Progress bar
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3.5,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(posStr, style: GoogleFonts.geist(fontSize: 10, color: Colors.white54)),
                  Text(totalStr, style: GoogleFonts.geist(fontSize: 10, color: Colors.white54)),
                ],
              ),
            ],
          ),
          const Spacer(),

          // Playback control row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                iconSize: 22,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                color: Colors.white,
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  playerCtrl.previous();
                },
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  if (isPlaying) {
                    playerCtrl.pause();
                  } else {
                    playerCtrl.play();
                  }
                },
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
              IconButton(
                iconSize: 22,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                color: Colors.white,
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  playerCtrl.next();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiscArtwork(String imageUrl) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (imageUrl.isNotEmpty &&
            (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')))
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            width: 22,
            height: 22,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.music_note_rounded, size: 12, color: Colors.white),
            ),
          )
        else
          const Center(
            child: Icon(Icons.music_note_rounded, size: 12, color: Colors.white),
          ),
        // Vinyl center spindle hole
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF0F080A),
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedArtwork(String imageUrl) {
    if (imageUrl.isNotEmpty &&
        (imageUrl.startsWith('http://') || imageUrl.startsWith('https://'))) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: 44,
        height: 44,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.music_note_rounded, color: AppColors.primary),
        ),
      );
    }
    return const Center(
      child: Icon(Icons.music_note_rounded, color: AppColors.primary),
    );
  }

  static String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
