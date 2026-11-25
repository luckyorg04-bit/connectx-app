# ConnectX Play Store release preparation

This branch adds a signed Android App Bundle (AAB) workflow. It does **not** certify the app as production-ready or submit it to Google Play.

## Release blockers to resolve before running the workflow

1. Choose and confirm a permanent, unique Android application ID. The current ID is the placeholder `com.example.newfluuter15042023`; do not publish with it.
2. Register that exact application ID as an Android app in Firebase project `connectx-app-f8407`, download the matching `google-services.json`, and replace `android/app/google-services.json`.
3. Update `applicationId` in `android/app/build.gradle` and the legacy manifest package in `android/app/src/main/AndroidManifest.xml` consistently. Check any package-specific Kotlin/Java paths and OAuth client configuration.
4. Confirm the Play-required target API level and upgrade the Flutter/Android Gradle toolchain as needed. This repository currently uses Flutter 3.7.12, Android Gradle Plugin 7.1.3, Gradle 7.4 and `flutter.targetSdkVersion`; this is an old toolchain and has not been certified against current Play requirements.
5. Review Firebase Security Rules, privacy policy, Data safety declarations, account deletion requirements (if accounts can be created), app access instructions, content rating, ads declaration and store listing assets.
6. Complete real-device QA for sign-in, messaging, notifications, audio/video calling, permissions, network changes and background behavior. A successful build does not prove calling works.

## Configure signing safely

Create an Android upload keystore locally and keep a secure backup. Never commit the keystore, passwords, or private key to Git.

Add these GitHub Actions repository secrets:

- `ANDROID_UPLOAD_KEYSTORE_BASE64`: base64 encoding of the upload keystore file
- `ANDROID_KEY_ALIAS`: key alias
- `ANDROID_STORE_PASSWORD`: keystore password
- `ANDROID_KEY_PASSWORD`: key password

Example local encoding command (run on your own machine; do not paste the output into chat):

```bash
base64 -w 0 connectx-upload-key.jks
```

The workflow restores the key into the runner's temporary directory, builds a signed AAB, uploads it as a workflow artifact and removes the temporary key file.

## Build

After all blockers above are resolved and secrets are configured:

GitHub → Actions → **ConnectX Play Store Release AAB** → Run workflow.

The workflow intentionally stops if the package ID is still a `com.example.*` placeholder, if Firebase package identity does not match, or if signing secrets are missing.

## Important

- The current workflow builds an AAB only. It does not upload to Play Console.
- Do not share keystore passwords, private keys, OTPs or Google account credentials in chat.
- Keep the upload key backed up securely. If Play App Signing is enabled, the upload key is used to authenticate uploads; Google manages the app signing key.
