import 'dart:async';
import 'package:connectx/main.dart';
import 'package:connectx/utils/chat_message.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models/user.dart';
import 'models/message.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final textFieldController = TextEditingController();
  final scrollController = ScrollController();
  User1? user;
  bool _initialized = false;
  bool _sending = false;
  Message? _replyingTo;
  Message? _editing;
  Timer? _typingTimer;
  bool _remoteTyping = false;
  StreamSubscription<DatabaseEvent>? _typingSubscription;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  CollectionReference<Map<String, dynamic>> get _messages =>
      FirebaseFirestore.instance.collection('messages')
          .doc(assignUsers(_uid, user!.key)).collection('chats');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      user = ModalRoute.of(context)!.settings.arguments as User1;
      _initialized = true;
      _listenForTyping();
    }
  }

  void _listenForTyping() {
    _typingSubscription = FirebaseDatabase.instance.ref('Users')
        .child(user!.key).child('typing').child(_uid).onValue.listen((event) {
      if (!mounted) return;
      setState(() => _remoteTyping = event.snapshot.value == true);
    });
  }

  Future<void> _setTyping(bool typing) async {
    final ref = FirebaseDatabase.instance.ref('Users').child(_uid)
        .child('typing').child(user!.key);
    if (typing) {
      await ref.set(true);
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () => ref.remove());
    } else {
      _typingTimer?.cancel();
      await ref.remove();
    }
  }

  Future<void> _sendMessage() async {
    final text = textFieldController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_editing != null) {
        final msg = _editing!;
        if (msg.sender != _uid ||
            DateTime.now().millisecondsSinceEpoch - msg.timestamp > 15 * 60 * 1000) {
          throw Exception('You can edit your own messages within 15 minutes.');
        }
        await _messages.doc(msg.messageId).update({
          'message': text,
          'isEdited': true,
          'editedAt': now,
        });
      } else {
        await _messages.add({
          'message': text,
          'isRead': false,
          'timestamp': now,
          'sender': _uid,
          'replyTo': _replyingTo?.message,
          'replyToId': _replyingTo?.messageId,
          'isEdited': false,
          'isForwarded': false,
          'reactions': <String, dynamic>{},
        });
        await FirebaseDatabase.instance.ref('Users').child(_uid)
            .child('chats').child('personal').child(user!.key).set(ServerValue.timestamp);
        await FirebaseDatabase.instance.ref('Users').child(user!.key)
            .child('chats').child('personal').child(_uid).set(ServerValue.timestamp);
      }
      textFieldController.clear();
      await _setTyping(false);
      if (mounted) setState(() {
        _replyingTo = null;
        _editing = null;
      });
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _messageActions(Message message, bool isMe) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          if (isMe) ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit message'),
            onTap: () => Navigator.pop(context, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.reply_rounded),
            title: const Text('Reply'),
            onTap: () => Navigator.pop(context, 'reply'),
          ),
          ListTile(
            leading: const Icon(Icons.forward_rounded),
            title: const Text('Forward'),
            onTap: () => Navigator.pop(context, 'forward'),
          ),
          ListTile(
            leading: const Icon(Icons.emoji_emotions_outlined),
            title: const Text('React'),
            onTap: () => Navigator.pop(context, 'react'),
          ),
          if (isMe) ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Delete for everyone'),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'reply') {
      setState(() { _replyingTo = message; _editing = null; textFieldController.clear(); });
    } else if (action == 'edit') {
      if (DateTime.now().millisecondsSinceEpoch - message.timestamp > 15 * 60 * 1000) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Messages can only be edited within 15 minutes.')));
        return;
      }
      setState(() { _editing = message; _replyingTo = null; textFieldController.text = message.message; });
    } else if (action == 'delete') {
      await _messages.doc(message.messageId).delete();
    } else if (action == 'react') {
      final emoji = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['👍','❤️','😂','😮','😢','🙏'].map((emoji) =>
            TextButton(onPressed: () => Navigator.pop(context, emoji),
              child: Text(emoji, style: const TextStyle(fontSize: 27)))).toList(),
        )),
      );
      if (emoji != null) {
        await _messages.doc(message.messageId).update({'reactions.$_uid': emoji});
      }
    } else if (action == 'forward') {
      await _forwardMessage(message);
    }
  }

  Future<void> _forwardMessage(Message message) async {
    final candidates = users.where((item) => item.key != _uid && item.key != user!.key).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No other contacts available to forward this message.')));
      return;
    }
    final target = await showDialog<User1>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forward to'),
        content: SizedBox(width: double.maxFinite, height: 300, child: ListView(
          children: candidates.map((candidate) => ListTile(
            leading: CircleAvatar(child: Text(candidate.username.isEmpty ? 'C' : candidate.username[0].toUpperCase())),
            title: Text(candidate.name),
            onTap: () => Navigator.pop(context, candidate),
          )).toList(),
        )),
      ),
    );
    if (target == null) return;
    final targetId = assignUsers(_uid, target.key);
    await FirebaseFirestore.instance.collection('messages').doc(targetId).collection('chats').add({
      'message': message.message,
      'isRead': false,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'sender': _uid,
      'isForwarded': true,
      'isEdited': false,
      'reactions': <String, dynamic>{},
    });
    await FirebaseDatabase.instance.ref('Users').child(_uid).child('chats')
        .child('personal').child(target.key).set(ServerValue.timestamp);
    await FirebaseDatabase.instance.ref('Users').child(target.key).child('chats')
        .child('personal').child(_uid).set(ServerValue.timestamp);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Forwarded to ${target.name}')));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final currentUser = FirebaseAuth.instance.currentUser!;
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0B141A) : const Color(0xFFEFEAE2),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.settings.name == '/main');
              currentRoute = '/main';
            },
          ),
          CircleAvatar(
            radius: 20,
            backgroundImage: user!.photoUrl.isNotEmpty ? NetworkImage(user!.photoUrl) : null,
            child: user!.photoUrl.isEmpty ? Text(user!.username.isEmpty ? 'C' : user!.username[0].toUpperCase()) : null,
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
            Text(_remoteTyping ? 'typing…' : (user!.online ? 'online' : 'last seen recently'),
              style: const TextStyle(fontSize: 11)),
          ])),
        ]),
      ),
      body: Column(children: [
        Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _messages.orderBy('timestamp', descending: true).limit(100).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text('Could not load messages: ${snapshot.error}'));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) return const Center(child: Text('Say hello to start this conversation.'));
            return ListView.builder(
              reverse: true,
              controller: scrollController,
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final message = Message.fromSnapshot(docs[index]);
                final isMe = message.sender == currentUser.uid;
                return GestureDetector(
                  onLongPress: () => _messageActions(message, isMe),
                  child: ChatMessage(
                    message: message,
                    isMe: isMe,
                    previousMessage: index + 1 < docs.length
                        ? (docs[index + 1].data()['timestamp'] as num?)?.toInt() : null,
                    isFirstMessage: index == docs.length - 1,
                    isLastMessage: index == 0,
                  ),
                );
              },
            );
          },
        )),
        if (_replyingTo != null || _editing != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            color: Theme.of(context).colorScheme.surface,
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_editing != null ? 'Editing message' : 'Replying to ${_replyingTo!.sender == _uid ? 'yourself' : user!.name}',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
                Text(_editing?.message ?? _replyingTo!.message, maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() {
                _replyingTo = null; _editing = null; textFieldController.clear();
              })),
            ]),
          ),
        SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Row(children: [
            Expanded(child: TextField(
              controller: textFieldController,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (value) => _setTyping(value.trim().isNotEmpty),
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: 'Message',
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
              ),
            )),
            const SizedBox(width: 6),
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: IconButton(
                icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, color: Colors.white),
                onPressed: _sending ? null : _sendMessage,
              ),
            ),
          ]),
        )),
      ]),
    );
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _typingSubscription?.cancel();
    _setTyping(false);
    textFieldController.dispose();
    scrollController.dispose();
    super.dispose();
  }
}

String assignUsers(String user1, String user2) {
  if (user1.compareTo(user2) <= 0) return '$user1,$user2';
  return '$user2,$user1';
}

bool isNewDay(bool isFirst, int? lastMessage, int message) {
  final date = DateTime.fromMillisecondsSinceEpoch(message);
  if (isFirst || lastMessage == null) return true;
  final previous = DateTime.fromMillisecondsSinceEpoch(lastMessage);
  return date.year != previous.year || date.month != previous.month || date.day != previous.day;
}
