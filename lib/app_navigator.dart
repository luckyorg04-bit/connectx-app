import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/database_service.dart';
import 'models/user.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
Map<String, dynamic>? pendingCallArguments;
String? pendingDirectChatUid;
String? pendingGroupChatId;

void openIncomingCall(Map<String, dynamic> arguments) {
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) {
    pendingCallArguments = arguments;
  } else {
    navigator.pushNamed(arguments['isGroupCall'] == true ? '/group-call' : '/call', arguments: arguments);
  }
}

Future<void> openDirectChat(String peerUid) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || peerUid.isEmpty || peerUid == uid) return;
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) {
    pendingDirectChatUid = peerUid;
    return;
  }
  try {
    final snapshot = await ConnectXDatabase.instance.ref('PublicUsers').child(peerUid).get();
    if (!snapshot.exists || appNavigatorKey.currentState == null) return;
    final contact = User1.getFromSnapshot(snapshot);
    appNavigatorKey.currentState!.pushNamed('/chat', arguments: contact);
  } catch (error) {
    debugPrint('ConnectX could not open direct chat from notification: $error');
  }
}

Future<void> openDirectChatFromConversation(String conversationId) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || conversationId.isEmpty) return;
  final participants = conversationId.split(',');
  if (participants.length != 2 || !participants.contains(uid)) return;
  final peerUid = participants.firstWhere((id) => id != uid);
  if (peerUid.isEmpty) return;
  await openDirectChat(peerUid);
}

Future<void> openGroupChatFromNotification(String groupId) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || groupId.isEmpty) return;
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) {
    pendingGroupChatId = groupId;
    return;
  }
  try {
    final snapshot = await FirebaseFirestore.instance.collection('groupChats').doc(groupId).get();
    if (!snapshot.exists || appNavigatorKey.currentState == null) return;
    final data = snapshot.data() ?? <String, dynamic>{};
    final members = List<String>.from(data['memberUids'] ?? []);
    if (!members.contains(uid)) return;
    appNavigatorKey.currentState!.pushNamed('/group', arguments: {
      'groupId': groupId,
      'name': (data['name'] ?? 'Group').toString(),
    });
  } catch (error) {
    debugPrint('ConnectX could not open group chat from notification: $error');
  }
}
