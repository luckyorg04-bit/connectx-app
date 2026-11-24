import 'package:connectx/main.dart';
import 'package:connectx/models/message.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../chat_screen.dart';
import '../models/user.dart';

class UserList extends StatefulWidget {
  final List<User1> users;
  final bool wantChats;
  final String filter;
  const UserList({super.key, required this.users, required this.wantChats, this.filter = 'All'});
  @override
  State<UserList> createState() => UserListState();
}

class UserListState extends State<UserList> {
  final Map<String, Message?> _latest = {};
  final Map<String, int> _unread = {};
  final Map<String, Map<String, dynamic>> _meta = {};
  final Set<String> _blockedUsers = <String>{};

  @override
  void initState() { super.initState(); _refresh(); }
  @override
  void didUpdateWidget(covariant UserList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.wantChats && oldWidget.users != widget.users) _refresh();
  }

  Future<void> _refresh() async {
    if (!widget.wantChats) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || widget.users.isEmpty) return;
    final latest = <String, Message?>{}, unread = <String, int>{};
    final metadata = <String, Map<String, dynamic>>{};
    final blockedSnapshot = await FirebaseDatabase.instance.ref('Users').child(uid).child('blockedUsers').get();
    final blocked = <String>{};
    if (blockedSnapshot.value is Map) {
      (blockedSnapshot.value as Map).forEach((key, value) {
        if (value == true) blocked.add(key.toString());
      });
    }
    await Future.wait(widget.users.map((contact) async {
      try {
        final snap = await FirebaseFirestore.instance.collection('messages')
          .doc(assignUsers(uid, contact.key)).collection('chats')
          .orderBy('timestamp', descending: true).limit(10).get();
        final list = snap.docs.map(Message.fromSnapshot).toList();
        latest[contact.key] = list.isEmpty ? null : list.first;
        unread[contact.key] = list.where((m) => !m.isRead && m.sender != uid).length;
      } catch (_) { latest[contact.key] = null; unread[contact.key] = 0; }
      try {
        final value = (await FirebaseDatabase.instance.ref('Users').child(uid)
          .child('chatMeta').child(contact.key).get()).value;
        metadata[contact.key] = value is Map ? Map<String, dynamic>.from(value) : {};
      } catch (_) { metadata[contact.key] = {}; }
    }));
    if (!mounted) return;
    setState(() { _latest..clear()..addAll(latest); _unread..clear()..addAll(unread); _meta..clear()..addAll(metadata); _blockedUsers..clear()..addAll(blocked); });
  }

  Future<void> _setMeta(User1 contact, String key, bool value) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseDatabase.instance.ref('Users').child(uid).child('chatMeta')
      .child(contact.key).child(key).set(value);
    if (mounted) setState(() { _meta[contact.key] = {...?_meta[contact.key], key: value}; });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final contacts = widget.users.where((c) {
      if (c.key == uid || _blockedUsers.contains(c.key)) return false;
      final meta = _meta[c.key] ?? const <String, dynamic>{};
      if (widget.filter == 'Archived') return meta['archived'] == true;
      if (meta['archived'] == true) return false;
      if (widget.filter == 'Unread') return (_unread[c.key] ?? 0) > 0;
      if (widget.filter == 'Favorites') return meta['favorite'] == true;
      if (widget.filter == 'Groups') return false;
      return true;
    }).toList();
    contacts.sort((a,b) {
      final ap = _meta[a.key]?['pinned'] == true, bp = _meta[b.key]?['pinned'] == true;
      if (ap != bp) return ap ? -1 : 1;
      return (_latest[b.key]?.timestamp ?? 0).compareTo(_latest[a.key]?.timestamp ?? 0);
    });
    if (contacts.isEmpty) {
      final message = widget.filter == 'Groups' ? 'Group chats will be available in Part 2.'
        : widget.filter == 'Unread' ? 'No unread conversations.'
        : widget.filter == 'Favorites' ? 'No favorites yet. Add a chat using its menu.'
        : widget.filter == 'Archived' ? 'No archived conversations.'
        : 'No chats yet. Start a conversation.';
      return Center(child: Padding(padding: const EdgeInsets.all(28),
        child: Text(message, textAlign: TextAlign.center)));
    }
    return ListView.builder(itemCount: contacts.length, physics: const ClampingScrollPhysics(),
      itemBuilder: (context,index) {
        final contact = contacts[index];
        final meta = _meta[contact.key] ?? <String, dynamic>{};
        final last = _latest[contact.key], count = _unread[contact.key] ?? 0;
        final preview = last?.message ?? (widget.wantChats ? 'Tap to start chatting' : '@${contact.username}');
        final time = last == null ? '' : DateFormat('h:mm a').format(DateTime.fromMillisecondsSinceEpoch(last.timestamp));
        return InkWell(onTap: () async {
          currentRoute='/chat';
          await Navigator.of(context).pushNamed('/chat', arguments: contact);
          if (mounted) _refresh();
        }, child: SizedBox(height:76, child: Row(children:[
          const SizedBox(width:12),
          CircleAvatar(radius:25, backgroundImage: contact.photoUrl.isNotEmpty ? NetworkImage(contact.photoUrl) : null,
            child: contact.photoUrl.isEmpty ? Text(contact.username.isEmpty ? 'C' : contact.username[0].toUpperCase()) : null),
          const SizedBox(width:12),
          Expanded(child: Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[
              Flexible(child:Text(contact.name,maxLines:1,overflow:TextOverflow.ellipsis,
                style:TextStyle(fontSize:16,fontWeight:count>0?FontWeight.w700:FontWeight.w600))),
              if(meta['pinned']==true) const Icon(Icons.push_pin,size:13,color:Colors.grey),
              if(meta['favorite']==true) const Icon(Icons.star,size:13,color:Colors.amber),
            ]),
            const SizedBox(height:5),
            Text(preview,maxLines:1,overflow:TextOverflow.ellipsis,
              style:TextStyle(fontSize:13,fontWeight:count>0?FontWeight.w600:FontWeight.w400,
                color:count>0?Theme.of(context).colorScheme.onSurface:Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
          if(widget.wantChats) Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[
            if(time.isNotEmpty) Text(time,style:TextStyle(fontSize:11,color:count>0?const Color(0xFF25D366):Theme.of(context).colorScheme.onSurfaceVariant)),
            if(count>0) Container(margin:const EdgeInsets.only(top:5),padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
              decoration:const BoxDecoration(color:Color(0xFF25D366),shape:BoxShape.circle),
              child:Text(count>99?'99+':'$count',style:const TextStyle(color:Colors.white,fontSize:10))),
          ]),
          if(widget.wantChats) PopupMenuButton<String>(onSelected:(v){
            if(v=='favorite') _setMeta(contact,'favorite',meta['favorite']!=true);
            if(v=='pin') _setMeta(contact,'pinned',meta['pinned']!=true);
            if(v=='archive') _setMeta(contact,'archived',meta['archived']!=true);
            if(v=='mute') _setMeta(contact,'muted',meta['muted']!=true);
          },itemBuilder:(context)=>[
            PopupMenuItem(value:'favorite',child:Text(meta['favorite']==true?'Remove favorite':'Add to favorites')),
            PopupMenuItem(value:'pin',child:Text(meta['pinned']==true?'Unpin chat':'Pin chat')),
            PopupMenuItem(value:'archive',child:Text(meta['archived']==true?'Unarchive chat':'Archive chat')),
            PopupMenuItem(value:'mute',child:Text(meta['muted']==true?'Unmute chat':'Mute chat')),
          ]),
        ])));
      });
  }
}
