import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:maidledger_localization/maidledger_localization.dart';
import '../../core/services/supabase_client_provider.dart';
import '../auth/auth_provider.dart';

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
        title: Text(AppStrings.settings(locale)),
        centerTitle: true,
      ),
      body: profileAsync.when(
        data: (profile) {
          final name = profile?['name'] ?? AppStrings.get(locale, 'worker');
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
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.blue,
                        child: const Icon(Icons.person, color: Colors.white, size: 32),
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
                            Text(
                              AppStrings.get(locale, 'worker'),
                              style: const TextStyle(color: Colors.blue, fontSize: 12),
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
                      title: Text(AppStrings.language(locale)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showLanguagePicker(context, ref),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 56, bottom: 8),
                      child: Text(
                        '${locale.flag} ${locale.label}',
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
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(AppStrings.version(locale)),
                      trailing: const Text('1.0.0', style: TextStyle(color: Colors.grey)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: Text(
                        AppStrings.logout(locale),
                        style: const TextStyle(color: Colors.red),
                      ),
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
        title: Text(AppStrings.selectLanguage(ref.read(localeProvider))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: AppLocale.values.map((l) {
            final current = ref.read(localeProvider);
            return ListTile(
              title: Text('${l.flag}  ${l.label}'),
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
    final locale = ref.read(localeProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${AppStrings.logout(locale)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.cancel(locale)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authStateProvider.notifier).signOut();
            },
            child: Text(AppStrings.confirm(locale)),
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