import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/widget/miee_widget_sync_service.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/midnight_velvet_tokens.dart';

/// Root Widget of the Miee Music Player application.
class MieeApp extends ConsumerStatefulWidget {
  const MieeApp({super.key});

  @override
  ConsumerState<MieeApp> createState() => _MieeAppState();
}

class _MieeAppState extends ConsumerState<MieeApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enableImmersiveMode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final router = ref.read(appRouterProvider);
      ref.read(widgetSyncServiceProvider).attachRouter(router);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restoreNormalUi();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enableImmersiveMode();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _restoreNormalUi();
    }
  }

  void _enableImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _restoreNormalUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('STARTUP: MieeApp.build() entered');
    final router = ref.watch(appRouterProvider);
    final isDesktop = (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.windows ||
                defaultTargetPlatform == TargetPlatform.linux ||
                defaultTargetPlatform == TargetPlatform.macOS)) ||
        kIsWeb;

    return MaterialApp.router(
      title: 'Miee Music Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      darkTheme: MidnightVelvetTokens.darkTheme,
      themeMode: isDesktop ? ThemeMode.dark : ThemeMode.system,
      routerConfig: router,
    );
  }
}
