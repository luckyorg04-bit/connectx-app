import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_contacts/flutter_contacts.dart';
import 'widgets/connectx_gif_picker.dart';
import 'chat_contact_info_screen.dart';
import 'package:record/record.dart';
import 'services/chat_storage.dart';
import 'package:connectx/main.dart';
import 'package:connectx/main_screen.dart' show users;
import 'package:connectx/utils/chat_message.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'utils/app_feedback.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models/user.dart';
import 'models/message.dart';
import 'services/database_service.dart';

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
  int _disappearingDurationMs = 0;
  bool _sendViewOnce = false;
  String _wallpaperId = '0';
  String? _wallpaperUrl;
  Timer? _expiryRefreshTimer;
  final Record _recorder = Record();
  final ImagePicker _imagePicker = ImagePicker();
  StreamSubscription<DatabaseEvent>? _typingSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _readReceiptSubscription;
  final Set<String> _readReceiptInFlight = <String>{};
  late Stream<QuerySnapshot<Map<String, dynamic>>> _messageStream;

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
      _messageStream = _messages.orderBy('timestamp', descending: true).limit(100).snapshots();
      _readReceiptSubscription = _messageStream.listen(_markIncomingMessagesRead,
        onError: (Object error) => debugPrint('ConnectX read receipt listener failed: $error'));
      _listenForTyping();
      _loadDisappearingSetting();
      _loadChatWallpaper();
      _expiryRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _markIncomingMessagesRead(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['sender'] == _uid || data['isRead'] == true) continue;
      if (!_readReceiptInFlight.add(doc.id)) continue;
      doc.reference.update({'isRead': true, 'isDelivered': true}).catchError((Object error) {
        debugPrint('ConnectX read receipt update failed: $error');
      }).whenComplete(() {
        _readReceiptInFlight.remove(doc.id);
      });
    }
  }

  Future<void> _loadDisappearingSetting() async {
    final value = await ConnectXDatabase.instance.ref('PrivateUsers').child(_uid)
      .child('chatMeta').child(user!.key).child('disappearingDurationMs').get();
    if (mounted) setState(() => _disappearingDurationMs = (value.value as num?)?.toInt() ?? 0);
  }


  DatabaseReference get _chatWallpaperRef => ConnectXDatabase.instance
      .ref('PrivateUsers').child(_uid).child('chatMeta').child(user!.key).child('wallpaper');

  Future<void> _loadChatWallpaper() async {
    try {
      final value = await _chatWallpaperRef.get();
      final data = value.value;
      if (!mounted || data is! Map) return;
      setState(() {
        _wallpaperId = (data['id'] ?? '0').toString();
        _wallpaperUrl = data['url']?.toString();
      });
    } catch (error) {
      debugPrint('ConnectX wallpaper preference unavailable: $error');
    }
  }

  Future<void> _saveChatWallpaper(String id, String? url) async {
    await _chatWallpaperRef.set({'id': id, 'url': url});
    if (!mounted) return;
    setState(() {
      _wallpaperId = id;
      _wallpaperUrl = url;
    });
  }

  Future<void> _openContactInfo() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatContactInfoScreen(
        user: user!,
        onWallpaperSelected: _saveChatWallpaper,
      ),
    ));
  }

  Future<void> _setDisappearingSetting() async {
    final selected = await showModalBottomSheet<int>(context: context, builder: (context) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Disappearing messages', style: TextStyle(fontWeight: FontWeight.w700))),
        ListTile(title: const Text('Off'), onTap: () => Navigator.pop(context, 0)),
        ListTile(title: const Text('1 hour'), onTap: () => Navigator.pop(context, 3600000)),
        ListTile(title: const Text('24 hours'), onTap: () => Navigator.pop(context, 86400000)),
        ListTile(title: const Text('7 days'), onTap: () => Navigator.pop(context, 604800000)),
      ]),
    ));
    if (selected == null) return;
    await ConnectXDatabase.instance.ref('PrivateUsers').child(_uid)
      .child('chatMeta').child(user!.key).child('disappearingDurationMs').set(selected);
    if (mounted) setState(() => _disappearingDurationMs = selected);
  }

  Map<String, dynamic> _expiryFields() {
    if (_disappearingDurationMs <= 0) return {};
    return {'expiresAt': DateTime.now().millisecondsSinceEpoch + _disappearingDurationMs};
  }

  void _listenForTyping() {
    _typingSubscription = ConnectXDatabase.instance.ref('Typing')
        .child(user!.key).child(_uid).onValue.listen((event) {
      if (!mounted) return;
      setState(() => _remoteTyping = event.snapshot.value == true);
    });
  }

  Future<void> _setTyping(bool typing) async {
    final ref = ConnectXDatabase.instance.ref('Typing').child(_uid).child(user!.key);
    try {
      if (typing) {
        await ref.set(true);
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 3), () {
          ref.remove().catchError((error) {
            debugPrint('ConnectX typing cleanup failed: $error');
          });
        });
      } else {
        _typingTimer?.cancel();
        await ref.remove();
      }
    } catch (error) {
      // Typing presence is optional; it must never block message delivery.
      debugPrint('ConnectX typing presence unavailable: $error');
    }
  }

  Future<void> _createPoll() async {
    final question = TextEditingController();
    final options = [TextEditingController(), TextEditingController()];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create poll'),
          content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: question, maxLength: 180,
                decoration: const InputDecoration(labelText: 'Question')),
              ...options.asMap().entries.map((entry) => TextField(
                controller: entry.value,
                maxLength: 80,
                decoration: InputDecoration(labelText: 'Option ${entry.key + 1}'))),
              if (options.length < 6)
                TextButton.icon(onPressed: () => setDialogState(() => options.add(TextEditingController())),
                  icon: const Icon(Icons.add), label: const Text('Add option')),
            ]),
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Share poll')),
          ],
        ),
      ),
    );
    final q = question.text.trim();
    final choices = options.map((c) => c.text.trim()).where((v) => v.isNotEmpty).toList();
    question.dispose();
    for (final c in options) { c.dispose(); }
    if (confirmed != true || q.isEmpty || choices.length < 2) {
      if (confirmed == true && mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a question and at least two options.')));
      return;
    }
    try {
      await _ensureCanMessage();
      await _messages.add({
        'message': q,
        'type': 'poll',
        'pollOptions': choices,
        'pollVotes': <String, dynamic>{},
        'isRead': false,
          'isDelivered': false,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'sender': _uid,
        'isEdited': false,
        'isForwarded': false,
        'reactions': <String, dynamic>{},
        ..._expiryFields(),
      });
      await _updateChatIndex();
    } catch (error) {
      showConnectXErrorDialog(context, 'Poll could not be sent. Please try again.');
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
          'type': 'text',
          'isRead': false,
          'isDelivered': false,
          'timestamp': now,
          'sender': _uid,
          'replyTo': _replyingTo?.message,
          'replyToId': _replyingTo?.messageId,
          'isEdited': false,
          'isForwarded': false,
          'reactions': <String, dynamic>{},
          ..._expiryFields(),
        });
        await _updateChatIndex();
      }
      textFieldController.clear();
      await _setTyping(false);
      if (mounted) setState(() {
        _replyingTo = null;
        _editing = null;
      });
    } catch (error) {
      showConnectXErrorDialog(context, 'Message could not be sent. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }


  // Firestore is the source of truth for message delivery. The RTDB chat index
  // is secondary navigation metadata and must never turn a saved message into
  // a reported send failure.
  Future<void> _updateChatIndex({String? targetUid}) async {
    final peerUid = targetUid ?? user!.key;
    // A client may only update its own RTDB profile. The trusted VPS
    // Firestore listener updates both participants' chat indexes with Admin SDK.
    try {
      await ConnectXDatabase.instance.ref('PrivateUsers').child(_uid)
          .child('chats').child('personal').child(peerUid)
          .set(ServerValue.timestamp);
    } catch (error) {
      debugPrint('ConnectX local chat index update failed: $error');
    }
  }

  Future<void> _ensureCanMessage() async {
    // Respect an explicit block, but do not let an unavailable RTDB read prevent
    // Firestore messaging. RTDB stores auxiliary block metadata, not messages.
    try {
      final currentBlocked = await ConnectXDatabase.instance.ref('BlockLists').child(_uid).child(user!.key).get();
      if (currentBlocked.value == true) {
        throw Exception('This conversation is blocked. Unblock the user to send messages.');
      }
    } catch (error) {
      if (error is Exception &&
          error.toString().contains('This conversation is blocked')) rethrow;
      debugPrint('ConnectX local block check unavailable: $error');
    }
    try {
      final otherBlocked = await ConnectXDatabase.instance.ref('BlockLists').child(user!.key).child(_uid).get();
      if (otherBlocked.value == true) {
        throw Exception('This conversation is blocked. The other user has blocked you.');
      }
    } catch (error) {
      if (error is Exception &&
          error.toString().contains('This conversation is blocked')) rethrow;
      debugPrint('ConnectX peer block check unavailable: $error');
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
    bool isViewOnce = false,
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
          'isDelivered': false,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'sender': _uid,
      'isEdited': false,
      'isForwarded': false,
      'isViewOnce': isViewOnce,
      'viewedBy': <String, dynamic>{},
      'reactions': <String, dynamic>{},
      ..._expiryFields(),
    });
    await _updateChatIndex();
  }

  Future<void> _uploadBytes({
    required List<int> bytes,
    required String fileName,
    required String contentType,
    required String type,
  }) async {
    if (bytes.isEmpty) return;
    if (bytes.length > 25 * 1024 * 1024) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum attachment size is 25 MB.')),
      );
      return;
    }
    if (mounted) setState(() => _sending = true);
    try {
      await _ensureCanMessage();
      final url = await ChatStorage.upload(
        conversationId: assignUsers(_uid, user!.key),
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
        contentType: contentType,
        viewOnce: _sendViewOnce,
      );
      await _sendStructuredMessage(
        type: type,
        text: fileName,
        mediaUrl: url,
        fileName: fileName,
        isViewOnce: _sendViewOnce,
      );
      if (mounted && _sendViewOnce) setState(() => _sendViewOnce = false);
    } catch (error) {
      showConnectXErrorDialog(context, 'Media upload failed. Check your connection and try again.');
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
      showConnectXErrorDialog(context, 'Media could not be selected. Please try again.');
    }
  }

  Future<void> _sendSticker() async {
    const stickers = ['😀','😂','🥰','😍','🤔','😎','😭','🔥','🎉','❤️','👍','🙏','💯','🤝','🚀','🌟','🎂','☕','🌈','🐱','🐶','🌻','⚽','🎮'];
    final sticker = await showModalBottomSheet<String>(context: context, builder: (context) => SafeArea(
      child: Padding(padding: const EdgeInsets.all(12), child: GridView.count(
        shrinkWrap: true, crossAxisCount: 4, children: stickers.map((value) => InkWell(
          onTap: () => Navigator.pop(context, value),
          child: Center(child: Text(value, style: const TextStyle(fontSize: 34))),
        )).toList(),
      )),
    ));
    if (sticker != null) {
      await _sendStructuredMessage(type: 'sticker', text: sticker);
    }
  }

  Future<void> _pickGif() async {
    final selected = await ConnectXGifPicker.show(context);
    if (selected == null || !mounted || _sending) return;
    setState(() => _sending = true);
    try {
      await _ensureCanMessage();
      final response = await http.get(Uri.parse(selected.url))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw Exception('GIF download failed');
      }
      if (response.bodyBytes.length > 25 * 1024 * 1024) {
        throw Exception('GIF is larger than 25 MB');
      }
      final mediaUrl = await ChatStorage.upload(
        conversationId: assignUsers(_uid, user!.key),
        fileName: 'connectx_gif_${DateTime.now().millisecondsSinceEpoch}.gif',
        bytes: response.bodyBytes,
        contentType: 'image/gif',
        viewOnce: false,
      );
      await _sendStructuredMessage(
        type: 'gif',
        text: selected.attribution,
        mediaUrl: mediaUrl,
        fileName: selected.title,
      );
    } catch (error) {
      if (mounted) showConnectXErrorDialog(
        context, 'GIF could not be sent. Please try another GIF or check your connection.',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) {
      showConnectXErrorDialog(context, 'Could not read this file. Please select it again.');
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
      showConnectXErrorDialog(context, 'Location could not be shared. Check location permission and try again.');
    }
  }

  Future<void> _shareContact() async {
    try {
      // Ask only for read access. Nothing is uploaded until the user chooses
      // one contact and explicitly taps Send.
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        if (mounted) showConnectXErrorDialog(
          context, 'Contacts permission is needed to choose a contact. You can allow it in app settings.',
        );
        return;
      }
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
      if (!mounted) return;
      final selected = await showModalBottomSheet<Contact>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (sheetContext) => _ConnectXContactPicker(contacts: contacts),
      );
      if (selected == null || !mounted) return;
      final name = selected.displayName.trim();
      final phones = selected.phones
          .map((phone) => phone.number.trim())
          .where((phone) => phone.isNotEmpty)
          .toSet()
          .toList();
      if (name.isEmpty || phones.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This contact has no phone number to share.')),
        );
        return;
      }
      final phone = phones.length == 1 ? phones.first : await showModalBottomSheet<String>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(title: Text('Choose phone number')),
            ...phones.map((number) => ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: Text(number),
              onTap: () => Navigator.pop(sheetContext, number),
            )),
          ]),
        ),
      );
      if (phone == null || phone.isEmpty) return;
      if (mounted) setState(() => _sending = true);
      try {
        await _sendStructuredMessage(
          type: 'contact',
          text: '$name • $phone',
          contactName: name,
          contactPhone: phone,
        );
      } finally {
        if (mounted) setState(() => _sending = false);
      }
    } catch (error) {
      if (mounted) showConnectXErrorDialog(
        context, 'Contacts could not be loaded. Check permission and try again.',
      );
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_sending) return;
    if (!_recording) {
      final allowed = await _recorder.hasPermission();
      if (!allowed) {
        if (mounted) showConnectXErrorDialog(
          context, 'Microphone permission is required to record a voice message.',
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
    final ref = ConnectXDatabase.instance.ref('PrivateUsers').child(_uid)
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

  Future<void> _startCall({required bool video}) async {
    final callId = FirebaseFirestore.instance.collection('calls').doc().id;
    await Navigator.of(context).pushNamed('/call', arguments: {
      'callId': callId,
      'peerUid': user!.key,
      'peerName': user!.name,
      'isCaller': true,
      'isVideo': video,
    });
  }

  Future<void> _showStarredMessages() async {
    final snap = await ConnectXDatabase.instance.ref('PrivateUsers').child(_uid)
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
      builder: (context) => SafeArea(child: SizedBox(height: (MediaQuery.of(context).size.height * .68).clamp(280.0, 520.0).toDouble(),
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
    final ref = ConnectXDatabase.instance.ref('BlockLists').child(_uid).child(user!.key);
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
          if (!message.isViewOnce)
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
    if (message.isViewOnce) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('View-once media cannot be forwarded.')),
      );
      return;
    }
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
      'type': message.type,
      'mediaUrl': message.mediaUrl,
      'fileName': message.fileName,
      'latitude': message.latitude,
      'longitude': message.longitude,
      'contactName': message.contactName,
      'contactPhone': message.contactPhone,
      'isRead': false,
          'isDelivered': false,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'sender': _uid,
      'isForwarded': true,
      'isEdited': false,
      'reactions': <String, dynamic>{},
    });
    await _updateChatIndex(targetUid: target.key);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Forwarded to ${target.name}')));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final currentUser = FirebaseAuth.instance.currentUser!;
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0B141B) : const Color(0xFFEFEAE2),
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
          GestureDetector(onTap: _openContactInfo, child: CircleAvatar(
            radius: 20,
            backgroundImage: user!.photoUrl.isNotEmpty ? NetworkImage(user!.photoUrl) : null,
            child: user!.photoUrl.isEmpty ? Text(user!.username.isEmpty ? 'C' : user!.username[0].toUpperCase()) : null,
          )),
          const SizedBox(width: 10),
          Expanded(child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openContactInfo,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
              Text(_remoteTyping ? 'typing…' : (user!.online ? 'online' : 'last seen recently'),
                style: const TextStyle(fontSize: 11)),
            ]),
          )),
        ]),
        actions: [
          IconButton(tooltip: 'Voice call', icon: const Icon(Icons.call_outlined),
            onPressed: () => _startCall(video: false)),
          IconButton(tooltip: 'Video call', icon: const Icon(Icons.videocam_outlined),
            onPressed: () => _startCall(video: true)),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'starred') _showStarredMessages();
              if (value == 'block') _blockOrUnblockUser();
              if (value == 'report') _reportUser();
              if (value == 'disappearing') _setDisappearingSetting();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'starred', child: Text('Starred messages')),
              PopupMenuItem(value: 'block', child: Text('Block / unblock user')),
              PopupMenuItem(value: 'report', child: Text('Report user')),
              PopupMenuItem(value: 'disappearing', child: Text('Disappearing messages')),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: _wallpaperUrl == null ? _wallpaperColor(_wallpaperId, Theme.of(context).brightness == Brightness.dark) : null,
          image: _wallpaperUrl == null ? null : DecorationImage(image: NetworkImage(_wallpaperUrl!), fit: BoxFit.cover),
        ),
        child: CustomPaint(
        painter: _ChatWallpaperPainter(dark: Theme.of(context).brightness == Brightness.dark),
        child: Column(children: [
        Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _messageStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Center(child: Text('Messages are temporarily unavailable. Check your connection and try again.'));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snapshot.data!.docs.where((doc) {
              final expiry = doc.data()['expiresAt'];
              return expiry == null || (expiry is num && expiry.toInt() > DateTime.now().millisecondsSinceEpoch);
            }).toList();
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
                    messageRef: docs[index].reference,
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
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
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
                if (value == 'poll') _createPoll();
                if (value == 'sticker') _sendSticker();
                if (value == 'gif') _pickGif();
                if (value == 'view_once') setState(() => _sendViewOnce = !_sendViewOnce);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'image', child: ListTile(leading: Icon(Icons.photo), title: Text('Photo'))),
                PopupMenuItem(value: 'video', child: ListTile(leading: Icon(Icons.videocam), title: Text('Video'))),
                PopupMenuItem(value: 'document', child: ListTile(leading: Icon(Icons.insert_drive_file), title: Text('Document'))),
                PopupMenuItem(value: 'location', child: ListTile(leading: Icon(Icons.location_on), title: Text('Location'))),
                PopupMenuItem(value: 'contact', child: ListTile(leading: Icon(Icons.contact_page), title: Text('Contact'))),
                PopupMenuItem(value: 'poll', child: ListTile(leading: Icon(Icons.poll_outlined), title: Text('Poll'))),
                PopupMenuItem(value: 'sticker', child: ListTile(leading: Icon(Icons.emoji_emotions_outlined), title: Text('Sticker'))),
                PopupMenuItem(value: 'gif', child: ListTile(leading: Icon(Icons.gif_box_outlined), title: Text('GIF'))),
                PopupMenuItem(value: 'view_once', child: ListTile(leading: Icon(Icons.looks_one_outlined), title: Text('Toggle view once'))),
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
                hintText: _recording ? 'Recording voice note…' : _sendViewOnce ? 'View-once media mode' : 'Message',
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.4)),
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
      )),
    );
  }

  @override
  void dispose() {
    _expiryRefreshTimer?.cancel();
    _typingTimer?.cancel();
    _typingSubscription?.cancel();
    _readReceiptSubscription?.cancel();
    _recorder.dispose();
    _setTyping(false);
    textFieldController.dispose();
    scrollController.dispose();
    super.dispose();
  }
}



/// WhatsApp-style local contact picker. Only the selected contact is shared.
class _ConnectXContactPicker extends StatefulWidget {
  final List<Contact> contacts;
  const _ConnectXContactPicker({required this.contacts});

  @override
  State<_ConnectXContactPicker> createState() => _ConnectXContactPickerState();
}

class _ConnectXContactPickerState extends State<_ConnectXContactPicker> {
  final TextEditingController _search = TextEditingController();
  Contact? _selected;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final contacts = widget.contacts.where((contact) {
      final name = contact.displayName.toLowerCase();
      final phones = contact.phones.map((phone) => phone.number).join(' ');
      return query.isEmpty || name.contains(query) || phones.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .82,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            child: Row(children: [
              const Expanded(child: Text('Share contact',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
              IconButton(onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search contacts',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: contacts.isEmpty
                ? const Center(child: Text('No contacts found'))
                : ListView.builder(
                    itemCount: contacts.length,
                    itemBuilder: (context, index) {
                      final contact = contacts[index];
                      final numbers = contact.phones.map((p) => p.number)
                          .where((p) => p.trim().isNotEmpty).toSet().toList();
                      final chosen = _selected?.id == contact.id;
                      final first = contact.displayName.trim().isEmpty
                          ? '?' : contact.displayName.trim().characters.first.toUpperCase();
                      return ListTile(
                        selected: chosen,
                        leading: CircleAvatar(child: Text(first)),
                        title: Text(contact.displayName.isEmpty ? 'Unnamed contact' : contact.displayName),
                        subtitle: Text(numbers.isEmpty ? 'No phone number' : numbers.join(' · '),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: chosen ? const Icon(Icons.check_circle, color: Color(0xFF008069))
                            : null,
                        onTap: numbers.isEmpty ? null : () => setState(() => _selected = contact),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _selected == null ? null : () => Navigator.pop(context, _selected),
                icon: const Icon(Icons.send_rounded),
                label: Text(_selected == null ? 'Select a contact' : 'Send contact'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

Color _wallpaperColor(String id, bool dark) {
  const colors = [0xFFEFEAE2,0xFFDCEFE7,0xFFE1E9F8,0xFFF8E2E2,0xFFF5E9CF,0xFFE8DDF4,0xFFD9E8EA,0xFFF2E3D3,0xFF24323A,0xFF172B4D,0xFF283A2F,0xFF402D35,0xFF3A3150,0xFF263B48,0xFF4A3B2D,0xFF20252B,0xFFF0F1F3,0xFFE3F2FD,0xFFFCE4EC,0xFFE8F5E9];
  final index = int.tryParse(id);
  if (index == null || index < 0 || index >= colors.length) return dark ? const Color(0xFF0B141B) : const Color(0xFFEFEAE2);
  return Color(colors[index]);
}

class _ChatWallpaperPainter extends CustomPainter {
  final bool dark;
  const _ChatWallpaperPainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (dark ? const Color(0xFF9FB2B8) : const Color(0xFF7B8B82)).withOpacity(dark ? .075 : .12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15;
    const step = 76.0;
    var row = 0;
    for (double y = -step; y < size.height + step; y += step) {
      final shift = row.isEven ? 0.0 : step / 2;
      for (double x = -step + shift; x < size.width + step; x += step) {
        final center = Offset(x, y);
        canvas.drawCircle(center, 9, paint);
        final wave = Path()
          ..moveTo(x - 15, y + 20)
          ..cubicTo(x - 5, y + 8, x + 5, y + 32, x + 16, y + 18);
        canvas.drawPath(wave, paint);
        canvas.drawArc(
          Rect.fromCircle(center: Offset(x + 22, y - 19), radius: 7),
          .4, 4.5, false, paint,
        );
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(covariant _ChatWallpaperPainter oldDelegate) => oldDelegate.dark != dark;
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
