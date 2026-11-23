import 'package:cmms/utils/app_date_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kTheme = 'ns_pref_theme';
const _kLanguage = 'ns_pref_language';
const _kDateFormat = 'ns_pref_date_format';

// ── Theme ──────────────────────────────────────────────────────────────────────

class ThemeModeNotifier extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final prefs = await SharedPreferences.getInstance();
    return _fromString(prefs.getString(_kTheme));
  }

  Future<void> setTheme(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTheme, value);
    state = AsyncData(_fromString(value));
  }

  static ThemeMode _fromString(String? v) {
    switch (v) {
      case 'Light':
        return ThemeMode.light;
      case 'Dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}

final themeModeProvider =
    AsyncNotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

// ── Locale ─────────────────────────────────────────────────────────────────────

class LocaleNotifier extends AsyncNotifier<Locale> {
  @override
  Future<Locale> build() async {
    final prefs = await SharedPreferences.getInstance();
    return _fromString(prefs.getString(_kLanguage));
  }

  Future<void> setLanguage(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLanguage, value);
    state = AsyncData(_fromString(value));
  }

  static Locale _fromString(String? v) =>
      v == 'Swahili' ? const Locale('sw') : const Locale('en');
}

final localeProvider =
    AsyncNotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

// ── Date format ────────────────────────────────────────────────────────────────

class DateFormatPrefNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kDateFormat) ?? 'DD/MM/YYYY';
    AppDateFormat.setPref(v);
    return v;
  }

  Future<void> setDateFormat(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDateFormat, value);
    AppDateFormat.setPref(value);
    state = AsyncData(value);
  }
}

final dateFormatPrefProvider =
    AsyncNotifierProvider<DateFormatPrefNotifier, String>(
        DateFormatPrefNotifier.new);
