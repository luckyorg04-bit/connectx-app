import 'package:flutter_test/flutter_test.dart';
import 'package:connectx/chat_screen.dart';

void main() {
  test('conversation IDs are stable regardless of participant order', () {
    expect(assignUsers('user-b', 'user-a'), 'user-a,user-b');
    expect(assignUsers('user-a', 'user-b'), 'user-a,user-b');
  });
}
