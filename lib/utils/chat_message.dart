import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../chat_screen.dart';
import '../models/message.dart';

final Set<String> _readReceiptAttempts = <String>{};

class ChatMessage extends StatefulWidget {
  final Message message;
  final DocumentReference<Map<String, dynamic>>? messageRef;
  final bool isMe;
  final int? previousMessage;
  final bool isFirstMessage;
  final bool isLastMessage;

  const ChatMessage({
    Key? key,
    required this.message,
    this.messageRef,
    required this.isMe,
    required this.previousMessage,
    required this.isFirstMessage,
    required this.isLastMessage,
  }) : super(key: key);

  @override
  State<ChatMessage> createState() => _ChatMessageState();
}

class _ChatMessageState extends State<ChatMessage> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _audioPlaying = false;

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<String?> _prepareMediaUrl(String value) async {
    final message = widget.message;
    if (!message.isViewOnce) return value;
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null) return null;
    if (!widget.isMe && message.viewedBy.containsKey(uid)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This view-once item has already been opened.')));
      return null;
    }
    if (!widget.isMe) {
      if (widget.messageRef == null) return null;
      try {
        await widget.messageRef!.update({'viewedBy.$uid': FieldValue.serverTimestamp()});
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This view-once item is no longer available.')));
        return null;
      }
    }
    final token = await user!.getIdToken();
    if (token == null || token.isEmpty) return null;
    final uri = Uri.parse(value);
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      'viewOnce': '1',
      'auth': token,
    }).toString();
  }

  Future<void> _openMedia(String value) async {
    final prepared = await _prepareMediaUrl(value);
    if (prepared == null) return;
    await _openUrl(prepared);
  }

  Widget _mediaContent(Color textColor, Color secondary) {
    final message = widget.message;
    final url = message.mediaUrl ?? '';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (message.isViewOnce && !widget.isMe && uid != null && message.viewedBy.containsKey(uid)) {
      return const Text('Opened once');
    }
    switch (message.type) {
      case 'image':
        if (message.isViewOnce && !widget.isMe) return TextButton.icon(
          onPressed: () => _openMedia(url), icon: const Icon(Icons.looks_one), label: const Text('Open photo once'));
        return GestureDetector(
          onTap: () => _openMedia(url),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(url, width: 230, height: 190, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 220, height: 90, child: Center(child: Icon(Icons.broken_image_outlined))),
              ),
            ),
            if (message.fileName != null)
              Padding(padding: const EdgeInsets.only(top: 4),
                child: Text(message.fileName!, style: TextStyle(color: textColor, fontSize: 12))),
          ]),
        );
      case 'video':
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(child: Icon(Icons.play_arrow_rounded)),
          title: Text(message.fileName ?? 'Video', style: TextStyle(color: textColor)),
          subtitle: Text('Tap to open video', style: TextStyle(color: secondary, fontSize: 11)),
          onTap: () => _openMedia(url),
        );
      case 'document':
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.insert_drive_file_rounded, size: 30),
          title: Text(message.fileName ?? 'Document', maxLines: 2,
            overflow: TextOverflow.ellipsis, style: TextStyle(color: textColor)),
          subtitle: Text('Tap to open document', style: TextStyle(color: secondary, fontSize: 11)),
          onTap: () => _openMedia(url),
        );
      case 'sticker':
        return Padding(padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(message.message, style: const TextStyle(fontSize: 52)));
      case 'poll':
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final votes = message.pollVotes;
        final total = votes.length;
        final selected = uid == null ? null : votes[uid];
        return SizedBox(width: 245, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [Icon(Icons.poll_outlined, size: 18), SizedBox(width: 6), Text('POLL', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11))]),
            const SizedBox(height: 7),
            Text(message.message, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...message.pollOptions.asMap().entries.map((entry) {
              final count = votes.values.where((v) => v == entry.key).length;
              final percent = total == 0 ? 0.0 : count / total;
              final isSelected = selected == entry.key;
              return InkWell(
                onTap: uid == null || widget.messageRef == null ? null : () {
                  widget.messageRef!.update({'pollVotes.$uid': entry.key}).catchError((_) {});
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 7),
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    border: Border.all(color: isSelected ? Theme.of(context).colorScheme.primary : secondary.withOpacity(.4)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(entry.value, style: TextStyle(color: textColor))),
                      Text('$count', style: TextStyle(color: secondary, fontSize: 11)),
                      if (isSelected) const Icon(Icons.check_circle, size: 15),
                    ]),
                    const SizedBox(height: 5),
                    ClipRRect(borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: percent, minHeight: 4)),
                  ]),
                ),
              );
            }),
            Text('$total vote(s) · Tap an option to vote/change vote',
              style: TextStyle(color: secondary, fontSize: 10)),
          ],
        ));
      case 'audio':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(_audioPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              size: 34, color: Theme.of(context).colorScheme.primary),
            onPressed: () async {
              if (_audioPlaying) {
                await _audioPlayer.pause();
                if (mounted) setState(() => _audioPlaying = false);
              } else {
                final playUrl = await _prepareMediaUrl(url);
              if (playUrl == null) return;
              await _audioPlayer.play(UrlSource(playUrl));
                if (mounted) setState(() => _audioPlaying = true);
                _audioPlayer.onPlayerComplete.listen((_) {
                  if (mounted) setState(() => _audioPlaying = false);
                });
              }
            },
          ),
          Text('Voice message', style: TextStyle(color: textColor)),
        ]);
      case 'location':
        final lat = message.latitude;
        final lng = message.longitude;
        return TextButton.icon(
          onPressed: lat == null || lng == null ? null
            : () => _openUrl('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
          icon: const Icon(Icons.location_on_rounded),
          label: Text('View shared location', style: TextStyle(color: textColor)),
        );
      case 'contact':
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
          title: Text(message.contactName ?? 'Contact', style: TextStyle(color: textColor)),
          subtitle: Text(message.contactPhone ?? '', style: TextStyle(color: secondary)),
          trailing: IconButton(
            icon: const Icon(Icons.call_rounded),
            onPressed: message.contactPhone == null ? null
              : () => _openUrl('tel:${message.contactPhone}'),
          ),
        );
      default:
        return Text(message.message,
          style: TextStyle(color: textColor, fontSize: 16, height: 1.28));
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isMe = widget.isMe;
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
      if (isNewDay(widget.isFirstMessage, widget.previousMessage, message.timestamp))
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
            _mediaContent(textColor, secondary),
            Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (message.isEdited) Text('edited ', style: TextStyle(fontSize: 9, color: secondary)),
              const SizedBox(width: 8),
              Text(time, style: TextStyle(fontSize: 10, color: secondary)),
              if (isMe) ...[
                const SizedBox(width: 3),
                Icon(message.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                  size: 15, color: message.isRead ? const Color(0xFF53BDEB) : secondary),
              ],
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
