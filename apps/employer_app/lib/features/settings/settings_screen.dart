import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maidledger_localization/maidledger_localization.dart';
import '../auth/auth_provider.dart';
import '../../main.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(employerProfileProvider);
    final locale = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.settings(locale)),
        centerTitle: true,
      ),
      body: profileAsync.when(
        data: (profile) {
          final name = profile?['name'] ?? AppStrings.get(locale, 'employer');
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
                        backgroundColor: Colors.green,
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
                              Text(
                                phone,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            Text(
                              AppStrings.get(locale, 'employer'),
                              style: const TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Settings items
              _SettingsSection(
                title: 'General',
                children: [
                  _NotificationToggleItem(),
                  _LanguageSettingsItem(),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                title: 'About',
                children: [
                  _SettingsItem(
                    icon: Icons.info_outline,
                    title: AppStrings.version(locale),
                    subtitle: '1.0.0',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Sign out
              FilledButton.tonal(
                onPressed: () => _signOut(context, ref),
                child: Text(AppStrings.logout(locale)),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final locale = ref.read(localeProvider);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${AppStrings.logout(locale)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.cancel(locale)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.confirm(locale)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final supabase = ref.read(supabaseClientProvider);
      await supabase.auth.signOut();
    }
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ),
        Card(
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _NotificationToggleItem extends ConsumerWidget {
  const _NotificationToggleItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(notificationEnabledProvider);

    return SwitchListTile(
      secondary: Icon(
        enabled ? Icons.notifications : Icons.notifications_off_outlined,
        color: Colors.grey,
      ),
      title: const Text('Notifications'),
      subtitle: Text(enabled ? 'Receive helper receipt uploads' : 'Notifications off'),
      value: enabled,
      onChanged: (_) => ref.read(notificationEnabledProvider.notifier).toggle(),
    );
  }
}

class _LanguageSettingsItem extends ConsumerWidget {
  const _LanguageSettingsItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    return ListTile(
      leading: const Icon(Icons.language, color: Colors.grey),
      title: Text(AppStrings.language(locale)),
      subtitle: Text('${locale.flag} ${locale.label}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showLanguagePicker(context, ref),
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
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}