import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({Key? key}) : super(key: key);

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  late String _groupId;
  late String _groupName;
  bool _initialized = false;

  CollectionReference<Map<String, dynamic>> get _messages =>
      FirebaseFirestore.instance.collection('groupChats')
          .doc(_groupId).collection('messages');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final args = ModalRoute.of(context)!.settings.arguments as Map;
    _groupId = args['groupId'].toString();
    _groupName = args['name'].toString();
    _initialized = true;
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _messages.add({
        'text': text,
        'senderUid': FirebaseAuth.instance.currentUser!.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _controller.clear();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Message not sent: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_groupName),
          const Text('Group conversation', style: TextStyle(fontSize: 11)),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _messages.orderBy('createdAt', descending: true).limit(100).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text('Unable to load group messages: ${snapshot.error}'));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              if (snapshot.data!.docs.isEmpty) return const Center(child: Text('No messages yet. Start the group conversation.'));
              return ListView.builder(
                reverse: true,
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  final data = snapshot.data!.docs[index].data();
                  final mine = data['senderUid'] == uid;
                  final created = data['createdAt'] as Timestamp?;
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      padding: const EdgeInsets.all(11),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .8),
                      decoration: BoxDecoration(
                        color: mine ? const Color(0xFFD9FDD3) : Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text((data['text'] ?? '').toString(),
                          style: const TextStyle(color: Color(0xFF111B21), fontSize: 16)),
                        if (created != null)
                          Text(TimeOfDay.fromDateTime(created.toDate()).format(context),
                            style: const TextStyle(fontSize: 10, color: Colors.black54)),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(hintText: 'Message group'),
              )),
              const SizedBox(width: 8),
              CircleAvatar(
                child: IconButton(
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, color: Colors.white),
                  onPressed: _sending ? null : _send,
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
