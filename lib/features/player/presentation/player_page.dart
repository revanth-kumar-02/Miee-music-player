import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';

/// Now Playing screen placeholder.
class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.expand_more),
          onPressed: () => context.pop(),
        ),
        title: const Text('NOW PLAYING'),
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music),
            onPressed: () => context.push('/queue'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.paddingSymmetricHorizontal,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Now Playing Screen Placeholder',
                style: theme.textTheme.headlineMedium,
              ),
              AppSpacing.heightXxl,
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 36),
                    onPressed: () {},
                  ),
                  AppSpacing.widthLg,
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColors.inverseSurface,
                    child: IconButton(
                      icon: const Icon(Icons.play_arrow, size: 36, color: Colors.white),
                      onPressed: () {},
                    ),
                  ),
                  AppSpacing.widthLg,
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 36),
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
