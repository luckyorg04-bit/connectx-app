import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'database_service.dart';

/// Phone numbers are private and are not verified because this flow has no OTP.
/// Registration and exact-match lookup are mediated by authenticated callables.
class PhoneLookupService {
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  static String normalize(String value) {
    final digits = value.trim().replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) {
      throw const FormatException(
        'Enter a phone number with 7–15 digits, including country code.',
      );
    }
    return digits;
  }

  static Future<void> register(String uid, String phone) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid != uid) {
      throw StateError('You must be signed in to register this phone number.');
    }
    final normalized = normalize(phone);
    await _functions.httpsCallable('registerPhoneNumber').call({
      'phone': normalized,
    }).timeout(const Duration(seconds: 18));
  }

  static Future<String?> findUid(String phone) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Sign in to search by phone number.');
    }
    final normalized = normalize(phone);
    final result = await _functions.httpsCallable('lookupPhoneNumber').call({
      'phone': normalized,
    }).timeout(const Duration(seconds: 18));
    final data = Map<String, dynamic>.from(result.data as Map);
    final uid = data['uid']?.toString();
    return uid == null || uid.isEmpty ? null : uid;
  }

  static Future<String?> getPrivatePhone(String uid) async {
    final value = (await ConnectXDatabase.instance
        .ref('PrivateUsers')
        .child(uid)
        .child('phone')
        .get().timeout(const Duration(seconds: 12))).value;
    return value?.toString();
  }
}
