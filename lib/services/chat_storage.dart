import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class ChatStorage {
  static Future<String> upload({
    required String conversationId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path = 'chat_media/$conversationId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final ref = FirebaseStorage.instance.ref(path);
    final task = await ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    return task.ref.getDownloadURL();
  }
}
