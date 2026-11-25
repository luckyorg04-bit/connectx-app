# ConnectX Production Release Readiness

**Repository:** `luckyorg04-bit/connectx-app`  
**Branch:** `release/connectx-ui-only-1.0.4`  
**Package:** `com.ghostgroup.connectx`  
**Firebase project:** `connectx-app-f8407`  
**Version currently declared:** `1.0.4+5`  
**Target SDK:** 36

## Verified repository configuration

- Android application ID and Firebase Android client entry are both `com.ghostgroup.connectx`.
- Android target SDK is 36 and minimum SDK is 21.
- Email/password and Google sign-in flows remain in the app.
- Phone numbers are stored under the owner's private RTDB profile and are not placed in public user records or QR payloads.
- Phone registration and exact lookup use authenticated callable functions in `asia-south1`; direct client writes to the phone field and direct reads/writes to the phone index are denied by RTDB rules.
- The phone registration callable replaces a user's previous index entry only after reserving the new number.
- The VPS API at `https://connecttx.duckdns.org` handles media uploads, TURN credentials and FCM notification listeners. The Functions package is limited to phone lookup/registration callables to avoid two notification workers being deployed from the current source.
- Group calls now request microphone/camera permissions, initialize audio routing and handle streamless remote tracks.
- An in-app Profile action now starts a manual account-deletion email request. This is not automatic account deletion.

## CI and verification

CI is configured to run Flutter analysis/tests, Firebase Realtime Database and Firestore emulator authorization tests, Node syntax checks and Android debug APK builds on the release branch and PR.

The current commit's results must be read from the GitHub Actions run list. Do not treat a cancelled, queued or in-progress run as a pass. No real-device camera, messaging, FCM, or two-device calling test is claimed by CI.

## Production blockers / external actions

1. **Account deletion:** The app currently initiates a support email request; it does not automatically delete the Firebase Auth account, user data, messages, groups, statuses or uploaded media. Implement and test complete deletion before declaring Google Play account-deletion compliance.
2. **Public privacy-policy URL:** `privacy-policy.html` is in the repository, but `firebase.json` does not configure Firebase Hosting. Publish it at a stable public HTTPS URL and enter that exact URL in Play Console and the app listing.
3. **Upload signing:** A production AAB must be signed with the upload key currently registered by Google Play. The GitHub release workflow requires the four repository secrets `UPLOAD_KEYSTORE_BASE64`, `UPLOAD_KEYSTORE_PASSWORD`, `UPLOAD_KEY_ALIAS`, and `UPLOAD_KEY_PASSWORD`. Do not upload a different keystore or private key to the repository. Resolve the existing Play upload-certificate mismatch before using the AAB workflow.
4. **Firebase deployment:** The updated RTDB rules, Firestore rules/indexes and phone callable functions are not deployed by CI. Back up current configuration and deploy only after reviewing the diff.
5. **Notification migration:** The VPS is the intended single FCM notification worker. If the old Cloud Function notification triggers are still deployed, remove those legacy triggers during the reviewed Functions deployment after confirming the VPS worker is healthy. Keep `registerPhoneNumber` and `lookupPhoneNumber`.
6. **VPS operations:** Confirm the service is healthy, its Firebase service account is mounted outside Git, persistent upload storage is backed up, TURN credentials are configured, and logs/monitoring are available.
7. **Play Console declarations:** Complete Data Safety, app content, ads/Advertising ID (if applicable), target API, permissions, privacy-policy, account-deletion URL and store-listing declarations using the actual shipped SDK behavior. Do not infer answers from this report.
8. **Device QA:** Test signup/login, Google Sign-In, username/phone search, QR scan, chat/media, group management, statuses, FCM in foreground/background/terminated states, direct/group calls, Bluetooth/audio routes, app upgrades and Android permission denial on multiple physical Android versions.
9. **Security features:** ConnectX does not currently claim WhatsApp-style end-to-end encryption. Do not market it as end-to-end encrypted until a reviewed cryptographic protocol, key lifecycle, multi-device model and independent security assessment are implemented.

## Safe Firebase deployment procedure

1. Back up current RTDB and Firestore rules and export any critical data.
2. Confirm the VPS notification worker is healthy before changing deployed notification triggers.
3. Review the exact branch diff and test results.
4. From a trusted developer environment with the correct Firebase project selected, deploy the reviewed configuration:

   ```bash
   firebase use connectx-app-f8407
   firebase deploy --only database,firestore:rules,firestore:indexes,functions
   ```

5. Review any prompt to delete old notification-trigger functions. Remove only the legacy duplicate notification triggers; do not remove the two phone callables.
6. Verify phone registration/search, notification delivery and call signaling against the live project after deployment.

**CI does not deploy Firebase, merge the PR, change signing keys or publish to Google Play.**
