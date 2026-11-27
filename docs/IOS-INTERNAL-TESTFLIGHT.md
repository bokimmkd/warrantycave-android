# First internal iPhone test

The internal workflow builds the current iOS branch with the registered Firebase
application. Local warranties, scanning, PDF export and cloud account behavior
can be tested on a physical device. Ads and Apple purchases are disabled while
their production configuration and sandbox acceptance tests remain pending.

`configure_ios.py --internal` selects this explicit configuration. Its archive
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
