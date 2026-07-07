import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';

/// Home screen placeholder.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Miee'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {},
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.paddingSymmetricHorizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSpacing.heightLg,
              Text(
                'Good morning',
                style: theme.textTheme.headlineLarge,
              ),
              AppSpacing.heightXl,
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Home Page Placeholder',
                        style: theme.textTheme.headlineMedium,
                      ),
                      AppSpacing.heightMd,
                      ElevatedButton(
                        onPressed: () => context.push('/player'),
                        child: const Text('Go to Now Playing'),
                      ),
                      AppSpacing.heightSm,
                      ElevatedButton(
                        onPressed: () => context.push('/library'),
                        child: const Text('Go to Library'),
                      ),
                      AppSpacing.heightSm,
                      ElevatedButton(
                        onPressed: () => context.push('/search'),
                        child: const Text('Go to Search'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (index) {
          switch (index) {
            case 0:
              break;
            case 1:
              context.go('/search');
              break;
            case 2:
              context.go('/library');
              break;
            case 3:
              context.go('/settings');
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
