import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:maidledger_localization/maidledger_localization.dart';
import '../../core/services/supabase_client_provider.dart';
import '../../core/services/relation_service.dart';
import '../auth/auth_provider.dart';
import '../auth/relation_gate.dart';

/// Settings screen with logout + language switch + employer link + default district
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = supabase.auth.currentUser;
    final locale = ref.watch(localeProvider);

    // Fetch profile directly
    final profileAsync = ref.watch(_helperProfileProvider(user?.id ?? ''));
    final relationAsync = ref.watch(relationStatusProvider);

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

              // Employer link section
              relationAsync.when(
                data: (status) => _EmployerLinkCard(
                  status: status,
                  locale: locale,
                  onLinked: () => ref.invalidate(relationStatusProvider),
                ),
                loading: () => const Card(
                  child: ListTile(
                    leading: Icon(Icons.link),
                    title: Text('载入中...'),
                  ),
                ),
                error: (_, __) => const SizedBox(),
              ),

              const SizedBox(height: 16),

              // Default district section
              Card(
                child: ListTile(
                  leading: const Icon(Icons.location_on),
                  title: Text(AppStrings.defaultLocation(locale)),
                  subtitle: Text(
                    profile?['default_location'] ?? AppStrings.notSet(locale),
                    style: TextStyle(
                      color: profile?['default_location'] != null ? Colors.green : Colors.grey,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showDistrictPicker(context, ref, profile),
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
    final currentLocale = ref.read(localeProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.selectLanguage(currentLocale)),
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

  void _showDistrictPicker(BuildContext context, WidgetRef ref, Map<String, dynamic>? profile) {
    final locale = ref.read(localeProvider);
    final districts = [
      '港島｜灣仔',
      '港島｜北角',
      '港島｜中環',
      '港島｜西營盤',
      '九龍｜旺角',
      '九龍｜深水埗',
      '九龍｜九龍城',
      '九龍｜黃大仙',
      '新界｜粉嶺',
      '新界｜大埔',
      '新界｜沙田',
      '新界｜屯門',
      '其他',
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.defaultLocation(locale)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: districts.length,
            itemBuilder: (_, idx) {
              final d = districts[idx];
              final current = profile?['default_location'] ?? '';
              return ListTile(
                title: Text(d),
                leading: Radio<String>(
                  value: d,
                  groupValue: current.isEmpty ? null : current,
                  onChanged: (v) {
                    if (v != null) _saveDefaultLocation(ctx, ref, profile?['id'], v);
                  },
                ),
                onTap: () => _saveDefaultLocation(ctx, ref, profile?['id'], d),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.cancel(locale)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveDefaultLocation(BuildContext ctx, WidgetRef ref, String? profileId, String district) async {
    if (profileId == null) return;
    await supabase.from('user_profiles').update({'default_location': district}).eq('id', profileId);
    ref.invalidate(_helperProfileProvider(profileId));
    if (ctx.mounted) Navigator.pop(ctx);
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

class _EmployerLinkCard extends ConsumerWidget {
  final RelationStatus status;
  final AppLocale locale;
  final VoidCallback onLinked;

  const _EmployerLinkCard({
    required this.status,
    required this.locale,
    required this.onLinked,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (status.hasActiveRelation && status.relations.isNotEmpty) {
      final relation = status.relations.first;
      final employer = relation['employer'];
      final employerName = employer is Map ? employer['name'] ?? '僱主' : '僱主';
      final employerId = relation['employer_id'] as String;

      return Card(
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: Colors.green,
            child: Icon(Icons.people, color: Colors.white),
          ),
          title: Text(AppStrings.get(locale, 'employer')),
          subtitle: Text(employerName),
          trailing: TextButton(
            onPressed: () => _confirmDisconnect(context, ref, employerId),
            child: Text(
              AppStrings.disconnectEmployer(locale),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      );
    }

    // Not linked — show link button
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.grey,
          child: Icon(Icons.link_off, color: Colors.white),
        ),
        title: Text(AppStrings.linkEmployer(locale)),
        subtitle: Text(AppStrings.noRelationHint(locale)),
        trailing: FilledButton(
          onPressed: () => _showLinkDialog(context, ref),
          child: Text(AppStrings.linkEmployer(locale)),
        ),
      ),
    );
  }

  void _showLinkDialog(BuildContext context, WidgetRef ref) {
    final codeCtrl = TextEditingController();
    final codeKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.linkEmployer(locale)),
        content: Form(
          key: codeKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(AppStrings.employerCodeHint(locale)),
              const SizedBox(height: 16),
              TextFormField(
                controller: codeCtrl,
                decoration: InputDecoration(
                  labelText: AppStrings.inviteCode(locale),
                  hintText: '例如 DEMO01',
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.cancel(locale)),
          ),
          FilledButton(
            onPressed: () async {
              if (!codeKey.currentState!.validate()) return;
              final user = supabase.auth.currentUser;
              if (user == null) return;

              final service = RelationService(supabase);
              final result = await service.linkToEmployer(
                helperId: user.id,
                employerCode: codeCtrl.text.trim(),
              );

              if (ctx.mounted) Navigator.pop(ctx);

              if (result.success) {
                onLinked();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ 已連接到 ${result.employerName ?? "僱主"}'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ ${result.error}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: Text(AppStrings.confirm(locale)),
          ),
        ],
      ),
    );
  }

  void _confirmDisconnect(BuildContext context, WidgetRef ref, String employerId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.disconnectEmployer(locale)),
        content: Text(AppStrings.disconnectConfirm(locale)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.cancel(locale)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final user = supabase.auth.currentUser;
              if (user == null) return;

              final service = RelationService(supabase);
              final result = await service.endRelation(
                helperId: user.id,
                employerId: employerId,
              );

              if (result.success) {
                onLinked();
              }
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