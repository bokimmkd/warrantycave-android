import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item_detail_screen.dart';
import 'serial_scanner_screen.dart';
import 'upgrade_screen.dart';

class AddWarrantyScreen extends StatefulWidget {
  const AddWarrantyScreen({
    super.key,
    this.existing,
    this.onSelectTab,
    this.startSmartScan = false,
  });
  final WarrantyItem? existing;
  final ValueChanged<int>? onSelectTab;
  final bool startSmartScan;
  @override
  State<AddWarrantyScreen> createState() => _AddWarrantyScreenState();
}

class _AddWarrantyScreenState extends State<AddWarrantyScreen> {
  final formKey = GlobalKey<FormState>();
  late final String id;
  late final TextEditingController name,
      brand,
      model,
      serial,
      store,
      authorizedService,
      servicePhone,
      serviceEmail,
      price,
      notes;
  String? productType;
  String? productPhoto;
  String currency = 'MKD';
  String location = '';
  DateTime purchaseDate = dateOnly(DateTime.now());
  DateTime expiryDate = addMonthsClamped(dateOnly(DateTime.now()), 12);
  String duration = '1 year';
  int durationMonths = 12;
  bool expiryManuallyEdited = false;
  bool saving = false;
  List<String> receipts = [], warranties = [];
  static const durations = {
    '6 months': 6,
    '1 year': 12,
    '2 years': 24,
    '3 years': 36,
    '4 years': 48,
    '5 years': 60,
  };

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    id = e?.id ?? context.read<AppController>().newId();
    productType = e?.productType;
    purchaseDate = e?.purchaseDate ?? purchaseDate;
    expiryDate = e?.expiryDate ?? expiryDate;
    duration = e?.durationLabel ?? duration;
    durationMonths = durations[duration] ?? 12;
    expiryManuallyEdited =
        e != null &&
        addMonthsClamped(purchaseDate, durationMonths) != expiryDate;
    receipts = [...?e?.receiptPhotos];
    warranties = [...?e?.warrantyPhotos];
    productPhoto = e?.productPhoto;
    currency =
        e?.currency ?? context.read<AppController>().settings.defaultCurrency;
    location = e?.location ?? '';
    name = TextEditingController(text: e?.productName);
    brand = TextEditingController(text: e?.brand);
    model = TextEditingController(text: e?.model);
    serial = TextEditingController(text: e?.serialNumber);
    store = TextEditingController(text: e?.store);
    authorizedService = TextEditingController(text: e?.authorizedService);
    servicePhone = TextEditingController(text: e?.servicePhone);
    serviceEmail = TextEditingController(text: e?.serviceEmail);
    price = TextEditingController(text: e?.purchasePrice?.toStringAsFixed(2));
    notes = TextEditingController(text: e?.notes);
    if (widget.startSmartScan) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) smartScanReceipt();
      });
    }
  }

  @override
  void dispose() {
    for (final c in [
      name,
      brand,
      model,
      serial,
      store,
      authorizedService,
      servicePhone,
      serviceEmail,
      price,
      notes,
    ])
      c.dispose();
    super.dispose();
  }

  void recalculate() {
    if (!expiryManuallyEdited)
      expiryDate = addMonthsClamped(purchaseDate, durationMonths);
  }

  Future<void> pickDate(bool purchase) async {
    final value = await showDatePicker(
      context: context,
      initialDate: purchase ? purchaseDate : expiryDate,
      firstDate: DateTime(1980),
      lastDate: DateTime(2150),
    );
    if (value != null)
      setState(() {
        if (purchase) {
          purchaseDate = value;
          recalculate();
        } else {
          expiryDate = value;
          expiryManuallyEdited = true;
        }
      });
  }

  Future<void> scanSerialNumber() async {
    final app = context.read<AppController>();
    if (!app.settings.plan.hasBarcodeScanner) {
      await AppBottomSheets.show<void>(
        context,
        title: context.l10n.text('scanSerial'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.qr_code_scanner_rounded,
              size: 58,
              color: caveTeal,
            ),
            const SizedBox(height: 14),
            Text(
              context.l10n.text('scannerPaid'),
              textAlign: TextAlign.center,
              style: AppTypography.muted,
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: context.l10n.text('viewPlans'),
              icon: Icons.workspace_premium_outlined,
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UpgradeScreen(
                      onSelectTab: widget.onSelectTab ?? (_) {},
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      );
      return;
    }
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const SerialScannerScreen()),
    );
    if (value != null && mounted) {
      serial.text = value;
      AppSnackbars.success(context, context.l10n.text('serialScanned'));
    }
  }

  Future<void> smartScanReceipt() async {
    final app = context.read<AppController>();
    if (!app.signedIn || !app.emailVerified) {
      AppSnackbars.error(context, context.l10n.text('verifyEmail'));
      return;
    }
    if (app.settings.smartScanCredits < 1) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              UpgradeScreen(onSelectTab: widget.onSelectTab ?? (_) {}),
        ),
      );
      return;
    }
    final source = await _photoSource(context.l10n.text('smartScan'));
    if (source == null || !mounted) return;
    final path = await app.addPhoto(
      itemId: id,
      kind: 'receipts',
      source: source,
    );
    if (path == null || !mounted) return;
    setState(() => receipts.add(path));
    try {
      final suggestion = await app.smartScanReceipt(path);
      if (!mounted) return;
      final apply = await AppBottomSheets.show<bool>(
        context,
        title: context.l10n.text('smartScan'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (suggestion.store?.isNotEmpty ?? false)
              ListTile(
                leading: const Icon(Icons.store_outlined, color: caveBlue),
                title: Text(context.l10n.text('storeRetailer')),
                subtitle: Text(suggestion.store!),
              ),
            if (suggestion.purchaseDate != null)
              ListTile(
                leading: const Icon(
                  Icons.calendar_today_outlined,
                  color: caveBlue,
                ),
                title: Text(context.l10n.text('purchaseDate')),
                subtitle: Text(
                  DateFormat.yMMMd().format(suggestion.purchaseDate!),
                ),
              ),
            if (suggestion.price != null)
              ListTile(
                leading: const Icon(Icons.payments_outlined, color: caveBlue),
                title: Text(context.l10n.text('purchasePrice')),
                subtitle: Text(
                  formatMoney(
                    suggestion.price!,
                    suggestion.currency ?? currency,
                  ),
                ),
              ),
            if (suggestion.serialNumber?.isNotEmpty ?? false)
              ListTile(
                leading: const Icon(Icons.numbers_outlined, color: caveBlue),
                title: Text(context.l10n.text('serialNumber')),
                subtitle: Text(suggestion.serialNumber!),
              ),
            const SizedBox(height: 10),
            PrimaryButton(
              label: context.l10n.text('apply'),
              icon: Icons.check_rounded,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );
      if (apply == true && mounted) {
        setState(() {
          if (suggestion.store?.isNotEmpty ?? false)
            store.text = suggestion.store!;
          if (suggestion.purchaseDate != null) {
            purchaseDate = dateOnly(suggestion.purchaseDate!);
            recalculate();
          }
          if (suggestion.price != null)
            price.text = suggestion.price!.toStringAsFixed(2);
          if (suggestion.currency?.isNotEmpty ?? false)
            currency = suggestion.currency!;
          if (suggestion.serialNumber?.isNotEmpty ?? false)
            serial.text = suggestion.serialNumber!;
          if (suggestion.productName?.isNotEmpty ?? false)
            name.text = suggestion.productName!;
          if (suggestion.brand?.isNotEmpty ?? false)
            brand.text = suggestion.brand!;
          if (suggestion.model?.isNotEmpty ?? false)
            model.text = suggestion.model!;
        });
      }
    } catch (_) {
      if (mounted)
        AppSnackbars.error(context, context.l10n.text('requestFailed'));
    }
  }

  Future<void> chooseType() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: softBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (context) => const _ProductTypeSheet(),
    );
    if (selected != null) setState(() => productType = selected);
  }

  Future<void> chooseDuration() async {
    final value = await AppBottomSheets.show<String>(
      context,
      title: context.l10n.text('warrantyDuration'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...durations.keys.map(
            (value) => ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.medium),
              ),
              tileColor: value == duration
                  ? AppColors.softBlue
                  : Colors.transparent,
              leading: Icon(
                value == duration
                    ? Icons.check_circle_rounded
                    : Icons.schedule_outlined,
                color: value == duration ? caveTeal : caveBlue,
              ),
              title: Text(value),
              onTap: () => Navigator.pop(context, value),
            ),
          ),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            leading: const Icon(Icons.edit_calendar_outlined, color: caveBlue),
            title: Text(context.l10n.text('customDuration')),
            onTap: () => Navigator.pop(context, 'Custom'),
          ),
        ],
      ),
    );
    if (!mounted || value == null) return;
    if (value == 'Custom') {
      final months = await _customMonths(context);
      if (months == null || !mounted) return;
      setState(() {
        durationMonths = months;
        duration = '$months months (custom)';
        recalculate();
      });
      return;
    }
    setState(() {
      duration = value;
      durationMonths = durations[value]!;
      recalculate();
    });
  }

  Future<void> addPhoto(List<String> target, String kind) async {
    final source = await AppBottomSheets.show<ImageSource>(
      context,
      title: context.l10n.text('addDocumentPhoto'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            tileColor: Colors.white,
            leading: const Icon(Icons.camera_alt_outlined, color: caveBlue),
            title: Text(
              context.l10n.text('takePhoto'),
              style: AppTypography.subtitle,
            ),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          const SizedBox(height: 8),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            tileColor: Colors.white,
            leading: const Icon(Icons.photo_library_outlined, color: caveBlue),
            title: Text(
              context.l10n.text('chooseGallery'),
              style: AppTypography.subtitle,
            ),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.text('cancel')),
          ),
        ],
      ),
    );
    if (source == null) return;
    final path = await context.read<AppController>().addPhoto(
      itemId: id,
      kind: kind,
      source: source,
    );
    if (path != null && mounted) {
      setState(() => target.add(path));
      AppSnackbars.success(context, context.l10n.text('photoAdded'));
    }
  }

  Future<void> chooseProductPhoto() async {
    final source = await _photoSource(context.l10n.text('productPhoto'));
    if (source == null || !mounted) return;
    final path = await context.read<AppController>().addPhoto(
      itemId: id,
      kind: 'product',
      source: source,
    );
    if (path != null && mounted) setState(() => productPhoto = path);
  }

  Future<ImageSource?> _photoSource(String title) =>
      AppBottomSheets.show<ImageSource>(
        context,
        title: title,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: caveBlue),
              title: Text(
                context.l10n.text('takePhoto'),
                style: AppTypography.subtitle,
              ),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: caveBlue,
              ),
              title: Text(
                context.l10n.text('chooseGallery'),
                style: AppTypography.subtitle,
              ),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      );

  Future<void> removeProductPhoto() async {
    if (productPhoto == null) return;
    final remove = await AppDialogs.confirm(
      context,
      title: context.l10n.text('deleteProductPhoto'),
      message: context.l10n.text('deleteProductPhotoInfo'),
      confirmLabel: context.l10n.text('delete'),
      danger: true,
      icon: Icons.delete_outline,
    );
    if (remove && mounted) setState(() => productPhoto = null);
  }

  Future<void> chooseCurrency() async {
    final selected = await AppBottomSheets.show<String>(
      context,
      title: context.l10n.text('selectCurrency'),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: supportedCurrencies
            .map(
              (value) => ChoiceChip(
                label: Text(value),
                selected: currency == value,
                onSelected: (_) => Navigator.pop(context, value),
              ),
            )
            .toList(),
      ),
    );
    if (selected != null && mounted) setState(() => currency = selected);
  }

  Future<void> chooseLocation() async {
    const choices = ['Home', 'Vacation home', 'Garage', 'Office'];
    final selected = await AppBottomSheets.show<String>(
      context,
      title: context.l10n.text('itemUsed'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...choices.map(
            (value) => ListTile(
              leading: Icon(
                location == value
                    ? Icons.check_circle
                    : Icons.location_on_outlined,
                color: location == value ? caveTeal : caveBlue,
              ),
              title: Text(value),
              onTap: () => Navigator.pop(context, value),
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.edit_location_alt_outlined,
              color: caveBlue,
            ),
            title: Text(context.l10n.text('otherCustom')),
            onTap: () => Navigator.pop(context, '__custom__'),
          ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    if (selected != '__custom__') {
      setState(() => location = selected);
      return;
    }
    final controller = TextEditingController(
      text: choices.contains(location) ? '' : location,
    );
    final custom = await AppBottomSheets.show<String>(
      context,
      title: context.l10n.text('customLocation'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: context.l10n.text('locationName'),
            ),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: context.l10n.text('saveLocation'),
            icon: Icons.check,
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
          ),
        ],
      ),
    );
    controller.dispose();
    if (custom != null && mounted) setState(() => location = custom);
  }

  Future<void> removePhoto(List<String> target, String path) async {
    final remove = await AppDialogs.confirm(
      context,
      title: context.l10n.text('removePhotoQuestion'),
      message: context.l10n.text('removePhotoInfo'),
      confirmLabel: context.l10n.text('remove'),
      danger: true,
      icon: Icons.delete_outline,
    );
    if (!remove || !mounted) return;
    setState(() => target.remove(path));
    if (mounted)
      AppSnackbars.success(context, context.l10n.text('photoRemoved'));
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate() || productType == null) {
      AppSnackbars.error(
        context,
        productType == null
            ? context.l10n.text('chooseTypeContinue')
            : context.l10n.text('checkRequiredFields'),
      );
      return;
    }
    setState(() => saving = true);
    final value = WarrantyItem(
      id: id,
      productType: productType!,
      productName: name.text.trim(),
      brand: brand.text.trim(),
      model: model.text.trim(),
      serialNumber: serial.text.trim(),
      store: store.text.trim(),
      authorizedService: authorizedService.text.trim(),
      servicePhone: servicePhone.text.trim(),
      serviceEmail: serviceEmail.text.trim(),
      location: location,
      purchasePrice: double.tryParse(price.text.replaceAll(',', '.')),
      currency: currency,
      notes: notes.text.trim(),
      productPhoto: productPhoto,
      purchaseDate: purchaseDate,
      expiryDate: expiryDate,
      durationLabel: duration,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      receiptPhotos: receipts,
      warrantyPhotos: warranties,
    );
    try {
      await context.read<AppController>().upsert(value);
      if (mounted) {
        await AppDialogs.message(
          context,
          title: widget.existing == null
              ? context.l10n.text('warrantySaved')
              : context.l10n.text('warrantyUpdated'),
          message: context.l10n.text('savedSafe'),
          buttonLabel: context.l10n.text('viewItem'),
        );
        if (mounted)
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ItemDetailScreen(
                itemId: value.id,
                onSelectTab: widget.onSelectTab,
              ),
            ),
          );
      }
    } catch (e) {
      if (mounted) AppSnackbars.error(context, context.l10n.text('saveFailed'));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        context.l10n.text(
          widget.existing == null ? 'addWarranty' : 'editWarranty',
        ),
      ),
    ),
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          AppCards(
            onTap: context.watch<AppController>().smartScanBusy
                ? null
                : smartScanReceipt,
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.softBlue,
                  child: Icon(Icons.document_scanner_outlined, color: caveBlue),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.text('smartScan'),
                        style: AppTypography.subtitle,
                      ),
                      Text(
                        context.l10n.text('scanDocument'),
                        style: AppTypography.muted,
                      ),
                    ],
                  ),
                ),
                if (context.watch<AppController>().smartScanBusy)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Column(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: caveTeal),
                      Text(
                        '${context.watch<AppController>().settings.smartScanCredits}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: caveNavy,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _FormHeading(context.l10n.text('product')),
          InkWell(
            onTap: chooseType,
            borderRadius: BorderRadius.circular(14),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: context.l10n.text('productTypeRequired'),
                suffixIcon: const Icon(Icons.keyboard_arrow_down),
              ),
              child: Text(
                productType ?? context.l10n.text('chooseProductType'),
                style: TextStyle(
                  color: productType == null ? Colors.blueGrey : caveNavy,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: name,
            decoration: InputDecoration(
              labelText: context.l10n.text('productNameRequired'),
            ),
            validator: (v) => v == null || v.trim().isEmpty
                ? context.l10n.text('productNameRequiredError')
                : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: brand,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('brand'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: model,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('model'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: serial,
            decoration: InputDecoration(
              labelText: context.l10n.text('serialNumber'),
              suffixIcon: IconButton(
                tooltip: context.l10n.text('scanSerial'),
                onPressed: scanSerialNumber,
                icon: Icon(
                  context.watch<AppController>().settings.plan.hasBarcodeScanner
                      ? Icons.qr_code_scanner_rounded
                      : Icons.lock_outline_rounded,
                  color: caveBlue,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: chooseLocation,
            borderRadius: BorderRadius.circular(AppRadius.medium),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: context.l10n.text('itemUsed'),
                suffixIcon: const Icon(Icons.location_on_outlined),
              ),
              child: Text(
                location.isEmpty
                    ? context.l10n.text('chooseLocationOptional')
                    : location,
                style: TextStyle(
                  color: location.isEmpty ? Colors.blueGrey : caveNavy,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          AppCards(
            onTap: chooseProductPhoto,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: productPhoto == null
                      ? Container(
                          width: 70,
                          height: 70,
                          color: AppColors.softBlue,
                          child: const Icon(
                            Icons.add_a_photo_outlined,
                            color: caveBlue,
                          ),
                        )
                      : StoredPhoto(
                          productPhoto!,
                          width: 70,
                          height: 70,
                          fit: BoxFit.cover,
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.text('productPhoto'),
                        style: AppTypography.subtitle,
                      ),
                      Text(
                        productPhoto == null
                            ? context.l10n.text('takeOrChoosePhoto')
                            : context.l10n.text('tapChangePhoto'),
                        style: AppTypography.muted,
                      ),
                    ],
                  ),
                ),
                if (productPhoto != null)
                  IconButton(
                    tooltip: context.l10n.text('deletePhoto'),
                    onPressed: removeProductPhoto,
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _FormHeading(context.l10n.text('warrantyPeriod')),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: context.l10n.text('purchaseDateRequired'),
                  date: purchaseDate,
                  onTap: () => pickDate(true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: chooseDuration,
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: context.l10n.text('durationRequired'),
                      suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    child: Text(
                      duration,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: caveNavy,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DateField(
            label: context.l10n.text('expiryDateEditable'),
            date: expiryDate,
            onTap: () => pickDate(false),
            helper: context.l10n.text('expiryCalculated'),
          ),
          const SizedBox(height: 22),
          _FormHeading(context.l10n.text('purchaseDetails')),
          TextFormField(
            controller: store,
            decoration: InputDecoration(
              labelText: context.l10n.text('storeRetailer'),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: authorizedService,
            decoration: InputDecoration(
              labelText: context.l10n.text('authorizedService'),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: servicePhone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: context.l10n.text('servicePhone'),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: serviceEmail,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: context.l10n.text('serviceEmail'),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: context.l10n.text('purchasePrice'),
              suffixIcon: Padding(
                padding: const EdgeInsets.all(7),
                child: TextButton(
                  onPressed: chooseCurrency,
                  child: Text(currency),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: notes,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: context.l10n.text('notes'),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 22),
          _PhotoSection(
            title: context.l10n.text('receipt'),
            emptyText: context.l10n.text('noReceipt'),
            actionLabel: context.l10n.text('addReceipt'),
            paths: receipts,
            onAdd: () => addPhoto(receipts, 'receipts'),
            onRemove: (p) => removePhoto(receipts, p),
          ),
          const SizedBox(height: 18),
          _PhotoSection(
            title: context.l10n.text('warrantyDocument'),
            emptyText: context.l10n.text('noWarrantyDocument'),
            actionLabel: context.l10n.text('addWarrantyDocument'),
            paths: warranties,
            onAdd: () => addPhoto(warranties, 'warranty'),
            onRemove: (p) => removePhoto(warranties, p),
          ),
          const SizedBox(height: 26),
          LoadingButton(
            label: widget.existing == null
                ? context.l10n.text('saveWarranty')
                : context.l10n.text('save'),
            onPressed: save,
            loading: saving,
            icon: Icons.save_outlined,
          ),
        ],
      ),
    ),
    bottomNavigationBar: widget.onSelectTab == null
        ? null
        : AppBottomNavigation(
            selectedIndex: 2,
            onSelected: (value) {
              if (value != 2) widget.onSelectTab!(value);
            },
          ),
  );
}

Future<int?> _customMonths(BuildContext context) async {
  final c = TextEditingController();
  final result = await AppBottomSheets.show<int>(
    context,
    title: context.l10n.text('customWarrantyDuration'),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: AppInputFields.decoration(
            label: context.l10n.text('numberMonths'),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlineButton(
                label: context.l10n.text('cancel'),
                icon: Icons.close,
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PrimaryButton(
                label: context.l10n.text('apply'),
                expand: false,
                icon: Icons.check,
                onPressed: () {
                  final n = int.tryParse(c.text);
                  if (n != null && n > 0) Navigator.pop(context, n);
                },
              ),
            ),
          ],
        ),
      ],
    ),
  );
  c.dispose();
  return result;
}

class _FormHeading extends StatelessWidget {
  const _FormHeading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: caveNavy,
      ),
    ),
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
    this.helper,
  });
  final String label;
  final DateTime date;
  final VoidCallback onTap;
  final String? helper;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        suffixIcon: const Icon(Icons.calendar_today_outlined),
      ),
      child: Text(
        DateFormat.yMMMd().format(date),
        style: const TextStyle(color: caveNavy, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.title,
    required this.emptyText,
    required this.actionLabel,
    required this.paths,
    required this.onAdd,
    required this.onRemove,
  });
  final String title;
  final String emptyText;
  final String actionLabel;
  final List<String> paths;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
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
      if (paths.isEmpty)
        SizedBox(
          width: double.infinity,
          child: AppCards(
            child: Column(
              children: [
                Text(
                  emptyText,
                  textAlign: TextAlign.center,
                  style: AppTypography.muted,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(actionLabel),
                ),
              ],
            ),
          ),
        )
      else ...[
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: paths.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: StoredPhoto(
                    paths[i],
                    width: 92,
                    height: 108,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  right: 3,
                  top: 3,
                  child: IconButton.filled(
                    onPressed: () => onRemove(paths[i]),
                    icon: const Icon(Icons.close, size: 16),
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(context.l10n.text('addAnotherPhoto')),
          ),
        ),
      ],
    ],
  );
}

class _ProductTypeSheet extends StatefulWidget {
  const _ProductTypeSheet();
  @override
  State<_ProductTypeSheet> createState() => _ProductTypeSheetState();
}

class _ProductTypeSheetState extends State<_ProductTypeSheet> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final options = productTypes
        .where((e) => e.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    final categories = options.map((e) => e.category).toSet();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            children: [
              Text(
                context.l10n.text('chooseProductType'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: caveNavy,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: context.l10n.text('searchProductTypes'),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  children: [
                    for (final category in categories) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                        child: Text(
                          category.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: caveBlue,
                          ),
                        ),
                      ),
                      ...options
                          .where((e) => e.category == category)
                          .map(
                            (option) => ListTile(
                              leading: Icon(option.icon, color: caveBlue),
                              title: Text(option.name),
                              onTap: () async {
                                if (option.name != 'Custom') {
                                  Navigator.pop(context, option.name);
                                  return;
                                }
                                final c = TextEditingController();
                                final value =
                                    await AppBottomSheets.show<String>(
                                      context,
                                      title: context.l10n.text(
                                        'customProductType',
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TextField(
                                            controller: c,
                                            autofocus: true,
                                            decoration:
                                                AppInputFields.decoration(
                                                  label: context.l10n.text(
                                                    'typeName',
                                                  ),
                                                ),
                                          ),
                                          const SizedBox(height: 16),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlineButton(
                                                  label: context.l10n.text(
                                                    'cancel',
                                                  ),
                                                  icon: Icons.close,
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: PrimaryButton(
                                                  label: context.l10n.text(
                                                    'useType',
                                                  ),
                                                  expand: false,
                                                  icon: Icons.check,
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                        c.text.trim(),
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                c.dispose();
                                if (value != null &&
                                    value.isNotEmpty &&
                                    context.mounted)
                                  Navigator.pop(context, value);
                              },
                            ),
                          ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
