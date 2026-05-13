import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  StreamSubscription? _authSubscription;
  Timer? _authTimeout;

  @override
  AuthState build() {
    // Clean up any existing subscription when build is called
    _authSubscription?.cancel();
    
    _initAuthListener();
    return const AuthLoading();
  }

  void _initAuthListener() {
    // Get current session
    try {
      final currentSession = supabase.auth.currentSession;
      if (currentSession != null) {
        state = AuthAuthenticated(
          userId: currentSession.user.id,
          email: currentSession.user.email ?? '',
        );
      } else {
        state = const AuthUnauthenticated();
      }
    } catch (e) {
      state = const AuthUnauthenticated();
    }

    // Listen to auth state changes
    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      // Cancel any pending timeout
      _authTimeout?.cancel();

      if (event == AuthChangeEvent.signedIn && session != null) {
        state = AuthAuthenticated(
          userId: session.user.id,
          email: session.user.email ?? '',
        );
      } else if (event == AuthChangeEvent.signedOut) {
        state = const AuthUnauthenticated();
      } else if (event == AuthChangeEvent.tokenRefreshed && session != null) {
        // Token refreshed - stay in current state
        state = AuthAuthenticated(
          userId: session.user.id,
          email: session.user.email ?? '',
        );
      }
    }, onError: (error) {
      // Handle stream errors gracefully
      state = const AuthUnauthenticated();
    });
  }

  Future<void> signIn(String email, String password) async {
    state = const AuthLoading();

    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        state = AuthAuthenticated(
          userId: response.user!.id,
          email: response.user!.email ?? '',
        );
      } else {
        state = const AuthError('Sign in failed - no user returned');
      }
    } on AuthException catch (e) {
      state = AuthError(e.message);
    } catch (e) {
      state = AuthError('Sign in failed: $e');
    }
  }

  Future<void> signUp(String email, String password, String name, String role) async {
    state = const AuthLoading();

    try {
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {'name': name, 'role': role},
      );

      if (response.user != null) {
        // Sign in immediately after sign up to establish session
        await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );

        state = AuthAuthenticated(
          userId: response.user!.id,
          email: response.user!.email ?? '',
        );
      } else {
        state = const AuthError('Sign up failed - no user returned');
      }
    } on AuthException catch (e) {
      state = AuthError(e.message);
    } catch (e) {
      state = AuthError('Sign up failed: $e');
    }
  }

  Future<void> signInWithGoogle() async {
    state = const AuthLoading();

    // Set a timeout to handle OAuth redirect issues
    _authTimeout = Timer(const Duration(seconds: 30), () {
      if (state is AuthLoading) {
        state = const AuthError('Google sign in timed out. Please try again.');
      }
    });

    try {
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'com.example.maidledger://login-callback',
      );
      // Note: OAuth flow is asynchronous - the callback will update state
    } on AuthException catch (e) {
      _authTimeout?.cancel();
      state = AuthError(e.message);
    } catch (e) {
      _authTimeout?.cancel();
      state = AuthError('Google sign in failed: $e');
    }
  }

  Future<void> signInWithApple() async {
    state = const AuthLoading();

    // Set a timeout to handle OAuth redirect issues
    _authTimeout = Timer(const Duration(seconds: 30), () {
      if (state is AuthLoading) {
        state = const AuthError('Apple sign in timed out. Please try again.');
      }
    });

    try {
      await supabase.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: 'com.example.maidledger://login-callback',
      );
    } on AuthException catch (e) {
      _authTimeout?.cancel();
      state = AuthError(e.message);
    } catch (e) {
      _authTimeout?.cancel();
      state = AuthError('Apple sign in failed: $e');
    }
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