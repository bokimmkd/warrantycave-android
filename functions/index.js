'use strict';

const crypto = require('crypto');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const vision = require('@google-cloud/vision');
const {parseReceipt} = require('./receipt_parser');

initializeApp();
const db = getFirestore();
const visionClient = new vision.ImageAnnotatorClient();
const OWNER_EMAIL = 'bokimk.ap@gmail.com';
const ONE_YEAR_MS = 365 * 24 * 60 * 60 * 1000;

function requireUser(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in is required.');
  return request.auth;
}

function normalizeCode(value) {
  return String(value || '').trim().toUpperCase().replace(/[^A-Z0-9]/g, '');
}

function codeHash(code) {
  return crypto.createHash('sha256').update(code).digest('hex');
}

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
  let plan = 'free';
  let expiresAt = null;
  if (isOwner) {
    plan = 'plus';
    expiresAt = '2099-12-31T23:59:59.000Z';
  } else if (paidUntil > now && ['basic', 'plus'].includes(user.plan)) {
    plan = user.plan;
    expiresAt = user.planExpiresAt.toDate().toISOString();
  } else if (promoUntil > now) {
    plan = 'basic';
    expiresAt = user.promotionalBasicUntil.toDate().toISOString();
  }
  return {plan, expiresAt, smartScanCredits: isOwner ? 999 : Number(user.smartScanCredits || 0)};
});
