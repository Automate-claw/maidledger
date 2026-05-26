import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maidledger_localization/maidledger_localization.dart';

import 'core/services/supabase_client_provider.dart';
import 'features/auth/auth_provider.dart';
import 'features/auth/login_screen.dart';
import 'features/receipts/receipts_screen.dart';
import 'features/mycode/my_code_screen.dart';
import 'features/settings/settings_screen.dart';

/// Notification settings provider (stored locally) - Riverpod 3.x Notifier API
final notificationEnabledProvider = NotifierProvider<NotificationEnabledNotifier, bool>(() {
  return NotificationEnabledNotifier();
});

class NotificationEnabledNotifier extends Notifier<bool> {
  static const _key = 'notification_enabled';

  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? true;
  }

  Future<void> toggle() async {
    final prefs = await SharedPreferences.getInstance();
    state = !state;
    await prefs.setBool(_key, state);
    if (!state) {
      FlutterLocalNotificationsPlugin().cancelAll();
    }
  }
}

/// Global notification service
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  RealtimeChannel? _channel;

  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await FlutterLocalNotificationsPlugin().initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    final android = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  void _onNotificationTap(NotificationResponse response) {
    // TODO: Navigate to receipt detail if needed
  }

  /// Subscribe to Realtime channel for notifications
  void subscribe(String employerId, {required bool enabled}) {
    _channel?.unsubscribe();
    if (!enabled) return;

    final supabase = Supabase.instance.client;
    _channel = supabase.channel('notifications:$employerId');

    _channel!.onBroadcast(
      event: 'new_receipt',
      callback: (payload) {
        final data = payload['data'] as Map<String, dynamic>?;
        if (data == null) return;

        _showLocalNotification(
          id: data['id'].hashCode,
          title: data['title'] as String? ?? '📸 收到新收據',
          body: data['body'] as String? ?? '工人上傳了新收據',
        );
      },
    );

    _channel!.subscribe();
  }

  void _showLocalNotification({
    required int id,
    required String title,
    required String body,
  }) {
    const androidDetails = AndroidNotificationDetails(
      'receipt_notifications',
      '收據通知',
      channelDescription: '工人上傳收據時的通知',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    FlutterLocalNotificationsPlugin().show(id, title, body, details);
  }

  void unsubscribe() {
    _channel?.unsubscribe();
    _channel = null;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final supabaseUrl = prefs.getString('SUPABASE_URL') ?? '';
  final supabaseAnonKey = prefs.getString('SUPABASE_ANON_KEY') ?? '';

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  await NotificationService.instance.init();

  runApp(
    const ProviderScope(
      child: EmployerApp(),
    ),
  );
}

class EmployerApp extends ConsumerWidget {
  const EmployerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'MaidLedger',
      debugShowCheckedModeBanner: false,
      locale: appLocaleToFlutterLocale(appLocale),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4CAF50),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Noto Sans HK',
      ),
      home: const AuthGate(),
    );
  }
}

/// AuthGate checks if user is logged in
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _profileEnsured = false;
  bool _notificationsInitialized = false;

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authStateProvider);

    // Ensure profile exists once when session becomes available
    authAsync.when(
      data: (session) {
        if (session != null && !_profileEnsured) {
          _profileEnsured = true;
          ensureEmployerProfile(ref.read(supabaseClientProvider));
        }
        // Subscribe to notifications after profile is loaded
        if (session != null && !_notificationsInitialized) {
          _notificationsInitialized = true;
          final userId = session.user.id;
          final enabled = ref.read(notificationEnabledProvider);
          NotificationService.instance.subscribe(userId, enabled: enabled);
        }
        return const SizedBox();
      },
      loading: () => const SizedBox(),
      error: (_, __) => const SizedBox(),
    );

    return authAsync.when(
      data: (session) {
        if (session != null) {
          return const MainScreen();
        }
        return const LoginScreen();
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const LoginScreen(),
    );
  }
}

/// Main screen with bottom navigation
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);

    final _pages = const [
      ReceiptsScreen(),
      MyCodeScreen(),
      SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
            label: AppStrings.get(locale, 'history'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.qr_code_outlined),
            selectedIcon: const Icon(Icons.qr_code),
            label: 'My Code',
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
