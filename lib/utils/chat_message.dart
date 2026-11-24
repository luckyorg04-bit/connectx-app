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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bubble = isMe ? (dark ? const Color(0xFF005C4B) : const Color(0xFFD9FDD3))
        : (dark ? const Color(0xFF202C33) : Colors.white);
    final textColor = dark ? const Color(0xFFE9EDEF) : const Color(0xFF111B21);
    final secondary = dark ? const Color(0xFFB7C4CC) : const Color(0xFF667781);
    final time = DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(message.timestamp));

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (!isMe && !message.isRead && uid != null && message.messageId != null &&
        _readReceiptAttempts.add(message.messageId!)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FirebaseFirestore.instance.collection('messages').doc(assignUsers(uid, message.sender))
            .collection('chats').doc(message.messageId).update({'isRead': true}).catchError((_) {});
      });
    }

    return Column(children: [
      if (isNewDay(isFirstMessage, previousMessage, message.timestamp))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF26343C) : const Color(0xFFE7F0F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(_dateLabel(message.timestamp), style: TextStyle(fontSize: 12, color: secondary)),
            ),
          ),
        ),
      Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(left: isMe ? 54 : 8, right: isMe ? 8 : 54, top: 2, bottom: 5),
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 6),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .82),
          decoration: BoxDecoration(
            color: bubble,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(8), topRight: const Radius.circular(8),
              bottomLeft: Radius.circular(isMe ? 8 : 2), bottomRight: Radius.circular(isMe ? 2 : 8),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (message.isForwarded)
              Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('↗ Forwarded',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: secondary))),
            if (message.replyTo != null && message.replyTo!.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 5),
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: Colors.black.withOpacity(.07),
                  border: Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 3)),
                  borderRadius: BorderRadius.circular(5)),
                child: Text(message.replyTo!, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: textColor.withOpacity(.8))),
              ),
            Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Flexible(child: Text(message.message, style: TextStyle(color: textColor, fontSize: 16, height: 1.28))),
              const SizedBox(width: 8),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (message.isEdited) Text('edited ', style: TextStyle(fontSize: 9, color: secondary)),
                Text(time, style: TextStyle(fontSize: 10, color: secondary)),
                if (isMe) ...[
                  const SizedBox(width: 3),
                  Icon(message.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 15, color: message.isRead ? const Color(0xFF53BDEB) : secondary),
                ],
              ]),
            ]),
            if (message.reactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Wrap(spacing: 4, children: message.reactions.values.map((value) =>
                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(.07), borderRadius: BorderRadius.circular(12)),
                    child: Text(value.toString(), style: const TextStyle(fontSize: 13)))).toList()),
              ),
          ]),
        ),
      ),
    ]);
  }

  String _dateLabel(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('MMMM d, y').format(date);
  }
}
