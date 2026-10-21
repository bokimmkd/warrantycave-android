'use strict';

const crypto = require('node:crypto');
const {onCall, onRequest, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret} = require('firebase-functions/params');
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const {createAppleStore} = require('./apple_billing');
const {referralRewardExpiryMs} = require('./referral');

const applePrivateKey = defineSecret('APPLE_IAP_PRIVATE_KEY');
const functionOptions = {region: 'us-central1', secrets: [applePrivateKey]};

function registerAppleFunctions({db, requireUser, entitlements}) {
  const store = () => createAppleStore(applePrivateKey.value());
  const accountRef = (uid) => db.collection('appleBillingAccounts').doc(uid);
  const subscriptionRef = (environment, id) =>
    db.collection('appleSubscriptions').doc(`${environment}-${id}`);

  async function save(current, uid, startedAt) {
    const {transaction, state, environment} = current;
    const token = transaction.appAccountToken;
    if (!token || !/^[a-f0-9-]{36}$/i.test(token)) {
      throw new HttpsError('failed-precondition', 'This purchase is not linked to a WarrantyCave account.');
    }
    const ref = subscriptionRef(environment, transaction.originalTransactionId);
    await db.runTransaction(async (tx) => {
      const [account, previous, userSnap] = await Promise.all([
        tx.get(accountRef(uid)), tx.get(ref), tx.get(db.collection('users').doc(uid)),
      ]);
      if (!userSnap.exists || account.data()?.token !== token ||
          (previous.exists && previous.data().uid !== uid)) {
        throw new HttpsError('permission-denied', 'This App Store purchase belongs to another account.');
      }
      if ((previous.data()?.verificationStartedAt || 0) > startedAt) return;
      const user = userSnap.data();
      const inviterUid = state && Number(transaction.price || 0) > 0 &&
          !user.referralRewardedAt && user.referralInviterUid &&
          user.referralInviterUid !== uid ? user.referralInviterUid : null;
      const inviterRef = inviterUid ? db.collection('users').doc(inviterUid) : null;
      const inviter = inviterRef ? await tx.get(inviterRef) : null;
      tx.set(ref, {
        uid, environment, originalTransactionId: transaction.originalTransactionId,
        transactionId: transaction.transactionId, productId: transaction.productId,
        plan: state?.plan || 'free',
        expiresAt: state ? Timestamp.fromMillis(state.expiresAt) : null,
        autoRenewing: state?.autoRenewing || false,
        verificationStartedAt: startedAt, verifiedAt: FieldValue.serverTimestamp(),
      });
      if (inviter?.exists) {
        const rewardUntil = Timestamp.fromMillis(referralRewardExpiryMs(
          Date.now(), inviter.data().referralPlusUntil?.toMillis?.() || 0));
        tx.update(db.collection('users').doc(uid), {
          referralStatus: 'rewarded', referralRewardedAt: FieldValue.serverTimestamp(),
        });
        tx.update(inviterRef, {
          referralPlusUntil: rewardUntil, referralRewardCount: FieldValue.increment(1),
          lastReferralRewardedAt: FieldValue.serverTimestamp(),
        });
        tx.set(db.collection('referralRewards').doc(uid), {
          inviterUid, invitedUid: uid, rewardUntil: rewardUntil.toDate().toISOString(),
          createdAt: FieldValue.serverTimestamp(),
        });
      }
    });
  }

  async function refresh(uid) {
    const rows = await db.collection('appleSubscriptions').where('uid', '==', uid).get();
    const stale = rows.docs.filter((row) =>
      Date.now() - (row.data().verificationStartedAt || 0) > 5 * 60 * 1000);
    if (stale.length) {
      const apple = store();
      for (const row of stale) {
        const startedAt = Date.now();
        const data = row.data();
        await save(await apple.current(data.originalTransactionId, data.environment), uid, startedAt);
      }
    }
    return (await db.collection('appleSubscriptions').where('uid', '==', uid).get()).docs.map((row) => row.data());
  }

  return {
    refresh,
    getAppleBillingAccount: onCall(functionOptions, async (request) => {
      const auth = requireUser(request);
      if (auth.token.email_verified !== true) throw new HttpsError('failed-precondition', 'Verify your account first.');
      store(); // Fail before checkout if verification has not been configured.
      return db.runTransaction(async (tx) => {
        const ref = accountRef(auth.uid);
        const previous = await tx.get(ref);
        if (previous.exists) return {appAccountToken: previous.data().token};
        const token = crypto.randomUUID();
        tx.create(ref, {token, createdAt: FieldValue.serverTimestamp()});
        tx.create(db.collection('appleAccountTokens').doc(token), {uid: auth.uid});
        return {appAccountToken: token};
      });
    }),
    confirmApplePurchase: onCall(functionOptions, async (request) => {
      const auth = requireUser(request);
      if (auth.token.email_verified !== true) throw new HttpsError('failed-precondition', 'Verify your account first.');
      const apple = store();
      let verified;
      try { verified = await apple.verifyTransaction(request.data?.signedTransaction); }
      catch (_) { throw new HttpsError('invalid-argument', 'Apple purchase verification failed.'); }
      const transaction = verified.payload;
      if (transaction.productId !== request.data?.productId) {
        throw new HttpsError('invalid-argument', 'Apple product mismatch.');
      }
      // The client JWS identifies a transaction; the API supplies its current
      // renewal/refund state. Replaying an old receipt cannot restore a refund.
      const startedAt = Date.now();
      const current = await apple.current(transaction.originalTransactionId, verified.environment);
      await save(current, auth.uid, startedAt);
      return entitlements(auth);
    }),
    onAppleSubscriptionUpdate: onRequest(functionOptions, async (request, response) => {
      if (request.method !== 'POST') { response.sendStatus(405); return; }
      if (!request.body?.signedPayload ||
          typeof request.body.signedPayload !== 'string' ||
          request.body.signedPayload.length > 100000) { response.sendStatus(400); return; }
      const apple = store();
      let notification;
      try { notification = await apple.verifyNotification(request.body.signedPayload); }
      catch (_) { response.sendStatus(400); return; }
      if (notification.payload.notificationType === 'TEST') { response.sendStatus(200); return; }
      const signed = notification.payload.data?.signedTransactionInfo;
      if (!signed) { response.sendStatus(200); return; }
      try {
        const verified = await apple.verifyTransaction(signed);
        if (verified.environment !== notification.environment) { response.sendStatus(400); return; }
        const token = verified.payload.appAccountToken;
        if (typeof token !== 'string' || !/^[a-f0-9-]{36}$/i.test(token)) { response.sendStatus(200); return; }
        const account = await db.collection('appleAccountTokens').doc(token).get();
        if (!account.exists) { response.sendStatus(200); return; }
        const startedAt = Date.now();
        const current = await apple.current(verified.payload.originalTransactionId, verified.environment);
        await save(current, account.data().uid, startedAt);
        response.sendStatus(200);
      } catch (_) {
        // Apple retries failed notifications. Never log signed payloads or keys.
        response.sendStatus(503);
      }
    }),
  };
}

module.exports = {applePrivateKey, registerAppleFunctions};
