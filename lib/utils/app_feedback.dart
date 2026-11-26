import 'package:flutter/material.dart';

Future<void> showConnectXErrorDialog(
  BuildContext context,
  String message, {
  String title = 'Something went wrong',
}) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
      title: Text(title),
      content: Text(message),
      actions: [FilledButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('OK'),
      )],
    ),
  );
}
