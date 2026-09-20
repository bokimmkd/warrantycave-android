# WarrantyCave 1.0.4 — build 14

## Release artifact

- Android package: `com.warrantycave.app`
- Version: `1.0.4+14`
- Minimum Android: API 24
- Target / compile Android: API 36
- Release APK: 67.5 MB
- APK Signature Scheme v2: verified
- SHA-256: `5bca452dafd722a885f0438f0076383e856f58e37a4c55058a7c3f1efc10c4ee`

This direct-install APK is signed with the Android debug certificate. Configure
a private Play upload/release key before publishing through Google Play.

## Firebase configuration

- Firebase project: `warrantycave`
- Android app: `com.warrantycave.app`
- Email/password authentication: enabled
- Email verification and password reset: implemented
- Password-reset confirmation uses account-safe wording and does not claim an
  email was sent when the address has no account
- The owner test account receives the highest in-app plan for subscription
  testing without a Google Play charge
- Receipt and warranty-document upload controls use matching full-width cards
  with one clear action per section
- Firestore database: Standard edition, `eur3 (Europe)`
- Firestore rules: authenticated users can access only `/users/{uid}` and its
  descendants
- Account deletion: re-authentication, cloud-data deletion, Firebase account
  deletion, and local cleanup
- Google Android SHA-1 fingerprints: registered

Google Sign-In still requires a Firebase project owner to enable the Google
provider. The current project account can edit the Android app but Firebase
reports that it lacks permission to manage sign-in methods. The app therefore
shows Google Sign-In as pending owner approval instead of exposing a broken
button.

Firebase Blaze is active with a USD 5 budget alert. Cloud Storage is enabled in
`EUROPE-WEST1`, and owner-only rules restrict every photo path to the
authenticated UID under `/users/{uid}`.

Product, receipt, and warranty-document photos upload for cloud-enabled plans,
restore on another device, render from cloud URLs, and are deleted from cloud
when their warranty or account is removed.

Version 1.0.4 repairs previously double-encoded Firebase Storage photo URLs, so
existing cloud photos render again without being uploaded a second time. Home,
Items, Reminders, and Settings support pull-to-refresh cloud sync, and Settings
shows the latest successful sync time. Newly generated Claim Packs include a
WarrantyCave memorandum header and branded footer.

Plan cards are selectable and the selected plan is carried to one final action
at the bottom of the screen. Google Play purchases remain disabled until the
corresponding Play Console products and Billing dependency are configured.
Camera barcode entry likewise remains pending its native scanner dependency;
no non-functional scanner control is exposed in this build.

## Verification

- `flutter pub get`: passed
- Automated tests: passed — 11/11
- Release APK build: passed
- Package/version manifest check: passed
- APK v2 signature verification: passed
- Dart release compilation: passed as part of the APK build

The standalone analysis server crashed in this build host with a Dart VM bus
error. This was an environment-level analysis-process failure; widget/unit tests
and the full release compiler completed successfully.

## Install

1. Download the APK to the Android phone.
2. Open it and allow installation from the browser or file manager if Android
   asks.
3. Install over the prior WarrantyCave build. If Android reports a signing-key
   conflict, uninstall the earlier build first; uninstalling removes its local
   data.
4. Create an account, verify the email, sign in, and add a warranty item.
5. With the owner test account, confirm that the same warranty metadata and
   photos restore after signing in on another device. Photos remain device-local
   on the Spark plan.
