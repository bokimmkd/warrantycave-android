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
SDK versions. A verified real install event remains a release gate, not a presumed result.
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
6. After the physical clean-install event and privacy checks, make a signed AAB and submit
   Alpha 39. This provides a real **Play 38 -> 39** update test using the controller already
   installed in 38. A direct debug APK install cannot verify the Play update flow.
7. Verify `application_id` error #1815437 is absent in an unpublished campaign draft.
   App Promotion spend/publish remains blocked until event verification and the user's
   immediate publish confirmation. Production/public install availability is separate.

No campaign has been published, and no advertising spend is authorized by this file.
