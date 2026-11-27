import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:warranty_cave/data/notification_planner.dart';
import 'package:warranty_cave/domain/models.dart';

WarrantyItem item(String id, DateTime expiry, {List<int>? days}) =>
    WarrantyItem(
      id: id,
      productType: 'Other',
      productName: id,
      brand: '',
      model: '',
      purchaseDate: DateTime(2026),
      expiryDate: expiry,
      durationLabel: '1 year',
      createdAt: DateTime(2026),
      reminderDays: days,
    );
const enabled = AppSettings(
  notificationConsentGranted: true,
  reminder60: true,
  reminder30: true,
  reminder7: true,
  reminderExpiry: true,
);

void main() {
  setUpAll(tzdata.initializeTimeZones);
  setUp(() => tz.setLocalLocation(tz.UTC));
  test(
    'iOS keeps the nearest 64 reminders across the whole account, independent of item order',
    () {
      final items = [
        for (var i = 0; i < 100; i++) item('far-$i', DateTime(2027, 1, i + 1)),
        item('near', DateTime(2026, 10, 30)),
      ];
      final reminders = planIOSReminders(
        items,
        enabled,
        now: DateTime.utc(2026, 10, 21),
      );
      expect(reminders.length, 64);
      expect(reminders[0].item.id, 'near');
      expect(reminders[0].days, 7);
      expect(reminders[1].item.id, 'near');
      expect(reminders[1].days, 0);
      for (var i = 1; i < reminders.length; i++) {
        expect(reminders[i].at.isBefore(reminders[i - 1].at), isFalse);
      }
      final reversed = planIOSReminders(
        items.reversed,
        enabled,
        now: DateTime.utc(2026, 10, 21),
      );
      expect(
        reversed.map((r) => '${r.item.id}/${r.days}'),
        reminders.map((r) => '${r.item.id}/${r.days}'),
      );
    },
  );
  test(
    'revoking consent, disabling an item and passed dates remove pending reminders',
    () {
      final next = item('next', DateTime(2026, 10, 30));
      expect(
        planIOSReminders([next], const AppSettings(), now: DateTime.utc(2026)),
        isEmpty,
      );
      expect(
        planIOSReminders(
          [item('disabled', next.expiryDate, days: [])],
          enabled,
          now: DateTime.utc(2026),
        ),
        isEmpty,
      );
      expect(
        planIOSReminders(
          [next],
          enabled,
          now: DateTime.utc(2026, 10, 30, 9, 1),
        ),
        isEmpty,
      );
    },
  );
  test(
    'reminders remain at 09:00 local time across a daylight-saving transition',
    () {
      tz.setLocalLocation(tz.getLocation('America/New_York'));
      final planned = planIOSReminders(
        [
          item('dst', DateTime(2026, 11, 2), days: [0]),
        ],
        enabled,
        now: tz.TZDateTime(tz.local, 2026, 10, 21),
      );
      expect(planned.single.at.hour, 9);
      expect(planned.single.at.timeZoneOffset, const Duration(hours: -5));
    },
  );
}
