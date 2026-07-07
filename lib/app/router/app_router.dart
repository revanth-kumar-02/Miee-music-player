import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/splash/presentation/splash_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/search/presentation/search_page.dart';
import '../../features/library/presentation/library_page.dart';
import '../../features/player/presentation/player_page.dart';
import '../../features/queue/presentation/queue_page.dart';
import '../../features/settings/presentation/settings_page.dart';

/// App router configuration using go_router.
/// Registers all major feature screens as placeholder routes.
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        return const SplashPage();
      },
    ),
    GoRoute(
      path: '/home',
      builder: (BuildContext context, GoRouterState state) {
        return const HomePage();
      },
    ),
    GoRoute(
      path: '/search',
      builder: (BuildContext context, GoRouterState state) {
        return const SearchPage();
      },
    ),
    GoRoute(
      path: '/library',
      builder: (BuildContext context, GoRouterState state) {
        return const LibraryPage();
      },
    ),
    GoRoute(
      path: '/player',
      builder: (BuildContext context, GoRouterState state) {
        return const PlayerPage();
      },
    ),
    GoRoute(
      path: '/queue',
      builder: (BuildContext context, GoRouterState state) {
        return const QueuePage();
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (BuildContext context, GoRouterState state) {
        return const SettingsPage();
      },
    ),
  ],
);
