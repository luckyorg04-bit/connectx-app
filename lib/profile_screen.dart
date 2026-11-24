import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return 'C';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final userRef = FirebaseDatabase.instance.ref('Users').child(user.uid);
    return StreamBuilder<DatabaseEvent>(
      stream: userRef.onValue,
      builder: (context, snapshot) {
        final data = snapshot.data?.snapshot;
        final name = data?.child('name').value?.toString() ??
            user.displayName ?? 'ConnectX User';
        final username = data?.child('username').value?.toString() ?? '';
        final about = data?.child('about').value?.toString() ?? 'Available on ConnectX';
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 58,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      _initials(name),
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
                  const SizedBox(height: 5),
                  Text('@$username', style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _ProfileInfoTile(
              icon: Icons.person_outline_rounded,
              title: 'Name',
              value: name,
            ),
            _ProfileInfoTile(
              icon: Icons.info_outline_rounded,
              title: 'About',
              value: about,
            ),
            _ProfileInfoTile(
              icon: Icons.alternate_email_rounded,
              title: 'Email',
              value: user.email ?? 'Not available',
            ),
            _ProfileInfoTile(
              icon: Icons.verified_user_outlined,
              title: 'Account',
              value: 'ConnectX account',
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                'Your profile information is visible to ConnectX users.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
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

  const _ProfileInfoTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.45),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: Theme.of(context).textTheme.labelMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ),
    );
  }
}
