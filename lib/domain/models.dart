import 'package:flutter/material.dart';

enum WarrantyStatus { active, expiringSoon, expired }

enum PlanTier { free, basic, plus }

extension PlanTierX on PlanTier {
  String get label => switch (this) {
    PlanTier.free => 'Free',
    PlanTier.basic => 'Basic',
    PlanTier.plus => 'Plus',
  };
  int get itemLimit => switch (this) {
    PlanTier.free => 10,
    PlanTier.basic => 15,
    PlanTier.plus => 50,
  };
  bool get hasCloud => this != PlanTier.free;
  bool get hasSmartScan => false;
  bool get hasBarcodeScanner => this != PlanTier.free;
  bool get hasAds => this == PlanTier.free;
}

/// Referral codes are identifiers only. Rewards must be granted by the backend
/// after Google Play confirms the referred user's first paid purchase.
class ReferralPolicy {
  static const rewardDays = 30;
  static const minimumCodeLength = 6;
  static const maximumCodeLength = 24;
  static const googlePlayDownloadUrl =
      'https://play.google.com/store/apps/details?id=com.warrantycave.app';

  static String normalize(String value) =>
      value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static bool isValid(String value) {
    final code = normalize(value);
    return code.length >= minimumCodeLength && code.length <= maximumCodeLength;
  }

  static String codeForUser(String uid) {
    final clean = normalize(uid);
    if (clean.length >= 10) return 'WC${clean.substring(0, 10)}';
    return 'WC${clean.padRight(10, '0')}';
  }

  static String linkForCode(String code) =>
      'https://warrantycave.com/ref/${normalize(code)}';
}

class ProductTypeOption {
  const ProductTypeOption(this.category, this.name, this.icon);
  final String category;
  final String name;
  final IconData icon;
}

const productTypes = <ProductTypeOption>[
  ProductTypeOption('Electronics', 'TV', Icons.tv_outlined),
  ProductTypeOption('Electronics', 'Phone', Icons.smartphone_outlined),
  ProductTypeOption('Electronics', 'Computer', Icons.computer_outlined),
  ProductTypeOption('Electronics', 'Laptop', Icons.laptop_outlined),
  ProductTypeOption('Electronics', 'Tablet', Icons.tablet_outlined),
  ProductTypeOption('Electronics', 'Monitor', Icons.monitor_outlined),
  ProductTypeOption('Electronics', 'Printer', Icons.print_outlined),
  ProductTypeOption(
    'Electronics',
    'Gaming Console',
    Icons.sports_esports_outlined,
  ),
  ProductTypeOption('Electronics', 'Camera', Icons.photo_camera_outlined),
  ProductTypeOption('Electronics', 'Audio / Speakers', Icons.speaker_outlined),
  ProductTypeOption(
    'Electronics',
    'Router / Network Equipment',
    Icons.router_outlined,
  ),
  ProductTypeOption('Home Appliances', 'Refrigerator', Icons.kitchen_outlined),
  ProductTypeOption('Home Appliances', 'Freezer', Icons.ac_unit_outlined),
  ProductTypeOption(
    'Home Appliances',
    'Washing Machine',
    Icons.local_laundry_service_outlined,
  ),
  ProductTypeOption('Home Appliances', 'Dryer', Icons.dry_cleaning_outlined),
  ProductTypeOption(
    'Home Appliances',
    'Dishwasher',
    Icons.countertops_outlined,
  ),
  ProductTypeOption(
    'Home Appliances',
    'Oven / Stove',
    Icons.microwave_outlined,
  ),
  ProductTypeOption('Home Appliances', 'Microwave', Icons.microwave_outlined),
  ProductTypeOption('Home Appliances', 'Air Conditioner', Icons.air_outlined),
  ProductTypeOption(
    'Home Appliances',
    'Vacuum Cleaner',
    Icons.cleaning_services_outlined,
  ),
  ProductTypeOption(
    'Home Appliances',
    'Coffee Machine',
    Icons.coffee_maker_outlined,
  ),
  ProductTypeOption(
    'Home Appliances',
    'Small Appliance',
    Icons.blender_outlined,
  ),
  ProductTypeOption('Tools', 'Power Tool', Icons.handyman_outlined),
  ProductTypeOption('Tools', 'Garden Tool', Icons.yard_outlined),
  ProductTypeOption(
    'Auto',
    'Car Electronics / Accessories',
    Icons.directions_car_outlined,
  ),
  ProductTypeOption('Other', 'Other', Icons.category_outlined),
  ProductTypeOption('Other', 'Custom', Icons.edit_outlined),
];

IconData iconForType(String type) =>
    productTypes
        .where((entry) => entry.name == type)
        .map((entry) => entry.icon)
        .firstOrNull ??
    Icons.inventory_2_outlined;

class WarrantyItem {
  WarrantyItem({
    required this.id,
    required this.productType,
    required this.productName,
    required this.purchaseDate,
    required this.expiryDate,
    required this.durationLabel,
    required this.createdAt,
    this.brand = '',
    this.model = '',
    this.serialNumber = '',
    this.store = '',
    this.authorizedService = '',
    this.servicePhone = '',
    this.serviceEmail = '',
    this.location = '',
    this.purchasePrice,
    this.currency = 'MKD',
    this.notes = '',
    this.productPhoto,
    this.receiptPhotos = const [],
    this.warrantyPhotos = const [],
  });

  final String id;
  final String productType;
  final String productName;
  final String brand;
  final String model;
  final String serialNumber;
  final String store;
  final String authorizedService;
  final String servicePhone;
  final String serviceEmail;
  final String location;
  final double? purchasePrice;
  final String currency;
  final String notes;
  final String? productPhoto;
  final DateTime purchaseDate;
  final DateTime expiryDate;
  final String durationLabel;
  final DateTime createdAt;
  final List<String> receiptPhotos;
  final List<String> warrantyPhotos;

  WarrantyStatus status({int thresholdDays = 60, DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());
    final expiry = dateOnly(expiryDate);
    if (expiry.isBefore(today)) return WarrantyStatus.expired;
    return expiry.difference(today).inDays <= thresholdDays
        ? WarrantyStatus.expiringSoon
        : WarrantyStatus.active;
  }

  int remainingDays({DateTime? now}) =>
      dateOnly(expiryDate).difference(dateOnly(now ?? DateTime.now())).inDays;

  String remainingLabel({DateTime? now}) {
    final days = remainingDays(now: now);
    if (days < 0) return 'Expired ${-days} day${days == -1 ? '' : 's'} ago';
    if (days == 0) return 'Expires today';
    if (days <= 60) return 'Expires in $days day${days == 1 ? '' : 's'}';
    return '$days days remaining';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'productType': productType,
    'productName': productName,
    'brand': brand,
    'model': model,
    'serialNumber': serialNumber,
    'store': store,
    'authorizedService': authorizedService,
    'servicePhone': servicePhone,
    'serviceEmail': serviceEmail,
    'location': location,
    'purchasePrice': purchasePrice,
    'currency': currency,
    'notes': notes,
    'productPhoto': productPhoto,
    'purchaseDate': purchaseDate.toIso8601String(),
    'expiryDate': expiryDate.toIso8601String(),
    'durationLabel': durationLabel,
    'createdAt': createdAt.toIso8601String(),
    'receiptPhotos': receiptPhotos,
    'warrantyPhotos': warrantyPhotos,
  };

  factory WarrantyItem.fromJson(Map<String, dynamic> json) => WarrantyItem(
    id: json['id'] as String,
    productType: json['productType'] as String,
    productName: json['productName'] as String,
    brand: json['brand'] as String? ?? '',
    model: json['model'] as String? ?? '',
    serialNumber: json['serialNumber'] as String? ?? '',
    store: json['store'] as String? ?? '',
    authorizedService: json['authorizedService'] as String? ?? '',
    servicePhone: json['servicePhone'] as String? ?? '',
    serviceEmail: json['serviceEmail'] as String? ?? '',
    location: json['location'] as String? ?? '',
    purchasePrice: (json['purchasePrice'] as num?)?.toDouble(),
    currency: json['currency'] as String? ?? 'MKD',
    notes: json['notes'] as String? ?? '',
    productPhoto: json['productPhoto'] as String?,
    purchaseDate: DateTime.parse(json['purchaseDate'] as String),
    expiryDate: DateTime.parse(json['expiryDate'] as String),
    durationLabel: json['durationLabel'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    receiptPhotos: List<String>.from(
      json['receiptPhotos'] as List? ?? const [],
    ),
    warrantyPhotos: List<String>.from(
      json['warrantyPhotos'] as List? ?? const [],
    ),
  );
}

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime addMonthsClamped(DateTime date, int months) {
  final targetMonth = date.month - 1 + months;
  final year = date.year + targetMonth ~/ 12;
  final month = targetMonth % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, date.day.clamp(1, lastDay));
}

class AppSettings {
  const AppSettings({
    this.onboardingComplete = false,
    this.expiringThresholdDays = 60,
    this.reminder60 = false,
    this.reminder30 = false,
    this.reminder7 = false,
    this.reminderExpiry = false,
    this.notificationConsentGranted = false,
    this.plan = PlanTier.free,
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.phone = '',
    this.defaultCurrency = 'MKD',
    this.cloudOwnerUid = '',
    this.languageCode = 'en',
    this.referralCode = '',
    this.pendingReferralCode = '',
    this.smartScanCredits = 0,
    this.planExpiresAt,
  });

  final bool onboardingComplete;
  final int expiringThresholdDays;
  final bool reminder60;
  final bool reminder30;
  final bool reminder7;
  final bool reminderExpiry;
  final bool notificationConsentGranted;
  final PlanTier plan;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String defaultCurrency;
  final String cloudOwnerUid;
  final String languageCode;
  final String referralCode;
  final String pendingReferralCode;
  final int smartScanCredits;
  final DateTime? planExpiresAt;

  AppSettings copyWith({
    bool? onboardingComplete,
    int? expiringThresholdDays,
    bool? reminder60,
    bool? reminder30,
    bool? reminder7,
    bool? reminderExpiry,
    bool? notificationConsentGranted,
    PlanTier? plan,
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? defaultCurrency,
    String? cloudOwnerUid,
    String? languageCode,
    String? referralCode,
    String? pendingReferralCode,
    int? smartScanCredits,
    DateTime? planExpiresAt,
    bool clearPlanExpiry = false,
  }) => AppSettings(
    onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    expiringThresholdDays: expiringThresholdDays ?? this.expiringThresholdDays,
    reminder60: reminder60 ?? this.reminder60,
    reminder30: reminder30 ?? this.reminder30,
    reminder7: reminder7 ?? this.reminder7,
    reminderExpiry: reminderExpiry ?? this.reminderExpiry,
    notificationConsentGranted:
        notificationConsentGranted ?? this.notificationConsentGranted,
    plan: plan ?? this.plan,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    defaultCurrency: defaultCurrency ?? this.defaultCurrency,
    cloudOwnerUid: cloudOwnerUid ?? this.cloudOwnerUid,
    languageCode: languageCode ?? this.languageCode,
    referralCode: referralCode ?? this.referralCode,
    pendingReferralCode: pendingReferralCode ?? this.pendingReferralCode,
    smartScanCredits: smartScanCredits ?? this.smartScanCredits,
    planExpiresAt: clearPlanExpiry ? null : planExpiresAt ?? this.planExpiresAt,
  );

  Map<String, dynamic> toJson() => {
    'onboardingComplete': onboardingComplete,
    'expiringThresholdDays': expiringThresholdDays,
    'reminder60': reminder60,
    'reminder30': reminder30,
    'reminder7': reminder7,
    'reminderExpiry': reminderExpiry,
    'notificationConsentGranted': notificationConsentGranted,
    'plan': plan.name,
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'phone': phone,
    'defaultCurrency': defaultCurrency,
    'cloudOwnerUid': cloudOwnerUid,
    'languageCode': languageCode,
    'referralCode': referralCode,
    'pendingReferralCode': pendingReferralCode,
    'smartScanCredits': smartScanCredits,
    'planExpiresAt': planExpiresAt?.toIso8601String(),
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    onboardingComplete: json['onboardingComplete'] as bool? ?? false,
    expiringThresholdDays: json['expiringThresholdDays'] as int? ?? 60,
    reminder60: json['reminder60'] as bool? ?? false,
    reminder30: json['reminder30'] as bool? ?? false,
    reminder7: json['reminder7'] as bool? ?? false,
    reminderExpiry: json['reminderExpiry'] as bool? ?? false,
    notificationConsentGranted:
        json['notificationConsentGranted'] as bool? ?? false,
    plan:
        PlanTier.values.where((e) => e.name == json['plan']).firstOrNull ??
        PlanTier.free,
    firstName: json['firstName'] as String? ?? '',
    lastName: json['lastName'] as String? ?? '',
    email: json['email'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    defaultCurrency: json['defaultCurrency'] as String? ?? 'MKD',
    cloudOwnerUid: json['cloudOwnerUid'] as String? ?? '',
    languageCode: json['languageCode'] as String? ?? 'en',
    referralCode: json['referralCode'] as String? ?? '',
    pendingReferralCode: json['pendingReferralCode'] as String? ?? '',
    smartScanCredits: (json['smartScanCredits'] as num?)?.toInt() ?? 0,
    planExpiresAt: json['planExpiresAt'] == null
        ? null
        : DateTime.tryParse(json['planExpiresAt'] as String),
  );
}

const supportedCurrencies = <String>[
  'MKD',
  'EUR',
  'USD',
  'GBP',
  'CHF',
  'TRY',
  'RSD',
  'ALL',
  'JPY',
  'RUB',
  'CNY',
  'AUD',
  'CAD',
];

String formatMoney(double value, String currency) {
  final amount = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  return switch (currency) {
    'EUR' => '€$amount',
    'USD' => '\$$amount',
    'GBP' => '£$amount',
    'CHF' => 'CHF $amount',
    'JPY' => '¥$amount',
    'RUB' => '₽$amount',
    'CNY' => '¥$amount',
    'AUD' => 'A\$$amount',
    'CAD' => 'C\$$amount',
    _ => '$amount $currency',
  };
}
