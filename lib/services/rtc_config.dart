import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class RtcConfig {
  static Map<String, dynamic>? _cachedConfig;
  static DateTime? _cachedAt;
  static const String _endpoint = 'https://connecttx.duckdns.org/api/turn-credentials';

  static Future<Map<String, dynamic>> load() async {
    final cachedAt = _cachedAt;
    if (_cachedConfig != null && cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 45)) {
      return _cachedConfig!;
    }
    final iceServers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null || token.isEmpty) {
        debugPrint('ConnectX TURN credentials unavailable: user is not authenticated; using STUN only.');
        return {'iceServers': iceServers};
      }
      final response = await http.get(
        Uri.parse(_endpoint),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        debugPrint('ConnectX TURN endpoint returned HTTP ${response.statusCode}; using STUN only.');
        return {'iceServers': iceServers};
      }
      final body = jsonDecode(response.body);
      final configured = body is Map ? body['iceServers'] : null;
      if (configured is List && configured.isNotEmpty) {
        iceServers.addAll(configured.whereType<Map>().map(
          (entry) => Map<String, dynamic>.from(entry),
        ));
        final hasTurn = configured.whereType<Map>().any((entry) {
          final urls = entry['urls'];
          if (urls is String) return urls.startsWith('turn:') || urls.startsWith('turns:');
          if (urls is List) return urls.whereType<String>().any((url) => url.startsWith('turn:') || url.startsWith('turns:'));
          return false;
        });
        if (!hasTurn) debugPrint('ConnectX TURN endpoint returned no TURN relay URL; calls may fail across mobile networks.');
      } else {
        debugPrint('ConnectX TURN endpoint returned no iceServers; using STUN only.');
      }
    } catch (error) {
      debugPrint('ConnectX TURN credential request failed: $error; using STUN only.');
    }
    _cachedConfig = {'iceServers': iceServers};
    _cachedAt = DateTime.now();
    return _cachedConfig!;
  }
}
