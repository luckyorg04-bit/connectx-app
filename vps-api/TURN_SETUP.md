# ConnectX TURN relay setup

ConnectX now requests short-lived TURN REST credentials from the authenticated VPS endpoint:

- `GET https://connecttx.duckdns.org/api/turn-credentials`
- The endpoint reads its shared secret and TURN URLs from the private Firestore document `appConfig/rtc`.
- Firestore client rules deny all access to `appConfig`; only the Admin SDK can read it.
- The Flutter app falls back to public STUN servers if TURN is not configured.

## VPS setup

Run on the ConnectX VPS only. This installs Coturn as a host service and does not recreate or modify any existing Docker container.

```bash
apt-get update
apt-get install -y coturn openssl

TURN_SECRET="$(openssl rand -hex 32)"
cat >/etc/turnserver.conf <<EOF
listening-port=3478
fingerprint
use-auth-secret
static-auth-secret=$TURN_SECRET
realm=connecttx.duckdns.org
stale-nonce
no-loopback-peers
no-multicast-peers
user-quota=12
total-quota=120
min-port=49160
max-port=49200
listening-ip=0.0.0.0
relay-ip=187.127.120.27
external-ip=187.127.120.27
no-cli
no-tls
no-dtls
EOF

if [ -f /etc/default/coturn ]; then
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

cd /opt/connectx-api
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
  console.log('TURN credentials stored in private Firestore config.');
  process.exit(0);
}).catch(error => {
  console.error(error);
  process.exit(1);
});
NODE

echo '=== COTURN STATUS ==='
systemctl --no-pager --full status coturn
echo '=== TURN SECRET STORED IN FIRESTORE ==='
```

Also allow TCP/UDP 3478 and UDP 49160–49200 in the Hostinger VPS firewall panel. The VPS API must be rebuilt/restarted with the current repository's `vps-api/server.js` for the credential endpoint to be active.

## Important

The group call implementation is an eight-participant WebRTC mesh. Mesh bandwidth and CPU usage increase with participant count. Coturn improves connectivity behind restrictive NATs; it does not replace final device/network verification.
