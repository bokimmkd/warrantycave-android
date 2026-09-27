# WarrantyCave subscription emails and billing dates

The backend records Google Play subscription expiry, the referral Plus end date,
and the next renewal separately. The Android Settings screen reads these values
from `getEntitlements`. Seven-day reminders read Google Play again immediately
before queuing an email; the daily job runs at 09:00 UTC.

## Before deploying

1. Verify `warrantycave.com` in Resend, including the domain's SPF/DKIM DNS
   records and the sender address `updates@warrantycave.com`.
2. In Firebase project `warrantycave`, set the Functions secret `RESEND_API_KEY`
   to a Resend API key. Never put it in Git or the Android app.
3. Deploy the new Cloud Functions and Firestore rules. Functions requiring the
   secret cannot deliver messages until it is configured.
4. Google Play Console > Monetize with Play > Monetization setup > Real-time
   developer notifications: publish subscription events to Pub/Sub topic
   `projects/warrantycave/topics/warrantycave-play-rtdn`. Grant the Google Play
   service account `google-play-developer-notifications@system.gserviceaccount.com`
   the Pub/Sub Publisher role on this topic. Confirm the Google Play Developer
   API service account can read purchases and manage subscriptions for this app.
5. Publish the Android build containing the separate subscription dates to a
   closed testing track and test with a real Google Play test subscription.

## Verify before production

- Create a new email/password account and a Google account. Check the branded
  welcome message arrives once for each account.
- Make a first Basic and Plus purchase. Check the confirmation includes the
  actual expiry and renewal date shown in Play, and Settings shows both dates.
- Make a referred first purchase. Check the inviter receives 30 days of Plus;
  if the inviter has a renewing Play subscription, check Play itself reports a
  30-day later renewal before expecting the referral email to claim that date.
- Cancel a test subscription in Play and confirm its RTDN updates the app and
  sends one cancellation email while access continues until its expiry.
- Use a test record with an expiry approximately seven days away and run the
  scheduled job. Confirm its reminder uses the latest date in Play, is sent
  once, and does not treat a referral reward as a Play charge.
- Delete a test account and confirm one deletion notice. Check any active Play
  subscription remains independently manageable in Google Play.

Existing purchases made before this version need one Restore Purchases in the
app to make their purchase token available for server-side renewal deferrals and
reminders. Referral rewards waiting for a pre-existing token are processed upon
that restore. Existing accounts do not receive retroactive welcome messages.

Mail delivery is backed by the `transactionalEmail` outbox with stable document
IDs and an idempotency key at the provider. The outbox and purchase token
collections are server-only under Firestore rules. Monitor failed Cloud Function
invocations and Resend delivery events during rollout.
