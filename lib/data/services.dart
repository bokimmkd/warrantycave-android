import 'dart:convert';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../domain/models.dart';

abstract interface class LocalStorageService {
  Future<(List<WarrantyItem>, AppSettings)> load();
  Future<void> save(List<WarrantyItem> items, AppSettings settings);
}

abstract interface class PhotoStorageService {
  Future<String?> capture(ImageSource source, String itemId, String kind);
  Future<void> delete(String path);
}

abstract interface class NotificationService {
  Future<void> initialize();
  Future<bool> requestPermission();
  Future<void> scheduleFor(WarrantyItem item, AppSettings settings);
  Future<void> cancelFor(String itemId);
}

abstract interface class CloudSyncService {
  bool get isConfigured;
  Future<void> sync();
}

abstract interface class SubscriptionService {
  Future<PlanTier> currentPlan();
  bool canAddItem(PlanTier tier, int currentCount);
}

class ScanSuggestion {
  const ScanSuggestion({
    this.store,
    this.purchaseDate,
    this.price,
    this.productName,
    this.brand,
    this.model,
    this.serialNumber,
    this.currency,
    this.remainingCredits,
  });
  final String? store;
  final DateTime? purchaseDate;
  final double? price;
  final String? productName;
  final String? brand;
  final String? model;
  final String? serialNumber;
  final String? currency;
  final int? remainingCredits;
}

abstract interface class SmartScanService {
  bool get isConfigured;
  Future<ScanSuggestion> scan(String localImagePath);
}

class JsonLocalStorageService implements LocalStorageService {
  Future<File> get _file async => File(
    '${(await getApplicationDocumentsDirectory()).path}/warrantycave/data.json',
  );

  @override
  Future<(List<WarrantyItem>, AppSettings)> load() async {
    final file = await _file;
    for (final candidate in [file, File('${file.path}.bak')]) {
      try {
        if (!await candidate.exists()) continue;
        final root =
            jsonDecode(await candidate.readAsString()) as Map<String, dynamic>;
        final items = (root['items'] as List? ?? const [])
            .map(
              (entry) => WarrantyItem.fromJson(
                Map<String, dynamic>.from(entry as Map),
              ),
            )
            .toList();
        final settings = AppSettings.fromJson(
          Map<String, dynamic>.from(root['settings'] as Map? ?? const {}),
        );
        return (items, settings);
      } catch (_) {
        continue;
      }
    }
    return (<WarrantyItem>[], const AppSettings());
  }

  @override
  Future<void> save(List<WarrantyItem> items, AppSettings settings) async {
    final file = await _file;
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    if (await file.exists()) await file.copy('${file.path}.bak');
    await temp.writeAsString(
      jsonEncode({
        'schemaVersion': 2,
        'items': items.map((e) => e.toJson()).toList(),
        'settings': settings.toJson(),
      }),
      flush: true,
    );
    await temp.rename(file.path);
  }
}

class LocalPhotoStorageService implements PhotoStorageService {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<String?> capture(
    ImageSource source,
    String itemId,
    String kind,
  ) async {
    final isProductPhoto = kind == 'product';
    final image = await _picker.pickImage(
      source: source,
      imageQuality: isProductPhoto ? 65 : 72,
      maxWidth: isProductPhoto ? 1200 : 1600,
      maxHeight: isProductPhoto ? 1200 : 2200,
    );
    if (image == null) return null;
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory('${root.path}/warrantycave/photos/$itemId/$kind');
    await folder.create(recursive: true);
    final path = '${folder.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(image.path).copy(path);
    return path;
  }

  @override
  Future<void> delete(String path) async {
    if (path.startsWith('https://') || path.startsWith('gs://')) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

class LocalNotificationService implements NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    await initialize();
    return await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission() ??
        true;
  }

  @override
  Future<void> scheduleFor(WarrantyItem item, AppSettings settings) async {
    await initialize();
    await cancelFor(item.id);
    final reminders = <int, bool>{
      60: settings.reminder60,
      30: settings.reminder30,
      7: settings.reminder7,
      0: settings.reminderExpiry,
    };
    var slot = 0;
    for (final entry in reminders.entries) {
      final date = dateOnly(
        item.expiryDate,
      ).subtract(Duration(days: entry.key));
      final scheduled = tz.TZDateTime(
        tz.local,
        date.year,
        date.month,
        date.day,
        9,
      );
      if (entry.value && scheduled.isAfter(tz.TZDateTime.now(tz.local))) {
        await _plugin.zonedSchedule(
          _notificationId(item.id, slot),
          entry.key == 0
              ? '${item.productName} warranty expires today'
              : '${item.productName} warranty expires in ${entry.key} days',
          'Open WarrantyCave to review your documents.',
          scheduled,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'warranty_expiry',
              'Warranty expiry reminders',
              channelDescription: 'Alerts before a warranty expires',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: item.id,
        );
      }
      slot++;
    }
  }

  @override
  Future<void> cancelFor(String itemId) async {
    await initialize();
    for (var i = 0; i < 4; i++)
      await _plugin.cancel(_notificationId(itemId, i));
  }

  int _notificationId(String value, int slot) =>
      ((value.hashCode & 0x3fffffff) * 4 + slot) & 0x7fffffff;
}

class LocalSubscriptionService implements SubscriptionService {
  @override
  Future<PlanTier> currentPlan() async => PlanTier.free;
  @override
  bool canAddItem(PlanTier tier, int currentCount) =>
      currentCount < tier.itemLimit;
}

class FirebaseReadyCloudSyncService implements CloudSyncService {
  @override
  bool get isConfigured => false;
  @override
  Future<void> sync() =>
      throw StateError('Firebase is not configured in this local-first build.');
}

class BackendReadySmartScanService implements SmartScanService {
  @override
  bool get isConfigured => false;
  @override
  Future<ScanSuggestion> scan(String localImagePath) =>
      throw StateError('Smart Scan backend is not configured.');
}
