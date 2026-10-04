# WarrantyCave Meta installation measurement — candidate 1.0.29 (39)

Base: build 38, `d47870643454b0d9ec0e33dd33c02d2d76a3adf4` on `feature/play-updates-adaptive-banner`.
Android package: `com.warrantycave.app`.
Play listing: https://play.google.com/store/apps/details?id=com.warrantycave.app
Meta app: **1141988704922118**, verified in Meta Developers on 4 October 2026.
SDK: `com.facebook.android:facebook-core:18.3.0` (latest official release checked 4 October).
The Android client token is public SDK configuration; no app secret is included.

## Behaviour and privacy

Settings now places Sign out and Delete account next to each other. Both original confirmation
flows remain, including both deletion confirmations and reauthentication.

Meta measurement is **off until explicit consent**, for Free and paid accounts alike.
Settings > Legal & support > App install measurement explains the events/identifiers,
offers Allow / Not now and links the privacy policy. Turning the switch off revokes
future activation logging and advertising-ID collection. The choice is local to this
installation, outside cloud-backed account settings. AdMob UMP consent is separate.

The Meta ContentProvider is removed in the merged manifest, not merely controlled by
AutoInitEnabled (the SDK provider still calls sdkInitialize even with that flag off).
Automatic event and purchase logging is disabled. No account identity, purchase,
referral, photo, receipt, warranty field or navigation event is passed to Meta.
To avoid the SDK's automatic activity view observation/codeless/advanced matching,
the bridge uses the pinned SDK's public install publisher, `FacebookSdk.publishInstallAsync`,
which persists its install timestamp, and emits `fb_mobile_activate_app` manually.
It deliberately does not register `AppEventsLogger.activateApp` lifecycle callbacks.
This install method is labelled for SDK-internal use by Meta; recheck it when upgrading
SDK versions. A verified real install event remains an advertising launch gate, not a presumed result.
SDK configuration/diagnostic traffic after an allowed initialization can finish asynchronously;
revocation does not undo events already transmitted. Already sent data is handled under Meta's
policy; clearing local app data is not a Meta data-deletion request.

## Required test and release gates

1. CI: analysis, Flutter/backend tests, debug APK, native activation-session tests and merged
   manifest check. Verify normal startup, navigation, sign-in, billing, restore, referrals,
   ads, cloud and stored warranties on real devices; no physical checks are claimed by CI.
2. Register this debug APK's certificate key hash, and **Play App Signing** certificate hash
   for Play installs. The upload certificate is a different identity; do not substitute it.
   Debug hashes can change with CI's keystore, so use the certificate shipped with this APK.
3. Clean install the debug APK; confirm no measurement before Allow. Enable the Settings
   choice and verify a real event for App ID 1141988704922118 in Events Manager. Not now /
   revocation must not generate further activation events. Rotation and short Play dialogs
   must not duplicate activation. Never uninstall a user's only copy of local warranties.
4. Complete Meta Android platform, portfolio and authorized ad-account linking. Confirm the
   intended account rather than reusing another app's ID. Keep automatic advanced matching
   and codeless/purchase logging off; this candidate measures installs/activation only.
5. Publish the Meta privacy disclosure on the website and recheck Google Play Data Safety
   (optional Device or other IDs, app interactions, diagnostics and SDK/network-derived
   information, sharing with Meta for advertising/measurement). Preserve existing Firebase,
   Google Sign-In, Play and AdMob declarations. Current live policy was read and mentions
   Firebase/Play/AdMob, **not Meta**; the website disclosure is still required before release.
6. Build and upload the signed AAB to Alpha 39 as requested on 5 October. Keep it as a
   draft until the website privacy disclosure and Play Data Safety are accurate. Complete
   physical install/activation testing before enabling an install campaign. This provides a real **Play 38 -> 39** update test using the controller already
   installed in 38. A direct debug APK install cannot verify the Play update flow.
7. Verify `application_id` error #1815437 is absent in an unpublished campaign draft.
   App Promotion spend/publish remains blocked until event verification and the user's
   immediate publish confirmation. Production/public install availability is separate.

No campaign has been published, and no advertising spend is authorized by this file.

## Console handover: where each instruction belongs

- Meta Developers > App 1141988704922118 > Settings > Basic > Android: Google Play,
  package `com.warrantycave.app`, class `com.warrantycave.app.MainActivity`; store listing
  https://play.google.com/store/apps/details?id=com.warrantycave.app. Saved and checked.
- Basic: Privacy Policy `https://warrantycave.com/privacy/`, Terms
  `https://warrantycave.com/terms/`, data-deletion instructions
  `https://warrantycave.com/privacy/`. The live disclosure must describe Meta before review.
- Android Key hashes: debug APK at source 275f8c5 uses `t7hxMbEJgtvWWkdwHOKF4pyT2NI=`
  (registered). Every new CI debug APK may use another certificate: calculate from that
  artifact. Play release hash MUST come from the Play App Signing SHA-1/certificate,
  not the upload key. Play > Test and release > App integrity > Play app signing, now
  under Protect with Play > Manage Play app signing. Still pending retrieval.
- Use cases > App ads > App Events settings: automatic event logging OFF (saved).
  Android platform automatic purchase logging OFF. Do not enable codeless or matching.
- Business Settings > Apps: BLW Apps portfolio ID 3881159028598226. Link only the intended
  usable ad account; currently listed A1 1753797805416038 is restricted/disabled. Do not
  claim this is a valid campaign destination. Authorized ad accounts currently 0/100.
- Events Manager > WarrantyCave > Test Events: real clean install, then explicit Allow
  in Settings. Current status is no events received. Verify again after the exact signed
  Play build or matching debug certificate is installed. Keep the event page open.
- Play Console > App content > Data Safety: preserve existing declarations and review
  optional device IDs/app interaction/diagnostics and sharing for Meta install measurement.
  Data transmitted after Allow still counts as collected/shared even when optional.
- Campaign draft: App promotion, Android, this exact App ID + package/listing; inspect
  promoted object validation (#1815437). Do not publish until real event verification,
  account readiness and immediate user confirmation of spending.

## Website privacy disclosure to incorporate into the existing policy

WarrantyCave offers optional Meta app install and activation measurement. It is disabled
by default. If you allow it in Settings, the Meta Android SDK sends install and app
activation events and associated identifiers, device/app details and SDK diagnostic
information to Meta for advertising attribution and measurement. This can include the
Android advertising identifier when available; Meta also receives network information
when the SDK contacts its services. Warranty contents, receipts, photos, account profile,
billing purchases and referrals are not sent by this integration. You can turn off
future measurement in Settings at any time. Turning it off does not erase information
already sent to Meta. AdMob advertising consent is managed separately. For Meta's
processing, retention and privacy choices, see https://www.facebook.com/privacy/policy/.
Use the existing policy contact and deletion procedure for requests to WarrantyCave.

This is ready-to-incorporate wording, not a claim that the live website was changed.
Preserve the rest of the current policy and deploy from its current hosting source.
