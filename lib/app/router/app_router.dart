import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/splash/presentation/splash_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/search/presentation/search_page.dart';
import '../../features/player/presentation/player_page.dart';
import '../../features/queue/presentation/queue_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/playlists/presentation/playlist_detail_page.dart';
import '../../features/playlists/presentation/playlists_page.dart';
import '../../features/playlists/presentation/local_songs_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/library/presentation/albums_page.dart';
import '../../features/library/presentation/album_detail_page.dart';
import '../../features/library/presentation/artists_page.dart';
import '../../features/library/presentation/artist_detail_page.dart';
import '../../features/library/presentation/genres_page.dart';
import '../../features/library/presentation/genre_detail_page.dart';
import '../../shared/widgets/main_app_shell.dart';

/// App router configuration using go_router.
/// Registers the SplashPage as a root route, and all other pages within a ShellRoute.
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        debugPrint("STARTUP: GoRouter builder for '/' executing");
        return const SplashPage();
      },
    ),
    ShellRoute(
      builder: (context, state, child) {
        return MainAppShell(child: child);
      },
      routes: [
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
          path: '/player',
          pageBuilder: (BuildContext context, GoRouterState state) {
            return CustomTransitionPage<void>(
              key: state.pageKey,
              child: const PlayerPage(),
              transitionDuration: const Duration(milliseconds: 400),
              reverseTransitionDuration: const Duration(milliseconds: 350),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: animation.drive(
                    Tween<Offset>(
                      begin: const Offset(0.0, 1.0),
                      end: Offset.zero,
                    ).chain(CurveTween(curve: Curves.easeOutCubic)),
                  ),
                  child: child,
                );
              },
            );
          },
        ),
        GoRoute(
          path: '/queue',
          pageBuilder: (BuildContext context, GoRouterState state) {
            return CustomTransitionPage<void>(
              key: state.pageKey,
              child: const QueuePage(),
              transitionDuration: const Duration(milliseconds: 350),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: animation.drive(
                    Tween<Offset>(
                      begin: const Offset(0.0, 1.0),
                      end: Offset.zero,
                    ).chain(CurveTween(curve: Curves.easeOutCubic)),
                  ),
                  child: child,
                );
              },
            );
          },
        ),
        GoRoute(
          path: '/playlists',
          pageBuilder: (BuildContext context, GoRouterState state) {
            return CustomTransitionPage<void>(
              key: state.pageKey,
              child: const PlaylistsPage(),
              transitionDuration: const Duration(milliseconds: 350),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: animation.drive(
                    Tween<Offset>(
                      begin: const Offset(1.0, 0.0),
                      end: Offset.zero,
                    ).chain(CurveTween(curve: Curves.easeOutCubic)),
                  ),
                  child: child,
                );
              },
            );
          },
        ),
        GoRoute(
          path: '/local-songs',
          pageBuilder: (BuildContext context, GoRouterState state) {
            return CustomTransitionPage<void>(
              key: state.pageKey,
              child: const LocalSongsPage(),
              transitionDuration: const Duration(milliseconds: 350),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: animation.drive(
                    Tween<Offset>(
                      begin: const Offset(1.0, 0.0),
                      end: Offset.zero,
                    ).chain(CurveTween(curve: Curves.easeOutCubic)),
                  ),
                  child: child,
                );
              },
            );
          },
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (BuildContext context, GoRouterState state) {
            return CustomTransitionPage<void>(
              key: state.pageKey,
              child: const SettingsPage(),
              transitionDuration: const Duration(milliseconds: 350),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: animation.drive(
                    Tween<Offset>(
                      begin: const Offset(1.0, 0.0),
                      end: Offset.zero,
                    ).chain(CurveTween(curve: Curves.easeOutCubic)),
                  ),
                  child: child,
                );
              },
            );
          },
        ),
        GoRoute(
          path: '/playlist/:id',
          pageBuilder: (BuildContext context, GoRouterState state) {
            final id = state.pathParameters['id']!;
            return CustomTransitionPage<void>(
              key: state.pageKey,
              child: PlaylistDetailPage(playlistId: id),
              transitionDuration: const Duration(milliseconds: 350),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: animation.drive(
                    Tween<Offset>(
                      begin: const Offset(1.0, 0.0),
                      end: Offset.zero,
                    ).chain(CurveTween(curve: Curves.easeOutCubic)),
                  ),
                  child: child,
                );
              },
            );
          },
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (BuildContext context, GoRouterState state) {
            return CustomTransitionPage<void>(
              key: state.pageKey,
              child: const ProfilePage(),
              transitionDuration: const Duration(milliseconds: 350),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: animation.drive(
                    Tween<Offset>(
                      begin: const Offset(1.0, 0.0),
                      end: Offset.zero,
                    ).chain(CurveTween(curve: Curves.easeOutCubic)),
                  ),
                  child: child,
                );
              },
            );
          },
        ),
        GoRoute(
          path: '/albums',
          builder: (BuildContext context, GoRouterState state) {
            return const AlbumsPage();
          },
        ),
        GoRoute(
          path: '/album/:id',
          builder: (BuildContext context, GoRouterState state) {
            final id = state.pathParameters['id']!;
            return AlbumDetailPage(albumId: id);
          },
        ),
        GoRoute(
          path: '/artists',
          builder: (BuildContext context, GoRouterState state) {
            return const ArtistsPage();
          },
        ),
        GoRoute(
          path: '/artist/:id',
          builder: (BuildContext context, GoRouterState state) {
            final id = state.pathParameters['id']!;
            return ArtistDetailPage(artistId: id);
          },
        ),
        GoRoute(
          path: '/genres',
          builder: (BuildContext context, GoRouterState state) {
            return const GenresPage();
          },
        ),
        GoRoute(
          path: '/genre/:id',
          builder: (BuildContext context, GoRouterState state) {
            final id = state.pathParameters['id']!;
            return GenreDetailPage(genreId: id);
          },
        ),
      ],
    ),
  ],
);
