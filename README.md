# ConnectX — Messaging and Calling

ConnectX is a Flutter-based communication app with real-time messaging, voice and video calls, group conversations, status updates, profile management, QR-based connection, and push notifications.

## Core capabilities

- Email/password and Google authentication
- Direct and group messaging with delivery/read indicators
- Image, video, file, voice-note, location and contact sharing
- Voice and video calls, including group calls
- Status updates and QR-code profile sharing
- Username and phone-number discovery
- Light, dark and system theme preferences
- English and Hindi language preference

## Technology

- Flutter / Dart
- Firebase Authentication
- Firebase Realtime Database
- Cloud Firestore
- Firebase Cloud Messaging
- WebRTC for voice/video media
- ConnectX VPS API for media and TURN services

## Android application

- Display name: ConnectX
- Package ID: `com.ghostgroup.connectx`
- Firebase project: `connectx-app-f8407`

## Development

1. Install the Flutter stable SDK.
2. Configure the Firebase Android client for `com.ghostgroup.connectx`.
3. Resolve dependencies with `flutter pub get`.
4. Run checks with `flutter analyze` and `flutter test`.
5. Build a local debug APK with `flutter build apk --debug`.

Release builds use the protected GitHub Actions signing workflow. Do not commit upload keystores, passwords, Firebase service-account keys, or other secrets.

## Release and compliance notes

Review [RELEASE_READINESS.md](RELEASE_READINESS.md) before a production rollout. CI success does not replace physical-device testing, Firebase deployment review, Play Console declarations, privacy-policy verification, or account-deletion compliance.
