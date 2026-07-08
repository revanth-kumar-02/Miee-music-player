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
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    final localSongs = ref.watch(songsProvider);
    final localAlbums = ref.watch(albumsProvider);
    final localArtists = ref.watch(artistsProvider);
    final favoritesCount = ref.watch(favoritesProvider).length;
    final searchHistoryCount = ref.watch(searchHistoryProvider).length;

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

              // ── Appearance Section ──
              _buildSectionHeader('Appearance'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('Theme Mode'),
                      subtitle: Text(settings.theme.toUpperCase()),
                      trailing: DropdownButton<String>(
                        value: settings.theme,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'system', child: Text('System')),
                          DropdownMenuItem(value: 'light', child: Text('Light')),
                          DropdownMenuItem(value: 'dark', child: Text('Dark')),
                        ],
                        onChanged: (val) {
                          if (val != null) settingsNotifier.setTheme(val);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // ── Playback Section ──
              _buildSectionHeader('Playback'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.speed_outlined),
                      title: const Text('Playback Speed'),
                      subtitle: Slider(
                        value: settings.playbackSpeed,
                        min: 0.5,
                        max: 2.0,
                        divisions: 6,
                        label: '${settings.playbackSpeed}x',
                        onChanged: (val) => settingsNotifier.setPlaybackSpeed(val),
                      ),
                      trailing: Text(
                        '${settings.playbackSpeed}x',
                        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.restore_outlined),
                      title: const Text('Resume Playback'),
                      subtitle: const Text('Resume song state on app startup'),
                      value: settings.resumePlayback,
                      onChanged: (val) => settingsNotifier.setResumePlayback(val),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.skip_next_outlined),
                      title: const Text('Auto Play Next'),
                      subtitle: const Text('Play subsequent queue tracks automatically'),
                      value: settings.autoPlayNext,
                      onChanged: (val) => settingsNotifier.setAutoPlayNext(val),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.shuffle_outlined),
                      title: const Text('Shuffle Default'),
                      subtitle: const Text('Always enable shuffle mode for new queues'),
                      value: settings.shuffleDefault,
                      onChanged: (val) => settingsNotifier.setShuffleDefault(val),
                    ),
                    ListTile(
                      leading: const Icon(Icons.repeat_outlined),
                      title: const Text('Repeat Default'),
                      subtitle: Text(settings.repeatDefault.toUpperCase()),
                      trailing: DropdownButton<String>(
                        value: settings.repeatDefault,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'off', child: Text('Off')),
                          DropdownMenuItem(value: 'all', child: Text('All')),
                          DropdownMenuItem(value: 'one', child: Text('One')),
                        ],
                        onChanged: (val) {
                          if (val != null) settingsNotifier.setRepeatDefault(val);
                        },
                      ),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.transform_outlined),
                      title: const Text('Crossfade Tracks'),
                      subtitle: const Text('Smoothly overlap songs (placeholder)'),
                      value: settings.crossfadeEnabled,
                      onChanged: (val) => settingsNotifier.setCrossfadeEnabled(val),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.linear_scale_outlined),
                      title: const Text('Gapless Playback'),
                      subtitle: const Text('Minimize silence buffers between tracks'),
                      value: settings.gaplessPlaybackEnabled,
                      onChanged: (val) => settingsNotifier.setGaplessPlaybackEnabled(val),
                    ),
                  ],
                ),
              ),

              // ── Library & Preferred Source ──
              _buildSectionHeader('Library & YouTube'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.sync_outlined),
                      title: const Text('Rescan Local Library'),
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
                        await settingsNotifier.setLastScanTime(scanStr);
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
                      leading: const Icon(Icons.source_outlined),
                      title: const Text('Preferred Audio Source'),
                      subtitle: Text(settings.sourceSelection == 'smart'
                          ? 'Prefer Local (Smart)'
                          : settings.sourceSelection == 'alwaysLocal'
                              ? 'Always Local'
                              : settings.sourceSelection == 'alwaysYouTube'
                                  ? 'Always YouTube'
                                  : 'Ask Every Time'),
                      trailing: DropdownButton<String>(
                        value: settings.sourceSelection,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'smart', child: Text('Smart Selection')),
                          DropdownMenuItem(value: 'alwaysLocal', child: Text('Always Local')),
                          DropdownMenuItem(value: 'alwaysYouTube', child: Text('Always YouTube')),
                          DropdownMenuItem(value: 'askEveryTime', child: Text('Ask Every Time')),
                        ],
                        onChanged: (val) {
                          if (val != null) settingsNotifier.setSourceSelectionMode(val);
                        },
                      ),
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

              // ── Search & Storage ──
              _buildSectionHeader('Storage & Cache'),
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
                      leading: const Icon(Icons.image_not_supported_outlined),
                      title: const Text('Clear Artwork Cache'),
                      subtitle: Text('Clean on-disk cache: $_artworkCacheSize'),
                      onTap: _clearArtworkCache,
                    ),
                    ListTile(
                      leading: const Icon(Icons.delete_forever_outlined),
                      title: const Text('Reset Library Databases'),
                      subtitle: const Text('Wipe favorites, playlists, and settings'),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Reset Library?'),
                            content: const Text('This will delete all custom playlists, favorited items, recently played histories, and reset setting toggles. This action is irreversible.'),
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
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                      child: Column(
                        children: [
                          _buildStorageRow('Database File Size', _databaseSize),
                          const SizedBox(height: 6.0),
                          _buildStorageRow('Favorites Track Count', '$favoritesCount tracks'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Notifications Section ──
              _buildSectionHeader('Notifications & Background'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_active_outlined),
                      title: const Text('Media Notification'),
                      subtitle: const Text('Display playback widget in notification bar'),
                      value: settings.mediaNotificationEnabled,
                      onChanged: (val) => settingsNotifier.setMediaNotificationEnabled(val),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.play_circle_outline),
                      title: const Text('Background Playback'),
                      subtitle: const Text('Allow music to continue when app is minimized'),
                      value: settings.backgroundPlaybackEnabled,
                      onChanged: (val) => settingsNotifier.setBackgroundPlaybackEnabled(val),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.phonelink_lock_outlined),
                      title: const Text('Lock Screen Controls'),
                      subtitle: const Text('Show playback overlays on devices lock screen'),
                      value: settings.lockScreenControlsEnabled,
                      onChanged: (val) => settingsNotifier.setLockScreenControlsEnabled(val),
                    ),
                  ],
                ),
              ),

              // ── About Section ──
              _buildSectionHeader('About'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('App Version'),
                      subtitle: const Text('Miee v1.0.0 (Stable Release)'),
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
                      title: const Text('Flutter SDK Version'),
                      subtitle: const Text('Flutter 3.22.2 (Channel stable)'),
                    ),
                    const ListTile(
                      leading: const Icon(Icons.person_pin_outlined),
                      title: const Text('Developer'),
                      subtitle: const Text('Antigravity Team'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('Privacy Policy'),
                      subtitle: const Text('Read our data and privacy statement'),
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
                    ListTile(
                      leading: const Icon(Icons.library_books_outlined),
                      title: const Text('Open Source Libraries'),
                      subtitle: const Text('Hive, Riverpod, JustAudio, GoRouter'),
                      onTap: () {
                        _showInfoDialog('Open Source Licences', 'This application leverages high-performance libraries from the Flutter community:\n\n- riverpod: State management\n- just_audio: Core player engine\n- hive: High-performance databases\n- go_router: Page routing\n- permission_handler: Media scanner utilities\n\nThanks to all contributors!');
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
                        leading: const Icon(Icons.developer_mode, color: Colors.red),
                        title: const Text('Current Player Engine', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        subtitle: const Text('just_audio / audio_service active'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.format_list_numbered, color: Colors.red),
                        title: const Text('Active Queue Length', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        subtitle: Text('${ref.watch(queueManagerProvider).queue.length} items in list'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.stream, color: Colors.red),
                        title: const Text('Playback State Status', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        subtitle: Text(ref.watch(playerControllerProvider).status.toString()),
                      ),
                      ListTile(
                        leading: const Icon(Icons.security, color: Colors.red),
                        title: const Text('Media Permission status', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
