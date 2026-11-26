# ConnectX 1.0.5 — Release notes draft

- Standardised the web app/PWA metadata to use the ConnectX brand name and colours.
- Reworked group creation and group management dialogs to fit shorter mobile screens.
- Made the starred-messages sheet adapt to the available screen height.
- Kept the Android package ID, Firebase project and existing upload signing identity unchanged.

## Release validation still required

- Complete the signed APK/AAB CI workflow and confirm both artifact signatures match the existing Play Console upload certificate.
- Verify the version code is greater than the highest version already uploaded in Play Console.
- Run physical-device tests for sign-in, messaging, media permissions, notifications, and direct/group calls.
- Deploy reviewed Firebase rules/functions and public privacy/account-deletion pages separately.
- Complete the Play Console Data Safety, app content, privacy and account-deletion declarations.

ConnectX does not currently implement end-to-end encryption or automatic account/data deletion.
