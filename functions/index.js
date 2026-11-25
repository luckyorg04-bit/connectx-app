const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp({
  databaseURL: 'https://connectx-app-f8407-default-rtdb.firebaseio.com'
});

async function sendToUser(uid, title, body, data) {
  const snapshot = await admin.database().ref('PrivateTokens/' + uid).once('value');
  const token = snapshot.val();
  if (!token) return null;

  try {
    return await admin.messaging().send({
      token,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data).map(([key, value]) => [key, String(value)])
      ),
      android: { priority: 'high' }
    });
  } catch (error) {
    if (error.code === 'messaging/registration-token-not-registered' ||
        error.code === 'messaging/invalid-registration-token') {
      await admin.database().ref('PrivateTokens/' + uid).remove();
      return null;
    }
    throw error;
  }
}

exports.notifyDirectMessage = functions
  .region('asia-south1')
  .firestore.document('messages/{conversationId}/chats/{messageId}')
  .onCreate(async (snapshot, context) => {
    const message = snapshot.data();
    const participants = context.params.conversationId.split(',');
    const recipientUid = participants.find(uid => uid !== message.sender);
    if (!recipientUid) return null;

    // Keep both chat lists in sync using trusted Admin SDK writes. Mobile
    // clients are intentionally not allowed to write another user's profile.
    const indexTimestamp = Number(message.timestamp) || Date.now();
    await Promise.all([
      admin.database().ref('PrivateUsers/' + message.sender + '/chats/personal/' + recipientUid)
        .set(indexTimestamp),
      admin.database().ref('PrivateUsers/' + recipientUid + '/chats/personal/' + message.sender)
        .set(indexTimestamp)
    ]);

    // Call history entries are already visible in the conversation. Do not
    // generate a second push notification after a call has ended.
    if (message.type === 'call') return null;

    const recipientPrivate = admin.database().ref('PrivateUsers/' + recipientUid);
    const [muteSnapshot, settingsSnapshot] = await Promise.all([
      recipientPrivate.child('chatMeta/' + message.sender + '/muted').once('value'),
      recipientPrivate.child('notificationSettings/messages').once('value')
    ]);
    if (muteSnapshot.val() === true || settingsSnapshot.val() === false) return null;

    const senderSnapshot = await admin.database()
      .ref('PublicUsers/' + message.sender).once('value');
    const senderName = senderSnapshot.child('name').val() || 'New message';
    const body = message.type === 'text'
      ? String(message.message || 'New message')
      : message.type === 'image' ? '📷 Photo'
      : message.type === 'video' ? '🎥 Video'
      : message.type === 'audio' ? '🎤 Voice message'
      : message.type === 'location' ? '📍 Location'
      : message.type === 'contact' ? '👤 Contact'
      : '📎 ' + String(message.fileName || 'Attachment');

    return sendToUser(recipientUid, senderName, body, {
      type: 'direct_message',
      conversationId: context.params.conversationId,
      messageId: context.params.messageId
    });
  });

exports.notifyGroupMessage = functions
  .region('asia-south1')
  .firestore.document('groupChats/{groupId}/messages/{messageId}')
  .onCreate(async (snapshot, context) => {
    const message = snapshot.data();
    const groupSnapshot = await admin.firestore()
      .collection('groupChats').doc(context.params.groupId).get();
    if (!groupSnapshot.exists) return null;

    const group = groupSnapshot.data();
    const memberUids = Array.isArray(group.memberUids) ? group.memberUids : [];
    const senderUid = message.senderUid;
    const senderSnapshot = await admin.database()
      .ref('PublicUsers/' + senderUid).once('value');
    const senderName = senderSnapshot.child('name').val() || 'A member';
    const title = String(group.name || 'ConnectX group');
    const body = senderName + ': ' + String(message.text || 'New group message');
    const recipients = memberUids.filter(uid => uid !== senderUid);

    const tokens = [];
    for (const uid of recipients) {
      const privateRef = admin.database().ref('PrivateUsers/' + uid);
      const [tokenSnapshot, settingsSnapshot] = await Promise.all([
        admin.database().ref('PrivateTokens/' + uid).once('value'),
        privateRef.child('notificationSettings/groups').once('value')
      ]);
      if (settingsSnapshot.val() === false) continue;
      const token = tokenSnapshot.val();
      if (token) tokens.push({ uid, token });
    }
    if (!tokens.length) return null;

    const response = await admin.messaging().sendEachForMulticast({
      tokens: tokens.map(item => item.token),
      notification: { title, body },
      data: {
        type: 'group_message',
        groupId: context.params.groupId,
        messageId: context.params.messageId
      },
      android: { priority: 'high' }
    });

    const invalid = [];
    response.responses.forEach((result, index) => {
      if (!result.success && (
        result.error.code === 'messaging/registration-token-not-registered' ||
        result.error.code === 'messaging/invalid-registration-token'
      )) invalid.push(tokens[index].uid);
    });
    await Promise.all(invalid.map(uid =>
      admin.database().ref('PrivateTokens/' + uid).remove()
    ));
    return null;
  });

// Send an incoming-call alert only after the caller has published a usable SDP
// offer. The call document is created before camera/microphone setup; notifying
// onCreate would let the callee answer before the offer exists.
exports.notifyIncomingCall = functions
  .region('asia-south1')
  .firestore.document('calls/{callId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const call = change.after.data() || {};

    if (before.status !== 'ringing' ||
        call.status !== 'ringing' ||
        (before.offer && before.offer.sdp) ||
        !call.offer ||
        typeof call.offer.sdp !== 'string' ||
        !call.offer.sdp.trim()) {
      return null;
    }

    if (!call.calleeUid || !call.callerUid || call.calleeUid === call.callerUid) {
      console.error('Incoming call notification skipped: invalid participants', context.params.callId);
      return null;
    }

    const callNotifications = await admin.database()
      .ref('PrivateUsers/' + call.calleeUid + '/notificationSettings/calls').once('value');
    if (callNotifications.val() === false) return null;

    return sendToUser(
      call.calleeUid,
      String(call.callerName || 'ConnectX user'),
      call.type === 'video' ? 'Incoming video call' : 'Incoming voice call',
      {
        type: 'incoming_call',
        callId: context.params.callId,
        callerUid: call.callerUid,
        callerName: String(call.callerName || 'ConnectX user'),
        callType: call.type === 'video' ? 'video' : 'voice'
      }
    );
  });

exports.notifyGroupCall = functions
  .region('asia-south1')
  .firestore.document('groupCalls/{callId}')
  .onCreate(async (snapshot, context) => {
    const call = snapshot.data() || {};
    if (call.status !== 'active' || !call.groupId) return null;
    const groupSnapshot = await admin.firestore().collection('groupChats').doc(String(call.groupId)).get();
    if (!groupSnapshot.exists) return null;
    const group = groupSnapshot.data() || {};
    const creatorUid = String(call.createdBy || '');
    const members = (Array.isArray(group.memberUids) ? group.memberUids : [])
      .filter(uid => typeof uid === 'string' && uid && uid !== creatorUid);
    const recipients = [];
    for (const uid of members) {
      const [tokenSnapshot, settingsSnapshot] = await Promise.all([
        admin.database().ref('PrivateTokens/' + uid).once('value'),
        admin.database().ref('PrivateUsers/' + uid + '/notificationSettings/calls').once('value')
      ]);
      if (settingsSnapshot.val() === false) continue;
      const token = tokenSnapshot.val();
      if (token) recipients.push({ uid, token });
    }
    for (let i = 0; i < recipients.length; i += 500) {
      const batch = recipients.slice(i, i + 500);
      const result = await admin.messaging().sendEachForMulticast({
        tokens: batch.map(item => item.token),
        notification: {
          title: String(call.groupName || group.name || 'ConnectX group'),
          body: (call.type === 'video' ? 'Group video call started' : 'Group voice call started') + ' · Tap to join'
        },
        data: {
          type: 'group_call',
          callId: context.params.callId,
          groupId: String(call.groupId),
          groupName: String(call.groupName || group.name || 'Group'),
          callType: call.type === 'video' ? 'video' : 'voice'
        },
        android: { priority: 'high' }
      });
      const invalid = [];
      result.responses.forEach((response, index) => {
        if (!response.success && response.error &&
            ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(response.error.code)) {
          invalid.push(batch[index].uid);
        }
      });
      await Promise.all(invalid.map(uid => admin.database().ref('PrivateTokens/' + uid).remove()));
    }
    return null;
  });



// Phone lookup is performed only by authenticated callable functions. The
// phone index is never readable or writable directly by mobile clients.
const crypto = require('crypto');

function normalizePhoneNumber(value) {
  if (typeof value !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'A phone number is required.');
  }
  const digits = value.replace(/\D/g, '');
  if (digits.length < 7 || digits.length > 15) {
    throw new functions.https.HttpsError('invalid-argument', 'Enter a valid phone number with country code.');
  }
  return digits;
}

function phoneLookupHash(phone) {
  return crypto.createHash('sha256').update(phone, 'utf8').digest('hex');
}

function authenticatedUid(context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError('unauthenticated', 'Sign in to use phone search.');
  }
  return context.auth.uid;
}

exports.registerPhoneNumber = functions
  .region('asia-south1')
  .https.onCall(async (data, context) => {
    const uid = authenticatedUid(context);
    const phone = normalizePhoneNumber(data && data.phone);
    const hash = phoneLookupHash(phone);
    const lookupRef = admin.database().ref('PhoneLookup/' + hash);
    const privatePhoneRef = admin.database().ref('PrivateUsers/' + uid + '/phone');
    const oldPhoneSnapshot = await privatePhoneRef.once('value');
    const oldPhoneValue = oldPhoneSnapshot.val();
    const oldPhone = typeof oldPhoneValue === 'string'
      ? oldPhoneValue.replace(/\\D/g, '')
      : '';

    if (oldPhone === phone) return { success: true, unchanged: true };

    // Reserve the new number atomically before changing the user's private
    // profile. A different UID can never take an already-reserved number.
    const reservation = await lookupRef.transaction(current => {
      if (current === null || current === uid) return uid;
      return;
    });

    if (!reservation.committed) {
      throw new functions.https.HttpsError('already-exists', 'This phone number is already linked to another ConnectX account.');
    }

    try {
      await privatePhoneRef.set(phone);
      if (oldPhone && oldPhone !== phone) {
        await admin.database().ref('PhoneLookup/' + phoneLookupHash(oldPhone))
          .transaction(current => current === uid ? null : current);
      }
      return { success: true };
    } catch (error) {
      // Release only the reservation created by this account. Never remove a
      // mapping that another account may have acquired.
      if (oldPhone !== phone) {
        await lookupRef.transaction(current => current === uid ? null : current);
      }
      throw new functions.https.HttpsError('internal', 'Could not save the phone number. Please try again.');
    }
  });

exports.lookupPhoneNumber = functions
  .region('asia-south1')
  .https.onCall(async (data, context) => {
    const uid = authenticatedUid(context);
    const phone = normalizePhoneNumber(data && data.phone);
    const now = Date.now();
    const rateRef = admin.database().ref('PhoneLookupRateLimits/' + uid);

    const rateResult = await rateRef.transaction(current => {
      const previous = current && typeof current === 'object' ? current : {};
      const windowStart = Number(previous.windowStart) || now;
      const count = now - windowStart >= 60000 ? 1 : (Number(previous.count) || 0) + 1;
      if (count > 12) return;
      return { windowStart: count === 1 ? now : windowStart, count };
    });

    if (!rateResult.committed) {
      throw new functions.https.HttpsError('resource-exhausted', 'Too many phone searches. Try again in a minute.');
    }

    const snapshot = await admin.database().ref('PhoneLookup/' + phoneLookupHash(phone)).once('value');
    const targetUid = snapshot.val();
    return { uid: typeof targetUid === 'string' ? targetUid : null };
  });
