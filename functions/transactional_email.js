'use strict';

const STORE_URL = 'https://play.google.com/store/apps/details?id=com.warrantycave.app';
const MANAGE_URL = 'https://play.google.com/store/account/subscriptions?package=com.warrantycave.app';

function escapeHtml(value) {
  return String(value || '').replace(/[&<>"']/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[character]);
}

function readableDate(value) {
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) throw new Error('A valid date is required.');
  return new Intl.DateTimeFormat('en-GB', {
    day: 'numeric', month: 'long', year: 'numeric',
    hour: '2-digit', minute: '2-digit', timeZone: 'UTC', timeZoneName: 'short',
  }).format(date);
}

function renderEmail(kind, details = {}) {
  const name = String(details.name || '').trim().split(/\s+/)[0].slice(0, 80);
  const greeting = name ? `Hi ${name},` : 'Hello,';
  let subject;
  let heading;
  let paragraphs;
  let action = {label: 'Open WarrantyCave', url: STORE_URL};

  switch (kind) {
  case 'welcome':
    subject = 'Welcome to WarrantyCave';
    heading = 'Your warranties have a new home';
    paragraphs = [
      greeting,
      'Your account is ready. With Free, you can save up to 10 warranties on this device, add receipts and warranty photos, and use local reminders. Free includes ads.',
      'Basic adds cloud backup and sync, barcode scanning, and room for 15 warranties. Plus includes those features and room for 50 warranties. Google Play shows the current price in your country before you pay.',
      'Start by adding a product and its receipt. You can choose a plan in the app whenever you are ready.',
    ];
    break;
  case 'subscribed':
    subject = `Your WarrantyCave ${details.plan === 'plus' ? 'Plus' : 'Basic'} subscription`;
    heading = 'Your plan is active';
    paragraphs = [
      greeting,
      `Google Play confirmed your ${details.plan === 'plus' ? 'Plus' : 'Basic'} subscription. Your current paid period runs through ${readableDate(details.expiresAt)}.`,
      details.autoRenewing
        ? `Your next Google Play billing date is ${readableDate(details.expiresAt)}, unless you cancel or the date changes in Google Play.`
        : 'This subscription is not set to renew automatically.',
      'You can see your plan and access date in WarrantyCave. Google Play provides the payment receipt and lets you manage or cancel your subscription.',
    ];
    action = {label: 'Manage in Google Play', url: MANAGE_URL};
    break;
  case 'referral':
    subject = 'You earned 30 days of WarrantyCave Plus';
    heading = 'Your referral reward is active';
    paragraphs = [
      greeting,
      'Someone you invited completed their first paid WarrantyCave purchase. You earned 30 additional days of Plus.',
      `This referral reward is recorded until ${readableDate(details.rewardUntil)}.`,
      details.nextBillingAt
        ? `Your next Google Play charge has also been moved to ${readableDate(details.nextBillingAt)}. Check Google Play for the current billing date.`
        : details.billingPending
          ? 'Your Plus reward is active. We are checking the Google Play billing date separately and will only confirm a new charge date after Google Play verifies it.'
        : 'If you do not have an active renewing Google Play subscription, there is no next charge to move. Your Plus reward is still active.',
    ];
    break;
  case 'cancelled':
    subject = 'Your WarrantyCave subscription was cancelled';
    heading = 'Your subscription was cancelled';
    paragraphs = [
      greeting,
      'Google Play confirmed that your subscription will not renew. There are no further scheduled renewal charges for this subscription.',
      `Your paid access remains available until ${readableDate(details.expiresAt)}. If you have a separate referral reward, that reward keeps its own end date.`,
      'You can check your subscription details or resubscribe in Google Play.',
    ];
    action = {label: 'View in Google Play', url: MANAGE_URL};
    break;
  case 'reminder':
    subject = details.autoRenewing
      ? 'Your WarrantyCave subscription renews in about 7 days'
      : 'Your WarrantyCave paid period ends in about 7 days';
    heading = details.autoRenewing ? 'A reminder before your next renewal' : 'Your paid period is ending soon';
    paragraphs = [
      greeting,
      details.autoRenewing
        ? `Your next Google Play billing date is ${readableDate(details.expiresAt)}. Google Play shows the current charge and payment method.`
        : `Your current paid period runs through ${readableDate(details.expiresAt)}. This subscription is not set to renew. A separate referral reward may have its own end date.`,
      'You can check or manage your subscription in Google Play.',
    ];
    action = {label: 'Manage in Google Play', url: MANAGE_URL};
    break;
  case 'reward_reminder':
    subject = 'Your WarrantyCave referral Plus ends in about 7 days';
    heading = 'Your referral Plus is ending soon';
    paragraphs = [
      greeting,
      `Your referral Plus reward runs through ${readableDate(details.expiresAt)}.`,
      'Any separately paid subscription keeps its own access and billing date. You can see your current plan and dates in WarrantyCave.',
    ];
    break;
  case 'deleted':
    subject = 'Your WarrantyCave account was deleted';
    heading = 'Your account has been deleted';
    paragraphs = [
      greeting,
      'Your WarrantyCave sign-in account was deleted. Your stored app data is no longer available in this account.',
      'Deleting an app account does not cancel a Google Play subscription. If you had an active subscription, check and cancel it in Google Play to avoid future charges.',
      'If you did not request this, please contact WarrantyCave support.',
    ];
    action = {label: 'Check Google Play subscriptions', url: MANAGE_URL};
    break;
  default:
    throw new Error(`Unsupported email type: ${kind}`);
  }

  const body = paragraphs.map((line) => `<p style="margin:0 0 18px;color:#354c61;font-size:16px;line-height:1.55">${escapeHtml(line)}</p>`).join('');
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;background:#f4f7fd;font-family:Arial,sans-serif"><table role="presentation" cellpadding="0" cellspacing="0" width="100%"><tr><td align="center" style="padding:28px 16px"><table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="max-width:580px;background:#fff;border-radius:20px;overflow:hidden"><tr><td style="padding:28px 32px;background:#133f72;color:#fff;font-size:25px;font-weight:800">Warranty<span style="color:#32cbb4">Cave</span></td></tr><tr><td style="padding:32px"><h1 style="margin:0 0 26px;color:#102f53;font-size:26px">${escapeHtml(heading)}</h1>${body}<a href="${action.url}" style="display:inline-block;margin:6px 0 18px;padding:14px 20px;background:#16578b;color:#fff;text-decoration:none;border-radius:12px;font-weight:700">${escapeHtml(action.label)}</a><p style="color:#718495;font-size:13px;line-height:1.5">WarrantyCave · <a href="https://warrantycave.com" style="color:#16578b">warrantycave.com</a></p></td></tr></table></td></tr></table></body></html>`;
  const text = `${heading}\n\n${paragraphs.join('\n\n')}\n\n${action.label}: ${action.url}\n\nWarrantyCave · warrantycave.com`;
  return {subject, html, text};
}

module.exports = {renderEmail, readableDate};
