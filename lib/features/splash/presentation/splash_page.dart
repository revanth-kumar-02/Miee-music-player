import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/sync/sync_manager.dart';

/// Splash screen that handles branding visualization and triggers background cloud sync.
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  @override
  void initState() {
    super.initState();
    
    // Trigger offline-first background cloud synchronization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncManagerProvider).triggerSync();
    });

    // Simulate auto-navigation to Home screen after 2.5 seconds
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        context.go('/home');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Miee',
              style: theme.textTheme.displayLarge?.copyWith(
                color: AppColors.onSurface,
              ),
            ),
            AppSpacing.heightMd,
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              strokeWidth: 2.0,
            ),
          ],
        ),
      ),
    );
  }
}
