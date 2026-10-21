'use strict';

const fs = require('node:fs');
const path = require('node:path');
const {
  AppStoreServerAPIClient, SignedDataVerifier, Environment,
} = require('@apple/app-store-server-library');

const PRODUCTS = new Map([
  ['warrantycave_basic_yearly', 'basic'],
  ['warrantycave_plus_yearly', 'plus'],
]);

// Input to this function must already have passed Apple's signature verifier.
// Status comes from a fresh App Store Server API response, never the client.
function subscriptionState(transaction, renewal, status, now = Date.now()) {
  if (!PRODUCTS.has(transaction.productId) ||
      transaction.type !== 'Auto-Renewable Subscription' ||
      !transaction.originalTransactionId || !transaction.transactionId ||
      !transaction.appAccountToken || transaction.revocationDate ||
      transaction.isUpgraded === true) return null;
  const expiry = status === 4
    ? Number(renewal?.gracePeriodExpiresDate || 0)
    : Number(transaction.expiresDate || 0);
  if (![1, 4].includes(status) || !Number.isFinite(expiry) || expiry <= now) return null;
  return {
    plan: PRODUCTS.get(transaction.productId),
    productId: transaction.productId,
    expiresAt: expiry,
    autoRenewing: renewal?.autoRenewStatus === 1,
  };
}

function createAppleStore(privateKey) {
  const bundleId = process.env.APPLE_BUNDLE_ID;
  const appId = Number(process.env.APPLE_APP_ID);
  const keyId = process.env.APPLE_IAP_KEY_ID;
  const issuerId = process.env.APPLE_IAP_ISSUER_ID;
  if (!bundleId || !Number.isSafeInteger(appId) || appId <= 0 ||
      !privateKey || !keyId || !issuerId) {
    throw new Error('Apple subscription verification is not configured.');
  }
  const roots = ['AppleRootCA-G3.cer', 'AppleRootCA-G2.cer'].map(
    (name) => fs.readFileSync(path.join(__dirname, 'apple-roots', name)),
  );
  const environments = [Environment.PRODUCTION];
  if (process.env.APPLE_ALLOW_SANDBOX === 'true') environments.push(Environment.SANDBOX);
  const stores = environments.map((environment) => ({
    environment,
    verifier: new SignedDataVerifier(roots, true, environment, bundleId, appId),
    client: new AppStoreServerAPIClient(privateKey, keyId, issuerId, bundleId, environment),
  }));

  async function verify(signed, method) {
    if (typeof signed !== 'string' || signed.length < 100 || signed.length > 100000) {
      throw new Error('Invalid Apple signed data.');
    }
    for (const store of stores) {
      try {
        const payload = await store.verifier[method](signed);
        return {...store, payload};
      } catch (_) { /* An environment is accepted only after full verification. */ }
    }
    throw new Error('Apple signature verification failed.');
  }

  async function current(originalTransactionId, environment) {
    if (!/^\d{1,32}$/.test(originalTransactionId || '')) throw new Error('Invalid transaction.');
    const store = stores.find((entry) => entry.environment === environment);
    if (!store) throw new Error('Apple environment is not enabled.');
    const response = await store.client.getAllSubscriptionStatuses(originalTransactionId);
    if (response.bundleId !== bundleId || response.environment !== environment) {
      throw new Error('Apple app mismatch.');
    }
    const candidates = [];
    for (const group of response.data || []) {
      for (const entry of group.lastTransactions || []) {
        const transaction = await store.verifier.verifyAndDecodeTransaction(entry.signedTransactionInfo);
        if (transaction.originalTransactionId !== originalTransactionId) continue;
        const renewal = entry.signedRenewalInfo
          ? await store.verifier.verifyAndDecodeRenewalInfo(entry.signedRenewalInfo) : null;
        if (renewal && renewal.originalTransactionId !== originalTransactionId) {
          throw new Error('Apple renewal mismatch.');
        }
        candidates.push({transaction, renewal, status: entry.status});
      }
    }
    // Keep the newest state even when expired/revoked so restores can clear it.
    candidates.sort((a, b) => Number(b.transaction.purchaseDate || 0) - Number(a.transaction.purchaseDate || 0));
    if (!candidates.length) throw new Error('Apple subscription was not found.');
    const latest = candidates[0];
    if (!PRODUCTS.has(latest.transaction.productId)) throw new Error('Unknown Apple product.');
    return {...latest, environment, state: subscriptionState(
      latest.transaction, latest.renewal, latest.status,
    )};
  }

  return {
    verifyTransaction: (signed) => verify(signed, 'verifyAndDecodeTransaction'),
    verifyNotification: (signed) => verify(signed, 'verifyAndDecodeNotification'),
    current,
  };
}

module.exports = {PRODUCTS, subscriptionState, createAppleStore};
