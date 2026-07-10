import 'package:flutter/material.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// Root Widget of the Miee Music Player application.
class MieeApp extends StatelessWidget {
  const MieeApp({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('STARTUP: MieeApp.build() entered');
    debugPrint('STARTUP: MaterialApp.router() building');
    return MaterialApp.router(
      title: 'Miee Music Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      routerConfig: appRouter,
    );
  }
}
