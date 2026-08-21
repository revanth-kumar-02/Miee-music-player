import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/audio/playback_state.dart' as pb;
import '../../core/audio/providers.dart';
import '../../features/profile/presentation/profile_controller.dart';
import '../../shared/widgets/miee_logo.dart';
import '../../shared/widgets/widgets.dart';

/// The unified Shell Layout wrapper for Miee Web v2.
/// Adapts seamlessly between desktop (sidebar + topbar + floating player)
/// and mobile (full-screen page content + bottom miniplayer + bottom nav).
class MainAppShell extends ConsumerStatefulWidget {
  final Widget child;

  const MainAppShell({super.key, required this.child});

  @override
  ConsumerState<MainAppShell> createState() => _MainAppShellState();
}

class _MainAppShellState extends ConsumerState<MainAppShell> {
  bool _isSidebarCollapsed = false;
  bool _isQueueOpen = false;
  bool _isLyricsOpen = false;
  double _volume = 0.8;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;

    // Full screen routes on mobile that should not show bottom bars
    final isFullScreenMobile = (location == '/player' ||
        location == '/queue' ||
        location == '/' ||
        location.startsWith('/playlist/') ||
        location.startsWith('/album/') ||
        location.startsWith('/artist/') ||
        location.startsWith('/genre/') ||
        location == '/local-songs');

    if (!isDesktop) {
      // ── MOBILE LAYOUT ──
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            Positioned.fill(child: widget.child),
            // Floating MiniPlayer + Bottom Navigation
            if (!isFullScreenMobile) ...[
              Positioned(
                left: AppSpacing.sm,
                right: AppSpacing.sm,
                bottom: 88.0 + MediaQuery.of(context).padding.bottom,
                child: _buildMobileMiniPlayer(context),
              ),
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
          ],
        ),
      );
    }

    // ── DESKTOP LAYOUT ──
    final playback = ref.watch(playerControllerProvider);
    final hasTrack = playback.currentTrack != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7), // Light Gray base theme
      body: Stack(
        children: [
          // Sidebar (Left)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            left: 16.0,
            top: 16.0,
            bottom: hasTrack ? 120.0 : 16.0,
            width: _isSidebarCollapsed ? 80.0 : 240.0,
            child: _buildSidebar(context, location),
          ),

          // Main Content Area (Right)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            left: (_isSidebarCollapsed ? 80.0 : 240.0) + 32.0,
            right: (_isQueueOpen || _isLyricsOpen ? 320.0 : 0.0) + 16.0,
            top: 16.0,
            bottom: hasTrack ? 120.0 : 16.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Bar
                _buildTopBar(context),
                const SizedBox(height: 16.0),
                // Child Page Content
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20.0),
                    child: Container(
                      color: Colors.white,
                      child: widget.child,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Sliding Panels (Queue/Lyrics)
          if (_isQueueOpen || _isLyricsOpen)
            Positioned(
              right: 16.0,
              top: 16.0,
              bottom: hasTrack ? 120.0 : 16.0,
              width: 300.0,
              child: _buildSidePanel(),
            ),

          // Floating Player (Bottom)
          if (hasTrack)
            Positioned(
              left: 16.0,
              right: 16.0,
              bottom: 16.0,
              height: 88.0,
              child: _buildDesktopPlayer(playback),
            ),
        ],
      ),
    );
  }

  // ── NAVIGATION HELPERS ──

  int _getNavIndex(String location) {
    if (location == '/home') return 0;
    if (location == '/search') return 1;
    if (location == '/playlists') return 2;
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

  // ── MOBILE MINI PLAYER ──

  Widget _buildMobileMiniPlayer(BuildContext context) {
    final playback = ref.watch(playerControllerProvider);
    final hasTrack = playback.currentTrack != null;
    if (!hasTrack) return const SizedBox.shrink();

    return MiniPlayer(
      musicItem: playback.currentTrack!,
      isPlaying: playback.status == pb.PlaybackStatus.playing,
      progress: playback.duration.inMilliseconds > 0
          ? playback.position.inMilliseconds / playback.duration.inMilliseconds
          : 0.0,
      onTap: () {
        context.push('/player');
      },
    );
  }

  // ── DESKTOP COMPONENTS ──

  Widget _buildSidebar(BuildContext context, String location) {
    final profile = ref.watch(profileProvider);

    return _GlassContainer(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 12.0),
        child: Column(
          children: [
            // Collapse/Logo row
            Row(
              mainAxisAlignment: _isSidebarCollapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.spaceBetween,
              children: [
                if (_isSidebarCollapsed)
                  // Compact "ee" mark when sidebar is collapsed
                  const MieeCompactIcon(size: 32, color: Colors.white)
                else
                  // Full wordmark when expanded
                  const MieeWordmark(width: 100, color: Colors.white),
                IconButton(
                  icon: Icon(
                    _isSidebarCollapsed ? Icons.menu_open : Icons.menu,
                    color: AppColors.onSurface,
                  ),
                  onPressed: () {
                    setState(() {
                      _isSidebarCollapsed = !_isSidebarCollapsed;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 32.0),

            // Sidebar items
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildSidebarItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home,
                    label: 'Home',
                    isActive: location == '/home',
                    onTap: () => context.go('/home'),
                  ),
                  _buildSidebarItem(
                    icon: Icons.search_outlined,
                    activeIcon: Icons.search,
                    label: 'Search',
                    isActive: location == '/search',
                    onTap: () => context.go('/search'),
                  ),
                  _buildSidebarItem(
                    icon: Icons.queue_music_outlined,
                    activeIcon: Icons.queue_music,
                    label: 'Playlists',
                    isActive: location == '/playlists',
                    onTap: () => context.go('/playlists'),
                  ),
                  _buildSidebarItem(
                    icon: Icons.favorite_outline,
                    activeIcon: Icons.favorite,
                    label: 'Favorites',
                    isActive: location == '/local-songs',
                    onTap: () => context.go('/local-songs'),
                  ),
                  _buildSidebarItem(
                    icon: Icons.download_outlined,
                    activeIcon: Icons.download,
                    label: 'Downloads',
                    isActive: false,
                    onTap: () {},
                  ),
                  _buildSidebarItem(
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings,
                    label: 'Settings',
                    isActive: location == '/settings',
                    onTap: () => context.go('/settings'),
                  ),
                ],
              ),
            ),

            // Profile info at the bottom
            const Divider(color: Colors.white24, height: 24.0),
            GestureDetector(
              onTap: () => context.go('/profile'),
              child: Row(
                mainAxisAlignment: _isSidebarCollapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20.0,
                    backgroundColor: AppColors.surfaceContainerHigh,
                    backgroundImage: profile.profilePicturePath != null
                        ? NetworkImage(profile.profilePicturePath!)
                        : null,
                    child: profile.profilePicturePath == null
                        ? Text(
                            profile.displayName.isNotEmpty
                                ? profile.displayName[0].toUpperCase()
                                : 'M',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface),
                          )
                        : null,
                  ),
                  if (!_isSidebarCollapsed) ...[
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.displayName.isNotEmpty
                                ? profile.displayName
                                : 'Miee User',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelMedium.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Premium Member',
                            style: AppTypography.labelSmall.copyWith(
                              fontSize: 10.0,
                              color: AppColors.accentIndigo,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.0),
        child: Container(
          height: 48.0,
          decoration: BoxDecoration(
            color: isActive ? Colors.white.withOpacity(0.3) : Colors.transparent,
            borderRadius: BorderRadius.circular(12.0),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: _isSidebarCollapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(
                isActive ? activeIcon : icon,
                color: isActive ? AppColors.primary : AppColors.onSurfaceVariant,
              ),
              if (!_isSidebarCollapsed) ...[
                const SizedBox(width: 16.0),
                Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                    color: isActive ? AppColors.onSurface : AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return _GlassContainer(
      child: Container(
        height: 64.0,
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Row(
          children: [
            // New brand wordmark in topbar
            const MieeWordmark(width: 80, color: Colors.white),
            const Spacer(),
            // Search field link
            GestureDetector(
              onTap: () => context.go('/search'),
              child: Container(
                width: 280.0,
                height: 36.0,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(18.0),
                  border: Border.all(color: Colors.white30),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 18.0, color: AppColors.onSurfaceVariant),
                    const SizedBox(width: 8.0),
                    Text(
                      'Search music...',
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16.0),
            IconButton(
              icon: const Icon(Icons.notifications_none),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.account_circle_outlined),
              onPressed: () => context.go('/profile'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidePanel() {
    final playback = ref.watch(playerControllerProvider);

    return _GlassContainer(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isQueueOpen ? 'Up Next' : 'Lyrics',
                  style: AppTypography.headlineMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _isQueueOpen = false;
                      _isLyricsOpen = false;
                    });
                  },
                ),
              ],
            ),
            const Divider(color: Colors.white24),
            Expanded(
              child: _isQueueOpen
                  ? (playback.currentTrack != null
                      ? const Center(child: Text('Active Playback Queue List'))
                      : const Center(child: Text('No active track playing')))
                  : const Center(
                      child: Text(
                        'Lyrics temporarily unavailable',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopPlayer(pb.PlaybackState playback) {
    final track = playback.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final isPlaying = playback.status == pb.PlaybackStatus.playing;
    final progress = playback.duration.inMilliseconds > 0
        ? playback.position.inMilliseconds / playback.duration.inMilliseconds
        : 0.0;

    return _GlassContainer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        child: Row(
          children: [
            // Album Art + Song details
            ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: Image.network(
                track.imageUrl,
                width: 56.0,
                height: 56.0,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 56.0,
                  height: 56.0,
                  color: AppColors.surfaceContainerHigh,
                  child: const Icon(Icons.music_note),
                ),
              ),
            ),
            const SizedBox(width: 16.0),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSmall.copyWith(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),

            // Controls & Waveform
            Expanded(
              flex: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shuffle),
                        color: playback.isShuffleEnabled ? AppColors.accentIndigo : AppColors.onSurfaceVariant,
                        onPressed: () => ref.read(playerControllerProvider.notifier).toggleShuffle(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        onPressed: () => ref.read(playerControllerProvider.notifier).previous(),
                      ),
                      FloatingActionButton.small(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: const CircleBorder(),
                        onPressed: () {
                          if (isPlaying) {
                            ref.read(playerControllerProvider.notifier).pause();
                          } else {
                            ref.read(playerControllerProvider.notifier).play();
                          }
                        },
                        child: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        onPressed: () => ref.read(playerControllerProvider.notifier).next(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.repeat),
                        color: playback.repeatMode != pb.RepeatMode.off ? AppColors.accentIndigo : AppColors.onSurfaceVariant,
                        onPressed: () => ref.read(playerControllerProvider.notifier).toggleRepeatMode(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4.0),
                  // Centered, responsive waveform progress scrub
                  Row(
                    children: [
                      Text(
                        _formatDuration(playback.position),
                        style: const TextStyle(fontSize: 10.0),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: WaveformWidget(
                            isPlaying: isPlaying,
                            activeProgress: progress,
                            onScrub: (frac) {
                              final seekPos = Duration(
                                milliseconds: (frac * playback.duration.inMilliseconds).toInt(),
                              );
                              ref.read(playerControllerProvider.notifier).seek(seekPos);
                            },
                          ),
                        ),
                      ),
                      Text(
                        _formatDuration(playback.duration),
                        style: const TextStyle(fontSize: 10.0),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Volume & Extra drawers
            Expanded(
              flex: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(_isLyricsOpen ? Icons.lyrics : Icons.lyrics_outlined),
                    color: _isLyricsOpen ? AppColors.accentIndigo : AppColors.onSurfaceVariant,
                    onPressed: () {
                      setState(() {
                        _isLyricsOpen = !_isLyricsOpen;
                        _isQueueOpen = false;
                      });
                    },
                  ),
                  IconButton(
                    icon: Icon(_isQueueOpen ? Icons.queue_music : Icons.queue_music_outlined),
                    color: _isQueueOpen ? AppColors.accentIndigo : AppColors.onSurfaceVariant,
                    onPressed: () {
                      setState(() {
                        _isQueueOpen = !_isQueueOpen;
                        _isLyricsOpen = false;
                      });
                    },
                  ),
                  const Icon(Icons.volume_up, size: 20.0),
                  SizedBox(
                    width: 80.0,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.0,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                      ),
                      child: Slider(
                        value: _volume,
                        onChanged: (v) {
                          setState(() {
                            _volume = v;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${twoDigits(seconds)}';
  }
}

/// Helper Glassmorphic Box container wrapping BackdropFilter
class _GlassContainer extends StatelessWidget {
  final Widget child;

  const _GlassContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20.0),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30.0, sigmaY: 30.0),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20.0),
            border: Border.all(
              color: Colors.white.withOpacity(0.25),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 30.0,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
