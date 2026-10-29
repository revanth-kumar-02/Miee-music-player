import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/audio/providers.dart';
import '../domain/wrapped_models.dart';
import '../providers/wrapped_providers.dart';

class WrappedStoryPage extends ConsumerStatefulWidget {
  const WrappedStoryPage({super.key});

  @override
  ConsumerState<WrappedStoryPage> createState() => _WrappedStoryPageState();
}

class _WrappedStoryPageState extends ConsumerState<WrappedStoryPage>
    with SingleTickerProviderStateMixin {
  static const int _totalSlides = 10;
  static const Duration _slideDuration = Duration(seconds: 7);

  final GlobalKey _shareCardKey = GlobalKey();
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

  void _playTop5Playlist(List<WrappedTrackItem> topTracks) {
    final validItems = topTracks
        .where((t) => t.musicItem != null)
        .map((t) => t.musicItem!)
        .toList();

    if (validItems.isNotEmpty) {
      ref.read(playerControllerProvider.notifier).setQueue(
            validItems,
            startIndex: 0,
            playingFrom: 'Miee Wrapped Top 5',
          );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Playing your Top 5 playlist!'),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF3A252B),
        ),
      );
    }
  }

  Future<Uint8List?> _captureShareCardPng() async {
    try {
      final boundary = _shareCardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[Wrapped] Error capturing share card: $e');
      return null;
    }
  }

  Future<void> _shareWrapped(WrappedSummary summary) async {
    final topTrack = summary.topTrack?.title ?? 'My Favorite Songs';
    final topArtist = summary.topArtist?.name ?? 'Top Artists';

    final text = '✨ My ${summary.year} Miee Wrapped ✨\n\n'
        '🎧 ${summary.totalHours.toStringAsFixed(summary.totalHours < 1 ? 1 : 0)} hours of music listened\n'
        '🎵 ${summary.totalTracks} songs played\n'
        '👑 Top Artist: $topArtist\n'
        '🔥 Top Song: "$topTrack"\n'
        '✨ Archetype: ${summary.archetype.title}\n\n'
        'Discovered with Miee Music Player.';

    try {
      final pngBytes = await _captureShareCardPng();
      if (pngBytes != null) {
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/miee_wrapped_${summary.year}.png';
        final file = File(filePath);
        await file.writeAsBytes(pngBytes);

        await SharePlus.instance.share(
          ShareParams(
            text: text,
            subject: 'My ${summary.year} Miee Wrapped',
            files: [XFile(file.path, mimeType: 'image/png')],
          ),
        );
        return;
      }
    } catch (e) {
      debugPrint('[Wrapped] Image export failed, falling back to text: $e');
    }

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          subject: 'My ${summary.year} Miee Wrapped',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sharing failed: $e'),
            backgroundColor: const Color(0xFF8B4F48),
          ),
        );
      }
    }
  }

  Future<void> _saveToGallery() async {
    try {
      final pngBytes = await _captureShareCardPng();
      if (pngBytes == null) {
        throw Exception('Could not capture image boundary');
      }

      final docsDir = await getApplicationDocumentsDirectory();
      final filePath = '${docsDir.path}/miee_wrapped_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(filePath);
      await file.writeAsBytes(pngBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to: ${file.path.split("/").last}'),
            backgroundColor: const Color(0xFF3A252B),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save image: $e'),
            backgroundColor: const Color(0xFF8B4F48),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eligibility = ref.watch(wrappedEligibilityProvider);
    final summary = ref.watch(wrappedSummaryProvider);

    // If the account is under 1 year old, Wrapped is completely hidden from the user
    if (!eligibility.isEligible) {
      if (_progressController.isAnimating) {
        _progressController.stop();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            context.go('/home');
          }
        }
      });
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: SizedBox.shrink(),
      );
    } else {
      if (!_progressController.isAnimating && !_isPaused && _progressController.value < 1.0) {
        _progressController.forward();
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9F6F0), // Warm ivory canvas
      body: SafeArea(
        child: GestureDetector(
          onTapDown: (_) => _pauseTimer(),
          onTapUp: (details) {
            _resumeTimer();
            final screenWidth = MediaQuery.of(context).size.width;
            if (details.localPosition.dx < screenWidth * 0.25) {
              _previousSlide();
            } else if (details.localPosition.dy < MediaQuery.of(context).size.height * 0.85) {
              _advanceSlide();
            }
          },
          onTapCancel: () => _resumeTimer(),
          onLongPressStart: (_) => _pauseTimer(),
          onLongPressEnd: (_) => _resumeTimer(),
          child: Stack(
            children: [
              // ── Background Watercolor Organic Blobs ─────────────────────────
              Positioned(
                top: -50,
                right: -50,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3EDE7).withValues(alpha: 0.7), // Soft Sage
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                bottom: -60,
                left: -60,
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2D8D0).withValues(alpha: 0.6), // Dusty Terracotta
                    shape: BoxShape.circle,
                  ),
                ),
              ),

              // ── Top Bar Header (Title, Slide counter, Progress bar) ─────────
              Positioned(
                top: 12,
                left: 20,
                right: 20,
                child: Column(
                  children: [
                    // Segmented Story Bar
                    Row(
                      children: List.generate(_totalSlides, (index) {
                        return Expanded(
                          child: Container(
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 2.0),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3A252B).withValues(alpha: 0.12),
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
                                      color: const Color(0xFFC87D6B),
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
                    const SizedBox(height: 14),

                    // Top Row: Brand & Slide Indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Miee Wrapped',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF3A252B),
                                  ),
                                ),
                                Text(
                                  'Year ${eligibility.activeYear} • ${summary.year}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: const Color(0xFF75656A),
                                  ),
                                ),
                              ],
                            ),
                            if (eligibility.availableYears.length > 1) ...[
                              const SizedBox(width: 8),
                              PopupMenuButton<int>(
                                initialValue: eligibility.activeYear,
                                tooltip: 'Select Milestone Year',
                                onSelected: (int selectedYear) {
                                  ref.read(wrappedSelectedAnniversaryYearProvider.notifier).state = selectedYear;
                                },
                                itemBuilder: (context) => eligibility.availableYears.map((yr) {
                                  return PopupMenuItem<int>(
                                    value: yr,
                                    child: Text('Year $yr Recap', style: GoogleFonts.inter(fontSize: 13)),
                                  );
                                }).toList(),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3A252B).withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Yr ${eligibility.activeYear}',
                                        style: GoogleFonts.inter(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF3A252B),
                                        ),
                                      ),
                                      const Icon(Icons.arrow_drop_down_rounded, size: 16, color: Color(0xFF3A252B)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),

                        // Slide number indicator (e.g. 02 / 10)
                        Row(
                          children: [
                            Text(
                              '${(_currentSlide + 1).toString().padLeft(2, '0')} / 10',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF75656A),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 22, color: Color(0xFF3A252B)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Active Slide Body ───────────────────────────────────────────
              Positioned.fill(
                top: 76,
                bottom: 80,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: _buildSlideContent(_currentSlide, summary),
                  ),
                ),
              ),

              // ── Bottom Navigation Row (Dots + Advance Button) ───────────────
              if (_currentSlide > 0 && _currentSlide < _totalSlides - 1)
                Positioned(
                  bottom: 20,
                  left: 24,
                  right: 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Dots Indicator
                      Row(
                        children: List.generate(_totalSlides, (index) {
                          final isActive = index == _currentSlide;
                          return Container(
                            margin: const EdgeInsets.only(right: 5),
                            width: isActive ? 16 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFFC87D6B)
                                  : const Color(0xFF3A252B).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),

                      // Next Circle Button
                      Material(
                        color: const Color(0xFFC87D6B),
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _advanceSlide,
                          child: const SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
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

  Widget _buildSlideContent(int slideIndex, WrappedSummary summary) {
    switch (slideIndex) {
      case 0:
        return _buildSlide1Opening(summary);
      case 1:
        return _buildSlide2Personality(summary);
      case 2:
        return _buildSlide3YearInNumbers(summary);
      case 3:
        return _buildSlide4Top5Songs(summary);
      case 4:
        return _buildSlide5TopArtist(summary);
      case 5:
        return _buildSlide6FavouriteAlbum(summary);
      case 6:
        return _buildSlide7Timeline(summary);
      case 7:
        return _buildSlide8Languages(summary);
      case 8:
        return _buildSlide9WhereYouListened(summary);
      case 9:
      default:
        return _buildSlide10FinalShare(summary);
    }
  }

  // ── SLIDE 1 (01/10): OPENING ────────────────────────────────────────────────
  Widget _buildSlide1Opening(WrappedSummary summary) {
    return Column(
      key: const ValueKey('slide_1'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),

        // Headline
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.anniversaryYear > 1
                    ? 'YEAR ${summary.anniversaryYear},\nIN MUSIC.'
                    : 'YOUR YEAR,\nIN MUSIC.',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                  letterSpacing: -0.5,
                  color: const Color(0xFF8B4F48),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Every song told a story.\nHere\'s yours.',
                style: GoogleFonts.inter(
                  fontSize: 14.5,
                  color: const Color(0xFF5A4A50),
                  height: 1.35,
                ),
              ),
              if (!summary.hasSufficientHistory) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF1EC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    summary.totalTracks > 0
                        ? 'Early listening overview • ${summary.totalTracks} songs recorded'
                        : 'New journey • Start listening to build your story',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF4A6B5D),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Illustration Area: Listening Room Scene
        Expanded(
          flex: 6,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: const Color(0xFFEFE8DD),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3A252B).withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Arched Window in Illustration
                  Container(
                    width: 170,
                    height: 240,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F5EE),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(85)),
                      border: Border.all(color: const Color(0xFFE5DDD0), width: 4),
                    ),
                  ),

                  // Turntable Vinyl Graphic
                  Positioned(
                    bottom: 28,
                    child: Column(
                      children: [
                        Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF221A1D),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFC87D6B),
                              ),
                              child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 22),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Indoor Plant icon accent
                  Positioned(
                    top: 24,
                    right: 32,
                    child: Icon(Icons.eco_rounded, size: 40, color: const Color(0xFF7D9D8B).withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),

        // Action: "Let's begin →"
        Material(
          color: const Color(0xFFFAF6F0),
          borderRadius: BorderRadius.circular(28),
          elevation: 2,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: _advanceSlide,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFDCCFC3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Let\'s begin',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF3A252B),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 18, color: Color(0xFFC87D6B)),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
      ],
    );
  }

  // ── SLIDE 2 (02/10): LISTENING PERSONALITY ──────────────────────────────────
  Widget _buildSlide2Personality(WrappedSummary summary) {
    final archetype = summary.archetype;

    return Column(
      key: const ValueKey('slide_2'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'YOU ARE...',
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.0,
            color: const Color(0xFF7D9D8B),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          archetype.title,
          style: GoogleFonts.playfairDisplay(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF8B4F48),
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          archetype.description,
          style: GoogleFonts.inter(
            fontSize: 13.5,
            color: const Color(0xFF5A4A50),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),

        // Moonlit Window Illustration
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: const Color(0xFFE9E0D4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Night Sky & Moon Window
                  Container(
                    width: 190,
                    height: 250,
                    decoration: BoxDecoration(
                      color: const Color(0xFF261D2B),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(95)),
                      border: Border.all(color: const Color(0xFFDDD2C4), width: 5),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: 36,
                          right: 36,
                          child: Icon(Icons.nightlight_round, size: 48, color: Colors.amber.shade100),
                        ),
                        Positioned(
                          top: 90,
                          left: 45,
                          child: Icon(Icons.auto_awesome, size: 16, color: Colors.white.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ),

                  // Window Sill with Headphone
                  Positioned(
                    bottom: 20,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Color(0xFF3A252B),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.headphones_rounded, color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.yard_rounded, color: Color(0xFF7D9D8B), size: 36),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Archetype Tags
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: archetype.tags.map((tag) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF0E5D8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFDECFC0)),
              ),
              child: Text(
                tag,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF8B4F48),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // ── SLIDE 3 (03/10): YOUR YEAR IN NUMBERS ───────────────────────────────────
  Widget _buildSlide3YearInNumbers(WrappedSummary summary) {
    return Column(
      key: const ValueKey('slide_3'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'YOUR YEAR\nIN NUMBERS',
          style: GoogleFonts.playfairDisplay(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF4A6B5D), // Forest / Sage
            height: 1.15,
          ),
        ),
        const SizedBox(height: 18),

        // 6 Bento Cards
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.12,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildBentoCard(
                icon: Icons.headphones_rounded,
                iconColor: const Color(0xFF4A6B5D),
                value: '${summary.totalHours.round()}',
                label: 'hours\nlistening time',
                bgColor: const Color(0xFFEAF1EC), // Mint/Sage
              ),
              _buildBentoCard(
                icon: Icons.play_circle_filled_rounded,
                iconColor: const Color(0xFFC87D6B),
                value: summary.totalTracks.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},'),
                label: 'songs played',
                bgColor: const Color(0xFFF7ECE8), // Rose
              ),
              _buildBentoCard(
                icon: Icons.whatshot_rounded,
                iconColor: const Color(0xFFD97706),
                value: '${summary.totalArtists}',
                label: 'artists explored',
                bgColor: const Color(0xFFFAF0E4), // Peach
              ),
              _buildBentoCard(
                icon: Icons.album_rounded,
                iconColor: const Color(0xFF2E6F52),
                value: '${summary.totalAlbums}',
                label: 'albums played',
                bgColor: const Color(0xFFEBF3EF), // Soft Mint
              ),
              _buildBentoCard(
                icon: Icons.calendar_today_rounded,
                iconColor: const Color(0xFFC87D6B),
                value: '${summary.longestStreakDays} days',
                label: 'longest streak',
                bgColor: const Color(0xFFF6EDE8), // Terracotta
              ),
              _buildBentoCard(
                icon: Icons.language_rounded,
                iconColor: const Color(0xFF5B7288),
                value: '${summary.totalLanguages}',
                label: 'languages',
                bgColor: const Color(0xFFEDF2F6), // Sky tint
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBentoCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF2D1F23),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: const Color(0xFF6B5C62),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  // ── SLIDE 4 (04/10): YOUR TOP 5 SONGS ───────────────────────────────────────
  Widget _buildSlide4Top5Songs(WrappedSummary summary) {
    return Column(
      key: const ValueKey('slide_4'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'YOUR TOP 5\nSONGS',
          style: GoogleFonts.playfairDisplay(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF8B4F48),
            height: 1.15,
          ),
        ),
        const SizedBox(height: 14),

        // List of Tracks (honest empty or real items)
        Expanded(
          child: summary.topTracks.isEmpty
              ? Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFEAE2D8)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.music_note_rounded, size: 48, color: Color(0xFFC87D6B)),
                        const SizedBox(height: 12),
                        Text(
                          'No Songs Recorded Yet',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF2D1F23),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start playing songs from your library or search to build your top ranked tracks.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: const Color(0xFF75656A),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: summary.topTracks.length,
                  physics: const NeverScrollableScrollPhysics(),
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final track = summary.topTracks[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFEAE2D8)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${track.rank}',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF3A252B),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Artwork
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE9C9B7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: track.imageUrl != null && track.imageUrl!.isNotEmpty
                                  ? Image.network(
                                      track.imageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.music_note_rounded, color: Colors.white70),
                                    )
                                  : const Icon(Icons.music_note_rounded, color: Colors.white70),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Title & Artist
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  style: GoogleFonts.inter(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF2D1F23),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  track.artist,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: const Color(0xFF75656A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${track.playCount} plays',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFC87D6B),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Icon(
                            track.isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: track.isFavorited ? const Color(0xFFC87D6B) : const Color(0xFFB0A4A8),
                            size: 20,
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),

        // Action: "Play Top Songs"
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Material(
            color: const Color(0xFFC87D6B),
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {
                if (summary.topTracks.isNotEmpty) {
                  _playTop5Playlist(summary.topTracks);
                } else {
                  Navigator.of(context).pop();
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      summary.topTracks.isNotEmpty ? Icons.play_arrow_rounded : Icons.explore_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      summary.topTracks.isEmpty
                          ? 'Explore Songs'
                          : (summary.topTracks.length < 5
                              ? 'Play Top ${summary.topTracks.length} Songs'
                              : 'Play Top 5 Playlist'),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── SLIDE 5 (05/10): YOUR TOP ARTIST ────────────────────────────────────────
  Widget _buildSlide5TopArtist(WrappedSummary summary) {
    final artist = summary.topArtist;
    final name = artist?.name ?? 'Top Artist';

    return Column(
      key: const ValueKey('slide_5'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 10),
        Text(
          'YOUR TOP\nARTIST',
          textAlign: TextAlign.center,
          style: GoogleFonts.playfairDisplay(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF8B4F48),
            height: 1.15,
          ),
        ),
        const SizedBox(height: 18),

        // Large Circular Artist Portrait
        Container(
          width: 170,
          height: 170,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF7D9D8B).withValues(alpha: 0.3),
            border: Border.all(color: const Color(0xFFC87D6B), width: 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3A252B).withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipOval(
            child: artist?.imageUrl != null && artist!.imageUrl!.isNotEmpty
                ? Image.network(
                    artist.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 80, color: Colors.white),
                  )
                : const Icon(Icons.person_rounded, size: 80, color: Colors.white),
          ),
        ),
        const SizedBox(height: 16),

        Text(
          name,
          style: GoogleFonts.playfairDisplay(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2D1F23),
          ),
        ),
        const SizedBox(height: 16),

        // 3 Stat Badges: Plays | Songs | Hours
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildArtistStatPill('${artist?.playCount ?? 0}', 'plays'),
            const SizedBox(width: 12),
            _buildArtistStatPill('${artist?.songsCount ?? 0}', 'songs'),
            const SizedBox(width: 12),
            _buildArtistStatPill(
              artist != null
                  ? (artist.totalHours < 1 ? artist.totalHours.toStringAsFixed(1) : '${artist.totalHours.round()}')
                  : '0',
              'hours',
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Quote Box
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            artist != null
                ? artist.quote
                : '“ Play your favorite tracks to uncover which artist accompanied you the most this year. ”',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: const Color(0xFF8B4F48),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildArtistStatPill(String val, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF2EAE0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5DDD0)),
      ),
      child: Column(
        children: [
          Text(val, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF2D1F23))),
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF75656A))),
        ],
      ),
    );
  }

  // ── SLIDE 6 (06/10): YOUR FAVOURITE ALBUM ────────────────────────────────────
  Widget _buildSlide6FavouriteAlbum(WrappedSummary summary) {
    final album = summary.topAlbum;

    return Column(
      key: const ValueKey('slide_6'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'YOUR\nFAVOURITE ALBUM',
          style: GoogleFonts.playfairDisplay(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2D1F23),
            height: 1.15,
          ),
        ),
        const SizedBox(height: 20),

        // Album Artwork + Grooved Vinyl sliding out
        Expanded(
          child: Center(
            child: SizedBox(
              width: 280,
              height: 180,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Vinyl Disc
                  Positioned(
                    right: 10,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1E1A1C),
                        border: Border.all(color: const Color(0xFF3A3337), width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 14,
                            offset: const Offset(4, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFC87D6B),
                          ),
                          child: const Icon(Icons.album_rounded, color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                  ),

                  // Album Jacket Cover
                  Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9C9B7),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3A252B).withValues(alpha: 0.18),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: album?.artworkUrl != null && album!.artworkUrl!.isNotEmpty
                          ? Image.network(
                              album.artworkUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.album_rounded, size: 60, color: Colors.white),
                            )
                          : const Icon(Icons.album_rounded, size: 60, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Title & Artist
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album?.title ?? 'Album Data Unavailable',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF2D1F23),
                  ),
                ),
                Text(
                  album?.artist ?? 'Gathered from full album listening',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF75656A),
                  ),
                ),
              ],
            ),
            const Icon(Icons.favorite_rounded, color: Color(0xFFC87D6B), size: 24),
          ],
        ),
        const SizedBox(height: 16),

        // 2 Stat Badges: Plays & Hours
        Row(
          children: [
            _buildArtistStatPill('${album?.playCount ?? 0}', 'plays'),
            const SizedBox(width: 12),
            _buildArtistStatPill(
              album != null
                  ? (album.totalHours < 1 ? album.totalHours.toStringAsFixed(1) : '${album.totalHours.round()}')
                  : '0',
              'hours',
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Quote
        Text(
          album != null
              ? album.quote
              : '“ Play complete albums to showcase your favorite album and vinyl disc here. ”',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontStyle: FontStyle.italic,
            color: const Color(0xFF8B4F48),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── SLIDE 7 (07/10): YOUR MUSIC TIMELINE ─────────────────────────────────────
  Widget _buildSlide7Timeline(WrappedSummary summary) {
    return Column(
      key: const ValueKey('slide_7'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'YOUR MUSIC\nTIMELINE',
          style: GoogleFonts.playfairDisplay(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF8B4F48),
            height: 1.15,
          ),
        ),
        const SizedBox(height: 18),

        Expanded(
          child: summary.timelineMilestones.isEmpty
              ? Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFEAE2D8)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timeline_rounded, size: 48, color: Color(0xFF8B4F48)),
                        const SizedBox(height: 12),
                        Text(
                          'Your Timeline Is Waiting',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF2D1F23),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Monthly milestones will automatically unfold here as you listen to music across different months of the year.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: const Color(0xFF75656A),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: summary.timelineMilestones.length,
                  physics: const NeverScrollableScrollPhysics(),
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final node = summary.timelineMilestones[index];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Month Circle Node
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7ECE8),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFC87D6B), width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              node.monthLabel,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFC87D6B),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Artwork Thumbnail
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE9C9B7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: node.imageUrl != null && node.imageUrl!.isNotEmpty
                                ? Image.network(
                                    node.imageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.music_note_rounded, color: Colors.white70),
                                  )
                                : const Icon(Icons.music_note_rounded, color: Colors.white70),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Title & Description
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                node.title,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF2D1F23),
                                ),
                              ),
                              Text(
                                node.description,
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: const Color(0xFF75656A),
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── SLIDE 8 (08/10): MUSIC WITHOUT BORDERS ──────────────────────────────────
  Widget _buildSlide8Languages(WrappedSummary summary) {
    return Column(
      key: const ValueKey('slide_8'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'MUSIC WITHOUT\nBORDERS',
          style: GoogleFonts.playfairDisplay(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF4A6B5D),
            height: 1.15,
          ),
        ),
        const SizedBox(height: 18),

        // Custom Donut Chart
        Center(
          child: SizedBox(
            width: 170,
            height: 170,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(170, 170),
                  painter: _DonutChartPainter(summary.languages),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'YOUR\nTOP LANGUAGE',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF75656A),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary.languages.isNotEmpty ? summary.languages.first.name : 'Uncharted',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF2D1F23),
                      ),
                    ),
                    Text(
                      summary.languages.isNotEmpty ? '${summary.languages.first.percentage}%' : '0%',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF4A6B5D),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Legend list
        Expanded(
          child: summary.languages.isEmpty
              ? Center(
                  child: Text(
                    'Language insights will appear as you play songs from diverse cultures and artists.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: const Color(0xFF75656A),
                      height: 1.4,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: summary.languages.length,
                  physics: const NeverScrollableScrollPhysics(),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final lang = summary.languages[index];
                    return Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: lang.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            lang.name,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF2D1F23),
                            ),
                          ),
                        ),
                        Text(
                          '${lang.percentage}%',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF2D1F23),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── SLIDE 9 (09/10): WHERE YOU LISTENED MOST ────────────────────────────────
  Widget _buildSlide9WhereYouListened(WrappedSummary summary) {
    return Column(
      key: const ValueKey('slide_9'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'WHERE YOU\nLISTENED MOST',
          style: GoogleFonts.playfairDisplay(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2D1F23),
            height: 1.15,
          ),
        ),
        const SizedBox(height: 18),

        Expanded(
          child: ListView.separated(
            itemCount: summary.listeningContexts.length,
            physics: const NeverScrollableScrollPhysics(),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final ctx = summary.listeningContexts[index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEAE2D8)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF1EC),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(ctx.icon, color: const Color(0xFF4A6B5D), size: 22),
                    ),
                    const SizedBox(width: 14),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ctx.label,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF2D1F23),
                            ),
                          ),
                          Text(
                            ctx.subLabel,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: const Color(0xFF75656A),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Text(
                      '${ctx.percentage}%',
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2D1F23),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── SLIDE 10 (10/10): FINAL SHARE CARD ──────────────────────────────────────
  Widget _buildSlide10FinalShare(WrappedSummary summary) {
    return Column(
      key: const ValueKey('slide_10'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Script header
        Text(
          'Miee Wrapped',
          style: GoogleFonts.caveat(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF8B4F48),
          ),
        ),
        const SizedBox(height: 14),

        // Framed Poster Card wrapped in RepaintBoundary for genuine image export
        RepaintBoundary(
          key: _shareCardKey,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE0D4C5)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3A252B).withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                // Hero Thumbnail
                Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: const Color(0xFF261D2B),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Icon(Icons.music_note_rounded, size: 70, color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      Positioned(
                        bottom: 16,
                        left: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'My ${summary.year}\nin Music',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 3 Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildFinalStatItem(
                      summary.totalHours < 1 ? summary.totalHours.toStringAsFixed(1) : '${summary.totalHours.round()}',
                      'hours',
                    ),
                    Container(width: 1, height: 28, color: const Color(0xFFEAE2D8)),
                    _buildFinalStatItem('${summary.totalTracks}', 'songs'),
                    Container(width: 1, height: 28, color: const Color(0xFFEAE2D8)),
                    _buildFinalStatItem(summary.topArtist?.name ?? 'Top Artist', 'top artist'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Action 1: "Share Your Wrapped"
        Material(
          color: const Color(0xFF2D1F23),
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => _shareWrapped(summary),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.share_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Share Your Wrapped',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Action 2: "Save to Gallery"
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: _saveToGallery,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFDCCFC3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.download_rounded, color: Color(0xFF3A252B), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Save to Gallery',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF3A252B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFinalStatItem(String val, String label) {
    return Column(
      children: [
        Text(
          val,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF2D1F23),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10.5,
            color: const Color(0xFF75656A),
          ),
        ),
      ],
    );
  }
}

/// Custom painter for Donut Chart in Slide 8 (Music Without Borders)
class _DonutChartPainter extends CustomPainter {
  final List<WrappedLanguageItem> languages;

  _DonutChartPainter(this.languages);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 24.0;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    double startAngle = -math.pi / 2;

    for (final lang in languages) {
      final sweepAngle = (lang.percentage / 100.0) * (2 * math.pi);
      paint.color = lang.color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) => true;
}
