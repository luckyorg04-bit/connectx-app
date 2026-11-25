import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'models/user.dart';
import 'services/database_service.dart';

class ConnectQrScreen extends StatefulWidget {
  final bool scanMode;

  const ConnectQrScreen({super.key, this.scanMode = false});

  @override
  State<ConnectQrScreen> createState() => _ConnectQrScreenState();
}

class _ConnectQrScreenState extends State<ConnectQrScreen> {
  bool _handlingScan = false;

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_handlingScan || !mounted) return;
    final barcode = capture.barcodes
        .map((item) => item.rawValue)
        .whereType<String>()
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (barcode.isEmpty) return;

    _handlingScan = true;
    try {
      final uri = Uri.tryParse(barcode);
      if (uri == null ||
          uri.scheme != 'connectx' ||
          uri.host != 'user' ||
          uri.pathSegments.length != 1) {
        _showMessage('This is not a valid ConnectX QR code.');
        _handlingScan = false;
        return;
      }

      final targetUid = uri.pathSegments.single;
      if (!RegExp(r'^[A-Za-z0-9_-]{10,128}$').hasMatch(targetUid)) {
        _showMessage('Invalid ConnectX profile code.');
        _handlingScan = false;
        return;
      }
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (targetUid == currentUid) {
        _showMessage('This is your own QR code.');
        _handlingScan = false;
        return;
      }

      final snapshot = await ConnectXDatabase.instance
          .ref('PublicUsers')
          .child(targetUid)
          .get();
      if (!mounted) return;
      if (!snapshot.exists) {
        _showMessage('ConnectX profile not found.');
        _handlingScan = false;
        return;
      }

      final user = User1.getFromSnapshot(snapshot);
      final openChat = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('ConnectX profile found'),
          content: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundImage:
                    user.photoUrl.isNotEmpty ? NetworkImage(user.photoUrl) : null,
                child: user.photoUrl.isEmpty
                    ? Text(user.username.isEmpty
                        ? 'C'
                        : user.username[0].toUpperCase())
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('@${user.username}',
                        style: Theme.of(dialogContext).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Message'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (openChat == true) {
        await Navigator.of(context)
            .pushReplacementNamed('/chat', arguments: user);
      }
    } catch (error) {
      debugPrint('ConnectX QR scan failed: $error');
      _showMessage('Could not open this QR code. Try again.');
    } finally {
      if (mounted) _handlingScan = false;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (widget.scanMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('Scan ConnectX QR')),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                child: Text(
                  'Point your camera at someone’s ConnectX QR code.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(onDetect: _handleScan),
                        IgnorePointer(
                          child: Center(
                            child: Container(
                              width: 250,
                              height: 250,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: colors.primary,
                                  width: 4,
                                ),
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 22,
                          child: Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(.62),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 9),
                                child: Text(
                                  'Scanning for ConnectX code…',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final qrData = 'connectx://user/$uid';
    return Scaffold(
      appBar: AppBar(title: const Text('My ConnectX QR')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: colors.primaryContainer,
                  child: Icon(Icons.qr_code_2_rounded,
                      size: 38, color: colors.onPrimaryContainer),
                ),
                const SizedBox(height: 18),
                Text('Your ConnectX code',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        )),
                const SizedBox(height: 8),
                Text(
                  'Let people scan this code to find your profile and message you.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 248,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: uid.isEmpty
                      ? null
                      : () => Share.share(
                            'Connect with me on ConnectX. Scan my QR code in the ConnectX app.\n$qrData',
                          ),
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Share my code'),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ConnectQrScreen(scanMode: true),
                    ),
                  ),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scan someone’s code'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
