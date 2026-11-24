# ConnectX VPS API

This service replaces Firebase Storage uploads and Cloud Functions notifications.
It requires the ConnectX service-account JSON to be mounted read-only inside the
container at `/run/secrets/firebase-service-account.json`. Never commit that JSON.

Persistent uploads: host `/opt/connectx-api/uploads` -> container `/app/uploads`.

The API:
- Verifies Firebase ID tokens for uploads and TURN credential requests.
- Uploads direct-chat media and issues signed media URLs.
- Enforces status audience membership and 24-hour expiry for status media.
- Removes expired status files and status records on its cleanup schedule.
- Sends FCM notifications for direct messages, group messages, 1-to-1 calls and group calls.
- Issues one-hour TURN REST credentials using the private Firestore document `appConfig/rtc`.

Ordinary direct-chat media URLs remain signed capability links. Keep them inside the
intended conversation. Status media additionally requires a Firebase ID token and
a matching audience UID; it expires after 24 hours.

## Build and deploy

Build the current source on the VPS from `/opt/connectx-api`:

```bash
docker build -t connectx-api:1.3 .
```

When recreating the container, preserve the existing Traefik routing, port 3100
binding, restart policy, environment, and uploads mount. Preserve this read-only
credential mount:

```bash
-v /etc/connectx-api/service-account.json:/run/secrets/firebase-service-account.json:ro
-e GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/firebase-service-account.json
```

Do not remove the current container until the replacement image has built and the
new container is ready. Do not modify unrelated Roso AI containers.

## TURN relay

The authenticated `GET /api/turn-credentials` endpoint reads its shared secret
and TURN URLs from the server-only Firestore document `appConfig/rtc`. Client
Firestore rules deny access to this document. Install Coturn and store its shared
secret in this document using the instructions in [TURN_SETUP.md](TURN_SETUP.md).

The Flutter app falls back to public STUN servers if TURN is not configured.
