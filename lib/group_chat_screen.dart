import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectx/main_screen.dart' show users;
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

  Future<void> _manageGroup() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseFirestore.instance.collection('groupChats').doc(_groupId);
    final snap = await ref.get();
    if (!snap.exists || !mounted) return;
    final data = snap.data()!;
    final admins = List<String>.from(data['adminUids'] ?? [data['createdBy']]);
    if (!admins.contains(uid) && data['createdBy'] != uid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only group admins can manage members.')));
      return;
    }
    final members = List<String>.from(data['memberUids'] ?? []);
    final creator = (data['createdBy'] ?? '').toString();
    final selected = <String>{...members};
    final selectedAdmins = <String>{...admins, creator};
    final nameController = TextEditingController(text: (data['name'] ?? _groupName).toString());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Manage group'),
          content: SizedBox(width: double.maxFinite, height: 430, child: Column(children: [
            TextField(controller: nameController, maxLength: 40,
              decoration: const InputDecoration(labelText: 'Group name')),
            const Align(alignment: Alignment.centerLeft,
              child: Text('Members and admins', style: TextStyle(fontWeight: FontWeight.w600))),
            Expanded(child: ListView(children: users.where((u) => u.key != uid || selected.contains(uid)).map((person) {
              final isMember = selected.contains(person.key);
              return Column(children: [
                CheckboxListTile(
                  dense: true,
                  value: isMember,
                  title: Text(person.name),
                  subtitle: Text('@${person.username}'),
                  onChanged: person.key == creator ? null : (value) => setDialogState(() {
                    if (value == true) { selected.add(person.key); }
                    else { selected.remove(person.key); selectedAdmins.remove(person.key); }
                  }),
                ),
                if (isMember)
                  SwitchListTile(
                    dense: true,
                    title: const Text('Group admin'),
                    value: selectedAdmins.contains(person.key),
                    onChanged: person.key == creator ? null : (value) => setDialogState(() {
                      if (value) selectedAdmins.add(person.key);
                      else selectedAdmins.remove(person.key);
                    }),
                  ),
              ]);
            }).toList())),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    final newName = nameController.text.trim();
    nameController.dispose();
    if (confirmed != true || newName.isEmpty) return;
    selected.add(creator);
    selectedAdmins.add(creator);
    selected.add(uid);
    try {
      await ref.update({
        'name': newName,
        'memberUids': selected.toList(),
        'adminUids': selectedAdmins.where(selected.contains).toList(),
      });
      if (mounted) setState(() => _groupName = newName);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group settings updated.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update group: $error')));
    }
  }

  Future<void> _startGroupCall() async {
    final callType = await showModalBottomSheet<String>(context: context,
      builder: (c) => SafeArea(child: Wrap(children: [
        ListTile(leading: const Icon(Icons.call), title: const Text('Voice group call'),
          onTap: () => Navigator.pop(c, 'voice')),
        ListTile(leading: const Icon(Icons.videocam), title: const Text('Video group call'),
          onTap: () => Navigator.pop(c, 'video')),
      ])));
    if (callType == null || !mounted) return;
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final groupSnapshot = await FirebaseFirestore.instance.collection('groupChats').doc(_groupId).get();
      final groupData = groupSnapshot.data();
      final groupMembers = List<String>.from(groupData?['memberUids'] ?? []);
      if (!groupSnapshot.exists || !groupMembers.contains(uid)) {
        throw Exception('Only current group members can start a group call.');
      }
      final ref = FirebaseFirestore.instance.collection('groupCalls').doc();
      await ref.set({
        'groupId': _groupId,
        'groupName': _groupName,
        'groupMemberUids': groupMembers,
        'createdBy': uid,
        'participants': [uid],
        'activeUids': [uid],
        'type': callType,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      await Navigator.of(context).pushNamed('/group-call', arguments: {
        'callId': ref.id, 'groupId': _groupId, 'groupName': _groupName,
        'callType': callType, 'isCreator': true,
      });
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start group call: $error')),
      );
    }
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
        actions: [
          IconButton(tooltip: 'Start group call', icon: const Icon(Icons.video_call), onPressed: _startGroupCall),
          IconButton(tooltip: 'Manage group', icon: const Icon(Icons.group_outlined), onPressed: _manageGroup),
        ],
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_groupName),
          const Text('Group conversation', style: TextStyle(fontSize: 11)),
        ]),
      ),
      body: Column(children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('groupCalls')
            .where('groupId', isEqualTo: _groupId)
            .where('groupMemberUids', arrayContains: uid)
            .where('status', isEqualTo: 'active').snapshots(),
          builder: (context, calls) {
            if (!calls.hasData || calls.data!.docs.isEmpty) return const SizedBox.shrink();
            final activeCall = calls.data!.docs.first;
            final callData = activeCall.data();
            final participants = List<String>.from(callData['activeUids'] ?? []);
            if (participants.contains(uid)) return const SizedBox.shrink();
            return Material(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.groups_rounded),
                title: Text('${callData['type'] == 'video' ? 'Video' : 'Voice'} group call is active'),
                subtitle: Text('${participants.length} participant(s) in call'),
                trailing: FilledButton(
                  onPressed: () => Navigator.of(context).pushNamed('/group-call', arguments: {
                    'callId': activeCall.id, 'groupId': _groupId, 'groupName': _groupName,
                    'callType': callData['type'] ?? 'voice', 'isCreator': false,
                  }),
                  child: const Text('Join'),
                ),
              ),
            );
          },
        ),
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
