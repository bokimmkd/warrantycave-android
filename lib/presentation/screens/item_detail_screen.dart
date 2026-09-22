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
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.text('warrantyDetails')),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AddWarrantyScreen(existing: item, onSelectTab: onSelectTab),
              ),
            ),
            icon: const Icon(Icons.edit_outlined),
            tooltip: context.l10n.text('edit'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9F4FC),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child:
                        item.productPhoto != null &&
                            (isCloudPhoto(item.productPhoto!) ||
                                File(item.productPhoto!).existsSync())
                        ? StoredPhoto(item.productPhoto!)
                        : Icon(
                            iconForType(item.productType),
                            size: 38,
                            color: caveBlue,
                          ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    item.productName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: caveNavy,
                    ),
                  ),
                  Text(
                    item.productType,
                    style: const TextStyle(color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 12),
                  StatusChip(
                    item.status(
                      thresholdDays: app.settings.expiringThresholdDays,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    localizedRemainingLabel(context, item),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: caveBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Details(item: item),
          if (item.servicePhone.isNotEmpty || item.serviceEmail.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ServiceContact(item: item),
          ],
          if (item.productPhoto != null) ...[
            const SizedBox(height: 18),
            _PhotoGallery(
              title: context.l10n.text('productPhoto'),
              paths: [item.productPhoto!],
            ),
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
                        color: caveNavy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(item.notes),
                  ],
                ),
              ),
            ),
          ],
          if (item.receiptPhotos.isNotEmpty) ...[
            const SizedBox(height: 18),
            _PhotoGallery(
              title: context.l10n.text('receiptPhotos'),
              paths: item.receiptPhotos,
            ),
          ],
          if (item.warrantyPhotos.isNotEmpty) ...[
            const SizedBox(height: 18),
            _PhotoGallery(
              title: context.l10n.text('warrantyPhotos'),
              paths: item.warrantyPhotos,
            ),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: OutlineButton(
                  label: context.l10n.text('share'),
                  icon: Icons.share_outlined,
                  onPressed: () => _shareText(context, item),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrimaryButton(
                  label: context.l10n.text('claimPack'),
                  icon: Icons.picture_as_pdf_outlined,
                  expand: false,
                  onPressed: () => _claimPack(context, item),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
              context.l10n.locale.languageCode,
            ).format(item.expiryDate),
          }),
        ),
      );
  Future<void> _claimPack(BuildContext context, WarrantyItem item) async {
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
                [context.l10n.text('productType'), item.productType],
                [context.l10n.text('brand'), item.brand],
                [context.l10n.text('model'), item.model],
                [context.l10n.text('serialNumber'), item.serialNumber],
                [context.l10n.text('warrantyStatus'), status],
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
                    context.l10n.locale.languageCode,
                  ).format(item.purchaseDate),
                ],
                [context.l10n.text('warrantyDuration'), item.durationLabel],
                [
                  context.l10n.text('expiryDate'),
                  DateFormat.yMMMd(
                    context.l10n.locale.languageCode,
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
                  context.l10n.locale.languageCode,
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
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: context.l10n.format('claimPackSubject', {
            'product': item.productName,
          }),
        ),
      );
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

class _Details extends StatelessWidget {
  const _Details({required this.item});
  final WarrantyItem item;
  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[
      MapEntry(context.l10n.text('brand'), item.brand),
      MapEntry(context.l10n.text('model'), item.model),
      MapEntry(context.l10n.text('serialNumber'), item.serialNumber),
      MapEntry(context.l10n.text('storeRetailer'), item.store),
      MapEntry(context.l10n.text('authorizedService'), item.authorizedService),
      MapEntry(context.l10n.text('servicePhone'), item.servicePhone),
      MapEntry(context.l10n.text('serviceEmail'), item.serviceEmail),
      MapEntry(context.l10n.text('usedAt'), item.location),
      MapEntry(
        context.l10n.text('purchaseDate'),
        DateFormat.yMMMd(
          context.l10n.locale.languageCode,
        ).format(item.purchaseDate),
      ),
      MapEntry(
        context.l10n.text('purchasePrice'),
        item.purchasePrice == null
            ? ''
            : formatMoney(item.purchasePrice!, item.currency),
      ),
      MapEntry(context.l10n.text('warrantyDuration'), item.durationLabel),
      MapEntry(
        context.l10n.text('expiryDate'),
        DateFormat.yMMMd(
          context.l10n.locale.languageCode,
        ).format(item.expiryDate),
      ),
    ].where((e) => e.value.isNotEmpty);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: rows
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          e.key,
                          style: const TextStyle(color: Colors.blueGrey),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e.value,
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: caveNavy,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _ServiceContact extends StatelessWidget {
  const _ServiceContact({required this.item});
  final WarrantyItem item;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        if (item.servicePhone.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.phone_outlined, color: caveBlue),
            title: Text(
              item.authorizedService.isEmpty
                  ? context.l10n.text('servicePhone')
                  : '${item.authorizedService} · ${context.l10n.text('phone')}',
            ),
            subtitle: Text(item.servicePhone),
            trailing: const Icon(Icons.call_outlined),
            onTap: () => launchUrl(Uri(scheme: 'tel', path: item.servicePhone)),
          ),
        if (item.servicePhone.isNotEmpty && item.serviceEmail.isNotEmpty)
          const Divider(height: 1),
        if (item.serviceEmail.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.email_outlined, color: caveBlue),
            title: Text(
              item.authorizedService.isEmpty
                  ? context.l10n.text('serviceEmail')
                  : '${item.authorizedService} · ${context.l10n.text('email')}',
            ),
            subtitle: Text(item.serviceEmail),
            trailing: const Icon(Icons.send_outlined),
            onTap: () =>
                launchUrl(Uri(scheme: 'mailto', path: item.serviceEmail)),
          ),
      ],
    ),
  );
}

class _PhotoGallery extends StatelessWidget {
  const _PhotoGallery({required this.title, required this.paths});
  final String title;
  final List<String> paths;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: caveNavy,
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 120,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: paths.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) => InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _PhotoPreview(paths: paths, initialIndex: i),
              ),
            ),
            child: Hero(
              tag: paths[i],
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: StoredPhoto(
                  paths[i],
                  width: 105,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
      ),
    ],
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
