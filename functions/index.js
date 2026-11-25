const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp({
  databaseURL: 'https://connectx-app-f8407-default-rtdb.firebaseio.com'
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
      ? oldPhoneValue.replace(/\D/g, '')
      : '';

    if (oldPhone === phone) return { success: true, unchanged: true };

    const registrationRateRef = admin.database().ref('PhoneRegistrationRateLimits/' + uid);
    const now = Date.now();
    const rateResult = await registrationRateRef.transaction(current => {
      const previous = current && typeof current === 'object' ? current : {};
      const windowStart = Number(previous.windowStart) || now;
      const count = now - windowStart >= 3600000 ? 1 : (Number(previous.count) || 0) + 1;
      if (count > 5) return;
      return { windowStart: count === 1 ? now : windowStart, count };
    });
    if (!rateResult.committed) {
      throw new functions.https.HttpsError('resource-exhausted', 'Too many phone registration attempts. Try again later.');
    }

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
