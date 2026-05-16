import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_client_provider.dart';

// ---------------------------------------------------------------------------
// Timeout configuration for auth operations
// ---------------------------------------------------------------------------
const _oauthTimeout = Duration(seconds: 30);
const _passwordTimeout = Duration(seconds: 15);

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

/// Runs [action] with a shared timeout timer.
Future<bool> _runWithTimeout({
  required Duration timeout,
  required void Function(AuthState) setState,
  required Future<void> Function() action,
  required String timeoutMessage,
}) async {
  Timer? timer;
  bool timedOut = false;

  timer = Timer(timeout, () {
    timedOut = true;
    setState(AuthError(timeoutMessage));
  });

  try {
    await action();
    return true;
  } on AuthException catch (e) {
    if (!timedOut) setState(AuthError(e.message));
    return false;
  } catch (e) {
    if (!timedOut) setState(AuthError('Operation failed: $e'));
    return false;
  } finally {
    timer?.cancel();
  }
}

/// Ensure helper profile exists in user_profiles (call after OAuth sign-in)
Future<void> ensureHelperProfile() async {
  final user = supabase.auth.currentUser;
  if (user == null) return;

  final existing = await supabase
      .from('user_profiles')
      .select('id')
      .eq('id', user.id)
      .maybeSingle();

  if (existing != null) return;

  final role = user.userMetadata?['role'] as String? ?? 'helper';
  final name = user.userMetadata?['name'] as String? ??
                user.userMetadata?['full_name'] as String? ??
                user.email ?? '工人';

  await supabase.from('user_profiles').insert({
    'id': user.id,
    'role': role,
    'name': name,
  });
}

/// Builds a new authenticated state from a session.
AuthState _authFromSession(Session session) => AuthAuthenticated(
      userId: session.user.id,
      email: session.user.email ?? '',
    );

/// Auth notifier using Riverpod 2.x Notifier
class AuthNotifier extends Notifier<AuthState> {
  StreamSubscription? _authSubscription;

  @override
  AuthState build() {
    _authSubscription?.cancel();
    
    // Check current session synchronously
    AuthState initialState;
    try {
      final currentSession = supabase.auth.currentSession;
      if (currentSession != null) {
        initialState = _authFromSession(currentSession);
      } else {
        initialState = const AuthUnauthenticated();
      }
    } catch (e) {
      initialState = const AuthUnauthenticated();
    }
    
    // Set initial state then listen for changes
    state = initialState;

    // Ensure profile exists if we have an existing session
    if (initialState is AuthAuthenticated) {
      ensureHelperProfile();
    }

    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.signedIn && session != null) {
        state = _authFromSession(session);
      } else if (event == AuthChangeEvent.signedOut) {
        state = const AuthUnauthenticated();
      } else if (event == AuthChangeEvent.tokenRefreshed && session != null) {
        state = _authFromSession(session);
      }
    }, onError: (error) {
      state = const AuthUnauthenticated();
    });

    // Return the actual initial state, not AuthLoading
    return initialState;
  }

  Future<void> signIn(String email, String password) async {
    state = const AuthLoading();

    await _runWithTimeout(
      timeout: _passwordTimeout,
      setState: (s) => state = s,
      timeoutMessage: 'Sign in timed out. Please try again.',
      action: () async {
        final response = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
        if (response.user == null) {
          state = const AuthError('Sign in failed - no user returned');
        }
      },
    );
  }

  Future<void> signUp(String email, String password, String name, String role) async {
    state = const AuthLoading();

    await _runWithTimeout(
      timeout: _passwordTimeout,
      setState: (s) => state = s,
      timeoutMessage: 'Sign up timed out. Please try again.',
      action: () async {
        final response = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {'name': name, 'role': role},
        );
        if (response.user != null) {
          try {
            await supabase.auth.signInWithPassword(
              email: email,
              password: password,
            );
          } catch (e) {
            state = AuthError('Sign up succeeded but auto-signin failed: $e');
          }
        } else {
          state = const AuthError('Sign up failed - no user returned');
        }
      },
    );
  }

  Future<void> signInWithGoogle() async {
    state = const AuthLoading();

    await _runWithTimeout(
      timeout: _oauthTimeout,
      setState: (s) => state = s,
      timeoutMessage: 'Google sign in timed out. Please try again.',
      action: () => supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'com.wandvault.maidledger://login-callback',
      ).then((_) => ensureHelperProfile()),
    );
  }

  Future<void> signInWithApple() async {
    state = const AuthLoading();

    await _runWithTimeout(
      timeout: _oauthTimeout,
      setState: (s) => state = s,
      timeoutMessage: 'Apple sign in timed out. Please try again.',
      action: () => supabase.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: 'com.wandvault.maidledger://login-callback',
      ).then((_) => ensureHelperProfile()),
    );
  }

  Future<void> signOut() async {
    try {
      await supabase.auth.signOut();
    } catch (_) {
      // Ignore sign out errors
    }
    state = const AuthUnauthenticated();
  }
}

/// Auth state provider
final authStateProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});