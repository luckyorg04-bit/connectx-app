import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/chat_storage.dart';
import 'package:connectx/main.dart';
import 'package:connectx/main_screen.dart' show users;
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
  bool _recording = false;
  final Record _recorder = Record();
  final ImagePicker _imagePicker = ImagePicker();
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
      await _ensureCanMessage();
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


  Future<void> _ensureCanMessage() async {
    final currentBlocked = await FirebaseDatabase.instance.ref('Users')
        .child(_uid).child('blockedUsers').child(user!.key).get();
    final otherBlocked = await FirebaseDatabase.instance.ref('Users')
        .child(user!.key).child('blockedUsers').child(_uid).get();
    if (currentBlocked.value == true || otherBlocked.value == true) {
      throw Exception('This conversation is blocked. Unblock the user to send messages.');
    }
  }

  Future<void> _sendStructuredMessage({
    required String type,
    required String text,
    String? mediaUrl,
    String? fileName,
    int? durationMs,
    double? latitude,
    double? longitude,
    String? contactName,
    String? contactPhone,
  }) async {
    await _ensureCanMessage();
    await _messages.add({
      'message': text,
      'type': type,
      'mediaUrl': mediaUrl,
      'fileName': fileName,
      'durationMs': durationMs,
      'latitude': latitude,
      'longitude': longitude,
      'contactName': contactName,
      'contactPhone': contactPhone,
      'isRead': false,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'sender': _uid,
      'isEdited': false,
      'isForwarded': false,
      'reactions': <String, dynamic>{},
    });
    await FirebaseDatabase.instance.ref('Users').child(_uid)
        .child('chats').child('personal').child(user!.key).set(ServerValue.timestamp);
    await FirebaseDatabase.instance.ref('Users').child(user!.key)
        .child('chats').child('personal').child(_uid).set(ServerValue.timestamp);
  }

  Future<void> _uploadBytes({
    required List<int> bytes,
    required String fileName,
    required String contentType,
    required String type,
  }) async {
    if (bytes.isEmpty) return;
    if (mounted) setState(() => _sending = true);
    try {
      await _ensureCanMessage();
      final url = await ChatStorage.upload(
        conversationId: assignUsers(_uid, user!.key),
        fileName: fileName,
        bytes: bytes is List<int> ? Uint8List.fromList(bytes) : Uint8List(0),
        contentType: contentType,
      );
      await _sendStructuredMessage(
        type: type,
        text: fileName,
        mediaUrl: url,
        fileName: fileName,
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImageOrVideo(bool video) async {
    try {
      final picked = video
          ? await _imagePicker.pickVideo(source: ImageSource.gallery)
          : await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 82);
      if (picked == null) return;
      final extension = picked.name.split('.').last.toLowerCase();
      await _uploadBytes(
        bytes: await picked.readAsBytes(),
        fileName: picked.name,
        contentType: video ? 'video/${extension == 'mov' ? 'quicktime' : 'mp4'}'
            : 'image/${extension == 'png' ? 'png' : extension == 'webp' ? 'webp' : 'jpeg'}',
        type: video ? 'video' : 'image',
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to select media: $error')),
      );
    }
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read this file. Please select it again.')),
      );
      return;
    }
    final ext = (file.extension ?? '').toLowerCase();
    final type = ext == 'pdf' ? 'application/pdf'
        : ext == 'txt' ? 'text/plain'
        : ext == 'doc' ? 'application/msword'
        : 'application/octet-stream';
    await _uploadBytes(bytes: file.bytes!, fileName: file.name,
        contentType: type, type: 'document');
  }

  Future<void> _sendLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Turn on Location Services and try again.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission was not granted.');
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _sendStructuredMessage(
        type: 'location',
        text: 'Shared a location',
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location sharing failed: $error')),
      );
    }
  }

  Future<void> _shareContact() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Share contact'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Contact name')),
          TextField(controller: phone, keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone number')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Share')),
        ],
      ),
    );
    if (confirmed == true && name.text.trim().isNotEmpty && phone.text.trim().isNotEmpty) {
      await _sendStructuredMessage(type: 'contact',
        text: '${name.text.trim()} • ${phone.text.trim()}',
        contactName: name.text.trim(), contactPhone: phone.text.trim());
    }
    name.dispose();
    phone.dispose();
  }

  Future<void> _toggleVoiceRecording() async {
    if (_sending) return;
    if (!_recording) {
      final allowed = await _recorder.hasPermission();
      if (!allowed) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required.')),
        );
        return;
      }
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/connectx_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(path: path, encoder: AudioEncoder.aacLc);
      if (mounted) setState(() => _recording = true);
      return;
    }
    final path = await _recorder.stop();
    if (mounted) setState(() => _recording = false);
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    await _uploadBytes(bytes: bytes, fileName: 'voice_note.m4a',
      contentType: 'audio/mp4', type: 'audio');
  }

  Future<void> _toggleStar(Message message) async {
    if (message.messageId == null) return;
    final ref = FirebaseDatabase.instance.ref('Users').child(_uid)
        .child('chatMeta').child(user!.key).child('starredMessages')
        .child(message.messageId!);
    final existing = await ref.get();
    if (existing.value == true) {
      await ref.remove();
    } else {
      await ref.set(true);
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(existing.value == true ? 'Removed from starred' : 'Message starred')),
    );
  }

  Future<void> _showStarredMessages() async {
    final snap = await FirebaseDatabase.instance.ref('Users').child(_uid)
        .child('chatMeta').child(user!.key).child('starredMessages').get();
    if (!snap.exists || snap.value is! Map) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No starred messages in this chat.')),
      );
      return;
    }
    final ids = Map<dynamic, dynamic>.from(snap.value as Map).keys.map((e) => e.toString()).toList();
    final docs = await Future.wait(ids.map((id) => _messages.doc(id).get()));
    final items = docs.where((doc) => doc.exists).toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(child: SizedBox(height: 420,
        child: items.isEmpty
          ? const Center(child: Text('No starred messages found.'))
          : ListView(children: items.map((doc) {
              final data = doc.data() ?? {};
              return ListTile(
                leading: const Icon(Icons.star, color: Colors.amber),
                title: Text((data['message'] ?? 'Shared item').toString(),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(DateTime.fromMillisecondsSinceEpoch(
                  (data['timestamp'] as num?)?.toInt() ?? 0).toString()),
              );
            }).toList(),
        ),
      )),
    );
  }

  Future<void> _blockOrUnblockUser() async {
    final ref = FirebaseDatabase.instance.ref('Users').child(_uid)
        .child('blockedUsers').child(user!.key);
    final existing = await ref.get();
    if (existing.value == true) {
      await ref.remove();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User unblocked.')),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block this user?'),
        content: const Text('They will not be able to exchange messages with you through ConnectX.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Block')),
        ],
      ),
    );
    if (confirm == true) {
      await ref.set(true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User blocked.')),
      );
    }
  }

  Future<void> _reportUser() async {
    final reason = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report user'),
        content: TextField(controller: reason, maxLines: 3,
          decoration: const InputDecoration(hintText: 'Describe the issue')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit report')),
        ],
      ),
    );
    if (confirm == true && reason.text.trim().isNotEmpty) {
      await FirebaseFirestore.instance.collection('reports').add({
        'reporterUid': _uid,
        'reportedUid': user!.key,
        'reason': reason.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'open',
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report submitted.')),
      );
    }
    reason.dispose();
  }

  Future<void> _messageActions(Message message, bool isMe) async {
    final action = await showModalBottomSheet<String>(
      context: context,
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
            leading: const Icon(Icons.star_border_rounded),
            title: const Text('Star message'),
            onTap: () => Navigator.pop(context, 'star'),
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
    } else if (action == 'star') {
      await _toggleStar(message);
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
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'starred') _showStarredMessages();
              if (value == 'block') _blockOrUnblockUser();
              if (value == 'report') _reportUser();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'starred', child: Text('Starred messages')),
              PopupMenuItem(value: 'block', child: Text('Block / unblock user')),
              PopupMenuItem(value: 'report', child: Text('Report user')),
            ],
          ),
        ],
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
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.attach_file_rounded),
              onSelected: (value) {
                if (value == 'image') _pickImageOrVideo(false);
                if (value == 'video') _pickImageOrVideo(true);
                if (value == 'document') _pickDocument();
                if (value == 'location') _sendLocation();
                if (value == 'contact') _shareContact();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'image', child: ListTile(leading: Icon(Icons.photo), title: Text('Photo'))),
                PopupMenuItem(value: 'video', child: ListTile(leading: Icon(Icons.videocam), title: Text('Video'))),
                PopupMenuItem(value: 'document', child: ListTile(leading: Icon(Icons.insert_drive_file), title: Text('Document'))),
                PopupMenuItem(value: 'location', child: ListTile(leading: Icon(Icons.location_on), title: Text('Location'))),
                PopupMenuItem(value: 'contact', child: ListTile(leading: Icon(Icons.contact_page), title: Text('Contact'))),
              ],
            ),
            Expanded(child: TextField(
              controller: textFieldController,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (value) => _setTyping(value.trim().isNotEmpty),
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: _recording ? 'Recording voice note…' : 'Message',
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
              ),
            )),
            const SizedBox(width: 6),
            IconButton(
              tooltip: _recording ? 'Stop and send voice note' : 'Record voice note',
              icon: Icon(_recording ? Icons.stop_circle_rounded : Icons.mic_none_rounded,
                color: _recording ? Colors.red : Theme.of(context).colorScheme.primary),
              onPressed: _sending ? null : _toggleVoiceRecording,
            ),
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
    _recorder.dispose();
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
