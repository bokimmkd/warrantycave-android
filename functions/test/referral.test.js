'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  REFERRAL_REWARD_MS,
  normalizeCode,
  referralCodeForUid,
  referralRewardExpiryMs,
} = require('../referral');

test('normalizes referral codes exactly like the app', () => {
  assert.equal(normalizeCode(' wc-ab 12! '), 'WCAB12');
});

test('creates the same deterministic code for a Firebase uid', () => {
  assert.equal(referralCodeForUid('AbC123-xYz987'), 'WCABC123XYZ9');
});

test('starts a 30 day Plus reward immediately when none exists', () => {
  const now = Date.UTC(2026, 8, 25);
  assert.equal(referralRewardExpiryMs(now), now + REFERRAL_REWARD_MS);
});

test('stacks a new reward after an existing referral reward', () => {
  const now = Date.UTC(2026, 8, 25);
  const existing = now + 5 * 24 * 60 * 60 * 1000;
  assert.equal(
    referralRewardExpiryMs(now, existing),
    existing + REFERRAL_REWARD_MS,
  );
});
