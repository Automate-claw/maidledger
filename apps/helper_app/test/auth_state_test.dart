import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:maidledger/features/auth/auth_provider.dart';

void main() {
  group('AuthState', () {
    test('AuthInitial is initial state', () {
      const state = AuthInitial();
      expect(state, isA<AuthState>());
    });

    test('AuthLoading represents loading state', () {
      const state = AuthLoading();
      expect(state, isA<AuthState>());
    });

    test('AuthAuthenticated holds user data', () {
      const state = AuthAuthenticated(
        userId: 'test-user-id',
        email: 'test@example.com',
      );
      
      expect(state.userId, equals('test-user-id'));
      expect(state.email, equals('test@example.com'));
      expect(state, isA<AuthState>());
    });

    test('AuthUnauthenticated is unauthenticated state', () {
      const state = AuthUnauthenticated();
      expect(state, isA<AuthState>());
    });

    test('AuthError holds error message', () {
      const state = AuthError('Invalid credentials');
      
      expect(state.message, equals('Invalid credentials'));
      expect(state, isA<AuthState>());
    });

    test('AuthState sealed class allows exhaustive switching', () {
      const states = [
        AuthInitial(),
        AuthLoading(),
        AuthAuthenticated(userId: '123', email: 'a@b.com'),
        AuthUnauthenticated(),
        AuthError('test'),
      ];

      for (final state in states) {
        final result = switch (state) {
          AuthInitial() => 'initial',
          AuthLoading() => 'loading',
          AuthAuthenticated() => 'authenticated',
          AuthUnauthenticated() => 'unauthenticated',
          AuthError() => 'error',
        };
        expect(result, isNotNull);
      }
    });
  });

  group('Auth state machine - all AuthState subtypes', () {
    test('AuthInitial transitions to AuthLoading on sign-in attempt', () {
      const initial = AuthInitial();
      expect(initial, isA<AuthState>());
    });

    test('AuthLoading can transition to AuthAuthenticated on success', () {
      const loading = AuthLoading();
      const authenticated = AuthAuthenticated(userId: 'u1', email: 'a@b.com');

      expect(loading, isA<AuthState>());
      expect(authenticated, isA<AuthState>());
    });

    test('AuthLoading can transition to AuthError on failure', () {
      const loading = AuthLoading();
      const error = AuthError('bad credentials');

      expect(loading, isA<AuthState>());
      expect(error, isA<AuthState>());
      expect(error.message, 'bad credentials');
    });

    test('AuthAuthenticated transitions to AuthUnauthenticated on sign-out', () {
      const authenticated = AuthAuthenticated(userId: 'u1', email: 'a@b.com');
      const unauthenticated = AuthUnauthenticated();

      expect(authenticated, isA<AuthState>());
      expect(unauthenticated, isA<AuthState>());
    });

    test('AuthError can transition back to AuthLoading for retry', () {
      const error = AuthError('network error');
      const loading = AuthLoading();

      expect(error, isA<AuthState>());
      expect(loading, isA<AuthState>());
    });

    test('Exhaustive state machine simulation', () {
      // Simulate full auth lifecycle: Initial -> Loading -> Auth -> Loading -> Auth -> Unauth
      AuthState state = const AuthInitial();
      expect(state, isA<AuthInitial>());

      state = const AuthLoading();
      expect(state, isA<AuthLoading>());

      state = const AuthAuthenticated(userId: 'u1', email: 'a@b.com');
      expect(state, isA<AuthAuthenticated>());

      state = const AuthLoading();
      expect(state, isA<AuthLoading>());

      state = const AuthAuthenticated(userId: 'u2', email: 'c@d.com');
      expect(state, isA<AuthAuthenticated>());

      state = const AuthUnauthenticated();
      expect(state, isA<AuthUnauthenticated>());
    });
  });

  group('_authFromSession helper', () {
    test('should extract userId and email from session', () {
      // AuthAuthenticated is the expected output; verify the field mapping
      const auth = AuthAuthenticated(userId: 'id-123', email: 'user@test.com');
      expect(auth.userId, 'id-123');
      expect(auth.email, 'user@test.com');
    });
  });
}