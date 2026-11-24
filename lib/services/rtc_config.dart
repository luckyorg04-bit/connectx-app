import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class RtcConfig {
  static Map<String, dynamic>? _cachedConfig;
  static DateTime? _cachedAt;
  static const String _endpoint = 'https://connecttx.duckdns.org/api/turn-credentials';

  static bool _containsTurnServer(List<dynamic> servers) {
    return servers.whereType<Map>().any((entry) {
      final urls = entry['urls'];
      final hasTurnUrl = urls is String
          ? urls.startsWith('turn:') || urls.startsWith('turns:')
          : urls is List && urls.whereType<String>().any(
              (url) => url.startsWith('turn:') || url.startsWith('turns:'));
      return hasTurnUrl &&
          entry['username'] is String &&
          (entry['username'] as String).isNotEmpty &&
          entry['credential'] is String &&
          (entry['credential'] as String).isNotEmpty;
    });
  }

  static Future<Map<String, dynamic>> load({bool forceRefresh = false}) async {
    final cachedAt = _cachedAt;
    if (!forceRefresh &&
        _cachedConfig != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 45)) {
      return _cachedConfig!;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Sign in is required to retrieve secure TURN credentials.');
    }

    try {
      final token = await user.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw StateError('Firebase authentication token is unavailable.');
      }
      final response = await http.get(
        Uri.parse(_endpoint),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw StateError('TURN credential service returned HTTP ${response.statusCode}.');
      }

      final body = jsonDecode(response.body);
      final configured = body is Map ? body['iceServers'] : null;
      if (configured is! List || configured.isEmpty || !_containsTurnServer(configured)) {
        throw StateError('TURN service returned no valid authenticated relay server.');
      }

      final iceServers = <Map<String, dynamic>>[
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        ...configured.whereType<Map>().map(
          (entry) => Map<String, dynamic>.from(entry),
        ),
      ];

      _cachedConfig = {'iceServers': iceServers};
      _cachedAt = DateTime.now();
      debugPrint('ConnectX RTC: authenticated TURN relay configuration loaded.');
      return _cachedConfig!;
    } catch (error) {
      _cachedConfig = null;
      _cachedAt = null;
      debugPrint('ConnectX RTC TURN configuration failed: $error');
      rethrow;
    }
  }
}
