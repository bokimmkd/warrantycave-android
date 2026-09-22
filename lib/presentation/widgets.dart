import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../domain/models.dart';
import '../l10n/app_localizations.dart';
import 'theme.dart';

bool isCloudPhoto(String path) =>
    path.startsWith('https://') || path.startsWith('http://');

/// Repairs download URLs written by the first Storage-enabled build, where
/// an already encoded object path was encoded a second time (`%2F` -> `%252F`).
/// Existing cloud photos therefore recover without being uploaded again.
String normalizedCloudPhotoUrl(String value) => value.replaceAllMapped(
  RegExp(r'%25([0-9A-Fa-f]{2})'),
  (match) => '%${match.group(1)}',
);

class StoredPhoto extends StatelessWidget {
  const StoredPhoto(
    this.path, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorColor,
  });

  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Color? errorColor;

  @override
  Widget build(BuildContext context) {
    Widget onError(BuildContext context, Object error, StackTrace? stack) =>
        SizedBox(
          width: width,
          height: height,
          child: Icon(Icons.broken_image_outlined, color: errorColor),
        );
    return isCloudPhoto(path)
        ? Image.network(
            normalizedCloudPhotoUrl(path),
            width: width,
            height: height,
            fit: fit,
            errorBuilder: onError,
          )
        : Image.file(
            File(path),
            width: width,
            height: height,
            fit: fit,
            errorBuilder: onError,
          );
  }
}

class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home_rounded),
          label: context.l10n.text('home'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.inventory_2_outlined),
          selectedIcon: const Icon(Icons.inventory_2_rounded),
          label: context.l10n.text('items'),
        ),
        NavigationDestination(
          icon: const DecoratedBox(
            decoration: BoxDecoration(color: caveBlue, shape: BoxShape.circle),
            child: Padding(
              padding: EdgeInsets.all(9),
              child: Icon(Icons.add, color: Colors.white),
            ),
          ),
          label: context.l10n.text('add'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.notifications_outlined),
          selectedIcon: const Icon(Icons.notifications_rounded),
          label: context.l10n.text('reminders'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings_rounded),
          label: context.l10n.text('settings'),
        ),
      ],
    ),
  );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: compact ? 38 : 48,
        height: compact ? 38 : 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [caveBlue, skyBlue]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.receipt_long_rounded, color: Colors.white),
      ),
      const SizedBox(width: 10),
      Text.rich(
        const TextSpan(
          children: [
            TextSpan(
              text: 'Warranty',
              style: TextStyle(color: caveNavy),
            ),
            TextSpan(
              text: 'Cave',
              style: TextStyle(color: caveTeal),
            ),
          ],
        ),
        style: TextStyle(
          fontSize: compact ? 18 : 24,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: caveNavy,
          ),
        ),
      ),
      if (action != null) action!,
    ],
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final WarrantyStatus status;
  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      WarrantyStatus.active => (
        context.l10n.text('active'),
        caveTeal,
        Icons.shield_outlined,
      ),
      WarrantyStatus.expiringSoon => (
        context.l10n.text('expiringSoon'),
        Colors.orange,
        Icons.schedule_outlined,
      ),
      WarrantyStatus.expired => (
        context.l10n.text('expired'),
        Colors.redAccent,
        Icons.cancel_outlined,
      ),
    };
    return AppStatusChip(label: label, color: color, icon: icon);
  }
}

class WarrantyCard extends StatelessWidget {
  const WarrantyCard({
    required this.item,
    required this.threshold,
    required this.onTap,
    super.key,
  });
  final WarrantyItem item;
  final int threshold;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AppCards(
    onTap: onTap,
    padding: const EdgeInsets.all(14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: const Color(0xFFE9F4FC),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child:
              item.productPhoto != null &&
                  (isCloudPhoto(item.productPhoto!) ||
                      File(item.productPhoto!).existsSync())
              ? StoredPhoto(item.productPhoto!)
              : Icon(iconForType(item.productType), color: caveBlue),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: caveNavy,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  StatusChip(item.status(thresholdDays: threshold)),
                ],
              ),
              if ([
                item.brand,
                item.model,
              ].where((e) => e.isNotEmpty).isNotEmpty)
                Text(
                  [
                    item.brand,
                    item.model,
                  ].where((e) => e.isNotEmpty).join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.blueGrey.shade600),
                ),
              const SizedBox(height: 5),
              Text(
                '${DateFormat.yMMMd(context.l10n.locale.languageCode).format(item.expiryDate)} • ${localizedRemainingLabel(context, item)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: caveBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

String localizedRemainingLabel(
  BuildContext context,
  WarrantyItem item, {
  DateTime? now,
}) {
  final days = item.remainingDays(now: now);
  if (days < 0) {
    return context.l10n.format('expiredDaysAgo', {'days': -days});
  }
  if (days == 0) return context.l10n.text('expiresToday');
  if (days <= 60) {
    return context.l10n.format('expiresInDays', {'days': days});
  }
  return context.l10n.format('daysRemaining', {'days': days});
}
