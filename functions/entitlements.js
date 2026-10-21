'use strict';

// All inputs are server-owned, verified records. Apple and Play subscriptions
// coexist, so a delayed update from one store cannot overwrite the other.
function resolveEntitlements(user, apple, isOwner, now = Date.now()) {
  const candidates = [];
  const add = (plan, expiry, nextBillingAt = null) => {
    if (['basic', 'plus'].includes(plan) && expiry > now) candidates.push({plan, expiry, nextBillingAt});
  };
  const playExpiry = user.planExpiresAt?.toMillis?.() || 0;
  add(user.plan, playExpiry, user.playAutoRenewing === true ? playExpiry : null);
  for (const row of apple) add(row.plan, row.expiresAt?.toMillis?.() || 0,
    row.nextBillingAt?.toMillis?.() || null);
  const paid = [...candidates].sort((a, b) =>
    (b.plan === 'plus') - (a.plan === 'plus') || b.expiry - a.expiry)[0];
  const referral = user.referralPlusUntil?.toMillis?.() || 0;
  add('plus', referral);
  add('basic', user.promotionalBasicUntil?.toMillis?.() || 0);
  candidates.sort((a, b) => (b.plan === 'plus') - (a.plan === 'plus') || b.expiry - a.expiry);
  const effective = candidates[0];
  const iso = (value) => value ? new Date(value).toISOString() : null;
  return {
    plan: isOwner ? 'plus' : effective?.plan || 'free',
    expiresAt: isOwner ? null : iso(effective?.expiry),
    paidExpiresAt: iso(paid?.expiry),
    nextBillingAt: iso(paid?.nextBillingAt),
    referralPlusUntil: referral > now ? iso(referral) : null,
    smartScanCredits: isOwner ? 999 : Number(user.smartScanCredits || 0),
  };
}
module.exports = {resolveEntitlements};
