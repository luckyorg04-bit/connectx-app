const fs = require('node:fs');
const { test, before, after } = require('node:test');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { ref, get, set } = require('firebase/database');
const { collection, doc, getDoc, getDocs, query, where, setDoc, updateDoc, serverTimestamp } = require('firebase/firestore');

const root = path.resolve(__dirname, '..');
let env;

async function seed() {
  await env.withSecurityRulesDisabled(async (context) => {
    const database = context.database();
    await set(ref(database, 'PrivateUsers/alice/phone'), '919876543210');
    await set(ref(database, 'PrivateUsers/bob/phone'), '919876543211');
    await set(ref(database, 'PublicUsers/alice'), {
      name: 'Alice', username: 'alice_01', key: 'alice',
      online: true, lastSeen: Date.now(), bio: '', photoUrl: '',
    });
    await setDoc(doc(context.firestore(), 'groupChats/group-1'), {
      name: 'Team', createdBy: 'alice',
      memberUids: ['alice', 'bob'], adminUids: ['alice'],
    });
    await setDoc(doc(context.firestore(), 'groupCalls/group-call-1'), {
      groupId: 'group-1', groupName: 'Team', groupMemberUids: ['alice', 'bob'],
      createdBy: 'alice', participants: ['alice', 'bob'], activeUids: ['alice', 'bob'],
      type: 'voice', status: 'active', expiresAt: new Date(Date.now() + 60 * 60 * 1000),
    });
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'connectx-rules-test',
    database: { rules: fs.readFileSync(path.join(root, 'database.rules.json'), 'utf8') },
    firestore: { rules: fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8') },
  });
  await seed();
});

after(async () => {
  if (env) await env.cleanup();
});

test('Realtime Database keeps private profile and phone number private', async () => {
  const alice = env.authenticatedContext('alice').database();
  const bob = env.authenticatedContext('bob').database();

  await assertSucceeds(get(ref(alice, 'PrivateUsers/alice/phone')));
  await assertFails(get(ref(bob, 'PrivateUsers/alice/phone')));
  await assertFails(set(ref(alice, 'PrivateUsers/alice/phone'), '911111111111'));
  await assertFails(set(ref(alice, 'PhoneLookup/fake-hash'), 'alice'));
  await assertFails(get(ref(alice, 'PhoneLookup/fake-hash')));
  await assertFails(set(ref(alice, 'PhoneRegistrationRateLimits/alice'), { count: 1 }));
  await assertFails(get(ref(alice, 'PhoneRegistrationRateLimits/alice')));
});

test('Realtime Database permits only the intended owner preference writes', async () => {
  const alice = env.authenticatedContext('alice').database();
  const bob = env.authenticatedContext('bob').database();

  await assertSucceeds(set(ref(alice, 'PrivateUsers/alice/chatMeta/bob/muted'), true));
  await assertSucceeds(set(ref(alice, 'PrivateUsers/alice/notificationSettings/messages'), false));
  await assertSucceeds(set(ref(alice, 'PrivateUsers/alice/appSettings/themeMode'), 'dark'));
  await assertSucceeds(set(ref(alice, 'PrivateUsers/alice/appSettings/languageCode'), 'hi'));
  await assertFails(set(ref(bob, 'PrivateUsers/alice/chatMeta/bob/muted'), false));
  await assertFails(set(ref(alice, 'PrivateUsers/alice/unreviewedAdminFlag'), true));
});

test('Firestore direct messages are limited to conversation participants', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  const charlie = env.authenticatedContext('charlie').firestore();

  const message = doc(alice, 'messages/alice,bob/chats/message-1');
  await assertSucceeds(setDoc(message, {
    sender: 'alice', message: 'Hello', timestamp: Date.now(),
    isRead: false, isDelivered: false,
  }));
  await assertFails(getDoc(doc(charlie, 'messages/alice,bob/chats/message-1')));
  await assertFails(setDoc(doc(alice, 'messages/alice,bob/chats/forged'), {
    sender: 'bob', message: 'Spoofed sender', timestamp: Date.now(),
    isRead: false, isDelivered: false,
  }));
  await assertSucceeds(updateDoc(message, { 'reactions.alice': '❤️' }));
  await assertSucceeds(updateDoc(message, { 'reactions.bob': '👍' }));
  await assertFails(updateDoc(message, { 'reactions.alice': '😂' }));
});


test('Firestore status feed is readable to signed-in users and media audience is recorded', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  const bob = env.authenticatedContext('bob').firestore();
  const charlie = env.authenticatedContext('charlie').firestore();
  const status = doc(alice, 'statuses/status-1');

  await assertSucceeds(setDoc(status, {
    ownerUid: 'alice',
    statusText: 'Hello ConnectX',
    mediaType: 'text',
    audienceUids: ['alice', 'bob'],
    expiresAt: new Date(Date.now() + 60 * 60 * 1000),
  }));
  await assertSucceeds(getDoc(doc(bob, 'statuses/status-1')));
  await assertFails(getDoc(doc(charlie, 'statuses/status-1')));
  await assertSucceeds(getDocs(query(collection(bob, 'statuses'), where('expiresAt', '>', new Date()))));
});

test('Firestore direct call records are restricted to their participants', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  const bob = env.authenticatedContext('bob').firestore();
  const charlie = env.authenticatedContext('charlie').firestore();
  const call = doc(alice, 'calls/call-1');

  await assertSucceeds(setDoc(call, {
    callerUid: 'alice',
    calleeUid: 'bob',
    participants: ['alice', 'bob'],
    type: 'voice',
    status: 'ringing',
    createdAt: serverTimestamp(),
  }));
  await assertSucceeds(getDoc(doc(bob, 'calls/call-1')));
  await assertSucceeds(getDocs(query(collection(bob, 'calls'), where('participants', 'array-contains', 'bob'))));
  await assertFails(getDoc(doc(charlie, 'calls/call-1')));
});

test('Firestore group call list query is restricted to participants', async () => {
  const bob = env.authenticatedContext('bob').firestore();
  const charlie = env.authenticatedContext('charlie').firestore();

  await assertSucceeds(getDocs(query(
    collection(bob, 'groupCalls'),
    where('participants', 'array-contains', 'bob'),
  )));
  await assertSucceeds(getDocs(query(
    collection(charlie, 'groupCalls'),
    where('participants', 'array-contains', 'charlie'),
  )));
});

test('Firestore group creation requires the creator and at least one other member', async () => {
  const alice = env.authenticatedContext('alice').firestore();

  await assertFails(setDoc(doc(alice, 'groupChats/solo-group'), {
    name: 'Solo', createdBy: 'alice',
    memberUids: ['alice'], adminUids: ['alice'],
  }));
  await assertSucceeds(setDoc(doc(alice, 'groupChats/team-group'), {
    name: 'Team', description: 'Project team', createdBy: 'alice',
    memberUids: ['alice', 'bob'], adminUids: ['alice'],
  }));
});

test('Firestore group messages require membership and sender identity', async () => {
  const bob = env.authenticatedContext('bob').firestore();
  const charlie = env.authenticatedContext('charlie').firestore();

  await assertSucceeds(setDoc(doc(bob, 'groupChats/group-1/messages/message-1'), {
    senderUid: 'bob', text: 'Group hello', type: 'text',
    createdAt: new Date(),
  }));
  await assertFails(getDoc(doc(charlie, 'groupChats/group-1/messages/message-1')));
  await assertFails(setDoc(doc(charlie, 'groupChats/group-1/messages/forged'), {
    senderUid: 'bob', text: 'Spoofed', type: 'text',
    createdAt: new Date(),
  }));
});

test('Firestore group administration is restricted to admins', async () => {
  const bob = env.authenticatedContext('bob').firestore();
  const alice = env.authenticatedContext('alice').firestore();

  await assertFails(updateDoc(doc(bob, 'groupChats/group-1'), { name: 'Hijacked' }));
  await assertSucceeds(updateDoc(doc(alice, 'groupChats/group-1'), { name: 'Team Updated' }));
});
