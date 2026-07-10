import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// Root Widget of the Miee Music Player application.
class MieeApp extends StatefulWidget {
  const MieeApp({super.key});

  @override
  State<MieeApp> createState() => _MieeAppState();
}

class _MieeAppState extends State<MieeApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enableImmersiveMode();
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
    debugPrint('STARTUP: MaterialApp.router() building');
    return MaterialApp.router(
      title: 'Miee Music Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      routerConfig: appRouter,
    );
  }
}
