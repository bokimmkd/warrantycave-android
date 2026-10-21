'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {subscriptionState} = require('../apple_billing');
const NOW = 100000;
const purchase = {
  productId: 'warrantycave_basic_yearly', type: 'Auto-Renewable Subscription',
  originalTransactionId: '1001', transactionId: '1002', appAccountToken: 'owner-token',
  expiresDate: NOW + 1000,
};

test('Apple: active and canceled auto-renew subscriptions retain access until expiry', () => {
  assert.equal(subscriptionState(purchase, {autoRenewStatus: 1}, 1, NOW).plan, 'basic');
  assert.equal(subscriptionState(purchase, {autoRenewStatus: 0}, 1, NOW).autoRenewing, false);
  assert.equal(subscriptionState({...purchase, expiresDate: NOW}, {}, 1, NOW), null);
});
test('Apple: billing retry, refund, expired, unknown products and upgrades cannot grant access', () => {
  for (const status of [2, 3, 5, 0, undefined]) {
    assert.equal(subscriptionState(purchase, {}, status, NOW), null);
  }
  for (const changes of [
    {revocationDate: NOW - 1}, {isUpgraded: true}, {appAccountToken: null},
    {productId: 'fake_plus'}, {type: 'Consumable'}, {expiresDate: NaN},
  ]) assert.equal(subscriptionState({...purchase, ...changes}, {}, 1, NOW), null);
});
test('Apple: grace access uses only the signed grace expiry', () => {
  assert.equal(subscriptionState(purchase, {}, 4, NOW), null);
  const grace = subscriptionState({...purchase, expiresDate: NOW - 1},
    {autoRenewStatus: 1, gracePeriodExpiresDate: NOW + 500}, 4, NOW);
  assert.equal(grace.expiresAt, NOW + 500);
});
