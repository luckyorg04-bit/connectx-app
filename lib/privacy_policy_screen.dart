import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String _email = 'contact@luckydubey.in';

  Future<void> _contactSupport() async {
    final uri = Uri(scheme: 'mailto', path: _email,
      queryParameters: {'subject': 'ConnectX Privacy Request'});
    await launchUrl(uri);
  }

  Widget _section(BuildContext context, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
        Text(body, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        children: [
          Text('ConnectX – Chat', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Effective date: 25 November 2026', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 18),
          _section(context, '1. Information we may collect',
            'Account and profile information such as email address, name, username, profile photo and bio. Messages and content you choose to send, including group messages, polls, images, videos, voice notes and files. Device and notification tokens. When you use calling, microphone and, for video calls, camera access. If you choose location sharing and grant permission, your device location may be shared with the recipients you select.'),
          _section(context, '2. How we use information',
            'We use information to create and manage accounts, display profiles, deliver messages and files, enable group conversations and calls, send notifications, provide optional location sharing, protect the service, troubleshoot failures and respond to support requests.'),
          _section(context, '3. How information is shared',
            'Information and content you choose to share in a profile, chat, group or location-sharing action is visible to the relevant recipients. We use Google Firebase services for authentication, databases and push notifications. Uploaded media and profile photos are processed by ConnectX infrastructure at connecttx.duckdns.org. We may disclose information when required by law or reasonably necessary to protect users or the service. We do not sell personal information or serve third-party advertising.'),
          _section(context, '4. Data storage and security',
            'Information is processed and stored by ConnectX and its service providers as needed to operate the service. We use reasonable technical and organisational safeguards, but no internet transmission or storage system can be guaranteed completely secure.'),
          _section(context, '5. Data retention',
            'We retain account information and user content for as long as needed to provide the service, meet operational needs and comply with applicable legal obligations. Backups and service-provider systems may take additional time to complete deletion.'),
          _section(context, '6. Account and data deletion',
            'Open Profile and select Request account deletion to start an email request, or contact $_email from your registered email address. Include your ConnectX username and the subject “Account and Data Deletion Request”. Requests are manually reviewed and processed by support. This email request does not delete the account automatically. Uninstalling the app does not delete your account or data.'),
          _section(context, '7. Children’s privacy',
            'ConnectX is not directed to children under 13, and we do not knowingly seek to collect personal information from children under 13. Contact support if you believe a child has provided personal information.'),
          _section(context, '8. Your choices',
            'You can manage app permissions through Android settings, choose what content you share, and avoid optional features such as camera, microphone or location sharing. You may contact support to ask about, correct or request deletion of your information, subject to applicable law.'),
          _section(context, '9. Changes to this policy',
            'We may update this policy when the app or our practices change. The latest version and effective date will be published through our official privacy-policy page.'),
          _section(context, '10. Contact',
            'ConnectX Privacy Support\nGhost Group of Industries\n$_email'),
          OutlinedButton.icon(
            onPressed: _contactSupport,
            icon: const Icon(Icons.mail_outline),
            label: const Text('Contact privacy support'),
          ),
        ],
      ),
    );
  }
}
