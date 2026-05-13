import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Initialize Supabase with custom storage
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: 'https://hnyazfrkzpxdjiyfzemm.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhueWF6ZnJrenB4ZGppeWZ6ZW1tIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg2NTUwMjcsImV4cCI6MjA5NDIzMTAyN30.lo2HAv0E9WK1CRHTtU3idlrq3xNogdUAbWfpXvz90J0',
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: true,
    ),
  );
}

/// Supabase client getter
SupabaseClient get supabase => Supabase.instance.client;