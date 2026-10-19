import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/firebase_service.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/register_page.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/onboarding/presentation/artist_selection_page.dart';
import '../../features/profile/providers/profile_providers.dart';
import '../../features/splash/presentation/splash_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/search/presentation/search_page.dart';
import '../../features/player/presentation/player_page.dart';
import '../../features/queue/presentation/queue_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/playlists/presentation/playlist_detail_page.dart';
import '../../features/playlists/presentation/playlists_page.dart';
import '../../features/playlists/presentation/local_songs_page.dart';
import '../../features/playlists/presentation/liked_songs_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/library/presentation/albums_page.dart';
import '../../features/library/presentation/album_detail_page.dart';
import '../../features/library/presentation/artists_page.dart';
import '../../features/library/presentation/artist_detail_page.dart';
import '../../features/library/presentation/genres_page.dart';
import '../../features/library/presentation/genre_detail_page.dart';
import '../../shared/widgets/main_app_shell.dart';

/// Listens to authentication and profile state to trigger router re-evaluation.
class AppRouterNotifier extends ChangeNotifier {
  final Ref _ref;

  AppRouterNotifier(this._ref) {
    _ref.listen(authStateChangesProvider, (_, __) => notifyListeners());
    _ref.listen(userProfileNotifierProvider, (_, __) => notifyListeners());
    _ref.listen(guestModeProvider, (_, __) => notifyListeners());
  }

  String? redirect(BuildContext context, GoRouterState state) {
    final location = state.matchedLocation;
    final isGoingToSplash = location == '/';
    final isGoingToLogin = location == '/login';
    final isGoingToRegister = location == '/register';
    final isGoingToOnboarding = location == '/onboarding';

    // 1. Allow splash screen to execute its entry branding
    if (isGoingToSplash) return null;

    // 2. Allow guest mode access
    final isGuest = _ref.read(guestModeProvider);
    if (isGuest) {
      if (isGoingToLogin || isGoingToRegister) return '/home';
      return null;
    }

    final authUser = _ref.read(currentAuthUserProvider);

    // 3. Unauthenticated user: restrict access to /login and /register
    // If Firebase is not configured, allow guest access to all music features
    if (authUser == null) {
      if (!FirebaseService.isConfigured) return null;
      if (isGoingToLogin || isGoingToRegister || isGoingToOnboarding) return null;
      return '/login';
    }

    // 3. Authenticated user: verify onboarding status
    final profileState = _ref.read(userProfileNotifierProvider);

    // If profile is still loading from Firestore/cache, do not redirect prematurely
    if (profileState.isLoading && profileState.profile == null) {
      return null;
    }

    final profile = profileState.profile;
    final isOnboardingCompleted = profile?.onboardingCompleted ?? false;

    // Incomplete onboarding: must complete artist selection before entering Home
    if (!isOnboardingCompleted) {
      if (isGoingToOnboarding) return null;
      return '/onboarding';
    }

    // Completed onboarding: prevent navigating back to login, register, onboarding, or splash
    if (isGoingToLogin || isGoingToRegister || isGoingToOnboarding) {
      return '/home';
    }

    // Allow normal destination inside the app
    return null;
  }
}

final appRouterNotifierProvider = Provider<AppRouterNotifier>((ref) {
  return AppRouterNotifier(ref);
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(appRouterNotifierProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const ArtistSelectionPage(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return MainAppShell(child: child);
        },
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomePage(),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchPage(),
          ),
          GoRoute(
            path: '/player',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
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
            ),
          ),
          GoRoute(
            path: '/queue',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
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
            ),
          ),
          GoRoute(
            path: '/playlists',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
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
            ),
          ),
          GoRoute(
            path: '/local-songs',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
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
            ),
          ),
          GoRoute(
            path: '/liked-songs',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              child: const LikedSongsPage(),
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
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
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
            ),
          ),
          GoRoute(
            path: '/playlist/:id',
            pageBuilder: (context, state) {
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
            pageBuilder: (context, state) => CustomTransitionPage<void>(
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
            ),
          ),
          GoRoute(
            path: '/albums',
            builder: (context, state) => const AlbumsPage(),
          ),
          GoRoute(
            path: '/album/:id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return AlbumDetailPage(albumId: id);
            },
          ),
          GoRoute(
            path: '/artists',
            builder: (context, state) => const ArtistsPage(),
          ),
          GoRoute(
            path: '/artist/:id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return ArtistDetailPage(artistId: id);
            },
          ),
          GoRoute(
            path: '/genres',
            builder: (context, state) => const GenresPage(),
          ),
          GoRoute(
            path: '/genre/:id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return GenreDetailPage(genreId: id);
            },
          ),
        ],
      ),
    ],
  );
});

/// Direct fallback router reference for existing code/tests.
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashPage(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterPage(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const ArtistSelectionPage(),
    ),
    ShellRoute(
      builder: (context, state, child) => MainAppShell(child: child),
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => const HomePage(),
        ),
      ],
    ),
  ],
);
