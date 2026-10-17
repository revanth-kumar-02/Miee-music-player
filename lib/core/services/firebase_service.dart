import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

enum FirebaseInitStatus {
  uninitialized,
  configured,
  missingConfiguration,
  error,
}

/// Manages singleton initialization of Firebase across platforms.
///
/// Ensures Firebase is initialized exactly once, catching missing configuration
/// files gracefully so the app displays a clear setup banner rather than hanging or crashing.
class FirebaseService {
  static FirebaseInitStatus _status = FirebaseInitStatus.uninitialized;
  static String? _errorMessage;

  static FirebaseInitStatus get status => _status;
  static String? get errorMessage => _errorMessage;
  static bool get isConfigured => _status == FirebaseInitStatus.configured;

  static Future<void> initialize() async {
    if (_status == FirebaseInitStatus.configured) return;

    try {
      debugPrint('[FirebaseService] Initializing Firebase...');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _status = FirebaseInitStatus.configured;
      debugPrint('[FirebaseService] Firebase successfully initialized.');
    } catch (e, stack) {
      debugPrint('[FirebaseService] Firebase initialization encountered: $e');
      if (kDebugMode) debugPrintStack(stackTrace: stack);

      final errStr = e.toString().toLowerCase();
      if (errStr.contains('google-services') ||
          errStr.contains('defaultfirebaseoptions') ||
          errStr.contains('not configured') ||
          errStr.contains('no-app')) {
        _status = FirebaseInitStatus.missingConfiguration;
        _errorMessage = 'Firebase configuration file (google-services.json) is missing. '
            'Please place it into android/app/ to enable cloud features.';
      } else {
        _status = FirebaseInitStatus.error;
        _errorMessage = e.toString();
      }
    }
  }
}
