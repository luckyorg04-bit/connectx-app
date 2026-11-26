const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const multer = require('multer');
const rateLimit = require('express-rate-limit');
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const app = express();
const PORT = Number(process.env.PORT || 3100);
const PROJECT_ID = 'connectx-app-f8407';
const DATABASE_URL = 'https://connectx-app-f8407-default-rtdb.firebaseio.com';
const UPLOAD_DIR = process.env.UPLOAD_DIR || '/app/uploads';
const KEY_FILE = process.env.GOOGLE_APPLICATION_CREDENTIALS || '/run/secrets/firebase-service-account.json';

if (!fs.existsSync(KEY_FILE)) throw new Error('Firebase service account is not mounted: ' + KEY_FILE);
const serviceAccount = JSON.parse(fs.readFileSync(KEY_FILE, 'utf8'));
if (serviceAccount.project_id !== PROJECT_ID) throw new Error('Wrong Firebase project in service account');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount), databaseURL: DATABASE_URL });
const db = admin.firestore();
const rtdb = admin.database();
console.log('Firebase Admin initialized for project ' + PROJECT_ID);
const signingKey = crypto.createHash('sha256').update(serviceAccount.private_key).digest();
// Serialize one-time opens inside this API process to prevent simultaneous reuse.
const viewOnceLocks = new Set();
fs.mkdirSync(UPLOAD_DIR, { recursive: true });

app.set('trust proxy', 1);
app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
app.use(cors({ origin: true, methods: ['GET', 'POST', 'DELETE'], allowedHeaders: ['Authorization', 'Content-Type'] }));
app.use(express.json({ limit: '100kb' }));
app.use('/api/', rateLimit({ windowMs: 900000, limit: 120, standardHeaders: 'draft-7', legacyHeaders: false }));

async function authenticate(req, res, next) {
  try {
    const h = req.headers.authorization || '';
    if (!h.startsWith('Bearer ')) return res.status(401).json({ success: false, error: 'Firebase ID token required' });
    req.user = await admin.auth().verifyIdToken(h.slice(7));
    return next();
  } catch (_) {
    return res.status(401).json({ success: false, error: 'Invalid or expired Firebase token' });
  }
}

const types = {
  '.jpg':'image/jpeg','.jpeg':'image/jpeg','.png':'image/png','.webp':'image/webp','.gif':'image/gif',
  '.mp4':'video/mp4','.mov':'video/quicktime','.mp3':'audio/mpeg','.m4a':'audio/mp4','.aac':'audio/aac',
  '.wav':'audio/wav','.ogg':'audio/ogg','.pdf':'application/pdf','.doc':'application/msword',
  '.docx':'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xls':'application/vnd.ms-excel','.xlsx':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.txt':'text/plain'
};
const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, UPLOAD_DIR),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname || '').toLowerCase();
    if (!types[ext]) return cb(new Error('Unsupported file extension'));
    cb(null, crypto.randomUUID() + ext);
  }
});
const upload = multer({
  storage, limits: { fileSize: 25 * 1024 * 1024, files: 1 },
  fileFilter: (_req, file, cb) => {
    const expected = types[path.extname(file.originalname || '').toLowerCase()];
    if (!expected || (file.mimetype !== expected && file.mimetype !== 'application/octet-stream')) return cb(new Error('Unsupported file type'));
    cb(null, true);
  }
});
function sign(filename, conversationId) {
  return crypto.createHmac('sha256', signingKey).update(filename + ':' + conversationId).digest('hex');
}
function equalHex(a, b) {
  const x = Buffer.from(String(a || ''), 'hex'), y = Buffer.from(String(b || ''), 'hex');
  return x.length === y.length && x.length > 0 && crypto.timingSafeEqual(x, y);
}

app.get('/health', (_req, res) => res.json({ success: true, service: 'ConnectX API', status: 'running' }));
app.get('/api/turn-credentials', authenticate, async (req, res) => {
  try {
    let config = {};
    if (!process.env.TURN_SHARED_SECRET || !process.env.TURN_URLS) {
      const snapshot = await db.collection('appConfig').doc('rtc').get();
      config = snapshot.exists ? snapshot.data() || {} : {};
    }
    const secret = process.env.TURN_SHARED_SECRET || String(config.turnSharedSecret || '');
    const envUrls = String(process.env.TURN_URLS || '').split(',').map(value => value.trim()).filter(Boolean);
    const storedUrls = Array.isArray(config.turnUrls) ? config.turnUrls.filter(value => typeof value === 'string') : [];
    const urls = envUrls.length ? envUrls : storedUrls;
    if (!secret || urls.length === 0) {
      return res.status(503).json({ success: false, error: 'TURN service is not configured' });
    }
    const expiresAt = Math.floor(Date.now() / 1000) + 3600;
    const username = expiresAt + ':' + req.user.uid;
    const credential = crypto.createHmac('sha1', secret).update(username).digest('base64');
    return res.json({
      success: true,
      expiresAt,
      iceServers: [{ urls, username, credential }]
    });
  } catch (error) {
    console.error('TURN credential error:', error.message);
    return res.status(503).json({ success: false, error: 'Could not issue TURN credentials' });
  }
});

app.post('/api/upload', authenticate, upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ success: false, error: 'Select a file to upload' });
  const conversationId = String(req.body.conversationId || '');
  const participants = conversationId.split(',');
  if (participants.length !== 2 || !participants.includes(req.user.uid)) {
    fs.unlink(req.file.path, () => {});
    return res.status(403).json({ success: false, error: 'Not a participant in this conversation' });
  }
  const resourceType = String(req.body.resourceType || 'message');
  if (!['message', 'status'].includes(resourceType)) {
    fs.unlink(req.file.path, () => {});
    return res.status(400).json({ success: false, error: 'Unsupported media resource type' });
  }
  let audienceUids = [];
  if (resourceType === 'status') {
    try { audienceUids = JSON.parse(String(req.body.audienceUids || '[]')); } catch (_) { audienceUids = null; }
    if (!Array.isArray(audienceUids) || !audienceUids.includes(req.user.uid) ||
        audienceUids.some(uid => typeof uid !== 'string' || uid.length > 128)) {
      fs.unlink(req.file.path, () => {});
      return res.status(400).json({ success: false, error: 'A valid status audience is required' });
    }
  }
  const originalName = path.basename(req.file.originalname || 'attachment');
  const mimeType = types[path.extname(req.file.filename).toLowerCase()];
  const meta = {
    conversationId, ownerUid: req.user.uid, originalName, mimeType, size: req.file.size,
    resourceType, audienceUids,
    expiresAt: resourceType === 'status' ? Date.now() + 24 * 60 * 60 * 1000 : null,
    viewOnce: req.body.viewOnce === 'true', viewedBy: []
  };
  fs.writeFileSync(req.file.path + '.meta.json', JSON.stringify(meta), { mode: 0o600 });
  const token = sign(req.file.filename, conversationId);
  const url = 'https://connecttx.duckdns.org/media/' + encodeURIComponent(req.file.filename) +
    '?conversationId=' + encodeURIComponent(conversationId) + '&token=' + token;
  return res.status(201).json({ success: true, fileName: originalName, storedName: req.file.filename, mimeType, size: req.file.size, url });
});

// Profile photos are public profile assets, but only the authenticated owner may replace or delete them.
app.post('/api/profile-photo', authenticate, upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ success: false, error: 'Select a profile photo' });
  const profileKey = 'profile:' + req.user.uid;
  const originalName = path.basename(req.file.originalname || 'profile-photo');
  const mimeType = types[path.extname(req.file.filename).toLowerCase()];
  const meta = {
    conversationId: profileKey,
    ownerUid: req.user.uid,
    originalName,
    mimeType,
    size: req.file.size,
    resourceType: 'profile',
    audienceUids: [],
    expiresAt: null,
    viewOnce: false,
    viewedBy: []
  };
  try {
    fs.writeFileSync(req.file.path + '.meta.json', JSON.stringify(meta), { mode: 0o600 });
    const token = sign(req.file.filename, profileKey);
    const url = 'https://connecttx.duckdns.org/media/' + encodeURIComponent(req.file.filename) +
      '?conversationId=' + encodeURIComponent(profileKey) + '&token=' + token;
    return res.status(201).json({ success: true, url, fileName: originalName });
  } catch (error) {
    fs.unlink(req.file.path, () => {});
    return res.status(500).json({ success: false, error: 'Could not save profile photo' });
  }
});

app.delete('/api/profile-photo/:filename', authenticate, (req, res) => {
  const filename = path.basename(req.params.filename);
  const file = path.join(UPLOAD_DIR, filename);
  const metaFile = file + '.meta.json';
  if (!fs.existsSync(file) || !fs.existsSync(metaFile)) {
    return res.status(404).json({ success: false, error: 'Profile photo not found' });
  }
  try {
    const meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
    if (meta.resourceType !== 'profile' || meta.ownerUid !== req.user.uid) {
      return res.status(403).json({ success: false, error: 'You cannot delete this profile photo' });
    }
    fs.unlinkSync(file);
    fs.unlinkSync(metaFile);
    return res.json({ success: true });
  } catch (_) {
    return res.status(400).json({ success: false, error: 'Invalid profile photo metadata' });
  }
});

// Direct-chat attachments use signed capability URLs; status media additionally
// requires an authenticated viewer included in the saved status audience.
app.get('/media/:filename', async (req, res) => {
  const filename = path.basename(req.params.filename);
  const file = path.join(UPLOAD_DIR, filename);
  const metaFile = file + '.meta.json';
  if (!fs.existsSync(file) || !fs.existsSync(metaFile)) return res.status(404).json({ success: false, error: 'File not found' });
  let viewOnceLockAcquired = false;
  try {
    const meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
    const conversationId = String(req.query.conversationId || '');
    if (meta.conversationId !== conversationId || !equalHex(req.query.token, sign(filename, conversationId))) {
      return res.status(403).json({ success: false, error: 'Invalid media link' });
    }
    if (meta.resourceType === 'status') {
      const authToken = String(req.query.auth || '');
      if (!authToken) return res.status(401).json({ success: false, error: 'Sign-in is required to view this status media' });
      const viewer = await admin.auth().verifyIdToken(authToken);
      if (Number(meta.expiresAt || 0) <= Date.now()) {
        return res.status(410).json({ success: false, error: 'This status has expired' });
      }
      // Active status media is available to any authenticated ConnectX user,
      // matching the Firestore status feed visibility rule.
    }
    if (meta.viewOnce === true) {
      if (viewOnceLocks.has(filename)) {
        return res.status(409).json({ success: false, error: 'This one-time attachment is already being opened' });
      }
      viewOnceLocks.add(filename);
      viewOnceLockAcquired = true;
      const authToken = String(req.query.auth || '');
      if (req.query.viewOnce !== '1' || !authToken) {
        return res.status(403).json({ success: false, error: 'This attachment requires one-time authenticated access' });
      }
      const viewer = await admin.auth().verifyIdToken(authToken);
      const participants = conversationId.split(',');
      if (!participants.includes(viewer.uid)) {
        return res.status(403).json({ success: false, error: 'Not allowed to open this one-time attachment' });
      }
      if (viewer.uid !== meta.ownerUid) {
        const viewedBy = Array.isArray(meta.viewedBy) ? meta.viewedBy : [];
        if (viewedBy.includes(viewer.uid)) {
          return res.status(410).json({ success: false, error: 'This one-time attachment has already been opened' });
        }
        viewedBy.push(viewer.uid);
        meta.viewedBy = viewedBy;
        const tempMetaFile = metaFile + '.' + process.pid + '.tmp';
        fs.writeFileSync(tempMetaFile, JSON.stringify(meta), { mode: 0o600 });
        fs.renameSync(tempMetaFile, metaFile);
      }
    }
    res.setHeader('Content-Type', meta.mimeType || 'application/octet-stream');
    res.setHeader('Content-Disposition', 'inline; filename="' + String(meta.originalName || 'attachment').replace(/["\\\r\n]/g, '_') + '"');
    res.setHeader('Cache-Control', meta.viewOnce || meta.resourceType === 'status' ? 'no-store' : 'private, max-age=3600');
    return res.sendFile(file);
  } catch (_) {
    return res.status(400).json({ success: false, error: 'Invalid media metadata' });
  } finally {
    if (viewOnceLockAcquired) {
      viewOnceLocks.delete(filename);
    }
  }
});

async function tokenFor(uid) {
  const snap = await rtdb.ref('PrivateTokens/' + uid).get();
  return snap.val();
}
async function notificationEnabled(uid, category) {
  try {
    const snap = await rtdb.ref('PrivateUsers/' + uid + '/notificationSettings').get();
    const prefs = snap.val() || {};
    const key = category === 'direct_message' ? 'messages'
      : category === 'group_message' ? 'groups'
      : (category === 'incoming_call' || category === 'group_call') ? 'calls' : null;
    return !key || prefs[key] !== false;
  } catch (_) {
    return true;
  }
}
async function sendDirect(uid, title, body, data) {
  if (!await notificationEnabled(uid, String(data.type || ''))) return;
  const token = await tokenFor(uid);
  if (!token) return;
  try {
    await admin.messaging().send({
      token, notification: { title, body },
      data: Object.fromEntries(Object.entries(data).map(([k,v]) => [k, String(v)])),
      android: { priority: 'high' }
    });
  } catch (e) {
    if (['messaging/registration-token-not-registered','messaging/invalid-registration-token'].includes(e.code)) {
      await rtdb.ref('PrivateTokens/' + uid).remove();
    } else console.error('Direct FCM error:', e.message);
  }
}
async function sendGroup(groupId, messageId, message) {
  const groupSnap = await db.collection('groupChats').doc(groupId).get();
  if (!groupSnap.exists) return;
  const group = groupSnap.data() || {};
  const senderUid = String(message.senderUid || '');
  const sender = await rtdb.ref('PublicUsers/' + senderUid).get();
  const senderName = sender.child('name').val() || 'A member';
  const uids = (Array.isArray(group.memberUids) ? group.memberUids : []).filter(uid => uid !== senderUid);
  const rows = (await Promise.all(uids.map(async uid => ({ uid, token: await tokenFor(uid), enabled: await notificationEnabled(uid, 'group_message') })))).filter(x => x.token && x.enabled);
  for (let i = 0; i < rows.length; i += 500) {
    const batch = rows.slice(i, i + 500);
    const result = await admin.messaging().sendEachForMulticast({
      tokens: batch.map(x => x.token),
      notification: { title: String(group.name || 'ConnectX group'), body: senderName + ': ' + String(message.text || 'New message').slice(0,180) },
      data: { type: 'group_message', groupId, messageId },
      android: { priority: 'high' }
    });
    const invalid = [];
    result.responses.forEach((r, n) => {
      if (!r.success && r.error && ['messaging/registration-token-not-registered','messaging/invalid-registration-token'].includes(r.error.code)) invalid.push(batch[n].uid);
    });
    await Promise.all(invalid.map(uid => rtdb.ref('PrivateTokens/' + uid).remove()));
  }
}

async function sendGroupCallInvitation(callId, call) {
  const groupId = String(call.groupId || '');
  if (!groupId) return;
  const groupSnap = await db.collection('groupChats').doc(groupId).get();
  if (!groupSnap.exists) return;
  const group = groupSnap.data() || {};
  const active = new Set(Array.isArray(call.activeUids) ? call.activeUids : []);
  const memberUids = (Array.isArray(group.memberUids) ? group.memberUids : [])
    .filter(uid => uid && !active.has(uid));
  const rows = (await Promise.all(memberUids.map(async uid => ({
    uid,
    token: await tokenFor(uid),
    enabled: await notificationEnabled(uid, 'group_call')
  })))).filter(row => row.token && row.enabled);
  for (let i = 0; i < rows.length; i += 500) {
    const batch = rows.slice(i, i + 500);
    const result = await admin.messaging().sendEachForMulticast({
      tokens: batch.map(row => row.token),
      notification: {
        title: String(call.groupName || group.name || 'ConnectX group'),
        body: (call.type === 'video' ? 'Group video call started' : 'Group voice call started') + ' · Tap to join'
      },
      data: {
        type: 'group_call',
        callId,
        groupId,
        groupName: String(call.groupName || group.name || 'Group'),
        callType: call.type === 'video' ? 'video' : 'voice'
      },
      android: { priority: 'high' }
    });
    const invalid = [];
    result.responses.forEach((response, index) => {
      if (!response.success && response.error &&
          ['messaging/registration-token-not-registered','messaging/invalid-registration-token'].includes(response.error.code)) {
        invalid.push(batch[index].uid);
      }
    });
    await Promise.all(invalid.map(uid => rtdb.ref('PrivateTokens/' + uid).remove()));
  }
}

async function cleanupExpiredMessages() {
  try {
    const expired = await db.collectionGroup('chats')
      .where('expiresAt', '<=', Date.now()).limit(400).get();
    if (expired.empty) return;
    const batch = db.batch();
    expired.docs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
    console.log('Deleted expired chat messages:', expired.size);
  } catch (e) {
    console.error('Expired-message cleanup error:', e.message);
  }
}

async function cleanupExpiredGroupCalls() {
  try {
    const expired = await db.collection('groupCalls')
      .where('status', '==', 'active')
      .where('expiresAt', '<=', admin.firestore.Timestamp.now())
      .limit(100).get();
    if (expired.empty) return;
    const batch = db.batch();
    expired.docs.forEach(doc => batch.update(doc.ref, {
      status: 'ended',
      endedAt: admin.firestore.FieldValue.serverTimestamp()
    }));
    await batch.commit();
    console.log('Ended expired group calls:', expired.size);
  } catch (error) {
    console.error('Expired group call cleanup error:', error.message);
  }
}

async function cleanupExpiredStatuses() {
  try {
    const expired = await db.collection('statuses')
      .where('expiresAt', '<=', admin.firestore.Timestamp.now())
      .limit(200).get();
    for (const status of expired.docs) {
      const views = await status.ref.collection('views').limit(400).get();
      const batch = db.batch();
      views.docs.forEach(view => batch.delete(view.ref));
      batch.delete(status.ref);
      await batch.commit();
    }
    if (!expired.empty) console.log('Deleted expired statuses:', expired.size);
  } catch (error) {
    console.error('Expired status cleanup error:', error.message);
  }
}

async function cleanupExpiredStatusMedia() {
  try {
    for (const name of fs.readdirSync(UPLOAD_DIR)) {
      if (!name.endsWith('.meta.json')) continue;
      const metaPath = path.join(UPLOAD_DIR, name);
      try {
        const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
        if (meta.resourceType !== 'status' || Number(meta.expiresAt || 0) > Date.now()) continue;
        const mediaPath = metaPath.slice(0, -'.meta.json'.length);
        fs.unlink(mediaPath, () => {});
        fs.unlink(metaPath, () => {});
      } catch (error) {
        console.error('Status media cleanup metadata error:', error.message);
      }
    }
  } catch (error) {
    console.error('Status media cleanup error:', error.message);
  }
}

function startListeners() {
  let directInitial = true;
  db.collectionGroup('chats').onSnapshot(snapshot => {
    if (directInitial) { directInitial = false; console.log('Direct Firestore listener ready; initial documents:', snapshot.size); return; }
    for (const change of snapshot.docChanges()) {
      if (change.type !== 'added') continue;
      const p = change.doc.ref.path.split('/');
      if (p.length !== 4 || p[0] !== 'messages') continue;
      const conversationId = p[1], messageId = p[3], msg = change.doc.data() || {};
      const recipient = conversationId.split(',').find(uid => uid !== msg.sender);
      if (!recipient || !msg.sender) continue;

      // The client must not write into another user's private RTDB profile.
      // Use Admin SDK to publish the conversation index for both participants.
      const indexTimestamp = Number(msg.timestamp) || Date.now();
      const updateIndexes = Promise.all([
        rtdb.ref('PrivateUsers/' + msg.sender + '/chats/personal/' + recipient)
          .set(indexTimestamp),
        rtdb.ref('PrivateUsers/' + recipient + '/chats/personal/' + msg.sender)
          .set(indexTimestamp)
      ]).catch(error => {
        console.error('Direct chat index update failed:', error.message);
      });

      updateIndexes.then(() => rtdb.ref('PublicUsers/' + msg.sender).get()).then(sender => {
        const title = sender.child('name').val() || 'New message';
        const body = msg.type === 'text' ? String(msg.message || 'New message').slice(0,180)
          : msg.type === 'image' ? 'Photo' : msg.type === 'video' ? 'Video'
          : msg.type === 'audio' ? 'Voice message' : msg.type === 'location' ? 'Location'
          : msg.type === 'contact' ? 'Contact' : String(msg.fileName || 'Attachment');
        return sendDirect(recipient, title, body, { type: 'direct_message', conversationId, messageId });
      }).catch(e => console.error('Direct notification error:', e.message));
    }
  }, e => console.error('Direct Firestore listener error:', e.message));

  let callInitial = true;
  const notifiedCalls = new Set();
  db.collection('calls').onSnapshot(snapshot => {
    if (callInitial) { callInitial = false; console.log('Call notification listener ready; initial documents:', snapshot.size); return; }
    for (const change of snapshot.docChanges()) {
      if (change.type !== 'added' && change.type !== 'modified') continue;
      const call = change.doc.data() || {};
      const callId = change.doc.id;
      if (call.status !== 'ringing' || !call.offer || !call.offer.sdp || notifiedCalls.has(callId)) continue;
      const calleeUid = String(call.calleeUid || '');
      const callerUid = String(call.callerUid || '');
      if (!calleeUid || !callerUid) continue;
      notifiedCalls.add(callId);
      const callerName = String(call.callerName || 'ConnectX user');
      const callType = call.type === 'video' ? 'video' : 'voice';
      sendDirect(calleeUid, callerName,
        callType === 'video' ? 'Incoming video call' : 'Incoming voice call',
        { type: 'incoming_call', callId, callerUid, callerName, callType }
      ).catch(e => console.error('Call notification error:', e.message));
    }
  }, e => console.error('Call Firestore listener error:', e.message));

  let groupCallInitial = true;
  const notifiedGroupCalls = new Set();
  db.collection('groupCalls').onSnapshot(snapshot => {
    if (groupCallInitial) {
      groupCallInitial = false;
      console.log('Group call notification listener ready; initial documents:', snapshot.size);
      return;
    }
    for (const change of snapshot.docChanges()) {
      if (change.type !== 'added') continue;
      const call = change.doc.data() || {};
      if (call.status !== 'active' || notifiedGroupCalls.has(change.doc.id)) continue;
      notifiedGroupCalls.add(change.doc.id);
      sendGroupCallInvitation(change.doc.id, call)
        .catch(error => console.error('Group call notification error:', error.message));
    }
  }, error => console.error('Group call Firestore listener error:', error.message));

  let groupInitial = true;
  db.collectionGroup('messages').onSnapshot(snapshot => {
    if (groupInitial) { groupInitial = false; console.log('Group Firestore listener ready; initial documents:', snapshot.size); return; }
    for (const change of snapshot.docChanges()) {
      if (change.type !== 'added') continue;
      const p = change.doc.ref.path.split('/');
      if (p.length === 4 && p[0] === 'groupChats' && p[2] === 'messages') {
        sendGroup(p[1], p[3], change.doc.data() || {}).catch(e => console.error('Group notification error:', e.message));
      }
    }
  }, e => console.error('Group Firestore listener error:', e.message));
}
app.use((err, _req, res, _next) => {
  const status = err instanceof multer.MulterError ? (err.code === 'LIMIT_FILE_SIZE' ? 413 : 400) : 400;
  res.status(status).json({ success: false, error: err.message || 'Request failed' });
});
app.listen(PORT, '0.0.0.0', () => {
  console.log('ConnectX API listening on ' + PORT);
  console.log('Starting Firestore notification listeners...');
  startListeners();
  cleanupExpiredMessages();
  cleanupExpiredGroupCalls();
  cleanupExpiredStatuses();
  cleanupExpiredStatusMedia();
  setInterval(cleanupExpiredMessages, 60 * 60 * 1000);
  setInterval(cleanupExpiredGroupCalls, 5 * 60 * 1000);
  setInterval(cleanupExpiredStatuses, 60 * 60 * 1000);
  setInterval(cleanupExpiredStatusMedia, 60 * 60 * 1000);
});
