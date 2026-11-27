import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/midnight_velvet_tokens.dart';
import '../../../../core/audio/providers.dart';
import '../../../../core/storage/adapters/history_entry.dart';
import '../../../../shared/models/music_item.dart';
import '../../../../shared/models/track.dart';
import '../../../artwork/presentation/miee_artwork_image.dart';
import '../../../library/presentation/artist_detail_page.dart';
import '../../../library/providers/library_providers.dart';
import '../../../notifications/presentation/widgets/notification_sheet.dart';
import '../../../media/domain/models.dart';
import '../../../media/providers/media_providers.dart';
import '../../../onboarding/domain/artist_model.dart';
import '../../../profile/domain/user_profile.dart';
import '../../../profile/providers/profile_providers.dart';
import '../../../recommendations/domain/daily_mix.dart';
import '../../../recommendations/presentation/daily_mix_playback_helper.dart';
import '../../../recommendations/providers/daily_mix_providers.dart';

/// The Desktop Primary Dashboard View strictly reproducing the
/// Midnight Velvet & Warm Studio design language.
///
/// Sections:
/// 1. Top Bar (Search pill, Notification bell with amber pip, User Avatar)
/// 2. Quick Filter Chips (All, On Repeat, Made For You, Playlists, New Releases)
/// 3. Editorial Spotlight Hero Banner (Featured Release / Master Spotlight)
/// 4. Continue Listening (Row of 6 square cards with dynamic vinyl sleeves)
/// 5. Popular Artists (Row of 6 circular portrait cards with tactile play triggers)
/// 6. Daily Mixes (Row of 6 editorial sleeve cards with wave cutouts)
class DesktopDashboardView extends ConsumerStatefulWidget {
  final VoidCallback? onSearchTap;
  final VoidCallback? onSeeAllContinue;
  final VoidCallback? onSeeAllArtists;
  final VoidCallback? onSeeAllMixes;
  final void Function(ArtistModel artist)? onArtistTap;

  const DesktopDashboardView({
    super.key,
    this.onSearchTap,
    this.onSeeAllContinue,
    this.onSeeAllArtists,
    this.onSeeAllMixes,
    this.onArtistTap,
  });

  @override
  ConsumerState<DesktopDashboardView> createState() =>
      _DesktopDashboardViewState();
}

class _DesktopDashboardViewState extends ConsumerState<DesktopDashboardView> {
  String _selectedFilter = 'All';
  String? _hoveredArtistId;
  bool _isBannerHovered = false;

  static const List<String> _filters = [
    'All',
    'On Repeat',
    'Made For You',
    'Playlists',
    'New Releases',
  ];

  static const List<
          ({String id, String name, String imageUrl, String listeners})>
      _curatedPopularArtists = [
    (
      id: '223843195',
      name: 'Sai Abhyankkar',
      imageUrl:
          'https://cdn-images.dzcdn.net/images/artist/234646e93d6ab2923f3bdc363f53d330/500x500-000000-80-0-0.jpg',
      listeners: '3.2M monthly',
    ),
    (
      id: '491',
      name: 'A. R. Rahman',
      imageUrl:
          'https://cdn-images.dzcdn.net/images/artist/bd34315ef977a62a9e28c1ab19bb8ac4/500x500-000000-80-0-0.jpg',
      listeners: '14.8M monthly',
    ),
    (
      id: '1516162',
      name: 'Anirudh Ravichander',
      imageUrl:
          'https://cdn-images.dzcdn.net/images/artist/9da0a547b39e99bc35c6a9724aef91bf/500x500-000000-80-0-0.jpg',
      listeners: '18.4M monthly',
    ),
    (
      id: '362663',
      name: 'Harris Jayaraj',
      imageUrl:
          'https://cdn-images.dzcdn.net/images/artist/b10caf45eae518a2b16997874ded7143/500x500-000000-80-0-0.jpg',
      listeners: '8.6M monthly',
    ),
    (
      id: '3847661',
      name: 'Yuvan Shankar Raja',
      imageUrl:
          'https://cdn-images.dzcdn.net/images/artist/1dbf7d81a2e964d9c707e53478407974/500x500-000000-80-0-0.jpg',
      listeners: '9.1M monthly',
    ),
    (
      id: '4325950',
      name: 'Santhosh Narayanan',
      imageUrl:
          'https://cdn-images.dzcdn.net/images/artist/74004fed94dddf9ae2d7c83084eaf1ad/500x500-000000-80-0-0.jpg',
      listeners: '5.7M monthly',
    ),
  ];

  String _cleanTrackTitle(String title) {
    var cleaned = title
        .replaceAll(
            RegExp(
                r'\s*\([^)]*(From|Soundtrack|OST|Version|Audio|feat|ft\.)[^)]*\)',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(
                r'\s*\[[^\]]*(From|Soundtrack|OST|Version|Audio|feat|ft\.)[^\]]*\]',
                caseSensitive: false),
            '')
        .trim();
    return cleaned.isNotEmpty ? cleaned : title;
  }

  String _formatDurationMs(int? ms) {
    if (ms == null || ms <= 0) return '03:45';
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _onArtistSelected(String artistId, String artistName, String imageUrl) {
    final artist = ArtistModel(
      id: artistId,
      name: artistName,
      imageUrl: imageUrl,
    );
    if (widget.onArtistTap != null) {
      widget.onArtistTap!(artist);
      return;
    }
    try {
      context.push('/artist/$artistId', extra: artist);
    } catch (_) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ArtistDetailPage(
            artistId: artistId,
            initialArtist: artist,
          ),
        ),
      );
    }
  }

  void _playArtistTracks(String artistName, List<MediaSong> localSongs) {
    final cleanName = artistName.toLowerCase().trim();
    final matchingSongs = localSongs.where((s) {
      return s.artist.toLowerCase().contains(cleanName) ||
          cleanName.contains(s.artist.toLowerCase());
    }).toList();

    if (matchingSongs.isNotEmpty) {
      final queue = matchingSongs
          .map((s) => Track(
                id: s.id,
                title: _cleanTrackTitle(s.title),
                artist: s.artist,
                imageUrl: s.artworkPath,
                duration: _formatDurationMs(s.durationMs),
                filePath: s.filePath,
              ))
          .toList();

      ref.read(playerControllerProvider.notifier).setQueue(
            queue,
            startIndex: 0,
            playingFrom: 'Popular Artists • $artistName',
          );
    } else {
      final artistDef = _curatedPopularArtists.firstWhere(
        (a) => a.name.toLowerCase() == cleanName,
        orElse: () => (id: '0', name: artistName, imageUrl: '', listeners: ''),
      );
      _onArtistSelected(artistDef.id, artistDef.name, artistDef.imageUrl);
    }
  }

  void _playFeaturedSpotlight(List<MediaSong> localSongs) {
    final match = localSongs
        .where((s) =>
            s.title.toLowerCase().contains('kannukulla') ||
            s.artist.toLowerCase().contains('abhyankkar'))
        .firstOrNull;

    final Track trackToPlay;
    if (match != null) {
      trackToPlay = Track(
        id: match.id,
        title: _cleanTrackTitle(match.title),
        artist: match.artist,
        imageUrl: match.artworkPath,
        duration: _formatDurationMs(match.durationMs),
        filePath: match.filePath,
      );
    } else {
      trackToPlay = const Track(
        id: 'featured_spotlight_kannukulla',
        title: 'Kannukulla',
        artist: 'Sai Abhyankkar',
        imageUrl: '',
        duration: '04:38',
      );
    }

    ref.read(playerControllerProvider.notifier).playTrack(trackToPlay);
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(recentlyPlayedProvider);
    final history = historyAsync.valueOrNull ?? const <HistoryEntry>[];
    final localSongs = ref.watch(songsProvider);
    final dailyMixAsync = ref.watch(dailyMixSnapshotProvider);
    final userProfile = ref.watch(currentUserProfileProvider);

    // Resolve exactly 6 distinct, deduplicated Continue Listening items
    final continueItems = _resolveContinueListeningItems(history, localSongs);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── 1. Authentic Studio Ambient Lighting ──────────────────────
          // A. Primary Half-Circle Ambient Dome (Top-Center Edge)
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.06, -1.0),
                    radius: 0.78,
                    colors: [
                      Color(0xFFC89E78),
                      Color(0xCCA87E5E),
                      Color(0x756B4232),
                      Color(0x243A201A),
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.30, 0.60, 0.85, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // B. Co-anchored Baby Pink / Soft Rose Warmth (Top Edge, Right Half)
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.32, -1.0),
                    radius: 0.72,
                    colors: [
                      Color(0x8CB25850),
                      Color(0x55873E40),
                      Color(0x20501E24),
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.35, 0.70, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // C. Subtle Ambient Edge Vignette
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.5, 0.5),
                    radius: 1.45,
                    colors: [
                      Colors.transparent,
                      Color(0x300A080C),
                    ],
                    stops: [0.72, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── 2. Scrollable Content Body ────────────────────────────────
          SingleChildScrollView(
            padding: const EdgeInsets.only(
              left: 36,
              right: 36,
              top: 24,
              bottom: 120, // Buffer for floating pill player
            ),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top Header Row (Search Pill, Bell, Avatar) ────────
                _buildTopHeader(context, userProfile),

                const SizedBox(height: 18),

                // ── Quick Filter Chips (Tactile Micro-Filter) ─────────
                _buildFilterChipsRow(),

                const SizedBox(height: 22),

                // ── Editorial Hero Spotlight Banner (New Feature!) ────
                _buildFeaturedHeaderBanner(context, localSongs),

                const SizedBox(height: 28),

                // ── Section 1: Continue Listening ─────────────────────
                _buildSectionHeader(
                  title: 'Continue Listening',
                  actionLabel: 'See all >',
                  onAction: widget.onSeeAllContinue,
                ),
                const SizedBox(height: 14),
                _buildContinueListeningRow(context, continueItems),

                const SizedBox(height: 32),

                // ── Section 2: Popular Artists ────────────────────────
                _buildSectionHeader(
                  title: 'Popular Artists',
                  actionLabel: 'See all >',
                  onAction: widget.onSeeAllArtists,
                ),
                const SizedBox(height: 14),
                _buildPopularArtistsRow(context, localSongs),

                const SizedBox(height: 32),

                // ── Section 3: Daily Mixes ────────────────────────────
                _buildSectionHeader(
                  title: 'Daily Mixes',
                  actionLabel: 'See All >',
                  onAction: widget.onSeeAllMixes,
                ),
                const SizedBox(height: 14),
                _buildDailyMixesRow(context, dailyMixAsync, localSongs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Editorial Hero Spotlight Banner ───────────────────────────────────
  Widget _buildFeaturedHeaderBanner(
      BuildContext context, List<MediaSong> localSongs) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isBannerHovered = true),
      onExit: (_) => setState(() => _isBannerHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        height: 204,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xF02A1E2A),
              Color(0xEE1E1824),
              Color(0xF014111A),
            ],
          ),
          border: Border.all(
            color: _isBannerHovered
                ? const Color(0x35FFEBF0)
                : const Color(0x18FFEBF0),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.50),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
            if (_isBannerHovered)
              BoxShadow(
                color: const Color(0xFFE5A96A).withValues(alpha: 0.12),
                blurRadius: 28,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Ambient Right Warm Dome Glow
              Positioned(
                right: -40,
                top: -30,
                bottom: -30,
                width: 380,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.4, 0.0),
                        radius: 0.85,
                        colors: [
                          const Color(0xFFE5A96A).withValues(alpha: 0.22),
                          const Color(0xFFB25850).withValues(alpha: 0.12),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Banner Content Row
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                child: Row(
                  children: [
                    // Left Column: Editorial Details & Play Actions
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Overline Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE5A96A)
                                  .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE5A96A)
                                    .withValues(alpha: 0.35),
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              'FEATURED SPOTLIGHT',
                              style: GoogleFonts.inter(
                                fontSize: 9.0,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFF2C79A),
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),

                          const SizedBox(height: 6),

                          // Track Headline
                          Text(
                            'Kannukulla',
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.4,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                          const SizedBox(height: 2),

                          // Subtitle & Album Info
                          Text(
                            'Sai Abhyankkar • Dude Original Motion Picture Soundtrack',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFFE5A96A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                          const SizedBox(height: 5),

                          // Editorial Description
                          Text(
                            'Lush acoustic orchestration and infectious modern rhythms redefine contemporary Indian cinema music.',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFFA8A29E),
                              height: 1.25,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                          const SizedBox(height: 12),

                          // Actions Row
                          Row(
                            children: [
                              // Primary Play Button
                              InkWell(
                                onTap: () => _playFeaturedSpotlight(localSongs),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 7),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFF2C79A),
                                        Color(0xFFE5A96A),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFE5A96A)
                                            .withValues(alpha: 0.30),
                                        blurRadius: 10,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.play_arrow_rounded,
                                        size: 17,
                                        color: Color(0xFF16141B),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Play Now',
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF16141B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(width: 10),

                              // Secondary Save Button
                              InkWell(
                                onTap: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Added to Library'),
                                      duration: Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: const Color(0x33282330),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0x22FFEBF0),
                                      width: 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.bookmark_add_outlined,
                                        size: 15,
                                        color: Color(0xFFECE7E2),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Save Track',
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: const Color(0xFFECE7E2),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 24),

                    // Right Side: 3D Vinyl & Album Sleeve Motif
                    SizedBox(
                      width: 200,
                      height: 140,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          // Sliding Vinyl Record (Right)
                          Positioned(
                            right: 0,
                            child: AnimatedSlide(
                              offset: _isBannerHovered
                                  ? const Offset(0.06, 0)
                                  : Offset.zero,
                              duration: const Duration(milliseconds: 200),
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const RadialGradient(
                                    colors: [
                                      Color(0xFFE5A96A),
                                      Color(0xFF1E1A22),
                                      Color(0xFF0F0E12),
                                    ],
                                    stops: [0.15, 0.6, 1.0],
                                  ),
                                  border: Border.all(
                                    color: const Color(0x30E5A96A),
                                    width: 1.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.60),
                                      blurRadius: 14,
                                      offset: const Offset(4, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFFE5A96A),
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Color(0xFF121114),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Front Album Cover Sleeve
                          Container(
                            width: 130,
                            height: 130,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFB43830),
                                  Color(0xFF5A1D20),
                                ],
                              ),
                              border: Border.all(
                                color: const Color(0x30FFEBF0),
                                width: 1.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                children: [
                                  Image.asset(
                                    'assets/images/continue_cover_5.png',
                                    fit: BoxFit.cover,
                                    width: 130,
                                    height: 130,
                                    errorBuilder: (_, __, ___) => const Center(
                                      child: Text(
                                        'DUDE',
                                        style: TextStyle(
                                          color: Color(0xFFF2C79A),
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
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

  // ── Quick Filter Chips Row ────────────────────────────────────────────
  Widget _buildFilterChipsRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: _filters.map((filter) {
          final isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: InkWell(
              onTap: () {
                setState(() => _selectedFilter = filter);
              },
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0x38E5A96A)
                      : const Color(0x661A1720),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0x80E5A96A)
                        : const Color(0x14FFEBF0),
                    width: 1.0,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color:
                                const Color(0xFFE5A96A).withValues(alpha: 0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  filter,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? const Color(0xFFF2C79A)
                        : const Color(0xFF9E9793),
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Section 2: Popular Artists Row ────────────────────────────────────
  Widget _buildPopularArtistsRow(
      BuildContext context, List<MediaSong> localSongs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        const gap = 16.0;
        final cardWidth =
            (((totalWidth - (5 * gap)) / 6) * 1.06).clamp(136.0, 178.0);
        final avatarSize = (cardWidth * 0.72).clamp(96.0, 120.0);

        return SizedBox(
          height: avatarSize + 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _curatedPopularArtists.length,
            separatorBuilder: (_, __) => const SizedBox(width: gap),
            itemBuilder: (context, index) {
              final artist = _curatedPopularArtists[index];
              final isHovered = _hoveredArtistId == artist.id;

              return MouseRegion(
                onEnter: (_) => setState(() => _hoveredArtistId = artist.id),
                onExit: (_) => setState(() {
                  if (_hoveredArtistId == artist.id) _hoveredArtistId = null;
                }),
                child: InkWell(
                  onTap: () => _onArtistSelected(
                      artist.id, artist.name, artist.imageUrl),
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: cardWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Circular Avatar with Hover Play Badge
                        SizedBox(
                          width: avatarSize,
                          height: avatarSize,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Avatar Container
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                width: avatarSize,
                                height: avatarSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isHovered
                                        ? const Color(0x60E5A96A)
                                        : const Color(0x18FFEBF0),
                                    width: isHovered ? 1.8 : 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.45),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                    if (isHovered)
                                      BoxShadow(
                                        color: const Color(0xFFE5A96A)
                                            .withValues(alpha: 0.25),
                                        blurRadius: 16,
                                        spreadRadius: 1,
                                      ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: MieeArtworkImage(
                                    explicitUrl: artist.imageUrl,
                                    fit: BoxFit.cover,
                                    placeholder: _buildArtistMonogram(
                                        artist.name, avatarSize),
                                    errorWidget: _buildArtistMonogram(
                                        artist.name, avatarSize),
                                  ),
                                ),
                              ),

                              // Tactile Play Badge on Bottom-Right of Avatar
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: AnimatedScale(
                                  scale: isHovered ? 1.0 : 0.88,
                                  duration: const Duration(milliseconds: 140),
                                  child: Tooltip(
                                    message: 'Play ${artist.name}',
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _playArtistTracks(
                                            artist.name, localSongs),
                                        customBorder: const CircleBorder(),
                                        child: Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: const LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Color(0xFFF2C79A),
                                                Color(0xFFE5A96A),
                                              ],
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.50),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: const Center(
                                            child: Icon(
                                              Icons.play_arrow_rounded,
                                              size: 20,
                                              color: Color(0xFF16141B),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 9),

                        // Artist Name
                        Text(
                          artist.name,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isHovered
                                ? const Color(0xFFF2C79A)
                                : const Color(0xFFECE7E2),
                            letterSpacing: -0.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 2),

                        // Role / Subtitle
                        Text(
                          'Artist',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF9E9793),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildArtistMonogram(String name, double size) {
    final initials = name
        .trim()
        .split(' ')
        .map((p) => p.isNotEmpty ? p[0] : '')
        .take(2)
        .join();
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2C2433),
            Color(0xFF18151D),
          ],
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.inter(
            fontSize: size * 0.30,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFF2C79A),
          ),
        ),
      ),
    );
  }

  // ── Continue Listening Deduplication & Resolution ─────────────────────
  List<MusicItem> _resolveContinueListeningItems(
    List<HistoryEntry> history,
    List<MediaSong> localSongs,
  ) {
    final result = <MusicItem>[];
    final seenIds = <String>{};
    final seenTitles = <String>{};

    for (final entry in history) {
      if (result.length >= 6) break;
      try {
        final rawTrack = entry.track.toTrack();
        final normId = rawTrack.id.replaceFirst('youtube_', '').trim();
        final normTitle = _cleanTrackTitle(rawTrack.title).toLowerCase();

        if (seenIds.contains(rawTrack.id) ||
            seenIds.contains(normId) ||
            seenTitles.contains(normTitle)) {
          continue;
        }
        seenIds.add(rawTrack.id);
        seenIds.add(normId);
        seenTitles.add(normTitle);

        String resolvedArtwork = rawTrack.imageUrl;
        if (!rawTrack.isYoutube) {
          final localMatch = localSongs.where((s) {
            if (s.id == rawTrack.id || s.id == normId) return true;
            return _cleanTrackTitle(s.title).toLowerCase() == normTitle;
          }).firstOrNull;

          if (localMatch != null && localMatch.artworkPath.isNotEmpty) {
            resolvedArtwork = localMatch.artworkPath;
          }
        }

        result.add(Track(
          id: rawTrack.id,
          title: _cleanTrackTitle(rawTrack.title),
          artist: rawTrack.artist,
          imageUrl: resolvedArtwork,
          duration: rawTrack.duration,
          filePath: rawTrack.filePath,
        ));
      } catch (_) {}
    }

    if (result.length < 6 && localSongs.isNotEmpty) {
      for (final song in localSongs) {
        if (result.length >= 6) break;
        final normId = song.id.trim();
        final normTitle = _cleanTrackTitle(song.title).toLowerCase();
        if (seenIds.contains(normId) || seenTitles.contains(normTitle)) {
          continue;
        }
        seenIds.add(normId);
        seenTitles.add(normTitle);

        result.add(Track(
          id: normId,
          title: _cleanTrackTitle(song.title),
          artist: song.artist,
          imageUrl: song.artworkPath,
          duration: _formatDurationMs(song.durationMs),
          filePath: song.filePath,
        ));
      }
    }

    if (result.length < 6) {
      final studioFallbacks = [
        (title: 'Vaazhanum Baththa', artist: 'Sai Abhyankkar & Karthik Netha'),
        (title: 'Magale', artist: 'Sai Abhyankkar'),
        (title: 'Vizhi Veekura', artist: 'Sai Abhyankkar'),
        (title: 'Sithira Puthiri', artist: 'Sai Abhyankkar'),
        (title: 'Kannukulla', artist: 'Sai Abhyankkar'),
        (title: 'Veera Veera Lyrical', artist: 'Sai Abhyankkar'),
      ];

      for (var i = result.length; i < 6; i++) {
        final fb = studioFallbacks[i % studioFallbacks.length];
        result.add(Track(
          id: 'miee_studio_ref_$i',
          title: fb.title,
          artist: fb.artist,
          imageUrl: '',
          duration: '03:45',
        ));
      }
    }

    return result;
  }

  // ── Top Header (Search Pill, Bell, Avatar) ─────────────────────────────
  Widget _buildTopHeader(BuildContext context, UserProfile? userProfile) {
    return Row(
      children: [
        const Spacer(),

        // Search Pill
        InkWell(
          onTap: widget.onSearchTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 180,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0x661E1A22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0x14FFEBF0),
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  size: 15,
                  color: Color(0xFF78716C),
                ),
                const SizedBox(width: 6),
                Text(
                  'Search',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF78716C),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 14),

        // Notification Bell with Amber Dot
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded),
              iconSize: 18,
              color: const Color(0xFFA8A29E),
              onPressed: () => NotificationSheet.show(context),
              tooltip: 'Notifications',
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              padding: EdgeInsets.zero,
            ),
            Positioned(
              top: 7,
              right: 7,
              child: Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: Color(0xFFE5A96A),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x50E5A96A),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(width: 8),

        // Circular User Profile Avatar
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF282330),
            border: Border.all(
              color: const Color(0x26FFEBF0),
              width: 1.0,
            ),
          ),
          child: ClipOval(
            child: (userProfile?.avatarUrl != null &&
                    userProfile!.avatarUrl!.isNotEmpty)
                ? Image.network(
                    userProfile.avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _buildAvatarInitial(userProfile),
                  )
                : _buildAvatarInitial(userProfile),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarInitial(UserProfile? userProfile) {
    final initial = (userProfile?.displayName.trim().isNotEmpty ?? false)
        ? userProfile!.displayName.trim()[0].toUpperCase()
        : 'R';
    return Center(
      child: Text(
        initial,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: const Color(0xFFECE7E2),
        ),
      ),
    );
  }

  // ── Section Header ────────────────────────────────────────────────────
  Widget _buildSectionHeader({
    required String title,
    required String actionLabel,
    VoidCallback? onAction,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFECE7E2),
            letterSpacing: -0.2,
          ),
        ),
        InkWell(
          onTap: onAction,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              actionLabel,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF78716C),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Section 1: Continue Listening Row ─────────────────────────────────
  Widget _buildContinueListeningRow(
    BuildContext context,
    List<MusicItem> items,
  ) {
    if (items.isEmpty) {
      return _buildContinueEmptyState();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        const gap = 16.0;
        final cardWidth =
            (((totalWidth - (5 * gap)) / 6) * 1.06).clamp(136.0, 178.0);

        return SizedBox(
          height: cardWidth + 54,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: gap),
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildContinueListeningCard(
                  context, item, items, index, cardWidth);
            },
          ),
        );
      },
    );
  }

  Widget _buildContinueListeningCard(
    BuildContext context,
    MusicItem item,
    List<MusicItem> queue,
    int index,
    double cardWidth,
  ) {
    final hasValidArtwork = item.effectiveArtworkUrl.isNotEmpty &&
        !item.effectiveArtworkUrl.contains('default_') &&
        !item.effectiveArtworkUrl.contains('empty');

    return InkWell(
      onTap: () {
        ref.read(playerControllerProvider.notifier).setQueue(
              queue,
              startIndex: index,
              playingFrom: 'Continue Listening',
            );
      },
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Square Album Artwork
            Container(
              width: cardWidth,
              height: cardWidth,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0x10FFEBF0),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.40),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: hasValidArtwork
                    ? MieeArtworkImage(
                        explicitUrl: item.effectiveArtworkUrl,
                        fit: BoxFit.cover,
                        placeholder: _buildDarkAbstractPlaceholder(index),
                        errorWidget: _buildDarkAbstractPlaceholder(index),
                      )
                    : _buildDarkAbstractPlaceholder(index),
              ),
            ),

            const SizedBox(height: 8),

            // Track Title
            Text(
              item.displayTitle,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFECE7E2),
                letterSpacing: -0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 2),

            // Artist / Meta Subtitle
            Text(
              item.artist,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF9E9793),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Authentic Midnight Velvet studio sleeve artwork placeholder
  Widget _buildDarkAbstractPlaceholder(int index) {
    final assetIndex = (index % 6) + 1;
    return Image.asset(
      'assets/images/continue_cover_$assetIndex.png',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2C2433), Color(0xFF18151D)],
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.album_rounded,
            size: 26,
            color: Color(0x60E5A96A),
          ),
        ),
      ),
    );
  }

  Widget _buildContinueEmptyState() {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: MidnightVelvetTokens.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: MidnightVelvetTokens.hairlineRim,
          width: 1.0,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.music_note_rounded,
              size: 28,
              color: MidnightVelvetTokens.textMuted,
            ),
            const SizedBox(height: 6),
            Text(
              'No Recent Sessions',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFECE7E2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section 3: Daily Mixes Row ────────────────────────────────────────
  Widget _buildDailyMixesRow(
    BuildContext context,
    AsyncValue<dynamic> dailyMixAsync,
    List<MediaSong> localSongs,
  ) {
    final existingMixes = <DailyMix>[];
    if (dailyMixAsync.hasValue && dailyMixAsync.value != null) {
      final snapshot = dailyMixAsync.value;
      if (snapshot.mixes is List<DailyMix>) {
        existingMixes.addAll(snapshot.mixes as List<DailyMix>);
      }
    }

    final fullMixes = _resolveFullDailyMixes(existingMixes, localSongs);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        const gap = 16.0;
        final cardWidth = ((totalWidth - (5 * gap)) / 6).clamp(128.0, 168.0);
        final cardHeight = cardWidth * 1.30;

        return SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: fullMixes.length,
            separatorBuilder: (_, __) => const SizedBox(width: gap),
            itemBuilder: (context, index) {
              final mix = fullMixes[index];
              return _buildDailyMixCard(context, mix, index, cardWidth);
            },
          ),
        );
      },
    );
  }

  List<DailyMix> _resolveFullDailyMixes(
      List<DailyMix> existing, List<MediaSong> localSongs) {
    final mixes = List<DailyMix>.from(existing);

    final curatedDefinitions = [
      (title: 'Daily Mix 1', subtitle: 'Rloe amite • Rose-Ember'),
      (title: 'Daily Mix 2', subtitle: 'Aimarotoo • Champagne Gold'),
      (title: 'Daily Mix 3', subtitle: 'My Rene • Rose-Ember'),
      (title: 'Daily Mix 4', subtitle: 'Miee Brand • Champagne Gold'),
      (title: 'Daily Mix 5', subtitle: 'Jotn Reon • Rose-Ember'),
      (title: 'Daily Mix 6', subtitle: 'My Sffort • Champagne Gold'),
    ];

    while (mixes.length < 6) {
      final index = mixes.length;
      final def = curatedDefinitions[index % curatedDefinitions.length];

      final sampleTracks = <Track>[];
      if (localSongs.isNotEmpty) {
        final start = (index * 4) % localSongs.length;
        for (var i = 0; i < math.min(4, localSongs.length); i++) {
          final s = localSongs[(start + i) % localSongs.length];
          sampleTracks.add(Track(
            id: s.id,
            title: _cleanTrackTitle(s.title),
            artist: s.artist,
            imageUrl: s.artworkPath,
            duration: _formatDurationMs(s.durationMs),
            filePath: s.filePath,
          ));
        }
      }

      mixes.add(DailyMix(
        id: 'curated_mix_${index + 1}',
        title: def.title,
        subtitle: def.subtitle,
        tracks: sampleTracks,
        coverImageUrl: null,
      ));
    }

    return mixes.take(6).toList();
  }

  Widget _buildDailyMixCard(
    BuildContext context,
    DailyMix mix,
    int index,
    double cardWidth,
  ) {
    final artworkWidth = cardWidth - 18;
    final artworkHeight = artworkWidth * 0.92;

    return InkWell(
      onTap: () {
        if (mix.tracks.isNotEmpty) {
          ref.read(playerControllerProvider.notifier).playDailyMix(mix);
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: cardWidth,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: const Color(0xFF16141B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0x14FFEBF0),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.40),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: artworkWidth,
              height: artworkHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/images/mix_cover_${(index % 6) + 1}.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _buildAbstractMixPlaceholder(index),
                ),
              ),
            ),

            const SizedBox(height: 7),

            // Mix Title
            Text(
              mix.title,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFECE7E2),
                letterSpacing: -0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 1.5),

            // Artist / Subtitle
            Text(
              mix.subtitle,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF9E9793),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Authentic Midnight Velvet editorial mix artwork sleeve placeholder
  Widget _buildAbstractMixPlaceholder(int index) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C2433), Color(0xFF18151D)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.album_rounded,
              size: 26,
              color: const Color(0xFFE5A96A).withValues(alpha: 0.70),
            ),
            const SizedBox(height: 4),
            Text(
              'Daily Mix ${(index % 6) + 1}',
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                color: const Color(0xFFC7A280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
