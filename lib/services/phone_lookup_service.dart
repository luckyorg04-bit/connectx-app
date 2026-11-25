import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_database/firebase_database.dart';

import 'database_service.dart';

/// Stores phone numbers privately and exposes only a one-way lookup key.
/// Phone ownership is not verified because this flow intentionally has no OTP.
class PhoneLookupService {
  static String normalize(String value) {
    final trimmed = value.trim();
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) {
      throw const FormatException('Enter a phone number with 7–15 digits, including country code.');
    }
    return digits;
  }

  static String _key(String normalizedPhone) =>
      sha256.convert(utf8.encode(normalizedPhone)).toString();

  static Future<void> register(String uid, String phone) async {
    final normalized = normalize(phone);
    final database = ConnectXDatabase.instance;
    final lookupRef = database.ref('PhoneLookup').child(_key(normalized));
    await lookupRef.set(uid);
    await database.ref('PrivateUsers').child(uid).child('phone').set(normalized);
  }

  static Future<String?> findUid(String phone) async {
    final normalized = normalize(phone);
    final snapshot = await ConnectXDatabase.instance
        .ref('PhoneLookup')
        .child(_key(normalized))
        .get();
    final uid = snapshot.value?.toString();
    return uid == null || uid.isEmpty ? null : uid;
  }

  static Future<String?> getPrivatePhone(String uid) async {
    final value = (await ConnectXDatabase.instance
        .ref('PrivateUsers')
        .child(uid)
        .child('phone')
        .get()).value;
    return value?.toString();
  }
}
