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
      const userSnapshot = await admin.database().ref('PrivateTokens/' + uid).once('value');
      const token = userSnapshot.val();
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

// Notify the callee as soon as a direct voice/video call is created.
exports.notifyIncomingCall = functions
  .region('asia-south1')
  .firestore.document('calls/{callId}')
  .onCreate(async (snapshot, context) => {
    const call = snapshot.data() || {};
    const callerUid = String(call.callerUid || '');
    const calleeUid = String(call.calleeUid || '');
    if (!callerUid || !calleeUid || callerUid === calleeUid || call.status !== 'ringing') return null;
    const callerName = String(call.callerName || 'ConnectX user').slice(0, 80);
    return sendToUser(calleeUid, callerName,
      call.type === 'video' ? 'Incoming video call' : 'Incoming voice call', {
        type: 'incoming_call',
        callId: context.params.callId,
        callerUid,
        callerName,
        callType: call.type === 'video' ? 'video' : 'voice'
      });
  });

// Notify every other group member when a group voice/video call starts.
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
      const tokenSnapshot = await admin.database().ref('PrivateTokens/' + uid).once('value');
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

