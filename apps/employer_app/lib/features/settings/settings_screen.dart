import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/supabase_client_provider.dart';
import '../auth/auth_provider.dart';
import '../../main.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(employerProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        centerTitle: true,
      ),
      body: profileAsync.when(
        data: (profile) {
          final name = profile?['name'] ?? '僱主';
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
                            const Text(
                              '僱主',
                              style: TextStyle(
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
                title: '一般',
                children: [
                  _NotificationToggleItem(),
                  const _SettingsItem(
                    icon: Icons.language,
                    title: '語言',
                    subtitle: '繁體中文',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _SettingsSection(
                title: '關於',
                children: [
                  _SettingsItem(
                    icon: Icons.info_outline,
                    title: '版本',
                    subtitle: '1.0.0',
                  ),
                  _SettingsItem(
                    icon: Icons.description_outlined,
                    title: '使用條款',
                    subtitle: '查看使用條款和隱私政策',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Sign out
              FilledButton.tonal(
                onPressed: () => _signOut(context, ref),
                child: const Text('登出'),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('錯誤：$err')),
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確定要登出嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('登出'),
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
      title: const Text('通知設定'),
      subtitle: Text(enabled ? '接收工人上傳的收據通知' : '通知已關閉'),
      value: enabled,
      onChanged: (_) => ref.read(notificationEnabledProvider.notifier).toggle(),
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