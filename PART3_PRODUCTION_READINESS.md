# ConnectX Part 3 — Production hardening and Play Store readiness

This checklist is intentionally separate from source implementation and APK compilation. Items marked pending must not be advertised as production-ready.

## Implemented in the current source updates

- Profile editing now supports name, bio, profile photo upload and photo removal.
- Existing about profile values are migrated to bio on the next successful sign-in.
- A dedicated authenticated VPS endpoint stores and deletes profile photos.
- The trusted VPS Firestore listener now updates the direct-chat index for both participants; the mobile client only writes its own profile's chat index.
- The chat list refreshes when the shared user list changes in place and handles unavailable block metadata without aborting message preview loading.
- Incoming one-to-one calls start a system ringtone after the incoming call screen opens; the ringtone stops on answer/end.
- Incoming one-to-one calls are routed directly to the call screen while the app is in the foreground.
- API syntax, deployment-script syntax, Flutter analysis and Flutter tests are included in CI.

## Deployment still required

- Deploy the updated VPS API so profile-photo endpoints and Admin SDK chat-index updates are live.
- Verify the /app/uploads persistent volume mount.
- Deploy Firestore rules and indexes.
- Install/configure Coturn and open the required Hostinger firewall ports.
- Verify the API health endpoint and authenticated profile/media uploads.

## Functional verification still required on two or more physical Android devices

- Account creation, Google sign-in, email/password sign-in, logout and re-login.
- Search a second active user and open a direct chat.
- Text delivery in both directions, message history after app restart, read receipts, unread counts and notification tap routing.
- Photo, video, audio, GIF and document upload, download, preview/playback and failure/retry behavior.
- Profile photo change/removal, bio edit and persistence across sign-out/re-login and on other users' devices.
- Incoming/outgoing voice and video calls on Wi-Fi and mobile data, including ringing, accept, decline, hang-up, mute, camera toggle and network interruption.
- Group creation, membership changes, group messages, polls, voting, group voice/video call and participant departure.
- Status audience privacy, media playback, view list and automatic 24-hour expiry.
- Communities and channels: create, join/leave/follow/unfollow and permissions.
- Block/report behavior and unauthorized access attempts.

## Security and Play Store blockers

- End-to-end encryption is not implemented. Do not market direct or group messages as end-to-end encrypted.
- Add a user-facing account deletion flow and backend data cleanup.
- Publish a privacy policy and complete the Play Console Data safety declaration accurately.
- Review user-generated content moderation, reporting, blocking and abuse handling.
- Choose and freeze a unique Android application ID before first Play Store release. The current ID is a development-style com.example... value; changing it later creates a different app identity.
- Configure a private release keystore and protected signing credentials. The current Gradle release build uses the debug signing configuration and is not Play Store release-ready.
- Build and validate a signed Android App Bundle (AAB), versioning, target SDK, app icon, screenshots and store listing.
- Run a final regression test on supported Android versions and networks.

## Release gate

A successful debug APK build proves only that the source compiles. Production sign-off requires successful CI, deployed backend/rules, persistent media storage, two-device functional tests, security review and a signed release AAB. Do not mark ConnectX 100% complete until every required gate is verified.