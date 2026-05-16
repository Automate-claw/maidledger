import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_client_provider.dart';
import '../auth/auth_provider.dart';

/// Supported locales
enum AppLocale {
  tradChinese('繁體中文', 'zh_HK'),
  english('English', 'en');

  final String label;
  final String code;
  const AppLocale(this.label, this.code);
}

/// Locale provider (persisted)
final localeProvider = NotifierProvider<LocaleNotifier, AppLocale>(() {
  return LocaleNotifier();
});

class LocaleNotifier extends Notifier<AppLocale> {
  @override
  AppLocale build() {
    _load();
    return AppLocale.tradChinese;
  }

  static const _key = 'app_locale';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key) ?? 'zh_HK';
    state = AppLocale.values.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLocale.tradChinese,
    );
  }

  Future<void> setLocale(AppLocale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale.code);
    state = locale;
  }
}

/// Settings screen with logout + language switch
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = supabase.auth.currentUser;
    final locale = ref.watch(localeProvider);

    // Fetch profile directly
    final profileAsync = ref.watch(_helperProfileProvider(user?.id ?? ''));

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        centerTitle: true,
      ),
      body: profileAsync.when(
        data: (profile) {
          final name = profile?['name'] ?? '工人';
          final phone = profile?['phone'];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Profile section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.blue,
                        child: Icon(Icons.person, color: Colors.white, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (phone != null)
                              Text(phone, style: const TextStyle(color: Colors.grey)),
                            const Text(
                              '工人',
                              style: TextStyle(color: Colors.blue, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Language section
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.language),
                      title: const Text('語言'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showLanguagePicker(context, ref),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 56, bottom: 8),
                      child: Text(
                        locale == AppLocale.tradChinese ? '繁體中文' : 'English',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Account section
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('版本'),
                      trailing: Text('1.0.0', style: TextStyle(color: Colors.grey)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text('登出', style: TextStyle(color: Colors.red)),
                      onTap: () => _confirmLogout(context, ref),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('錯誤：$err')),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('選擇語言'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: AppLocale.values.map((l) {
            final current = ref.read(localeProvider);
            return ListTile(
              title: Text(l.label),
              leading: Radio<AppLocale>(
                value: l,
                groupValue: current,
                onChanged: (value) {
                  if (value != null) {
                    ref.read(localeProvider.notifier).setLocale(value);
                    Navigator.pop(ctx);
                  }
                },
              ),
              onTap: () {
                ref.read(localeProvider.notifier).setLocale(l);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確定要登出嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authStateProvider.notifier).signOut();
            },
            child: const Text('登出'),
          ),
        ],
      ),
    );
  }
}

/// Helper profile provider family
final _helperProfileProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, userId) async {
  if (userId.isEmpty) return null;

  final profile = await supabase
      .from('user_profiles')
      .select()
      .eq('id', userId)
      .maybeSingle();

  return profile;
});