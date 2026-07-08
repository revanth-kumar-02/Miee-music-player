import 'package:supabase_flutter/supabase_flutter.dart';

/// Configuration keys for Supabase cloud sync integration.
abstract class SupabaseConfig {
  static const String url = 'https://your-project.supabase.co';
  static const String anonKey = 'your-anon-key';

  /// Helper to determine if a real Supabase configuration is loaded.
  static bool get hasActiveSupabase {
    return url.startsWith('http') && 
           url != 'https://your-project.supabase.co' && 
           anonKey.isNotEmpty && 
           anonKey != 'your-anon-key';
  }
}
