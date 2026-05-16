import 'package:flutter_dotenv/flutter_dotenv.dart';
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
  await dotenv.load(fileName: '.env');

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null || supabaseAnonKey == null) {
    throw Exception('Missing SUPABASE_URL or SUPABASE_ANON_KEY in .env file');
  }

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: true,
    ),
  );
}

/// Supabase client getter
SupabaseClient get supabase => Supabase.instance.client;