import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Configuration and initialization for Supabase client.
abstract class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://qjvjmruovmftcbwrfjsq.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFqdmptcnVvdm1mdGNid3JmanNxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI3NjQ2MjQsImV4cCI6MjEwODM0MDYyNH0.qpYnNxLM9sw_2bkRBEt8mzXPsVWOZxhjkp8s6cTeBIA',
  );

  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  static bool get hasActiveSupabase =>
      url.isNotEmpty &&
      url.startsWith('https://') &&
      anonKey.isNotEmpty &&
      anonKey != 'your-anon-key';

  static Future<void> initialize() async {
    if (_initialized) return;

    if (!hasActiveSupabase) {
      debugPrint('[SupabaseConfig] Missing active Supabase configuration.');
      return;
    }

    try {
      debugPrint('[SupabaseConfig] Initializing Supabase client ($url)...');
      await Supabase.initialize(
        url: url,
        anonKey: anonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
        realtimeClientOptions: const RealtimeClientOptions(
          logLevel: RealtimeLogLevel.info,
        ),
      );
      _initialized = true;
      debugPrint('[SupabaseConfig] Supabase successfully initialized.');
    } catch (e) {
      debugPrint('[SupabaseConfig] Supabase initialization failed: $e');
    }
  }

  static SupabaseClient get client => Supabase.instance.client;
}
