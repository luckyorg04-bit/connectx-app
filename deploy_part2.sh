#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ID="connectx-app-f8407"
REPO_RAW="https://raw.githubusercontent.com/luckyorg04-bit/connectx-app/master"
SERVICE_ACCOUNT="/etc/connectx-api/service-account.json"
API_CONTAINER="connectx-api"
API_SOURCE_DIR="/opt/connectx-api"
API_IMAGE="connectx-api:1.3"
TURN_REALM="connecttx.duckdns.org"
PUBLIC_IP="187.127.120.27"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script as root."
  exit 1
fi
if [[ ! -s "$SERVICE_ACCOUNT" ]]; then
  echo "Firebase service account not found at $SERVICE_ACCOUNT"
  exit 1
fi
docker inspect "$API_CONTAINER" >/dev/null
mkdir -p /opt/connectx-firebase-deploy
cd /opt/connectx-firebase-deploy

echo "=== 1/4 DEPLOY FIRESTORE RULES AND INDEXES ==="
curl -fsSL "$REPO_RAW/firebase.json" -o firebase.json
curl -fsSL "$REPO_RAW/firestore.rules" -o firestore.rules
curl -fsSL "$REPO_RAW/firestore.indexes.json" -o firestore.indexes.json
export GOOGLE_APPLICATION_CREDENTIALS="$SERVICE_ACCOUNT"
npx --yes firebase-tools deploy --only firestore:rules,firestore:indexes --project "$PROJECT_ID"

echo "=== 2/4 UPDATE ONLY THE CONNECTX API CONTAINER ==="
mkdir -p "$API_SOURCE_DIR"
if [[ -f "$API_SOURCE_DIR/server.js" ]]; then
  cp -a "$API_SOURCE_DIR/server.js" "$API_SOURCE_DIR/server.js.part2-backup-$(date +%Y%m%d%H%M%S)"
fi
curl -fsSL "$REPO_RAW/vps-api/server.js" -o "$API_SOURCE_DIR/server.js.new"
node --check "$API_SOURCE_DIR/server.js.new"
mv "$API_SOURCE_DIR/server.js.new" "$API_SOURCE_DIR/server.js"
docker cp "$API_SOURCE_DIR/server.js" "$API_CONTAINER:/app/server.js"
if ! docker restart "$API_CONTAINER"; then
  echo "API restart failed; restoring the previous server.js inside the container."
  latest_backup="$(ls -1t "$API_SOURCE_DIR"/server.js.part2-backup-* | head -n 1)"
  docker cp "$latest_backup" "$API_CONTAINER:/app/server.js"
  docker restart "$API_CONTAINER" || true
  exit 1
fi
docker commit "$API_CONTAINER" "$API_IMAGE" >/dev/null
echo "ConnectX API source updated; saved image tag: $API_IMAGE"

echo "=== 3/4 INSTALL AND CONFIGURE COTURN ==="
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y coturn openssl
TURN_SECRET="$(openssl rand -hex 32)"
cat >/etc/turnserver.conf <<EOF
listening-port=3478
fingerprint
use-auth-secret
static-auth-secret=$TURN_SECRET
realm=$TURN_REALM
stale-nonce
no-loopback-peers
no-multicast-peers
user-quota=12
total-quota=120
min-port=49160
max-port=49200
listening-ip=0.0.0.0
relay-ip=$PUBLIC_IP
external-ip=$PUBLIC_IP
no-cli
no-tls
no-dtls
EOF
chmod 600 /etc/turnserver.conf
if [[ -f /etc/default/coturn ]]; then
  if grep -q '^TURNSERVER_ENABLED=' /etc/default/coturn; then
    sed -i 's/^TURNSERVER_ENABLED=.*/TURNSERVER_ENABLED=1/' /etc/default/coturn
  else
    echo 'TURNSERVER_ENABLED=1' >>/etc/default/coturn
  fi
fi
ufw allow 3478/tcp || true
ufw allow 3478/udp || true
ufw allow 49160:49200/udp || true
systemctl enable coturn
systemctl restart coturn

echo "=== 4/4 STORE PRIVATE TURN CONFIG IN FIRESTORE ==="
cd "$API_SOURCE_DIR"
TURN_SECRET="$TURN_SECRET" node <<'NODE'
const fs = require('fs');
const admin = require('firebase-admin');
const serviceAccount = JSON.parse(fs.readFileSync('/etc/connectx-api/service-account.json', 'utf8'));
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
admin.firestore().collection('appConfig').doc('rtc').set({
  turnSharedSecret: process.env.TURN_SECRET,
  turnUrls: [
    'turn:connecttx.duckdns.org:3478?transport=udp',
    'turn:connecttx.duckdns.org:3478?transport=tcp'
  ],
  updatedAt: admin.firestore.FieldValue.serverTimestamp()
}, { merge: true }).then(() => {
  console.log('Private TURN configuration saved.');
  process.exit(0);
}).catch(error => {
  console.error('Could not save TURN configuration:', error.message);
  process.exit(1);
});
NODE

echo
echo "=== PART 2 INFRASTRUCTURE DEPLOYMENT COMMANDS FINISHED ==="
echo "No Flutter tests or APK build were run. Those remain the final step."
echo "IMPORTANT: In Hostinger Firewall, allow TCP/UDP 3478 and UDP 49160-49200."
echo "Unrelated containers were not stopped or recreated."
