# ConnectX VPS API

This service replaces Firebase Storage uploads and Cloud Functions notifications.
It requires the ConnectX service-account JSON to be mounted read-only inside the
container at /run/secrets/firebase-service-account.json. Never commit that JSON.

Persistent uploads: host /opt/connectx-api/uploads -> container /app/uploads.
The service verifies Firebase ID tokens, uploads chat files, signs media URLs,
and listens to Firestore direct/group message collections to send FCM notifications.

Media URLs are signed capability links: anyone who receives the complete URL can
open the file. Keep them inside the intended conversation.

Build on VPS after copying these files:
docker build -t connectx-api:1.1 .

When recreating the container, preserve the existing Traefik routing, port 3100
binding, restart policy and uploads mount. Add this read-only credential mount:
-v /etc/connectx-api/service-account.json:/run/secrets/firebase-service-account.json:ro
and this environment variable:
-e GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/firebase-service-account.json

Do not remove the current container until the replacement image has built.
