import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class ProfileStorage {
  static const String _baseUrl = 'https://connecttx.duckdns.org';

  static Future<String> upload(XFile file) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Please sign in before changing your profile photo.');
    final token = await user.getIdToken();
    if (token.isEmpty) throw Exception('Could not get Firebase sign-in token.');

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/api/profile-photo'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath(
      'file',
      file.path,
      filename: file.name,
    ));
    final streamed = await request.send().timeout(const Duration(seconds: 120));
    final response = await http.Response.fromStream(streamed);
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Profile server returned an invalid response.');
    }
    if (response.statusCode != 201 || payload['success'] != true ||
        payload['url'] is! String) {
      throw Exception(payload['error']?.toString() ?? 'Profile photo upload failed.');
    }
    return payload['url'].toString();
  }

  static Future<void> delete(String photoUrl) async {
    final uri = Uri.tryParse(photoUrl);
    if (uri == null || uri.host != 'connecttx.duckdns.org' ||
        !uri.path.startsWith('/media/')) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Please sign in before deleting your profile photo.');
    final token = await user.getIdToken();
    if (token.isEmpty) throw Exception('Could not get Firebase sign-in token.');
    final filename = Uri.decodeComponent(uri.pathSegments.last);
    final response = await http.delete(
      Uri.parse('$_baseUrl/api/profile-photo/${Uri.encodeComponent(filename)}'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode == 404) return;
    if (response.statusCode != 200) {
      try {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(payload['error']?.toString() ?? 'Profile photo deletion failed.');
      } catch (error) {
        if (error is Exception) rethrow;
        throw Exception('Profile photo deletion failed.');
      }
    }
  }
}
