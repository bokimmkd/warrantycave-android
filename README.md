# WarrantyCave

WarrantyCave is a local-first Flutter Android app for storing and tracking consumer warranties.

## Core build

- Manual add/edit/delete flow with required product type, product name, purchase date, warranty duration, and editable expiry date
- Grouped predefined product types plus custom types
- Multiple compressed receipt and warranty photos stored inside the app documents directory
- Versioned JSON persistence with atomic writes and a backup recovery file
- Active, expiring soon, and expired classification
- Search, type/status filters, and date sorting
- Local Android reminders at 60, 30, 7, and 0 days before expiry
- Fixed state-preserving Material 3 bottom navigation
- Branded first-launch Welcome screen and commercial-style dialogs/bottom sheets
- Add Warranty entry sheet with manual flow and Smart Scan upgrade path
- Local PDF claim-pack summary and Android sharing
- Free-plan limit and honest upgrade screen without fake purchase buttons

## Architecture

UI state is separated from platform services through `LocalStorageService`, `PhotoStorageService`, `NotificationService`, `SubscriptionService`, `CloudSyncService`, and `SmartScanService`. Firebase, Google Play Billing, and an AI parser are deliberately not runtime dependencies of the stable local build.

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

The test release APK is signed with the Android debug key for direct sideload testing. Configure a private upload key and Play App Signing before store distribution.
