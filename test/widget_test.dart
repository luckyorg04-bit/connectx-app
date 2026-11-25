import 'package:flutter_test/flutter_test.dart';
import 'package:connectx/chat_screen.dart';
import 'package:connectx/login.dart';
import 'package:connectx/models/message.dart';
import 'package:connectx/models/user.dart';
import 'package:connectx/services/phone_lookup_service.dart';

void main() {
  test('conversation IDs are stable regardless of participant order', () {
    expect(assignUsers('user-b', 'user-a'), 'user-a,user-b');
    expect(assignUsers('user-a', 'user-b'), 'user-a,user-b');
  });

  test('message model preserves media, reply and read state', () {
    final original = Message(
      message: 'photo.jpg',
      isRead: true,
      isDelivered: true,
      timestamp: 1732440000000,
      sender: 'sender-1',
      messageId: 'message-1',
      replyTo: 'hello',
      replyToId: 'message-0',
      type: 'image',
      mediaUrl: 'https://example.test/photo.jpg',
      fileName: 'photo.jpg',
      isForwarded: true,
      reactions: const {'receiver-1': '❤️'},
    );

    final restored = Message.fromJson(original.toJson());

    expect(restored.message, original.message);
    expect(restored.isRead, isTrue);
    expect(restored.isDelivered, isTrue);
    expect(restored.sender, original.sender);
    expect(restored.messageId, original.messageId);
    expect(restored.replyToId, original.replyToId);
    expect(restored.type, 'image');
    expect(restored.mediaUrl, original.mediaUrl);
    expect(restored.fileName, original.fileName);
    expect(restored.isForwarded, isTrue);
    expect(restored.reactions['receiver-1'], '❤️');
  });

  test('delivery receipt is separate from read receipt', () {
    final original = Message(
      message: 'Hello',
      isRead: false,
      isDelivered: true,
      timestamp: 1732440000000,
      sender: 'sender-1',
    );
    final restored = Message.fromJson(original.toJson());
    expect(restored.isDelivered, isTrue);
    expect(restored.isRead, isFalse);
  });

  test('email validation rejects malformed addresses', () {
    expect(validateEmail('person@example.com'), isNull);
    expect(validateEmail('not-an-email'), isNotNull);
    expect(validateEmail(''), isNotNull);
  });

  test('public user JSON never includes private FCM tokens', () {
    final user = User1(
      name: 'Lucky',
      username: 'lucky_01',
      key: 'user-1',
      online: true,
      lastSeen: 1732440000000,
      bio: 'Hello',
      photoUrl: '',
    );

    expect(user.toJson().keys.toSet(), {
      'name', 'username', 'key', 'online', 'lastSeen', 'photoUrl', 'bio',
    });
    expect(user.toJson().containsKey('fcmToken'), isFalse);
  });

  test('date separators detect a new calendar day', () {
    final first = DateTime(2026, 11, 24, 23, 59).millisecondsSinceEpoch;
    final next = DateTime(2026, 11, 25, 0, 1).millisecondsSinceEpoch;
    expect(isNewDay(false, first, next), isTrue);
    expect(isNewDay(false, first, first + 30000), isFalse);
  });

  test('phone validation accepts international phone numbers without OTP', () {
    expect(validatePhone('+91 98765 43210'), isNull);
    expect(validatePhone('9876'), isNotNull);
    expect(PhoneLookupService.normalize('+91 98765 43210'), '919876543210');
    expect(PhoneLookupService.normalize('91-98765-43210'), '919876543210');
    expect(
      () => PhoneLookupService.normalize('1234'),
      throwsA(isA<FormatException>()),
    );
  });

  test('username validation enforces supported format', () {
    expect(validateUsername('lucky_01'), isNull);
    expect(validateUsername('1lucky'), isNotNull);
    expect(validateUsername('ab'), isNotNull);
    expect(validateUsername('bad..name'), isNotNull);
  });
}
