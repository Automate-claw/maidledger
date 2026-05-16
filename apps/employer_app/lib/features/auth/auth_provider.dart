import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_client_provider.dart';

/// Auth state provider - maps AuthState to Session?
final authStateProvider = StreamProvider<Session?>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return supabase.auth.onAuthStateChange.map((event) => event.session);
});

/// Current user provider
final currentUserProvider = Provider<User?>((ref) {
  final asyncSession = ref.watch(authStateProvider);
  return asyncSession.whenOrNull(data: (session) => session?.user);
});

/// Generate a simple 6-char alphanumeric code
String _generateShortCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final seed = DateTime.now().millisecondsSinceEpoch;
  return List.generate(6, (i) => chars[(seed ~/ (i + 1) + i * 7) % chars.length]).join();
}

/// Ensure employer profile exists (call after OAuth sign-in to fix missing profiles)
Future<void> ensureEmployerProfile(SupabaseClient supabase) async {
  final user = supabase.auth.currentUser;
  if (user == null) return;

  final existing = await supabase
      .from('user_profiles')
      .select('id')
      .eq('id', user.id)
      .maybeSingle();

  if (existing != null) return;

  // Create profile with role from metadata or default to 'employer'
  final role = user.userMetadata?['role'] as String? ?? 'employer';
  final name = user.userMetadata?['name'] as String? ??
                user.userMetadata?['full_name'] as String? ??
                user.email ?? '僱主';

  await supabase.from('user_profiles').insert({
    'id': user.id,
    'role': role,
    'name': name,
    'short_code': _generateShortCode(),
  });
}

/// Employer profile provider
final employerProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  final supabase = ref.read(supabaseClientProvider);
  final profile = await supabase
      .from('user_profiles')
      .select()
      .eq('id', user.id)
      .maybeSingle();

  return profile;
});