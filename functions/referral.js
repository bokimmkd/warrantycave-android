'use strict';

const REFERRAL_REWARD_MS = 30 * 24 * 60 * 60 * 1000;

function normalizeCode(value) {
  return String(value || '').trim().toUpperCase().replace(/[^A-Z0-9]/g, '');
}

function referralCodeForUid(uid) {
  const clean = normalizeCode(uid);
  return `WC${clean.slice(0, 10).padEnd(10, '0')}`;
}

function referralRewardExpiryMs(now, currentExpiry = 0) {
  return Math.max(now, currentExpiry) + REFERRAL_REWARD_MS;
}

module.exports = {
  REFERRAL_REWARD_MS,
  normalizeCode,
  referralCodeForUid,
  referralRewardExpiryMs,
};
