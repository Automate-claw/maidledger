import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maidledger_localization/maidledger_localization.dart';
import 'core/services/supabase_client_provider.dart';
import 'features/auth/auth_provider.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/relation_gate.dart';
import 'features/scan/scan_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/history/history_screen.dart';
import 'features/settings/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await initSupabase();
  } catch (e) {
    debugPrint('Supabase init failed: $e');
    // Continue anyway - auth will handle the error state
  }
  
  runApp(
    const ProviderScope(
      child: MaidLedgerApp(),
    ),
  );
}

class MaidLedgerApp extends ConsumerWidget {
  const MaidLedgerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'MaidLedger',
      debugShowCheckedModeBanner: false,
      locale: appLocaleToFlutterLocale(appLocale),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

/// Routes based on auth state
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _profileEnsured = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    // Ensure profile exists when session becomes available
    if (authState is AuthAuthenticated && !_profileEnsured) {
      _profileEnsured = true;
      ensureHelperProfile();
    }

    return switch (authState) {
      AuthAuthenticated() => const RelationGate(
          child: MainNavigationScreen(),
        ),
      AuthLoading() => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      AuthInitial() => const LoginScreen(),
      AuthUnauthenticated() => const LoginScreen(),
      AuthError() => const LoginScreen(),
    };
  }
}

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);

    final _screens = const [
      ScanScreen(),
      ChatScreen(),
      HistoryScreen(),
      SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.camera_alt_outlined),
            selectedIcon: const Icon(Icons.camera_alt),
            label: AppStrings.scan(locale),
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: AppStrings.chat(locale),
          ),
          NavigationDestination(
            icon: const Icon(Icons.history_outlined),
            selectedIcon: const Icon(Icons.history),
            label: AppStrings.history(locale),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: AppStrings.settings(locale),
          ),
        ],
      ),
    );
  }
}