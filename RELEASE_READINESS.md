# ConnectX Production Release Readiness

**Repository:** `luckyorg04-bit/connectx-app`  
**Branch:** `release/connectx-ui-only-1.0.4`  
**Package:** `com.ghostgroup.connectx`  
**Firebase project:** `connectx-app-f8407`  
**Version currently declared:** `1.0.5+6`  
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
- Privacy policy is accessible from Profile inside the app. Firebase Hosting configuration and public `privacy-policy.html` / `account-deletion.html` pages are prepared, but Hosting has not been deployed. The in-app Profile action starts a manual account-deletion email request; this is not automatic account deletion.

## CI and verification

CI is configured to run Flutter analysis/tests, Firebase Realtime Database and Firestore emulator authorization tests, Node syntax checks and Android debug APK builds on the release branch and PR.

The current commit's results must be read from the GitHub Actions run list. Do not treat a cancelled, queued or in-progress run as a pass. No real-device camera, messaging, FCM, or two-device calling test is claimed by CI.

## Production blockers / external actions

1. **Account deletion:** The app currently initiates a support email request; it does not automatically delete the Firebase Auth account, user data, messages, groups, statuses or uploaded media. Implement and test complete deletion before declaring Google Play account-deletion compliance.
2. **Public privacy/deletion URLs:** Firebase Hosting is now configured in `firebase.json`, with `public/privacy-policy.html` and `public/account-deletion.html`. Hosting has not been deployed and the live site ID/URL has not been verified. Create/confirm the Firebase Hosting site, deploy Hosting, verify both pages load publicly, then enter the actual account-deletion URL in Play Console Data Safety and the privacy-policy URL in Play Console.
3. **Upload signing:** GitHub Actions has successfully configured the existing upload keystore and produced a signed AAB in an earlier 1.0.4 run; the 1.0.5+6 signed release workflow is being validated after mobile layout and brand metadata updates. Before upload, compare the AAB signer certificate with the upload certificate currently registered in Play Console. Do not reset or replace the existing signing identity. Verify versionCode `6` is greater than every version already uploaded to Play Console.
4. **Firebase deployment:** The updated RTDB rules, Firestore rules/indexes, phone callable functions and Hosting pages are not deployed by CI. Back up current configuration and deploy only after reviewing the diff.
5. **Notification migration:** The VPS is the intended single FCM notification worker. If the old Cloud Function notification triggers are still deployed, remove those legacy triggers during the reviewed Functions deployment after confirming the VPS worker is healthy. Keep `registerPhoneNumber` and `lookupPhoneNumber`.
6. **VPS operations:** Confirm the service is healthy, its Firebase service account is mounted outside Git, persistent upload storage is backed up, TURN credentials are configured, and logs/monitoring are available.
7. **Play Console declarations:** Complete Data Safety, app content, ads/Advertising ID (if applicable), target API, permissions, privacy-policy, account-deletion URL and store-listing declarations using the actual shipped SDK behavior. Do not infer answers from this report.
8. **Device QA:** Test signup/login, Google Sign-In, username/phone search, QR scan, chat/media, group management, statuses, FCM in foreground/background/terminated states, direct/group calls, Bluetooth/audio routes, app upgrades and Android permission denial on multiple physical Android versions.
9. **Security and localization:** ConnectX does not currently claim WhatsApp-style end-to-end encryption. Do not market it as end-to-end encrypted until a reviewed cryptographic protocol, key lifecycle, multi-device model and independent security assessment are implemented. Settings currently persists Light/Dark/System and English/Hindi preference, but full app-wide translation coverage for all screens is not implemented.

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
6. After confirming the Firebase Hosting site ID, deploy the public pages separately with `firebase deploy --only hosting` and verify the actual URLs.
7. Verify phone registration/search, notification delivery and call signaling against the live project after deployment.

**CI does not deploy Firebase, merge the PR, change signing keys or publish to Google Play.**
