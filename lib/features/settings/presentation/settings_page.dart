import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/theme/app_colors.dart';
import '../../library/providers/library_providers.dart';
import '../../media/providers/media_providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/providers/auth_providers.dart';
import '../../profile/providers/profile_providers.dart';
import '../../profile/presentation/profile_controller.dart';
import '../../../shared/widgets/widgets.dart';
import 'settings_controller.dart';

/// Cleaned and unified Settings screen organized strictly into seven categories:
/// 1. Account
/// 2. Personalization
/// 3. Music Library
/// 4. Playback & Notifications
/// 5. Storage & Cache
/// 6. Search History
/// 7. About Miee
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _artworkCacheSize = 'Calculating...';
  String _databaseSize = 'Calculating...';
  PermissionStatus _permissionStatus = PermissionStatus.denied;
  bool _isRefreshingMetadata = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    try {
      final status = await Permission.audio.status;
      if (mounted) {
        setState(() {
          _permissionStatus = status;
        });
      }
    } catch (_) {}
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
    if (i >= suffixes.length) i = suffixes.length - 1;
    return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  Future<int> _calculateCacheSize() async {
    try {
      final tempDir = await getTemporaryDirectory();
      int total = 0;
      if (await tempDir.exists()) {
        await for (final file in tempDir.list(recursive: false, followLinks: false)) {
          if (file is File && (file.path.endsWith('.png') || file.path.endsWith('.cache'))) {
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
        await for (final file in docDir.list(recursive: false, followLinks: false)) {
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
            try {
              await file.delete();
            } catch (_) {}
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
          SnackBar(content: Text('Failed to clear artwork cache: $e')),
        );
      }
    }
  }

  Future<void> _clearAppCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final file in tempDir.list(recursive: true, followLinks: false)) {
          if (file is File) {
            try {
              await file.delete();
            } catch (_) {}
          }
        }
      }
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App cache cleared successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear app cache: $e')),
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
            try {
              await file.delete();
            } catch (_) {}
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

  Future<void> _refreshMetadata() async {
    final isScanning = ref.read(loadingStateProvider);
    if (_isRefreshingMetadata || isScanning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A library scan is already in progress.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isRefreshingMetadata = true;
    });

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Refreshing metadata...'),
          duration: Duration(seconds: 2),
        ),
      );

      await ref.read(mediaLibraryServiceProvider.notifier).scanDevice(forceRefresh: true);

      if (!mounted) return;

      final mediaState = ref.read(mediaLibraryServiceProvider);
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();

      if (mediaState.errorMessage != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(mediaState.errorMessage!),
          ),
        );
      } else if (!mediaState.hasPermission) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Storage permission was denied.'),
          ),
        );
      } else {
        final now = DateTime.now();
        final scanStr =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        await ref.read(settingsControllerProvider.notifier).updateLastScanTime(scanStr);
        _loadStats();

        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Metadata tags refreshed successfully (${mediaState.songs.length} songs).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh metadata: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingMetadata = false;
        });
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
    final searchHistoryCount = ref.watch(searchHistoryProvider).length;

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 960;

    final profile = ref.watch(profileProvider);
    final cloudProfile = ref.watch(currentUserProfileProvider);
    final authUser = ref.watch(currentAuthUserProvider);

    final resolvedDisplayName = (cloudProfile?.displayName.trim().isNotEmpty == true &&
            cloudProfile?.displayName != 'Miee Listener' &&
            cloudProfile?.displayName != 'Miee User')
        ? cloudProfile!.displayName
        : (authUser?.displayName?.trim().isNotEmpty == true &&
                authUser?.displayName != 'Miee Listener' &&
                authUser?.displayName != 'Miee User')
            ? authUser!.displayName!
            : (profile.displayName.isNotEmpty &&
                    profile.displayName != 'Miee User' &&
                    profile.displayName != 'Miee Listener')
                ? profile.displayName
                : (authUser?.email.isNotEmpty == true
                    ? authUser!.email.split('@').first
                    : profile.displayName);

    final resolvedUsername = (profile.username as String?)?.isNotEmpty == true
        ? profile.username as String
        : (resolvedDisplayName != 'Miee User' && resolvedDisplayName != 'Miee Listener')
            ? resolvedDisplayName.toLowerCase().replaceAll(RegExp(r'\s+'), '_')
            : null;

    final resolvedAvatarUrl = (profile.profilePicturePath as String?)?.isNotEmpty == true
        ? profile.profilePicturePath as String
        : (cloudProfile?.avatarUrl?.isNotEmpty == true
            ? cloudProfile!.avatarUrl
            : authUser?.photoUrl);

    final selectedArtists = cloudProfile?.selectedArtists ?? [];

    return Scaffold(
      extendBody: true,
      backgroundColor: AppColors.vanillaCream,
      appBar: const AppHeader(
        title: 'Settings',
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 24.0 : 16.0,
                vertical: 12.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 1. ACCOUNT ──
                  _buildSectionHeader('Account'),
                  _buildSectionCard(
                    children: [
                      _buildAccountProfileTile(
                        context,
                        profile: profile,
                        avatarUrl: resolvedAvatarUrl,
                        displayName: resolvedDisplayName,
                        username: resolvedUsername,
                        email: authUser?.email,
                        isAuthenticated: authUser != null,
                      ),
                      if (authUser == null) ...[
                        const Divider(height: 1, color: AppColors.oatBeige),
                        ListTile(
                          leading: const Icon(Icons.login_rounded, color: AppColors.cocoaPlum),
                          title: const Text(
                            'Sign In or Register',
                            style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                          ),
                          subtitle: const Text(
                            'Sync favorites and playlists across all your devices',
                            style: TextStyle(color: AppColors.mutedMauve),
                          ),
                          trailing: const Icon(Icons.chevron_right, color: AppColors.mutedMauve),
                          onTap: () => context.push('/login'),
                        ),
                      ] else ...[
                        const Divider(height: 1, color: AppColors.oatBeige),
                        ListTile(
                          leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                          title: const Text(
                            'Sign Out',
                            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.redAccent),
                          ),
                          subtitle: Text(
                            'Signed in as ${authUser.email}',
                            style: const TextStyle(color: AppColors.mutedMauve),
                          ),
                          onTap: () => _confirmSignOut(context),
                        ),
                      ],
                    ],
                  ),

                  // ── 2. PERSONALIZATION ──
                  _buildSectionHeader('Personalization'),
                  _buildSectionCard(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.mic_external_on_outlined, color: AppColors.cocoaPlum),
                        title: const Text(
                          'Favourite Artists',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                        ),
                        subtitle: Text(
                          selectedArtists.isNotEmpty
                              ? '${selectedArtists.length} artists selected for your feed'
                              : (profile.favoriteArtist.isNotEmpty && profile.favoriteArtist != 'Unknown Artist'
                                  ? 'Primary: ${profile.favoriteArtist}'
                                  : 'Select artists to tailor your recommendations'),
                          style: const TextStyle(color: AppColors.mutedMauve),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: AppColors.mutedMauve),
                        onTap: () => context.push('/onboarding'),
                      ),
                      if (selectedArtists.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 12.0),
                          child: SizedBox(
                            height: 36.0,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: selectedArtists.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8.0),
                              itemBuilder: (context, index) {
                                final artist = selectedArtists[index];
                                return Chip(
                                  label: Text(
                                    artist.name,
                                    style: const TextStyle(
                                      fontSize: 12.0,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.cocoaPlum,
                                    ),
                                  ),
                                  backgroundColor: AppColors.surfaceContainer,
                                  side: BorderSide(color: AppColors.oatBeige.withOpacity(0.8)),
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                );
                              },
                            ),
                          ),
                        ),
                      const Divider(height: 1, color: AppColors.oatBeige),
                      ListTile(
                        leading: const Icon(Icons.tune_outlined, color: AppColors.cocoaPlum),
                        title: const Text(
                          'Preferred Playback Source',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                        ),
                        subtitle: Text(
                          settings.preferredSource == 'preferLocal'
                              ? 'Prefer Local Audio'
                              : settings.preferredSource == 'preferYouTube'
                                  ? 'Prefer YouTube Music'
                                  : 'Ask Every Time',
                          style: const TextStyle(color: AppColors.mutedMauve),
                        ),
                        trailing: DropdownButton<String>(
                          value: settings.preferredSource,
                          underline: const SizedBox(),
                          icon: const Icon(Icons.arrow_drop_down, color: AppColors.cocoaPlum),
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

                  // ── 3. MUSIC LIBRARY ──
                  _buildSectionHeader('Music Library'),
                  _buildSectionCard(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.sync_outlined, color: AppColors.cocoaPlum),
                        title: const Text(
                          'Rescan Music Library',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                        ),
                        subtitle: settings.lastScanTime != null
                            ? Text('Last scanned: ${settings.lastScanTime}',
                                style: const TextStyle(color: AppColors.mutedMauve))
                            : const Text('Scan directories for offline audio files',
                                style: TextStyle(color: AppColors.mutedMauve)),
                        trailing: const Icon(Icons.chevron_right, color: AppColors.mutedMauve),
                        onTap: () async {
                          if (_isRefreshingMetadata || ref.read(loadingStateProvider)) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Scanning local library...')),
                          );
                          await ref.read(mediaLibraryServiceProvider.notifier).scanDevice(forceRefresh: true);
                          final now = DateTime.now();
                          final scanStr =
                              '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
                          await settingsNotifier.updateLastScanTime(scanStr);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Library scan completed! Found ${ref.read(songsProvider).length} songs.'),
                              ),
                            );
                          }
                        },
                      ),
                      const Divider(height: 1, color: AppColors.oatBeige),
                      ListTile(
                        leading: const Icon(Icons.refresh_outlined, color: AppColors.cocoaPlum),
                        title: const Text(
                          'Refresh Metadata',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                        ),
                        subtitle: const Text(
                          'Reload tags and local file information',
                          style: TextStyle(color: AppColors.mutedMauve),
                        ),
                        trailing: _isRefreshingMetadata
                            ? const SizedBox(
                                width: 18.0,
                                height: 18.0,
                                child: CircularProgressIndicator(strokeWidth: 2.0, color: AppColors.dustyRose),
                              )
                            : const Icon(Icons.chevron_right, color: AppColors.mutedMauve),
                        onTap: _isRefreshingMetadata ? null : _refreshMetadata,
                      ),
                      const Divider(height: 1, color: AppColors.oatBeige),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatBadge('Songs', localSongs.length.toString()),
                            _buildStatBadge('Albums', localAlbums.length.toString()),
                            _buildStatBadge('Artists', localArtists.length.toString()),
                          ],
                        ),
                      ),
                      if (Platform.isAndroid && _permissionStatus != PermissionStatus.granted) ...[
                        const Divider(height: 1, color: AppColors.oatBeige),
                        ListTile(
                          leading: const Icon(Icons.folder_shared_outlined, color: AppColors.dustyRose),
                          title: const Text('Audio Storage Permission', style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text('Permission is needed to discover songs on your device'),
                          trailing: TextButton(
                            onPressed: () async {
                              final status = await Permission.audio.request();
                              if (mounted) setState(() => _permissionStatus = status);
                              if (status.isPermanentlyDenied) {
                                await openAppSettings();
                              }
                            },
                            child: const Text('Grant', style: TextStyle(color: AppColors.dustyRose, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // ── 4. PLAYBACK & NOTIFICATIONS ──
                  _buildSectionHeader('Playback & Notifications'),
                  _buildSectionCard(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.play_circle_outline, color: AppColors.cocoaPlum),
                        title: const Text(
                          'Background Playback',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                        ),
                        subtitle: const Text(
                          'Allow music to continue when app is minimized',
                          style: TextStyle(color: AppColors.mutedMauve),
                        ),
                        activeColor: AppColors.dustyRose,
                        value: settings.backgroundPlayback,
                        onChanged: (val) => settingsNotifier.updateBackgroundPlayback(val),
                      ),
                      const Divider(height: 1, color: AppColors.oatBeige),
                      SwitchListTile(
                        secondary: const Icon(Icons.notifications_active_outlined, color: AppColors.cocoaPlum),
                        title: const Text(
                          'Media Notification',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                        ),
                        subtitle: const Text(
                          'Display playback controls in notification drawer',
                          style: TextStyle(color: AppColors.mutedMauve),
                        ),
                        activeColor: AppColors.dustyRose,
                        value: settings.mediaNotification,
                        onChanged: (val) async {
                          if (val && Platform.isAndroid) {
                            final status = await Permission.notification.status;
                            if (status.isDenied) {
                              final res = await Permission.notification.request();
                              if (!res.isGranted) return;
                            } else if (status.isPermanentlyDenied) {
                              await openAppSettings();
                              return;
                            }
                          }
                          settingsNotifier.updateMediaNotification(val);
                        },
                      ),
                      const Divider(height: 1, color: AppColors.oatBeige),
                      SwitchListTile(
                        secondary: const Icon(Icons.screen_lock_portrait_outlined, color: AppColors.cocoaPlum),
                        title: const Text(
                          'Lock Screen Controls',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                        ),
                        subtitle: const Text(
                          'Show playback controls on device lock screen',
                          style: TextStyle(color: AppColors.mutedMauve),
                        ),
                        activeColor: AppColors.dustyRose,
                        value: settings.lockScreenControls,
                        onChanged: (val) => settingsNotifier.updateLockScreenControls(val),
                      ),
                      const Divider(height: 1, color: AppColors.oatBeige),
                      SwitchListTile(
                        secondary: const Icon(Icons.restore_outlined, color: AppColors.cocoaPlum),
                        title: const Text(
                          'Resume Playback on Startup',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                        ),
                        subtitle: const Text(
                          'Restore last active song state when Miee starts',
                          style: TextStyle(color: AppColors.mutedMauve),
                        ),
                        activeColor: AppColors.dustyRose,
                        value: settings.resumePlayback,
                        onChanged: (val) => settingsNotifier.updateResumePlayback(val),
                      ),
                    ],
                  ),

                  // ── 5. STORAGE & CACHE ──
                  _buildSectionHeader('Storage & Cache'),
                  _buildSectionCard(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
                        child: Column(
                          children: [
                            _buildStorageRow('Artwork Cache Size', _artworkCacheSize),
                            const SizedBox(height: 8.0),
                            _buildStorageRow('Playlist Database Size', _databaseSize),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: AppColors.oatBeige),
                      ListTile(
                        leading: const Icon(Icons.image_not_supported_outlined, color: AppColors.cocoaPlum),
                        title: const Text(
                          'Clear Artwork Cache',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                        ),
                        subtitle: Text(
                          'Free up image storage ($_artworkCacheSize)',
                          style: const TextStyle(color: AppColors.mutedMauve),
                        ),
                        onTap: () => _confirmAction(
                          context,
                          title: 'Clear Artwork Cache?',
                          message: 'Locally cached album covers will be deleted. They will automatically re-download when needed.',
                          actionLabel: 'Clear Cache',
                          onConfirm: _clearArtworkCache,
                        ),
                      ),
                      const Divider(height: 1, color: AppColors.oatBeige),
                      ListTile(
                        leading: const Icon(Icons.cleaning_services_outlined, color: AppColors.cocoaPlum),
                        title: const Text(
                          'Clear App Cache',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                        ),
                        subtitle: const Text(
                          'Delete temporary application cache files',
                          style: TextStyle(color: AppColors.mutedMauve),
                        ),
                        onTap: () => _confirmAction(
                          context,
                          title: 'Clear App Cache?',
                          message: 'This clears temporary media files and scratch storage.',
                          actionLabel: 'Clear Cache',
                          onConfirm: _clearAppCache,
                        ),
                      ),
                      const Divider(height: 1, color: AppColors.oatBeige),
                      ListTile(
                        leading: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
                        title: const Text(
                          'Reset Library & Data',
                          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.redAccent),
                        ),
                        subtitle: const Text(
                          'Wipe all custom playlists, favorites, and history',
                          style: TextStyle(color: AppColors.mutedMauve),
                        ),
                        onTap: () => _confirmAction(
                          context,
                          title: 'Reset Library?',
                          message: 'Are you sure you want to delete all custom playlists, favorites, search history, and stored preferences? This is a destructive action that cannot be undone.',
                          actionLabel: 'Wipe Everything',
                          isDestructive: true,
                          onConfirm: _resetLibrary,
                        ),
                      ),
                    ],
                  ),

                  // ── 6. SEARCH HISTORY ──
                  _buildSectionHeader('Search History'),
                  _buildSectionCard(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.manage_search_outlined, color: AppColors.cocoaPlum),
                        title: const Text(
                          'Search History',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                        ),
                        subtitle: Text(
                          '$searchHistoryCount cached queries in local search history',
                          style: const TextStyle(color: AppColors.mutedMauve),
                        ),
                      ),
                      const Divider(height: 1, color: AppColors.oatBeige),
                      ListTile(
                        leading: const Icon(Icons.delete_sweep_outlined, color: AppColors.cocoaPlum),
                        title: const Text(
                          'Clear Search History',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                        ),
                        subtitle: const Text(
                          'Remove all recent search queries and suggestions',
                          style: TextStyle(color: AppColors.mutedMauve),
                        ),
                        onTap: () => _confirmAction(
                          context,
                          title: 'Clear Search History?',
                          message: 'All your cached and recent search queries will be removed.',
                          actionLabel: 'Clear',
                          onConfirm: () async {
                            await ref.read(searchHistoryProvider.notifier).clearAll();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Search history cleared.')),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),

                  // ── 7. ABOUT MIEE ──
                  _buildSectionHeader('About Miee'),
                  _buildSectionCard(
                    children: [
                      const ListTile(
                        leading: Icon(Icons.info_outline, color: AppColors.cocoaPlum),
                        title: Text(
                          'Miee Version',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                        ),
                        subtitle: Text('v1.0.0 (Build 1) • Stable', style: TextStyle(color: AppColors.mutedMauve)),
                      ),
                      const Divider(height: 1, color: AppColors.oatBeige),
                      ListTile(
                        leading: const Icon(Icons.library_books_outlined, color: AppColors.cocoaPlum),
                        title: const Text(
                          'Open Source Licenses',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                        ),
                        subtitle: const Text(
                          'View licenses of libraries and dependencies',
                          style: TextStyle(color: AppColors.mutedMauve),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: AppColors.mutedMauve),
                        onTap: () {
                          showLicensePage(
                            context: context,
                            applicationName: 'Miee Music',
                            applicationVersion: '1.0.0',
                            applicationLegalese: 'Crafted with Flutter & Material 3',
                          );
                        },
                      ),
                      const Divider(height: 1, color: AppColors.oatBeige),
                      ListTile(
                        leading: const Icon(Icons.description_outlined, color: AppColors.cocoaPlum),
                        title: const Text(
                          'Privacy Policy',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                        ),
                        subtitle: const Text('Read our local-first privacy statement', style: TextStyle(color: AppColors.mutedMauve)),
                        trailing: const Icon(Icons.chevron_right, color: AppColors.mutedMauve),
                        onTap: () {
                          _showInfoDialog(
                            'Privacy Policy',
                            'Miee Music Player is a local-first application. We do not transmit your private local music files, personal storage contents, or playback logs to external servers. Online audio streams are retrieved directly through public streams without third-party data tracking.',
                          );
                        },
                      ),
                      const Divider(height: 1, color: AppColors.oatBeige),
                      ListTile(
                        leading: const Icon(Icons.gavel_outlined, color: AppColors.cocoaPlum),
                        title: const Text(
                          'Terms of Service',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.cocoaPlum),
                        ),
                        subtitle: const Text('Review user agreements and terms of usage', style: TextStyle(color: AppColors.mutedMauve)),
                        trailing: const Icon(Icons.chevron_right, color: AppColors.mutedMauve),
                        onTap: () {
                          _showInfoDialog(
                            'Terms of Service',
                            'By using Miee, you agree to comply with your local copyright laws regarding private music files and media streams. Miee operates on user-supplied storage directories and public media feeds.',
                          );
                        },
                      ),
                    ],
                  ),

                  // Bottom padding allowing clean scroll above bottom navigation bar
                  SizedBox(height: 96.0 + bottomInset),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── REUSABLE UI BUILDERS ───────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0, left: 4.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16.0,
          fontWeight: FontWeight.w700,
          color: AppColors.cocoaPlum,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  Widget _buildSectionCard({required List<Widget> children}) {
    return Material(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16.0),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(color: AppColors.oatBeige.withOpacity(0.6), width: 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _buildAccountProfileTile(
    BuildContext context, {
    required dynamic profile,
    String? avatarUrl,
    required String displayName,
    String? username,
    String? email,
    required bool isAuthenticated,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showAvatarOptions(context),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                ProfileAvatar(
                  imageUrl: avatarUrl ?? (profile.profilePicturePath as String?),
                  size: 60.0,
                ),
                Container(
                  width: 20.0,
                  height: 20.0,
                  decoration: const BoxDecoration(
                    color: AppColors.dustyRose,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt, size: 11.0, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 16.0,
                          fontWeight: FontWeight.bold,
                          color: AppColors.cocoaPlum,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                      decoration: BoxDecoration(
                        color: isAuthenticated
                            ? AppColors.dustyRose.withOpacity(0.12)
                            : AppColors.mutedMauve.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6.0),
                      ),
                      child: Text(
                        isAuthenticated ? 'Signed In' : 'Guest',
                        style: TextStyle(
                          fontSize: 11.0,
                          fontWeight: FontWeight.w600,
                          color: isAuthenticated ? AppColors.dustyRose : AppColors.mutedMauve,
                        ),
                      ),
                    ),
                  ],
                ),
                if (username != null && username.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Text(
                      '@$username',
                      style: const TextStyle(fontSize: 13.0, color: AppColors.mutedMauve),
                    ),
                  )
                else if (email != null && email.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Text(
                      email,
                      style: const TextStyle(fontSize: 13.0, color: AppColors.mutedMauve),
                    ),
                  ),
                const SizedBox(height: 8.0),
                SizedBox(
                  height: 30.0,
                  child: OutlinedButton(
                    onPressed: () => context.push('/profile'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      side: const BorderSide(color: AppColors.oatBeige),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                    child: const Text(
                      'Manage Profile',
                      style: TextStyle(fontSize: 12.0, color: AppColors.cocoaPlum, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAvatarOptions(BuildContext context) {
    final profile = ref.read(profileProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                'Profile Photo',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: AppColors.cocoaPlum),
              ),
            ),
            const Divider(color: AppColors.oatBeige),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.cocoaPlum),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickSettingsProfileImage();
              },
            ),
            if (profile.profilePicturePath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Remove Photo', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  _removeSettingsProfileImage();
                },
              ),
            const SizedBox(height: 12.0),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSettingsProfileImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    final profile = ref.read(profileProvider);
    await ref.read(profileProvider.notifier).updateProfile(
          displayName: profile.displayName,
          username: profile.username,
          profilePicturePath: picked.path,
          favoriteGenre: profile.favoriteGenre,
          favoriteArtist: profile.favoriteArtist,
        );
  }

  Future<void> _removeSettingsProfileImage() async {
    await ref.read(profileProvider.notifier).removeProfilePicture();
  }

  Widget _buildStatBadge(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20.0,
            fontWeight: FontWeight.bold,
            color: AppColors.cocoaPlum,
          ),
        ),
        const SizedBox(height: 2.0),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.0,
            fontWeight: FontWeight.w500,
            color: AppColors.mutedMauve,
          ),
        ),
      ],
    );
  }

  Widget _buildStorageRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14.0,
              color: AppColors.mutedMauve,
            ),
          ),
        ),
        const SizedBox(width: 8.0),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w600,
            color: AppColors.cocoaPlum,
          ),
        ),
      ],
    );
  }

  void _confirmAction(
    BuildContext context, {
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onConfirm,
    bool isDestructive = false,
  }) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.cocoaPlum)),
        content: Text(message, style: const TextStyle(color: AppColors.mutedMauve)),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: AppColors.mutedMauve)),
            onPressed: () => Navigator.pop(dialogCtx),
          ),
          TextButton(
            child: Text(
              actionLabel,
              style: TextStyle(
                color: isDestructive ? Colors.redAccent : AppColors.dustyRose,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () {
              Navigator.pop(dialogCtx);
              onConfirm();
            },
          ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
        title: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.cocoaPlum)),
        content: const Text(
          'Are you sure you want to sign out of your Miee account? Local offline songs will remain accessible.',
          style: TextStyle(color: AppColors.mutedMauve),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: AppColors.mutedMauve)),
            onPressed: () => Navigator.pop(dialogCtx),
          ),
          TextButton(
            child: const Text('Sign Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await ref.read(authControllerProvider.notifier).signOut();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Signed out successfully.')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(String title, String body) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.cocoaPlum)),
        content: Text(body, style: const TextStyle(color: AppColors.mutedMauve, height: 1.4)),
        actions: [
          TextButton(
            child: const Text('OK', style: TextStyle(color: AppColors.dustyRose, fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
