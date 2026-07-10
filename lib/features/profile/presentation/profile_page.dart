import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../shared/widgets/profile_avatar.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../library/providers/library_providers.dart';
import '../../media/providers/media_providers.dart';
import '../../../../core/audio/providers.dart';
import '../../../../core/audio/playback_state.dart';
import '../../../../core/storage/adapters/history_entry.dart';
import '../../../../core/sync/sync_state.dart';
import '../../../../core/sync/sync_manager.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/profile_model.dart';
import 'profile_controller.dart';

/// User Profile screen detailing stats, custom details, preferences, and offline-first cloud sync actions.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider);
    final profileNotifier = ref.read(profileProvider.notifier);

    // Watch auth and sync states
    final authState = ref.watch(authControllerProvider);
    final authNotifier = ref.read(authControllerProvider.notifier);
    final syncState = ref.watch(syncStateProvider);
    final syncManager = ref.read(syncManagerProvider);

    // Watch dynamic data for listening statistics calculation
    final localSongs = ref.watch(songsProvider);
    final playlists = ref.watch(userPlaylistsProvider);
    final favorites = ref.watch(favoritesProvider);
    final recentlyPlayedAsync = ref.watch(recentlyPlayedProvider);
    final recentlyPlayedList = recentlyPlayedAsync.value ?? [];

    // Calculate Dynamic Statistics
    final totalSongsPlayed = recentlyPlayedList.length;
    
    // Total listening time: Sum duration of recently played items
    int totalListeningSecs = recentlyPlayedList.fold(0, (sum, entry) => sum + _parseDurationToSeconds(entry.track.duration));
    final totalListeningMins = (totalListeningSecs / 60).toStringAsFixed(1);

    // Calculate dynamic favorite artist based on history count
    final favoriteArtistCalculated = _calculateFavoriteArtist(recentlyPlayedList);

    // Member since date formatting
    final memberSince = _formatDate(profile.createdDate);

    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              top: false,
              bottom: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 12.0),
              
              // Profile Picture & Name Display
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  ProfileAvatar(
                    imageUrl: profile.profilePicturePath,
                    size: 96.0,
                  ),
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primary,
                    radius: 18.0,
                    child: IconButton(
                      icon: const Icon(Icons.camera_alt, size: 16.0, color: Colors.white),
                      onPressed: () => _showEditProfilePictureSheet(context, ref, profileNotifier),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16.0),

              Text(
                profile.displayName,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (profile.username != null && profile.username!.isNotEmpty)
                Text(
                  '@${profile.username}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 6.0),
              Text(
                'Member Since $memberSince',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 24.0),

              // ── Cloud Integration Section ──
              _buildSectionTitle(context, 'Cloud Integration'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (authState.user != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Linked Cloud Account',
                                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    authState.user!.email ?? 'Anonymous User',
                                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.logout, color: Colors.red),
                              onPressed: () => _showSignOutDialog(context, authNotifier, syncManager),
                            ),
                          ],
                        ),
                        const Divider(height: 24.0),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sync Status',
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                _buildSyncStatusText(context, syncState),
                              ],
                            ),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.sync, size: 16),
                              label: const Text('Sync Now'),
                              onPressed: syncState.status == SyncStatus.syncing ? null : () => syncManager.triggerSync(),
                            ),
                          ],
                        ),
                      ] else ...[
                        Text(
                          'Back up to the Cloud',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4.0),
                        Text(
                          'Synchronize your playlists, favorites, history, and preferences across your devices securely.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12.0),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.cloud_queue),
                            label: const Text('Connect to Cloud'),
                            onPressed: () => _showAuthDialog(context, ref, authNotifier, syncManager),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16.0),

              // Listening Statistics Row Grid
              _buildSectionTitle(context, 'Listening Statistics'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem(context, 'Songs Played', totalSongsPlayed.toString()),
                          _buildStatItem(context, 'Listening Time', '$totalListeningMins m'),
                          _buildStatItem(context, 'Playlists', playlists.length.toString()),
                        ],
                      ),
                      const Divider(height: 24.0),
                      _buildStorageRow(context, 'Top Artist (History)', favoriteArtistCalculated),
                      const SizedBox(height: 8.0),
                      _buildStorageRow(context, 'Favorite Genre (Profile)', profile.favoriteGenre),
                      const SizedBox(height: 8.0),
                      _buildStorageRow(context, 'Favorite Artist (Profile)', profile.favoriteArtist),
                      const SizedBox(height: 8.0),
                      _buildStorageRow(context, 'Favorites Count', '${favorites.length} tracks'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16.0),

              // Quick Actions Panel
              _buildSectionTitle(context, 'Quick Actions'),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('Edit Profile'),
                      subtitle: const Text('Modify name, username, genres, and photo'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showEditProfileDialog(context, profile, profileNotifier),
                    ),
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: const Text('Application Settings'),
                      subtitle: const Text('Playback rules, storage cache, notifications'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('About Miee'),
                      subtitle: const Text('App information and software details'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('About Miee'),
                            content: const Text('Miee is an offline-first, premium minimalist audio playback player. Fully written in Flutter using Clean Architecture principles, Hive storage persistence, and Riverpod providers.\n\nBuilt by the Antigravity Team.'),
                            actions: [
                              TextButton(
                                child: const Text('OK'),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(height: 160.0 + bottomInset),
            ],
          ),
        ),
      ),
    ),
      Positioned(
        left: AppSpacing.marginMobile,
        right: AppSpacing.marginMobile,
        bottom: 80.0 + bottomInset + AppSpacing.sm,
        child: Consumer(
          builder: (context, ref, child) {
            final playbackState = ref.watch(playerControllerProvider);
            final controller = ref.read(playerControllerProvider.notifier);
            final currentTrack = playbackState.currentTrack;

            if (currentTrack == null) {
              return const SizedBox.shrink();
            }

            final isPlaying = playbackState.status == PlaybackStatus.playing;
            final total = playbackState.duration.inMilliseconds;
            final pos = playbackState.position.inMilliseconds;
            final progress = total > 0 ? pos / total : 0.0;

            return MiniPlayer(
              musicItem: currentTrack,
              progress: progress,
              isPlaying: isPlaying,
              isFavorited: favorites.any((t) => t.id == currentTrack.id),
              isDark: true, // Black backing color matches Stitch HTML design
              onTap: () => context.push('/player'),
              onPlayPauseTap: () {
                if (isPlaying) {
                  controller.pause();
                } else {
                  controller.play();
                }
              },
              onFavoriteTap: () {},
            );
          },
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: BottomNavigation(
          currentIndex: 3, // Setting/Profile is tab 3
          onTap: (index) {
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
          },
        ),
      ),
    ],
  ),
);
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4.0, bottom: 8.0, top: 12.0),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
        ),
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value) {
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
        const SizedBox(height: 4.0),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildStorageRow(BuildContext context, String label, String value) {
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

  Widget _buildSyncStatusText(BuildContext context, SyncState state) {
    final theme = Theme.of(context);
    switch (state.status) {
      case SyncStatus.idle:
        return Text(
          'Up to date',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.green),
        );
      case SyncStatus.syncing:
        return Text(
          'Syncing in background...',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
        );
      case SyncStatus.success:
        final timeStr = state.lastSynced != null
            ? '${state.lastSynced!.hour.toString().padLeft(2, '0')}:${state.lastSynced!.minute.toString().padLeft(2, '0')}'
            : '';
        return Text(
          'Last synced at $timeStr',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.green),
        );
      case SyncStatus.error:
        return Text(
          'Sync failed. Retrying...',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
        );
    }
  }

  String _calculateFavoriteArtist(List<HistoryEntry> history) {
    if (history.isEmpty) return 'None';
    final counts = <String, int>{};
    for (final entry in history) {
      final artist = entry.track.artist;
      counts[artist] = (counts[artist] ?? 0) + 1;
    }
    var fav = 'None';
    var maxVal = 0;
    counts.forEach((k, v) {
      if (v > maxVal) {
        maxVal = v;
        fav = k;
      }
    });
    return fav;
  }

  String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return "${months[date.month - 1]} ${date.year}";
  }

  void _showEditProfilePictureSheet(BuildContext context, WidgetRef ref, ProfileController notifier) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pick image from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final ImagePicker picker = ImagePicker();
                final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                if (image != null) {
                  final activeProfile = ref.read(profileProvider);
                  await notifier.updateProfile(
                    displayName: activeProfile.displayName,
                    username: activeProfile.username,
                    profilePicturePath: image.path,
                    favoriteGenre: activeProfile.favoriteGenre,
                    favoriteArtist: activeProfile.favoriteArtist,
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Remove profile picture', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                await notifier.removeProfilePicture();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context, ProfileModel profile, ProfileController notifier) {
    final nameController = TextEditingController(text: profile.displayName);
    final userController = TextEditingController(text: profile.username ?? '');
    final genreController = TextEditingController(text: profile.favoriteGenre);
    final artistController = TextEditingController(text: profile.favoriteArtist);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Display Name',
                  hintText: 'Enter Display Name',
                ),
              ),
              const SizedBox(height: 8.0),
              TextField(
                controller: userController,
                decoration: const InputDecoration(
                  labelText: 'Username (Optional)',
                  hintText: 'Enter Username',
                ),
              ),
              const SizedBox(height: 8.0),
              TextField(
                controller: genreController,
                decoration: const InputDecoration(
                  labelText: 'Favorite Genre',
                  hintText: 'Enter Genre',
                ),
              ),
              const SizedBox(height: 8.0),
              TextField(
                controller: artistController,
                decoration: const InputDecoration(
                  labelText: 'Favorite Artist',
                  hintText: 'Enter Artist',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('Save'),
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              Navigator.pop(context);
              await notifier.updateProfile(
                displayName: nameController.text.trim(),
                username: userController.text.trim().isEmpty ? null : userController.text.trim(),
                profilePicturePath: profile.profilePicturePath,
                favoriteGenre: genreController.text.trim().isEmpty ? 'Unknown' : genreController.text.trim(),
                favoriteArtist: artistController.text.trim().isEmpty ? 'Unknown' : artistController.text.trim(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAuthDialog(BuildContext context, WidgetRef ref, AuthController authNotifier, SyncManager syncManager) {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final nameController = TextEditingController(text: 'Miee User');
    bool isSignUp = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isSignUp ? 'Create Cloud Account' : 'Connect to Cloud'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSignUp) ...[
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Display Name'),
                  ),
                  const SizedBox(height: 8.0),
                ],
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Email Address'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8.0),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                ),
                const SizedBox(height: 16.0),
                TextButton(
                  child: Text(isSignUp
                      ? 'Already have an account? Sign In'
                      : 'Don\'t have an account? Sign Up'),
                  onPressed: () {
                    setState(() {
                      isSignUp = !isSignUp;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: Text(isSignUp ? 'Sign Up' : 'Sign In'),
              onPressed: () async {
                final email = emailController.text.trim();
                final pass = passwordController.text.trim();
                if (email.isEmpty || pass.isEmpty) return;

                Navigator.pop(context);
                
                bool success = false;
                if (isSignUp) {
                  success = await authNotifier.signUp(email, pass, nameController.text.trim());
                } else {
                  success = await authNotifier.signIn(email, pass);
                }

                if (success) {
                  // Run full remote download on sign in
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Account connected successfully! Loading cloud backup...')),
                  );
                  await syncManager.downloadAllRemoteData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cloud backup restored successfully!')),
                  );
                } else {
                  final error = ref.read(authControllerProvider).errorMessage ?? 'Unknown error';
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Connection Failed'),
                      content: Text(error),
                      actions: [
                        TextButton(
                          child: const Text('OK'),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSignOutDialog(BuildContext context, AuthController authNotifier, SyncManager syncManager) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out?'),
        content: const Text(
          'Before logging out, all pending changes will be uploaded to the cloud backup. '
          'Your local cache data will be kept intact on this device.',
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Uploading local changes and signing out...')),
              );
              // 1. Upload local changes before signing out
              await syncManager.replayOfflineQueue();
              // 2. Perform sign out
              await authNotifier.signOut();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Signed out successfully.')),
              );
            },
          ),
        ],
      ),
    );
  }

  int _parseDurationToSeconds(String durationStr) {
    final parts = durationStr.split(':');
    if (parts.length == 2) {
      final mins = int.tryParse(parts[0]) ?? 0;
      final secs = int.tryParse(parts[1]) ?? 0;
      return mins * 60 + secs;
    }
    return 0;
  }
}
