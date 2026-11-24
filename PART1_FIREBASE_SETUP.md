# ConnectX Part 1 Firebase setup

The Flutter code in this repository uses Firebase Authentication, Realtime Database, Cloud Firestore, Firebase Storage and Firebase Cloud Messaging.

## 1. Publish Firestore rules

Firebase Console → Firestore Database → Rules.

Replace the complete rules editor content with the repository file `firestore.rules`, then click Publish.

This rules file covers:
- 1-to-1 message read/create/edit/read receipts/reactions/delete
- Group membership and group messages
- User report submissions

## 2. Enable Firebase Storage

Firebase Console → Build → Storage → Get started.

Create the default bucket if it does not exist. Then open Storage → Rules and publish the complete contents of `storage.rules`.

Media and voice-note upload will not work until Storage is enabled and these rules are published.

## 3. Push notification delivery

The app requests notification permission and registers the current FCM token in:
`Users/{uid}/fcmToken`

Foreground notifications are displayed by the app. Background delivery requires the Cloud Functions in `functions/index.js`.

Deploy from the repository root after installing Firebase CLI and signing in:

```bash
npm --prefix functions install
firebase deploy --only functions
```

Firebase Cloud Functions deployment requires the Firebase project to use the Blaze (pay-as-you-go) plan. Usage may be low, but Google requires a billing account for deployment. Do not deploy if you do not accept that requirement.

## 4. Android permissions

The app requests microphone and location access only when the related feature is used. Android 13+ notification permission is requested by Firebase Messaging.

## 5. Important feature boundaries

- Contact sharing currently lets the user enter a contact name and phone number manually; it does not read the device address book.
- Video and document files are uploaded to Firebase Storage and opened using an external app/browser.
- Location sharing sends the current device coordinates after permission is granted.
- Block state is stored per user in Realtime Database; report submissions are stored in Firestore.
- Groups use Firestore membership documents. Group text messages are supported; group media and admin roles are not part of this Part 1 implementation.
- Messages are not yet end-to-end encrypted. Firebase transport/security rules do not equal Signal Protocol E2E encryption.
