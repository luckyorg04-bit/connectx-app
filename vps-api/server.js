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
fs.mkdirSync(UPLOAD_DIR, { recursive: true });

app.set('trust proxy', 1);
app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
app.use(cors({ origin: true, methods: ['GET', 'POST'], allowedHeaders: ['Authorization', 'Content-Type'] }));
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

app.post('/api/upload', authenticate, upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ success: false, error: 'Select a file to upload' });
  const conversationId = String(req.body.conversationId || '');
  const participants = conversationId.split(',');
  if (participants.length !== 2 || !participants.includes(req.user.uid)) {
    fs.unlink(req.file.path, () => {});
    return res.status(403).json({ success: false, error: 'Not a participant in this conversation' });
  }
  const originalName = path.basename(req.file.originalname || 'attachment');
  const mimeType = types[path.extname(req.file.filename).toLowerCase()];
  const meta = { conversationId, ownerUid: req.user.uid, originalName, mimeType, size: req.file.size };
  fs.writeFileSync(req.file.path + '.meta.json', JSON.stringify(meta), { mode: 0o600 });
  const token = sign(req.file.filename, conversationId);
  const url = 'https://connecttx.duckdns.org/media/' + encodeURIComponent(req.file.filename) +
    '?conversationId=' + encodeURIComponent(conversationId) + '&token=' + token;
  return res.status(201).json({ success: true, fileName: originalName, storedName: req.file.filename, mimeType, size: req.file.size, url });
});

// Signed capability URL: anyone with the complete URL can access the file.
// Keep media URLs inside the intended conversation.
app.get('/media/:filename', (req, res) => {
  const filename = path.basename(req.params.filename);
  const file = path.join(UPLOAD_DIR, filename);
  const metaFile = file + '.meta.json';
  if (!fs.existsSync(file) || !fs.existsSync(metaFile)) return res.status(404).json({ success: false, error: 'File not found' });
  try {
    const meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
    const conversationId = String(req.query.conversationId || '');
    if (meta.conversationId !== conversationId || !equalHex(req.query.token, sign(filename, conversationId))) {
      return res.status(403).json({ success: false, error: 'Invalid media link' });
    }
    res.setHeader('Content-Type', meta.mimeType || 'application/octet-stream');
    res.setHeader('Content-Disposition', 'inline; filename="' + String(meta.originalName || 'attachment').replace(/["\\\r\n]/g, '_') + '"');
    res.setHeader('Cache-Control', 'private, max-age=3600');
    return res.sendFile(file);
  } catch (_) {
    return res.status(400).json({ success: false, error: 'Invalid media metadata' });
  }
});

async function tokenFor(uid) {
  const snap = await rtdb.ref('Users/' + uid + '/fcmToken').get();
  return snap.val();
}
async function sendDirect(uid, title, body, data) {
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
      await rtdb.ref('Users/' + uid + '/fcmToken').remove();
    } else console.error('Direct FCM error:', e.message);
  }
}
async function sendGroup(groupId, messageId, message) {
  const groupSnap = await db.collection('groupChats').doc(groupId).get();
  if (!groupSnap.exists) return;
  const group = groupSnap.data() || {};
  const senderUid = String(message.senderUid || '');
  const sender = await rtdb.ref('Users/' + senderUid).get();
  const senderName = sender.child('name').val() || 'A member';
  const uids = (Array.isArray(group.memberUids) ? group.memberUids : []).filter(uid => uid !== senderUid);
  const rows = (await Promise.all(uids.map(async uid => ({ uid, token: await tokenFor(uid) })))).filter(x => x.token);
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
    await Promise.all(invalid.map(uid => rtdb.ref('Users/' + uid + '/fcmToken').remove()));
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
      rtdb.ref('Users/' + msg.sender).get().then(sender => {
        const title = sender.child('name').val() || 'New message';
        const body = msg.type === 'text' ? String(msg.message || 'New message').slice(0,180)
          : msg.type === 'image' ? 'Photo' : msg.type === 'video' ? 'Video'
          : msg.type === 'audio' ? 'Voice message' : msg.type === 'location' ? 'Location'
          : msg.type === 'contact' ? 'Contact' : String(msg.fileName || 'Attachment');
        return sendDirect(recipient, title, body, { type: 'direct_message', conversationId, messageId });
      }).catch(e => console.error('Direct notification error:', e.message));
    }
  }, e => console.error('Direct Firestore listener error:', e.message));

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
});
