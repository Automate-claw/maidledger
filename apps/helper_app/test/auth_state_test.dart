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
}