import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import '../features/settings/presentation/settings_controller.dart';

/// Root Widget of the Miee Music Player application.
/// Extends [ConsumerWidget] to integrate Riverpod state management.
class MieeApp extends ConsumerWidget {
  const MieeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final themePref = settings.themeMode;

    ThemeMode mode;
    if (themePref == 'light') {
      mode = ThemeMode.light;
    } else if (themePref == 'dark') {
      mode = ThemeMode.dark;
    } else {
      mode = ThemeMode.system;
    }

    return MaterialApp.router(
      title: 'Miee Music Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: mode,
      routerConfig: appRouter,
    );
  }
}
