import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../app_navigator.dart';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _chatChannel = AndroidNotificationChannel(
  'connectx_chat_messages',
  'ConnectX messages',
  description: 'Notifications for new ConnectX messages',
  importance: Importance.high,
);

@pragma('vm:entry-point')
Future<void> connectXBackgroundMessageHandler(RemoteMessage message) async {
  // Android displays notification payloads automatically in the background.
}

class NotificationService {
  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<RemoteMessage>? _openedSubscription;

  static Future<void> initialize() async {
    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    } catch (_) {
      // Do not prevent sign-in if notification permission is unavailable.
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/logo');
    const settings = InitializationSettings(android: androidSettings);
    try {
      await _localNotifications.initialize(settings, onDidReceiveNotificationResponse: (response) async {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try { openIncomingCall(Map<String, dynamic>.from(jsonDecode(payload) as Map)); } catch (_) {}
      });
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_chatChannel);
    } catch (_) {
      // Chat and authentication remain usable if local notifications fail.
    }

    FirebaseMessaging.onBackgroundMessage(connectXBackgroundMessageHandler);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await _saveToken(user.uid, await messaging.getToken());
      } catch (_) {
        // Token registration can retry when FCM refreshes the token.
      }
    }

    _tokenSubscription?.cancel();
    _tokenSubscription = messaging.onTokenRefresh.listen((token) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        _saveToken(uid, token).catchError((_) {});
      }
    });

    _foregroundSubscription?.cancel();
    _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) async {
      final notification = message.notification;
      if (notification == null) return;
      try {
        await _localNotifications.show(
          message.hashCode,
          notification.title ?? 'ConnectX',
          notification.body ?? 'New message',
          NotificationDetails(
            android: AndroidNotificationDetails(
              _chatChannel.id,
              _chatChannel.name,
              channelDescription: _chatChannel.description,
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          payload: message.data['type'] == 'incoming_call' ? jsonEncode({
            'callId': message.data['callId'],
            'peerUid': message.data['callerUid'],
            'peerName': message.data['callerName'] ?? 'ConnectX user',
            'isCaller': false,
            'isVideo': message.data['callType'] == 'video',
          }) : null,
        );
      } catch (_) {
        // Ignore display failures; do not interrupt the active chat.
      }
    });

    _openedSubscription?.cancel();
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) _handleOpenedMessage(initialMessage);
  }

  static void _handleOpenedMessage(RemoteMessage message) {
    if (message.data['type'] != 'incoming_call') return;
    openIncomingCall({
      'callId': message.data['callId'],
      'peerUid': message.data['callerUid'],
      'peerName': message.data['callerName'] ?? 'ConnectX user',
      'isCaller': false,
      'isVideo': message.data['callType'] == 'video',
    });
  }

  static Future<void> _saveToken(String uid, String? token) async {
    if (token == null || token.isEmpty) return;
    await FirebaseDatabase.instance.ref('Users').child(uid).update({
      'fcmToken': token,
    });
  }

  static Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
  }
}
