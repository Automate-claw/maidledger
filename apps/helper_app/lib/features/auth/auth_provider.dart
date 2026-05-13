import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart';
import '../../core/services/supabase_client_provider.dart';

/// Auth state using sealed class pattern for exhaustive switching
sealed class AuthState {
  const AuthState();
}

/// Initial state
class AuthInitial extends AuthState {
  const AuthInitial();
}

/// Loading state
class AuthLoading extends AuthState {
  const AuthLoading();
}

/// Authenticated state
class AuthAuthenticated extends AuthState {
  final String userId;
  final String email;
  const AuthAuthenticated({required this.userId, required this.email});
}

/// Unauthenticated state
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// Error state
class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
}

/// Auth notifier using Riverpod 2.x Notifier
class AuthNotifier extends Notifier<AuthState> {
  SupabaseClient? _client;

  @override
  AuthState build() {
    _init();
    return const AuthLoading();
  }

  Future<void> _init() async {
    _client = await SupabaseClientProvider.instance;
    
    // Listen to auth state changes
    _client!.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.signedIn && session != null) {
        state = AuthAuthenticated(
          userId: session.user.id,
          email: session.user.email ?? '',
        );
      } else if (event == AuthChangeEvent.signedOut) {
        state = const AuthUnauthenticated();
      }
    });

    // Check current session
    final currentSession = _client!.auth.currentSession;
    if (currentSession != null) {
      state = AuthAuthenticated(
        userId: currentSession.user.id,
        email: currentSession.user.email ?? '',
      );
    } else {
      state = const AuthUnauthenticated();
    }
  }

  Future<void> signIn(String email, String password) async {
    if (_client == null) {
      state = const AuthError('Client not initialized');
      return;
    }
    
    state = const AuthLoading();

    try {
      final response = await _client!.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        state = AuthAuthenticated(
          userId: response.user!.id,
          email: response.user!.email ?? '',
        );
      } else {
        state = const AuthError('Sign in failed');
      }
    } on AuthException catch (e) {
      state = AuthError(e.message);
    } catch (e) {
      state = AuthError(e.toString());
    }
  }

  Future<void> signUp(String email, String password, String name, String role) async {
    if (_client == null) {
      state = const AuthError('Client not initialized');
      return;
    }
    
    state = const AuthLoading();

    try {
      final response = await _client!.auth.signUp(
        email: email,
        password: password,
        data: {'name': name, 'role': role},
      );

      if (response.user != null) {
        // Create user profile
        await _client!.from('user_profiles').insert({
          'id': response.user!.id,
          'name': name,
          'role': role,
        });

        state = AuthAuthenticated(
          userId: response.user!.id,
          email: response.user!.email ?? '',
        );
      } else {
        state = const AuthError('Sign up failed');
      }
    } on AuthException catch (e) {
      state = AuthError(e.message);
    } catch (e) {
      state = AuthError(e.toString());
    }
  }

  Future<void> signOut() async {
    if (_client == null) return;
    await _client!.auth.signOut();
    state = const AuthUnauthenticated();
  }
}

/// Auth state provider
final authStateProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});