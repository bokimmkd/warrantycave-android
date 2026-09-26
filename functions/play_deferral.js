'use strict';

const DAY_MS = 24 * 60 * 60 * 1000;

function deferralState(baseBillingAt, observedBillingAt) {
  const base = Date.parse(baseBillingAt);
  const observed = Date.parse(observedBillingAt);
  if (!Number.isFinite(base) || !Number.isFinite(observed)) throw new Error('Invalid Play billing date.');
  if (Math.abs(observed - (base + 30 * DAY_MS)) <= 1000) return 'confirmed';
  if (observed === base) return 'unchanged';
  return 'unexpected_change';
}

module.exports = {deferralState};
