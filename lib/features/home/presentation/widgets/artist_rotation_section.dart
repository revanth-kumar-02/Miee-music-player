import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/web_colors.dart';
import '../../../../core/audio/playback_state.dart';
import '../../../../core/audio/providers.dart';
import '../../../../shared/models/music_item.dart';
import '../../../../shared/widgets/song_tile.dart';
import '../../../onboarding/data/artist_discovery_repository.dart';
import '../../../onboarding/domain/artist_model.dart';
import '../../../recommendations/providers/recommendation_providers.dart';

/// A cross-platform section for the Home screen that rotates spotlighted artists
/// every 15 seconds, displays up to 6 tracks from the active artist, and provides
/// manual Next/Previous controls with smooth sequential fade-out/fade-in transitions
/// without disrupting audio playback.
class ArtistRotationSection extends ConsumerStatefulWidget {
  final List<ArtistSummary> artists;
  final List<MusicItem> initialTracks;
  final Duration rotationInterval;

  const ArtistRotationSection({
    super.key,
    required this.artists,
    this.initialTracks = const [],
    this.rotationInterval = const Duration(seconds: 15),
  });

  @override
  ConsumerState<ArtistRotationSection> createState() =>
      _ArtistRotationSectionState();
}

class _ArtistRotationSectionState extends ConsumerState<ArtistRotationSection>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late List<ArtistSummary> _effectiveArtists;
  final Map<String, List<MusicItem>> _tracksByArtistId = {};
  int _currentIndex = 0;
  Timer? _rotationTimer;
  bool _isLoadingTarget = false;
  bool _isTransitioning = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1.0,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.04),
      end: Offset.zero,
    ).animate(_fadeAnimation);

    _initArtists();
    _startRotationTimer();
  }

  @override
  void didUpdateWidget(covariant ArtistRotationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.artists != oldWidget.artists) {
      _initArtists();
    }
  }

  void _initArtists() {
    _effectiveArtists = widget.artists.isNotEmpty
        ? widget.artists
        : DeezerArtistRepository.staticCuratedArtists
            .take(8)
            .map((a) => a.toSummary())
            .toList();

    if (_effectiveArtists.isNotEmpty) {
      final initialArtist = _effectiveArtists.first;
      if (widget.initialTracks.isNotEmpty &&
          !_tracksByArtistId.containsKey(initialArtist.id)) {
        _tracksByArtistId[initialArtist.id] =
            widget.initialTracks.take(6).toList();
      }

      // Proactively prefetch initial artist tracks if not yet cached
      if (!_tracksByArtistId.containsKey(initialArtist.id)) {
        _fetchTracksForArtist(initialArtist).then((tracks) async {
          if (mounted && tracks.isNotEmpty) {
            if (_currentIndex == 0) {
              await _fadeController.animateTo(
                0.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInCubic,
              );
              if (!mounted) return;
              setState(() {
                _tracksByArtistId[initialArtist.id] = tracks;
              });
              await _fadeController.animateTo(
                1.0,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
              );
            } else {
              setState(() {
                _tracksByArtistId[initialArtist.id] = tracks;
              });
            }
          }
        });
      }

      // Proactively prefetch the next artist's tracks for instant rotation
      if (_effectiveArtists.length > 1) {
        _prefetchArtistTracks(1);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopRotationTimer();
    } else if (state == AppLifecycleState.resumed) {
      _startRotationTimer();
    }
  }

  void _startRotationTimer() {
    _stopRotationTimer();
    if (_effectiveArtists.length <= 1) return;

    _rotationTimer = Timer.periodic(widget.rotationInterval, (_) {
      _rotateToNext(manual: false);
    });
  }

  void _stopRotationTimer() {
    _rotationTimer?.cancel();
    _rotationTimer = null;
  }

  void _resetTimer() {
    _startRotationTimer();
  }

  Future<List<MusicItem>> _fetchTracksForArtist(ArtistSummary artist) async {
    final service = ref.read(recommendationServiceProvider);
    return service.getTracksForArtist(artist, limit: 6);
  }

  void _prefetchArtistTracks(int index) {
    if (index < 0 || index >= _effectiveArtists.length) return;
    final artist = _effectiveArtists[index];
    if (_tracksByArtistId.containsKey(artist.id)) return;

    _fetchTracksForArtist(artist).then((tracks) {
      if (mounted && tracks.isNotEmpty) {
        _tracksByArtistId[artist.id] = tracks;
      }
    }).catchError((_) {});
  }

  Future<void> _rotateToNext({required bool manual}) async {
    if (_effectiveArtists.length <= 1 || _isTransitioning) return;
    if (manual) _resetTimer();

    final nextIndex = (_currentIndex + 1) % _effectiveArtists.length;
    await _navigateToIndex(nextIndex);
  }

  Future<void> _rotateToPrevious({required bool manual}) async {
    if (_effectiveArtists.length <= 1 || _isTransitioning) return;
    if (manual) _resetTimer();

    final prevIndex =
        (_currentIndex - 1 + _effectiveArtists.length) % _effectiveArtists.length;
    await _navigateToIndex(prevIndex);
  }

  Future<void> _navigateToIndex(int targetIndex) async {
    if (_isTransitioning ||
        targetIndex == _currentIndex ||
        targetIndex < 0 ||
        targetIndex >= _effectiveArtists.length) {
      return;
    }

    final targetArtist = _effectiveArtists[targetIndex];
    List<MusicItem>? targetTracks = _tracksByArtistId[targetArtist.id];

    // If tracks for target artist are not yet cached, fetch them first while
    // keeping the current artist and tracks visible at full opacity.
    if (targetTracks == null || targetTracks.isEmpty) {
      if (mounted) setState(() => _isLoadingTarget = true);
      try {
        final fetched = await _fetchTracksForArtist(targetArtist);
        if (!mounted) return;
        if (fetched.isNotEmpty) {
          _tracksByArtistId[targetArtist.id] = fetched;
          targetTracks = fetched;
        } else {
          setState(() => _isLoadingTarget = false);
          return;
        }
      } catch (_) {
        if (mounted) setState(() => _isLoadingTarget = false);
        return;
      }
    }

    _isTransitioning = true;
    if (mounted) setState(() => _isLoadingTarget = false);

    // ── PHASE 1: Smooth Fade-Out (cleanly dissolves existing artist & tracks) ──
    await _fadeController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInCubic,
    );

    if (!mounted) {
      _isTransitioning = false;
      return;
    }

    // ── PHASE 2: Invisible Data Swap at Opacity 0.0 (prevents visual superposition) ──
    setState(() {
      _currentIndex = targetIndex;
    });

    // ── PHASE 3: Smooth Fade-In (emerges with subtle upward elevation) ──
    await _fadeController.animateTo(
      1.0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );

    _isTransitioning = false;
    _prefetchArtistTracks((targetIndex + 1) % _effectiveArtists.length);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopRotationTimer();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_effectiveArtists.isEmpty) return const SizedBox.shrink();

    final isDesktop = MediaQuery.of(context).size.width >= 960;
    final currentArtist = _effectiveArtists[_currentIndex];
    final currentTracks = _tracksByArtistId[currentArtist.id] ??
        widget.initialTracks.take(6).toList();

    final hasMultiple = _effectiveArtists.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header Row with Title, Spotlight Badge, and Nav Buttons ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'From Your Artists',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: isDesktop
                              ? MieeWebColors.textDark
                              : AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Active Artist Badge Pill with synchronized fade
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: _buildArtistPill(currentArtist, isDesktop),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Subtitle with synchronized fade
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Text(
                        'Featuring top songs by ${currentArtist.name}',
                        style: GoogleFonts.geist(
                          fontSize: 13,
                          color: isDesktop
                              ? MieeWebColors.outline
                              : AppColors.mutedMauve,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Compact Navigation Controls
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildNavButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: 'Previous artist',
                  enabled: hasMultiple && !_isTransitioning && !_isLoadingTarget,
                  isDesktop: isDesktop,
                  onPressed: () => _rotateToPrevious(manual: true),
                ),
                const SizedBox(width: 6),
                _buildNavButton(
                  icon: Icons.chevron_right_rounded,
                  tooltip: 'Next artist',
                  enabled: hasMultiple && !_isTransitioning && !_isLoadingTarget,
                  isDesktop: isDesktop,
                  onPressed: () => _rotateToNext(manual: true),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 14),

        // ── Smooth Animated Track List ──
        FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: _buildTrackList(currentTracks),
          ),
        ),

        const SizedBox(height: 36),
      ],
    );
  }

  Widget _buildArtistPill(ArtistSummary artist, bool isDesktop) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDesktop
            ? MieeWebColors.surfaceLowest
            : AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDesktop
              ? MieeWebColors.subtleBorder
              : AppColors.oatBeige,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (artist.imageUrl.isNotEmpty) ...[
            ClipOval(
              child: Image.network(
                artist.imageUrl,
                width: 16,
                height: 16,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.person_rounded,
                  size: 14,
                  color: isDesktop
                      ? MieeWebColors.outline
                      : AppColors.mutedMauve,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDesktop
                    ? MieeWebColors.textDark
                    : AppColors.onSurface,
              ),
            ),
          ),
          if (_effectiveArtists.length > 1) ...[
            const SizedBox(width: 4),
            Text(
              '${_currentIndex + 1}/${_effectiveArtists.length}',
              style: GoogleFonts.geist(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: isDesktop
                    ? MieeWebColors.outline
                    : AppColors.mutedMauve,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required bool isDesktop,
    required VoidCallback onPressed,
  }) {
    final bgColor = isDesktop
        ? (enabled
            ? MieeWebColors.surfaceLowest
            : MieeWebColors.surfaceLowest.withValues(alpha: 0.45))
        : (enabled
            ? AppColors.surfaceContainerLow
            : AppColors.surfaceContainerLow.withValues(alpha: 0.45));

    final borderColor = isDesktop
        ? (enabled
            ? MieeWebColors.subtleBorder
            : MieeWebColors.subtleBorder.withValues(alpha: 0.3))
        : (enabled
            ? AppColors.oatBeige
            : AppColors.oatBeige.withValues(alpha: 0.3));

    final iconColor = isDesktop
        ? (enabled
            ? MieeWebColors.onSurfaceVariant
            : MieeWebColors.outline.withValues(alpha: 0.35))
        : (enabled
            ? AppColors.onSurface
            : AppColors.mutedMauve.withValues(alpha: 0.35));

    return Tooltip(
      message: enabled ? tooltip : '',
      waitDuration: const Duration(milliseconds: 500),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bgColor,
          border: Border.all(color: borderColor),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            hoverColor: isDesktop
                ? MieeWebColors.surfaceContainerHigh
                : AppColors.surfaceContainerHigh,
            onTap: enabled ? onPressed : null,
            child: Center(
              child: Icon(icon, size: 20, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackList(List<MusicItem> tracks) {
    if (tracks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.dustyRose),
            ),
          ),
        ),
      );
    }

    final currentTrack = ref.watch(
      playerControllerProvider.select((s) => s.currentTrack),
    );

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tracks.take(6).length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final track = tracks[index];
        final isPlaying = currentTrack?.id == track.id;

        return Consumer(
          builder: (context, ref, _) {
            final isTrackLoading = ref.watch(
              playerControllerProvider.select((s) =>
                  s.loadingTrackId != null &&
                  isSameTrackId(s.loadingTrackId, track.id)),
            );

            return SongTile(
              title: track.title,
              artist: track.artist,
              duration: track.duration,
              imageUrl: track.imageUrl,
              isPlaying: isPlaying,
              isLoading: isTrackLoading,
              onTap: isTrackLoading
                  ? null
                  : () {
                      ref
                          .read(playerControllerProvider.notifier)
                          .selectTrack(track, tracks,
                              playingFrom: 'From Your Artists');
                    },
            );
          },
        );
      },
    );
  }
}
