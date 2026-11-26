import 'package:flutter/material.dart';
import 'services/app_preferences.dart';
import 'services/database_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _messages = true;
  bool _groups = true;
  bool _calls = true;
  bool _loading = true;
  String _language = 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final results = await Future.wait([
        ConnectXDatabase.instance.ref('PrivateUsers').child(uid)
            .child('notificationSettings').get(),
        ConnectXDatabase.instance.ref('PrivateUsers').child(uid)
            .child('appSettings').get(),
      ]);
      final notifications = results[0].value is Map
          ? Map<String, dynamic>.from(results[0].value as Map)
          : <String, dynamic>{};
      final preferences = results[1].value is Map
          ? Map<String, dynamic>.from(results[1].value as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _messages = notifications['messages'] != false;
        _groups = notifications['groups'] != false;
        _calls = notifications['calls'] != false;
        _language = preferences['languageCode']?.toString() ?? 'en';
        _loading = false;
      });
    } catch (error) {
      debugPrint('ConnectX settings load failed: $error');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveNotifications() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await ConnectXDatabase.instance.ref('PrivateUsers').child(uid)
        .child('notificationSettings').set({
      'messages': _messages,
      'groups': _groups,
      'calls': _calls,
    });
  }

  Future<void> _changeTheme(ThemeMode mode) async {
    try {
      await AppPreferences.saveTheme(mode);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _showError('Theme preference could not be saved.');
    }
  }

  Future<void> _changeLanguage(String? code) async {
    if (code == null) return;
    try {
      await AppPreferences.saveLanguage(code);
      if (mounted) setState(() => _language = code);
      // Language selection is persisted; full translation coverage is being
      // rolled out separately so untranslated screens remain readable.
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Language preference saved.')),
      );
    } catch (error) {
      if (mounted) _showError('Language preference could not be saved.');
    }
  }

  void _showError(String message) {
    showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Unable to save settings'),
      content: Text(message),
      actions: [FilledButton(onPressed: () => Navigator.pop(dialogContext),
        child: const Text('OK'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentTheme = AppPreferences.themeMode.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _section('DISPLAY'),
                Card(child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('Theme'),
                    subtitle: const Text('Choose light, dark or follow device settings'),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.light,
                    groupValue: currentTheme,
                    title: const Text('Light'),
                    onChanged: (value) => _changeTheme(value!),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.dark,
                    groupValue: currentTheme,
                    title: const Text('Dark'),
                    onChanged: (value) => _changeTheme(value!),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.system,
                    groupValue: currentTheme,
                    title: const Text('System default'),
                    onChanged: (value) => _changeTheme(value!),
                  ),
                ])),
                const SizedBox(height: 20),
                _section('LANGUAGE'),
                Card(child: ListTile(
                  leading: const Icon(Icons.language_rounded),
                  title: const Text('Preferred language'),
                  subtitle: const Text('Language preference is saved to your account'),
                  trailing: DropdownButton<String>(
                    value: _language,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'en', child: Text('English')),
                      DropdownMenuItem(value: 'hi', child: Text('हिन्दी')),
                    ],
                    onChanged: _changeLanguage,
                  ),
                )),
                const SizedBox(height: 20),
                _section('NOTIFICATIONS'),
                Card(child: Column(children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.chat_bubble_outline),
                    title: const Text('Direct messages'),
                    value: _messages,
                    onChanged: (value) async {
                      setState(() => _messages = value);
                      try { await _saveNotifications(); }
                      catch (_) { if (mounted) _showError('Notification settings could not be saved.'); }
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.groups_outlined),
                    title: const Text('Group messages'),
                    value: _groups,
                    onChanged: (value) async {
                      setState(() => _groups = value);
                      try { await _saveNotifications(); }
                      catch (_) { if (mounted) _showError('Notification settings could not be saved.'); }
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.call_outlined),
                    title: const Text('Voice and video calls'),
                    value: _calls,
                    onChanged: (value) async {
                      setState(() => _calls = value);
                      try { await _saveNotifications(); }
                      catch (_) { if (mounted) _showError('Notification settings could not be saved.'); }
                    },
                  ),
                ])),
                const SizedBox(height: 20),
                _section('ACCOUNT'),
                Card(child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('Profile'),
                    subtitle: const Text('Name, photo and account details'),
                    onTap: () => Navigator.pop(context),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.qr_code_2),
                    title: const Text('QR code'),
                    onTap: () => Navigator.pushNamed(context, '/my-qr'),
                  ),
                ])),
                const SizedBox(height: 18),
                Text('ConnectX settings', textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
    );
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
    child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(
      letterSpacing: 1.2, fontWeight: FontWeight.w800,
      color: Theme.of(context).colorScheme.primary)),
  );
}
