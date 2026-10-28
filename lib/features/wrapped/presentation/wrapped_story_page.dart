import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../../app/theme/app_colors.dart';
import '../domain/wrapped_models.dart';
import '../providers/wrapped_providers.dart';

class WrappedStoryPage extends ConsumerStatefulWidget {
  const WrappedStoryPage({super.key});

  @override
  ConsumerState<WrappedStoryPage> createState() => _WrappedStoryPageState();
}

class _WrappedStoryPageState extends ConsumerState<WrappedStoryPage>
    with SingleTickerProviderStateMixin {
  static const int _totalSlides = 7;
  static const Duration _slideDuration = Duration(seconds: 6);

  int _currentSlide = 0;
  late AnimationController _progressController;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: _slideDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _advanceSlide();
        }
      });

    _progressController.forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _advanceSlide() {
    if (_currentSlide < _totalSlides - 1) {
      setState(() {
        _currentSlide++;
      });
      _progressController.reset();
      _progressController.forward();
      HapticFeedback.lightImpact();
    } else {
      _progressController.stop();
    }
  }

  void _previousSlide() {
    if (_currentSlide > 0) {
      setState(() {
        _currentSlide--;
      });
      _progressController.reset();
      _progressController.forward();
      HapticFeedback.lightImpact();
    } else {
      _progressController.reset();
      _progressController.forward();
    }
  }

  void _pauseTimer() {
    if (!_isPaused) {
      _isPaused = true;
      _progressController.stop();
    }
  }

  void _resumeTimer() {
    if (_isPaused) {
      _isPaused = false;
      if (_currentSlide < _totalSlides - 1 || _progressController.value < 1.0) {
        _progressController.forward();
      }
    }
  }

  void _restartStory() {
    setState(() {
      _currentSlide = 0;
    });
    _progressController.reset();
    _progressController.forward();
    HapticFeedback.mediumImpact();
  }

  void _shareWrapped(WrappedSummary summary) {
    final topTrack = summary.topTrack?.title ?? 'Music';
    final topArtist = summary.topArtist?.name ?? 'Artists';

    final text = '🎵 My ${summary.year} Miee Wrapped!\n\n'
        '⏱ ${summary.totalMinutes} minutes of music listened\n'
        '🎧 Top Song: "$topTrack"\n'
        '👑 Top Artist: $topArtist\n'
        '✨ Archetype: ${summary.archetype.title} ("${summary.archetype.tagline}")\n'
        '🌙 Peak Listening: ${summary.peakHourLabel} on ${summary.peakDayName}s\n\n'
        'Discover your sound on Miee Music Player.';

    SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: 'My ${summary.year} Miee Wrapped',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(wrappedSummaryProvider);
    final archetype = summary.archetype;

    return Scaffold(
      backgroundColor: const Color(0xFF140D10), // Warm nocturnal base
      body: SafeArea(
        child: GestureDetector(
          onTapDown: (_) => _pauseTimer(),
          onTapUp: (details) {
            _resumeTimer();
            final screenWidth = MediaQuery.of(context).size.width;
            if (details.localPosition.dx < screenWidth * 0.30) {
              _previousSlide();
            } else {
              _advanceSlide();
            }
          },
          onTapCancel: () => _resumeTimer(),
          onLongPressStart: (_) => _pauseTimer(),
          onLongPressEnd: (_) => _resumeTimer(),
          child: Stack(
            children: [
              // Dynamic Background Aura based on Archetype colors
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.0, -0.2),
                      radius: 1.2,
                      colors: [
                        archetype.primaryColor.withValues(alpha: 0.18),
                        archetype.secondaryColor.withValues(alpha: 0.08),
                        const Color(0xFF120C0F),
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),

              // Active Slide Content
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: _buildSlideContent(_currentSlide, summary),
                  ),
                ),
              ),

              // Top Story Header: Multi-segment Progress Bars & Actions
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Column(
                  children: [
                    // Segmented Progress Bars
                    Row(
                      children: List.generate(_totalSlides, (index) {
                        return Expanded(
                          child: Container(
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 2.5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: AnimatedBuilder(
                              animation: _progressController,
                              builder: (context, _) {
                                double fill = 0.0;
                                if (index < _currentSlide) {
                                  fill = 1.0;
                                } else if (index == _currentSlide) {
                                  fill = _progressController.value;
                                }
                                return FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: fill,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 12),

                    // Top Bar (Tag & Close Button)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    color: archetype.secondaryColor,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'MIEE WRAPPED ${summary.year}',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (summary.isSampleData) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'PREVIEW',
                                  style: GoogleFonts.inter(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amberAccent,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),

                        // Close button
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 24),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
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

  Widget _buildSlideContent(int slideIndex, WrappedSummary summary) {
    switch (slideIndex) {
      case 0:
        return _buildIntroSlide(summary);
      case 1:
        return _buildMinutesSlide(summary);
      case 2:
        return _buildTopSongsSlide(summary);
      case 3:
        return _buildTopArtistSlide(summary);
      case 4:
        return _buildArchetypeSlide(summary);
      case 5:
        return _buildRhythmSlide(summary);
      case 6:
      default:
        return _buildFinaleSlide(summary);
    }
  }

  // ── SLIDE 0: INTRO ──────────────────────────────────────────────────────────
  Widget _buildIntroSlide(WrappedSummary summary) {
    return Column(
      key: const ValueKey('slide_intro'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Spinning record icon badge
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF26141B),
            boxShadow: [
              BoxShadow(
                color: AppColors.dustyRose.withValues(alpha: 0.35),
                blurRadius: 36,
                spreadRadius: 4,
              ),
            ],
            border: Border.all(color: AppColors.dustyRose.withValues(alpha: 0.5), width: 2),
          ),
          child: const Center(
            child: Icon(
              Icons.graphic_eq_rounded,
              color: AppColors.dustyRose,
              size: 52,
            ),
          ),
        ),
        const SizedBox(height: 36),

        Text(
          'YOUR YEAR IN SOUND',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 3.0,
            color: AppColors.dustyRose,
          ),
        ),
        const SizedBox(height: 12),

        Text(
          'Ready to see what\nyou listened to?',
          textAlign: TextAlign.center,
          style: GoogleFonts.playfairDisplay(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'From late-night repeats to morning anthems,\nhere is your ${summary.timeframeLabel} musical journey.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Colors.white70,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 44),

        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tap to begin',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white54,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white54, size: 16),
          ],
        ),
      ],
    );
  }

  // ── SLIDE 1: MINUTES & HOURS ────────────────────────────────────────────────
  Widget _buildMinutesSlide(WrappedSummary summary) {
    return Column(
      key: const ValueKey('slide_minutes'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'TIME SPENT LISTENING',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.5,
            color: summary.archetype.secondaryColor,
          ),
        ),
        const SizedBox(height: 14),

        Text(
          'You listened for',
          style: GoogleFonts.playfairDisplay(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 8),

        // Hero Minutes Counter
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [Colors.white, summary.archetype.secondaryColor],
          ).createShader(bounds),
          child: Text(
            summary.totalMinutes.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},'),
            style: GoogleFonts.outfit(
              fontSize: 68,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.0,
              letterSpacing: -2.0,
            ),
          ),
        ),
        Text(
          'MINUTES',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 4.0,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 28),

        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.timer_outlined, color: Colors.white70, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'That is ${summary.totalHours} hours of music',
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatPill('Tracks Explored', '${summary.totalTracks}'),
                  _buildStatPill('Distinct Artists', '${summary.totalArtists}'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatPill(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ],
    );
  }

  // ── SLIDE 2: TOP SONGS ──────────────────────────────────────────────────────
  Widget _buildTopSongsSlide(WrappedSummary summary) {
    final topTrack = summary.topTrack;

    return Column(
      key: const ValueKey('slide_top_songs'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'YOUR TOP TRACKS',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.5,
            color: summary.archetype.secondaryColor,
          ),
        ),
        const SizedBox(height: 8),

        Text(
          'The songs on repeat',
          style: GoogleFonts.playfairDisplay(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),

        // Spotlight #1 Song
        if (topTrack != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: summary.archetype.primaryColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: summary.archetype.primaryColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                // Rank 1 badge
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: summary.archetype.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '1',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topTrack.title,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        topTrack.artist,
                        style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white70),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${topTrack.playCount} plays',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 12),

        // Tracks #2 to #5
        ...summary.topTracks.skip(1).take(4).map((track) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(
                    '#${track.rank}',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white38,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          track.artist,
                          style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white60),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${track.playCount} plays',
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── SLIDE 3: TOP ARTIST ─────────────────────────────────────────────────────
  Widget _buildTopArtistSlide(WrappedSummary summary) {
    final topArtist = summary.topArtist;
    final name = topArtist?.name ?? 'Top Artist';

    return Column(
      key: const ValueKey('slide_top_artist'),
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'YOUR #1 ARTIST',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.5,
            color: summary.archetype.secondaryColor,
          ),
        ),
        const SizedBox(height: 20),

        // Glowing Artist Circle
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: summary.archetype.primaryColor.withValues(alpha: 0.25),
            border: Border.all(color: summary.archetype.secondaryColor, width: 3),
            boxShadow: [
              BoxShadow(
                color: summary.archetype.primaryColor.withValues(alpha: 0.4),
                blurRadius: 40,
                spreadRadius: 6,
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.person_rounded, size: 70, color: Colors.white),
          ),
        ),
        const SizedBox(height: 24),

        Text(
          name,
          textAlign: TextAlign.center,
          style: GoogleFonts.playfairDisplay(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),

        if (topArtist != null)
          Text(
            'You listened to ${topArtist.playCount} songs over ${topArtist.totalMinutes} minutes',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13.5, color: Colors.white70),
          ),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.military_tech_rounded, color: Colors.amber, size: 18),
              const SizedBox(width: 8),
              Text(
                'Top 0.5% Listener',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── SLIDE 4: ARCHETYPE ──────────────────────────────────────────────────────
  Widget _buildArchetypeSlide(WrappedSummary summary) {
    final archetype = summary.archetype;

    return Column(
      key: const ValueKey('slide_archetype'),
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'YOUR LISTENING PERSONALITY',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.5,
            color: archetype.secondaryColor,
          ),
        ),
        const SizedBox(height: 24),

        // Archetype Emblem
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: archetype.primaryColor,
            boxShadow: [
              BoxShadow(
                color: archetype.primaryColor.withValues(alpha: 0.5),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Icon(archetype.icon, color: Colors.white, size: 46),
        ),
        const SizedBox(height: 24),

        Text(
          archetype.title,
          textAlign: TextAlign.center,
          style: GoogleFonts.playfairDisplay(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),

        Text(
          '"${archetype.tagline}"',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: archetype.secondaryColor,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 18),

        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Text(
            archetype.description,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              color: Colors.white70,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  // ── SLIDE 5: RHYTHM & PEAK HOUR ─────────────────────────────────────────────
  Widget _buildRhythmSlide(WrappedSummary summary) {
    return Column(
      key: const ValueKey('slide_rhythm'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'YOUR LISTENING RHYTHM',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.5,
            color: summary.archetype.secondaryColor,
          ),
        ),
        const SizedBox(height: 12),

        Text(
          'When sound speaks to you',
          style: GoogleFonts.playfairDisplay(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 24),

        // Peak Hour Box
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: summary.archetype.primaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.access_time_rounded, color: summary.archetype.secondaryColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Peak Hour', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
                    const SizedBox(height: 2),
                    Text(
                      summary.peakHourLabel,
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Peak Day Box
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: summary.archetype.primaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.calendar_today_rounded, color: summary.archetype.secondaryColor, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Favorite Day', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
                    const SizedBox(height: 2),
                    Text(
                      '${summary.peakDayName}s',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (summary.topDay != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.whatshot_rounded, color: Colors.orangeAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Peak streak: ${summary.topDayTrackCount} songs played on ${summary.topDay!.month}/${summary.topDay!.day}',
                    style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── SLIDE 6: FINALE & SHARE POSTER ──────────────────────────────────────────
  Widget _buildFinaleSlide(WrappedSummary summary) {
    return Column(
      key: const ValueKey('slide_finale'),
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Summary Poster Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1419),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: summary.archetype.primaryColor.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.music_note_rounded, color: AppColors.dustyRose, size: 22),
                      const SizedBox(width: 6),
                      Text(
                        'MIEE WRAPPED',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${summary.year}',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: summary.archetype.secondaryColor,
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 24),

              // Archetype
              Row(
                children: [
                  Icon(summary.archetype.icon, color: summary.archetype.secondaryColor, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      summary.archetype.title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Stats Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MINUTES', style: GoogleFonts.inter(fontSize: 10, color: Colors.white54)),
                      Text(
                        '${summary.totalMinutes}',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TOP SONG', style: GoogleFonts.inter(fontSize: 10, color: Colors.white54)),
                      Text(
                        summary.topTrack?.title ?? 'None',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: summary.archetype.secondaryColor,
                        ),
                        maxLines: 1,
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TOP ARTIST', style: GoogleFonts.inter(fontSize: 10, color: Colors.white54)),
                      Text(
                        summary.topArtist?.name ?? 'None',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.share_rounded, size: 18),
                label: Text(
                  'Share Wrapped',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: summary.archetype.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => _shareWrapped(summary),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.replay_rounded, color: Colors.white70),
              tooltip: 'Replay Story',
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                padding: const EdgeInsets.all(14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _restartStory,
            ),
          ],
        ),
      ],
    );
  }
}
