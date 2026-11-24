import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class RtcConfig {
  static const String _endpoint = 'https://connecttx.duckdns.org/api/turn-credentials';

  static Future<Map<String, dynamic>> load() async {
    final iceServers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null || token.isEmpty) return {'iceServers': iceServers};
      final response = await http.get(
        Uri.parse(_endpoint),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return {'iceServers': iceServers};
      final body = jsonDecode(response.body);
      final configured = body is Map ? body['iceServers'] : null;
      if (configured is List && configured.isNotEmpty) {
        iceServers.addAll(configured.whereType<Map>().map(
          (entry) => Map<String, dynamic>.from(entry),
        ));
      }
    } catch (_) {
      // STUN remains available when the TURN service is not configured.
    }
    return {'iceServers': iceServers};
  }
}
