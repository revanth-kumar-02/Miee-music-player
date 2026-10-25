import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/audio/playback_state.dart' as pb;
import '../../core/audio/providers.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/playlists/presentation/widgets/add_to_playlist_sheet.dart';
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
  final bool initialDrawerOpen;

  const MainAppShell({
    super.key,
    required this.child,
    this.initialDrawerOpen = false,
  });

  static String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${twoDigits(seconds)}';
  }

  @override
  ConsumerState<MainAppShell> createState() => _MainAppShellState();
}

class _MainAppShellState extends ConsumerState<MainAppShell> {
  late bool _isNowPlayingDrawerOpen;
  final TextEditingController _topSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isNowPlayingDrawerOpen = widget.initialDrawerOpen;
  }

  @override
  void dispose() {
    _topSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      playerControllerProvider.select(
          (s) => s.status == pb.PlaybackStatus.error ? s.errorMessage : null),
      (previous, next) {
        if (next != null && next.isNotEmpty) {
          final messenger = ScaffoldMessenger.maybeOf(context);
          if (messenger == null) return;
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(next),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Dismiss',
                textColor: AppColors.dustyRose,
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                },
              ),
            ),
          );
        }
      },
    );

    String location = '/';
    String uriPath = '/';
    try {
      final routerState = GoRouterState.of(context);
      location = routerState.matchedLocation;
      uriPath = routerState.uri.path;
    } catch (_) {
      // Fallback for tests or widget harnesses rendered without GoRouter
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 960;
    final isTablet = screenWidth >= 650 && screenWidth < 960;

    final hasTrack = ref.watch(
      playerControllerProvider.select((s) => s.currentTrack != null),
    );
    final isNowPlayingRoute = location == '/player' || uriPath == '/player';
    final isSettingsRoute = location == '/settings' ||
        uriPath == '/settings' ||
        location.startsWith('/settings/') ||
        uriPath.startsWith('/settings/');

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
            // Floating MiniPlayer (Visible on all screens EXCEPT full Now Playing and Settings)
            if (!isNowPlayingRoute && !isSettingsRoute && hasTrack)
              Positioned(
                left: AppSpacing.sm,
                right: AppSpacing.sm,
                bottom: (hideBottomNav ? 12.0 : 88.0) +
                    MediaQuery.of(context).padding.bottom,
                child: _MobileMiniPlayerHost(shellState: this),
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
                  bottom: (hasTrack && !isNowPlayingRoute) ? (playerHeight + 28) : 16,
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

                // Persistent Bottom Player (hidden on full Now Playing route)
                if (hasTrack && !isNowPlayingRoute)
                  Positioned(
                    left: 20.0,
                    right: showDrawer ? 340.0 : 20.0,
                    bottom: 14.0,
                    height: playerHeight,
                    child: _DesktopPlayerBarHost(shellState: this),
                  ),

                // Cocoa Plum Now Playing Right Drawer
                if (showDrawer)
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: 320.0,
                    child: _DesktopNowPlayingPanelHost(
                      onClose: () => setState(() => _isNowPlayingDrawerOpen = false),
                    ),
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
                    child: MieeBrandMark.emblem(
                      emblemSize: 32,
                      showWordmark: false,
                      emblemColor: AppColors.dustyRose,
                    ),
                  )
                : const MieeBrandMark.soundwaveWordmark(
                    fontSize: 22,
                    emblemColor: AppColors.dustyRose,
                    dotColor: AppColors.dustyRose,
                    textColor: AppColors.vanillaCream,
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
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
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
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.geist(
                        fontSize: 13.5,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? AppColors.white
                            : AppColors.vanillaCream.withOpacity(0.85),
                      ),
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
    final authUser = ref.watch(currentAuthUserProvider);
    final effectiveName = (cloudProfile?.displayName.trim().isNotEmpty == true &&
            cloudProfile?.displayName != 'Miee Listener' &&
            cloudProfile?.displayName != 'Miee User')
        ? cloudProfile!.displayName
        : (authUser?.displayName?.trim().isNotEmpty == true &&
                authUser?.displayName != 'Miee Listener' &&
                authUser?.displayName != 'Miee User')
            ? authUser!.displayName!
            : (localProfile.displayName.isNotEmpty &&
                    localProfile.displayName != 'Miee User' &&
                    localProfile.displayName != 'Miee Listener')
                ? localProfile.displayName
                : (authUser?.email.isNotEmpty == true
                    ? authUser!.email.split('@').first
                    : localProfile.displayName);

    final resolvedAvatarUrl = (localProfile.profilePicturePath != null &&
            localProfile.profilePicturePath!.isNotEmpty)
        ? localProfile.profilePicturePath
        : (cloudProfile?.avatarUrl?.isNotEmpty == true
            ? cloudProfile!.avatarUrl
            : authUser?.photoUrl);

    final globalQuery = ref.watch(searchNotifierProvider.select((s) => s.query));
    if (_topSearchController.text != globalQuery && _topSearchController.selection.baseOffset <= 0) {
      _topSearchController.text = globalQuery;
    }

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
                    onChanged: (query) {
                      setState(() {});
                      ref.read(searchNotifierProvider.notifier).updateQuery(query);
                    },
                    onSubmitted: (query) {
                      final trimmed = query.trim();
                      if (trimmed.isNotEmpty) {
                        ref
                            .read(searchNotifierProvider.notifier)
                            .updateQuery(trimmed);
                        ref
                            .read(searchNotifierProvider.notifier)
                            .searchNow(trimmed);
                        if (GoRouterState.of(context).matchedLocation != '/search') {
                          context.go('/search');
                        }
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
                      suffixIcon: _topSearchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.mutedMauve),
                              splashRadius: 16,
                              onPressed: () {
                                _topSearchController.clear();
                                ref.read(searchNotifierProvider.notifier).updateQuery('');
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 16),

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
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: (resolvedAvatarUrl != null && resolvedAvatarUrl.isNotEmpty)
                  ? ProfileAvatar(
                      imageUrl: resolvedAvatarUrl,
                      size: 38,
                    )
                  : Text(
                      effectiveName.isNotEmpty
                          ? effectiveName[0].toUpperCase()
                          : 'M',
                      style: GoogleFonts.geist(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.cocoaPlum,
                      ),
                    ),
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
    final isLoading = playback.status == pb.PlaybackStatus.loading ||
        playback.status == pb.PlaybackStatus.buffering;
    final progress = playback.duration.inMilliseconds > 0
        ? (playback.position.inMilliseconds /
                playback.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    final isLiked = ref.watch(
      favoritesProvider.select((favs) => favs.any((t) => t.id == track.id)),
    );

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
            onTap: () => context.push('/player'),
            child: Tooltip(
              message: 'Open Now Playing',
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
          const SizedBox(width: 12),

          // ── Center: Playback Controls & Clean Progress Slider ──
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 460,
                height: 84,
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
                        onTap: isLoading
                            ? null
                            : () {
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
                          child: isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.0,
                                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                                  ),
                                )
                              : Icon(
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

                // Seek Progress Slider Row (Clean linear bar)
                Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(
                        _formatDuration(playback.position),
                        textAlign: TextAlign.right,
                        style: GoogleFonts.geist(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.mutedMauve,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3.5,
                          activeTrackColor: AppColors.dustyRose,
                          inactiveTrackColor: AppColors.oatBeige,
                          thumbColor: AppColors.dustyRose,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 4.5,
                            elevation: 1.0,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 10.0,
                          ),
                          overlayColor: AppColors.dustyRose.withOpacity(0.15),
                        ),
                        child: SizedBox(
                          height: 20,
                          child: Slider(
                            value: progress,
                            onChanged: (val) {
                              if (playback.duration.inMilliseconds > 0) {
                                final seekPos = Duration(
                                  milliseconds:
                                      (val * playback.duration.inMilliseconds).toInt(),
                                );
                                ref
                                    .read(playerControllerProvider.notifier)
                                    .seek(seekPos);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 36,
                      child: Text(
                        playback.duration.inMilliseconds > 0
                            ? _formatDuration(playback.duration)
                            : '--:--',
                        textAlign: TextAlign.left,
                        style: GoogleFonts.geist(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.mutedMauve,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),

          const SizedBox(width: 12),

          // ── Right: Queue / Volume / Fullscreen Expand ──
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.queue_music_rounded),
                iconSize: 20,
                color: AppColors.cocoaPlum,
                tooltip: 'Queue',
                splashRadius: 18,
                onPressed: () => context.push('/queue'),
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
                icon: const Icon(Icons.open_in_full_rounded),
                iconSize: 17,
                color: AppColors.mutedMauve,
                tooltip: 'Expand Now Playing',
                splashRadius: 18,
                onPressed: () => context.push('/player'),
              ),
            ],
          ),
        ],
      ),
    );
  }



  // ── MOBILE MINI PLAYER ─────────────────────────────────────────────────────

  Widget _buildMobileMiniPlayer(
      BuildContext context, pb.PlaybackState playback) {
    final track = playback.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final isPlaying = playback.status == pb.PlaybackStatus.playing;
    final isLoading = playback.status == pb.PlaybackStatus.loading ||
        playback.status == pb.PlaybackStatus.buffering;
    final isLiked = ref.watch(
      favoritesProvider.select((favs) => favs.any((t) => t.id == track.id)),
    );

    return MiniPlayer(
      musicItem: track,
      isPlaying: isPlaying,
      isLoading: isLoading,
      isFavorited: isLiked,
      progress: playback.duration.inMilliseconds > 0
          ? playback.position.inMilliseconds / playback.duration.inMilliseconds
          : 0.0,
      onTap: () {
        context.push('/player');
      },
      onPlayPauseTap: () {
        if (isPlaying) {
          ref.read(playerControllerProvider.notifier).pause();
        } else {
          ref.read(playerControllerProvider.notifier).play();
        }
      },
      onFavoriteTap: () {
        final favNotifier = ref.read(favoritesProvider.notifier);
        if (isLiked) {
          favNotifier.removeFavorite(track.id);
        } else {
          favNotifier.addFavorite(
            track is Track
                ? track
                : Track(
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

class _MobileMiniPlayerHost extends ConsumerWidget {
  final _MainAppShellState shellState;
  const _MobileMiniPlayerHost({required this.shellState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playerControllerProvider);
    return shellState._buildMobileMiniPlayer(context, playback);
  }
}

class _DesktopPlayerBarHost extends ConsumerWidget {
  final _MainAppShellState shellState;
  const _DesktopPlayerBarHost({required this.shellState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playerControllerProvider);
    return shellState._buildDesktopPlayerBar(playback);
  }
}

class _DesktopNowPlayingPanelHost extends ConsumerWidget {
  final VoidCallback? onClose;
  const _DesktopNowPlayingPanelHost({this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playerControllerProvider);
    return DesktopNowPlayingPanel(playback: playback, onClose: onClose);
  }
}

/// The desktop right-hand Now Playing drawer panel.
class DesktopNowPlayingPanel extends ConsumerWidget {
  final pb.PlaybackState playback;
  final VoidCallback? onClose;

  const DesktopNowPlayingPanel({
    super.key,
    required this.playback,
    this.onClose,
  });

  Widget _buildArtworkPlaceholder() {
    return Container(
      color: AppColors.softClay,
      child: const Icon(
        Icons.music_note_rounded,
        size: 64,
        color: AppColors.vanillaCream,
      ),
    );
  }

  Widget _buildArtwork(String rawUrl) {
    if (rawUrl.isEmpty) {
      return _buildArtworkPlaceholder();
    }
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      return Image.network(
        rawUrl,
        fit: BoxFit.cover,
        cacheWidth: 400,
        cacheHeight: 400,
        errorBuilder: (_, __, ___) => _buildArtworkPlaceholder(),
      );
    }
    if (kIsWeb) {
      return _buildArtworkPlaceholder();
    }
    try {
      final normalizedPath = rawUrl.startsWith('file://')
          ? Uri.parse(rawUrl).toFilePath()
          : rawUrl;
      return Image.file(
        File(normalizedPath),
        fit: BoxFit.cover,
        cacheWidth: 400,
        cacheHeight: 400,
        errorBuilder: (_, __, ___) => _buildArtworkPlaceholder(),
      );
    } catch (_) {
      return _buildArtworkPlaceholder();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = playback.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final isPlaying = playback.status == pb.PlaybackStatus.playing;
    final isLoading = playback.status == pb.PlaybackStatus.loading ||
        playback.status == pb.PlaybackStatus.buffering;
    final progress = playback.duration.inMilliseconds > 0
        ? (playback.position.inMilliseconds /
                playback.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    final isLiked = ref.watch(
      favoritesProvider.select((favs) => favs.any((t) => t.id == track.id)),
    );

    return Container(
      width: 320,
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
                tooltip: 'Close panel',
                onPressed: onClose,
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
                tooltip: 'More options',
                onPressed: () => showAddToPlaylistSheet(context, track),
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
                child: _buildArtwork(track.imageUrl),
              ),
            ),
          ),

          const Spacer(),

          // Track Title & Artist + Favorite Heart
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
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

          // Linear Progress Slider & Timestamps
          Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3.5,
                  activeTrackColor: AppColors.dustyRose,
                  inactiveTrackColor: AppColors.white.withOpacity(0.2),
                  thumbColor: AppColors.dustyRose,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10.0),
                  overlayColor: AppColors.dustyRose.withOpacity(0.15),
                ),
                child: Slider(
                  value: progress,
                  onChanged: (val) {
                    if (playback.duration.inMilliseconds > 0) {
                      final seekPos = Duration(
                        milliseconds:
                            (val * playback.duration.inMilliseconds).toInt(),
                      );
                      ref.read(playerControllerProvider.notifier).seek(seekPos);
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      MainAppShell.formatDuration(playback.position),
                      style: GoogleFonts.geist(
                        fontSize: 11,
                        color: AppColors.vanillaCream.withOpacity(0.6),
                      ),
                    ),
                    Text(
                      playback.duration.inMilliseconds > 0
                          ? MainAppShell.formatDuration(playback.duration)
                          : '--:--',
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
                  onTap: isLoading
                      ? null
                      : () {
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
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                            ),
                          )
                        : Icon(
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
}

