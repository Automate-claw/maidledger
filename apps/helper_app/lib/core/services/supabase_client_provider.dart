import 'package:supabase/supabase.dart';

/// Supabase client singleton for MaidLedger
/// Initialized with anon key for client-side operations
class SupabaseClientProvider {
  static SupabaseClient? _instance;

  static SupabaseClient get instance {
    _instance ??= _createClient();
    return _instance!;
  }

  static SupabaseClient _createClient() {
    const url = 'https://hnyazfrkzpxdjiyfzemm.supabase.co';
    const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhueWF6ZnJrenB4ZGppeWZ6ZW1tIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg2NTUwMjcsImV4cCI6MjA5NDIzMTAyN30.lo2HAv0E9WK1CRHTtU3idlrq3xNogdUAbWfpXvz90J0';

    return SupabaseClient(url, anonKey);
  }

  /// For testing / injection
  static void setInstance(SupabaseClient client) {
    _instance = client;
  }

  static void reset() {
    _instance = null;
  }
}