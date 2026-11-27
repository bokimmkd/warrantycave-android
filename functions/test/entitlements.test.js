'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {resolveEntitlements} = require('../entitlements');
const NOW = 100000;
const at = (ms) => ({toMillis: () => ms});
test('higher active tier wins across Apple, Play, promotions and referral', () => {
  const result = resolveEntitlements({plan: 'basic', planExpiresAt: at(NOW + 9000)},
    [{plan: 'plus', expiresAt: at(NOW + 1000), autoRenewing: false}], false, NOW);
  assert.equal(result.plan, 'plus');
  assert.equal(result.nextBillingAt, null);
  assert.equal(result.expiresAt, new Date(NOW + 1000).toISOString());
});
test('Apple refund or expiry cannot revoke an independent Play purchase', () => {
  for (const row of [{plan: 'free', expiresAt: null}, {plan: 'plus', expiresAt: at(NOW - 1)}]) {
    const result = resolveEntitlements({plan: 'basic', planExpiresAt: at(NOW + 1000), playAutoRenewing: true},
      [row], false, NOW);
    assert.equal(result.plan, 'basic');
    assert.equal(result.nextBillingAt, new Date(NOW + 1000).toISOString());
  }
});
test('referral access expires independently of paid subscription', () => {
  assert.equal(resolveEntitlements({referralPlusUntil: at(NOW + 1)}, [], false, NOW).plan, 'plus');
  assert.equal(resolveEntitlements({referralPlusUntil: at(NOW)}, [], false, NOW).plan, 'free');
  assert.equal(resolveEntitlements({}, [], true, NOW).expiresAt, null);
});
