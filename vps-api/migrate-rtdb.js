const fs = require('fs');
const admin = require('firebase-admin');

const KEY_FILE = process.env.GOOGLE_APPLICATION_CREDENTIALS || '/run/secrets/firebase-service-account.json';
const PROJECT_ID = 'connectx-app-f8407';
const DATABASE_URL = 'https://connectx-app-f8407-default-rtdb.firebaseio.com';

if (!fs.existsSync(KEY_FILE)) throw new Error('Firebase service account is missing: ' + KEY_FILE);
const serviceAccount = JSON.parse(fs.readFileSync(KEY_FILE, 'utf8'));
if (serviceAccount.project_id !== PROJECT_ID) throw new Error('Wrong Firebase project in service account');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: DATABASE_URL
});

const db = admin.database();

async function valueAt(path) {
  const snapshot = await db.ref(path).get();
  return snapshot.exists() ? snapshot.val() : null;
}

async function migrate() {
  const legacySnapshot = await db.ref('Users').get();
  const legacyUsers = legacySnapshot.val() || {};
  const updates = {};
  let migrated = 0;

  for (const [uid, legacyValue] of Object.entries(legacyUsers)) {
    if (!legacyValue || typeof legacyValue !== 'object' || Array.isArray(legacyValue)) continue;
    const [publicExisting, privateExisting, tokenExisting, blocksExisting, typingExisting] = await Promise.all([
      valueAt('PublicUsers/' + uid),
      valueAt('PrivateUsers/' + uid),
      valueAt('PrivateTokens/' + uid),
      valueAt('BlockLists/' + uid),
      valueAt('Typing/' + uid)
    ]);

    const publicOld = publicExisting || {};
    const privateOld = privateExisting || {};
    const publicProfile = {
      name: String(publicOld.name ?? legacyValue.name ?? 'ConnectX User'),
      username: String(publicOld.username ?? legacyValue.username ?? ('user_' + uid.slice(0, 8))),
      key: uid,
      online: publicOld.online === true || legacyValue.online === true,
      lastSeen: Number.isFinite(Number(publicOld.lastSeen ?? legacyValue.lastSeen)) ? Number(publicOld.lastSeen ?? legacyValue.lastSeen) : Date.now(),
      bio: String(publicOld.bio ?? legacyValue.bio ?? legacyValue.about ?? 'Hey there! I am using ConnectX'),
      photoUrl: String(publicOld.photoUrl ?? legacyValue.photoUrl ?? '')
    };

    const privateProfile = { ...privateOld };
    if (privateProfile.chats == null && legacyValue.chats != null) privateProfile.chats = legacyValue.chats;
    if (privateProfile.chatMeta == null && legacyValue.chatMeta != null) privateProfile.chatMeta = legacyValue.chatMeta;
    if (privateProfile.notificationSettings == null && legacyValue.notificationSettings != null) {
      privateProfile.notificationSettings = legacyValue.notificationSettings;
    }

    const blockList = { ...(legacyValue.blockedUsers || {}), ...(blocksExisting || {}) };
    const typing = { ...(legacyValue.typing || {}), ...(typingExisting || {}) };

    updates['PublicUsers/' + uid] = publicProfile;
    updates['PrivateUsers/' + uid] = privateProfile;
    updates['BlockLists/' + uid] = blockList;
    updates['Typing/' + uid] = typing;
    if (tokenExisting == null && legacyValue.fcmToken) {
      updates['PrivateTokens/' + uid] = legacyValue.fcmToken;
    }
    migrated++;
  }

  if (Object.keys(updates).length > 0) await db.ref().update(updates);
  console.log('ConnectX RTDB migration completed. Legacy profiles processed: ' + migrated);
  console.log('Legacy Users data was retained for rollback; client rules will no longer expose it.');
}

migrate().then(() => process.exit(0)).catch(error => {
  console.error('ConnectX RTDB migration failed:', error);
  process.exit(1);
});
