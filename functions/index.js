'use strict';

const crypto = require('crypto');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {onMessagePublished} = require('firebase-functions/v2/pubsub');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const functionsV1 = require('firebase-functions/v1');
const {defineSecret} = require('firebase-functions/params');
const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {GoogleAuth} = require('google-auth-library');
const vision = require('@google-cloud/vision');
const {parseReceipt} = require('./receipt_parser');
const {renderEmail} = require('./transactional_email');
const {deferralState} = require('./play_deferral');
const {
  normalizeCode,
  referralCodeForUid,
  referralRewardExpiryMs,
} = require('./referral');

initializeApp();
const db = getFirestore();
const visionClient = new vision.ImageAnnotatorClient();
const OWNER_EMAIL = 'bokimk.ap@gmail.com';
const ONE_YEAR_MS = 365 * 24 * 60 * 60 * 1000;
const ANDROID_PACKAGE = 'com.warrantycave.app';
const PLAY_PRODUCTS = new Map([
  ['warrantycave_basic_yearly', 'basic'],
  ['warrantycave_plus_yearly', 'plus'],
]);
const androidPublisherAuth = new GoogleAuth({
  scopes: ['https://www.googleapis.com/auth/androidpublisher'],
});
const resendApiKey = defineSecret('RESEND_API_KEY');
const DAY_MS = 24 * 60 * 60 * 1000;

async function queueEmail(id, data) {
  await db.collection('transactionalEmail').doc(id).create({
    ...data, createdAt: FieldValue.serverTimestamp(),
  }).catch((error) => {
    if (error.code !== 6 && error.code !== 'already-exists') throw error;
  });
}

async function playRequest(path, {method = 'GET', body} = {}) {
  const client = await androidPublisherAuth.getClient();
  const headers = await client.getRequestHeaders();
  const requestHeaders = new Headers(headers);
  if (body) requestHeaders.set('Content-Type', 'application/json');
  const response = await fetch(`https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${ANDROID_PACKAGE}${path}`, {
    method,
    headers: requestHeaders,
    ...(body ? {body: JSON.stringify(body)} : {}),
  });
  if (response.status === 401 || response.status === 403) {
    throw new HttpsError('failed-precondition', 'Google Play Developer API access is not configured.');
  }
  if (response.status === 404) throw new HttpsError('not-found', 'Subscription not found in Google Play.');
  if (!response.ok) throw new HttpsError('unavailable', `Google Play request failed (${response.status}).`);
  return response.json();
}

function activeLine(purchase) {
  return (purchase.lineItems || [])
    .filter((line) => PLAY_PRODUCTS.has(line.productId) && Date.parse(line.expiryTime || '') > Date.now())
    .sort((a, b) => Date.parse(b.expiryTime) - Date.parse(a.expiryTime))[0];
}

function purchaseDetails(purchase) {
  const line = activeLine(purchase);
  if (!line) return null;
  return {
    line,
    expiry: new Date(line.expiryTime),
    autoRenewing: line.autoRenewingPlan?.autoRenewEnabled === true &&
      purchase.subscriptionState === 'SUBSCRIPTION_STATE_ACTIVE',
  };
}

function requireUser(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in is required.');
  return request.auth;
}

function codeHash(code) {
  return crypto.createHash('sha256').update(code).digest('hex');
}

exports.registerReferralSignup = onCall({region: 'us-central1'}, async (request) => {
  const auth = requireUser(request);
  const ownCode = referralCodeForUid(auth.uid);
  const invitedByCode = normalizeCode(request.data?.invitedByCode);
  if (invitedByCode && (invitedByCode.length < 6 || invitedByCode.length > 24)) {
    throw new HttpsError('invalid-argument', 'Invalid referral code.');
  }
  if (invitedByCode === ownCode) {
    throw new HttpsError('failed-precondition', 'You cannot use your own referral code.');
  }
  const userRef = db.collection('users').doc(auth.uid);
  const ownCodeRef = db.collection('referralCodes').doc(ownCode);
  const inviterCodeRef = invitedByCode
    ? db.collection('referralCodes').doc(invitedByCode)
    : null;

  return db.runTransaction(async (transaction) => {
    const reads = [transaction.get(userRef), transaction.get(ownCodeRef)];
    if (inviterCodeRef) reads.push(transaction.get(inviterCodeRef));
    const [userSnap, ownCodeSnap, inviterCodeSnap] = await Promise.all(reads);
    const existing = userSnap.data() || {};
    if (ownCodeSnap.exists && ownCodeSnap.data()?.uid !== auth.uid) {
      throw new HttpsError('already-exists', 'Referral code collision.');
    }

    let inviterUid = null;
    if (inviterCodeRef) {
      if (!inviterCodeSnap?.exists) {
        throw new HttpsError('not-found', 'Referral code not found.');
      }
      inviterUid = inviterCodeSnap.data()?.uid || null;
      if (!inviterUid || inviterUid === auth.uid) {
        throw new HttpsError('failed-precondition', 'Invalid referral code.');
      }
      if (existing.referralInviterUid && existing.referralInviterUid !== inviterUid) {
        throw new HttpsError('failed-precondition', 'A referral is already registered.');
      }
    }

    transaction.set(ownCodeRef, {
      uid: auth.uid,
      code: ownCode,
      createdAt: ownCodeSnap.exists
        ? ownCodeSnap.data()?.createdAt || FieldValue.serverTimestamp()
        : FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(userRef, {
      referralCode: ownCode,
      referralCreatedAt: existing.referralCreatedAt || FieldValue.serverTimestamp(),
      ...(inviterUid && !existing.referralRewardedAt ? {
        pendingReferralCode: invitedByCode,
        referralInviterUid: inviterUid,
        referralStatus: 'awaiting_first_paid_purchase',
      } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {referralCode: ownCode, referralStatus: inviterUid
      ? 'awaiting_first_paid_purchase'
      : existing.referralStatus || 'registered'};
  });
});

exports.redeemFounderCode = onCall({region: 'us-central1'}, async (request) => {
  const auth = requireUser(request);
  const code = normalizeCode(request.data?.code);
  if (code.length < 10 || code.length > 32) throw new HttpsError('invalid-argument', 'Invalid code.');
  const codeRef = db.collection('founderCodes').doc(codeHash(code));
  const userRef = db.collection('users').doc(auth.uid);
  return db.runTransaction(async (transaction) => {
    const [codeSnap, userSnap] = await Promise.all([transaction.get(codeRef), transaction.get(userRef)]);
    if (!codeSnap.exists) throw new HttpsError('not-found', 'Code not found.');
    const promo = codeSnap.data();
    if (promo.disabled === true || promo.redeemedBy) throw new HttpsError('already-exists', 'Code already used.');
    const now = Date.now();
    const current = userSnap.data()?.promotionalBasicUntil?.toMillis?.() || 0;
    const startsAt = Math.max(now, current);
    const expiresAt = Timestamp.fromMillis(startsAt + ONE_YEAR_MS);
    transaction.update(codeRef, {redeemedBy: auth.uid, redeemedAt: FieldValue.serverTimestamp()});
    transaction.set(userRef, {
      promotionalBasicUntil: expiresAt,
      entitlementSource: 'founder_code',
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {plan: 'basic', expiresAt: expiresAt.toDate().toISOString()};
  });
});

exports.smartScanReceipt = onCall({region: 'us-central1', timeoutSeconds: 60, memory: '512MiB'}, async (request) => {
  const auth = requireUser(request);
  const imageBase64 = String(request.data?.imageBase64 || '');
  if (!imageBase64 || imageBase64.length > 10_000_000) throw new HttpsError('invalid-argument', 'Receipt image is missing or too large.');
  const userRef = db.collection('users').doc(auth.uid);
  const userSnap = await userRef.get();
  const isOwner = String(auth.token.email || '').toLowerCase() === OWNER_EMAIL;
  const credits = Number(userSnap.data()?.smartScanCredits || 0);
  if (!isOwner && credits < 1) throw new HttpsError('resource-exhausted', 'No Smart Scan credits.');

  const [result] = await visionClient.textDetection({image: {content: imageBase64}});
  const text = result.fullTextAnnotation?.text || result.textAnnotations?.[0]?.description || '';
  if (!text.trim()) throw new HttpsError('not-found', 'No receipt text found.');
  const suggestion = parseReceipt(text);
  let remainingCredits = credits;
  if (!isOwner) {
    await db.runTransaction(async (transaction) => {
      const fresh = await transaction.get(userRef);
      const available = Number(fresh.data()?.smartScanCredits || 0);
      if (available < 1) throw new HttpsError('resource-exhausted', 'No Smart Scan credits.');
      remainingCredits = available - 1;
      transaction.update(userRef, {smartScanCredits: remainingCredits, updatedAt: FieldValue.serverTimestamp()});
    });
  }
  return {...suggestion, remainingCredits: isOwner ? 999 : remainingCredits};
});

exports.getEntitlements = onCall({region: 'us-central1'}, async (request) => {
  const auth = requireUser(request);
  const user = (await db.collection('users').doc(auth.uid).get()).data() || {};
  const now = Date.now();
  const isOwner = String(auth.token.email || '').toLowerCase() === OWNER_EMAIL;
  const paidUntil = user.planExpiresAt?.toMillis?.() || 0;
  const promoUntil = user.promotionalBasicUntil?.toMillis?.() || 0;
  const referralPlusUntil = user.referralPlusUntil?.toMillis?.() || 0;
  let plan = 'free';
  let expiresAt = null;
  if (isOwner) {
    plan = 'plus';
    expiresAt = null;
  } else if (referralPlusUntil > now) {
    plan = 'plus';
    expiresAt = new Date(user.plan === 'plus' ? Math.max(referralPlusUntil, paidUntil) : referralPlusUntil).toISOString();
  } else if (paidUntil > now && ['basic', 'plus'].includes(user.plan)) {
    plan = user.plan;
    expiresAt = user.planExpiresAt.toDate().toISOString();
  } else if (promoUntil > now) {
    plan = 'basic';
    expiresAt = user.promotionalBasicUntil.toDate().toISOString();
  }
  return {
    plan, expiresAt,
    paidExpiresAt: paidUntil > now ? user.planExpiresAt.toDate().toISOString() : null,
    referralPlusUntil: referralPlusUntil > now ? user.referralPlusUntil.toDate().toISOString() : null,
    nextBillingAt: paidUntil > now && user.playAutoRenewing === true
      ? user.planExpiresAt.toDate().toISOString() : null,
    smartScanCredits: isOwner ? 999 : Number(user.smartScanCredits || 0),
  };
});

exports.confirmPlayPurchase = onCall({region: 'us-central1'}, async (request) => {
  const auth = requireUser(request);
  const suppliedProductId = String(request.data?.productId || '');
  const purchaseToken = String(request.data?.purchaseToken || '');
  if (!PLAY_PRODUCTS.has(suppliedProductId) || purchaseToken.length < 16 || purchaseToken.length > 4096) {
    throw new HttpsError('invalid-argument', 'Invalid Google Play purchase.');
  }

  const purchase = await playRequest(`/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`);
  const details = purchaseDetails(purchase);
  if (!details) {
    throw new HttpsError('failed-precondition', 'This subscription is not active.');
  }
  const {line, expiry: expiresAt, autoRenewing} = details;
  if (line.productId !== suppliedProductId) {
    throw new HttpsError('permission-denied', 'Purchase product mismatch.');
  }
  const plan = PLAY_PRODUCTS.get(line.productId);
  const userRef = db.collection('users').doc(auth.uid);
  const tokenHash = codeHash(purchaseToken);
  const tokenRef = db.collection('playPurchaseTokens').doc(tokenHash);
  await db.runTransaction(async (transaction) => {
    const [userSnap, tokenSnap] = await Promise.all([
      transaction.get(userRef),
      transaction.get(tokenRef),
    ]);
    const userData = userSnap.data() || {};
    if (tokenSnap.exists && tokenSnap.data()?.uid !== auth.uid) {
      throw new HttpsError('permission-denied', 'This purchase belongs to another account.');
    }
    const inviterUid = userData.referralStatus === 'awaiting_first_paid_purchase'
      ? userData.referralInviterUid
      : null;
    const inviterRef = inviterUid ? db.collection('users').doc(inviterUid) : null;
    const inviterSnap = inviterRef ? await transaction.get(inviterRef) : null;

    transaction.set(tokenRef, {
      uid: auth.uid,
      productId: line.productId,
      // Server-only collection. Needed to defer a referred subscriber's renewal.
      purchaseToken,
      createdAt: tokenSnap.exists
        ? tokenSnap.data()?.createdAt || FieldValue.serverTimestamp()
        : FieldValue.serverTimestamp(),
      verifiedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(userRef, {
      plan,
      planExpiresAt: Timestamp.fromDate(expiresAt),
      playProductId: line.productId,
      playPurchaseTokenHash: tokenHash,
      playSubscriptionState: purchase.subscriptionState || null,
      playAutoRenewing: autoRenewing,
      entitlementSource: 'google_play',
      ...(inviterRef ? {
        referralStatus: 'rewarded',
        referralRewardedAt: FieldValue.serverTimestamp(),
      } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    if (!tokenSnap.exists && auth.token.email) {
      transaction.set(db.collection('transactionalEmail').doc(`subscription-${tokenHash}`), {
        type: 'subscribed', to: auth.token.email,
        plan, expiresAt: expiresAt.toISOString(), autoRenewing,
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    if (inviterRef && inviterSnap?.exists) {
      const currentReward = inviterSnap.data()?.referralPlusUntil?.toMillis?.() || 0;
      const rewardUntil = Timestamp.fromMillis(
        referralRewardExpiryMs(Date.now(), currentReward),
      );
      transaction.set(inviterRef, {
        referralPlusUntil: rewardUntil,
        referralRewardCount: FieldValue.increment(1),
        lastReferralRewardedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(db.collection('referralRewards').doc(auth.uid), {
        inviterUid, invitedUid: auth.uid,
        rewardUntil: rewardUntil.toDate().toISOString(),
        createdAt: FieldValue.serverTimestamp(),
      });
    }
  });

  // Restoring a pre-existing purchase supplies tokens for pending referral deferrals.
  const pending = await db.collection('referralRewards').where('inviterUid', '==', auth.uid)
    .get();
  for (const reward of pending.docs) {
    if (reward.data().status !== 'waiting_for_purchase_token') continue;
    try {
      await applyReferralReward(reward.id);
    } catch (error) {
      console.error('Referral deferral will retry', reward.id, error);
    }
  }

  return {plan, expiresAt: expiresAt.toISOString(),
    paidExpiresAt: expiresAt.toISOString(),
    nextBillingAt: autoRenewing ? expiresAt.toISOString() : null};
});

// Firebase Auth emits these after creation/deletion, including Google sign-in accounts.
exports.onAccountCreated = functionsV1.region('us-central1').auth.user().onCreate(async (user) => {
  if (user.email) await queueEmail(`welcome-${user.uid}`, {
    type: 'welcome', to: user.email, name: user.displayName || '',
  });
});

exports.onAccountDeleted = functionsV1.region('us-central1').auth.user().onDelete(async (user) => {
  if (user.email) await queueEmail(`deleted-${user.uid}`, {
    type: 'deleted', to: user.email, name: user.displayName || '',
  });
});

exports.sendTransactionalEmail = onDocumentCreated({
  document: 'transactionalEmail/{emailId}', region: 'us-central1',
  secrets: [resendApiKey], retry: true,
}, async (event) => {
  const mail = event.data?.data();
  if (!mail?.to || !mail.type) return;
  const {subject, html, text} = renderEmail(mail.type, mail);
  const secret = resendApiKey.value();
  if (!secret) throw new Error('RESEND_API_KEY is missing. Configure the verified sender before enabling email delivery.');
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${secret}`,
      'Content-Type': 'application/json',
      'Idempotency-Key': event.params.emailId,
    },
    body: JSON.stringify({
      from: 'WarrantyCave <updates@warrantycave.com>',
      to: [mail.to], subject, html, text,
    }),
  });
  if (!response.ok) throw new Error(`Email provider returned ${response.status}: ${(await response.text()).slice(0, 500)}`);
  const result = await response.json();
  await event.data.ref.update({sentAt: FieldValue.serverTimestamp(), providerId: result.id || null});
});

exports.remindBeforeSubscriptionDate = onSchedule({
  schedule: 'every day 09:00', timeZone: 'Etc/UTC', region: 'us-central1',
}, async () => {
  const now = Date.now();
  // Daily cadence: the date falls within half a day of seven full days away.
  const from = Timestamp.fromMillis(now + Math.round(6.5 * DAY_MS));
  const until = Timestamp.fromMillis(now + Math.round(7.5 * DAY_MS));
  const users = await db.collection('users').where('playProductId', 'in',
    [...PLAY_PRODUCTS.keys()]).get();
  for (const doc of users.docs) {
    const user = doc.data();
    if (!PLAY_PRODUCTS.has(user.playProductId)) continue;
    const tokenSnap = user.playPurchaseTokenHash
      ? await db.collection('playPurchaseTokens').doc(user.playPurchaseTokenHash).get() : null;
    const token = tokenSnap?.data()?.purchaseToken;
    if (!token) continue;
    const purchase = await playRequest(`/purchases/subscriptionsv2/tokens/${encodeURIComponent(token)}`);
    const details = purchaseDetails(purchase);
    if (details && user.planExpiresAt?.toMillis?.() !== details.expiry.getTime()) {
      await doc.ref.update({planExpiresAt: Timestamp.fromDate(details.expiry),
        playAutoRenewing: details.autoRenewing, updatedAt: FieldValue.serverTimestamp()});
    }
    if (!details || details.expiry.getTime() < from.toMillis() ||
        details.expiry.getTime() >= until.toMillis()) continue;
    const expiresAt = details.expiry.toISOString();
    const email = user.email || user.emailLower || (await getAuth().getUser(doc.id)).email;
    if (!email) continue;
    await queueEmail(`reminder-${doc.id}-${details.expiry.getTime()}`, {
      type: 'reminder', to: email, expiresAt,
      autoRenewing: details.autoRenewing,
    });
  }
  const referralRewards = await db.collection('users').where('referralPlusUntil', '>=', from)
    .where('referralPlusUntil', '<', until).get();
  for (const doc of referralRewards.docs) {
    const user = doc.data();
    const rewardEnd = user.referralPlusUntil.toMillis();
    if (user.plan === 'plus' && user.planExpiresAt?.toMillis?.() >= rewardEnd) continue;
    const email = user.email || user.emailLower || (await getAuth().getUser(doc.id)).email;
    if (!email) continue;
    await queueEmail(`reward-reminder-${doc.id}-${rewardEnd}`, {
      type: 'reward_reminder', to: email,
      expiresAt: user.referralPlusUntil.toDate().toISOString(),
    });
  }
});

exports.onPlaySubscriptionUpdate = onMessagePublished({
  topic: 'warrantycave-play-rtdn', region: 'us-central1', retry: true,
}, async (event) => {
  const raw = event.data.message.data;
  if (!raw) return;
  const notification = JSON.parse(Buffer.from(raw, 'base64').toString('utf8'));
  const change = notification.subscriptionNotification;
  if (notification.packageName !== ANDROID_PACKAGE || !change?.purchaseToken) return;
  const tokenHash = codeHash(change.purchaseToken);
  const tokenSnap = await db.collection('playPurchaseTokens').doc(tokenHash).get();
  if (!tokenSnap.exists) return;
  const userRef = db.collection('users').doc(tokenSnap.data().uid);
  const current = await userRef.get();
  if (!current.exists || current.data().playPurchaseTokenHash !== tokenHash) return;
  const purchase = await playRequest(`/purchases/subscriptionsv2/tokens/${encodeURIComponent(change.purchaseToken)}`);
  const line = (purchase.lineItems || []).find((item) => PLAY_PRODUCTS.has(item.productId));
  if (!line?.expiryTime) return;
  const expiresAt = new Date(line.expiryTime);
  const autoRenewing = line.autoRenewingPlan?.autoRenewEnabled === true &&
    purchase.subscriptionState === 'SUBSCRIPTION_STATE_ACTIVE';
  const wasAutoRenewing = current.data().playAutoRenewing === true;
  await userRef.update({
    plan: PLAY_PRODUCTS.get(line.productId), planExpiresAt: Timestamp.fromDate(expiresAt),
    playAutoRenewing: autoRenewing, playSubscriptionState: purchase.subscriptionState || null,
    updatedAt: FieldValue.serverTimestamp(),
  });
  if (change.notificationType === 3 && wasAutoRenewing && !autoRenewing) {
    const email = current.data().email || current.data().emailLower ||
      (await getAuth().getUser(tokenSnap.data().uid)).email;
    if (email) await queueEmail(`cancelled-${tokenHash}-${expiresAt.getTime()}`, {
      type: 'cancelled', to: email, expiresAt: expiresAt.toISOString(),
    });
  }
  if (change.notificationType === 2 &&
      current.data().planExpiresAt?.toMillis?.() !== expiresAt.getTime()) {
    const email = current.data().email || current.data().emailLower ||
      (await getAuth().getUser(tokenSnap.data().uid)).email;
    if (email) await queueEmail(`renewal-${tokenHash}-${expiresAt.getTime()}`, {
      type: 'subscribed', to: email, plan: PLAY_PRODUCTS.get(line.productId),
      expiresAt: expiresAt.toISOString(), autoRenewing,
    });
  }
});

async function applyReferralReward(rewardId) {
  const rewardRef = db.collection('referralRewards').doc(rewardId);
  const rewardSnap = await rewardRef.get();
  if (!rewardSnap.exists || rewardSnap.data().status === 'completed') return;
  const reward = rewardSnap.data();
  const lockRef = db.collection('referralLocks').doc(reward.inviterUid);
  await db.runTransaction(async (transaction) => {
    const lock = await transaction.get(lockRef);
    if (lock.exists && lock.data().until?.toMillis?.() > Date.now()) {
      throw new Error('Referral renewal is already being extended; retry this reward.');
    }
    transaction.set(lockRef, {
      owner: rewardId, until: Timestamp.fromMillis(Date.now() + 5 * 60 * 1000),
    });
  });
  try {
    await applyLockedReferralReward(rewardId, rewardRef, reward);
  } finally {
    await db.runTransaction(async (transaction) => {
      const lock = await transaction.get(lockRef);
      if (lock.exists && lock.data().owner === rewardId) transaction.delete(lockRef);
    });
  }
}

async function applyLockedReferralReward(rewardId, rewardRef, reward) {
  const inviterRef = db.collection('users').doc(reward.inviterUid);
  const inviterSnap = await inviterRef.get();
  if (!inviterSnap.exists) return;
  const inviter = inviterSnap.data();
  const to = inviter.email || inviter.emailLower || (await getAuth().getUser(reward.inviterUid)).email;
  if (!to) return;

  if (PLAY_PRODUCTS.has(inviter.playProductId) &&
      inviter.planExpiresAt?.toMillis?.() > Date.now() &&
      !Object.hasOwn(inviter, 'playAutoRenewing')) {
    await rewardRef.update({status: 'waiting_for_purchase_token'});
    return;
  }

  let nextBillingAt = null;
  if (inviter.playAutoRenewing === true && inviter.playPurchaseTokenHash) {
    const tokenSnap = await db.collection('playPurchaseTokens')
      .doc(inviter.playPurchaseTokenHash).get();
    const token = tokenSnap.data()?.purchaseToken;
    if (!token) {
      await rewardRef.update({status: 'waiting_for_purchase_token'});
      return;
    }
    const path = `/purchases/subscriptionsv2/tokens/${encodeURIComponent(token)}`;
    const purchase = await playRequest(path);
    const details = purchaseDetails(purchase);
    if (details?.autoRenewing) {
      // Persist the starting state before the request. After a function retry, compare
      // against that state to avoid charging the customer for a duplicate extension.
      let baseBillingAt = reward.baseBillingAt;
      if (!baseBillingAt) {
        baseBillingAt = details.expiry.toISOString();
        await rewardRef.update({baseBillingAt});
      }
      if (deferralState(baseBillingAt, details.expiry.toISOString()) === 'confirmed') {
        nextBillingAt = details.expiry.toISOString();
      } else {
        if (deferralState(baseBillingAt, details.expiry.toISOString()) !== 'unchanged') {
          // A normal yearly renewal or another change must never be mistaken
          // for this referral's 30-day deferral.
          await rewardRef.update({status: 'needs_manual_review',
            lastObservedBillingAt: details.expiry.toISOString()});
          await queueEmail(`referral-${rewardId}`, {
            type: 'referral', to, rewardUntil: reward.rewardUntil,
            billingPending: true,
          });
          return;
        }
        const deferred = await playRequest(`${path}:defer`, {
          method: 'POST',
          body: {deferralContext: {etag: purchase.etag, deferDuration: '2592000s'}},
        });
        const deferredExpiry = deferred?.itemExpiryTimeDetails?.find((item) =>
          item.productId === details.line.productId)?.expiryTime ||
          (await playRequest(path)).lineItems?.find((item) => item.productId === details.line.productId)?.expiryTime;
        if (!deferredExpiry || deferralState(baseBillingAt, deferredExpiry) !== 'confirmed') {
          throw new Error('Google Play did not confirm a 30-day renewal deferral.');
        }
        nextBillingAt = new Date(deferredExpiry).toISOString();
      }
      // Read back from Play: the user should see the same expiry as the store.
      const fresh = await playRequest(path);
      const freshLine = (fresh.lineItems || []).find((item) => item.productId === details.line.productId);
      if (!freshLine?.expiryTime || deferralState(baseBillingAt, freshLine.expiryTime) !== 'confirmed') {
        throw new Error('Google Play renewal deferral was not visible on read back.');
      }
      nextBillingAt = freshLine.expiryTime;
      await db.runTransaction(async (transaction) => {
        const latest = await transaction.get(inviterRef);
        if (latest.exists && latest.data().playPurchaseTokenHash === inviter.playPurchaseTokenHash) {
          transaction.update(inviterRef, {
            planExpiresAt: Timestamp.fromDate(new Date(nextBillingAt)),
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
      });
    }
  }

  // A nonrenewing plan has no Google Play charge to move; the Plus reward remains.
  await queueEmail(`referral-${rewardId}`, {
    type: 'referral', to, rewardUntil: reward.rewardUntil, nextBillingAt,
  });
  await rewardRef.update({status: 'completed', nextBillingAt,
    processedAt: FieldValue.serverTimestamp()});
}

exports.onReferralReward = onDocumentCreated({
  document: 'referralRewards/{rewardId}', region: 'us-central1', retry: true,
}, async (event) => applyReferralReward(event.params.rewardId));
