import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supported locales
enum AppLocale {
  tradChinese('繁體中文', 'zh_HK', '🇭🇰'),
  english('English', 'en', '🇬🇧'),
  indonesian('Bahasa Indonesia', 'id', '🇮🇩'),
  filipino('Filipino', 'fil', '🇵🇭');

  final String label;
  final String code;
  final String flag;
  const AppLocale(this.label, this.code, this.flag);
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

/// Flutter Locale from AppLocale
Locale appLocaleToFlutterLocale(AppLocale appLocale) {
  switch (appLocale) {
    case AppLocale.tradChinese:
      return const Locale('zh', 'HK');
    case AppLocale.english:
      return const Locale('en');
    case AppLocale.indonesian:
      return const Locale('id');
    case AppLocale.filipino:
      return const Locale('fil');
  }
}