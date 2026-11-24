import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../chat_screen.dart';
import '../models/message.dart';
import 'package:url_launcher/url_launcher.dart';

final Set<String> _readReceiptAttempts = <String>{};

class ChatMessage extends StatelessWidget {
  final Message message;
  final bool isMe;
  final int? previousMessage;
  final bool isFirstMessage;
  final bool isLastMessage;

  const ChatMessage({
    Key? key,
    required this.message,
    required this.isMe,
    required this.previousMessage,
    required this.isFirstMessage,
    required this.isLastMessage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bubbleColor = isMe
        ? (isDark ? const Color(0xFF005C4B) : const Color(0xFFD9FDD3))
        : (isDark ? const Color(0xFF202C33) : Colors.white);
    final textColor = isDark ? const Color(0xFFE9EDEF) : const Color(0xFF111B21);
    final secondaryColor = isDark ? const Color(0xFFB7C4CC) : const Color(0xFF667781);
    final time = DateFormat('h:mm a').format(
      DateTime.fromMillisecondsSinceEpoch(message.timestamp),
    );

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final messageId = message.messageId;
    if (!isMe && !message.isRead && currentUid != null &&
        messageId != null && _readReceiptAttempts.add(messageId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FirebaseFirestore.instance
            .collection('messages')
            .doc(assignUsers(currentUid, message.sender))
            .collection('chats')
            .doc(messageId)
            .update({'isRead': true})
            .catchError((_) {
              // Firestore rules must allow the receiver to update isRead.
            });
      });
    }

    return Column(
      children: [
        if (isNewDay(isFirstMessage, previousMessage, message.timestamp))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF26343C) : const Color(0xFFE7F0F5),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  _dateLabel(message.timestamp),
                  style: TextStyle(fontSize: 12, color: secondaryColor, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
        Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
            onTap: () => _openLink(message.message),
            child: Container(
              margin: EdgeInsets.only(
                left: isMe ? 54 : 8,
                right: isMe ? 8 : 54,
                top: 2,
                bottom: 2,
              ),
              padding: const EdgeInsets.fromLTRB(10, 7, 8, 5),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(8),
                  topRight: const Radius.circular(8),
                  bottomLeft: Radius.circular(isMe ? 8 : 2),
                  bottomRight: Radius.circular(isMe ? 2 : 8),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(isDark ? 0.05 : 0.035), blurRadius: 1),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        message.message,
                        style: TextStyle(color: textColor, fontSize: 16, height: 1.28),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(time, style: TextStyle(fontSize: 10, color: secondaryColor)),
                        if (isMe) ...[
                          const SizedBox(width: 3),
                          Icon(
                            message.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                            size: 15,
                            color: message.isRead ? const Color(0xFF53BDEB) : secondaryColor,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _dateLabel(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(date.year, date.month, date.day);
    if (messageDay == today) return 'Today';
    if (messageDay == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('MMMM d, y').format(date);
  }

  Future<void> _openLink(String text) async {
    final uri = getUri(text);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Uri? getUri(String text) {
    final urlRegex = RegExp(r'(https?://[^\s]+)');
    final match = urlRegex.firstMatch(text);
    if (match == null) return null;
    return Uri.tryParse(match.group(0)!);
  }
}
