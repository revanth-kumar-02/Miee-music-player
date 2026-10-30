import '../../features/music_drop/presentation/widgets/incoming_drop_banner.dart';
import '../../features/player/presentation/widgets/miee_dynamic_island.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/web_colors.dart';
import 'desktop_waveform_scrubber.dart';
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
import '../providers/web_navigation_provider.dart';

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

  /// Visibility flag for Web header notification controls.
  /// Set to false per Web UI requirements to hide the notification bell
  /// and badge while preserving the complete UI implementation for future re-enablement.
  static const bool showWebNotifications = false;

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

    // Synchronize desktop web navigation history
    final currentRoute = location;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(webNavigationProvider.notifier).recordRoute(currentRoute);
      }
    });

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
    final isRoomRoute = location == '/rooms' ||
        uriPath == '/rooms' ||
        location.startsWith('/rooms/') ||
        uriPath.startsWith('/rooms/');
    final isQueueRoute = location == '/queue' ||
        uriPath == '/queue' ||
        location.startsWith('/queue/') ||
        uriPath.startsWith('/queue/');

    // Detail screens where mobile bottom nav is hidden
    final hideBottomNav = (isNowPlayingRoute ||
        isQueueRoute ||
        location == '/' ||
        location.startsWith('/playlist/') ||
        location.startsWith('/album/') ||
        location.startsWith('/artist/') ||
        location.startsWith('/genre/') ||
        location == '/local-songs' ||
        location == '/liked-songs' ||
        isRoomRoute);

    // ── MOBILE & COMPACT TABLET LAYOUT ──
    if (!isDesktop) {
      final hideMiniPlayer = isNowPlayingRoute ||
          isSettingsRoute ||
          isRoomRoute ||
          isQueueRoute ||
          !hasTrack;

      return Scaffold(
        backgroundColor: AppColors.vanillaCream,
        body: Stack(
          children: [
            Positioned.fill(child: widget.child),
            // Top Miee Dynamic Island (Visible when a song is loaded, outside of full Now Playing and Room screens)
            if (hasTrack && !isNowPlayingRoute && !isRoomRoute)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: MieeDynamicIsland(),
              ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 4,
              left: 0,
              right: 0,
              child: const IncomingDropBanner(),
            ),
            // Floating MiniPlayer (Hidden on full Now Playing, Settings, all Room screens, and Queue)
            if (!hideMiniPlayer)
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
    const double sidebarWidth = 240.0;
    const double playerHeight = 88.0;
    const double topBarHeight = 64.0;

    final showDrawer = _isNowPlayingDrawerOpen && hasTrack;
    final effectiveSidebarWidth = isTablet ? 76.0 : sidebarWidth;

    return Scaffold(
      backgroundColor: MieeWebColors.surface,
      body: Stack(
        children: [
          // ── 1. Light Linen Left Sidebar (full height above player) ──
          Positioned(
            left: 0,
            top: 0,
            bottom: (hasTrack && !isNowPlayingRoute) ? playerHeight : 0,
            width: effectiveSidebarWidth,
            child: _buildDesktopSidebar(context, location, isTablet),
          ),

          // ── 2. Top Header Bar (from sidebar to drawer/edge) ──
          Positioned(
            left: effectiveSidebarWidth,
            top: 0,
            right: showDrawer ? 360.0 : 0,
            height: topBarHeight,
            child: _buildTopHeaderBar(context),
          ),

          // ── 3. Main Content Canvas ──
          Positioned(
            left: effectiveSidebarWidth,
            top: topBarHeight,
            right: showDrawer ? 360.0 : 0,
            bottom: (hasTrack && !isNowPlayingRoute) ? playerHeight : 0,
            child: widget.child,
          ),

          // ── 4. Now Playing Right Drawer ──
          if (showDrawer)
            Positioned(
              top: 0,
              right: 0,
              bottom: (hasTrack && !isNowPlayingRoute) ? playerHeight : 0,
              width: 360.0,
              child: _DesktopNowPlayingPanelHost(
                onClose: () => setState(() => _isNowPlayingDrawerOpen = false),
              ),
            ),

          // ── 5. Full-Width Docked Bottom Player Bar ──
          if (hasTrack && !isNowPlayingRoute)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: playerHeight,
              child: _DesktopPlayerBarHost(shellState: this),
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
    final favorites = ref.watch(favoritesProvider);

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
                    : 'Listener');

    final resolvedAvatarUrl = (localProfile.profilePicturePath != null &&
            localProfile.profilePicturePath!.isNotEmpty)
        ? localProfile.profilePicturePath
        : (cloudProfile?.avatarUrl?.isNotEmpty == true
            ? cloudProfile!.avatarUrl
            : authUser?.photoUrl);

    return Container(
      decoration: const BoxDecoration(
        color: MieeWebColors.surfaceLow,
        border: Border(
          right: BorderSide(color: MieeWebColors.subtleBorder, width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo & Branding
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.centerLeft,
            child: isCollapsed
                ? Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: MieeWebColors.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          'm',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  )
                : const MieeWordmarkDot(
                    fontSize: 24,
                    textColor: MieeWebColors.textDark,
                    dotColor: MieeWebColors.primaryContainer,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
          ),

          // Sidebar Navigation Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                // ── SECTION 1: MENU ──
                if (!isCollapsed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                    child: Text(
                      'MENU',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: MieeWebColors.outline,
                      ),
                    ),
                  ),

                _buildSidebarNavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Home',
                  isSelected: location == '/home',
                  isCollapsed: isCollapsed,
                  onTap: () => context.go('/home'),
                ),
                _buildSidebarNavItem(
                  icon: Icons.search_rounded,
                  activeIcon: Icons.search_rounded,
                  label: 'Search',
                  isSelected: location == '/search',
                  isCollapsed: isCollapsed,
                  onTap: () => context.go('/search'),
                ),
                _buildSidebarNavItem(
                  icon: Icons.local_library_outlined,
                  activeIcon: Icons.local_library_rounded,
                  label: 'Your Library',
                  isSelected: location == '/playlists' && !location.startsWith('/playlist/'),
                  isCollapsed: isCollapsed,
                  onTap: () => context.go('/playlists'),
                ),

                const SizedBox(height: 18),

                // ── SECTION 2: LIBRARY ──
                if (!isCollapsed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                    child: Text(
                      'LIBRARY',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: MieeWebColors.outline,
                      ),
                    ),
                  ),

                _buildSidebarNavItem(
                  icon: Icons.favorite_rounded,
                  activeIcon: Icons.favorite_rounded,
                  iconColor: MieeWebColors.secondary,
                  label: 'Liked Songs',
                  badgeText: favorites.isNotEmpty ? '${favorites.length}' : null,
                  isSelected: location == '/liked-songs',
                  isCollapsed: isCollapsed,
                  onTap: () => context.go('/liked-songs'),
                ),
                _buildSidebarNavItem(
                  icon: Icons.schedule_rounded,
                  activeIcon: Icons.schedule_rounded,
                  label: 'Recently Played',
                  isSelected: location == '/history',
                  isCollapsed: isCollapsed,
                  onTap: () => context.go('/playlists'),
                ),
                _buildSidebarNavItem(
                  icon: Icons.album_outlined,
                  activeIcon: Icons.album_rounded,
                  label: 'Albums',
                  isSelected: location == '/albums',
                  isCollapsed: isCollapsed,
                  onTap: () => context.go('/albums'),
                ),
                _buildSidebarNavItem(
                  icon: Icons.mic_none_outlined,
                  activeIcon: Icons.mic_rounded,
                  label: 'Artists',
                  isSelected: location == '/artists',
                  isCollapsed: isCollapsed,
                  onTap: () => context.go('/artists'),
                ),
                _buildSidebarNavItem(
                  icon: Icons.groups_outlined,
                  activeIcon: Icons.groups_rounded,
                  label: 'Rooms',
                  isSelected: location.startsWith('/rooms'),
                  isCollapsed: isCollapsed,
                  onTap: () => context.go('/rooms'),
                ),

                const SizedBox(height: 18),

                // ── SECTION 3: PLAYLISTS ──
                if (!isCollapsed) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 0, 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'PLAYLISTS',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: MieeWebColors.outline,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          color: MieeWebColors.onSurfaceVariant,
                          hoverColor: MieeWebColors.surfaceContainerHigh,
                          splashRadius: 16,
                          tooltip: 'New Playlist',
                          onPressed: () => showCreatePlaylistDialog(context),
                        ),
                      ],
                    ),
                  ),
                  if (userPlaylists.isNotEmpty)
                    ...userPlaylists.map(
                      (p) => _buildSidebarPlaylistItem(
                        title: p.name,
                        isSelected: location == '/playlist/${p.id}',
                        onTap: () => context.go('/playlist/${p.id}'),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Text(
                        'No playlists yet',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: MieeWebColors.outline,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),

          // ── USER PROFILE FOOTER ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: MieeWebColors.subtleBorder, width: 1.0),
              ),
            ),
            child: isCollapsed
                ? Center(
                    child: InkWell(
                      onTap: () => context.go('/profile'),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: MieeWebColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            effectiveName.isNotEmpty ? effectiveName[0].toUpperCase() : 'M',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  )
                : InkWell(
                    onTap: () => context.go('/profile'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: MieeWebColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: MieeWebColors.subtleBorder.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(
                              color: MieeWebColors.primary,
                              shape: BoxShape.circle,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: (resolvedAvatarUrl != null && resolvedAvatarUrl.isNotEmpty)
                                ? Image.network(
                                    resolvedAvatarUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Center(
                                      child: Text(
                                        effectiveName.isNotEmpty ? effectiveName[0].toUpperCase() : 'M',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: Text(
                                      effectiveName.isNotEmpty ? effectiveName[0].toUpperCase() : 'M',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              effectiveName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: MieeWebColors.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.settings_outlined, size: 18),
                            color: MieeWebColors.onSurfaceVariant,
                            splashRadius: 16,
                            tooltip: 'Settings',
                            onPressed: () => context.go('/settings'),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    Color? iconColor,
    String? badgeText,
    required bool isSelected,
    required bool isCollapsed,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: isSelected ? MieeWebColors.primaryContainer : MieeWebColors.surfaceContainerHigh,
          child: Container(
            height: 38,
            padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 0 : 12),
            decoration: BoxDecoration(
              color: isSelected ? MieeWebColors.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  size: 20,
                  color: isSelected
                      ? Colors.white
                      : (iconColor ?? MieeWebColors.onSurfaceVariant),
                ),
                if (!isCollapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected ? Colors.white : MieeWebColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (badgeText != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white.withValues(alpha: 0.2) : MieeWebColors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badgeText,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : MieeWebColors.onSurface,
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

  Widget _buildSidebarPlaylistItem({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: MieeWebColors.surfaceContainerHigh,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected ? MieeWebColors.surfaceContainerHigh : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? MieeWebColors.primaryContainer : MieeWebColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── TOPBAR (Header on Canvas) ─────────────────────────────────────────────

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
                    : 'Listener');

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

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: MieeWebColors.surface.withValues(alpha: 0.92),
        border: const Border(
          bottom: BorderSide(color: MieeWebColors.subtleBorder, width: 1.0),
        ),
      ),
      child: Row(
        children: [
          // Navigation Back & Forward buttons
          Consumer(
            builder: (context, ref, _) {
              final webNav = ref.watch(webNavigationProvider);
              final canGoBack = webNav.canGoBack;
              final canGoForward = webNav.canGoForward;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: canGoBack ? 'Go back' : '',
                    waitDuration: const Duration(milliseconds: 500),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: canGoBack
                            ? MieeWebColors.surfaceLowest
                            : MieeWebColors.surfaceLowest.withValues(alpha: 0.45),
                        border: Border.all(
                          color: canGoBack
                              ? MieeWebColors.subtleBorder
                              : MieeWebColors.subtleBorder.withValues(alpha: 0.3),
                        ),
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.chevron_left_rounded, size: 20),
                        color: canGoBack
                            ? MieeWebColors.onSurfaceVariant
                            : MieeWebColors.outline.withValues(alpha: 0.35),
                        hoverColor: canGoBack
                            ? MieeWebColors.surfaceContainerHigh
                            : Colors.transparent,
                        onPressed: canGoBack
                            ? () => ref.read(webNavigationProvider.notifier).goBack(context)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: canGoForward ? 'Go forward' : '',
                    waitDuration: const Duration(milliseconds: 500),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: canGoForward
                            ? MieeWebColors.surfaceLowest
                            : MieeWebColors.surfaceLowest.withValues(alpha: 0.45),
                        border: Border.all(
                          color: canGoForward
                              ? MieeWebColors.subtleBorder
                              : MieeWebColors.subtleBorder.withValues(alpha: 0.3),
                        ),
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.chevron_right_rounded, size: 20),
                        color: canGoForward
                            ? MieeWebColors.onSurfaceVariant
                            : MieeWebColors.outline.withValues(alpha: 0.35),
                        hoverColor: canGoForward
                            ? MieeWebColors.surfaceContainerHigh
                            : Colors.transparent,
                        onPressed: canGoForward
                            ? () => ref.read(webNavigationProvider.notifier).goForward(context)
                            : null,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(width: 16),

          // Search Field
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: MieeWebColors.surfaceLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: MieeWebColors.subtleBorder, width: 1.0),
                  ),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 10, right: 8),
                        child: Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: MieeWebColors.outline,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _topSearchController,
                          onChanged: (query) {
                            setState(() {});
                            ref.read(searchNotifierProvider.notifier).updateQuery(query);
                          },
                          onSubmitted: (query) {
                            final trimmed = query.trim();
                            if (trimmed.isNotEmpty) {
                              ref.read(searchNotifierProvider.notifier).updateQuery(trimmed);
                              ref.read(searchNotifierProvider.notifier).searchNow(trimmed);
                              if (GoRouterState.of(context).matchedLocation != '/search') {
                                context.go('/search');
                              }
                            }
                          },
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: MieeWebColors.onSurface,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            border: InputBorder.none,
                            hintText: 'Search artists, tracks, or soundscapes...',
                            hintStyle: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              color: MieeWebColors.outline,
                            ),
                          ),
                        ),
                      ),
                      if (_topSearchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16, color: MieeWebColors.outline),
                          splashRadius: 14,
                          onPressed: () {
                            _topSearchController.clear();
                            ref.read(searchNotifierProvider.notifier).updateQuery('');
                            setState(() {});
                          },
                        )
                      else
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: MieeWebColors.surfaceContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '⌘K',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: MieeWebColors.outline,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Notification Bell (conditionally excluded on Web, preserved for future re-enablement)
          if (MainAppShell.showWebNotifications) ...[
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined, size: 20),
                  color: MieeWebColors.onSurfaceVariant,
                  hoverColor: MieeWebColors.surfaceContainerHigh,
                  splashRadius: 18,
                  onPressed: () {},
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: MieeWebColors.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],

          // Profile Avatar
          InkWell(
            onTap: () => context.go('/profile'),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: MieeWebColors.primary,
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              child: (resolvedAvatarUrl != null && resolvedAvatarUrl.isNotEmpty)
                  ? Image.network(
                      resolvedAvatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(
                          effectiveName.isNotEmpty ? effectiveName[0].toUpperCase() : 'M',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        effectiveName.isNotEmpty ? effectiveName[0].toUpperCase() : 'M',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
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
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: MieeWebColors.surfaceLowest,
        border: Border(
          top: BorderSide(color: MieeWebColors.subtleBorder, width: 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A1A0F12),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Left: Artwork + Title + Artist + Like Action (width ~260) ──
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.push('/player'),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: MieeWebColors.surfaceContainerHigh,
                        border: Border.all(color: MieeWebColors.subtleBorder),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _buildPlayerBarArtwork(track.imageUrl),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => context.push('/player'),
                        child: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: MieeWebColors.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          color: MieeWebColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: isLiked ? MieeWebColors.secondary : MieeWebColors.outline,
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
                IconButton(
                  icon: const Icon(
                    Icons.playlist_add,
                    color: MieeWebColors.onSurfaceVariant,
                    size: 20,
                  ),
                  splashRadius: 18,
                  onPressed: () => showAddToPlaylistSheet(context, track),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // ── Center: Transport Controls & Discrete Waveform Scrubber (max 640) ──
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Transport row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.shuffle_rounded),
                          iconSize: 18,
                          color: playback.isShuffleEnabled
                              ? MieeWebColors.primaryContainer
                              : MieeWebColors.outline,
                          splashRadius: 16,
                          onPressed: () => ref
                              .read(playerControllerProvider.notifier)
                              .toggleShuffle(),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.skip_previous_rounded),
                          iconSize: 22,
                          color: MieeWebColors.onSurface,
                          splashRadius: 16,
                          onPressed: () => ref
                              .read(playerControllerProvider.notifier)
                              .previous(),
                        ),
                        const SizedBox(width: 10),
                        // Bordeaux Circular Play/Pause Button (#6E0D25)
                        Material(
                          color: MieeWebColors.primaryContainer,
                          shape: const CircleBorder(),
                          elevation: 2,
                          shadowColor: MieeWebColors.primaryContainer.withValues(alpha: 0.3),
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
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              child: isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.0,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : Icon(
                                      isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      size: 22,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded),
                          iconSize: 22,
                          color: MieeWebColors.onSurface,
                          splashRadius: 16,
                          onPressed: () =>
                              ref.read(playerControllerProvider.notifier).next(),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.repeat_rounded),
                          iconSize: 18,
                          color: playback.repeatMode != pb.RepeatMode.off
                              ? MieeWebColors.primaryContainer
                              : MieeWebColors.outline,
                          splashRadius: 16,
                          onPressed: () => ref
                              .read(playerControllerProvider.notifier)
                              .toggleRepeatMode(),
                        ),
                      ],
                    ),

                    const SizedBox(height: 2),

                    // Waveform Timeline Scrubber Row
                    Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(
                            _formatDuration(playback.position),
                            textAlign: TextAlign.right,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: MieeWebColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DiscreteWaveformScrubber(
                            progress: progress,
                            isPlaying: isPlaying,
                            height: 20,
                            barWidth: 2.8,
                            playedColor: MieeWebColors.waveformPlayed,
                            unplayedColor: MieeWebColors.waveformNeutral,
                            onSeek: (val) {
                              if (playback.duration.inMilliseconds > 0) {
                                final seekPos = Duration(
                                  milliseconds: (val * playback.duration.inMilliseconds).toInt(),
                                );
                                ref.read(playerControllerProvider.notifier).seek(seekPos);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 36,
                          child: Text(
                            playback.duration.inMilliseconds > 0
                                ? _formatDuration(playback.duration)
                                : '--:--',
                            textAlign: TextAlign.left,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: MieeWebColors.onSurfaceVariant,
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

          const SizedBox(width: 16),

          // ── Right: Queue / Volume / Fullscreen Expand (width ~240) ──
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 240),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.queue_music_rounded),
                  iconSize: 19,
                  color: _isNowPlayingDrawerOpen
                      ? MieeWebColors.primaryContainer
                      : MieeWebColors.onSurfaceVariant,
                  tooltip: 'Queue / Now Playing',
                  splashRadius: 18,
                  onPressed: () => setState(() => _isNowPlayingDrawerOpen = !_isNowPlayingDrawerOpen),
                ),
                IconButton(
                  icon: Icon(
                    playback.volume == 0
                        ? Icons.volume_off_rounded
                        : (playback.volume < 0.5
                            ? Icons.volume_down_rounded
                            : Icons.volume_up_rounded),
                  ),
                  iconSize: 19,
                  color: MieeWebColors.onSurfaceVariant,
                  splashRadius: 18,
                  onPressed: () {
                    final newVol = playback.volume > 0 ? 0.0 : 1.0;
                    ref.read(playerControllerProvider.notifier).setVolume(newVol);
                  },
                ),
                SizedBox(
                  width: 80,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3.0,
                      activeTrackColor: MieeWebColors.primaryContainer,
                      inactiveTrackColor: MieeWebColors.surfaceContainerHighest,
                      thumbColor: MieeWebColors.primaryContainer,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
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
                  iconSize: 16,
                  color: MieeWebColors.onSurfaceVariant,
                  tooltip: 'Expand Now Playing',
                  splashRadius: 18,
                  onPressed: () => context.push('/player'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerBarArtwork(String rawUrl) {
    if (rawUrl.isEmpty) {
      return const Icon(Icons.music_note_rounded, size: 24, color: MieeWebColors.outline);
    }
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      return Image.network(
        rawUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.music_note_rounded, size: 24, color: MieeWebColors.outline),
      );
    }
    return const Icon(Icons.music_note_rounded, size: 24, color: MieeWebColors.outline);
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

/// The desktop right-hand Now Playing drawer panel matching the editorial tactile design.
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
      color: MieeWebColors.surfaceContainerHigh,
      child: const Icon(
        Icons.music_note_rounded,
        size: 56,
        color: MieeWebColors.outline,
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
    final queue = ref.watch(queueManagerProvider).queue;

    return Container(
      width: 360,
      decoration: const BoxDecoration(
        color: MieeWebColors.surface,
        border: Border(
          left: BorderSide(color: MieeWebColors.subtleBorder, width: 1.0),
        ),
      ),
      child: Column(
        children: [
          // ── Header: Close button + Status + Badges ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.keyboard_arrow_right_rounded,
                    color: MieeWebColors.onSurface,
                    size: 24,
                  ),
                  tooltip: 'Close panel',
                  onPressed: onClose,
                ),
                Text(
                  'NOW PLAYING',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: MieeWebColors.outline,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: MieeWebColors.onSurfaceVariant,
                    size: 20,
                  ),
                  tooltip: 'More options',
                  onPressed: () => showAddToPlaylistSheet(context, track),
                ),
              ],
            ),
          ),

          const Divider(color: MieeWebColors.subtleBorder, height: 1),

          // ── Scrollable Body: Artwork, Waveform, Controls, Queue Preview ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // Square Artwork with "DIRECT MASTER" tag
                Center(
                  child: Stack(
                    children: [
                      Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1A1A0F12),
                              blurRadius: 24,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: _buildArtwork(track.imageUrl),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: MieeWebColors.tertiary.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.graphic_eq_rounded,
                                size: 13,
                                color: MieeWebColors.primaryFixed,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'DIRECT MASTER',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Track Title + Artist + Favorite
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
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: MieeWebColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: MieeWebColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: isLiked ? MieeWebColors.secondary : MieeWebColors.outline,
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

                const SizedBox(height: 16),

                // Clean Waveform Scrubber with timestamps below
                Column(
                  children: [
                    DiscreteWaveformScrubber(
                      progress: progress,
                      isPlaying: isPlaying,
                      height: 32,
                      barWidth: 3.0,
                      playedColor: MieeWebColors.waveformPlayed,
                      unplayedColor: MieeWebColors.waveformNeutral,
                      onSeek: (val) {
                        if (playback.duration.inMilliseconds > 0) {
                          final seekPos = Duration(
                            milliseconds: (val * playback.duration.inMilliseconds).toInt(),
                          );
                          ref.read(playerControllerProvider.notifier).seek(seekPos);
                        }
                      },
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          MainAppShell.formatDuration(playback.position),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: MieeWebColors.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          playback.duration.inMilliseconds > 0
                              ? MainAppShell.formatDuration(playback.duration)
                              : '--:--',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: MieeWebColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Controls Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.shuffle_rounded),
                      iconSize: 20,
                      color: playback.isShuffleEnabled
                          ? MieeWebColors.primaryContainer
                          : MieeWebColors.outline,
                      onPressed: () => ref
                          .read(playerControllerProvider.notifier)
                          .toggleShuffle(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded),
                      iconSize: 26,
                      color: MieeWebColors.onSurface,
                      onPressed: () =>
                          ref.read(playerControllerProvider.notifier).previous(),
                    ),
                    Material(
                      color: MieeWebColors.primaryContainer,
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
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.0,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Icon(
                                  isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 26,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded),
                      iconSize: 26,
                      color: MieeWebColors.onSurface,
                      onPressed: () =>
                          ref.read(playerControllerProvider.notifier).next(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.repeat_rounded),
                      iconSize: 20,
                      color: playback.repeatMode != pb.RepeatMode.off
                          ? MieeWebColors.primaryContainer
                          : MieeWebColors.outline,
                      onPressed: () => ref
                          .read(playerControllerProvider.notifier)
                          .toggleRepeatMode(),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Up Next Section
                if (queue.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.queue_music_rounded, size: 18, color: MieeWebColors.primaryContainer),
                          const SizedBox(width: 6),
                          Text(
                            'Up Next',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: MieeWebColors.textDark,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: MieeWebColors.surfaceContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${queue.length}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: MieeWebColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: () => context.push('/queue'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'View All',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: MieeWebColors.primaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...queue.take(4).map((qItem) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              width: 36,
                              height: 36,
                              color: MieeWebColors.surfaceContainerHigh,
                              child: _buildArtwork(qItem.imageUrl),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  qItem.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: MieeWebColors.onSurface,
                                  ),
                                ),
                                Text(
                                  qItem.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10.5,
                                    color: MieeWebColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

