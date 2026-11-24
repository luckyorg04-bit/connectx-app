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
