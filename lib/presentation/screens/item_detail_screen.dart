import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../theme.dart';
import '../widgets.dart';
import 'add_warranty_screen.dart';
import 'upgrade_screen.dart';

class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({
    required this.itemId,
    required this.onSelectTab,
    super.key,
  });
  final String itemId;
  final ValueChanged<int>? onSelectTab;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final matches = app.items.where((e) => e.id == itemId);
    if (matches.isEmpty)
      return Scaffold(
        body: Center(child: Text(context.l10n.text('warrantyMissing'))),
      );
    final item = matches.first;
    final canEdit = app.canEditItem(item);
    final archived = item.isArchived();
    final overLimit = app.countedItemCount > app.effectivePlan.itemLimit;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.text('warrantyDetails')),
        actions: [
          IconButton(
            onPressed: () async {
              if (!canEdit) {
                if (archived) {
                  await AppDialogs.message(
                    context,
                    title: context.l10n.text('archivedEditTitle'),
                    message: context.l10n.text('archivedEditMessage'),
                    buttonLabel: context.l10n.text('ok'),
                    icon: Icons.lock_outline_rounded,
                  );
                  return;
                }
                final viewPlans = await AppDialogs.confirm(
                  context,
                  title: context.l10n.text(
                    overLimit ? 'overLimitEditTitle' : 'editLockedTitle',
                  ),
                  message: context.l10n.text(
                    overLimit ? 'overLimitEditMessage' : 'editLockedPlan',
                  ),
                  confirmLabel: context.l10n.text('viewPlans'),
                  cancelLabel: context.l10n.text('cancel'),
                  icon: Icons.lock_outline_rounded,
                );
                if (viewPlans && context.mounted) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UpgradeScreen(
                        onSelectTab: (tab) => onSelectTab?.call(tab),
                      ),
                    ),
                  );
                }
                return;
              }
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddWarrantyScreen(
                    existing: item,
                    onSelectTab: onSelectTab,
                  ),
                ),
              );
            },
            icon: Icon(
              Icons.edit_outlined,
              color: canEdit ? null : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            tooltip: context.l10n.text(
              canEdit
                  ? 'edit'
                  : archived
                      ? 'archivedEditTitle'
                      : overLimit
                          ? 'overLimitEditTitle'
                          : 'editLockedTitle',
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton.filledTonal(
                tooltip: context.l10n.text('share'),
                icon: const Icon(Icons.share_outlined),
                onPressed: () => _shareText(context, item),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: context.l10n.text('claimPack'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: () => _claimPackAction(context, item),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _WarrantyHeader(item: item, settings: app.settings),
          const SizedBox(height: 16),
          _Details(item: item),
          if (item.receiptPhotos.isNotEmpty || item.warrantyPhotos.isNotEmpty) ...[
            const SizedBox(height: 14),
            _DocumentAttachments(item: item),
          ],
          if (item.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.text('notes'),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(item.notes),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          DangerButton(
            label: context.l10n.text('deleteWarrantyLabel'),
            onPressed: () => _delete(context, app, item),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNavigation(
        selectedIndex: 1,
        onSelected: (value) {
          if (onSelectTab != null) {
            onSelectTab!(value);
          } else if (value == 1) {
            Navigator.maybePop(context);
          }
        },
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    AppController app,
    WarrantyItem item,
  ) async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: context.l10n.text('deleteWarranty'),
      message: context.l10n.text('deleteWarrantyInfo'),
      confirmLabel: context.l10n.text('delete'),
      danger: true,
      icon: Icons.delete_forever_outlined,
    );
    if (confirmed) {
      final deleted = await app.delete(item);
      if (!context.mounted) return;
      if (deleted) {
        Navigator.pop(context);
      } else {
        AppSnackbars.error(context, context.l10n.text('networkFailed'));
      }
    }
  }

  Future<void> _shareText(BuildContext context, WarrantyItem item) =>
      SharePlus.instance.share(
        ShareParams(
          text: context.l10n.format('shareWarrantyText', {
            'product': item.productName,
            'details': '${item.brand} ${item.model}',
            'date': DateFormat.yMMMd(
              context.l10n.locale.toString(),
            ).format(item.expiryDate),
          }),
        ),
      );
  Future<void> _claimPackAction(BuildContext context, WarrantyItem item) async {
    final action = await AppBottomSheets.show<bool>(
      context,
      title: context.l10n.text('claimPack'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(context.l10n.text('downloadPdf')),
            onTap: () => Navigator.pop(context, true),
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: Text(context.l10n.text('sharePdf')),
            onTap: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
    if (action != null && context.mounted) {
      await _claimPack(context, item, download: action);
    }
  }

  Future<void> _claimPack(
    BuildContext context,
    WarrantyItem item, {
    required bool download,
  }) async {
    try {
      final regularFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/DejaVuSans.ttf'),
      );
      final boldFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'),
      );
      final doc = pw.Document(
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
      );
      final attachments = <({String label, String path})>[
        if (item.productPhoto != null)
          (label: context.l10n.text('productPhoto'), path: item.productPhoto!),
        ...item.receiptPhotos.indexed.map(
          (entry) => (
            label: context.l10n.format('receiptOf', {
              'current': entry.$1 + 1,
              'total': item.receiptPhotos.length,
            }),
            path: entry.$2,
          ),
        ),
        ...item.warrantyPhotos.indexed.map(
          (entry) => (
            label: context.l10n.format('warrantyDocumentOf', {
              'current': entry.$1 + 1,
              'total': item.warrantyPhotos.length,
            }),
            path: entry.$2,
          ),
        ),
      ];

      final status = switch (item.status()) {
        WarrantyStatus.active => context.l10n.text('active'),
        WarrantyStatus.expiringSoon => context.l10n.text('expiringSoon'),
        WarrantyStatus.expired => context.l10n.text('expired'),
      };
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(36),
          footer: (pageContext) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                context.l10n.text('generatedWith'),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
              ),
              pw.Text(
                context.l10n.format('pageOf', {
                  'current': pageContext.pageNumber,
                  'total': pageContext.pagesCount,
                }),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
              ),
            ],
          ),
          build: (_) => [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 46,
                  height: 46,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#175A91'),
                    borderRadius: pw.BorderRadius.circular(12),
                  ),
                  child: pw.Text(
                    'WC',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'WarrantyCave',
                      style: pw.TextStyle(
                        color: PdfColor.fromHex('#123A5A'),
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Scan. Store. Relax.',
                      style: pw.TextStyle(
                        color: PdfColor.fromHex('#19AFA5'),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.Divider(color: PdfColor.fromHex('#D9E7F1')),
            pw.SizedBox(height: 8),
            pw.Text(
              context.l10n.text('claimPackTitle'),
              style: pw.TextStyle(
                color: PdfColor.fromHex('#175A91'),
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              item.productName,
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              data: [
                [context.l10n.text('field'), context.l10n.text('value')],
                [context.l10n.text('productType'), context.l10n.productLabel(item.productType, context.read<AppController>().settings)],
                [context.l10n.text('brand'), item.brand],
                [context.l10n.text('model'), item.model],
                [context.l10n.text('serialNumber'), item.serialNumber],
                [context.l10n.text('warrantyStatus'), status],
                if (item.isExtendedWarranty)
                  [context.l10n.text('extendedWarrantyToggle'),
                   context.l10n.text('extendedWarrantyBadge')],
                [
                  context.l10n.text('timeRemaining'),
                  localizedRemainingLabel(context, item),
                ],
                [context.l10n.text('retailer'), item.store],
                [
                  context.l10n.text('authorizedService'),
                  item.authorizedService,
                ],
                [context.l10n.text('servicePhone'), item.servicePhone],
                [context.l10n.text('serviceEmail'), item.serviceEmail],
                [context.l10n.text('usedAt'), item.location],
                [
                  context.l10n.text('purchaseDate'),
                  DateFormat.yMMMd(
                    context.l10n.locale.toString(),
                  ).format(item.purchaseDate),
                ],
                [context.l10n.text('warrantyDuration'), context.l10n.duration(item.durationLabel)],
                [
                  context.l10n.text('expiryDate'),
                  DateFormat.yMMMd(
                    context.l10n.locale.toString(),
                  ).format(item.expiryDate),
                ],
                [
                  context.l10n.text('purchasePrice'),
                  item.purchasePrice == null
                      ? ''
                      : formatMoney(item.purchasePrice!, item.currency),
                ],
                [context.l10n.text('notes'), item.notes],
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              context.l10n.format('attachedReceipts', {
                'count': item.receiptPhotos.length,
              }),
            ),
            pw.Text(
              context.l10n.format('attachedWarranties', {
                'count': item.warrantyPhotos.length,
              }),
            ),
            pw.Text(
              context.l10n.format('totalImagePages', {
                'count': attachments.length,
              }),
            ),
            pw.SizedBox(height: 28),
            pw.Text(
              context.l10n.format('generatedOn', {
                'date': DateFormat.yMMMd(
                  context.l10n.locale.toString(),
                ).add_jm().format(DateTime.now()),
              }),
              style: const pw.TextStyle(color: PdfColors.grey),
            ),
          ],
        ),
      );

      for (final attachment in attachments) {
        try {
          final bytes = await _readPhotoBytes(attachment.path);
          if (bytes == null) continue;
          final image = pw.MemoryImage(bytes);
          doc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(36),
              build: (_) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    attachment.label,
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 18),
                  pw.Expanded(
                    child: pw.Center(
                      child: pw.Image(image, fit: pw.BoxFit.contain),
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Text(
                    item.productName,
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey,
                    ),
                  ),
                ],
              ),
            ),
          );
        } catch (_) {
          // Keep the rest of the claim pack usable if one local image is bad.
        }
      }
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/WarrantyCave_${item.productName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}.pdf',
      );
      await file.writeAsBytes(await doc.save());
      if (download) {
        final saved = await const MethodChannel('com.warrantycave.app/document_saver')
            .invokeMethod<bool>('savePdf', {
              'fileName': file.uri.pathSegments.last,
              'bytes': await file.readAsBytes(),
            });
        if (saved == true && context.mounted) {
          AppSnackbars.success(context, context.l10n.text('pdfSaved'));
        }
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            subject: context.l10n.format('claimPackSubject', {
              'product': item.productName,
            }),
          ),
        );
      }
    } catch (e) {
      if (context.mounted)
        AppSnackbars.error(context, context.l10n.text('claimPackFailed'));
    }
  }

  Future<Uint8List?> _readPhotoBytes(String path) async {
    if (isCloudPhoto(path)) {
      final response = await http.get(Uri.parse(normalizedCloudPhotoUrl(path)));
      return response.statusCode == 200 ? response.bodyBytes : null;
    }
    final file = File(path);
    return await file.exists() ? file.readAsBytes() : null;
  }
}

class _WarrantyHeader extends StatelessWidget {
  const _WarrantyHeader({required this.item, required this.settings});
  final WarrantyItem item;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (statusLabel, statusColor, statusIcon) = switch (
      item.status(thresholdDays: settings.expiringThresholdDays)
    ) {
      WarrantyStatus.active => (context.l10n.text('active'), caveTeal, Icons.shield_outlined),
      WarrantyStatus.expiringSoon => (context.l10n.text('expiringSoon'), Colors.orange, Icons.schedule_outlined),
      WarrantyStatus.expired => (context.l10n.text('expired'), Colors.redAccent, Icons.cancel_outlined),
    };
    return Card(
      key: const Key('warranty-header'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              key: const Key('warranty-product-heading'),
              children: [
                InkWell(
                  key: const Key('product-photo-preview'),
                  onTap: item.productPhoto == null ? null
                      : () => _openPhotos(context, [item.productPhoto!]),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 68, height: 68,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: item.productPhoto != null &&
                        (isCloudPhoto(item.productPhoto!) || File(item.productPhoto!).existsSync())
                      ? StoredPhoto(item.productPhoto!)
                      : Icon(iconForType(item.productType), size: 32, color: colors.primary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.productName,
                        key: const Key('warranty-product-name'),
                        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800,
                          color: colors.onSurface)),
                      const SizedBox(height: 4),
                      Text(context.l10n.productLabel(item.productType, settings),
                        style: TextStyle(color: colors.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _DetailBadge(
                    key: const Key('warranty-status-badge'),
                    label: statusLabel, color: statusColor, icon: statusIcon)),
                  if (item.isExtendedWarranty) ...[
                    const SizedBox(width: 8),
                    Expanded(child: _DetailBadge(
                      key: const Key('warranty-extended-badge'),
                      label: context.l10n.text('extendedWarrantyBadge'),
                      color: colors.primary, icon: Icons.verified_outlined)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(localizedRemainingLabel(context, item),
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, color: colors.primary)),
          ],
        ),
      ),
    );
  }
}

class _DetailBadge extends StatelessWidget {
  const _DetailBadge({super.key, required this.label, required this.color, required this.icon});
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 36),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      border: Border.all(color: color.withValues(alpha: .30)),
      borderRadius: BorderRadius.circular(18),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 5),
        Expanded(child: Text(label.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface))),
      ],
    ),
  );
}

void _openPhotos(BuildContext context, List<String> paths) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _PhotoPreview(paths: paths, initialIndex: 0),
    ),
  );
}

class _DetailEntry {
  const _DetailEntry(this.label, this.value, {this.contact});
  final String label;
  final String value;
  final Uri? contact;
}

class _Details extends StatelessWidget {
  const _Details({required this.item});
  final WarrantyItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rows = <_DetailEntry>[
      _DetailEntry(context.l10n.text('brand'), item.brand),
      _DetailEntry(context.l10n.text('model'), item.model),
      _DetailEntry(context.l10n.text('serialNumber'), item.serialNumber),
      _DetailEntry(context.l10n.text('storeRetailer'), item.store),
      _DetailEntry(context.l10n.text('authorizedService'), item.authorizedService),
      _DetailEntry(context.l10n.text('servicePhone'), item.servicePhone,
        contact: Uri(scheme: 'tel', path: item.servicePhone)),
      _DetailEntry(context.l10n.text('serviceEmail'), item.serviceEmail,
        contact: Uri(scheme: 'mailto', path: item.serviceEmail)),
      _DetailEntry(context.l10n.text('usedAt'), item.location),
      _DetailEntry(context.l10n.text('purchaseDate'),
        DateFormat.yMMMd(context.l10n.locale.toString()).format(item.purchaseDate)),
      _DetailEntry(context.l10n.text('purchasePrice'),
        item.purchasePrice == null ? '' : formatMoney(item.purchasePrice!, item.currency)),
      _DetailEntry(context.l10n.text('warrantyDuration'),
        context.l10n.duration(item.durationLabel)),
      _DetailEntry(context.l10n.text('expiryDate'),
        DateFormat.yMMMd(context.l10n.locale.toString()).format(item.expiryDate)),
    ].where((row) => row.value.isNotEmpty).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          key: const Key('warranty-details-fields'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: .5, color: colors.outlineVariant),
              _field(context, rows[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(BuildContext context, _DetailEntry row) {
    final colors = Theme.of(context).colorScheme;
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: row.contact == null ? 44 : 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(row.label, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(child: Text(row.value,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontWeight: FontWeight.w700, color: colors.onSurface))),
                if (row.contact != null) ...[
                  const SizedBox(width: 8),
                  Icon(row.contact!.scheme == 'tel' ? Icons.call_outlined : Icons.email_outlined,
                    size: 18, color: colors.primary),
                ],
              ],
            ),
          ],
        ),
      ),
    );
    return MergeSemantics(
      child: row.contact == null ? content : Semantics(
        button: true,
        child: InkWell(
          key: Key('warranty-contact-${row.contact!.scheme}'),
          onTap: () => launchUrl(row.contact!),
          child: content,
        ),
      ),
    );
  }
}

class _DocumentAttachments extends StatelessWidget {
  const _DocumentAttachments({required this.item});
  final WarrantyItem item;

  @override
  Widget build(BuildContext context) {
    final attachments = <Widget>[
      if (item.receiptPhotos.isNotEmpty)
        _PhotoAttachment(
          key: const Key('receipt-photo-attachment'),
          title: context.l10n.text('receiptPhotos'),
          paths: item.receiptPhotos,
        ),
      if (item.warrantyPhotos.isNotEmpty)
        _PhotoAttachment(
          key: const Key('warranty-photo-attachment'),
          title: context.l10n.text('warrantyPhotos'),
          paths: item.warrantyPhotos,
        ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      // Long translations and enlarged accessibility text keep their full size.
      if (attachments.length < 2 || constraints.maxWidth < 340 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.2) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < attachments.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              attachments[i],
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: attachments[0]),
          const SizedBox(width: 8),
          Expanded(child: attachments[1]),
        ],
      );
    });
  }
}

class _PhotoAttachment extends StatelessWidget {
  const _PhotoAttachment({super.key, required this.title, required this.paths});
  final String title;
  final List<String> paths;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: title,
    value: '${paths.length}',
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openPhotos(context, paths),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: StoredPhoto(paths.first, width: 44, height: 54, fit: BoxFit.cover),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (paths.length > 1) ...[
                const SizedBox(width: 4),
                Text('${paths.length}', style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _PhotoPreview extends StatefulWidget {
  const _PhotoPreview({required this.paths, required this.initialIndex});
  final List<String> paths;
  final int initialIndex;
  @override
  State<_PhotoPreview> createState() => _PhotoPreviewState();
}

class _PhotoPreviewState extends State<_PhotoPreview> {
  late int index = widget.initialIndex;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text('${index + 1} of ${widget.paths.length}'),
    ),
    body: PageView.builder(
      controller: PageController(initialPage: widget.initialIndex),
      onPageChanged: (value) => setState(() => index = value),
      itemCount: widget.paths.length,
      itemBuilder: (context, i) => Center(
        child: InteractiveViewer(
          minScale: .8,
          maxScale: 5,
          child: Hero(
            tag: widget.paths[i],
            child: StoredPhoto(widget.paths[i], errorColor: Colors.white),
          ),
        ),
      ),
    ),
  );
}


