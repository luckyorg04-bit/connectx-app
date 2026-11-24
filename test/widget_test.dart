import 'package:flutter_test/flutter_test.dart';
import 'package:connectx/chat_screen.dart';
import 'package:connectx/login.dart';
import 'package:connectx/models/message.dart';

void main() {
  test('conversation IDs are stable regardless of participant order', () {
    expect(assignUsers('user-b', 'user-a'), 'user-a,user-b');
    expect(assignUsers('user-a', 'user-b'), 'user-a,user-b');
  });

  test('message model preserves media, reply and read state', () {
    final original = Message(
      message: 'photo.jpg',
      isRead: true,
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
    expect(restored.sender, original.sender);
    expect(restored.messageId, original.messageId);
    expect(restored.replyToId, original.replyToId);
    expect(restored.type, 'image');
    expect(restored.mediaUrl, original.mediaUrl);
    expect(restored.fileName, original.fileName);
    expect(restored.isForwarded, isTrue);
    expect(restored.reactions['receiver-1'], '❤️');
  });

  test('email validation rejects malformed addresses', () {
    expect(validateEmail('person@example.com'), isNull);
    expect(validateEmail('not-an-email'), isNotNull);
    expect(validateEmail(''), isNotNull);
  });

  test('username validation enforces supported format', () {
    expect(validateUsername('lucky_01'), isNull);
    expect(validateUsername('1lucky'), isNotNull);
    expect(validateUsername('ab'), isNotNull);
    expect(validateUsername('bad..name'), isNotNull);
  });
}
