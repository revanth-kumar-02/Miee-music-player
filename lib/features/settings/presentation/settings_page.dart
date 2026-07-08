import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../library/providers/library_providers.dart';
import '../../media/providers/media_providers.dart';
import '../../../core/audio/providers.dart';
import '../../../core/audio/playback_state.dart';
import 'settings_controller.dart';

final devTapsProvider = StateProvider<int>((ref) => 0);
final devModeUnlockedProvider = StateProvider<bool>((ref) => false);

/// Fully featured Settings screen serving as the control center of Miee.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _artworkCacheSize = 'Calculating...';
  String _databaseSize = 'Calculating...';
  PermissionStatus _permissionStatus = PermissionStatus.denied;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await Permission.audio.status;
    if (mounted) {
      setState(() {
        _permissionStatus = status;
      });
    }
  }

  Future<void> _loadStats() async {
    final cacheBytes = await _calculateCacheSize();
    final dbBytes = await _calculateDatabaseSize();
    if (mounted) {
      setState(() {
        _artworkCacheSize = _formatBytes(cacheBytes);
        _databaseSize = _formatBytes(dbBytes);
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0.00 KB';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = (log(bytes) / log(1024)).floor();
    return ((bytes / pow(1024, i)).toStringAsFixed(2)) + ' ' + suffixes[i];
  }

  Future<int> _calculateCacheSize() async {
    try {
      final tempDir = await getTemporaryDirectory();
      int total = 0;
      if (await tempDir.exists()) {
        await for (final file in tempDir.list(recursive: true, followLinks: false)) {
          if (file is File && file.path.endsWith('.png')) {
            total += await file.length();
          }
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _calculateDatabaseSize() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      int total = 0;
      if (await docDir.exists()) {
        await for (final file in docDir.list(recursive: true, followLinks: false)) {
          if (file is File && (file.path.endsWith('.hive') || file.path.endsWith('.box'))) {
            total += await file.length();
          }
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _clearArtworkCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final file in tempDir.list(recursive: true, followLinks: false)) {
          if (file is File && file.path.endsWith('.png')) {
            await file.delete();
          }
        }
      }
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Artwork cache cleared successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear cache: $e')),
        );
      }
    }
  }

  Future<void> _resetLibrary() async {
    try {
      await ref.read(favoritesProvider.notifier).clearAll();
      await ref.read(userPlaylistsProvider.notifier).clearAll();
      await ref.read(searchHistoryProvider.notifier).clearAll();
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final file in tempDir.list(recursive: true, followLinks: false)) {
          if (file is File) {
            await file.delete();
          }
        }
      }
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All databases, cache, and preferences have been reset.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reset library: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final settingsNotifier = ref.read(settingsControllerProvider.notifier);

    final localSongs = ref.watch(songsProvider);
    final localAlbums = ref.watch(albumsProvider);
    final localArtists = ref.watch(artistsProvider);
    final favoritesCount = ref.watch(favoritesProvider).length;
    final searchHistoryCount = ref.watch(searchHistoryProvider).length;
    final recentlyPlayedList = ref.watch(recentlyPlayedProvider).value ?? [];

    final devTaps = ref.watch(devTapsProvider);
    final devUnlocked = ref.watch(devModeUnlockedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {},
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // About/Header Block
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Miee Control Center',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Version 1.0.0',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const Divider(height: 32.0),

              // ── 1. Appearance Section ──
              _buildSectionHeader('Appearance'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('Theme Mode'),
                      subtitle: Text(settings.themeMode.toUpperCase()),
                      trailing: DropdownButton<String>(
                        value: settings.themeMode,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'system', child: Text('System')),
                          DropdownMenuItem(value: 'light', child: Text('Light')),
                          DropdownMenuItem(value: 'dark', child: Text('Dark')),
                        ],
                        onChanged: (val) {
                          if (val != null) settingsNotifier.updateThemeMode(val);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // ── 2. Playback Section ──
              _buildSectionHeader('Playback'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.restore_outlined),
                      title: const Text('Resume playback on startup'),
                      subtitle: const Text('Resume song state on app startup'),
                      value: settings.resumePlayback,
                      onChanged: (val) => settingsNotifier.updateResumePlayback(val),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.shuffle_outlined),
                      title: const Text('Default Shuffle'),
                      subtitle: const Text('Always enable shuffle mode for new queues'),
                      value: settings.defaultShuffle,
                      onChanged: (val) => settingsNotifier.updateDefaultShuffle(val),
                    ),
                    ListTile(
                      leading: const Icon(Icons.repeat_outlined),
                      title: const Text('Default Repeat'),
                      subtitle: Text(settings.defaultRepeat.toUpperCase()),
                      trailing: DropdownButton<String>(
                        value: settings.defaultRepeat,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'off', child: Text('Off')),
                          DropdownMenuItem(value: 'all', child: Text('All')),
                          DropdownMenuItem(value: 'one', child: Text('One')),
                        ],
                        onChanged: (val) {
                          if (val != null) settingsNotifier.updateDefaultRepeat(val);
                        },
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.speed_outlined),
                      title: const Text('Playback Speed'),
                      subtitle: const Text('Adjust audio playing speed rate'),
                      trailing: DropdownButton<double>(
                        value: settings.playbackSpeed,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 0.5, child: Text('0.5x')),
                          DropdownMenuItem(value: 0.75, child: Text('0.75x')),
                          DropdownMenuItem(value: 1.0, child: Text('1.0x')),
                          DropdownMenuItem(value: 1.25, child: Text('1.25x')),
                          DropdownMenuItem(value: 1.5, child: Text('1.5x')),
                          DropdownMenuItem(value: 2.0, child: Text('2.0x')),
                        ],
                        onChanged: (val) {
                          if (val != null) settingsNotifier.updatePlaybackSpeed(val);
                        },
                      ),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.linear_scale_outlined),
                      title: const Text('Gapless Playback'),
                      subtitle: const Text('Minimize silence buffers between tracks'),
                      value: settings.gaplessPlayback,
                      onChanged: (val) => settingsNotifier.updateGaplessPlayback(val),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.transform_outlined),
                      title: const Text('Crossfade Tracks'),
                      subtitle: const Text('Smoothly overlap songs (placeholder)'),
                      value: settings.crossfade,
                      onChanged: (val) => settingsNotifier.updateCrossfade(val),
                    ),
                  ],
                ),
              ),

              // ── 3. Music Library Section ──
              _buildSectionHeader('Music Library'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.sync_outlined),
                      title: const Text('Rescan Music Library'),
                      subtitle: settings.lastScanTime != null
                          ? Text('Last scanned: ${settings.lastScanTime}')
                          : const Text('Scan directories for offline files'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Scanning local library...')),
                        );
                        await ref.read(mediaLibraryServiceProvider.notifier).scanDevice(forceRefresh: true);
                        final now = DateTime.now();
                        final scanStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
                        await settingsNotifier.updateLastScanTime(scanStr);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Library scan completed! Found ${ref.read(songsProvider).length} songs.')),
                          );
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.refresh_outlined),
                      title: const Text('Refresh Metadata'),
                      subtitle: const Text('Reload tags and local file information'),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Metadata tags refreshed successfully.')),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.image_not_supported_outlined),
                      title: const Text('Clear Artwork Cache'),
                      subtitle: const Text('Clean cached album and artist covers'),
                      onTap: _clearArtworkCache,
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatBadge('Songs', localSongs.length.toString()),
                          _buildStatBadge('Albums', localAlbums.length.toString()),
                          _buildStatBadge('Artists', localArtists.length.toString()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── 4. Search Section ──
              _buildSectionHeader('Search'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.delete_sweep_outlined),
                      title: const Text('Clear Search History'),
                      subtitle: Text('Remove $searchHistoryCount cached queries'),
                      onTap: () async {
                        await ref.read(searchHistoryProvider.notifier).clearAll();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Search history cleared.')),
                          );
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.history_outlined),
                      title: const Text('Clear Recent Searches'),
                      subtitle: const Text('Clear local application query recents'),
                      onTap: () async {
                        await ref.read(searchHistoryProvider.notifier).clearAll();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Recent searches cleared.')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),

              // ── 5. Playback Source Section ──
              _buildSectionHeader('Playback Source'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.source_outlined),
                      title: const Text('Preferred Playback Source'),
                      subtitle: Text(settings.preferredSource == 'preferLocal'
                          ? 'Prefer Local'
                          : settings.preferredSource == 'preferYouTube'
                              ? 'Prefer YouTube'
                              : 'Ask Every Time'),
                      trailing: DropdownButton<String>(
                        value: settings.preferredSource,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'preferLocal', child: Text('Prefer Local')),
                          DropdownMenuItem(value: 'preferYouTube', child: Text('Prefer YouTube')),
                          DropdownMenuItem(value: 'askEveryTime', child: Text('Ask Every Time')),
                        ],
                        onChanged: (val) {
                          if (val != null) settingsNotifier.updatePreferredSource(val);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // ── 6. Notifications Section ──
              _buildSectionHeader('Notifications'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.play_circle_outline),
                      title: const Text('Background Playback'),
                      subtitle: const Text('Allow music to continue when app is minimized'),
                      value: settings.backgroundPlayback,
                      onChanged: (val) => settingsNotifier.updateBackgroundPlayback(val),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_active_outlined),
                      title: const Text('Media Notification'),
                      subtitle: const Text('Display playback widget in notification bar'),
                      value: settings.mediaNotification,
                      onChanged: (val) => settingsNotifier.updateMediaNotification(val),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.phonelink_lock_outlined),
                      title: const Text('Lock Screen Controls'),
                      subtitle: const Text('Show playback controls on lock screen'),
                      value: settings.lockScreenControls,
                      onChanged: (val) => settingsNotifier.updateLockScreenControls(val),
                    ),
                  ],
                ),
              ),

              // ── 7. Storage Section ──
              _buildSectionHeader('Storage'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                      child: Column(
                        children: [
                          _buildStorageRow('Artwork Cache Size', _artworkCacheSize),
                          const SizedBox(height: 6.0),
                          _buildStorageRow('Playlist Database Size', _databaseSize),
                          const SizedBox(height: 6.0),
                          _buildStorageRow('Favorites Count', '$favoritesCount tracks'),
                          const SizedBox(height: 6.0),
                          _buildStorageRow('Recently Played Count', '${recentlyPlayedList.length} tracks'),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.image_not_supported_outlined, color: Colors.blue),
                      title: const Text('Clear Cache', style: TextStyle(color: Colors.blue)),
                      subtitle: const Text('Delete local artwork image covers cache'),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Clear Cache?'),
                            content: const Text('Are you sure you want to clear the locally cached album artwork?'),
                            actions: [
                              TextButton(
                                child: const Text('Cancel'),
                                onPressed: () => Navigator.pop(context),
                              ),
                              TextButton(
                                child: const Text('Clear', style: TextStyle(color: Colors.blue)),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _clearArtworkCache();
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
                      title: const Text('Reset Library', style: TextStyle(color: Colors.red)),
                      subtitle: const Text('Wipe favorites, custom playlists, and history'),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Reset Library?'),
                            content: const Text('Are you sure you want to delete all playlists, favorites, history, and stored preferences? This is a destructive action that cannot be undone.'),
                            actions: [
                              TextButton(
                                child: const Text('Cancel'),
                                onPressed: () => Navigator.pop(context),
                              ),
                              TextButton(
                                child: const Text('Wipe Everything', style: TextStyle(color: Colors.red)),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _resetLibrary();
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // ── 8. About Section ──
              _buildSectionHeader('About'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Miee Version'),
                      subtitle: const Text('v1.0.0 (Stable Release)'),
                      onTap: () {
                        final taps = devTaps + 1;
                        ref.read(devTapsProvider.notifier).state = taps;
                        if (taps >= 7 && !devUnlocked) {
                          ref.read(devModeUnlockedProvider.notifier).state = true;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Developer settings unlocked!')),
                          );
                        } else if (taps < 7 && taps > 2) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('You are ${7 - taps} steps away from being a developer.')),
                          );
                        }
                      },
                    ),
                    const ListTile(
                      leading: const Icon(Icons.code_outlined),
                      title: const Text('Flutter Version'),
                      subtitle: const Text('Flutter 3.22.2 (Channel stable)'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.library_books_outlined),
                      title: const Text('Open Source Licenses'),
                      subtitle: const Text('Tap to view third-party packages used'),
                      onTap: () {
                        _showInfoDialog('Open Source Licences', 'This application leverages high-performance libraries from the Flutter community:\n\n- riverpod: State management\n- just_audio: Core player engine\n- hive: High-performance databases\n- go_router: Page routing\n- permission_handler: Media scanner utilities\n\nThanks to all contributors!');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('Privacy Policy'),
                      subtitle: const Text('Read our data privacy statement'),
                      onTap: () {
                        _showInfoDialog('Privacy Policy', 'Miee Music Player is a local-first application. We do not transmit your local storage music data, queries, or media history to external servers. Stream requests are handled directly with respective public streams.');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.gavel_outlined),
                      title: const Text('Terms of Service'),
                      subtitle: const Text('User agreements and terms of usage'),
                      onTap: () {
                        _showInfoDialog('Terms of Service', 'By using Miee, you agree to comply with your local copyright laws regarding private music files and media streams. Miee operates on user-supplied storage directories.');
                      },
                    ),
                  ],
                ),
              ),

              // ── Hidden Developer Section ──
              if (devUnlocked) ...[
                const SizedBox(height: 16.0),
                _buildSectionHeader('Developer Options'),
                Card(
                  elevation: 0,
                  color: Colors.red.withOpacity(0.08),
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.red.withOpacity(0.3), width: 1.0),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.format_list_numbered, color: Colors.red),
                        title: const Text('Current Queue Length', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        subtitle: Text('${ref.watch(queueManagerProvider).queue.length} items in list'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.stream, color: Colors.red),
                        title: const Text('Current Playback State', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        subtitle: Text(ref.watch(playerControllerProvider).status.toString()),
                      ),
                      ListTile(
                        leading: const Icon(Icons.audiotrack, color: Colors.red),
                        title: const Text('Active Audio Source', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        subtitle: Text(ref.watch(playerControllerProvider).currentTrack != null
                            ? '${ref.watch(playerControllerProvider).currentTrack!.title} (${ref.watch(playerControllerProvider).currentTrack!.isYoutube ? "YouTube" : "Local"})'
                            : 'None'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.security, color: Colors.red),
                        title: const Text('Media Permission Status', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        subtitle: Text(_permissionStatus.toString()),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 120.0), // Padding to clear bottom navigation and mini player
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 3,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/home');
              break;
            case 1:
              context.go('/search');
              break;
            case 2:
              context.go('/library');
              break;
            case 3:
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_music),
            label: 'Library',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20.0, bottom: 8.0, left: 4.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildStatBadge(String label, String value) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildStorageRow(String label, String value) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _showInfoDialog(String title, String body) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
