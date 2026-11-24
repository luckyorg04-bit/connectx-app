# ConnectX Part 1 — Firebase and backend setup

This repository uses:
- Firebase Authentication for Google and email/password sign-in.
- Cloud Firestore for direct messages, groups, calls, statuses, communities and channels.
- Firebase Realtime Database for user profiles, online state and chat-list metadata.
- Firebase Cloud Messaging for push notifications.
- The ConnectX VPS API for message/status/profile media uploads, media delivery, notification dispatch and TURN credentials.

## Required deployment

1. Deploy `firestore.rules` and `firestore.indexes.json` for project `connectx-app-f8407`.
2. Deploy the current `vps-api/server.js` to the existing `connectx-api` container.
3. Preserve the persistent host upload mount `/opt/connectx-api/uploads:/app/uploads`.
4. Keep the Firebase service account mounted read-only at `/run/secrets/firebase-service-account.json`.
5. Verify `https://connecttx.duckdns.org/health` returns a successful health response.
6. Verify authenticated uploads and media reads using two signed-in test accounts.

The controlled script `deploy_part2.sh` deploys Firestore rules/indexes, updates only the ConnectX API container, and configures Coturn. It now refuses to proceed if the API upload directory is not mounted persistently. It performs API syntax and health checks before reporting success.

Run it on the ConnectX VPS as root:

```bash
curl -fsSL https://raw.githubusercontent.com/luckyorg04-bit/connectx-app/master/deploy_part2.sh -o /root/deploy_part2.sh && bash /root/deploy_part2.sh
```

Afterward, allow these ports in the Hostinger firewall:
- TCP and UDP 3478
- UDP 49160–49200

## Realtime Database access model

The app writes a user's own profile and own chat-index entry. The trusted ConnectX VPS Admin SDK writes the conversation index for both participants when a Firestore direct-message document is created. Do not permit a client to write arbitrary data under another user's `Users/{uid}` record.

The repository currently does not include a Realtime Database rules file. Review and publish rules in Firebase Console that permit:
- Authenticated users to read the profile fields needed for user search and chat display.
- A signed-in user to write only their own profile, online state, FCM token and own chat metadata.
- No client writes to another user's profile or chat index.
- No public reads of private account fields.

## Media and billing

Direct-chat attachments, status media and profile photos use the VPS API, not Firebase Storage. Firebase Storage is therefore not required for these code paths. The API stores files under `/app/uploads`; the host mount is required so container restarts do not erase uploads.

Uploads are limited to 25 MB and supported file extensions/MIME types. Validate real device uploads for JPG/PNG/WebP, MP4/MOV, audio and supported documents. A successful APK build does not verify the VPS API, firewall, persistent storage or media access.

## Push notifications

The current VPS API listens to Firestore and sends FCM notifications using the Admin SDK. It also updates the chat index for both participants. Do not separately deploy the legacy `functions/index.js` notification triggers unless the VPS notification listener is intentionally disabled; running both paths can send duplicate notifications.

## Known feature boundaries

- Contact sharing currently accepts a name and phone number entered manually; it does not read the device address book.
- Video and document attachments open in an external player/viewer.
- Direct messages are not end-to-end encrypted. Firebase transport encryption and Firestore security rules are not Signal-protocol end-to-end encryption.
- Group message media attachments are not currently included in the Part 2 implementation.
- Play Store release signing, privacy-policy publication, account-deletion workflow and real-device call/media verification are separate production-readiness tasks.
