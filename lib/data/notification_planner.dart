import 'package:timezone/timezone.dart' as tz;
import '../domain/models.dart';

class PlannedReminder {
  const PlannedReminder(this.item, this.days, this.at);
  final WarrantyItem item;
  final int days;
  final tz.TZDateTime at;
}

// iOS retains at most 64 pending requests. Select across the entire account,
// rather than allowing the last items iterated to replace earlier reminders.
List<PlannedReminder> planIOSReminders(
  Iterable<WarrantyItem> items,
  AppSettings settings, {
  required DateTime now,
}) {
  if (!settings.notificationConsentGranted) return [];
  final planned = <PlannedReminder>[];
  for (final item in items) {
    final reminders = item.effectiveReminderDays(settings);
    for (final days in const [60, 30, 7, 0]) {
      if (!reminders.contains(days)) continue;
      final date = dateOnly(item.expiryDate).subtract(Duration(days: days));
      final at = tz.TZDateTime(tz.local, date.year, date.month, date.day, 9);
      if (at.isAfter(now)) planned.add(PlannedReminder(item, days, at));
    }
  }
  planned.sort((a, b) {
    final date = a.at.compareTo(b.at);
    return date != 0 ? date : a.item.id.compareTo(b.item.id);
  });
  return planned.take(64).toList();
}
