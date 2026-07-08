import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../library/providers/library_providers.dart';

/// Settings screen placeholder.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sourceMode = ref.watch(sourceSelectionProvider);
    final notifier = ref.read(sourceSelectionProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Miee'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {},
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.paddingSymmetricHorizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Miee',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Version 1.0.0',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              AppSpacing.heightLg,
              Text(
                'Settings',
                style: theme.textTheme.headlineLarge,
              ),
              AppSpacing.heightMd,
              Text(
                'Source Selection Preference',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              AppSpacing.heightSm,
              Text(
                'Configure how Miee selects the audio source when playing or queueing tracks.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              AppSpacing.heightMd,
              RadioListTile<String>(
                title: const Text('Smart Selection'),
                subtitle: const Text('Prefer local version if available, otherwise stream via YouTube.'),
                value: 'smart',
                groupValue: sourceMode,
                activeColor: AppColors.primary,
                onChanged: (val) => notifier.setMode(val!),
              ),
              RadioListTile<String>(
                title: const Text('Always Local'),
                subtitle: const Text('Force playing local device music files only.'),
                value: 'alwaysLocal',
                groupValue: sourceMode,
                activeColor: AppColors.primary,
                onChanged: (val) => notifier.setMode(val!),
              ),
              RadioListTile<String>(
                title: const Text('Always YouTube'),
                subtitle: const Text('Force streaming from YouTube regardless of local files.'),
                value: 'alwaysYouTube',
                groupValue: sourceMode,
                activeColor: AppColors.primary,
                onChanged: (val) => notifier.setMode(val!),
              ),
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
}

