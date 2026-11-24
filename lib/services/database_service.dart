import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

/// Explicitly binds every client RTDB reference to the project's default
/// Realtime Database. The checked-in google-services.json does not currently
/// contain a firebase_url field, so relying on FirebaseDatabase.instance can
/// fail during runtime initialization on Android.
class ConnectXDatabase {
  static final FirebaseDatabase instance = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://connectx-app-f8407-default-rtdb.firebaseio.com',
  );
}
