# ConnectX Part 2 implementation status

This file tracks implementation work separately from final device testing.

## Implemented in source

- Status creation supports text, photo and video with a selected audience.
- Status media now stores its audience in the VPS metadata; media requests require a Firebase ID token and an audience match.
- Status records and media are scheduled for cleanup after 24 hours.
- Status viewer counts and seen-by list remain available to the owner.
- Direct chats include voice notes, location/contact sharing, polls, stickers, GIF/document attachments, view-once media and per-chat disappearing-message settings.
- Group chats support admin/member management, group polls, poll voting and sticker messages.
- Communities support creation, joining/leaving, member-only discussion feeds and member posts.
- Channels support creation, follow/unfollow and owner announcements.
- One-to-one calls use dynamic ICE configuration.
- Group voice/video calls use an eight-participant WebRTC mesh, per-peer Firestore signaling, participant history, call controls and an active-call join banner.
- Group call push notifications and notification-tap routing are implemented.
- Group calls expire after four hours; stale calls are ended by the VPS cleanup job.
- TURN credentials are issued as one-hour credentials by the authenticated VPS endpoint. The Coturn installation and private Firestore configuration steps are in `vps-api/TURN_SETUP.md`.
- Firestore rules and composite indexes have been updated for the new workflows.

## Infrastructure work still required

1. Run the controlled deployment script from the VPS: `bash deploy_part2.sh`. It deploys Firestore rules/indexes, updates only the existing `connectx-api` container in place, installs Coturn and stores private TURN configuration. The script does not run Flutter tests or build an APK.
2. In Hostinger Firewall, allow TCP/UDP 3478 and UDP 49160–49200 as described in `vps-api/TURN_SETUP.md`.
3. Only after implementation and infrastructure are complete: run the final Flutter analysis, Android build, and device/network verification; then deliver the final APK.

No final testing or APK sign-off is claimed by this document.
