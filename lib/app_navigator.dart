import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'models/user.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
Map<String, dynamic>? pendingCallArguments;
String? pendingDirectChatUid;

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
    final snapshot = await FirebaseDatabase.instance.ref('Users').child(peerUid).get();
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
  String? peerUid;
  for (final id in conversationId.split(',')) {
    if (id.isNotEmpty && id != uid) { peerUid = id; break; }
  }
  if (peerUid == null || peerUid.isEmpty) return;
  await openDirectChat(peerUid);
}
