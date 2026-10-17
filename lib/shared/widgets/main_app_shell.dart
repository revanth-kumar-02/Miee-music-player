import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/audio/playback_state.dart' as pb;
import '../../core/audio/providers.dart';
import '../../features/playlists/presentation/widgets/create_playlist_dialog.dart';
import '../../features/playlists/providers/playlist_providers.dart';
import '../../features/profile/presentation/profile_controller.dart';
import '../../features/profile/providers/profile_providers.dart';
import '../../features/library/providers/library_providers.dart';
import '../../features/search/providers/search_providers.dart';
import '../../shared/models/track.dart';
import '../../shared/widgets/widgets.dart';

/// The unified Shell Layout wrapper for Miee Web.
/// Matches the reference design:
/// - Cocoa Plum fixed left sidebar (#3A252B) with Dusty Rose active pill (#D78D9B)
/// - Vanilla Cream primary content canvas (#F8F1E8)
/// - Top bar with pill search input, notification icon, profile avatar
/// - Persistent bottom playback bar in cream/white with Dusty Rose circular play button
/// - Cocoa Plum Now Playing right panel drawer
class MainAppShell extends ConsumerStatefulWidget {
  final Widget child;

  const MainAppShell({super.key, required this.child});

  @override
  ConsumerState<MainAppShell> createState() => _MainAppShellState();
}

class _MainAppShellState extends ConsumerState<MainAppShell> {
  bool _isNowPlayingDrawerOpen = false;
  final TextEditingController _topSearchController = TextEditingController();

  @override
  void dispose() {
    _topSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 960;
    final isTablet = screenWidth >= 650 && screenWidth < 960;

    final playback = ref.watch(playerControllerProvider);
    final uriPath = GoRouterState.of(context).uri.path;
    final isNowPlayingRoute = location == '/player' || uriPath == '/player';

    // Detail screens where mobile bottom nav is hidden
    final hideBottomNav = (isNowPlayingRoute ||
        location == '/queue' ||
        location == '/' ||
        location.startsWith('/playlist/') ||
        location.startsWith('/album/') ||
        location.startsWith('/artist/') ||
        location.startsWith('/genre/') ||
        location == '/local-songs' ||
        location == '/liked-songs');

    // ── MOBILE & COMPACT TABLET LAYOUT ──
    if (!isDesktop) {
      return Scaffold(
        backgroundColor: AppColors.vanillaCream,
        body: Stack(
          children: [
            Positioned.fill(child: widget.child),
            // Floating MiniPlayer (Visible on all screens EXCEPT full Now Playing)
            if (!isNowPlayingRoute && playback.currentTrack != null)
              Positioned(
                left: AppSpacing.sm,
                right: AppSpacing.sm,
                bottom: (hideBottomNav ? 12.0 : 88.0) +
                    MediaQuery.of(context).padding.bottom,
                child: _buildMobileMiniPlayer(context, playback),
              ),
            // Bottom Navigation
            if (!hideBottomNav)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: BottomNavigation(
                  currentIndex: _getNavIndex(location),
                  onTap: (index) => _handleNavigation(context, index),
                ),
              ),
          ],
        ),
      );
    }

    // ── DESKTOP VIEWPORT (~1536 x 1024 Reference Layout) ──
    const double sidebarWidth = 215.0;
    const double playerHeight = 84.0;
    const double topBarHeight = 56.0;

    final hasTrack = playback.currentTrack != null;
    final showDrawer = _isNowPlayingDrawerOpen && hasTrack;

    return Scaffold(
      backgroundColor: AppColors.vanillaCream,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. Cocoa Plum Left Sidebar ──
          SizedBox(
            width: isTablet ? 76.0 : sidebarWidth,
            child: _buildDesktopSidebar(context, location, isTablet),
          ),

          // ── 2. Vanilla Cream Main Canvas + TopBar + Bottom Player ──
          Expanded(
            child: Stack(
              children: [
                // Scrollable main canvas
                Positioned(
                  left: 0,
                  top: topBarHeight + 16,
                  right: showDrawer ? 320.0 : 0,
                  bottom: hasTrack ? (playerHeight + 28) : 16,
                  child: widget.child,
                ),

                // Top Header Bar
                Positioned(
                  left: 0,
                  top: 0,
                  right: showDrawer ? 320.0 : 0,
                  height: topBarHeight + 16,
                  child: _buildTopHeaderBar(context),
                ),

                // Persistent Bottom Player
                if (hasTrack)
                  Positioned(
                    left: 20.0,
                    right: showDrawer ? 340.0 : 20.0,
                    bottom: 14.0,
                    height: playerHeight,
                    child: _buildDesktopPlayerBar(playback),
                  ),

                // Cocoa Plum Now Playing Right Drawer
                if (showDrawer)
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: 320.0,
                    child: _buildNowPlayingPanel(playback),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── DESKTOP SIDEBAR ────────────────────────────────────────────────────────

  Widget _buildDesktopSidebar(
      BuildContext context, String location, bool isCollapsed) {
    final playlistsState = ref.watch(playlistControllerProvider);
    final userPlaylists = playlistsState.playlists;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cocoaPlum,
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo & Branding
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 16, 20),
            child: isCollapsed
                ? const Center(
                    child: MieeWaveSymbol(size: 26, color: AppColors.dustyRose),
                  )
                : const MieeReferenceLogo(
                    symbolSize: 26,
                    fontSize: 24,
                    symbolColor: AppColors.dustyRose,
                    textColor: AppColors.vanillaCream,
                    isDarkBackground: true,
                  ),
          ),

          // Primary Navigation Items
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                _buildNavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Home',
                  isSelected: location == '/home',
                  isCollapsed: isCollapsed,
                  onTap: () => context.go('/home'),
                ),
                _buildNavItem(
                  icon: Icons.search_rounded,
                  activeIcon: Icons.search_rounded,
                  label: 'Search',
                  isSelected: location == '/search',
                  isCollapsed: isCollapsed,
                  onTap: () => context.go('/search'),
                ),
                _buildNavItem(
                  icon: Icons.auto_stories_outlined,
                  activeIcon: Icons.auto_stories_rounded,
                  label: 'Your Library',
                  isSelected: location == '/playlists',
                  isCollapsed: isCollapsed,
                  onTap: () => context.go('/playlists'),
                ),
                _buildNavItem(
                  icon: Icons.queue_music_rounded,
                  activeIcon: Icons.queue_music_rounded,
                  label: 'Playlists',
                  isSelected: location.startsWith('/playlist/'),
                  isCollapsed: isCollapsed,
                  onTap: () => context.go('/playlists'),
                ),
                _buildNavItem(
                  icon: Icons.favorite_border_rounded,
                  activeIcon: Icons.favorite_rounded,
                  label: 'Liked Songs',
                  isSelected: location == '/liked-songs',
                  isCollapsed: isCollapsed,
                  onTap: () => context.go('/liked-songs'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          if (!isCollapsed) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(
                color: AppColors.white.withOpacity(0.12),
                height: 1,
              ),
            ),
            const SizedBox(height: 16),

            // "PLAYLISTS" Section Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'PLAYLISTS',
                style: GoogleFonts.geist(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.softClay.withOpacity(0.7),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Playlists list (user playlists or clean prompt)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  if (userPlaylists.isNotEmpty)
                    ...userPlaylists.map(
                      (p) => _buildPlaylistTile(
                        title: p.name,
                        songCount: '${p.tracks.length} songs',
                        thumbnail: p.customCoverPath,
                        fallbackColor: AppColors.softClay,
                        onTap: () => context.go('/playlist/${p.id}'),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Text(
                        'No playlists created yet',
                        style: GoogleFonts.geist(
                          fontSize: 12,
                          color: AppColors.softClay.withOpacity(0.6),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // "+ New Playlist" action at the bottom
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: InkWell(
                onTap: () => showCreatePlaylistDialog(context),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.white.withOpacity(0.18),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.add,
                        size: 18,
                        color: AppColors.vanillaCream,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'New Playlist',
                        style: GoogleFonts.geist(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.vanillaCream,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isSelected,
    required bool isCollapsed,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 42,
            padding: EdgeInsets.symmetric(
              horizontal: isCollapsed ? 0 : 12,
            ),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.dustyRose : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: isCollapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  size: 20,
                  color: isSelected
                      ? AppColors.white
                      : AppColors.vanillaCream.withOpacity(0.85),
                ),
                if (!isCollapsed) ...[
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: GoogleFonts.geist(
                      fontSize: 13.5,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? AppColors.white
                          : AppColors.vanillaCream.withOpacity(0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistTile({
    required String title,
    required String songCount,
    String? thumbnail,
    required Color fallbackColor,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: thumbnail != null && thumbnail.isNotEmpty
                    ? Image.network(
                        thumbnail,
                        width: 34,
                        height: 34,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 34,
                          height: 34,
                          color: fallbackColor,
                          child: const Icon(
                            Icons.music_note,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : Container(
                        width: 34,
                        height: 34,
                        color: fallbackColor,
                        child: const Icon(
                          Icons.music_note,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.geist(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.vanillaCream,
                      ),
                    ),
                    Text(
                      songCount,
                      style: GoogleFonts.geist(
                        fontSize: 11,
                        color: AppColors.softClay.withOpacity(0.65),
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

  // ── TOPBAR (Header on Vanilla Cream Canvas) ────────────────────────────────

  Widget _buildTopHeaderBar(BuildContext context) {
    final localProfile = ref.watch(profileProvider);
    final cloudProfile = ref.watch(currentUserProfileProvider);
    final effectiveName = (cloudProfile?.displayName.trim().isNotEmpty ?? false)
        ? cloudProfile!.displayName
        : localProfile.displayName;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 6),
      child: Row(
        children: [
          // Search Field (Pill Shape)
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: AppColors.oatBeige,
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.cocoaPlum.withOpacity(0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _topSearchController,
                    onSubmitted: (query) {
                      final trimmed = query.trim();
                      if (trimmed.isNotEmpty) {
                        ref
                            .read(searchNotifierProvider.notifier)
                            .updateQuery(trimmed);
                        ref
                            .read(searchNotifierProvider.notifier)
                            .searchNow(trimmed);
                        context.go('/search');
                      }
                    },
                    style: GoogleFonts.geist(
                      fontSize: 13.5,
                      color: AppColors.cocoaPlum,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 11,
                        horizontal: 16,
                      ),
                      border: InputBorder.none,
                      hintText: 'Search songs, artists, albums...',
                      hintStyle: GoogleFonts.geist(
                        fontSize: 13,
                        color: AppColors.mutedMauve,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: AppColors.mutedMauve,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Notification Bell
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.white,
              border: Border.all(color: AppColors.oatBeige, width: 1.0),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.notifications_none_rounded,
                size: 20,
                color: AppColors.cocoaPlum,
              ),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("You're all caught up! No new notifications."),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ),

          const SizedBox(width: 12),

          // User Profile Avatar
          InkWell(
            onTap: () => context.go('/profile'),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.softClay,
                border: Border.all(color: AppColors.oatBeige, width: 1.5),
                image: (cloudProfile?.avatarUrl != null &&
                        cloudProfile!.avatarUrl!.isNotEmpty)
                    ? DecorationImage(
                        image: NetworkImage(cloudProfile.avatarUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              alignment: Alignment.center,
              child: (cloudProfile?.avatarUrl == null ||
                      cloudProfile!.avatarUrl!.isEmpty)
                  ? Text(
                      effectiveName.isNotEmpty
                          ? effectiveName[0].toUpperCase()
                          : 'M',
                      style: GoogleFonts.geist(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.cocoaPlum,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  // ── PERSISTENT DESKTOP PLAYER BAR ──────────────────────────────────────────

  Widget _buildDesktopPlayerBar(pb.PlaybackState playback) {
    final track = playback.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final isPlaying = playback.status == pb.PlaybackStatus.playing;
    final progress = playback.duration.inMilliseconds > 0
        ? (playback.position.inMilliseconds /
                playback.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    final favorites = ref.watch(favoritesProvider);
    final isLiked = favorites.any((t) => t.id == track.id);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.oatBeige, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: AppColors.cocoaPlum.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Left: Artwork + Title + Artist + Like Action ──
          GestureDetector(
            onTap: () {
              setState(() {
                _isNowPlayingDrawerOpen = !_isNowPlayingDrawerOpen;
              });
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                track.imageUrl,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 50,
                  height: 50,
                  color: AppColors.softClay,
                  child: const Icon(
                    Icons.music_note_rounded,
                    color: AppColors.cocoaPlum,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.geist(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.geist(
                    fontSize: 11.5,
                    color: AppColors.mutedMauve,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 6),

          // Heart Like Action
          IconButton(
            icon: Icon(
              isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isLiked ? AppColors.dustyRose : AppColors.mutedMauve,
              size: 20,
            ),
            splashRadius: 18,
            onPressed: () {
              final favNotifier = ref.read(favoritesProvider.notifier);
              if (isLiked) {
                favNotifier.removeFavorite(track.id);
              } else {
                favNotifier.addFavorite(
                  Track(
                    id: track.id,
                    title: track.title,
                    artist: track.artist,
                    imageUrl: track.imageUrl,
                    duration: track.duration,
                    filePath: track.filePath,
                  ),
                );
              }
            },
          ),

          const Spacer(),

          // ── Center: Playback Controls & Progress Slider ──
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Controls Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Shuffle
                    IconButton(
                      icon: const Icon(Icons.shuffle_rounded),
                      iconSize: 18,
                      color: playback.isShuffleEnabled
                          ? AppColors.dustyRose
                          : AppColors.mutedMauve,
                      splashRadius: 16,
                      onPressed: () => ref
                          .read(playerControllerProvider.notifier)
                          .toggleShuffle(),
                    ),
                    const SizedBox(width: 4),

                    // Previous
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded),
                      iconSize: 22,
                      color: AppColors.cocoaPlum,
                      splashRadius: 16,
                      onPressed: () => ref
                          .read(playerControllerProvider.notifier)
                          .previous(),
                    ),
                    const SizedBox(width: 8),

                    // Circular Dusty Rose Play/Pause Button
                    Material(
                      color: AppColors.dustyRose,
                      shape: const CircleBorder(),
                      elevation: 2,
                      shadowColor: AppColors.dustyRose.withOpacity(0.4),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          if (isPlaying) {
                            ref.read(playerControllerProvider.notifier).pause();
                          } else {
                            ref.read(playerControllerProvider.notifier).play();
                          }
                        },
                        child: Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          child: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 22,
                            color: AppColors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Next
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded),
                      iconSize: 22,
                      color: AppColors.cocoaPlum,
                      splashRadius: 16,
                      onPressed: () =>
                          ref.read(playerControllerProvider.notifier).next(),
                    ),
                    const SizedBox(width: 4),

                    // Repeat
                    IconButton(
                      icon: const Icon(Icons.repeat_rounded),
                      iconSize: 18,
                      color: playback.repeatMode != pb.RepeatMode.off
                          ? AppColors.dustyRose
                          : AppColors.mutedMauve,
                      splashRadius: 16,
                      onPressed: () => ref
                          .read(playerControllerProvider.notifier)
                          .toggleRepeatMode(),
                    ),
                  ],
                ),

                // Seek Progress Waveform Row
                Row(
                  children: [
                    Text(
                      _formatDuration(playback.position),
                      style: GoogleFonts.geist(
                        fontSize: 11,
                        color: AppColors.mutedMauve,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: WaveformWidget(
                        height: 24.0,
                        isPlaying: isPlaying,
                        activeProgress: progress,
                        activeColor: AppColors.dustyRose,
                        inactiveColor: AppColors.oatBeige,
                        onScrub: (val) {
                          final seekPos = Duration(
                            milliseconds:
                                (val * playback.duration.inMilliseconds).toInt(),
                          );
                          ref
                              .read(playerControllerProvider.notifier)
                              .seek(seekPos);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _formatDuration(playback.duration),
                      style: GoogleFonts.geist(
                        fontSize: 11,
                        color: AppColors.mutedMauve,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Spacer(),

          // ── Right: Queue / Lyrics / Volume / Equalizer ──
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.playlist_play_rounded),
                iconSize: 22,
                color: _isNowPlayingDrawerOpen
                    ? AppColors.dustyRose
                    : AppColors.cocoaPlum,
                splashRadius: 18,
                onPressed: () {
                  setState(() {
                    _isNowPlayingDrawerOpen = !_isNowPlayingDrawerOpen;
                  });
                },
              ),
              IconButton(
                icon: Icon(
                  playback.volume == 0
                      ? Icons.volume_off_rounded
                      : (playback.volume < 0.5
                          ? Icons.volume_down_rounded
                          : Icons.volume_up_rounded),
                ),
                iconSize: 20,
                color: AppColors.cocoaPlum,
                splashRadius: 18,
                onPressed: () {
                  final newVol = playback.volume > 0 ? 0.0 : 1.0;
                  ref.read(playerControllerProvider.notifier).setVolume(newVol);
                },
              ),
              SizedBox(
                width: 76,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.0,
                    activeTrackColor: AppColors.dustyRose,
                    inactiveTrackColor: AppColors.oatBeige,
                    thumbColor: AppColors.dustyRose,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 4.5,
                    ),
                  ),
                  child: Slider(
                    value: playback.volume.clamp(0.0, 1.0),
                    onChanged: (v) {
                      ref.read(playerControllerProvider.notifier).setVolume(v);
                    },
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.tune_rounded),
                iconSize: 18,
                color: AppColors.mutedMauve,
                splashRadius: 18,
                onPressed: () => context.go('/settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── COCOA PLUM NOW PLAYING PANEL (Right Drawer on Desktop) ─────────────────

  Widget _buildNowPlayingPanel(pb.PlaybackState playback) {
    final track = playback.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final isPlaying = playback.status == pb.PlaybackStatus.playing;
    final progress = playback.duration.inMilliseconds > 0
        ? (playback.position.inMilliseconds /
                playback.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    final favorites = ref.watch(favoritesProvider);
    final isLiked = favorites.any((t) => t.id == track.id);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cocoaPlum,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          bottomLeft: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        children: [
          // Header: Chevron down + "PLAYING FROM" + 3-dots
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.vanillaCream,
                  size: 24,
                ),
                onPressed: () {
                  setState(() => _isNowPlayingDrawerOpen = false);
                },
              ),
              Column(
                children: [
                  Text(
                    'PLAYING FROM',
                    style: GoogleFonts.geist(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: AppColors.softClay.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    playback.playingFrom ??
                        (track.artist.isNotEmpty ? track.artist : 'Now Playing'),
                    style: GoogleFonts.geist(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.vanillaCream,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: AppColors.vanillaCream,
                  size: 20,
                ),
                onPressed: () {},
              ),
            ],
          ),

          const Spacer(),

          // Large Square Album Artwork
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240, maxHeight: 240),
            child: AspectRatio(
              aspectRatio: 1.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  track.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.softClay,
                    child: const Icon(
                      Icons.music_note_rounded,
                      size: 64,
                      color: AppColors.cocoaPlum,
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Title & Artist + Heart
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.vanillaCream,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.geist(
                        fontSize: 13,
                        color: AppColors.softClay.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isLiked ? AppColors.dustyRose : AppColors.vanillaCream,
                  size: 22,
                ),
                onPressed: () {
                  final favNotifier = ref.read(favoritesProvider.notifier);
                  if (isLiked) {
                    favNotifier.removeFavorite(track.id);
                  } else {
                    favNotifier.addFavorite(
                      Track(
                        id: track.id,
                        title: track.title,
                        artist: track.artist,
                        imageUrl: track.imageUrl,
                        duration: track.duration,
                        filePath: track.filePath,
                      ),
                    );
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Waveform & Timestamps
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: WaveformWidget(
                  height: 30.0,
                  isPlaying: isPlaying,
                  activeProgress: progress,
                  activeColor: AppColors.dustyRose,
                  inactiveColor: AppColors.white.withOpacity(0.25),
                  onScrub: (val) {
                    final seekPos = Duration(
                      milliseconds:
                          (val * playback.duration.inMilliseconds).toInt(),
                    );
                    ref.read(playerControllerProvider.notifier).seek(seekPos);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(playback.position),
                      style: GoogleFonts.geist(
                        fontSize: 11,
                        color: AppColors.vanillaCream.withOpacity(0.6),
                      ),
                    ),
                    Text(
                      _formatDuration(playback.duration),
                      style: GoogleFonts.geist(
                        fontSize: 11,
                        color: AppColors.vanillaCream.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Controls Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.shuffle_rounded),
                iconSize: 20,
                color: playback.isShuffleEnabled
                    ? AppColors.dustyRose
                    : AppColors.vanillaCream.withOpacity(0.6),
                onPressed: () => ref
                    .read(playerControllerProvider.notifier)
                    .toggleShuffle(),
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded),
                iconSize: 26,
                color: AppColors.vanillaCream,
                onPressed: () =>
                    ref.read(playerControllerProvider.notifier).previous(),
              ),
              Material(
                color: AppColors.dustyRose,
                shape: const CircleBorder(),
                elevation: 3,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    if (isPlaying) {
                      ref.read(playerControllerProvider.notifier).pause();
                    } else {
                      ref.read(playerControllerProvider.notifier).play();
                    }
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    child: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 28,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded),
                iconSize: 26,
                color: AppColors.vanillaCream,
                onPressed: () =>
                    ref.read(playerControllerProvider.notifier).next(),
              ),
              IconButton(
                icon: const Icon(Icons.repeat_rounded),
                iconSize: 20,
                color: playback.repeatMode != pb.RepeatMode.off
                    ? AppColors.dustyRose
                    : AppColors.vanillaCream.withOpacity(0.6),
                onPressed: () => ref
                    .read(playerControllerProvider.notifier)
                    .toggleRepeatMode(),
              ),
            ],
          ),

          const Spacer(),

          // Bottom "Lyrics" Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lyrics_outlined,
                  size: 16,
                  color: AppColors.vanillaCream,
                ),
                const SizedBox(width: 8),
                Text(
                  'Lyrics',
                  style: GoogleFonts.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.vanillaCream,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── MOBILE MINI PLAYER ─────────────────────────────────────────────────────

  Widget _buildMobileMiniPlayer(
      BuildContext context, pb.PlaybackState playback) {
    final track = playback.currentTrack;
    if (track == null) return const SizedBox.shrink();

    return MiniPlayer(
      musicItem: track,
      isPlaying: playback.status == pb.PlaybackStatus.playing,
      progress: playback.duration.inMilliseconds > 0
          ? playback.position.inMilliseconds / playback.duration.inMilliseconds
          : 0.0,
      onTap: () {
        context.push('/player');
      },
    );
  }

  // ── HELPERS ────────────────────────────────────────────────────────────────

  int _getNavIndex(String location) {
    if (location == '/home') return 0;
    if (location == '/search') return 1;
    if (location == '/playlists' || location.startsWith('/playlist/')) return 2;
    if (location == '/settings') return 3;
    return 0;
  }

  void _handleNavigation(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/search');
        break;
      case 2:
        context.go('/playlists');
        break;
      case 3:
        context.go('/settings');
        break;
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${twoDigits(seconds)}';
  }
}
