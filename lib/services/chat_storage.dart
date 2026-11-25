import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ChatStorage {
  static const String _uploadEndpoint = 'https://connecttx.duckdns.org/api/upload';

  static Future<String> upload({
    required String conversationId,
    required String fileName,
    required List<int> bytes,
    required String contentType,
    bool viewOnce = false,
    String resourceType = 'message',
    List<String>? audienceUids,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Please sign in before uploading media.');
    final idToken = await user.getIdToken();
    if (idToken.isEmpty) throw Exception('Could not get Firebase sign-in token.');

    final request = http.MultipartRequest('POST', Uri.parse(_uploadEndpoint));
    request.headers['Authorization'] = 'Bearer $idToken';
    request.fields['conversationId'] = conversationId;
    request.fields['contentType'] = contentType;
    request.fields['viewOnce'] = viewOnce ? 'true' : 'false';
    request.fields['resourceType'] = resourceType;
    if (audienceUids != null) request.fields['audienceUids'] = jsonEncode(audienceUids);
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));

    final streamed = await request.send().timeout(const Duration(seconds: 120));
    final response = await http.Response.fromStream(streamed);
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Upload server returned an invalid response.');
    }
    if (response.statusCode != 201 || payload['success'] != true || payload['url'] == null) {
      throw Exception(payload['error']?.toString() ?? 'Upload failed.');
    }
    return payload['url'].toString();
  }
}
