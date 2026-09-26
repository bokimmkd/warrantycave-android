'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {renderEmail} = require('../transactional_email');

test('welcome explains actual Free, Basic and Plus limits without claiming a purchase', () => {
  const message = renderEmail('welcome', {name: 'Alex <script>'});
  assert.match(message.text, /10 warranties/);
  assert.match(message.text, /15 warranties/);
  assert.match(message.text, /50 warranties/);
  assert.doesNotMatch(message.html, /<script>/);
});

test('paid email distinguishes entitlement date from renewal and formats UTC', () => {
  const message = renderEmail('subscribed', {
    plan: 'basic', expiresAt: '2026-10-26T09:38:00.000Z', autoRenewing: true,
  });
  assert.match(message.text, /26 October 2026/);
  assert.match(message.text, /next Google Play billing date/);
});

test('referral email promises a new charge date only after Play actually deferred it', () => {
  const noSubscription = renderEmail('referral', {rewardUntil: '2026-10-26T09:38:00.000Z'});
  assert.match(noSubscription.text, /no next charge to move/);
  const deferred = renderEmail('referral', {
    rewardUntil: '2026-10-26T09:38:00.000Z',
    nextBillingAt: '2027-10-26T09:38:00.000Z',
  });
  assert.match(deferred.text, /moved to 26 October 2027/);
});

test('deletion email does not claim Google Play charges have been cancelled', () => {
  const message = renderEmail('deleted');
  assert.match(message.text, /does not cancel a Google Play subscription/);
});

test('seven-day reminder reflects renewal or cancellation accurately', () => {
  const renew = renderEmail('reminder', {
    expiresAt: '2026-10-26T09:38:00.000Z', autoRenewing: true,
  });
  const ended = renderEmail('reminder', {
    expiresAt: '2026-10-26T09:38:00.000Z', autoRenewing: false,
  });
  assert.match(renew.text, /next Google Play billing date/);
  assert.doesNotMatch(ended.text, /next Google Play billing date/);
  const reward = renderEmail('reward_reminder', {
    expiresAt: '2026-10-26T09:38:00.000Z',
  });
  assert.match(reward.text, /referral Plus reward runs through 26 October 2026/);
  assert.doesNotMatch(reward.text, /next Google Play billing date/);
});
