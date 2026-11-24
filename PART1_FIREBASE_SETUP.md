# ConnectX Part 1 Firebase setup

The Flutter code in this repository uses Firebase Authentication, Realtime Database, Cloud Firestore, Firebase Storage and Firebase Cloud Messaging.

## 1. Publish Firestore rules

Firebase Console → Firestore Database → Rules.

Replace the complete rules editor content with the repository file `firestore.rules`, then click Publish.

This rules file covers:
- 1-to-1 message read/create/edit/read receipts/reactions/delete
- Group membership and group messages
- User report submissions

## 2. Firebase Storage billing requirement

Firebase Console → Build → Storage → Get started.

Important: Cloud Storage for Firebase now requires the Blaze pay-as-you-go plan, including access to default buckets. If this project remains on Spark, image/video/document/voice upload through Firebase Storage will fail. The code is ready for Firebase Storage, but the user must either enable Blaze billing or move the upload service to a separately hosted server. See Google's current requirement: https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024.

If the project is on Blaze, create the default bucket, then open Storage → Rules and publish the complete contents of `storage.rules`.

## 3. Push notification delivery

The app requests notification permission and registers the current FCM token in:
`Users/{uid}/fcmToken`

Foreground notifications are displayed by the app. Background delivery requires the Cloud Functions in `functions/index.js`.

Cloud Functions also requires the Blaze plan. FCM itself is no-cost, but the server-side trigger that sends a push notification when a Firestore message is created must run somewhere. Deploy from the repository root after installing Firebase CLI and signing in:

```bash
npm --prefix functions install
firebase deploy --only functions
```

Firebase Cloud Functions deployment requires the Firebase project to use the Blaze (pay-as-you-go) plan and a linked billing account. Usage may fit within no-cost quotas, but deployment still requires billing. Do not deploy if you do not accept that requirement. See https://firebase.google.com/docs/functions/faq-and-troubleshooting.

## 4. Android permissions

The app requests microphone and location access only when the related feature is used. Android 13+ notification permission is requested by Firebase Messaging.

## 5. Important feature boundaries

- Contact sharing currently lets the user enter a contact name and phone number manually; it does not read the device address book.
- Video and document files are uploaded to Firebase Storage and opened using an external app/browser.
- Location sharing sends the current device coordinates after permission is granted.
- Block state is stored per user in Realtime Database; report submissions are stored in Firestore.
- Groups use Firestore membership documents. Group text messages are supported; group media and admin roles are not part of this Part 1 implementation.
- Messages are not yet end-to-end encrypted. Firebase transport/security rules do not equal Signal Protocol E2E encryption.
