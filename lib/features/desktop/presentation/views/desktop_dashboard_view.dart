import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/midnight_velvet_tokens.dart';
import '../../../../core/audio/providers.dart';
import '../../../../core/storage/adapters/history_entry.dart';
import '../../../../shared/models/music_item.dart';
import '../../../../shared/models/track.dart';
import '../../../artwork/presentation/miee_artwork_image.dart';
import '../../../library/providers/library_providers.dart';
import '../../../media/domain/models.dart';
import '../../../media/providers/media_providers.dart';
import '../../../profile/domain/user_profile.dart';
import '../../../profile/providers/profile_providers.dart';
import '../../../recommendations/domain/daily_mix.dart';
import '../../../recommendations/presentation/daily_mix_playback_helper.dart';
import '../../../recommendations/providers/daily_mix_providers.dart';

/// The Desktop Primary Dashboard View strictly reproducing the
/// First Reference Design Image (Miee Desktop — Midnight Velvet & Warm Studio).
class DesktopDashboardView extends ConsumerWidget {
  final VoidCallback? onSearchTap;
  final VoidCallback? onSeeAllContinue;
  final VoidCallback? onSeeAllMixes;

  const DesktopDashboardView({
    super.key,
    this.onSearchTap,
    this.onSeeAllContinue,
    this.onSeeAllMixes,
  });

  String _cleanTrackTitle(String title) {
    var cleaned = title
        .replaceAll(RegExp(r'\s*\([^)]*(From|Soundtrack|OST|Version|Audio|feat|ft\.)[^)]*\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\[[^\]]*(From|Soundtrack|OST|Version|Audio|feat|ft\.)[^\]]*\]', caseSensitive: false), '')
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          // Measured directly from reference: Prominent, soft half-circle ambient
          // light dome centered at top edge, radiating downward across Continue
          // Listening with warm champagne gold and baby pink / rose tint on the right.
          //
          // A. Primary Half-Circle Ambient Dome (Top-Center Edge)
          // Geometrically anchored at y = -1.0 so it forms a clean arched half-circle dome.
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.06, -1.0), // Anchored directly on top edge for true half-circle
                    radius: 0.78, // Arched semi-circle dome spanning Continue Listening
                    colors: [
                      Color(0xFFC89E78), // Radiant warm champagne gold peak (RGB 167, 130, 103)
                      Color(0xCCA87E5E), // Warm champagne amber transition
                      Color(0x756B4232), // Warm bronze-amber bathing Continue Listening
                      Color(0x243A201A), // Soft half-circle outer contour falloff
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.30, 0.60, 0.85, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // B. Co-anchored Baby Pink / Soft Rose Warmth (Top Edge, Right Half)
          // Also anchored at top edge (y = -1.0) to preserve the pure half-circle geometry
          // while infusing the soft baby pink shade across the right side of the dome.
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.32, -1.0), // Top edge right-bias
                    radius: 0.72,
                    colors: [
                      Color(0x8CB25850), // Soft baby pink / rose ember light
                      Color(0x55873E40), // Warm rose-terracotta tint
                      Color(0x20501E24), // Subtle ambient rose feathering
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
                      Color(0x300A080C), // Subtle edge vignette
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
              bottom: 110, // Buffer for floating pill player
            ),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top Header Row ────────────────────────────────────
                _buildTopHeader(context, userProfile),

                const SizedBox(height: 28),

                // ── Section 1: Continue Listening ─────────────────────
                _buildSectionHeader(
                  title: 'Continue Listening',
                  actionLabel: 'See all >',
                  onAction: onSeeAllContinue,
                ),
                const SizedBox(height: 14),
                _buildContinueListeningRow(context, ref, continueItems),

                const SizedBox(height: 32),

                // ── Section 2: Daily Mixes ────────────────────────────
                _buildSectionHeader(
                  title: 'Daily Mixes',
                  actionLabel: 'See All >',
                  onAction: onSeeAllMixes,
                ),
                const SizedBox(height: 14),
                _buildDailyMixesRow(context, ref, dailyMixAsync, localSongs),
              ],
            ),
          ),
        ],
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

    // 1. Process recent playback history with strict deduplication
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

        // Resolve artwork against local songs if not a full web URL
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

    // 2. Supplement with unique local songs if fewer than 6
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

    // 3. Fallback aesthetic studio tracks strictly matching reference image
    if (result.length < 6) {
      final studioFallbacks = [
        (title: 'Amasonic', artist: 'Rose-Ember'),
        (title: 'Champagne Gold', artist: 'Rose-Ember'),
        (title: 'Samak', artist: 'Evwonne'),
        (title: 'Suromeno', artist: 'Rose-Ember'),
        (title: 'The illing Rose', artist: 'Rose-Ember'),
        (title: 'Bang & Olufsen', artist: 'Teenage-Velvet'),
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

  // ── Top Header ────────────────────────────────────────────────────────
  Widget _buildTopHeader(BuildContext context, UserProfile? userProfile) {
    return Row(
      children: [
        // Heading - Smaller and restrained matching reference
        Text(
          'Dashboard',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFECE7E2),
            letterSpacing: -0.3,
          ),
        ),

        const Spacer(),

        // Search Pill
        InkWell(
          onTap: onSearchTap,
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
              onPressed: () {},
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
            child: (userProfile?.avatarUrl != null && userProfile!.avatarUrl!.isNotEmpty)
                ? Image.network(
                    userProfile.avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildAvatarInitial(userProfile),
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
    WidgetRef ref,
    List<MusicItem> items,
  ) {
    if (items.isEmpty) {
      return _buildContinueEmptyState();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        const gap = 16.0;
        final cardWidth = (((totalWidth - (5 * gap)) / 6) * 1.06).clamp(136.0, 178.0);

        return SizedBox(
          height: cardWidth + 54,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: gap),
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildContinueListeningCard(context, ref, item, items, index, cardWidth);
            },
          ),
        );
      },
    );
  }

  Widget _buildContinueListeningCard(
    BuildContext context,
    WidgetRef ref,
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
            // Square Album Artwork (Dynamically sized to span row width)
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

  /// Authentic Midnight Velvet studio sleeve artwork placeholder (never light-grey or empty icon)
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

  // ── Section 2: Daily Mixes Row ────────────────────────────────────────
  Widget _buildDailyMixesRow(
    BuildContext context,
    WidgetRef ref,
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

    // Always guarantee exactly 6 full Daily Mix cards across the view
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
              return _buildDailyMixCard(context, ref, mix, index, cardWidth);
            },
          ),
        );
      },
    );
  }

  List<DailyMix> _resolveFullDailyMixes(List<DailyMix> existing, List<MediaSong> localSongs) {
    final mixes = List<DailyMix>.from(existing);

    // Exact curated metadata directly matching the First Reference Design Image
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
    WidgetRef ref,
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
          color: const Color(0xFF16141B), // Clean smoked espresso velvet matching reference
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
            // Authentic editorial artwork sleeve with organic wave cutout and 'Daily Mixe'
            SizedBox(
              width: artworkWidth,
              height: artworkHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/images/mix_cover_${(index % 6) + 1}.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildAbstractMixPlaceholder(index),
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
