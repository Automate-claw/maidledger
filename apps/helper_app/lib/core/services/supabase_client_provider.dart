import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase/supabase.dart';

/// SharedPreferences-based async storage for Supabase auth
class SharedPreferencesGotrueStorage extends GotrueAsyncStorage {
  final SharedPreferences _prefs;

  SharedPreferencesGotrueStorage(this._prefs);

  @override
  Future<String?> getItem({required String key}) async {
    return _prefs.getString(key);
  }

  @override
  Future<void> setItem({
    required String key,
    required String value,
  }) async {
    await _prefs.setString(key, value);
  }

  @override
  Future<void> removeItem({required String key}) async {
    await _prefs.remove(key);
  }
}

/// Supabase client singleton for MaidLedger
class SupabaseClientProvider {
  static SupabaseClient? _instance;
  static SharedPreferences? _prefs;

  static Future<SupabaseClient> get instance async {
    _instance ??= await _createClient();
    return _instance!;
  }

  static Future<SupabaseClient> _createClient() async {
    const url = 'https://hnyazfrkzpxdjiyfzemm.supabase.co';
    const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhueWF6ZnJrenB4ZGppeWZ6ZW1tIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg2NTUwMjcsImV4cCI6MjA5NDIzMTAyN30.lo2HAv0E9WK1CRHTtU3idlrq3xNogdUAbWfpXvz90J0';

    _prefs ??= await SharedPreferences.getInstance();
    final storage = SharedPreferencesGotrueStorage(_prefs!);

    return SupabaseClient(
      url,
      anonKey,
      authOptions: AuthClientOptions(
        pkceAsyncStorage: storage,
        autoRefreshToken: true,
      ),
    );
  }

  /// For testing / injection
  static void setInstance(SupabaseClient client) {
    _instance = client;
  }

  static void reset() {
    _instance = null;
    _prefs = null;
  }
}