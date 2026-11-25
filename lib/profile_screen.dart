import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'services/database_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return 'C';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final userRef = ConnectXDatabase.instance.ref('PublicUsers').child(user.uid);
    return StreamBuilder<DatabaseEvent>(
      stream: userRef.onValue,
      builder: (context, snapshot) {
        final data = snapshot.data?.snapshot;
        final name = data?.child('name').value?.toString() ?? user.displayName ?? 'ConnectX User';
        final username = data?.child('username').value?.toString() ?? '';
        final bio = data?.child('bio').value?.toString() ?? data?.child('about').value?.toString() ?? '';
        final photoUrl = data?.child('photoUrl').value?.toString() ?? user.photoURL ?? '';
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 36),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [colors.primary, Color.lerp(colors.primary, colors.tertiary, .45)!],
                ),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: colors.onPrimary.withOpacity(.16),
                  backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                  child: photoUrl.isEmpty
                      ? Text(_initials(name), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: colors.onPrimary))
                      : null,
                ),
                const SizedBox(height: 16),
                Text(name, textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(color: colors.onPrimary, fontWeight: FontWeight.w800)),
                if (username.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text('@$username', style: theme.textTheme.bodyMedium?.copyWith(color: colors.onPrimary.withOpacity(.82))),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: colors.onPrimary.withOpacity(.14), borderRadius: BorderRadius.circular(30)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.verified_user_outlined, size: 15, color: colors.onPrimary),
                    const SizedBox(width: 7),
                    Text('ConnectX account', style: theme.textTheme.labelMedium?.copyWith(color: colors.onPrimary, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pushNamed('/my-qr'),
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text('My QR code'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).pushNamed('/scan-qr'),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Scan QR'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Text('ACCOUNT DETAILS', style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant, letterSpacing: 1.1, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            _ProfileInfoTile(icon: Icons.person_outline_rounded, title: 'Full name', value: name),
            _ProfileInfoTile(icon: Icons.alternate_email_rounded, title: 'Username', value: username.isEmpty ? 'Not set' : '@$username'),
            _ProfileInfoTile(icon: Icons.info_outline_rounded, title: 'About', value: bio.isEmpty ? 'No bio added yet' : bio),
            _ProfileInfoTile(icon: Icons.mail_outline_rounded, title: 'Email address', value: user.email ?? 'Not available'),
            const SizedBox(height: 12),
            Text('Your profile details help other people recognise you on ConnectX.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.45)),
          ],
        );
      },
    );
  }
}

class _ProfileInfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _ProfileInfoTile({required this.icon, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withOpacity(.42),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: colors.outlineVariant.withOpacity(.55)),
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(13)),
          child: Icon(icon, color: colors.onPrimaryContainer),
        ),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
        ])),
      ]),
    );
  }
}
