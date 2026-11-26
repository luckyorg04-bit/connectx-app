# ConnectX 1.0.4 — Release notes draft

- Updated chat, profile, QR and calling experiences.
- Added phone number registration and exact phone search without OTP.
- Added real ConnectX QR generation and camera scanning.
- Added sent, delivered and read message indicators.
- Improved notification preference handling and call setup.
- Added group-call microphone/camera permission prompts and audio routing.
- Tightened Realtime Database and Firestore authorization checks.

## Release caveats
- Firebase rules and callable functions require a reviewed production deployment.
- Account deletion currently starts a support request; automatic account/data deletion is not implemented.
- Incoming call behavior and media/call reliability require physical-device testing.
- End-to-end encryption is not implemented.
