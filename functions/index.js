'use strict';

const crypto = require('crypto');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {GoogleAuth} = require('google-auth-library');
const vision = require('@google-cloud/vision');
const {parseReceipt} = require('./receipt_parser');
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
    expiresAt = '2099-12-31T23:59:59.000Z';
  } else if (referralPlusUntil > now) {
    plan = 'plus';
    expiresAt = user.referralPlusUntil.toDate().toISOString();
  } else if (paidUntil > now && ['basic', 'plus'].includes(user.plan)) {
    plan = user.plan;
    expiresAt = user.planExpiresAt.toDate().toISOString();
  } else if (promoUntil > now) {
    plan = 'basic';
    expiresAt = user.promotionalBasicUntil.toDate().toISOString();
  }
  return {plan, expiresAt, smartScanCredits: isOwner ? 999 : Number(user.smartScanCredits || 0)};
});

exports.confirmPlayPurchase = onCall({region: 'us-central1'}, async (request) => {
  const auth = requireUser(request);
  const suppliedProductId = String(request.data?.productId || '');
  const purchaseToken = String(request.data?.purchaseToken || '');
  if (!PLAY_PRODUCTS.has(suppliedProductId) || purchaseToken.length < 16 || purchaseToken.length > 4096) {
    throw new HttpsError('invalid-argument', 'Invalid Google Play purchase.');
  }

  const client = await androidPublisherAuth.getClient();
  const headers = await client.getRequestHeaders();
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${ANDROID_PACKAGE}` +
    `/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
  const response = await fetch(url, {headers});
  if (response.status === 401 || response.status === 403) {
    throw new HttpsError(
      'failed-precondition',
      'Google Play purchase verification is not connected to the Play Console service account.',
    );
  }
  if (response.status === 404) {
    throw new HttpsError('not-found', 'Google Play purchase was not found.');
  }
  if (!response.ok) {
    throw new HttpsError('unavailable', `Google Play verification failed (${response.status}).`);
  }

  const purchase = await response.json();
  const validLines = (purchase.lineItems || []).filter((line) => {
    const expiry = Date.parse(line.expiryTime || '');
    return PLAY_PRODUCTS.has(line.productId) && Number.isFinite(expiry) && expiry > Date.now();
  });
  if (validLines.length === 0) {
    throw new HttpsError('failed-precondition', 'This subscription is not active.');
  }
  validLines.sort((a, b) => Date.parse(b.expiryTime) - Date.parse(a.expiryTime));
  const line = validLines[0];
  if (line.productId !== suppliedProductId) {
    throw new HttpsError('permission-denied', 'Purchase product mismatch.');
  }
  const plan = PLAY_PRODUCTS.get(line.productId);
  const expiresAt = new Date(line.expiryTime);
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
      entitlementSource: 'google_play',
      ...(inviterRef ? {
        referralStatus: 'rewarded',
        referralRewardedAt: FieldValue.serverTimestamp(),
      } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

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
    }
  });

  return {plan, expiresAt: expiresAt.toISOString()};
});
