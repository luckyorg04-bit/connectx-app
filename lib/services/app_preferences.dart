import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'database_service.dart';

class AppPreferences {
  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.system);
  static String languageCode = 'en';

  static DatabaseReference _settingsRef() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to change app preferences.');
    return ConnectXDatabase.instance.ref('PrivateUsers').child(uid).child('appSettings');
  }

  static Future<void> load() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    try {
      final snapshot = await _settingsRef().get();
      final value = snapshot.value is Map
          ? Map<String, dynamic>.from(snapshot.value as Map)
          : <String, dynamic>{};
      final theme = value['themeMode']?.toString() ?? 'system';
      themeMode.value = theme == 'light'
          ? ThemeMode.light
          : theme == 'dark'
              ? ThemeMode.dark
              : ThemeMode.system;
      languageCode = value['languageCode']?.toString() ?? 'en';
    } catch (error) {
      debugPrint('ConnectX preferences load failed: $error');
    }
  }

  static Future<void> saveTheme(ThemeMode mode) async {
    await _settingsRef().update({
      'themeMode': mode == ThemeMode.light
          ? 'light'
          : mode == ThemeMode.dark
              ? 'dark'
              : 'system',
    });
    themeMode.value = mode;
  }

  static Future<void> saveLanguage(String code) async {
    await _settingsRef().update({'languageCode': code});
    languageCode = code;
  }
}
