import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_cave/domain/models.dart';

WarrantyItem itemExpiring(DateTime expiry) => WarrantyItem(
  id: 'test',
  productType: 'TV',
  productName: 'Living room TV',
  purchaseDate: DateTime(2025, 1, 1),
  expiryDate: expiry,
  durationLabel: '1 year',
  createdAt: DateTime(2025, 1, 1),
);

void main() {
  group('warranty status', () {
    final now = DateTime(2026, 1, 1, 18);

    test('active outside threshold', () {
      expect(
        itemExpiring(DateTime(2026, 4, 1)).status(now: now),
        WarrantyStatus.active,
      );
    });

    test('expiring soon inside default 60-day threshold', () {
      expect(
        itemExpiring(DateTime(2026, 2, 1)).status(now: now),
        WarrantyStatus.expiringSoon,
      );
    });

    test('expired after expiry date', () {
      expect(
        itemExpiring(DateTime(2025, 12, 20)).status(now: now),
        WarrantyStatus.expired,
      );
      expect(
        itemExpiring(DateTime(2025, 12, 20)).remainingLabel(now: now),
        'Expired 12 days ago',
      );
    });

    test('expiry day is still expiring soon', () {
      expect(
        itemExpiring(DateTime(2026, 1, 1)).remainingLabel(now: now),
        'Expires today',
      );
    });
  });

  group('expiry calculation', () {
    test('one year keeps the same calendar day', () {
      expect(
        addMonthsClamped(DateTime(2026, 9, 20), 12),
        DateTime(2027, 9, 20),
      );
    });

    test('clamps leap day safely', () {
      expect(
        addMonthsClamped(DateTime(2024, 2, 29), 12),
        DateTime(2025, 2, 28),
      );
    });

    test('clamps end of month', () {
      expect(addMonthsClamped(DateTime(2025, 8, 31), 6), DateTime(2026, 2, 28));
    });
  });

  test('free plan keeps a ten item limit with ads', () {
    expect(PlanTier.free.itemLimit, 10);
    expect(PlanTier.free.hasCloud, isFalse);
    expect(PlanTier.free.hasAds, isTrue);
    expect(PlanTier.basic.hasAds, isFalse);
    expect(PlanTier.basic.itemLimit, 15);
    expect(PlanTier.plus.itemLimit, 50);
    expect(PlanTier.basic.hasSmartScan, isFalse);
    expect(PlanTier.plus.hasSmartScan, isFalse);
    expect(PlanTier.free.hasBarcodeScanner, isFalse);
    expect(PlanTier.basic.hasBarcodeScanner, isTrue);
    expect(PlanTier.plus.hasBarcodeScanner, isTrue);
  });

  test('item JSON round trip preserves photos and values', () {
    final original = WarrantyItem(
      id: 'abc',
      productType: 'Phone',
      productName: 'Phone',
      brand: 'Brand',
      purchaseDate: DateTime(2026, 1, 1),
      expiryDate: DateTime(2028, 1, 1),
      durationLabel: '2 years',
      createdAt: DateTime(2026, 1, 1),
      receiptPhotos: const ['/receipt.jpg'],
      warrantyPhotos: const ['/warranty.jpg'],
      productPhoto: '/product.jpg',
      location: 'Vacation home',
      servicePhone: '+38970111222',
      serviceEmail: 'service@example.com',
      authorizedService: 'Brand Care Center',
      currency: 'EUR',
      purchasePrice: 499.99,
    );
    final restored = WarrantyItem.fromJson(original.toJson());
    expect(restored.productName, original.productName);
    expect(restored.receiptPhotos, original.receiptPhotos);
    expect(restored.productPhoto, original.productPhoto);
    expect(restored.location, 'Vacation home');
    expect(restored.servicePhone, '+38970111222');
    expect(restored.serviceEmail, 'service@example.com');
    expect(restored.authorizedService, 'Brand Care Center');
    expect(restored.currency, 'EUR');
    expect(restored.purchasePrice, original.purchasePrice);
  });

  test('settings preserve profile and default currency', () {
    const original = AppSettings(
      firstName: 'Alex',
      lastName: 'Cave',
      email: 'alex@example.com',
      phone: '+38970000000',
      defaultCurrency: 'EUR',
      languageCode: 'mk',
      referralCode: 'WCABC12345',
      pendingReferralCode: 'WCINVITE99',
    );
    final restored = AppSettings.fromJson(original.toJson());
    expect(restored.firstName, 'Alex');
    expect(restored.lastName, 'Cave');
    expect(restored.email, 'alex@example.com');
    expect(restored.phone, '+38970000000');
    expect(restored.defaultCurrency, 'EUR');
    expect(restored.languageCode, 'mk');
    expect(restored.referralCode, 'WCABC12345');
    expect(restored.pendingReferralCode, 'WCINVITE99');
  });

  test('reminders require explicit user opt-in', () {
    const settings = AppSettings();
    expect(settings.reminder60, isFalse);
    expect(settings.reminder30, isFalse);
    expect(settings.reminder7, isFalse);
    expect(settings.reminderExpiry, isFalse);
    expect(settings.notificationConsentGranted, isFalse);
  });

  test('referral policy normalizes codes and never implies signup reward', () {
    expect(ReferralPolicy.normalize(' wc-ab 12! '), 'WCAB12');
    expect(ReferralPolicy.isValid('WCAB12'), isTrue);
    expect(ReferralPolicy.isValid('123'), isFalse);
    expect(ReferralPolicy.rewardDays, 30);
    expect(
      ReferralPolicy.googlePlayDownloadUrl,
      'https://play.google.com/store/apps/details?id=com.warrantycave.app',
    );
    expect(
      ReferralPolicy.linkForCode('wc-ab12'),
      'https://warrantycave.com/ref/WCAB12',
    );
  });

  test('money formatting uses selected currency', () {
    expect(formatMoney(24990, 'MKD'), '24990 MKD');
    expect(formatMoney(399.99, 'EUR'), '€399.99');
    expect(formatMoney(449.99, 'USD'), r'$449.99');
  });
}
