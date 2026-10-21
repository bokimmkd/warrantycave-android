'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {registerAppleFunctions} = require('../apple_functions');

const TOKEN = '4b293923-b932-450a-bc62-96599c5c3481';
function fixture({owner = 'alice', refunded = false, invalidSignature = false} = {}) {
  const records = new Map([
    ['users/alice', {}],
    ['appleBillingAccounts/alice', {token: TOKEN}],
    ['appleSubscriptions/Production-1001', {uid: owner, verificationStartedAt: 1, plan: 'plus'}],
  ]);
  const calls = [];
  const reference = (path) => ({path, get: async () => snapshot(path)});
  const snapshot = (path) => ({exists: records.has(path), data: () => records.get(path)});
  const db = {
    collection: (name) => ({doc: (id) => reference(`${name}/${id}`)}),
    runTransaction: async (callback) => {
      const writes = [];
      const result = await callback({
        get: async (ref) => snapshot(ref.path),
        set: (ref, data) => writes.push([ref.path, data]),
      });
      for (const [path, data] of writes) records.set(path, data);
      return result;
    },
  };
  const transaction = {originalTransactionId: '1001', transactionId: '1002',
    productId: 'warrantycave_basic_yearly', appAccountToken: TOKEN};
  const handlers = registerAppleFunctions({
    db, requireUser: (request) => request.auth,
    entitlements: async () => ({plan: records.get('appleSubscriptions/Production-1001').plan}),
    storeFactory: () => ({
      verifyTransaction: async (signed) => {
        if (invalidSignature) throw new Error('Untrusted certificate');
        calls.push(['verify', signed]);
        return {payload: transaction, environment: 'Production'};
      },
      current: async (originalId, environment) => {
        calls.push(['current', originalId, environment]);
        return {transaction, environment, state: refunded ? null : {
          plan: 'basic', expiresAt: Date.now() + 100000,
          autoRenewing: false, nextBillingAt: null,
        }};
      },
    }),
  });
  const request = {auth: {uid: 'alice', token: {email_verified: true}}, data: {
    signedTransaction: 'previously.signed.receipt', productId: transaction.productId,
  }};
  return {records, calls, handlers, request};
}

test('Apple restore cannot take ownership of another Firebase account purchase', async () => {
  const {records, handlers, request} = fixture({owner: 'bob'});
  await assert.rejects(handlers.confirmApplePurchase.run(request), {code: 'permission-denied'});
  assert.equal(records.get('appleSubscriptions/Production-1001').uid, 'bob');
  assert.equal(records.get('appleSubscriptions/Production-1001').plan, 'plus');
});

test('replaying an old signed purchase fetches current Apple state and removes refunded access', async () => {
  const {handlers, request, records, calls} = fixture({refunded: true});
  assert.deepEqual(await handlers.confirmApplePurchase.run(request), {plan: 'free'});
  assert.deepEqual(calls, [['verify', 'previously.signed.receipt'], ['current', '1001', 'Production']]);
  assert.equal(records.get('appleSubscriptions/Production-1001').expiresAt, null);
});

test('invalid signatures, product substitutions and account token mismatches cannot grant a plan', async () => {
  let context = fixture({invalidSignature: true});
  await assert.rejects(context.handlers.confirmApplePurchase.run(context.request), {code: 'invalid-argument'});
  assert.equal(context.records.get('appleSubscriptions/Production-1001').plan, 'plus');
  context = fixture();
  context.request.data.productId = 'warrantycave_plus_yearly';
  await assert.rejects(context.handlers.confirmApplePurchase.run(context.request), {code: 'invalid-argument'});
  assert.equal(context.calls.length, 1);
  context = fixture();
  context.records.set('appleBillingAccounts/alice', {token: 'another-account-token'});
  await assert.rejects(context.handlers.confirmApplePurchase.run(context.request), {code: 'permission-denied'});
  assert.equal(context.records.get('appleSubscriptions/Production-1001').plan, 'plus');
});
