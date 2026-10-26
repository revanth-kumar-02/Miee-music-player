import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/shared/providers/web_navigation_provider.dart';

void main() {
  group('WebNavigationNotifier Tests', () {
    late WebNavigationNotifier notifier;

    setUp(() {
      notifier = WebNavigationNotifier();
    });

    test('Initial state has empty history and both back and forward disabled', () {
      final state = notifier.state;
      expect(state.history, isEmpty);
      expect(state.currentIndex, equals(-1));
      expect(state.canGoBack, isFalse);
      expect(state.canGoForward, isFalse);
      expect(state.currentRoute, isNull);
    });

    test('First recorded route sets index 0 with back/forward disabled', () {
      notifier.recordRoute('/home');
      final state = notifier.state;
      expect(state.history, equals(['/home']));
      expect(state.currentIndex, equals(0));
      expect(state.canGoBack, isFalse);
      expect(state.canGoForward, isFalse);
      expect(state.currentRoute, equals('/home'));
    });

    test('Deduplicates consecutive visits to the same route', () {
      notifier.recordRoute('/home');
      notifier.recordRoute('/home');
      notifier.recordRoute('/home/');

      final state = notifier.state;
      expect(state.history, equals(['/home']));
      expect(state.currentIndex, equals(0));
      expect(state.canGoBack, isFalse);
      expect(state.canGoForward, isFalse);
    });

    test('Navigating to multiple routes enables canGoBack and keeps canGoForward disabled', () {
      notifier.recordRoute('/home');
      notifier.recordRoute('/search');
      notifier.recordRoute('/playlists');

      final state = notifier.state;
      expect(state.history, equals(['/home', '/search', '/playlists']));
      expect(state.currentIndex, equals(2));
      expect(state.canGoBack, isTrue);
      expect(state.canGoForward, isFalse);
      expect(state.currentRoute, equals('/playlists'));
    });

    test('Simulating browser back updates currentIndex and enables canGoForward', () {
      notifier.recordRoute('/home');
      notifier.recordRoute('/search');
      notifier.recordRoute('/playlists');

      // User presses browser back (route becomes /search)
      notifier.recordRoute('/search');
      expect(notifier.state.currentIndex, equals(1));
      expect(notifier.state.canGoBack, isTrue);
      expect(notifier.state.canGoForward, isTrue);
      expect(notifier.state.currentRoute, equals('/search'));

      // User presses browser back again (route becomes /home)
      notifier.recordRoute('/home');
      expect(notifier.state.currentIndex, equals(0));
      expect(notifier.state.canGoBack, isFalse);
      expect(notifier.state.canGoForward, isTrue);
      expect(notifier.state.currentRoute, equals('/home'));
    });

    test('Simulating browser forward updates currentIndex and disables canGoForward at end', () {
      notifier.recordRoute('/home');
      notifier.recordRoute('/search');
      notifier.recordRoute('/playlists');

      // Step back twice
      notifier.recordRoute('/search');
      notifier.recordRoute('/home');
      expect(notifier.state.currentIndex, equals(0));

      // Browser forward to /search
      notifier.recordRoute('/search');
      expect(notifier.state.currentIndex, equals(1));
      expect(notifier.state.canGoBack, isTrue);
      expect(notifier.state.canGoForward, isTrue);

      // Browser forward to /playlists
      notifier.recordRoute('/playlists');
      expect(notifier.state.currentIndex, equals(2));
      expect(notifier.state.canGoBack, isTrue);
      expect(notifier.state.canGoForward, isFalse);
    });

    test('Navigating to a new route from middle of history truncates forward stack', () {
      notifier.recordRoute('/home');
      notifier.recordRoute('/search');
      notifier.recordRoute('/playlists');

      // Step back to /search
      notifier.recordRoute('/search');
      expect(notifier.state.currentIndex, equals(1));

      // User now clicks on /albums instead of going forward
      notifier.recordRoute('/albums');
      final state = notifier.state;
      expect(state.history, equals(['/home', '/search', '/albums']));
      expect(state.currentIndex, equals(2));
      expect(state.canGoBack, isTrue);
      expect(state.canGoForward, isFalse);
      expect(state.currentRoute, equals('/albums'));
    });

    test('reset clears the history and indices', () {
      notifier.recordRoute('/home');
      notifier.recordRoute('/search');
      expect(notifier.state.history.length, equals(2));

      notifier.reset();
      expect(notifier.state.history, isEmpty);
      expect(notifier.state.currentIndex, equals(-1));
      expect(notifier.state.canGoBack, isFalse);
      expect(notifier.state.canGoForward, isFalse);
    });
  });
}
