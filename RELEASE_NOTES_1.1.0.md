# ConnectX 1.1.0 — WhatsApp-style experience update

## Interface
- Rebuilt the branded sign-in and sign-up experience with responsive layouts, accessible field labels, autofill hints, password visibility, and clear loading states.
- Standardised the app around ConnectX green, Roboto typography, clean surfaces, rounded controls and consistent spacing.
- Added a subtle original chat wallpaper while retaining readable incoming/outgoing message bubbles and the existing composer actions.
- Refined the home header and mobile navigation styling.

## Session reliability
- Logout now clears account-scoped RTDB listeners and notification subscriptions, signs out the Google session when present, and then signs out Firebase Authentication.
- If Firebase sign-out fails, the signed-in session and home listeners are restored rather than leaving a half-logged-out screen.
- Existing email/password, Google sign-in, password reset, user profile repair, chat, media, status, group and call flows are retained.

## Release identity
- App: ConnectX
- Android package: `com.ghostgroup.connectx`
- Firebase project: `connectx-app-f8407`
- Version: `1.1.0+7`
- Existing upload signing identity is preserved.

## Validation
CI must pass Firebase rules emulator tests, Flutter analysis, Flutter tests, signed APK/AAB generation and signature fingerprint comparison. Real-device tests remain required for login/logout, messaging, media permissions, notifications, and direct/group calls. This release does not claim end-to-end encryption or automatic account deletion.
