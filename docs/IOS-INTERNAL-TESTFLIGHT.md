# First internal iPhone test

## Device acceptance and release checkpoint — 27 November 2026

Build 1.0.44 (3) was uploaded and independently verified as VALID,
IN_BETA_TESTING and present in WarrantyCave Internal. The user's iPhone
screenshots confirm this build is installed, including ordinary and Bold Text
layouts. Keep the existing date-field ellipsis as requested. The next internal
build keeps the single search icon beside My Items at normal text size with
Bold Text; narrow and enlarged-text layouts retain the separate-row fallback.

Purchases are disabled by default. The account holder completes banking and
tax details in App Store Connect. The last verified Paid Apps Agreement status
is Pending User Info. Apple requires the agreement to be active for sandbox
purchases.

After the account holder completes banking/tax and the agreement is Active:

1. Create a separate In-App Purchase server key and securely configure the
   APPLE_IAP_PRIVATE_KEY secret and Apple identifiers described in IOS-PORT.md.
2. Deploy and verify the Apple entitlement/notification functions. Set
   `APPLE_ALLOW_SANDBOX=true` and `APPLE_SANDBOX_TESTER_UIDS` to the
   comma-separated Firebase UIDs of the designated test accounts. Validate
   Apple's test notification.
3. Set the GitHub Actions repository variable `IOS_TESTFLIGHT_SANDBOX_BILLING=true`
   when Apple and the backend are ready, then run the internal workflow. While
   the workflow is only on the feature branch, a push changing its workflow
   file triggers the run. Remove or clear the variable to return to the beta
   with purchases disabled.
4. On a test account, verify Basic/Plus purchase, cancel, restore, tier changes,
   expiry and wrong-account restore. TestFlight purchases use Apple's sandbox
   and do not charge the tester. Existing unit tests are not device acceptance.
5. Complete Apple sign-in/revocation, iOS AdMob/consent, branded native launch
   assets, App Store metadata/privacy and screenshots before release review.

Apple references: [IAP setup and Active agreement requirement](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/),
[TestFlight uses sandbox](https://developer.apple.com/in-app-purchase/).

The internal workflow builds the current iOS branch with the registered Firebase
application. Local warranties, scanning, PDF export and cloud account behavior
can be tested on a physical device. Ads and Apple purchases are disabled while
their production configuration and sandbox acceptance tests remain pending.

`configure_ios.py --internal` selects this explicit configuration, with
`--sandbox-billing` for the purchase-enabled beta. Its archive
guard requires matching Dart defines, the registered App Store ID, and an export
plist with `method=app-store-connect` and `testFlightInternalTestingOnly=true`.
The public release guard continues to require real iOS ads and enabled billing;
it rejects internal testing defines. Internal builds cannot be submitted to the
public App Store or external TestFlight groups.

The `iOS internal TestFlight` workflow runs only on `feature/ios-port`, when its
workflow file is pushed or through a manual dispatch. It uses these repository
secrets (never source files):

- `IOS_FIREBASE_PLIST_BASE64`: the registered iOS Firebase configuration.
- `IOS_DISTRIBUTION_PRIVATE_KEY_BASE64`: DER-encoded distribution private key.
- `APP_STORE_CONNECT_API_KEY_JSON`: Developer API key JSON with `key_id`,
  `issuer_id`, `key`, and `in_house=false`.

The workflow retrieves the registered profile from Apple, validates team,
bundle, entitlements and certificate/key pairing, signs in an ephemeral
keychain, exports the internal-only IPA, verifies its signature and uploads it
with altool. Cleanup restores the original keychain list and deletes private
signing inputs. Only the signed IPA is retained as a short-lived artifact.

After Apple finishes processing the upload, add the build and the account
holder to an internal TestFlight group. Install it through the TestFlight app.
Check guest warranty creation and persistence after restart, camera/photo scan,
PDF save/share, reminder permissions, login/cloud sync and account deletion.
Apple login also requires enabling the Apple provider in Firebase; verify it
separately before treating that login method as accepted.
