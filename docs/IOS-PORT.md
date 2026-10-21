# WarrantyCave iOS port

Base: Android 1.0.36+47, release/1.0.36-navigation-labels at 229019cc.
The iOS bundle ID is provisionally `com.warrantycave.app`; register that exact
identifier in Apple Developer and as a separate iOS app in Firebase project
`warrantycave`. The Android Firebase app and Android AdMob units cannot serve as
the iOS registration. No Apple signing team, App Store numeric ID or iOS service
IDs have been invented or committed. The Developer enrollment ID is not a Team ID.

## Run on the Mac without cloud configuration

Use Flutter 3.47.5 and Xcode with the iOS simulator runtime installed:

```sh
flutter config --no-enable-swift-package-manager
python3 scripts/configure_ios.py --local
flutter pub get
open -a Simulator
flutter run --dart-define-from-file=.ios-dart-defines.json
```

This explicitly local-only Debug build uses the real local storage, notification,
photo/scanner, PDF export, sharing and iOS review bridges. Ads are disabled for
deterministic local testing; use `--dart-define=IOS_DISABLE_ADS=false` in a Debug
build to exercise Google's iOS test ads. Accounts/cloud and purchases are unavailable until the real services are
configured. Notification permission is requested only when the user enables
reminders. Simulator camera hardware, Apple sign-in, real subscriptions and
delivery of notifications while the app is closed need device/sandbox testing.
Because iOS retains at most 64 pending notification requests, the iOS scheduler
selects the nearest 64 across all warranties. It reconciles them on startup,
account changes and warranty/settings edits, including deletions and consent
revocation. Later reminders require reopening the app to refill the queue; this
is an iOS platform limit rather than a promise of unlimited offline scheduling.

The `iOS simulator and shared checks` workflow compiles Swift/plugins and runs
an integration test of native startup, guest warranty persistence and navigation.
Its app artifact is for Simulator; it is not a signed IPA or TestFlight upload.
Release/Profile builds fail if the native configuration is still local/development.

## Connect the real services

1. Wait for Apple's membership activation, then get the actual Team ID. Create
   WarrantyCave in App Store Connect and enable Sign in with Apple on the App ID.
2. Register `com.warrantycave.app` in the existing Firebase project. Enable Google
   and Apple authentication for it; configure Apple's key/team/provider and private
   email relay as required by Firebase. Download its `GoogleService-Info.plist`.
3. Create a separate iOS AdMob app and iOS banner units. Review UMP messages for
   the iOS app. Current iOS ad requests are nonpersonalized; the app does not
   request ATT or enable Meta install measurement on iOS. Analytics uses
   FirebaseAnalytics/Core without advertising identity support, starts disabled,
   and enables only after the separate usage consent choice. SDK privacy
   manifests do not replace App Store privacy answers.
4. Copy `ios/services.example.json` to `.ios-config.json` and supply the actual
   IDs. Leave `appleBillingEnabled` false until the backend and sandbox tests below
   pass. Do not put `.p8` keys in this JSON or in the repository.

```sh
python3 scripts/configure_ios.py --firebase-plist /path/to/GoogleService-Info.plist --config .ios-config.json
flutter run --dart-define-from-file=.ios-dart-defines.json
```

The helper validates the iOS bundle/project/app ID, installs the local plist,
generates native Google URL schemes/AdMob settings and Dart settings, and decodes
the existing PDF fonts. These machine-specific outputs are ignored by git.

## Apple subscriptions

Create these **auto-renewable, one-year products in one subscription group**:

| Product ID | Tier | Limit |
| --- | --- | --- |
| `warrantycave_basic_yearly` | Basic | 25 active items |
| `warrantycave_plus_yearly` | Plus | 100 active items |

Set Plus above Basic for upgrade/downgrade handling, configure storefront prices
and required subscription metadata, disable Family Sharing (ownership is bound
to the buyer's WarrantyCave account), and complete paid-app agreements/tax/banking.
The app displays prices returned by StoreKit rather than copied Android prices.

The server issues an opaque UUID for each authenticated/verified Firebase user.
StoreKit receives it as `appAccountToken`; restores cannot transfer purchases to
another WarrantyCave account. The server verifies Apple's JWS certificate chain
using the official Apple library and bundled Apple public root certificates, then
queries the App Store Server API for the **current** subscription status. Old
client receipts cannot reinstate refunded purchases. Only active/grace-period
subscriptions grant access. Finishing a StoreKit transaction follows successful
server confirmation; the client does not grant a paid plan on its own.

Configure on the Firebase Functions deployment (not in the app):

| Setting | Value |
| --- | --- |
| `APPLE_BUNDLE_ID` | `com.warrantycave.app` |
| `APPLE_APP_ID` | Actual numeric App Store Connect app ID |
| `APPLE_IAP_KEY_ID` | In-App Purchase server API key ID |
| `APPLE_IAP_ISSUER_ID` | Issuer ID for the key |
| Secret `APPLE_IAP_PRIVATE_KEY` | Contents of the server API `.p8` key |
| `APPLE_ALLOW_SANDBOX` | `true` for TestFlight/sandbox testing; explicit choice for production |

Deploy the new `getAppleBillingAccount`, `confirmApplePurchase`,
`onAppleSubscriptionUpdate` functions and updated `getEntitlements` together.
Configure **App Store Server Notifications V2** for production and sandbox:
`https://us-central1-warrantycave.cloudfunctions.net/onAppleSubscriptionUpdate`.
Send Apple's test notification and verify delivery before enabling purchases.
The port does not deploy functions or change any production account automatically.

Apple subscriptions live in server-only `appleSubscriptions` records, independent
of Play entitlement fields. The highest valid tier wins across stores and rewards.
Notifications reconcile renewal, cancellation, grace, expiration and refunds;
on account sync, records older than five minutes are refreshed from Apple.
First paid Apple purchases can trigger the existing one-time inviter Plus reward;
the implementation does **not** extend an Apple renewal charge date. Review the
referral offer and emails for iOS before release, including mixed-store customers.

## Before TestFlight / App Store submission

Run signed device/sandbox checks for email, Google and Apple login; fresh and
returning Apple users; private relay email; reauthentication and account deletion
with Apple token revocation; camera/gallery/barcode access; reminders in the
background; PDF save/cancel in Files; share popovers on iPad; purchase, restore,
upgrade/downgrade, renewal, expiry, billing retry/grace, refund and wrong-account
restore. Verify referral behavior, consent and correct ad units on a device.

Verify the annual subscription disclosures/terms/privacy links, privacy nutrition labels,
screenshots, support/marketing links, age/content rating, export compliance and
reviewer login/instructions. Review the final aggregated privacy report from the
archive against all SDK behavior. Apple's review is separate from a successful
build; this branch is a draft until native CI and device/service checks pass.

After those checks, set `appleBillingEnabled` true and prepare the release:

```sh
python3 scripts/configure_ios.py --firebase-plist /path/to/GoogleService-Info.plist --config .ios-config.json --release
flutter build ipa --release --dart-define-from-file=.ios-dart-defines.json
```

Use `ios/Runner.xcworkspace` in Xcode, the actual developer team and distribution
signing. Upload the signed archive to App Store Connect/TestFlight, test it, and
submit a version to App Review. Upload/review/submission have not been performed
by this code change. Keep Android's published version/build numbers unchanged;
an iOS version/build can be set independently with Flutter build flags.

References: [Firebase Apple auth](https://firebase.google.com/docs/auth/flutter/federated-auth),
[Apple server library](https://github.com/apple/app-store-server-library-node),
[AdMob iOS setup](https://developers.google.com/admob/flutter/quick-start).
